//
//  file: FilterDataProvider+Inbound.m
//  project: LuLu_Plus
//  description: the inbound half of FilterDataProvider: a flow with no process behind it, and a flow arriving at a listening socket
//
//  copyright (c) 2026 LuLu_Plus. All rights reserved.
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

@implementation FilterDataProvider (Inbound)

//no user/client to show an alert to
// allow the flow, but create a (passive) rule so the user can review it later
// note: used by every alert-requiring path, so a flow is never left paused w/ no one to answer
-(FlowVerdict)allowNoClient:(Process*)process
{
    //rule info
    NSMutableDictionary* info = nil;

    //dbg msg
    os_log_debug(logHandle, "no active user or no connected client, will allow (and create rule)...");

    //init info for (passive allow) rule
    info = [@{KEY_PATH:process.path, KEY_ACTION:@RULE_STATE_ALLOW, KEY_TYPE:@RULE_TYPE_PASSIVE} mutableCopy];

    //add process cs info?
    if(nil != process.csInfo) info[KEY_CS_INFO] = process.csInfo;

    //create and add rule
    // note: no 'rulesChanged' broadcast — there's no connected client to receive it;
    //       the rule is saved and picked up when the client (re)connects & fetches rules
    if(YES != [rules add:[[Rule alloc] init:info] save:YES])
    {
        //err msg
        os_log_error(logHandle, "ERROR: failed to add rule for %{public}@", info[KEY_PATH]);
    }

    return kFlowVerdictAllow;
}

//decide an inbound (peer -> this mac) flow
// note: the extremes are silent by design - 'permissive' allows everything, 'lockdown' blocks
//       everything, and neither consults the rules nor the user. in between, the flow's rule
//       decides and, when there is none, the user is asked (as outbound does), so who is reaching
//       in doesn't get decided behind their back
-(FlowVerdict)processInboundEvent:(NEFilterSocketFlow*)flow
{
    //how should unruled inbound traffic be treated?
    SecurityMode mode = [preferences getSecurityMode];

    //process listening on the other end
    Process* process = nil;

    //matching rule
    Rule* rule = nil;

    //console user
    NSString* consoleUser = nil;

    //is there anyone to ask?
    BOOL canAlert = NO;

    //default to allow
    FlowVerdict verdict = kFlowVerdictAllow;

    //dbg msg
    os_log_debug(logHandle, "inbound flow: %{public}@ -> %{public}@ (mode: %ld)", flow.remoteEndpoint, flow.localEndpoint, (long)mode);

    //at the extremes the rule set (and the user) don't get a say
    if(SecurityModePermissive == mode) goto bail;
    if(SecurityModeLockdown == mode) { verdict = kFlowVerdictBlock; goto bail; }

    //who owns the socket?
    // note: same resolution the outbound path uses, minus the parts that only make sense there
    if(sizeof(audit_token_t) == flow.sourceAppAuditToken.length)
    {
        pid_t pid = audit_token_to_pid(*(audit_token_t*)flow.sourceAppAuditToken.bytes);

        if(0 != pid)
        {
            //cached?
            process = [self.cache objectForKey:flow.sourceAppAuditToken];
            if(nil == process) process = [self createProcess:flow];
        }
    }

    //can't tell who's being connected to?
    // ...there is nothing to prompt about, and no rule can be keyed on an unknown process
    if(nil == process)
    {
        //dbg msg
        os_log_debug(logHandle, "no process for inbound flow, applying mode default");
        goto modeDefault;
    }

    //inbound rules
    // note: -find: only returns rules scoped to this flow's direction, so an outbound-only rule
    //       can't decide an inbound connection
    rule = [rules find:process flow:flow];
    if(nil != rule)
    {
        //allow or block, as the rule says
        verdict = (RULE_STATE_ALLOW == rule.action.intValue) ? kFlowVerdictAllow : kFlowVerdictBlock;

        //log what we did
        if(kFlowVerdictBlock == verdict)
        {
            os_log(logHandle, "blocked inbound flow to %{public}@ from %{public}@ (rule: %{public}@)", process.path, flow.remoteEndpoint, rule);
        }

        goto bail;
    }

    //dbg msg
    os_log_debug(logHandle, "no inbound rule for %{public}@ <- %{public}@", process.path, flow.remoteEndpoint);

    //no rule? ask the user, unless there's no one to answer
    // note: passive mode means 'don't prompt me', and a paused flow with no client attached is
    //       just a hang ...both fall back to the mode's default
    consoleUser = getConsoleUser();

    canAlert = ( (YES != [preferences.preferences[PREF_PASSIVE_MODE] boolValue]) &&
                 (nil != consoleUser) &&
                 (YES == [alerts.xpcUserClient isConnected]) &&
                 // a different user at the console than the one alerts go to? don't prompt
                 ( (nil == alerts.consoleUser) || (YES == [alerts.consoleUser isEqualToString:consoleUser]) ) );

    if(NO == canAlert)
    {
        //dbg msg
        os_log_debug(logHandle, "no one to ask about this inbound flow (passive mode, or no user/client), applying mode default");
        goto modeDefault;
    }

    //an alert for this process is already on screen?
    // hold this flow behind it, to be decided once the user answers
    if(YES == [alerts isRelated:process])
    {
        //dbg msg
        os_log_debug(logHandle, "an alert is shown for %d/%{public}@, so holding off delivering the inbound one for now...", process.pid, process.path);

        verdict = kFlowVerdictRelated;
        goto bail;
    }

    //pause, and let the user decide
    // note: the alert carries the direction, so the user's answer creates an *inbound* rule, and
    //       the next peer to reach this port is settled by that rule instead of a second prompt
    verdict = kFlowVerdictPause;
    [self alert:flow process:process];

    goto bail;

modeDefault:

    //normal allows what no rule covers, strict blocks it
    verdict = (SecurityModeStrict == mode) ? kFlowVerdictBlock : kFlowVerdictAllow;

bail:

    return verdict;
}

@end
