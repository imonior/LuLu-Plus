//
//  ProfileConditionsViewController.m
//  project: LuLu_Plus (app)
//  description: see ProfileConditionsViewController.h
//

#import "ProfileConditionsViewController.h"
#import "ProfileConditions.h"
#import "consts.h"

//the wizard's sheet is 650 wide; the page keeps a margin and gives every field the same left edge
#define kPageWidth       650.0
#define kPageHeight      330.0
#define kMargin          24.0
#define kFieldLeft       200.0
#define kFieldWidth      402.0

//what the type popup shows for 'the kind of network says nothing here'
#define kTypeAny         @"__any__"

@implementation ProfileConditionsViewController
{
    //one entry per network the profile can adopt, each carrying every condition key as a string
    NSMutableArray* networks;

    //which of them the fields are showing: the list's own selection has already moved on by the
    //        time its action runs, so the row a commit belongs to has to be remembered here
    NSUInteger shownNetwork;
}

@synthesize conditionSets = _conditionSets;

-(void)loadView
{
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, kPageWidth, kPageHeight)];

    CGFloat top = kPageHeight;

    //what this page is for
    NSTextField* intro = [NSTextField labelWithString:NSLocalizedString(@"Only use this profile on some networks", @"Only use this profile on some networks")];
    intro.font = [NSFont boldSystemFontOfSize:13];
    intro.frame = NSMakeRect(kMargin, (top - 30), (kPageWidth - (2 * kMargin)), 17);
    [self.view addSubview:intro];

    NSTextField* help = [NSTextField wrappingLabelWithString:NSLocalizedString(@"The profile is switched on by itself when this mac is on one of these networks. Leave the list empty to use the profile whatever the network is.", @"The profile is switched on by itself when this mac is on one of these networks. Leave the list empty to use the profile whatever the network is.")];
    help.font = [NSFont systemFontOfSize:11 weight:NSFontWeightRegular];
    help.preferredMaxLayoutWidth = (kPageWidth - (2 * kMargin));
    help.frame = NSMakeRect(kMargin, (top - 70), (kPageWidth - (2 * kMargin)), 34);
    [self.view addSubview:help];

    //the networks the profile knows about, and the two buttons that change how many there are
    self.networksPopUp = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(kMargin, (top - 104), 480, 26) pullsDown:NO];
    self.networksPopUp.target = self;
    self.networksPopUp.action = @selector(networkChanged:);
    [self.view addSubview:self.networksPopUp];

    self.addButton = [NSButton buttonWithTitle:@"+" target:self action:@selector(addNetwork:)];
    self.addButton.frame = NSMakeRect(510, (top - 104), 44, 25);
    self.addButton.toolTip = NSLocalizedString(@"Add a network", @"Add a network");
    [self.view addSubview:self.addButton];

    self.removeButton = [NSButton buttonWithTitle:@"-" target:self action:@selector(removeNetwork:)];
    self.removeButton.frame = NSMakeRect(558, (top - 104), 44, 25);
    self.removeButton.toolTip = NSLocalizedString(@"Remove this network", @"Remove this network");
    [self.view addSubview:self.removeButton];

    //the fields of the network chosen above; a blank field is one this network doesn't check
    [self addFieldLabel:NSLocalizedString(@"Type", @"Type") atY:196];

    self.typePopUp = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(kFieldLeft, 194, 200, 25) pullsDown:NO];
    self.typePopUp.target = self;
    self.typePopUp.action = @selector(conditionFieldChanged:);
    [self.view addSubview:self.typePopUp];

    // note: the choices are added through the menu, not -[NSPopUpButton addItemWithTitle:]: that one
    //       drops a title the popup already shows, and a title here is a translated word, so two kinds
    //       of network translated the same way would cost the page a choice
    NSMenuItem* any = [self.typePopUp.menu addItemWithTitle:NSLocalizedString(@"Any", @"Any")
                                                     action:NULL keyEquivalent:@""];
    any.representedObject = kTypeAny;

    // note: these are the values a profile stores, not just the words the popup shows - the
    //       extension compares them verbatim (see +[NetworkContext interfaceTypeString:])
    for(NSString* type in @[KEY_INTERFACE_TYPE_WIFI, KEY_INTERFACE_TYPE_ETHERNET,
                            KEY_INTERFACE_TYPE_VPN, KEY_INTERFACE_TYPE_OTHER])
    {
        NSMenuItem* item = [self.typePopUp.menu addItemWithTitle:NSLocalizedString(type, type)
                                                          action:NULL keyEquivalent:@""];
        item.representedObject = type;
    }

    [self addFieldLabel:NSLocalizedString(@"Network name (SSID)", @"Network name (SSID)") atY:168];
    self.ssidField = [self addFieldAtY:166 placeholder:NSLocalizedString(@"for example: Home", @"for example: Home")];

    [self addFieldLabel:NSLocalizedString(@"Router address (BSSID)", @"Router address (BSSID)") atY:140];
    self.bssidField = [self addFieldAtY:138 placeholder:NSLocalizedString(@"for example: aa:bb:cc:dd:ee:ff", @"for example: aa:bb:cc:dd:ee:ff")];

    [self addFieldLabel:NSLocalizedString(@"Interface", @"Interface") atY:112];
    self.interfaceField = [self addFieldAtY:110 placeholder:NSLocalizedString(@"for example: en0", @"for example: en0")];

    [self addFieldLabel:NSLocalizedString(@"Gateway address", @"Gateway address") atY:84];
    self.gatewayField = [self addFieldAtY:82 placeholder:NSLocalizedString(@"for example: 192.168.1.1", @"for example: 192.168.1.1")];

    //how one entry is read
    NSTextField* note = [NSTextField wrappingLabelWithString:NSLocalizedString(@"Within one network, every field you fill in has to match. Each network in the list is an alternative.", @"Within one network, every field you fill in has to match. Each network in the list is an alternative.")];
    note.font = [NSFont systemFontOfSize:11 weight:NSFontWeightRegular];
    note.textColor = NSColor.secondaryLabelColor;
    note.preferredMaxLayoutWidth = (kPageWidth - (2 * kMargin));
    note.frame = NSMakeRect(kMargin, 30, (kPageWidth - (2 * kMargin)), 34);
    [self.view addSubview:note];

    //whatever the profile already had written down (the wizard may set this before or after the
    //    page is loaded, so both orders have to end up in the same place)
    [self applyConditionSets:_conditionSets];

    return;
}

#pragma mark – building blocks

-(NSTextField*)addFieldLabel:(NSString*)text atY:(CGFloat)y
{
    NSTextField* label = [NSTextField labelWithString:text];
    label.alignment = NSTextAlignmentRight;
    label.frame = NSMakeRect(kMargin, (y + 3), ((kFieldLeft - kMargin) - 10), 17);

    [self.view addSubview:label];

    return label;
}

-(NSTextField*)addFieldAtY:(CGFloat)y placeholder:(NSString*)placeholder
{
    NSTextField* field = [[NSTextField alloc] initWithFrame:NSMakeRect(kFieldLeft, y, kFieldWidth, 22)];
    field.placeholderString = placeholder;
    field.target = self;
    field.action = @selector(conditionFieldChanged:);
    field.cell.sendsActionOnEndEditing = YES;

    [self.view addSubview:field];

    return field;
}

-(NSMutableDictionary*)blankNetwork
{
    NSMutableDictionary* network = [NSMutableDictionary dictionary];

    for(NSString* key in [ProfileConditions conditionKeys]) network[key] = @"";

    return network;
}

#pragma mark – the list

//the line the list shows for one network
-(NSString*)summaryForNetwork:(NSDictionary*)network
{
    NSMutableArray* parts = [NSMutableArray array];

    NSString* type = network[KEY_CONDITION_INTERFACE_TYPE];
    if(0 != type.length) [parts addObject:type];

    for(NSString* key in @[KEY_CONDITION_SSID, KEY_CONDITION_BSSID,
                           KEY_CONDITION_INTERFACE, KEY_CONDITION_GATEWAY])
    {
        NSString* value = network[key];
        if(0 != value.length) [parts addObject:value];
    }

    if(0 == parts.count) return NSLocalizedString(@"New network", @"New network");

    return [parts componentsJoinedByString:@" / "];
}

//rebuild the list from what is being edited
-(void)refreshList
{
    [self.networksPopUp removeAllItems];

    NSMenu* menu = self.networksPopUp.menu;

    // note: the items go in through the menu, not -addItemWithTitle:, because that one refuses a title
    //       the list already shows - and two networks can genuinely read the same, since every blank
    //       one reads 'New network'. Added through the title they vanished instead, so pressing +
    //       twice on a fresh page left one network on the list while the page thought there were two
    for(NSDictionary* network in networks)
    {
        [menu addItemWithTitle:[self summaryForNetwork:network] action:NULL keyEquivalent:@""];
    }

    return;
}

//which network the list is pointing at
-(NSUInteger)pickedNetwork
{
    NSInteger selected = self.networksPopUp.indexOfSelectedItem;

    return (selected < 0) ? 0 : (NSUInteger)selected;
}

//show one network's values in the fields
-(void)showNetwork:(NSUInteger)index
{
    if(0 == networks.count) return;

    if(index >= networks.count) index = (networks.count - 1);

    NSDictionary* network = networks[index];
    NSString* type = network[KEY_CONDITION_INTERFACE_TYPE];

    if(0 == type.length) type = kTypeAny;

    //an interface type this build doesn't know (a hand-edited plist) has no place in the popup,
    //        so it reads as 'any' and is written back as no condition at all
    NSInteger typeIndex = [self.typePopUp indexOfItemWithRepresentedObject:type];
    [self.typePopUp selectItemAtIndex:(typeIndex < 0) ? 0 : typeIndex];
    self.ssidField.stringValue = network[KEY_CONDITION_SSID];
    self.bssidField.stringValue = network[KEY_CONDITION_BSSID];
    self.interfaceField.stringValue = network[KEY_CONDITION_INTERFACE];
    self.gatewayField.stringValue = network[KEY_CONDITION_GATEWAY];

    [self.networksPopUp selectItemAtIndex:(NSInteger)index];

    //the fields now say what this network says
    shownNetwork = index;

    return;
}

//write the fields back into the network they belong to
-(void)commitFields
{
    NSUInteger index = shownNetwork;
    if(index >= networks.count) return;

    NSMutableDictionary* network = networks[index];

    NSString* type = [self.typePopUp selectedItem].representedObject;
    network[KEY_CONDITION_INTERFACE_TYPE] = ((nil == type) || (0 == [type compare:kTypeAny])) ? @"" : type;

    network[KEY_CONDITION_SSID] = self.ssidField.stringValue;
    network[KEY_CONDITION_BSSID] = self.bssidField.stringValue;
    network[KEY_CONDITION_INTERFACE] = self.interfaceField.stringValue;
    network[KEY_CONDITION_GATEWAY] = self.gatewayField.stringValue;

    //the list entry is meant to say what the fields now say
    [self.networksPopUp itemAtIndex:(NSInteger)index].title = [self summaryForNetwork:network];

    return;
}

//start from the conditions a profile stores (or from one blank network)
-(void)applyConditionSets:(NSArray*)sets
{
    networks = [NSMutableArray array];

    for(NSDictionary* row in [ProfileConditions rowsFromConditionSets:sets])
    {
        NSMutableDictionary* network = [self blankNetwork];

        for(NSString* key in [ProfileConditions conditionKeys]) network[key] = row[key];

        [networks addObject:network];
    }

    //there is always something to type into
    if(0 == networks.count) [networks addObject:[self blankNetwork]];

    [self refreshList];
    [self showNetwork:0];

    return;
}

#pragma mark – actions

-(void)conditionFieldChanged:(id)sender
{
    [self commitFields];

    return;
}

-(void)networkChanged:(id)sender
{
    //the list has already moved on to the network being switched to, while the fields still hold
    //        the one being left: write it down first, or switching loses whatever is being typed
    [self commitFields];

    [self showNetwork:[self pickedNetwork]];

    return;
}

-(void)addNetwork:(id)sender
{
    [self commitFields];

    [networks addObject:[self blankNetwork]];

    [self refreshList];
    [self showNetwork:(networks.count - 1)];

    [[self.view window] makeFirstResponder:self.ssidField];

    return;
}

-(void)removeNetwork:(id)sender
{
    //the network being looked at, which is the one the fields are showing (and deliberately not
    //        committed first: what is in the fields is what the user has just thrown away)
    NSUInteger index = shownNetwork;
    if(index >= networks.count) return;

    [networks removeObjectAtIndex:index];

    //removing the last one leaves the profile with no conditions, but the page still needs a
    //    network on show, so it goes back to a blank one
    if(0 == networks.count) [networks addObject:[self blankNetwork]];

    [self refreshList];

    if(index >= networks.count) index = (networks.count - 1);
    [self showNetwork:index];

    return;
}

#pragma mark – stored form

-(NSArray<NSDictionary*>*)editedConditionSets
{
    //a page that was never shown has nothing to commit, so it gives back what it was handed
    if(YES != self.isViewLoaded) return _conditionSets;

    [self commitFields];

    return [ProfileConditions conditionSetsFromRows:networks];
}

-(void)setConditionSets:(NSArray<NSDictionary*>*)conditionSets
{
    _conditionSets = [conditionSets copy];

    //the fields only exist once the view has loaded; -loadView: picks the value up from there
    if(YES == self.isViewLoaded) [self applyConditionSets:_conditionSets];

    return;
}

-(NSArray<NSDictionary*>*)conditionSets
{
    return _conditionSets;
}

@end
