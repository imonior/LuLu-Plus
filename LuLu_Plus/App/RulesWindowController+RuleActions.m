//
//  file: RulesWindowController+RuleActions.m
//  project: LuLu_Plus
//  description: what the rules list does to a rule: the menu on each row and the items it offers
//
//  copyright (c) 2026 LuLu_Plus. All rights reserved.
//

#import "consts.h"
#import "RuleRow.h"
#import "utilities.h"
#import "AppDelegate.h"
#import "RulesWindowController+Private.h"

@implementation RulesWindowController (RuleActions)

//menu when user 2x clicks, or clicks on rule menu
-(IBAction)showRuleMenu:(NSButton*)sender
{
    BOOL mixedStates = NO;
    
    NSString* editTitle = nil;
    NSString* enableTitle = nil;
    NSString* deleteTitle = nil;
    NSString* disableTitle = nil;
    NSString* showPathsTitle = nil;
    
    NSInteger row = 0;
    row = [self.outlineView rowForView:sender];
    if (row < 0) return;
    
    //get item
    id item = [self.outlineView itemAtRow:row];
    
    //set flag
    BOOL isGroup = [item isKindOfClass:[NSArray class]];
    
    //determine if there are mixed states?
    if(isGroup && [item count] > 1) {
        
        BOOL firstState = ((Rule*)[item firstObject]).isDisabled.boolValue;
        for(int i = 1; i < [item count] && !mixedStates; i++) {
            mixedStates = (((Rule*)item[i]).isDisabled.boolValue != firstState);
        }
    }
    
    //set rule
    Rule* rule = isGroup ? [item firstObject] : (Rule *)item;
   
    //set base
    NSString* base = NSLocalizedString(@"Rule", nil);
    if(isGroup && [item count] > 1) {
        base = NSLocalizedString(@"Rules", nil);
    }
    
    //set titles
    editTitle = [NSString stringWithFormat:NSLocalizedString(@"Edit %@", @"Edit %@"), base];
    deleteTitle = [NSString stringWithFormat:NSLocalizedString(@"Delete %@", @"Delete %@"), base];

    enableTitle = [NSString stringWithFormat:NSLocalizedString(@"Enable %@", @"Enable %@"), base];
    disableTitle = [NSString stringWithFormat:NSLocalizedString(@"Disable %@", @"Disable %@"), base];
    
    //dbg msg
    os_log_debug(logHandle, "row: %ld, item: %{public}@", (long)row, item);

    //alloc menu
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Rule Menu"];
    menu.autoenablesItems = NO;
    
    //start with edit
    // but only for rules (not group)
    if(!isGroup) {
        [menu addItem:[self createMenuItemWithTitle:editTitle action:@selector(editRule:) row:row]];
    }

    //mixed states (in groups)
    // add both enable and disable
    if(mixedStates) {
        [menu addItem:[self createMenuItemWithTitle:enableTitle action:@selector(enableRule:) row:row]];
        [menu addItem:[self createMenuItemWithTitle:disableTitle action:@selector(disableRule:) row:row]];
    }
    
    //not mixed or single rule
    // so can just add one option to toggle
    else
    {
        //rule disabled?
        // set 'enable' option
        if(rule.isDisabled.boolValue) {
            [menu addItem:[self createMenuItemWithTitle:enableTitle action:@selector(enableRule:) row:row]];
        }
        
        //rule enabled?
        // set 'disable' option
        else {
            [menu addItem:[self createMenuItemWithTitle:disableTitle action:@selector(disableRule:) row:row]];
        }
    }
    
    //separator
    [menu addItem:[NSMenuItem separatorItem]];
    
    //add delete
    [menu addItem:[self createMenuItemWithTitle:deleteTitle action:@selector(deleteRule:) row:row]];
    
    //separator
    [menu addItem:[NSMenuItem separatorItem]];

    //add show paths
    showPathsTitle = NSLocalizedString(@"Display Path(s)", nil);
    [menu addItem:[self createMenuItemWithTitle:showPathsTitle action:@selector(showPaths:) row:row]];
    
    //show menu below button
    NSPoint pt = NSMakePoint(NSMinX(sender.bounds), NSMaxY(sender.bounds));
    [menu popUpMenuPositioningItem:nil atLocation:pt inView:sender];

    return;
}

//create menu item with title
-(NSMenuItem*)createMenuItemWithTitle:(NSString*)title action:(SEL)action row:(NSInteger)row {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:@""];
    item.target = self;
    item.representedObject = @(row);
    return item;
}

//edit rule
// just show 'add rule' window with pre-filled data
-(void)editRule:(NSMenuItem*)sender
{
    //grab rule
    // note: edit is only shown for rules (not item group)
    Rule *rule = [self.outlineView itemAtRow:[sender.representedObject integerValue]];
    
    //dbg msg
    os_log_debug(logHandle, "editing rule %{public}@", rule);
    
    //edit (via add window)
    [self addRule:rule];
    
    return;
}

//enable rule(s) via XPC
-(void)enableRule:(NSMenuItem*)sender
{
    Rule *rule = nil;
    NSString* uuid = nil;
    NSInteger selectedRow = -1;
    
    NSInteger row = [sender.representedObject integerValue];
    
    id item = [self.outlineView itemAtRow:row];
    
    if([item isKindOfClass:[NSArray class]]) {
        rule = [item firstObject];
    } else {
        rule = item;
        uuid = rule.uuid;
    }
    
    //save selected row
    selectedRow = self.outlineView.selectedRow;
    if(-1 == selectedRow) {
        selectedRow = row;
    }
    
    //dbg msg
    os_log_debug(logHandle, "enabling rule %{public}@", rule);
    
    //enable rule via XPC
    // nil uuid, means toggle all rules for item (process)
    [xpcDaemonClient toggleRule:rule.key rule:uuid state:@RULE_TOGGLE_STATE_ENABLE];
    
    //refresh
    [self loadRules:NO select:@(selectedRow)];
    
    return;
}

//disable rule(s) via XPC
-(void)disableRule:(NSMenuItem*)sender
{
    Rule *rule = nil;
    NSString* uuid = nil;
    NSInteger selectedRow = -1;
    
    NSInteger row = [sender.representedObject integerValue];
    
    id item = [self.outlineView itemAtRow:row];
    
    if([item isKindOfClass:[NSArray class]]) {
        rule = [item firstObject];
    } else {
        rule = item;
        uuid = rule.uuid;
    }
    
    //save selected row
    selectedRow = self.outlineView.selectedRow;
    if(-1 == selectedRow) {
        selectedRow = row;
    }
    
    //dbg msg
    os_log_debug(logHandle, "disabling rule %{public}@", rule);
    
    //disable rule via XPC
    // nil uuid, means toggle all rules for item (process)
    [xpcDaemonClient toggleRule:rule.key rule:uuid state:@RULE_TOGGLE_STATE_DISABLE];
    
    //refresh
    [self loadRules:NO select:@(selectedRow)];
    
    return;
}

//show paths
-(void)showPaths:(NSMenuItem *)sender
{
    Rule *rule = nil;
    NSInteger row = [sender.representedObject integerValue];
    
    id item = [self.outlineView itemAtRow:row];
    
    if([item isKindOfClass:[NSArray class]]) {
        rule = [item firstObject];
    } else {
        rule = item;
    }
    
    [self showItemPaths:rule.key];
    
    return;
}

//show paths in sheet
-(void)showItemPaths:(NSString*)itemKey
{
    //current rules (from ext)
    NSDictionary* currentRules = nil;
    
    //dbg msg
    os_log_debug(logHandle, "method '%s' invoked with %{public}@", __PRETTY_FUNCTION__, itemKey);
    
    //alloc sheet
    self.itemPathsWindowController = [[ItemPathsWindowController alloc] initWithWindowNibName:@"ItemPaths"];

    //get latest rules
    currentRules = [xpcDaemonClient getRules];
    
    //set rules
    self.itemPathsWindowController.item = currentRules[itemKey];
    
    //show it
    [self.window beginSheet:self.itemPathsWindowController.window completionHandler:^(NSModalResponse returnCode) {
        
        //unset
        self.itemPathsWindowController = nil;
        
    }];
    
    return;
}

@end
