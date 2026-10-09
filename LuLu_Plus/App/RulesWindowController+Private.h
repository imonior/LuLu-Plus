//
//  file: RulesWindowController+Private.h
//  project: LuLu_Plus
//  description: what the files making up RulesWindowController share
//
//  copyright (c) 2026 LuLu_Plus. All rights reserved.
//

#import "RulesWindowController.h"

//the key of the column the rules list is sorted by
// note: the main file installs the sort descriptor when the window loads and the outline file
//       compares against it, so the string isn't either one's private business
#define SORT_DESCRIPTOR_COLUMN_0 @"sort_0"

/* GLOBALS */

//log handle
extern os_log_t logHandle;

//xpc for daemon comms
extern XPCDaemonClient* xpcDaemonClient;

@interface RulesWindowController (Private)

//which row an item is showing, when it is showing
-(NSInteger)findRowForItem:(id)item;

//get the rules from the daemon, then re-fill the list (`row`, if given, is the row to select)
-(void)loadRules:(BOOL)showOverlay select:(NSNumber*)row;

//update outline view
-(void)update:(NSNumber*)select;

//the confirmation a 'default' rule asks for before it is edited or deleted
-(NSModalResponse)showDefaultRuleAlert:(Rule*)rule action:(NSString*)action;

@end

