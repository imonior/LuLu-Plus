//
//  file: FilterDataProvider+Private.h
//  project: LuLu_Plus
//  description: what the files making up FilterDataProvider share: the verdicts, the globals the extension keeps in main.m, and the decisions each half calls on the other
//
//  copyright (c) 2026 LuLu_Plus. All rights reserved.
//

#import "Alerts.h"             //brings Process.h, which the public header's declarations use
#import "FilterDataProvider.h"

/* note: this is not a category added to the class from the outside - the class itself is spread
   over several files, and what used to be one file's private business has to be said once here
   instead of copied into each of them */

//verdicts
typedef NS_ENUM(NSInteger, FlowVerdict) {
    kFlowVerdictAllow,
    kFlowVerdictBlock,
    kFlowVerdictPause,      // new alert shown, waiting for user
    kFlowVerdictRelated,    // another alert already shown for this process
};

/* GLOBALS */

//alerts
extern Alerts* alerts;

//log handle
extern os_log_t logHandle;

//rules
extern Rules* rules;

//filter data provider obj
extern FilterDataProvider* provider;

//preferences
extern Preferences* preferences;

//allow list
extern BlockOrAllowList* allowList;

//block list
extern BlockOrAllowList* blockList;

@interface FilterDataProvider (Private)

/* INTERNAL METHODS */

//the decisions, one per direction
-(FlowVerdict)allowNoClient:(Process*)process;
-(FlowVerdict)processInboundEvent:(NEFilterSocketFlow*)flow;
-(FlowVerdict)processEvent:(NEFilterFlow*)flow;

//helpers the decisions call, which stay in the main file
-(void)alert:(NEFilterSocketFlow*)flow process:(Process*)process;
-(Process*)createProcess:(NEFilterFlow*)flow;
-(BOOL)isLocalhostHostname:(NSString*)hostname;

@end

