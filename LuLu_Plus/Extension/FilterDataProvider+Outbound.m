//
//  file: FilterDataProvider+Outbound.m
//  project: LuLu_Plus
//  description: the outbound half of FilterDataProvider: deciding a flow leaving the machine
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

@implementation FilterDataProvider (Outbound)

//process a network out event from the network extension (OS)
// if there is no matching rule, will tell client to show alert
-(FlowVerdict)processEvent:(NEFilterFlow*)flow {

    //process obj
    Process* process = nil;
    
    //matching rule obj
    Rule* matchingRule = nil;
    
    //console user
    NSString* consoleUser = nil;
    
    //rule info
    NSMutableDictionary* info = nil;
    
    //default to allow (on errors, etc)
    FlowVerdict verdict = kFlowVerdictAllow;
    
    //(ext) install date
    static NSDate* installDate = nil;
    
    //token
    static dispatch_once_t onceToken = 0;
    
    //grab console user
    consoleUser = getConsoleUser();

    //pid
    // extracted from flow's audit token
    pid_t pid = 0;

    //extract pid
    // note: 'audit_token_to_pid' is just a field accessor (can't fail), so only call it on a well-formed token
    if(sizeof(audit_token_t) == flow.sourceAppAuditToken.length)
    {
        //extract
        pid = audit_token_to_pid(*(audit_token_t*)flow.sourceAppAuditToken.bytes);
    }

    //CHECK:
    // kernel (pid: 0) flow ...allow
    if(0 == pid)
    {
        //log msg
        os_log(logHandle, "flow originated from kernel (pid: 0), allowing: %{public}@", ((NEFilterSocketFlow*)flow).remoteEndpoint);

        //bail
        goto bail;
    }

    //CHECK:
    // process already exited (or zombie'd)?
    // ...unless the flow was created on its behalf by a (still running) system process, e.g. mDNSResponder (see #920)
    //    the socket belongs to that process & outlives the app, so evaluate the flow as it ...otherwise, deny
    if(YES != isAlive(pid))
    {
        //evaluate as delegate (if any)
        process = [self delegateProcess:flow];
        if(nil == process)
        {
            //dbg msg
            os_log_debug(logHandle, "process %d has exited, DENYING flow", pid);

            //block
            verdict = kFlowVerdictBlock;
            goto bail;
        }
    }

    //process is alive
    // lookup in cache, or create
    else
    {
        //check cache for process
        process = [self.cache objectForKey:flow.sourceAppAuditToken];
        if(!process) {

            os_log_debug(logHandle, "no process found in cache, will create");

            //create
            // also adds to cache
            process = [self createProcess:flow];
        }

        //in cache
        else
        {
            //dbg msg
            os_log_debug(logHandle, "found process object in cache: %{public}@ (pid: %d)", process.path, process.pid);
        }
    }

    //sanity check
    // couldn't create process obj?
    if(nil == process)
    {
        //process exited mid-lookup?
        // again, evaluate as its delegate (if any), otherwise deny
        if(YES != isAlive(pid))
        {
            //evaluate as delegate (if any)
            process = [self delegateProcess:flow];
            if(nil == process)
            {
                //dbg msg
                os_log_debug(logHandle, "process %d exited during lookup, DENYING flow", pid);

                //block
                verdict = kFlowVerdictBlock;
                goto bail;
            }
        }

        //process is alive, but still couldn't be examined ...fail open
        else
        {
            //err msg
            os_log_error(logHandle, "ERROR: failed to create process for flow (pid: %d), will allow: %{public}@", pid, ((NEFilterSocketFlow*)flow).remoteEndpoint);

            //bail
            goto bail;
        }
    }
        
    //CHECK:
    // different logged in user?
    // just allow flow, as we don't want to block their traffic
    if( (nil != consoleUser) && (nil != alerts.consoleUser) &&
        (YES != [alerts.consoleUser isEqualToString:consoleUser]) )
    {
        //dbg msg
        os_log_debug(logHandle, "current console user '%{public}@', is different than '%{public}@', so allowing flow: %{public}@", consoleUser, alerts.consoleUser, ((NEFilterSocketFlow*)flow).remoteEndpoint);
        
        //all set
        goto bail;
    }
    
    //CHECK:
    // client in (full) block mode? ...block!
    // unless there is an allow list set, which we'll check
    if(YES == [preferences.preferences[PREF_BLOCK_MODE] boolValue])
    {
        //but allow list set?
        if( (YES == [preferences.preferences[PREF_USE_ALLOW_LIST] boolValue]) &&
            (YES == [allowList isMatch:(NEFilterSocketFlow*)flow]) )
        {
            //dbg msg
            os_log_debug(logHandle, "client in block mode, but flow matches item in allow list, so allowing");
                
            //allow
            verdict = kFlowVerdictAllow;
                
            //all set
            goto bail;
        }
        
        //dbg msg
        os_log_debug(logHandle, "client in block mode (and item not on allow list), so disallowing %d/%{public}@", process.pid, process.binary.name);
        
        //deny
        verdict = kFlowVerdictBlock;
        
        //all set
        goto bail;
    }
        
    //CHECK:
    // client using (global) block list
    if( (YES == [preferences.preferences[PREF_USE_BLOCK_LIST] boolValue]) &&
        (0 != [preferences.preferences[PREF_BLOCK_LIST] length]) )
    {
        //dbg msg
        os_log_debug(logHandle, "client is using block list '%{public}@' (%lu items) ...will check for match", preferences.preferences[PREF_BLOCK_LIST], (unsigned long)blockList.items.count);
        
        //match in block list?
        if(YES == [blockList isMatch:(NEFilterSocketFlow*)flow])
        {
            //dbg msg
            os_log_debug(logHandle, "flow matches item in block list, so denying");
            
            //deny
            verdict = kFlowVerdictBlock;
            
            //all set
            goto bail;
        }
        //dbg msg
        else os_log_debug(logHandle, "remote endpoint/URL not on block list...");
    }
    
    //CHECK:
    // client using (global) allow list
    if( (YES == [preferences.preferences[PREF_USE_ALLOW_LIST] boolValue]) &&
        (0 != [preferences.preferences[PREF_ALLOW_LIST] length]) )
    {
        //dbg msg
        os_log_debug(logHandle, "client is using allow list '%{public}@' (%lu items) ...will check for match", preferences.preferences[PREF_ALLOW_LIST], (unsigned long)allowList.items.count);
        
        //match in allow list?
        if(YES == [allowList isMatch:(NEFilterSocketFlow*)flow])
        {
            //dbg msg
            os_log_debug(logHandle, "flow matches item in allow list, so allowing");
            
            //allow
            verdict = kFlowVerdictAllow;
            
            //all set
            goto bail;
        }
        
        //dbg msg
        else os_log_debug(logHandle, "remote endpoint/URL not on allow list...");
    }
    
    //CHECK:
    // allow localhost enabled?
    if([preferences.preferences[PREF_ALLOW_LOCALHOST] boolValue])
    {
        NEFilterSocketFlow* socketFlow = (NEFilterSocketFlow*)flow;
        NWHostEndpoint* remoteEndpoint = (NWHostEndpoint*)socketFlow.remoteEndpoint;
        
        //localhost?
        if([self isLocalhostHostname:remoteEndpoint.hostname]) {
            
            os_log_debug(logHandle, "localhost allowed (preferences), so allowing loopback to %{public}@", remoteEndpoint);
            
            //allow
            verdict = kFlowVerdictAllow;
            
            //all set
            goto bail;
        }
    }
    
    //CHECK:
    // check for existing rule
    
    //existing rule for process?
    matchingRule = [rules find:process flow:(NEFilterSocketFlow*)flow];
    if(nil != matchingRule)
    {
        //dbg msg
        os_log_debug(logHandle, "found matching rule for %d/%{public}@: %{public}@", process.pid, process.binary.name, matchingRule);
        
        //matching rule !global/!directory?
        // add its 'external' path (as might be different than original)
        if( (YES != matchingRule.isGlobal.boolValue) &&
            (YES != matchingRule.isDirectory.boolValue) )
        {
            //add path
            if(nil != process.path)
            {
                //add (synchronized accessor)
                [rules addPath:process.path forKey:process.key];
            }
        }
        
        //deny?
        // otherwise will default to allow
        if(RULE_STATE_BLOCK == matchingRule.action.intValue)
        {
            //dbg msg
            os_log_debug(logHandle, "setting verdict to: BLOCK");
            
            //deny
            verdict = kFlowVerdictBlock;
        }
        //allow (msg)
        else os_log_debug(logHandle, "rule says: ALLOW");
    
        //all set
        goto bail;
    }

    /* NO MATCHING RULE FOUND */

    //dbg msg
    os_log_debug(logHandle, "no (saved) rule found for %d/%{public}@", process.pid, process.binary.name);

    //CHECK:
    // client in passive mode?
    // take action based on user's settting ...allow/block
    if(YES == [preferences.preferences[PREF_PASSIVE_MODE] boolValue])
    {
        //dbg msg
        os_log_debug(logHandle, "client in passive mode...");
        
        //user action: allow?
        if(PREF_PASSIVE_MODE_ALLOW == [preferences.preferences[PREF_PASSIVE_MODE_ACTION] integerValue])
        {
            //dbg msg
            os_log_debug(logHandle, "passive mode: action is 'allow', so allowing %d/%{public}@", process.pid, process.binary.name);
            
            //allow
            verdict = kFlowVerdictAllow;
        }
        
        //user action: block?
        else
        {
            //dbg msg
            os_log_debug(logHandle, "passive mode: action is 'block', so blocking %d/%{public}@", process.pid, process.binary.name);
            
            //block
            verdict = kFlowVerdictBlock;
        }
        
        //create rule?
        if(PREF_PASSIVE_MODE_RULES_YES == [preferences.preferences[PREF_PASSIVE_MODE_RULES] integerValue])
        {
            //dbg msg
            os_log_debug(logHandle, "passive mode: create rules is set, so creating rule for new connection");
            
            //extract remote endpoint information
            NWHostEndpoint* remoteEndpoint = (NWHostEndpoint*)((NEFilterSocketFlow*)flow).remoteEndpoint;
            
            //init info for rule creation with specific endpoint information
            info = [@{KEY_PATH:process.path, KEY_TYPE:@RULE_TYPE_PASSIVE} mutableCopy];
            
            //get best hostname (prioritizes domain names over IP addresses)
            NSString* bestHostname = [self getBestHostnameFromFlow:(NEFilterSocketFlow*)flow];
            
            //add endpoint address (hostname) if available
            if(0!= bestHostname.length) {
                info[KEY_ENDPOINT_ADDR] = bestHostname;
            } else {
                info[KEY_ENDPOINT_ADDR] = VALUE_ANY;
            }
            
            //add endpoint port if available
            if(0 != remoteEndpoint.port.length) {
                info[KEY_ENDPOINT_PORT] = remoteEndpoint.port;
            } else {
                info[KEY_ENDPOINT_PORT] = VALUE_ANY;
            }
            
            //add protocol if available
            if(((NEFilterSocketFlow*)flow).socketProtocol > 0)
            {
                info[KEY_PROTOCOL] = [NSNumber numberWithInt:((NEFilterSocketFlow*)flow).socketProtocol];
            }

            //add process cs info?
            if(nil != process.csInfo) info[KEY_CS_INFO] = process.csInfo;
            
            //add action: allow
            if(PREF_PASSIVE_MODE_ALLOW == [preferences.preferences[PREF_PASSIVE_MODE_ACTION] integerValue])
            {
                //dbg msg
                os_log_debug(logHandle, "passive mode: creating rule with 'allow'");
                
                //allow
                info[KEY_ACTION] = @RULE_STATE_ALLOW;
            }
            //add action: block
            else
            {
                //dbg msg
                os_log_debug(logHandle, "passive mode: creating rule with 'block'");
                
                //block
                info[KEY_ACTION] = @RULE_STATE_BLOCK;
            }
            
            //create and add rule
            if(YES != [rules add:[[Rule alloc] init:info] save:YES])
            {
                //err msg
                os_log_error(logHandle, "ERROR: failed to add (passive) rule for %{public}@", info[KEY_PATH]);
                 
                //bail
                goto bail;
            }
            
            //tell user rules changed
            [alerts.xpcUserClient rulesChanged];
        }
        //no rule creation needed
        else
        {
            //dbg msg
            os_log_debug(logHandle, "passive mode: create rules is not set...");
        }
        
        //all set
        goto bail;
    }
    
    //dbg msg
    os_log_debug(logHandle, "client not in passive mode...");

    //CHECK:
    // 'allow dns traffic' pref set?
    // really, just any UDP traffic over port 53
    // note: checked first (before graylist, related alerts, etc.) as it's protocol/port based, so process-agnostic
    if(YES == [preferences.preferences[PREF_ALLOW_DNS] boolValue])
    {
        //dbg msg
        os_log_debug(logHandle, "'allow DNS traffic' is enabled, so checking port/protocol");

        //check proto (UDP) and port (53)
        if( (IPPROTO_UDP == ((NEFilterSocketFlow*)flow).socketProtocol) &&
            (YES == [((NWHostEndpoint*)((NEFilterSocketFlow*)flow).remoteEndpoint).port isEqualToString:@"53"]) )
        {
            //dbg msg
            os_log_debug(logHandle, "protocol is 'UDP' and port is '53', (so likely DNS traffic) ...will allow" );

            //allow
            verdict = kFlowVerdictAllow;

            //done
            goto bail;
        }
    }

    //CHECK:
    // there is related alert shown (i.e. for same process)
    // save this flow, as only want to process once user responds to first alert
    if(YES == [alerts isRelated:process])
    {
        //dbg msg
        os_log_debug(logHandle, "an alert is shown for process %d/%{public}@, so holding off delivering for now...", process.pid, process.binary.name);
        
        //related
        // will pause
        verdict = kFlowVerdictRelated;
        
        //bail
        goto bail;
    }
    
    //dbg msg
    os_log_debug(logHandle, "no related alert, currently shown...");

    //can we actually show an alert?
    // need a logged-in user AND a connected client; if not, alert-requiring paths below
    // allow + create a passive rule instead of pausing a flow no one can answer
    BOOL canAlert = ( (nil != consoleUser) &&
                      (YES == [alerts.xpcUserClient isConnected]) );

    //CHECK:
    // Apple process and 'PREF_ALLOW_APPLE' is set? Allow
    // Unless:
    //  a) Its on the 'graylist' (e.g. curl) as these can be (ab)used by malware
    //  b) There are other rules for this same process (even though they didn't match)
    if(YES == [preferences.preferences[PREF_ALLOW_APPLE] boolValue])
    {
        //dbg msg
        os_log_debug(logHandle, "'Allow Apple' preference is set, will check if is an Apple binary");
        
        //signed by Apple?
        if(Apple == [process.csInfo[KEY_CS_SIGNER] intValue])
        {
            //dbg msg
            os_log_debug(logHandle, "is an Apple binary...");
            
            //graylisted item?
            // pause and alert user (or, if no client, allow + create a passive rule)
            if(YES == [self.grayList isGrayListed:process])
            {
                //no user/client to prompt?
                // allow + create rule, so the flow isn't left paused w/ no one to answer
                if(NO == canAlert)
                {
                    verdict = [self allowNoClient:process];
                    goto bail;
                }

                //dbg msg
                os_log_debug(logHandle, "while signed by apple, %d/%{public}@ is gray listed, so will alert", process.pid, process.binary.name);

                //pause
                verdict = kFlowVerdictPause;

                //create/deliver alert
                [self alert:(NEFilterSocketFlow*)flow process:process];
            }
            //other rules for this process?
            else if(0 != [rules ruleCountForKey:process.key])
            {
                //no user/client to prompt?
                // allow + create rule, so the flow isn't left paused w/ no one to answer
                if(NO == canAlert)
                {
                    verdict = [self allowNoClient:process];
                    goto bail;
                }

                //dbg msg
                os_log_debug(logHandle, "while signed by apple, %d/%{public}@ has other (non-matching) rules, so will alert", process.pid, process.binary.name);

                //pause
                verdict = kFlowVerdictPause;

                //create/deliver alert
                [self alert:(NEFilterSocketFlow*)flow process:process];
            }
            //otherwise its a apple binary
            // not on graylist and w/ no other rules, so allow
            else
            {
                //dbg msg
                os_log_debug(logHandle, "due to preferences, allowing (non-graylisted) apple process %d/%{public}@", process.pid, process.path);
                
                //init for (rule) info
                // type: apple, action: allow
                info = [@{KEY_PATH:process.path, KEY_ACTION:@RULE_STATE_ALLOW, KEY_TYPE:@RULE_TYPE_APPLE} mutableCopy];
                
                //add process cs info
                if(nil != process.csInfo)
                {
                    //add
                    info[KEY_CS_INFO] = process.csInfo;
                }
                
                //add key
                info[KEY_KEY] = process.key;
                
                //add/save
                if(YES != [rules add:[[Rule alloc] init:info] save:YES])
                {
                    //err msg
                    os_log_error(logHandle, "ERROR: failed to add rule");
                    
                    //bail
                    goto bail;
                }
                
                //tell user rules changed
                [alerts.xpcUserClient rulesChanged];
            }
            
            //all set
            goto bail;
            
        } //signed by apple
    }
    //dbg msg
    else
    {
        //dbg msg
        os_log_debug(logHandle, "'Allow Apple' preference not set, so skipped 'Is Apple' check");
    }
    
    //'allow installed' check
    // if preference is enabled, item is 3rd-party, internal, and hasn't had its CS changed ...allow!
    if( (YES == [preferences.preferences[PREF_ALLOW_INSTALLED] boolValue]) &&
        (Apple != [process.csInfo[KEY_CS_SIGNER] intValue]) )
    {
        //only check internal processes
        // so, like ignore ones from DMGs, external drives, etc.
        if(YES == isInternalProcess(process.path))
        {
            //app date
            NSDate* date = nil;
            
            //dbg msg
            os_log_debug(logHandle, "3rd-party (internal) app, plus 'PREF_ALLOW_INSTALLED' is set...");
            
            //only once
            // get install date
            dispatch_once(&onceToken, ^{
                
                //get LuLu_Plus's install date
                installDate = preferences.preferences[PREF_INSTALL_TIMESTAMP];
                
                //dbg msg
                os_log_debug(logHandle, "LuLu_Plus's install date: %{public}@", installDate);
                
            });
            
            //get item's date added
            date = dateAdded(process.path);
            if( (nil != date) &&
                (NSOrderedAscending == [date compare:installDate]) )
            {
                //dbg msg
                os_log_debug(logHandle, "3rd-party item was installed prior (%@) to LuLu_Plus (%@), allowing & adding rule", date, installDate);
                
                //init info for rule creation
                info = [@{KEY_PATH:process.path, KEY_ACTION:@RULE_STATE_ALLOW, KEY_TYPE:@RULE_TYPE_BASELINE} mutableCopy];
                
                //add process cs info
                if(nil != process.csInfo)
                {
                    info[KEY_CS_INFO] = process.csInfo;
                }
                
                //create and add rule
                if(YES != [rules add:[[Rule alloc] init:info] save:YES])
                {
                    //err msg
                    os_log_error(logHandle, "ERROR: failed to add rule for %{public}@", info[KEY_PATH]);
                     
                    //bail
                    goto bail;
                }
                
                //tell user rules changed
                [alerts.xpcUserClient rulesChanged];
                
                //all set
                goto bail;
            }
            //newer
            else
            {
                //dbg msg
                os_log_debug(logHandle, "3rd-party item date (%@), is after LuLu_Plus's install date (%@)", date, installDate);
            }
        }
        //item is external
        else
        {
            os_log_debug(logHandle, "%{public}@ is external, so skipping 'allow installed' check", process.path);
        }
    }
    
    //allow simulator apps?
    if(YES == [preferences.preferences[PREF_ALLOW_SIMULATOR] boolValue])
    {
        //dbg msg
        os_log_debug(logHandle, "'allow simulator apps' is enabled, so checking process");
        
        //is simulator app?
        if(YES == isSimulatorApp(process.path))
        {
            //dbg msg
            os_log_debug(logHandle, "%{public}@, is an simulator app, so will allow", process.path);
            
            //allow
            verdict = kFlowVerdictAllow;
            
            //done
            goto bail;
        }
    }
    
    //no user/client to show an alert to?
    // allow, but create a rule for review
    if(NO == canAlert)
    {
        verdict = [self allowNoClient:process];
        goto bail;
    }

    //sending to user, so pause!
    verdict = kFlowVerdictPause;
        
    //create/deliver alert
    // note: handles response + next/any related flow
    [self alert:(NEFilterSocketFlow*)flow process:process];
    
bail:
    
    //log msg
    // match on this if you want detailed insight into LuLu_Plus's decision
    // log stream --level debug --predicate 'subsystem == "com.imonior.lulu-plus" && composedMessage BEGINSWITH "[LULU_PLUS]"'
    os_log_debug(logHandle, "[LULU_PLUS] PROCESS: %{public}@, FLOW (endpoint): %{public}@, RULE: %{public}@, verdict: %ld", process.path, ((NEFilterSocketFlow*)flow).remoteEndpoint, matchingRule, verdict);
    
    return verdict;
}

@end
