//
//  FilterDataProvider.m
//  LuLu_Plus
//
//  Created by Patrick Wardle on 8/1/20.
//  Copyright (c) 2020 Objective-See. All rights reserved.
//

#import "Rule.h"
#import "Rules.h"
#import "Alerts.h"
#import "consts.h"
#import "GrayList.h"
#import "BlockOrAllowList.h"
#import "utilities.h"
#import "Preferences.h"
#import "XPCUserProto.h"
#import "FilterDataProvider+Private.h"

@implementation FilterDataProvider

@synthesize cache;
@synthesize grayList;

//init
-(id)init
{
    //super
    self = [super init];
    if(nil != self)
    {
        //init cache
        cache = [[NSCache alloc] init];
        
        //set cache limit
        self.cache.countLimit = 2048;
        
        //init gray list
        grayList = [[GrayList alloc] init];
        
        //alloc related flows
        self.relatedFlows = [NSMutableDictionary dictionary];

        //save global handle
        // allows the XPC listener to resume held flows when the client goes away
        provider = self;

        //start timer to reap flows of terminated processes
        // a process can exit while its alert is pending; its paused flows would otherwise be held forever
        __weak typeof(self) weakSelf = self;
        self.reapTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0));
        dispatch_source_set_timer(self.reapTimer, dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC), 60 * NSEC_PER_SEC, 10 * NSEC_PER_SEC);
        dispatch_source_set_event_handler(self.reapTimer, ^{
            [weakSelf reapDeadFlows];
        });
        dispatch_resume(self.reapTimer);
    }

    return self;
}

//start filter
-(void)startFilterWithCompletionHandler:(void (^)(NSError *error))completionHandler {
    
    //rules
    NSMutableArray<NEFilterRule*>* rules = nil;

    //network rules
    NENetworkRule* anyOutboundRule = nil;
    NENetworkRule* loopbackRule4 = nil;
    NENetworkRule* loopbackRule6 = nil;

    //filter settings
    NEFilterSettings* filterSettings = nil;

    //log msg
    os_log_debug(logHandle, "%s", __PRETTY_FUNCTION__);

    //init rules array
    rules = [NSMutableArray array];

    //Rule 1:
    // IPv4 loopback (127.0.0.0/8), any port
    NWHostEndpoint* loopback4 = [NWHostEndpoint endpointWithHostname:@"127.0.0.0" port:@"0"];
    loopbackRule4 = [[NENetworkRule alloc] initWithRemoteNetwork:loopback4
                                                   remotePrefix:8
                                                    localNetwork:nil
                                                     localPrefix:0
                                                        protocol:NENetworkRuleProtocolAny
                                                       direction:NETrafficDirectionOutbound];
    [rules addObject:[[NEFilterRule alloc] initWithNetworkRule:loopbackRule4 action:NEFilterActionFilterData]];

    //Rule 2:
    // IPv6 loopback (::1/128), any port
    NWHostEndpoint* loopback6 = [NWHostEndpoint endpointWithHostname:@"::1" port:@"0"];
    loopbackRule6 = [[NENetworkRule alloc] initWithRemoteNetwork:loopback6
                                                   remotePrefix:128
                                                    localNetwork:nil
                                                     localPrefix:0
                                                        protocol:NENetworkRuleProtocolAny
                                                       direction:NETrafficDirectionOutbound];
    [rules addObject:[[NEFilterRule alloc] initWithNetworkRule:loopbackRule6 action:NEFilterActionFilterData]];

    //Rule 3:
    // any/all outbound traffic (non-loopback)
    anyOutboundRule = [[NENetworkRule alloc] initWithRemoteNetwork:nil
                                                     remotePrefix:0
                                                      localNetwork:nil
                                                       localPrefix:0
                                                          protocol:NENetworkRuleProtocolAny
                                                         direction:NETrafficDirectionOutbound];
    [rules addObject:[[NEFilterRule alloc] initWithNetworkRule:anyOutboundRule action:NEFilterActionFilterData]];

    //Rule 4:
    // any/all inbound traffic
    // note: without this the kernel never asks us about inbound flows
    NENetworkRule* anyInboundRule = [[NENetworkRule alloc] initWithRemoteNetwork:nil
                                                                     remotePrefix:0
                                                                      localNetwork:nil
                                                                       localPrefix:0
                                                                          protocol:NENetworkRuleProtocolAny
                                                                         direction:NETrafficDirectionInbound];
    [rules addObject:[[NEFilterRule alloc] initWithNetworkRule:anyInboundRule action:NEFilterActionFilterData]];

    //init filter settings
    filterSettings = [[NEFilterSettings alloc] initWithRules:rules defaultAction:NEFilterActionAllow];

    //apply rules
    [self applySettings:filterSettings completionHandler:^(NSError * _Nullable error) {

        //log msg
        os_log_debug(logHandle, "'applySettings' completed");

        //error?
        if(nil != error) os_log_error(logHandle, "ERROR: failed to apply filter settings: %@", error.localizedDescription);

        //call completion handler
        completionHandler(error);
    }];

    return;
}

//stop filter
-(void)stopFilterWithReason:(NEProviderStopReason)reason completionHandler:(void (^)(void))completionHandler {
    
    //log msg
    os_log_debug(logHandle, "method '%s' invoked with %ld", __PRETTY_FUNCTION__, (long)reason);
    
    //extra dbg info
    if(NEProviderStopReasonUserInitiated == reason)
    {
        //log msg
        os_log_debug(logHandle, "reason: NEProviderStopReasonUserInitiated");
    }

    //stop the reap timer
    if(nil != self.reapTimer)
    {
        //cancel & release
        dispatch_source_cancel(self.reapTimer);
        self.reapTimer = nil;
    }

    //resume (allow) any still held/paused flows
    [self resumeFlowsForKey:nil verdict:[NEFilterNewFlowVerdict allowVerdict]];

    //required
    completionHandler();
    
    return;
}

//handle flow
-(NEFilterNewFlowVerdict *)handleNewFlow:(NEFilterFlow *)flow {
    
    //socket flow
    NEFilterSocketFlow* socketFlow = nil;
    
    //remote endpoint
    NWHostEndpoint* remoteEndpoint = nil;
    
    //verdict
    NEFilterNewFlowVerdict* verdict = nil;
    
    //how the flow was decided
    FlowVerdict flowVerdict = kFlowVerdictAllow;
    
    //log msg
    os_log_debug(logHandle, "method '%s' invoked", __PRETTY_FUNCTION__);
    
    //init verdict to allow
    verdict = [NEFilterNewFlowVerdict allowVerdict];
    
    //no prefs (yet) or disabled
    // just allow the flow (don't block)
    if( (0 == preferences.preferences.count) ||
        (YES == [preferences.preferences[PREF_IS_DISABLED] boolValue]) )
    {
        //dbg msg
        os_log_debug(logHandle, "no prefs (yet) || disabled, so allowing flow");
        
        //bail
        goto bail;
    }
    
    //typecast
    socketFlow = (NEFilterSocketFlow*)flow;
    
    //log msg
    //os_log_debug(logHandle, "flow: %{public}@", flow);
    
    //extract remote endpoint
    remoteEndpoint = (NWHostEndpoint*)socketFlow.remoteEndpoint;
    
    //log msg
    os_log_debug(logHandle, "remote endpoint: %{public}@ / url: %{public}@", remoteEndpoint, flow.URL);
    
    //inbound traffic (peer -> this mac)?
    // note: decided on its own terms, and deliberately *not* handed to -processEvent:, which
    //       reads a flow as an app reaching out: the same rule set would block inbound traffic
    //       that happens to involve a blocked app, and its alert would describe the peer as
    //       whatever this mac was trying to connect to
    if(NETrafficDirectionInbound == socketFlow.direction)
    {
        //decide it
        flowVerdict = [self processInboundEvent:socketFlow];
    }
    //anything that isn't outbound?
    // ignore it
    else if(NETrafficDirectionOutbound != socketFlow.direction)
    {
        //log msg
        os_log_debug(logHandle, "ignoring unexpected traffic direction: %ld", (long)socketFlow.direction);

        //bail
        goto bail;
    }
    //outbound traffic (this mac -> elsewhere)
    else
    {
        //decide it
        flowVerdict = [self processEvent:flow];
    }

    //turn the flow verdict into the extension's verdict
    // note: shared by both directions, so a held/paused inbound flow behaves exactly like a
    //       paused outbound one - only the deciding method above differs
    switch(flowVerdict) {

        //allow
        case kFlowVerdictAllow:
            os_log_debug(logHandle, "verdict: allow");
            verdict = [NEFilterNewFlowVerdict allowVerdict];
            break;

        //block
        case kFlowVerdictBlock:
            os_log_debug(logHandle, "verdict: block");
            verdict = [NEFilterNewFlowVerdict dropVerdict];
            break;

        //pause
        case kFlowVerdictPause:
            os_log_debug(logHandle, "verdict: pause");
            verdict = [NEFilterNewFlowVerdict pauseVerdict];
            break;

        //related
        // pause & save
        case kFlowVerdictRelated:
        {
            os_log_debug(logHandle, "verdict: related");

            //who owns the flow?
            // note: -processInboundEvent:/-processEvent: only report 'related' once a process
            //       object exists, but the alert could have been answered in between
            Process* process = [self.cache objectForKey:flow.sourceAppAuditToken];
            if(nil != process)
            {
                //hold it behind the alert that's still on screen
                verdict = [self holdRelatedFlow:socketFlow key:process.key];
            }
            //no process
            // just allow
            else
            {
                verdict = [NEFilterNewFlowVerdict allowVerdict];
            }

            break;
        }
    }
    
    //log msg
    os_log_debug(logHandle, "verdict: %{public}@", verdict);
    
bail:
        
    return verdict;
}

//hold a flow that arrived while an alert for the same process is still on screen
// note: it's not paused yet (no verdict has been returned), so 'processRelatedFlow:' can't resume
//       it - if the alert was answered (and the queue drained) while this flow was being decided,
//       pull it back out and re-decide it, otherwise it would sit paused with nothing left to drain it
-(NEFilterNewFlowVerdict*)holdRelatedFlow:(NEFilterSocketFlow*)flow key:(NSString*)key
{
    //flag
    BOOL held = NO;

    //save as related flow
    [self addRelatedFlow:key flow:flow];

    //alert answered in the meantime?
    if(YES != [alerts isRelatedKey:key])
    {
        //pull from queue
        // unless something else already grabbed it
        @synchronized(self.relatedFlows)
        {
            held = [self.relatedFlows[key] containsObject:flow];
            if(YES == held) [self removeRelatedFlow:flow forKey:key];
        }

        //re-evaluate
        if(YES == held) return [self handleNewFlow:flow];
    }

    //pause
    return [NEFilterNewFlowVerdict pauseVerdict];
}

//1. Create and deliver alert
//2. Handle response (and process other shown alerts, etc.)
-(void)alert:(NEFilterSocketFlow*)flow process:(Process*)process
{
    //alert
    NSMutableDictionary* alert = nil;

    //rule
    __block Rule* rule = nil;

    //create alert
    alert = [alerts create:(NEFilterSocketFlow*)flow process:process];

    //dbg msg
    os_log_debug(logHandle, "created alert...");

    //weak refs to break retain cycle:
    // block → self → context → _socketFlows → flow → savedMessageHandler → block
    // (weakFlow is only used for the 'once' case, to resume the specific alerted flow)
    __weak typeof(self) weakSelf = self;
    __weak NEFilterSocketFlow* weakFlow = flow;

    //(process) key
    // captured, as a failed delivery has no (user) response to pull it from
    NSString* key = alert[KEY_KEY];

    //save as shown
    // needed so related (same process!) alerts aren't delivered as well
    // note: done *before* delivery, so a client disconnect/XPC error that lands right after delivery
    //       finds (and cleans up) this state ...otherwise the alert stays 'shown' forever, w/ no one to answer it
    [alerts addShown:alert];

    //track the primary (paused) flow alongside related flows
    // so it's resumed on reply (via processRelatedFlow), reaped if the process dies, or released on disconnect
    [self addRelatedFlow:key flow:flow];

    //deliver alert
    // and process user response
    if(YES != [alerts deliver:alert reply:^(NSDictionary* alert)
    {
        //re-strengthen to avoid races within the block
        __strong typeof(weakSelf) strongSelf = weakSelf;
        __strong NEFilterSocketFlow* strongFlow = weakFlow;

        //no response?
        // (async) XPC error, e.g. client went away, or dropped the reply
        if(nil == alert)
        {
            //handle
            [strongSelf alertFailed:key];
            return;
        }

        //log msg
        // note, this msg persists in log
        os_log(logHandle, "(user) response: \"%@\" for %{public}@, that was trying to connect to %{public}@:%{public}@", (RULE_STATE_BLOCK == [alert[KEY_ACTION] unsignedIntValue]) ? @"block" : @"allow", alert[KEY_PATH], alert[KEY_ENDPOINT_ADDR], alert[KEY_ENDPOINT_PORT]);

        //'once'? no rule created
        // apply the user's verdict to just this (alerted) flow; the next flow will re-prompt
        if(RuleDurationOnce == [alert[KEY_DURATION] intValue])
        {
            //dbg msg
            os_log_debug(logHandle, "'once' response, so just handling here ...no rule will be created");
            
            //verdict from user's action
            NEFilterNewFlowVerdict* verdict = (RULE_STATE_BLOCK == [alert[KEY_ACTION] unsignedIntValue])
                ? [NEFilterNewFlowVerdict dropVerdict]
                : [NEFilterNewFlowVerdict allowVerdict];

            //resume this (alerted) flow, & pull it from the queue so it isn't re-processed below
            [strongSelf resumeFlow:strongFlow withVerdict:verdict];
            [strongSelf removeRelatedFlow:strongFlow forKey:alert[KEY_KEY]];
        }
        //otherwise create a rule (from user's response)
        else
        {
            //init rule
            rule = [[Rule alloc] init:alert];

            //add / save
            [rules add:rule save:![rule isTemporary]];

            //tell user rules changed
            [alerts.xpcUserClient rulesChanged];
        }

        //remove from 'shown'
        [alerts removeShown:alert[KEY_KEY]];

        //process remaining paused flows for this process
        // rule path: each re-evaluates against the new rule & is resumed
        // 'once' path: the next flow finds no rule -> generates its own alert
        [strongSelf processRelatedFlow:alert[KEY_KEY]];
    }])
    {
        //failed to deliver
        [self alertFailed:key];
    }

    return;
}

//alert wasn't delivered (or its response was lost)
// un-'show' it & allow all held flows for the process (the alerted flow is tracked as related, so it's included)
// note: safe to run alongside the XPC invalidation handler's cleanup, as 'resumeFlowsForKey:' drops the key under the lock
-(void)alertFailed:(NSString*)key
{
    //dbg msg
    os_log_debug(logHandle, "alert for %{public}@ wasn't delivered/answered, cleaning up", key);

    //remove from 'shown'
    [alerts removeShown:key];

    //allow (& release) all held flows
    [self resumeFlowsForKey:key verdict:[NEFilterNewFlowVerdict allowVerdict]];

    return;
}


//add an alert to 'related'
// invoked when there is already an alert shown for process
// once user responds to alert, these will then be processed
-(void)addRelatedFlow:(NSString*)key flow:(NEFilterSocketFlow*)flow
{
    //dbg msg
    os_log_debug(logHandle, "adding flow to 'related': %{public}@ / %{public}@", key, flow);
    
    if(!key) {
        return;
    }
    
    //sync/save
    @synchronized(self.relatedFlows)
    {
        //first time
        // init (ordered) set for item (process) flows
        if(!self.relatedFlows[key]) {
            self.relatedFlows[key] = [NSMutableOrderedSet orderedSet];
        }

        //add
        [self.relatedFlows[key] addObject:flow];
    }

    return;
}

//process any related flows
-(void)processRelatedFlow:(NSString*)key
{
    //dbg msg
    @synchronized(self.relatedFlows) {
        os_log_debug(logHandle, "processing %lu related flow(s) for %{public}@", (unsigned long)[self.relatedFlows[key] count], key);
    }

    while(YES)
    {
        NEFilterSocketFlow* flow = nil;

        //dequeue one flow
        @synchronized(self.relatedFlows) {
            
            NSMutableOrderedSet* queue = self.relatedFlows[key];
            
            //done?
            if(!queue.count) {
                os_log_debug(logHandle, "drained (processed) all related flows");
                [self.relatedFlows removeObjectForKey:key];
                break;
            }
            
            flow = queue.firstObject;
            [queue removeObjectAtIndex:0];
        }

        //process
        // note: inbound flows are decided by -processInboundEvent:, so a queued inbound flow is
        //       re-decided on its own terms once the alert is answered
        FlowVerdict flowVerdict = (NETrafficDirectionInbound == flow.direction)
                                    ? [self processInboundEvent:flow]
                                    : [self processEvent:flow];

        //(still) related?
        // (re)add and be done for now
        if(flowVerdict == kFlowVerdictRelated) {
            os_log_debug(logHandle, "flow is (still) related");
            [self addRelatedFlow:key flow:flow];
            break;
        }
        
        //paused (asked user)
        // asked user, so be done for now too
        else if(flowVerdict == kFlowVerdictPause) {
            os_log_debug(logHandle, "flow is paused");
            break;
        }
        
        //resume flow
        NEFilterNewFlowVerdict* verdict = (flowVerdict == kFlowVerdictBlock)
            ? [NEFilterNewFlowVerdict dropVerdict]
            : [NEFilterNewFlowVerdict allowVerdict];
        
    
        os_log_debug(logHandle, "resuming related flow with %{public}@", verdict);

        [self resumeFlow:flow withVerdict:verdict];
    }
    
    os_log_debug(logHandle, "done processing related flows");
}

//resume flows + drop their key(s)
// pass a (process) key to resume just that one; pass nil to resume all keys
-(void)resumeFlowsForKey:(NSString*)key verdict:(NEFilterNewFlowVerdict*)verdict
{
    //sync
    @synchronized(self.relatedFlows)
    {
        //one key, or all keys (nil)
        NSArray* keys = (nil != key) ? @[key] : self.relatedFlows.allKeys;
        for(NSString* k in keys)
        {
            //resume each held flow, then drop the key
            for(NEFilterSocketFlow* flow in self.relatedFlows[k])
            {
                [self resumeFlow:flow withVerdict:verdict];
            }
            [self.relatedFlows removeObjectForKey:k];
        }
    }

    return;
}

//remove a single (specific) flow from a key's queue
// (e.g. an 'allow/block once' flow that was resumed directly)
-(void)removeRelatedFlow:(NEFilterSocketFlow*)flow forKey:(NSString*)key
{
    //sync
    @synchronized(self.relatedFlows)
    {
        //remove the flow
        [self.relatedFlows[key] removeObject:flow];

        //drop the key if now empty
        if(0 == [self.relatedFlows[key] count])
        {
            [self.relatedFlows removeObjectForKey:key];
        }
    }

    return;
}

//reap artifacts of terminated processes
// 1. paused flows held for a process that exited (would otherwise be held/leaked forever)
// 2. temporary ('while process runs') rules whose process exited, plus any expired rules
-(void)reapDeadFlows
{
    //dbg msg
    os_log_debug(logHandle, "cleaning up flows from terminated processes...");

    //sync
    @synchronized(self.relatedFlows)
    {
        //note: iterating a snapshot (allKeys), so safe to mutate the dict in the loop
        for(NSString* key in self.relatedFlows.allKeys)
        {
            //pid via the flow's (kernel) audit token; all flows for a key share the process
            NEFilterSocketFlow* flow = [self.relatedFlows[key] firstObject];
            if(nil == flow) continue;
            pid_t pid = audit_token_to_pid(*(audit_token_t*)flow.sourceAppAuditToken.bytes);

            //process still alive?
            // leave its flows be (still awaiting a verdict)
            if((0 != pid) &&
               (YES == isAlive(pid)))
            {
                continue;
            }

            //process exited, but flow was created on its behalf by a (still running) delegate?
            // then its flows were evaluated (& are held) as that delegate ...so leave them be too
            if(nil != [self delegateToken:flow])
            {
                continue;
            }

            //process is gone
            // drop all its held flows, then clear its (now-stale) alert state
            os_log_debug(logHandle, "process %d (key: %{public}@) has exited; reaping its flows", pid, key);
            [self resumeFlowsForKey:key verdict:[NEFilterNewFlowVerdict dropVerdict]];
            [alerts removeShown:key];
        }

        //dbg msg
        os_log_debug(logHandle, "related flows remaining: %lu key(s)", (unsigned long)self.relatedFlows.count);
    }

    //also clean up rules whose process has exited (temp/process rules) or that have expired
    // note: cleanup persists to disk; notify the UI if anything was removed (temp rules show in the rules window)
    if(0 != [rules cleanup:NO])
    {
        //rules changed
        [alerts.xpcUserClient rulesChanged];
    }

    return;
}

//get (audit) token of the process that created a flow on behalf of the flow's (source) app
// e.g. mDNSResponder resolving a name for an app: the flow is attributed to the app, but the socket is mDNSResponder's
// note: only returned if it differs from the app's token & that process is still alive ...and only available on macOS 13+
-(NSData*)delegateToken:(NEFilterFlow*)flow
{
    //token
    NSData* token = nil;

    //pid
    pid_t pid = 0;

    //grab token
    // macOS 13+ only
    if(@available(macOS 13.0, *))
    {
        //grab
        token = flow.sourceProcessAuditToken;
    }

    //sanity check
    if(sizeof(audit_token_t) != token.length)
    {
        //bail
        return nil;
    }

    //same as app's token?
    // not a delegated flow
    if(YES == [token isEqualToData:flow.sourceAppAuditToken])
    {
        //bail
        return nil;
    }

    //extract pid
    pid = audit_token_to_pid(*(audit_token_t*)token.bytes);

    //kernel, or exited?
    if( (0 == pid) ||
        (YES != isAlive(pid)) )
    {
        //bail
        return nil;
    }

    return token;
}

//create (or lookup) process object for the delegate that created a flow (see 'delegateToken:')
// used when the flow's app has exited: the socket belongs to the delegate (e.g. mDNSResponder), so the flow is evaluated as it
// note: cached under both the delegate's token & the flow's (app) token, so later lookups via the flow find the delegate, not the dead app
-(Process*)delegateProcess:(NEFilterFlow*)flow
{
    //delegate's token
    NSData* token = nil;

    //process obj
    Process* process = nil;

    //grab delegate's token
    // nil if flow wasn't delegated, or delegate is gone too
    token = [self delegateToken:flow];
    if(nil == token)
    {
        //bail
        goto bail;
    }

    //check cache
    // keyed by delegate's token, which is shared by all flows it creates
    process = [self.cache objectForKey:token];
    if(nil == process)
    {
        //create
        process = [[Process alloc] init:(audit_token_t*)token.bytes];
        if(nil == process)
        {
            //err msg
            os_log_error(logHandle, "ERROR: failed to create process for delegate %d", audit_token_to_pid(*(audit_token_t*)token.bytes));

            //bail
            goto bail;
        }
    }

    //log msg
    os_log(logHandle, "process %d has exited, but flow was created on its behalf by %{public}@ (pid: %d), so evaluating as that: %{public}@", audit_token_to_pid(*(audit_token_t*)flow.sourceAppAuditToken.bytes), process.path, process.pid, ((NEFilterSocketFlow*)flow).remoteEndpoint);

    //sync to add to cache
    @synchronized(self.cache) {

        //add to cache
        // under both the delegate's token & the flow's (app) token
        [self.cache setObject:process forKey:token];
        [self.cache setObject:process forKey:flow.sourceAppAuditToken];
    }

bail:

    return process;
}

//create process object
-(Process*)createProcess:(NEFilterFlow*)flow
{
    //audit token
    audit_token_t* token = NULL;
    
    //process obj
    Process* process = nil;
    
    //extract (audit) token
    token = (audit_token_t*)flow.sourceAppAuditToken.bytes;
    
    //init process object, via audit token
    process = [[Process alloc] init:token];
    if(nil == process)
    {
        //err msg
        os_log_error(logHandle, "ERROR: failed to create process for %d", audit_token_to_pid(*token));
        
        //bail
        goto bail;
    }
    
    //sync to add to cache
    @synchronized(self.cache) {
        
        //add to cache
        [self.cache setObject:process forKey:flow.sourceAppAuditToken];
    }
    
bail:
    
    return process;
}

//get best hostname from flow
// prioritizes domain names over IP addresses
// uses same logic as active mode rule matching
-(NSString*)getBestHostnameFromFlow:(NEFilterSocketFlow*)flow
{
    //best hostname
    NSString* bestHostname = nil;
    
    //remote endpoint
    NWHostEndpoint* remoteEndpoint = nil;
    
    //extract remote endpoint
    remoteEndpoint = (NWHostEndpoint*)flow.remoteEndpoint;
    
    //priority 1: try flow.URL.host (best for domain names)
    if(flow.URL.host.length)
    {
        //dbg msg
        os_log_debug(logHandle, "using flow.URL.host as best hostname: %{public}@", flow.URL.host);
        
        //use it
        bestHostname = flow.URL.host;
        
        //done
        goto bail;
    }
    
    //priority 2: try flow.remoteHostname (macOS 11+)
    if(@available(macOS 11, *))
    {
        if(flow.remoteHostname.length)
        {
            //dbg msg
            os_log_debug(logHandle, "using flow.remoteHostname as best hostname: %{public}@", flow.remoteHostname);
            
            //use it
            bestHostname = flow.remoteHostname;
            
            //done
            goto bail;
        }
    }
    
    //priority 3: fallback to remoteEndpoint.hostname (may be IP address)
    if(remoteEndpoint.hostname.length)
    {
        //dbg msg
        os_log_debug(logHandle, "using remoteEndpoint.hostname as fallback hostname: %{public}@", remoteEndpoint.hostname);
        
        //use it
        bestHostname = remoteEndpoint.hostname;
    }
    
bail:
    
    //dbg msg
    os_log_debug(logHandle, "best hostname for flow: %{public}@", bestHostname);
    
    return bestHostname;
}

//check if hostname is a valid localhost address
-(BOOL)isLocalhostHostname:(NSString*)hostname {
    
    struct sockaddr_in sa4 = {0};
    struct sockaddr_in6 sa6 = {0};
    
    //sanity check
    if(!hostname.length) {
        return NO;
    }
    
    //exact matches for localhost or IPv6 loopback
    if([hostname isEqualToString:@"::1"] ||
       [hostname isEqualToString:@"localhost"]) {
        return YES;
    }
    
    //check for valid IPv4 loopback range (127.0.0.0/8)
    if(inet_pton(AF_INET, hostname.UTF8String, &(sa4.sin_addr)) == 1) {
        return IN_LOOPBACK(ntohl(sa4.sin_addr.s_addr));
    }
    
    //check for valid IPv6 loopback (::1)
    if(inet_pton(AF_INET6, [hostname UTF8String], &(sa6.sin6_addr)) == 1) {
        return IN6_IS_ADDR_LOOPBACK(&sa6.sin6_addr);
    }
    
    //not a valid localhost address
    return NO;
}

@end
