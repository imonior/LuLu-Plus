//
//  file: RulesWindowController+Outline.m
//  project: LuLu_Plus
//  description: the outline half of RulesWindowController: filling the table, its cells, and the delete key
//
//  copyright (c) 2026 LuLu_Plus. All rights reserved.
//

#import "consts.h"
#import "RuleRow.h"
#import "utilities.h"
#import "AppDelegate.h"
#import "RulesWindowController+Private.h"

//custom view
// to disable highlighting for disabled rules
@interface CustomTableCellView : NSTableCellView
@property (nonatomic) BOOL isDisabled;
@end

@implementation CustomTableCellView

- (void)setBackgroundStyle:(NSBackgroundStyle)backgroundStyle {
    [super setBackgroundStyle:backgroundStyle];
    
    //maintain disabled color even when selected
    if (self.isDisabled) {
        self.textField.textColor = NSColor.disabledControlTextColor;
        [super setBackgroundStyle: NSBackgroundStyleLight];
    }
}

@end

@implementation RulesWindowController (Outline)

#pragma mark -
#pragma mark outline delegate methods

static const NSUInteger kDeleteKeyCode = 51;

//handle delete
// alert and delete rule
- (void)keyDown:(NSEvent *)event {
    
    // Only care about delete key
    if (event.keyCode != kDeleteKeyCode) {
        [super keyDown:event];
        return;
    }
        
    NSInteger selectedRow = self.outlineView.selectedRow;
    if (selectedRow == -1) {
        [super keyDown:event];
        return;
    }

    //grab item for the selected row
    id item = [self.outlineView itemAtRow:selectedRow];

    //alert message
    // default: single rule
    NSString* message = NSLocalizedString(@"Delete Rule?", @"Delete Rule?");

    //group (all rules for a program)?
    // ...call out that *all* its rules will be deleted, by name (e.g. 'curl')
    if([item isKindOfClass:[NSArray class]])
    {
        //process name (from the group's first rule)
        NSString* name = [(Rule*)[item firstObject] name];

        //customize message
        message = (0 != name.length) ?
            [NSString stringWithFormat:NSLocalizedString(@"Delete all rules for %@?", @"Delete all rules for %@?"), name] :
            NSLocalizedString(@"Delete all rules for this item?", @"Delete all rules for this item?");
    }

    //show alert
    NSModalResponse response = showAlert(NSAlertStyleWarning,
                                           message,
                                           nil,
                                           @[NSLocalizedString(@"Delete", @"Delete"),
                                             NSLocalizedString(@"Cancel", @"Cancel")]);
        
    //user chose delete
    if (response == NSAlertFirstButtonReturn) {
        
            //delete rule needs menu item
            NSMenuItem *tempMenuItem = [[NSMenuItem alloc] init];
            tempMenuItem.representedObject = @(selectedRow);
        
            //delete rule
            [self deleteRule:tempMenuItem];
    }
    
    return;

}

//number of the children
-(NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item
{
    //# of children
    // root: all
    // non-root, just items in item
    return (nil == item) ? self.rulesFiltered.count : [item count];
}

//items (processes) are expandable
// these items are built from items of type array
-(BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item
{
    return (YES == [item isKindOfClass:[NSArray class]]);
}

//return child
-(id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item
{
    //child
    id child = nil;
    
    //key
    id key = nil;
    
    //a root item?
    // 'child' is array of rules
    if(nil == item)
    {
        //key
        key = [self.rulesFiltered keyAtIndex:index];
        
        //child
        child = self.rulesFiltered[key][KEY_RULES];
    }
    //otherwise
    // child is rule at index
    else
    {
        //set child
        child = item[index];
    }
    
    return child;
}

//return custom row for view
// allows highlighting, etc...
-(NSTableRowView *)outlineView:(NSOutlineView *)outlineView rowViewForItem:(id)item
{
    //row view
    RuleRow* rowView = nil;
    
    //row ID
    static NSString* const kRowIdentifier = @"RowView";
    
    //try grab existing row view
    rowView = [self.outlineView makeViewWithIdentifier:kRowIdentifier owner:self];
    
    //make new if needed
    if(nil == rowView)
    {
        //create new
        // size doesn't matter
        rowView = [[RuleRow alloc] initWithFrame:NSZeroRect];
        
        //set row ID
        rowView.identifier = kRowIdentifier;
    }
    
    return rowView;
}

//table delegate method
// return new cell for row
-(NSView *)outlineView:(NSOutlineView *)outlineView viewForTableColumn:(NSTableColumn *)tableColumn item:(id)item
{
    //date formatter
    NSDateFormatter *dateFormatter = nil;
    
    //view
    NSTableCellView* cell = nil;
    
    //first rule
    Rule* rule = nil;
    
    //first column
    // process or connection
    if(tableColumn == self.outlineView.tableColumns[0])
    {
        //a root item?
        if(YES == [item isKindOfClass:[NSArray class]])
        {
            //grab first rule
            rule = [item firstObject];

            //create/configure process cell
            cell = [self createProcessCell:rule];
        }
        //child
        // create/configure event cell
        else
        {
            //create/configure process cell
            cell = [self createConnectionCell:item];
        }
    }
    //all other columns
    // init a basic cell
    else if(tableColumn == self.outlineView.tableColumns[1])
    {
        //cell
        cell = [self.outlineView makeViewWithIdentifier:@"ruleCell" owner:self];
        if(nil == cell) goto bail;
                
        //only add rule for connection (i.e. not item)
        if(YES == [item isKindOfClass:[Rule class]])
        {
            //action
            NSString* action = nil;
            
            //typecast
            rule = (Rule*)item;
            
            //block?
            if(RULE_STATE_BLOCK == rule.action.integerValue)
            {
                //set image
                cell.imageView.image = [NSImage imageNamed:@"RulesBlock"];
                
                //duration: process
                if(nil != rule.pid)
                {
                    //set msg
                    action = [NSString stringWithFormat:NSLocalizedString(@"Block (pid: %@)", @"Block (pid: %@)"), rule.pid];
                }
                
                //duration: expiration
                else if(nil != rule.expiration)
                {
                    //init date formatter
                    dateFormatter = [[NSDateFormatter alloc] init];
                    [dateFormatter setDateStyle:NSDateFormatterNoStyle];
                    [dateFormatter setTimeStyle:NSDateFormatterShortStyle];
                    
                    //set msg
                    action = [NSString stringWithFormat:NSLocalizedString(@"Block (until: %@)", @"Block (until: %@)"), [dateFormatter stringFromDate:rule.expiration]];
                }
                
                //normal
                else
                {
                    //set action text
                    action = NSLocalizedString(@"Block", @"Block");
                }
                
            }
            //allow?
            else
            {
                //set image
                cell.imageView.image = [NSImage imageNamed:@"RulesAllow"];
                
                //duration: process
                if(nil != rule.pid)
                {
                    //set msg
                    action = [NSString stringWithFormat:NSLocalizedString(@"Allow (pid: %@)", @"Allow (pid: %@)"), rule.pid];
                }
                
                //duration: expiration
                else if(nil != rule.expiration)
                {
                    //init date formatter
                    dateFormatter = [[NSDateFormatter alloc] init];
                    [dateFormatter setDateStyle:NSDateFormatterNoStyle];
                    [dateFormatter setTimeStyle:NSDateFormatterShortStyle];
                    
                    //set msg
                    action = [NSString stringWithFormat:NSLocalizedString(@"Allow (until: %@)", @"Allow (until: %@)"), [dateFormatter stringFromDate:rule.expiration]];
                }
                
                //normal
                else
                {
                    //set action text
                    action = NSLocalizedString(@"Allow", @"Allow");
                }
            }
            
            //process tree rule?
            // append '+kids' so it's distinguishable from a plain process rule
            if(ACTION_SCOPE_PROCESS_TREE == rule.scope.intValue)
            {
                //append
                action = [NSString stringWithFormat:NSLocalizedString(@"%@ +kids", @"%@ +kids"), action];
            }

            //disabled?
            // set flag (for highlighting) and color
            ((CustomTableCellView *)cell).isDisabled = rule.isDisabled.boolValue;
            if (rule.isDisabled.boolValue) {
                cell.textField.textColor = NSColor.disabledControlTextColor;
            } else {
                cell.textField.textColor = NSColor.controlTextColor;
            }

            //set text
            cell.textField.stringValue = action;
        }
        //otherwise unset image/text
        else
        {
            //grab first rule
            rule = [item firstObject];
            
            //unset image
            cell.imageView.image = nil;
            
            //unset text
            cell.textField.stringValue = @"";
        }
    }
    
bail:
    
    return cell;
}

//sort
// really for now, just reverse
-(void)outlineView:(NSOutlineView *)outlineView sortDescriptorsDidChange:(NSArray<NSSortDescriptor *> *)oldDescriptors
{
    //dbg msg
    os_log_debug(logHandle, "method '%s' invoked", __PRETTY_FUNCTION__);
    
    //only sort first column: rule name
    if(YES == [outlineView.sortDescriptors.firstObject.key isEqualToString:SORT_DESCRIPTOR_COLUMN_0])
    {
        //reverse
        [self.rules reverse];
        
        //toggle
        self.isAscending = !self.isAscending;
        
        //unselect row
        // want top row to be selected after reverse
        [self.outlineView deselectAll:nil];

        //refresh table
        [self update:nil];
    }
    
    return;
}

//create & customize process cell
// these are the root cells, that hold the item (process)
-(NSTableCellView*)createProcessCell:(Rule*)rule
{
    //item cell
    NSTableCellView* processCell = nil;
    
    //directory
    NSString* directory = nil;
    
    //create cell
    processCell = [self.outlineView makeViewWithIdentifier:@"processCell" owner:self];
    
    //global rule?
    // no icon, no path, etc.
    if(YES == rule.isGlobal.boolValue)
    {
        //set icon
        processCell.imageView.image = [[NSWorkspace sharedWorkspace]
        iconForFileType: NSFileTypeForHFSTypeCode(kGenericHardDiskIcon)];
        
        //set text
        processCell.textField.stringValue = NSLocalizedString(@"Any program", @"Any program");
        
        //(un)set detailed text
        ((NSTextField*)[processCell viewWithTag:TABLE_ROW_SUB_TEXT]).stringValue = @"";
    }
    //directory rule?
    else if(YES == rule.isDirectory.boolValue)
    {
        //init directory
        // ...by removing *
        directory = [rule.path substringToIndex:(rule.path.length-1)];
        
        //set icon
        processCell.imageView.image = getIconForProcess(directory);
        
        //main text
        // last directory
        processCell.textField.stringValue = [NSString stringWithFormat:NSLocalizedString(@"Programs within \"%@/\"", @"Programs within \"%@/\""), directory.lastPathComponent];
        
        //details
        // just use path
        ((NSTextField*)[processCell viewWithTag:TABLE_ROW_SUB_TEXT]).stringValue = rule.path;
    }
    
    //non global rule?
    // set icon, path, etc.
    else
    {
        //set icon
        processCell.imageView.image = getIconForProcess(rule.path);

        //main text
        // item's name
        processCell.textField.stringValue = rule.name;
        
        //format/set details
        ((NSTextField*)[processCell viewWithTag:TABLE_ROW_SUB_TEXT]).stringValue = [self formatItemDetails:rule];
    }
    
    return processCell;
}

//format details for item
-(NSString*)formatItemDetails:(Rule*)rule
{
    //details
    NSString* details = @"";
        
    //cs info?
    if(nil != rule.csInfo)
    {
        //format, based on signer
        switch([rule.csInfo[KEY_CS_SIGNER] intValue])
        {
            //apple
            case Apple:
                details = [NSString stringWithFormat:NSLocalizedString(@"%@ (signer: Apple Proper)", @"%@ (signer: Apple Proper)"), rule.csInfo[KEY_CS_ID]];
                break;
            
            //app store
            case AppStore:
                details = [NSString stringWithFormat:NSLocalizedString(@"%@ (signer: Apple Mac OS App Store)", @"%@ (signer: Apple Mac OS App Store)"), rule.csInfo[KEY_CS_ID]];
                break;
                
            //dev id
            case DevID:
                details = [NSString stringWithFormat:NSLocalizedString(@"%@ (signer: %@)",@"%@ (signer: %@)"), rule.csInfo[KEY_CS_ID], [rule.csInfo[KEY_CS_AUTHS] firstObject]];
                break;
                
            //ad hoc
            case AdHoc:
                details = [NSString stringWithFormat:NSLocalizedString(@"%@ (signer: %@)", @"%@ (signer: %@)"), rule.csInfo[KEY_CS_ID], NSLocalizedString(@"Ad hoc", @"Ad hoc")];
                break;
                
            default:
                break;
        }
    }
    
    //no valid cs info
    // just use path / and mention issue
    if(0 == details.length)
    {
        //set
        details = [NSString stringWithFormat:NSLocalizedString(@"%@ (signer: invalid/unsigned)", @"%@ (signer: invalid/unsigned)"), rule.path];
    }

    return details;
}

//create & customize connection cell
-(NSTableCellView*)createConnectionCell:(Rule*)rule
{
    //endpoint port
    NSString* port = nil;
    
    //endpoint addr
    NSString* address = nil;
    
    //item cell
    //NSTableCellView* cell = nil;
    
    //contents
    NSMutableString* contents = nil;
    
    //time stamp
    NSString* timestamp = nil;
    
    //date formatter
    static NSDateFormatter *dateFormatter = nil;
    
    //cell
    CustomTableCellView *cell = (CustomTableCellView *)[self.outlineView makeViewWithIdentifier:@"simpleCell" owner:self];
    
    //disabled?
    // set flag (for highlighting) and color
    cell.isDisabled = rule.isDisabled.boolValue;
    if (rule.isDisabled.boolValue) {
        cell.textField.textColor = NSColor.disabledControlTextColor;
    } else {
        cell.textField.textColor = NSColor.controlTextColor;
    }
    
    //reset text
    ((NSTableCellView*)cell).textField.stringValue = @"";
    ((NSTableCellView*)cell).textField.attributedStringValue = [[NSAttributedString alloc] initWithString:@""];
    
    //set endpoint addr
    address = (YES == [rule.endpointAddr isEqualToString:VALUE_ANY]) ? NSLocalizedString(@"any address",@"any address") : rule.endpointAddr;
    
    //set endpoint port
    port = (YES == [rule.endpointPort isEqualToString:VALUE_ANY]) ? NSLocalizedString(@"any port",@"any port") : rule.endpointPort;
    
    //default contents
    // address: port
    contents = [NSMutableString stringWithFormat:@"%@:%@", address, port];

    //which way this rule goes, when it doesn't go either way
    // note: an inbound and an outbound rule for the same peer looked identical, so the user
    //       couldn't tell from the list which one they were editing
    NSString* directionNote = rule.directionNote;
    if(nil != directionNote) [contents appendFormat:@" %@", directionNote];
    
    //in "recents" view, add creation timestamp
    if(RULE_TYPE_RECENT == self.selectedRuleView)
    {
        //init
        dateFormatter = [[NSDateFormatter alloc] init];
        
        //config
        [dateFormatter setDateFormat:@"yyyy-MM-dd HH:mm"];
        
        //init (formatted) timestamp
        timestamp = [NSString stringWithFormat:@" (created at: %@)", [dateFormatter stringFromDate:rule.creation]];
        
        //append
        [contents appendString:timestamp];
    }

    //set text
    cell.textField.stringValue = contents;
    
    return cell;
}

//find row for item
-(NSInteger)findRowForItem:(id)item
{
    //row
    NSInteger row = -1;
    
    //current item
    id currentItem = nil;
    
    //scan outline to find matching object
    for(NSUInteger i = 0; i < self.outlineView.numberOfRows; i++)
    {
        //extract current item
        currentItem = [self.outlineView itemAtRow:i];
        
        //looking for path?
        // only apply to item/process objects
        if( (YES == [item isKindOfClass:[NSString class]]) &&
            (YES == [currentItem isKindOfClass:[NSArray class]]) )
        {
            //paths match?
            if(YES == [item isEqualToString:((Rule*)[currentItem firstObject]).path])
            {
               //save index
               row = i;
               
               //all done
               break;
            }
        }
        
        //looking for item?
        // grab first rule from it's array and compare paths
        else if( (YES == [item isKindOfClass:[NSArray class]]) &&
                 (YES == [currentItem isKindOfClass:[NSArray class]]) )
        {
            //paths match?
            if(YES == [((Rule*)[item firstObject]).path isEqualToString:((Rule*)[currentItem firstObject]).path])
            {
               //save index
               row = i;
               
               //all done
               break;
            }
        }
        
        //looking for rule?
        else if( (YES == [item isKindOfClass:[Rule class]]) &&
                 (YES == [currentItem isKindOfClass:[Rule class]]) )
        {
            //rules match?
            if(YES == [(Rule*)item isEqualToRule:(Rule*)currentItem])
            {
               //save index
               row = i;
               
               //all done
               break;
            }
        }
        
    }//all items
    
    return row;
}

@end
