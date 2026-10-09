//
//  file: RulesWindowController.m
//  project: lulu_plus (main app)
//  description: window controller for 'rules' table
//
//  created by Patrick Wardle
//  copyright (c) 2017 Objective-See. All rights reserved.
//

#import "consts.h"
#import "RuleRow.h"
#import "utilities.h"
#import "AppDelegate.h"
#import "XPCDaemonClient.h"
#import "RulesWindowController+Private.h"
#import "AddRuleWindowController.h"
#import "3rd-party/OrderedDictionary.h"


@implementation RulesWindowController

@synthesize rules;
@synthesize toolbar;
@synthesize addedRule;
@synthesize filterBox;
@synthesize addRulePanel;
@synthesize loadingRules;
@synthesize rulesFiltered;
@synthesize rulesObserver;
@synthesize loadingRulesSpinner;

//init some settings
-(void)awakeFromNib
{
    //set target
    self.outlineView.target = self;
    
    //set 2x click handler
    self.outlineView.doubleAction = @selector(doubleClickHandler:);
    
    return;
}

//configure (UI)
-(void)configure
{
    //dbg msg
    os_log_debug(logHandle, "method '%s' invoked", __PRETTY_FUNCTION__);

    //set subtitle
    [self setSubTitle];

    //clear (any previous) filter
    self.filterBox.stringValue = @"";

    //(re)setup observer for new rules
    // here, not in 'windowDidLoad', as 'windowWillClose' removes it and 'windowDidLoad' only fires on first open
    if(nil == self.rulesObserver)
    {
        //setup observer
        // will be broadcast (via XPC) when daemon updates rules
        self.rulesObserver = [[NSNotificationCenter defaultCenter] addObserverForName:RULES_CHANGED object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *notification)
        {
            //get new rules
            [self loadRules:YES select:@(0)];
        }];
    }

    //first cleanup any expired/temp rules
    [xpcDaemonClient cleanupRules:NO];

    //then load rules
    [self loadRules:YES select:@0];

    return;
}

//set subtitle to current profile
-(void)setSubTitle
{
    //dbg msg
    os_log_debug(logHandle, "method '%s' invoked", __PRETTY_FUNCTION__);
    
    //current profile
    NSString* currentProfile = [xpcDaemonClient getCurrentProfile];
    
    //have profile?
    if(0 != currentProfile.length) {
        
        //add subtitle
        if (@available(macOS 11.0, *)) {
            self.window.subtitle = [NSString stringWithFormat:NSLocalizedString(@"Current Profile: %@",@"Current Profile: %@"), currentProfile];
        }
    }
    //set to default
    else
    {
        //set
        if (@available(macOS 11.0, *)) {
            self.window.subtitle = NSLocalizedString(@"Current Profile: Default",@"Current Profile: Default");
        }
    }
    
    return;
}

//alloc/init
// get rules and listen for new ones
-(void)windowDidLoad
{
    //set default rule's view
    self.selectedRuleView = RULE_TYPE_ALL;
    
    //set indentation level for outline view
    self.outlineView.indentationPerLevel = 42;
    
    //pre-req for color of overlay
    self.loadingRules.wantsLayer = YES;
    
    //round overlay's corners
    self.loadingRules.layer.cornerRadius = 20.0;
    
    //mask overlay
    self.loadingRules.layer.masksToBounds = YES;
    
    //set overlay's view material
    self.loadingRules.material = NSVisualEffectMaterialHUDWindow;
    
    //set initial table header
    self.outlineView.tableColumns.firstObject.headerCell.stringValue = NSLocalizedString(@"All Rules",@"All Rules");
    
    //set sort descriptor for first column
    [self.outlineView.tableColumns[0] setSortDescriptorPrototype:[[NSSortDescriptor alloc] initWithKey:SORT_DESCRIPTOR_COLUMN_0 ascending:YES]];
    
    //set resizing
    self.outlineView.columnAutoresizingStyle = NSTableViewFirstColumnOnlyAutoresizingStyle;
    
    //set it to whole too...
    [self.outlineView setSortDescriptors:@[self.outlineView.tableColumns[0].sortDescriptorPrototype]];
    
    //set flag
    self.isAscending = YES;

    return;
}

//get rules from daemon
// then, re-load rules table
-(void)loadRules:(BOOL)showOverlay select:(NSNumber*)row
{
    //dbg msg
    os_log_debug(logHandle, "loading rules...");
    
    //show overlay
    if(YES == showOverlay)
    {
        //show overlay
        self.loadingRules.hidden = NO;
        
        //start progress indicator
        [self.loadingRulesSpinner startAnimation:nil];
    }
    
    //in background get rules
    // ...then load rule table table
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
    ^{
        //current rules (from ext)
        NSDictionary* currentRules = nil;
        
        //sorted keys
        NSArray* sortedKeys = nil;
        
        //show overlay
        if(YES == showOverlay)
        {
            //nap for UI (loading msg)
            [NSThread sleepForTimeInterval:0.5f];
        }
        
        //get rules
        currentRules = [xpcDaemonClient getRules];
        
        //dbg msg
        os_log_debug(logHandle, "received %lu rules from daemon: %{public}@", (unsigned long)currentRules.count, currentRules.allKeys);
        
        //sync rules
        @synchronized (self)
        {
            //alloc
            self.rules = [[OrderedDictionary alloc] init];
        
            //dbg msg
            os_log_debug(logHandle, "sorting rules...");
            
            //sort by (rule) name
            sortedKeys = [currentRules keysSortedByValueUsingComparator:^NSComparisonResult(id _Nonnull obj1, id  _Nonnull obj2)
            {
                //normal
                if(YES == self.isAscending)
                {
                    //compare/return
                    return [((Rule*)[((NSDictionary*)obj1)[KEY_RULES] firstObject]).name compare:((Rule*)[((NSDictionary*)obj2)[KEY_RULES] firstObject]).name options:NSCaseInsensitiveSearch];
                }
                //reversed
                else
                {
                    //compare/return
                    return [((Rule*)[((NSDictionary*)obj2)[KEY_RULES] firstObject]).name compare:((Rule*)[((NSDictionary*)obj1)[KEY_RULES] firstObject]).name options:NSCaseInsensitiveSearch];
                }
            }];
            
            //add sorted rules
            for(NSInteger i = 0; i<sortedKeys.count; i++)
            {
                //add to ordered dictionary
                [self.rules insertObject:currentRules[sortedKeys[i]] forKey:sortedKeys[i] atIndex:i];
            }
            
        }//sync
        
        //show rules in UI
        dispatch_async(dispatch_get_main_queue(), ^{
            
            //show overlay
            if(YES == showOverlay)
            {
                //hide overlay
                self.loadingRules.hidden = YES;
                
                //stop spinner
                [self.loadingRulesSpinner stopAnimation:nil];
            }
            
            //update ui
            [self update:row];
            
            //set subtitle
            [self setSubTitle];
        });

    });
        
    return;
}

//update outline view
-(void)update:(NSNumber*)select
{
    //selected row
    NSInteger selectedRow = -1;
    
    //sync
    // filter & reload
    @synchronized(self)
    {
        //dbg msg
        os_log_debug(logHandle, "updating outline view for rules...");
        
        //row to select
        if(nil != select)
        {
            //set
            selectedRow = select.intValue;
        }
        //get currently selected row
        // default to first row if this fails
        else
        {
            //get
            selectedRow = self.outlineView.selectedRow;
            if(-1 == selectedRow)
            {
                //default
                selectedRow = 0;
            }
        }
    
        //always filter
        self.rulesFiltered = [self filter];
        
        //begin updates
        [self.outlineView beginUpdates];
        
        //full reload
        [self.outlineView reloadData];
        
        //auto expand
        [self.outlineView expandItem:nil expandChildren:YES];
        
        //end updates
        [self.outlineView endUpdates];
        
        //find row for new rule
        if(nil != self.addedRule)
        {
            //find row
            selectedRow = [self findRowForItem:self.addedRule];
            
            //unset
            self.addedRule = nil;
        }
    
        //prev selected now beyond bounds?
        // just default to select last row...
        if(self.outlineView.numberOfRows > 0)
        {
            selectedRow = MIN(selectedRow, (self.outlineView.numberOfRows-1));
        }
        
        //dbg msg
        os_log_debug(logHandle, "reselecting %ld", (long)selectedRow);
            
        //reselect
        [self.outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:selectedRow] byExtendingSelection:NO];
            
        //scroll
        [self.outlineView scrollRowToVisible:selectedRow];

    } //sync
    
bail:
        
    return;
}

//handler for rule select view
-(IBAction)rulesViewSelectorHandler:(id)sender {
    
    //dbg msg
    os_log_debug(logHandle, "method '%s' invoked", __PRETTY_FUNCTION__);
    
    //grab tag/save
    self.selectedRuleView = self.rulesViewSelector.selectedItem.tag;
    
    //set column title
    switch(self.selectedRuleView)
    {
        //all
        case RULE_TYPE_ALL:
            
            self.outlineView.tableColumns.firstObject.headerCell.stringValue = NSLocalizedString(@"All Rules", @"All Rules");
            break;
            
        //default
        case RULE_TYPE_DEFAULT:
            
            self.outlineView.tableColumns.firstObject.headerCell.stringValue = NSLocalizedString(@"Operating System Programs (required for system functionality)", @"Operating System Programs (required for system functionality)");
            break;
            
        //apple
        case RULE_TYPE_APPLE:
            
            self.outlineView.tableColumns.firstObject.headerCell.stringValue = NSLocalizedString(@"Apple Programs (automatically allowed & added here if 'allow apple programs' is set)", @"Apple Programs (automatically allowed & added here if 'allow apple programs' is set)");
            break;
          
        //baseline
        case RULE_TYPE_BASELINE:
            
            self.outlineView.tableColumns.firstObject.headerCell.stringValue = NSLocalizedString(@"Pre-installed 3rd-party Programs (automatically allowed & added here if 'allow installed applications' is set)", @"Pre-installed 3rd-party Programs (automatically allowed & added here if 'allow installed applications' is set)");
            break;
            
        //user
        case RULE_TYPE_USER:
            
            self.outlineView.tableColumns.firstObject.headerCell.stringValue = NSLocalizedString(@"User-specified Programs (manually added, or in response to an alert)", @"User-specified Programs (manually added, or in response to an alert)");
            
            break;
            
        case RULE_TYPE_PASSIVE:
            
            self.outlineView.tableColumns.firstObject.headerCell.stringValue = NSLocalizedString(@"Added passively (either if 'passive mode' is set, or no user was logged in when rule was created)", @"Added passively (either if 'passive mode' is set, or no user was logged in when rule was created)");
            
            break;
            
        case RULE_TYPE_RECENT:
            
            self.outlineView.tableColumns.firstObject.headerCell.stringValue = NSLocalizedString(@"Added in last 24 hours (sorted by creation time)", @"Added in last 24 hours (sorted by creation time)");
            break;
            
        
        default:
            break;
    }
    
    //unselect (all) row
    [self.outlineView deselectAll:nil];
    
    //reload table
    [self update:@(0)];
    
    //'add rules' only allowed for 'all' and 'user' views
    if( (self.selectedRuleView == RULE_TYPE_ALL) ||
        (self.selectedRuleView == RULE_TYPE_USER) )
    {
        //change label color to default
        self.addRuleLabel.textColor = [NSColor labelColor];
        
        //enable button
        self.addRuleButton.enabled = YES;
    }
    //'add rule' not allowed for 'default'/'apple'/'baseline'
    else
    {
        //change label color to gray
        self.addRuleLabel.textColor = [NSColor controlBackgroundColor];
        
        //disable button
        self.addRuleButton.enabled = NO;
    }
    
    return;
}

//filter (search box) handler
// just call into update method (which filters, etc)
-(IBAction)filterBoxHandler:(id)sender {
    
    //dbg msg
    os_log_debug(logHandle, "filtering rules...");
    
    //update
    [self update:nil];
    
    return;
}

//double-click handler
-(void)doubleClickHandler:(id)object
{
    NSInteger row = [self.outlineView clickedRow];
    if (row < 0) return;

    //get item
    id item = [self.outlineView itemAtRow:row];

    //only edit if it's a rule (not a group)
    if ([item isKindOfClass:[NSArray class]]) {
        return;
    }

    //grab rule
    Rule *rule = (Rule *)item;

    //dbg msg
    os_log_debug(logHandle, "editing rule %{public}@", rule);

    //edit (via add window)
    [self addRule:rule];
}


//warn user the modifying default rules might break things
-(NSModalResponse)showDefaultRuleAlert:(Rule*)rule action:(NSString*)action
{
    return showAlert(NSAlertStyleWarning, [NSString stringWithFormat:NSLocalizedString(@"%@ is legitimate macOS process", @"%@ is legitimate macOS process"), rule.name], [NSString stringWithFormat:NSLocalizedString(@"%@ this rule, may impact legitimate system functionalty ...continue?",@"%@ this rule, may impact legitimate system functionalty ...continue?"), action], @[NSLocalizedString(@"Continue", @"Continue"), NSLocalizedString(@"Cancel", @"Cancel")]);
}

//delete rule(s) via XPC
-(void)deleteRule:(NSMenuItem *)sender
{
    Rule *rule = nil;
    NSString* uuid = nil;
    
    NSInteger row = [sender.representedObject integerValue];
    
    id item = [self.outlineView itemAtRow:row];
    
    if([item isKindOfClass:[NSArray class]]) {
        rule = [item firstObject];
    } else {
        rule = item;
        uuid = rule.uuid;
    }
    
    //default rule?
    // show alert/warning
    if(RULE_TYPE_DEFAULT == rule.type.intValue)
    {
        //show alert
        // ...and bail if user cancels
        if(NSAlertSecondButtonReturn == [self showDefaultRuleAlert:rule action:@"Deleting"])
        {
            //bail
            goto bail;
        }
    }
    
    //dbg msg
    os_log_debug(logHandle, "deleting rule key: %{public}@, rule uuid: %{public}@", rule.key, uuid);
    
    //remove rule via XPC
    // nil uuid, means delete all rules for item (process)
    [xpcDaemonClient deleteRule:rule.key rule:uuid];
    
    //refresh
    [self loadRules:NO select:@(row)];
    
bail:
    
    return;
}

//button handler for 'add rules'
// show 'add rule' sheet and then, on close, add rule via XPC
-(IBAction)addRule:(id)sender
{
    //dbg msg
    os_log_debug(logHandle, "method '%s' invoked with %{public}@", __PRETTY_FUNCTION__, sender);
    
    //alloc sheet
    self.addRuleWindowController = [[AddRuleWindowController alloc] initWithWindowNibName:@"AddRule"];
    
    //invoked with existing rule (to edit)
    if(YES == [sender isKindOfClass:[Rule class]])
    {
        //item no longer exists? (globs ('*' / '/*') are exempt)
        // alert & bail, as editing (re)creates the rule, which would lose its code signing info
        if( (YES != [((Rule*)sender).path hasSuffix:VALUE_ANY]) &&
            (YES != [NSFileManager.defaultManager fileExistsAtPath:((Rule*)sender).path]) )
        {
            //show alert
            showAlert(NSAlertStyleWarning, NSLocalizedString(@"Unable to Edit Rule", @"Unable to Edit Rule"), [NSString stringWithFormat:NSLocalizedString(@"%@ no longer exists, so its rule cannot be edited. The rule can still be disabled or deleted.", @"%@ no longer exists, so its rule cannot be edited. The rule can still be disabled or deleted."), ((Rule*)sender).path], @[NSLocalizedString(@"OK", @"OK")]);

            //bail
            goto bail;
        }

        //default rule?
        //show alert/warning
        if(RULE_TYPE_DEFAULT == ((Rule*)sender).type.intValue)
        {
            //show alert
            // ...and bail if user cancels
            if(NSAlertSecondButtonReturn == [self showDefaultRuleAlert:sender action:@"Editing"])
            {
                //bail
                goto bail;
            }
        }
        
        //set rule
        self.addRuleWindowController.rule = (Rule*)sender;
    }
    
    //show it
    // on close/OK, invoke XPC to add rule, then reload
    NSModalResponse response = [NSApp runModalForWindow:self.addRuleWindowController.window];
    {
        
        //(existing) rule
        Rule* rule = nil;
        
        //dbg msg
        os_log_debug(logHandle, "add/edit rule window closed...");
        
        //on OK, add rule via XPC
        if(response == NSModalResponseOK)
        {
            //was an update to an existing rule?
            // delete it first, then go ahead and add
            if(nil != (rule = self.addRuleWindowController.rule))
            {
                //remove rule via XPC
                [xpcDaemonClient deleteRule:rule.key rule:rule.uuid];
            }
            
            //add rule via XPC
            [xpcDaemonClient addRule:self.addRuleWindowController.info];
            
            //new rule?
            // save path, and toggle to user tab
            if(nil == rule)
            {
                //save into iVar
                // allows table to select/scroll to this new rule
                self.addedRule = self.addRuleWindowController.info[KEY_PATH];
            }
            
            //reload
            [self loadRules:YES select:nil];
        }
        
        //unset add rule window controller
        self.addRuleWindowController = nil;
        
    }
    
bail:
    
    return;
}

//init array of filtered rules
// determines what rule view is selected, then sort based on that and also what's in search box
-(OrderedDictionary*)filter
{
    //filtered items
    OrderedDictionary* results = nil;
    
    //sorted keys
    NSArray* sortedKeys = nil;
    
    //sorted rules
    OrderedDictionary* sortedRules = nil;
    
    //filter string
    NSString* filter = nil;
    
    //dbg msg
    os_log_debug(logHandle, "filtering rules...");
    
    //init
    results = [[OrderedDictionary alloc] init];
    
    //grab filter string
    filter = self.filterBox.stringValue;
    
    //dbg msg
    os_log_debug(logHandle, "selected rule view: %ld", self.selectedRuleView);
    
    //all/no filter
    // don't need to filter
    if( (RULE_TYPE_ALL == self.selectedRuleView) &&
        (0 == filter.length) )
    {
        //dbg msg
        os_log_debug(logHandle, "selected toolbar item is 'all' and filter box is empty ...no need to filter");
        
        //no filter
        results = self.rules;
        
        //bail
        goto bail;
    }
    
    //dbg msg
    if(0 != filter.length)
    {
        //dbg msg
        os_log_debug(logHandle, "filtering on '%{public}@'", filter);
    }
        
    //scan all rules
    // add any that match rule view and filter string
    {[self.rules enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL* stop) {
        
        //item
        // cs info, rules, etc
        NSMutableDictionary* item = nil;
        
        //item's rules
        NSArray* itemRules = nil;
        
        //(item') recent rules
        NSMutableArray* recentRules = nil;
        
        //(item's) rules that match
        NSMutableArray* matchedRules = nil;
        
        //make copy
        item = [value mutableCopy];
        
        //item's rules
        itemRules = item[KEY_RULES];
        
        //init
        matchedRules = [NSMutableArray array];
        
        //not on 'all'/'recent' view?
        // skip rules if they don't match selected toolbar type
        if( (RULE_TYPE_ALL != self.selectedRuleView) &&
            (RULE_TYPE_RECENT != self.selectedRuleView) )
        {
            //check all item's rule for match
            for(Rule* itemRule in itemRules)
            {
                //match?
                if(self.selectedRuleView == itemRule.type.intValue)
                {
                    //add
                    [matchedRules addObject:itemRule];
                }
            }
            
            //done if no item rules match
            if(0 == matchedRules.count)
            {
                return;
            }
            
            //update
            item[KEY_RULES] = [matchedRules mutableCopy];
            
            //reset
            // as we reuse this in filtering
            [matchedRules removeAllObjects];
        }
        
        //recent?
        if(RULE_TYPE_RECENT == self.selectedRuleView)
        {
            //get (item's) recent rules
            recentRules = [self recentRules:itemRules];
            
            //item doesn't have any recent rules
            if(0 == recentRules.count)
            {
                //skip
                return;
            }
            
            //make copy
            item = [value mutableCopy];
            
            //update item's rules
            item[KEY_RULES] = recentRules;
        }
        
        //no filter?
        // we're done
        if(0 == filter.length)
        {
            //append
            [results insertObject:item forKey:key atIndex:results.count];
                        
            //next
            return;
        }
        
        /* NOW FILTER */
        
        //check each rule(s) on filter string
        for(Rule* rule in item[KEY_RULES])
        {
            //match?
            // save rule
            if(YES == [rule matchesString:filter])
            {
                //add
                [matchedRules addObject:rule];
            }
        }
        
        //any matched (item) rules?
        // update item rule array and add item
        if(0 != matchedRules.count)
        {
            //update item's rules
            item[KEY_RULES] = matchedRules;
            
            //append to filtered results
            [results insertObject:item forKey:key atIndex:results.count];
        }
        
    }];}
    
    //sort recent rules
    if(RULE_TYPE_RECENT == self.selectedRuleView)
    {
        //nap for UI (loading msg)
        [NSThread sleepForTimeInterval:0.5f];
        
        //dbg msg
        os_log_debug(logHandle, "sorting (recent) rules by creation timestamp...");
        
        //init
        sortedRules = [[OrderedDictionary alloc] init];
        
        //sort by (rule) timestamp
        sortedKeys = [results keysSortedByValueUsingComparator:^NSComparisonResult(id _Nonnull obj1, id  _Nonnull obj2)
        {
            //normal
            if(YES == self.isAscending)
            {
                //compare/return
                return [((Rule*)[((NSDictionary*)obj2)[KEY_RULES] firstObject]).creation compare:((Rule*)[((NSDictionary*)obj1)[KEY_RULES] firstObject]).creation];
            }
            //reversed
            else
            {
                //compare/return
                return [((Rule*)[((NSDictionary*)obj1)[KEY_RULES] firstObject]).creation compare:((Rule*)[((NSDictionary*)obj2)[KEY_RULES] firstObject]).creation];
            }
        }];
        
        //add sorted rules
        for(NSInteger i = 0; i<sortedKeys.count; i++)
        {
            //add to ordered dictionary
            [sortedRules insertObject:results[sortedKeys[i]] forKey:sortedKeys[i] atIndex:i];
        }
        
        results = sortedRules;
    }
            
bail:
    
    //dbg msg
    os_log_debug(logHandle, "filtered rules: %{public}@", results.allKeys);
    
    return results;
}

//item's recent rules
// any that are after boot time
-(NSMutableArray*)recentRules:(NSArray*)itemRules
{
    //24 hrs ago
    NSDate* cutoff = nil;
    
    //recent
    NSMutableArray* recentRules = nil;
    
    //alloc/init
    recentRules = [NSMutableArray array];
    
    //init
    cutoff = [[NSDate date] dateByAddingTimeInterval:-(24 * 60 * 60)];
    
    //check each rule(s)
    for(Rule* rule in itemRules)
    {
        //skip older rules
        // ...didn't have creation time
        if(nil == rule.creation)
        {
            continue;
        }
        
        //not after
        if(NSOrderedDescending != [rule.creation compare:cutoff])
        {
            continue;
        }

        //add
        [recentRules addObject:rule];
    }
    
bail:
    
    //sort: ascending
    if(YES == self.isAscending)
    {
        //sort from newest to oldest
        [recentRules sortUsingComparator:^NSComparisonResult(Rule *rule1, Rule *rule2) {
                //compare the creation dates
                return [rule2.creation compare:rule1.creation];
        }];
    }
    //sort: descending
    else
    {
        //sort from oldest to newest
        [recentRules sortUsingComparator:^NSComparisonResult(Rule *rule1, Rule *rule2) {
                //compare the creation dates
                return [rule1.creation compare:rule2.creation];
        }];
    }
    
    return recentRules;
}



//button handler
// open LuLu_Plus home page/docs
-(IBAction)openHomePage:(id)sender {
    
    //open
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:PRODUCT_URL]];
    
    return;
}

//on window close
// set activation policy
-(void)windowWillClose:(NSNotification *)notification
{
    //cleanup any expired/temp rules
    [xpcDaemonClient cleanupRules:NO];
    
    //remove observer
    if(self.rulesObserver) {
        [[NSNotificationCenter defaultCenter] removeObserver:self.rulesObserver];
        self.rulesObserver = nil;
    }
    
    //make sure spinner is stopped
    [self.loadingRulesSpinner stopAnimation:nil];
    
    //wait a bit, then set activation policy
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
    ^{
         //on main thread
         dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
             
             //set activation policy
             [((AppDelegate*)[[NSApplication sharedApplication] delegate]) setActivationPolicy];
             
         });
    });
    
    return;
}

@end
