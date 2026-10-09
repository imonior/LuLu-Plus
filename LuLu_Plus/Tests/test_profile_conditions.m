//
//  file: test_profile_conditions.m
//  project: LuLu_Plus (tests)
//  description: loads the network-conditions page of the add-profile wizard, fills it in the way a
//               user does, and checks the profile conditions it writes out - plus the conversion
//               rules it is built on - in every language the fork translates
//
//  usage: test_profile_conditions <language>
//

@import Cocoa;
@import OSLog;

#import "consts.h"
#import "ProfileConditions.h"
#import "ProfileConditionsViewController.h"
#import "NetworkContext.h"

#import <objc/message.h>

//NetworkContext logs through this
os_log_t logHandle = NULL;

static NSUInteger testsRun = 0;
static NSUInteger testsFailed = 0;

static NSString* gLanguage = nil;

static void check(const char* description, BOOL condition)
{
    testsRun++;

    if(YES != condition)
    {
        testsFailed++;
        printf("  FAIL  %s\n", description);
        return;
    }

    printf("  ok    %s\n", description);

    return;
}

static BOOL isEnglish(void)
{
    return (nil == gLanguage) || (0 == [gLanguage compare:@"en"]);
}

//the add-profile sheet in Preferences.xib, and the width of the wizard's own pages
#define kSheetWidth  650.0
#define kSheetHeight 420.0

/* helpers */

//one row of the editor, as it exists while the page is being filled in: every cell present,
//        nil standing for 'the user left this one blank'
static NSMutableDictionary* editorRow(NSString* type, NSString* ssid, NSString* bssid,
                                      NSString* interfaceName, NSString* gateway)
{
    NSMutableDictionary* row = [NSMutableDictionary dictionary];

    row[KEY_CONDITION_INTERFACE_TYPE] = ((nil != type) ? type : @"");
    row[KEY_CONDITION_SSID] = ((nil != ssid) ? ssid : @"");
    row[KEY_CONDITION_BSSID] = ((nil != bssid) ? bssid : @"");
    row[KEY_CONDITION_INTERFACE] = ((nil != interfaceName) ? interfaceName : @"");
    row[KEY_CONDITION_GATEWAY] = ((nil != gateway) ? gateway : @"");

    return row;
}

//drive a control the way AppKit does, through the target and action it is wired with
static void fire(NSControl* control)
{
    id target = control.target;
    SEL action = control.action;

    if((nil == target) || (NULL == action))
    {
        check("the control is wired to something", NO);
        return;
    }

    ((void (*)(id, SEL, id))objc_msgSend)(target, action, control);

    return;
}

static BOOL wiredTo(NSControl* control, id target, SEL action)
{
    return (YES == [control.target isEqual:target]) && (control.action == action);
}

//the page, loaded the way the wizard loads it
static ProfileConditionsViewController* page(NSArray* conditionSets)
{
    ProfileConditionsViewController* controller = [[ProfileConditionsViewController alloc] init];
    controller.conditionSets = conditionSets;

    if(nil == controller.view)
    {
        check("the conditions page loaded", NO);
        return nil;
    }

    check("the conditions page loaded", YES);

    return controller;
}

//what the page says the profile should check
static NSArray* stored(ProfileConditionsViewController* controller)
{
    return [controller editedConditionSets];
}

static BOOL isLabel(NSView* view)
{
    return (YES == [view isKindOfClass:[NSTextField class]]) &&
           (YES != [(NSTextField*)view isEditable]);
}

//a label that shows one line and truncates what doesn't fit, versus running text that wraps
// note: -usesSingleLineMode: is NO for both, so the cell's wrapping is what tells them apart
static BOOL isSingleLineLabel(NSView* view)
{
    return (YES == isLabel(view)) && (YES != [(NSTextField*)view cell].wraps);
}

static BOOL isParagraphLabel(NSView* view)
{
    return (YES == isLabel(view)) && (YES == [(NSTextField*)view cell].wraps);
}

static NSRect frameIn(NSView* view, NSView* other)
{
    return [view convertRect:view.bounds toView:other];
}

//the label that belongs to a control: the one standing to its left at the same height
static NSTextField* labelFor(NSView* view, NSView* control)
{
    NSRect controlFrame = frameIn(control, view);

    for(NSView* subview in view.subviews)
    {
        if(YES != isSingleLineLabel(subview)) continue;

        NSRect frame = frameIn(subview, view);

        if(NSMaxX(frame) > controlFrame.origin.x) continue;
        if((NSMaxY(frame) <= controlFrame.origin.y) || (NSMinY(frame) >= NSMaxY(controlFrame))) continue;

        return (NSTextField*)subview;
    }

    return nil;
}

//the label furthest up the page: what the page is for, said in one line
static NSTextField* topLabel(NSView* view)
{
    NSTextField* found = nil;

    for(NSView* subview in view.subviews)
    {
        if(YES != isSingleLineLabel(subview)) continue;

        if((nil == found) || (NSMaxY(frameIn(subview, view)) > NSMaxY(frameIn(found, view))))
        {
            found = (NSTextField*)subview;
        }
    }

    return found;
}

//how much room a single-line label's text actually needs
static CGFloat neededWidth(NSTextField* label)
{
    return label.cell.cellSize.width;
}

//how much room a wrapping label needs when held to the width it was given
static CGFloat neededHeight(NSTextField* label)
{
    CGRect rect = [label.stringValue boundingRectWithSize:CGSizeMake(label.frame.size.width, CGFLOAT_MAX)
                                                 options:(NSStringDrawingUsesLineFragmentOrigin |
                                                          NSStringDrawingUsesFontLeading)
                                              attributes:@{NSFontAttributeName: label.font}
                                                 context:nil];

    return ceil(rect.size.height);
}

//print what a set of conditions actually says, so a failure can be read instead of guessed at
static void printSet(NSArray* sets)
{
    NSMutableString* text = [NSMutableString string];

    for(NSDictionary* set in sets)
    {
        NSMutableArray* parts = [NSMutableArray array];

        for(NSString* key in [ProfileConditions conditionKeys])
        {
            NSString* value = set[key];
            if(nil == value) continue;

            [parts addObject:[NSString stringWithFormat:@"%@=%@", key, value]];
        }

        [text appendFormat:@"{%@} ", [parts componentsJoinedByString:@" & "]];
    }

    printf("        -> %s\n", (0 == sets.count) ? "(no conditions)" : text.UTF8String);

    return;
}

/* the conversion rules the page is built on */

static void testConversion(void)
{
    printf("\ncondition model: rows in, sets out\n");

    NSArray* keys = [ProfileConditions conditionKeys];

    check("the editor offers the five condition keys a profile stores",
          (5 == keys.count) &&
          (YES == [keys isEqualToArray:@[KEY_CONDITION_INTERFACE_TYPE, KEY_CONDITION_SSID,
                                         KEY_CONDITION_BSSID, KEY_CONDITION_INTERFACE,
                                         KEY_CONDITION_GATEWAY]]));

    check("a path is not a network condition",
          NO == [ProfileConditions isConditionKey:KEY_PATH]);

    check("something that isn't a key isn't a condition key either",
          (NO == [ProfileConditions isConditionKey:nil]) &&
          (NO == [ProfileConditions isConditionKey:(NSString*)@7]));

    NSArray* one = [ProfileConditions conditionSetsFromRows:
                        @[editorRow(@"Wi-Fi", @"Home", nil, nil, nil)]];

    check("one filled row becomes one set naming the keys that were filled in",
          (1 == one.count) &&
          (YES == [one[0] isEqualToDictionary:@{KEY_CONDITION_INTERFACE_TYPE: @"Wi-Fi",
                                                KEY_CONDITION_SSID: @"Home"}]));

    printSet(one);

    NSArray* spaces = [ProfileConditions conditionSetsFromRows:
                          @[editorRow(@"Wi-Fi", @"   ", nil, nil, nil)]];

    check("a cell of spaces is a cell the user left blank",
          (1 == spaces.count) && (1 == [(NSDictionary*)spaces[0] count]) &&
          (nil == spaces[0][KEY_CONDITION_SSID]));

    printSet(spaces);

    check("spaces around a value are trimmed before it is stored",
          YES == [[ProfileConditions conditionSetsFromRows:
                      @[editorRow(nil, @"  Home  ", @"  aa:bb  ", nil, nil)]]
                   isEqualToArray:@[@{KEY_CONDITION_SSID: @"Home", KEY_CONDITION_BSSID: @"aa:bb"}]]);

    check("a value typed with a newline after it is stored without it",
          YES == [[ProfileConditions conditionSetsFromRows:
                      @[editorRow(nil, nil, nil, @"en0\n", nil)]]
                   isEqualToArray:@[@{KEY_CONDITION_INTERFACE: @"en0"}]]);

    check("a mac address keeps the case it was typed in, since matching is the model's business",
          YES == [[ProfileConditions conditionSetsFromRows:
                      @[editorRow(nil, nil, @"AA:BB:CC:DD:EE:FF", nil, nil)]]
                   isEqualToArray:@[@{KEY_CONDITION_BSSID: @"AA:BB:CC:DD:EE:FF"}]]);

    NSMutableDictionary* stray = editorRow(nil, @"Home", nil, nil, nil);
    stray[@"port"] = @"443";
    stray[@"path"] = @"/bin/ls";

    check("a key the conditions model doesn't understand is not written out",
          YES == [[ProfileConditions conditionSetsFromRows:@[stray]]
                   isEqualToArray:@[@{KEY_CONDITION_SSID: @"Home"}]]);

    NSMutableDictionary* notText = editorRow(nil, nil, nil, nil, nil);
    notText[KEY_CONDITION_SSID] = @7;
    notText[KEY_CONDITION_BSSID] = [NSNull null];

    check("a value that isn't text isn't written out either",
          (0 == [[ProfileConditions conditionSetsFromRows:@[notText]] count]));

    check("a row that checks nothing is dropped, not stored as a condition that can never match",
          (0 == [[ProfileConditions conditionSetsFromRows:
                     @[editorRow(nil, nil, nil, nil, nil)]] count]));

    NSArray* mixed = [ProfileConditions conditionSetsFromRows:
                          @[editorRow(nil, @"Home", nil, nil, nil),
                            editorRow(nil, nil, nil, nil, nil),
                            editorRow(@"VPN", nil, nil, nil, nil)]];

    check("a blank row between two networks doesn't take them with it",
          (2 == mixed.count) &&
          (YES == [mixed[0][KEY_CONDITION_SSID] isEqualToString:@"Home"]) &&
          (YES == [mixed[1][KEY_CONDITION_INTERFACE_TYPE] isEqualToString:@"VPN"]));

    printSet(mixed);

    NSArray* junk = [NSArray arrayWithObjects:@7, @"Home", @[KEY_CONDITION_SSID], nil];

    check("what isn't a row is dropped instead of throwing",
          (0 == [[ProfileConditions conditionSetsFromRows:junk] count]));

    check("no rows at all means no conditions",
          (0 == [[ProfileConditions conditionSetsFromRows:nil] count]) &&
          (0 == [[ProfileConditions conditionSetsFromRows:@[]] count]));
}

/* stored form -> editor form -> stored form */

static void testRoundTrip(void)
{
    printf("\ncondition model: sets in, rows out, sets out again\n");

    NSArray* storedSets = @[@{KEY_CONDITION_SSID: @"Home", KEY_CONDITION_GATEWAY: @"192.168.1.1"},
                            @{KEY_CONDITION_INTERFACE_TYPE: @"Ethernet"}];

    NSArray* rows = [ProfileConditions rowsFromConditionSets:storedSets];

    check("every key shows up in a loaded row, so the editor has somewhere to put every value",
          (2 == rows.count) && (5 == [(NSDictionary*)rows[0] count]));

    check("a key this network doesn't check loads as an empty cell",
          (0 == [rows[0][KEY_CONDITION_INTERFACE_TYPE] length]) &&
          (YES == [rows[0][KEY_CONDITION_SSID] isEqualToString:@"Home"]));

    check("loading and saving changes nothing",
          YES == [[ProfileConditions conditionSetsFromRows:rows] isEqualToArray:storedSets]);

    check("doing it twice in a row changes nothing either",
          YES == [[ProfileConditions rowsFromConditionSets:
                      [ProfileConditions conditionSetsFromRows:
                          [ProfileConditions rowsFromConditionSets:storedSets]]]
                   isEqualToArray:
                      [ProfileConditions rowsFromConditionSets:storedSets]]);

    check("a stored set that checks nothing loads as nothing to edit",
          (0 == [[ProfileConditions rowsFromConditionSets:@[@{}, @{KEY_CONDITION_SSID: @"   "}]] count]));

    check("a stored value that isn't text reads as a blank cell and isn't kept on the way out",
          (0 == [[ProfileConditions conditionSetsFromRows:
                      [ProfileConditions rowsFromConditionSets:@[@{KEY_CONDITION_SSID: @7}]]] count]));

    check("a condition the model can't read is dropped on the way in, its sibling kept",
          (1 == [[ProfileConditions rowsFromConditionSets:
                     @[@{@"port": @443, KEY_CONDITION_SSID: @"Home"}]] count]) &&
          (YES == [[ProfileConditions conditionSetsFromRows:
                        [ProfileConditions rowsFromConditionSets:
                            @[@{@"port": @443, KEY_CONDITION_SSID: @"Home"}]]]
                    isEqualToArray:@[@{KEY_CONDITION_SSID: @"Home"}]]));

    BOOL readable = YES;

    for(NSDictionary* set in [ProfileConditions conditionSetsFromRows:
                                  @[editorRow(@"Wi-Fi", @"Home", @"aa:bb", @"en0", @"10.0.0.1")]])
    {
        for(NSString* key in set) if(YES != [ProfileConditions isConditionKey:key]) readable = NO;
    }

    check("nothing the editor writes out is something the model can't read", YES == readable);
}

/* the type popup's vocabulary */

static void testTypeVocabulary(ProfileConditionsViewController* controller)
{
    printf("\nthe interface types on offer\n");

    NSPopUpButton* typePopUp = controller.typePopUp;

    check("the popup offers one choice per kind of network, plus 'no check on the type'",
          (5 == typePopUp.numberOfItems));

    NSMutableArray* offered = [NSMutableArray array];

    for(NSMenuItem* item in typePopUp.menu.itemArray)
    {
        if(nil != item.representedObject) [offered addObject:item.representedObject];
    }

    check("every choice carries the value a profile stores, not the word it shows",
          (5 == offered.count) && (YES == [offered containsObject:@"__any__"]));

    //the extension reports a type by name; a condition naming anything else can never match
    NSMutableArray* reportable = [NSMutableArray array];

    for(NSInteger type = NetworkInterfaceTypeOther; type <= NetworkInterfaceTypeVPN; type++)
    {
        [reportable addObject:[NetworkContext interfaceTypeString:(NetworkInterfaceType)type]];
    }

    BOOL everyChoiceReportable = YES;

    for(NSString* value in offered)
    {
        if(YES == [value isEqual:@"__any__"]) continue;
        if(YES != [reportable containsObject:value]) everyChoiceReportable = NO;
    }

    check("every type the page offers is one the extension can report", YES == everyChoiceReportable);

    BOOL everyReportedOffered = YES;

    for(NSString* value in reportable)
    {
        if(YES != [offered containsObject:value]) everyReportedOffered = NO;
    }

    check("every type the extension can report is one the page offers", YES == everyReportedOffered);

    NSMutableArray* titles = [NSMutableArray array];

    for(NSUInteger i = 0; i < typePopUp.numberOfItems; i++)
    {
        [titles addObject:[typePopUp itemTitleAtIndex:i]];
    }

    printf("        values = %s\n", [[offered componentsJoinedByString:@", "] UTF8String]);
    printf("        titles = %s\n", [[titles componentsJoinedByString:@", "] UTF8String]);

    check("the first choice is the one that checks nothing",
          (YES == [[typePopUp itemAtIndex:0].representedObject isEqual:@"__any__"]) &&
          (0 == typePopUp.indexOfSelectedItem));
}

/* the page: layout */

static void testLayout(ProfileConditionsViewController* controller)
{
    printf("\nthe page: layout\n");

    NSView* view = controller.view;
    NSUInteger count = view.subviews.count;

    check("the page is as wide as the wizard's sheet", (650.0 == view.frame.size.width));

    check("the page fits the room the wizard swaps its pages into",
          (view.frame.size.height >= 250.0) && (view.frame.size.height <= 330.0));

    check("the page has a control or a piece of text for everything it asks about",
          (16 == count));

    //a control that was built but never put on the page works in a test and is invisible to a user
    NSView* onThePage[8] = {controller.networksPopUp, controller.addButton, controller.removeButton,
                            controller.typePopUp, controller.ssidField, controller.bssidField,
                            controller.interfaceField, controller.gatewayField};

    const char* onThePageNames[8] = {"the network list", "the + button", "the - button",
                                     "the type popup", "the network name field",
                                     "the router address field", "the interface field",
                                     "the gateway field"};

    for(int i = 0; i < 8; i++)
    {
        char what[160];
        snprintf(what, sizeof(what), "%s is on the page", onThePageNames[i]);

        check(what, (nil != onThePage[i]) && (YES == [view.subviews containsObject:onThePage[i]]));
    }

    NSUInteger singleLine = 0;
    NSUInteger paragraphs = 0;

    for(NSView* subview in view.subviews)
    {
        if(YES == isSingleLineLabel(subview)) singleLine++;
        else if(YES == isParagraphLabel(subview)) paragraphs++;
    }

    //counted rather than assumed: a check that walks the wrong set of views passes for nothing
    check("the page shows five field labels and a title in one line each", (6 == singleLine));
    check("the page explains itself in two blocks of running text", (2 == paragraphs));

    BOOL inside = YES;

    for(NSView* subview in view.subviews)
    {
        if(YES != NSContainsRect(view.bounds, frameIn(subview, view))) inside = NO;
    }

    check("every control sits inside the page", YES == inside);

    BOOL overlap = NO;

    for(NSUInteger i = 0; i < count; i++)
    {
        NSView* a = view.subviews[i];
        NSRect ra = frameIn(a, view);

        for(NSUInteger j = (i + 1); j < count; j++)
        {
            NSView* b = view.subviews[j];

            if(YES == NSIsEmptyRect(NSIntersectionRect(ra, frameIn(b, view)))) continue;

            overlap = YES;
            printf("        overlapping: %s and %s\n", a.className.UTF8String, b.className.UTF8String);
        }
    }

    check("no two controls overlap", NO == overlap);

    NSView* controls[5] = {controller.typePopUp, controller.ssidField, controller.bssidField,
                           controller.interfaceField, controller.gatewayField};

    const char* names[5] = {"type", "network name", "router address", "interface", "gateway"};

    for(int i = 0; i < 5; i++)
    {
        char what[160];

        NSTextField* label = labelFor(view, controls[i]);

        snprintf(what, sizeof(what), "the %s field has a label beside it", names[i]);
        check(what, nil != label);

        if(nil == label) continue;

        snprintf(what, sizeof(what), "the %s label has room for the word it shows", names[i]);
        check(what, (neededWidth(label) <= (label.frame.size.width + 1.0)));

        snprintf(what, sizeof(what), "the %s label stops before the field it belongs to", names[i]);
        check(what, (NSMaxX(frameIn(label, view)) <= frameIn(controls[i], view).origin.x));

        printf("        %-14s '%s' needs %.0f pt, has %.0f\n", names[i],
               label.stringValue.UTF8String, neededWidth(label), label.frame.size.width);
    }

    BOOL paragraphsFit = YES;

    for(NSView* subview in view.subviews)
    {
        if(YES != isParagraphLabel(subview)) continue;

        NSTextField* label = (NSTextField*)subview;

        if(neededHeight(label) > (label.frame.size.height + 1.0))
        {
            paragraphsFit = NO;
            printf("        clipped: '%s' needs %.0f pt, has %.0f\n",
                   label.stringValue.UTF8String, neededHeight(label), label.frame.size.height);
        }
    }

    check("the paragraphs on the page fit the band they are given", YES == paragraphsFit);
}

/* the page: switching between networks while typing */

static void testSwitching(void)
{
    printf("\nthe page: switching networks\n");

    ProfileConditionsViewController* controller = page(nil);
    if(nil == controller) return;

    //two networks saying nothing yet: the list has to show both of them, and it can only do that if
    //    it doesn't hand out one entry per *title* (see -refreshList)
    fire(controller.addButton);

    check("two blank networks are on the page to write down",
          (2 == controller.networksPopUp.numberOfItems));

    if(2 != controller.networksPopUp.numberOfItems)
    {
        printf("        (the rest of the section was skipped: it needs the second network)\n");
        return;
    }

    NSString* blankName = NSLocalizedString(@"New network", @"New network");

    check("and neither of them has been left off the list for saying the same as the other",
          YES == [controller.networksPopUp.itemTitles isEqualToArray:@[blankName, blankName]]);

    fire(controller.addButton);

    check("pressing + on a page whose networks all say the same still adds one",
          (3 == controller.networksPopUp.numberOfItems));

    check("and it is the newest of them the fields are showing",
          (2 == controller.networksPopUp.indexOfSelectedItem) &&
          (YES == [controller.networksPopUp.itemTitles isEqualToArray:
                       @[blankName, blankName, blankName]]));

    fire(controller.removeButton);

    check("and - takes one of them back off", (2 == controller.networksPopUp.numberOfItems));

    //start at the first one
    [controller.networksPopUp selectItemAtIndex:0];
    fire(controller.networksPopUp);

    //type into it, then move the list before the field has finished editing
    controller.ssidField.stringValue = @"Home";

    [controller.networksPopUp selectItemAtIndex:1];
    fire(controller.networksPopUp);

    check("switching networks writes down what was being typed into the one being left",
          YES == [controller.networksPopUp.itemTitles[0] containsString:@"Home"]);

    check("the network being switched to shows as the blank it is",
          (0 == controller.ssidField.stringValue.length));

    check("and only the network that was filled in is what the profile will check",
          YES == [stored(controller) isEqualToArray:@[@{KEY_CONDITION_SSID: @"Home"}]]);

    //back to the one the value was typed into
    [controller.networksPopUp selectItemAtIndex:0];
    fire(controller.networksPopUp);

    check("the network that was left still holds what was typed into it",
          YES == [controller.ssidField.stringValue isEqualToString:@"Home"]);

    //changing it replaces what that network said, instead of leaving the old value in the row
    controller.ssidField.stringValue = @"Cafe";

    [controller.networksPopUp selectItemAtIndex:1];
    fire(controller.networksPopUp);

    check("changing a network replaces what it said instead of adding a second network",
          YES == [stored(controller) isEqualToArray:@[@{KEY_CONDITION_SSID: @"Cafe"}]]);

    //the network thrown away is the one on show: type into the second one and remove it
    controller.ssidField.stringValue = @"Work";

    fire(controller.removeButton);

    check("the - button takes the network on show, not whichever one comes first",
          YES == [stored(controller) isEqualToArray:@[@{KEY_CONDITION_SSID: @"Cafe"}]]);

    check("and what was being typed into it goes with it",
          (1 == controller.networksPopUp.numberOfItems) &&
          (YES == [controller.ssidField.stringValue isEqualToString:@"Cafe"]));
}

/* the page: swapped into the wizard the way the wizard swaps pages */

//move the page to the top of the sheet and uncheck every button on it, which is what
//        -continueProfileButtonHandler: does to every page it shows
//        (PrefsWindowController+ProfileWizard.m)
static void wizardSwapIn(ProfileConditionsViewController* controller)
{
    NSView* view = controller.view;

    NSRect frame = view.frame;
    frame.origin.x = 0;
    frame.origin.y = (kSheetHeight - frame.size.height);
    view.frame = frame;

    for(NSView* subview in view.subviews)
    {
        if(YES != [subview isKindOfClass:[NSButton class]]) continue;

        NSButton* button = (NSButton*)subview;
        if((YES == button.allowsMixedState) || (NSControlStateValueOff != button.state))
        {
            button.state = NSControlStateValueOff;
        }
    }

    return;
}

static void testWizardSwap(void)
{
    printf("\nthe page inside the wizard\n");

    ProfileConditionsViewController* controller = page(nil);
    if(nil == controller) return;

    wizardSwapIn(controller);

    NSView* view = controller.view;

    check("the page still fits the wizard's sheet after being moved into it",
          (650.0 == view.frame.size.width) && (NSMaxY(view.frame) <= kSheetHeight) &&
          (NSMinY(view.frame) >= 0.0));

    check("the controls are still where the page put them",
          (YES == NSContainsRect(view.bounds, frameIn(controller.gatewayField, view))));

    //fill it in the way a user does, after the wizard has shown it
    NSInteger wifiIndex = [controller.typePopUp indexOfItemWithRepresentedObject:@"Wi-Fi"];

    [controller.typePopUp selectItemAtIndex:wifiIndex];
    fire(controller.typePopUp);

    controller.ssidField.stringValue = @"Home";
    fire(controller.ssidField);

    check("the wizard unchecking the buttons on a page doesn't take the type picked with it",
          YES == [[controller.typePopUp itemAtIndex:controller.typePopUp.indexOfSelectedItem]
                    .representedObject isEqual:@"Wi-Fi"]);

    check("and the network written down stays written down",
          YES == [stored(controller) isEqualToArray:
                     @[@{KEY_CONDITION_INTERFACE_TYPE: @"Wi-Fi", KEY_CONDITION_SSID: @"Home"}]]);

    printSet(stored(controller));

    //the paranoid case: the same sweep happening after the page has been filled in
    wizardSwapIn(controller);

    check("even a second sweep leaves what the user wrote alone",
          (1 == controller.networksPopUp.numberOfItems) &&
          (YES == [stored(controller) isEqualToArray:
                      @[@{KEY_CONDITION_INTERFACE_TYPE: @"Wi-Fi", KEY_CONDITION_SSID: @"Home"}]]));
}

/* the page: filled in by hand */

static void testEditing(void)
{
    printf("\nthe page: filling it in\n");

    ProfileConditionsViewController* controller = page(nil);
    if(nil == controller) return;

    check("a new profile starts with one blank network to write down",
          (1 == controller.networksPopUp.numberOfItems));

    check("an untouched page writes no conditions", (0 == [stored(controller) count]));

    controller.ssidField.stringValue = @"Home";
    fire(controller.ssidField);

    check("a network name typed in is written as a condition",
          YES == [stored(controller) isEqualToArray:@[@{KEY_CONDITION_SSID: @"Home"}]]);

    NSInteger wifiIndex = [controller.typePopUp indexOfItemWithRepresentedObject:@"Wi-Fi"];
    check("the page can pick a type by the value it stores", (wifiIndex >= 0));

    [controller.typePopUp selectItemAtIndex:wifiIndex];
    fire(controller.typePopUp);

    check("a type picked next to a name is written as a second key of the same condition",
          YES == [stored(controller) isEqualToArray:
                     @[@{KEY_CONDITION_INTERFACE_TYPE: @"Wi-Fi", KEY_CONDITION_SSID: @"Home"}]]);

    printSet(stored(controller));

    [controller.typePopUp selectItemAtIndex:0];
    fire(controller.typePopUp);

    check("choosing 'Any' writes no type condition at all",
          YES == [stored(controller) isEqualToArray:@[@{KEY_CONDITION_SSID: @"Home"}]]);

    printSet(stored(controller));

    fire(controller.addButton);

    check("the + button adds a network to the list", (2 == controller.networksPopUp.numberOfItems));

    check("adding a network keeps the one being edited",
          YES == [stored(controller) isEqualToArray:@[@{KEY_CONDITION_SSID: @"Home"}]]);

    controller.ssidField.stringValue = @"Office";
    fire(controller.ssidField);
    controller.gatewayField.stringValue = @"10.0.0.1";
    fire(controller.gatewayField);

    check("two fields of one network are both written, so both have to match",
          YES == [stored(controller) isEqualToArray:
                     @[@{KEY_CONDITION_SSID: @"Home"},
                       @{KEY_CONDITION_SSID: @"Office", KEY_CONDITION_GATEWAY: @"10.0.0.1"}]]);

    printSet(stored(controller));

    check("the list says which networks are in it",
          (YES == [controller.networksPopUp.itemTitles[0] containsString:@"Home"]) &&
          (YES == [controller.networksPopUp.itemTitles[1] containsString:@"Office"]));

    [controller.networksPopUp selectItemAtIndex:0];
    fire(controller.networksPopUp);

    check("switching networks shows the network that was picked",
          (YES == [controller.ssidField.stringValue isEqualToString:@"Home"]) &&
          (0 == controller.gatewayField.stringValue.length));

    controller.interfaceField.stringValue = @"en0";
    fire(controller.interfaceField);

    check("editing a network changes that network, not the one that was selected before it",
          YES == [stored(controller) isEqualToArray:
                     @[@{KEY_CONDITION_SSID: @"Home", KEY_CONDITION_INTERFACE: @"en0"},
                       @{KEY_CONDITION_SSID: @"Office", KEY_CONDITION_GATEWAY: @"10.0.0.1"}]]);

    printSet(stored(controller));

    [controller.networksPopUp selectItemAtIndex:1];
    fire(controller.networksPopUp);

    check("what was written down for a network survives being switched away from and back",
          (YES == [controller.ssidField.stringValue isEqualToString:@"Office"]) &&
          (YES == [controller.gatewayField.stringValue isEqualToString:@"10.0.0.1"]));

    fire(controller.removeButton);

    check("the - button removes the network being looked at",
          YES == [stored(controller) isEqualToArray:
                     @[@{KEY_CONDITION_SSID: @"Home", KEY_CONDITION_INTERFACE: @"en0"}]]);

    fire(controller.removeButton);

    check("removing the only network leaves nothing checked but the page still usable",
          (0 == [stored(controller) count]) && (1 == controller.networksPopUp.numberOfItems));

    //a field that hasn't finished editing yet: -addNetwork: commits the row being shown before it
    //        makes a new one, and a user who clicks + straight on the keyboard never ends editing
    controller.ssidField.stringValue = @"Cafe";
    controller.gatewayField.stringValue = @"10.1.1.1";

    fire(controller.addButton);

    check("pressing + commits what is still being typed into the network shown",
          YES == [controller.networksPopUp.itemTitles[0] containsString:@"Cafe"]);

    check("and that is what the profile ends up checking",
          YES == [stored(controller) isEqualToArray:
                     @[@{KEY_CONDITION_SSID: @"Cafe", KEY_CONDITION_GATEWAY: @"10.1.1.1"}]]);

    check("the network + adds starts blank, whatever was being typed",
          (2 == controller.networksPopUp.numberOfItems) &&
          (0 == controller.ssidField.stringValue.length) &&
          (0 == controller.gatewayField.stringValue.length));

    printSet(stored(controller));
}

/* the page: loaded from a profile that already has conditions */

static void testLoading(void)
{
    printf("\nthe page: what a profile already had\n");

    NSArray* conditionSets = @[@{KEY_CONDITION_INTERFACE_TYPE: @"VPN"},
                               @{KEY_CONDITION_SSID: @"Cafe", KEY_CONDITION_BSSID: @"aa:bb:cc:dd:ee:ff"}];

    ProfileConditionsViewController* controller = page(conditionSets);
    if(nil == controller) return;

    check("every network the profile had is on the page", (2 == controller.networksPopUp.numberOfItems));

    check("the page writes them back out unchanged when nothing is edited",
          YES == [stored(controller) isEqualToArray:conditionSets]);

    [controller.networksPopUp selectItemAtIndex:1];
    fire(controller.networksPopUp);

    check("a stored network's fields come back as they were stored",
          (YES == [controller.ssidField.stringValue isEqualToString:@"Cafe"]) &&
          (YES == [controller.bssidField.stringValue isEqualToString:@"aa:bb:cc:dd:ee:ff"]));

    check("a key the stored network doesn't check shows as an empty field",
          (0 == controller.gatewayField.stringValue.length));

    ProfileConditionsViewController* unknown = page(@[@{KEY_CONDITION_INTERFACE_TYPE: @"Token"}]);

    check("a type this build doesn't know reads as 'Any'",
          (nil != unknown) && (0 == unknown.typePopUp.indexOfSelectedItem));

    check("and it is not written back as a condition the profile can never match",
          (nil != unknown) && (0 == [stored(unknown) count]));

    ProfileConditionsViewController* handEdited = page(@[@{@"port": @443}]);

    check("a hand-edited condition the page can't show isn't quietly kept",
          (nil != handEdited) && (0 == [stored(handEdited) count]));

    ProfileConditionsViewController* notLoaded = [[ProfileConditionsViewController alloc] init];
    notLoaded.conditionSets = conditionSets;

    check("a page that was never shown hands back the conditions it was handed",
          YES == [[notLoaded editedConditionSets] isEqualToArray:conditionSets]);

    NSView* loadedPage = notLoaded.view;

    check("loading the page after being handed conditions puts them on it",
          (nil != loadedPage) && (2 == notLoaded.networksPopUp.numberOfItems) &&
          (YES == [[notLoaded editedConditionSets] isEqualToArray:conditionSets]));

    ProfileConditionsViewController* replaced = page(nil);

    if(nil != replaced)
    {
        replaced.conditionSets = conditionSets;

        check("being handed new conditions after it is shown reloads the page",
              (2 == replaced.networksPopUp.numberOfItems));
    }
}

/* the page: wired the way its buttons say they are */

static void testWiring(ProfileConditionsViewController* controller)
{
    printf("\nthe page: wiring\n");

    check("the + button adds a network",
          YES == wiredTo(controller.addButton, controller, @selector(addNetwork:)));

    check("the - button removes one",
          YES == wiredTo(controller.removeButton, controller, @selector(removeNetwork:)));

    check("picking a network in the list shows it",
          YES == wiredTo(controller.networksPopUp, controller, @selector(networkChanged:)));

    check("the type popup commits to the network being edited",
          YES == wiredTo(controller.typePopUp, controller, @selector(conditionFieldChanged:)));

    check("typing in the network name commits it",
          YES == wiredTo(controller.ssidField, controller, @selector(conditionFieldChanged:)));

    check("typing in the router address commits it",
          YES == wiredTo(controller.bssidField, controller, @selector(conditionFieldChanged:)));

    check("typing in the interface commits it",
          YES == wiredTo(controller.interfaceField, controller, @selector(conditionFieldChanged:)));

    check("typing in the gateway commits it",
          YES == wiredTo(controller.gatewayField, controller, @selector(conditionFieldChanged:)));

    check("a field commits when editing ends, not on every keystroke",
          (YES == controller.ssidField.cell.sendsActionOnEndEditing) &&
          (YES == controller.gatewayField.cell.sendsActionOnEndEditing));
}

/* the page: in the language it is shown in */

static void testLanguage(ProfileConditionsViewController* controller)
{
    printf("\nthe page in %s\n", (nil != gLanguage) ? gLanguage.UTF8String : "system");

    NSArray* canonical = @[KEY_INTERFACE_TYPE_WIFI, KEY_INTERFACE_TYPE_ETHERNET,
                           KEY_INTERFACE_TYPE_VPN, KEY_INTERFACE_TYPE_OTHER];

    NSMutableArray* values = [NSMutableArray array];
    NSMutableArray* titles = [NSMutableArray array];

    for(NSUInteger i = 1; i < controller.typePopUp.numberOfItems; i++)
    {
        [values addObject:[controller.typePopUp itemAtIndex:i].representedObject];
        [titles addObject:[controller.typePopUp itemTitleAtIndex:i]];
    }

    check("the values stored stay the ones the extension compares, whatever the language",
          YES == [values isEqualToArray:canonical]);

    BOOL titlesAsExpected = YES;

    for(NSUInteger i = 0; i < canonical.count; i++)
    {
        NSString* value = canonical[i];
        NSString* title = titles[i];

        if(YES == isEnglish())
        {
            if(0 != [title compare:value]) titlesAsExpected = NO;
            continue;
        }

        //Wi-Fi and VPN are written the same way in the languages the fork translates
        BOOL sameEverywhere = (YES == [value isEqualToString:KEY_INTERFACE_TYPE_WIFI]) ||
                              (YES == [value isEqualToString:KEY_INTERFACE_TYPE_VPN]);

        if((YES != sameEverywhere) && (0 == [title compare:value])) titlesAsExpected = NO;
    }

    if(YES == isEnglish())
    {
        check("in English the choices are the names themselves", YES == titlesAsExpected);
        return;
    }

    check("the choices are translated, apart from the names written the same everywhere",
          YES == titlesAsExpected);

    //picking a translated choice must still write the name the extension compares
    NSInteger ethernetIndex = [controller.typePopUp indexOfItemWithRepresentedObject:@"Ethernet"];
    [controller.typePopUp selectItemAtIndex:ethernetIndex];
    fire(controller.typePopUp);

    NSArray* picked = stored(controller);
    BOOL storedCanonical = (1 == picked.count) &&
                           (YES == [picked[0][KEY_CONDITION_INTERFACE_TYPE]
                                     isEqualToString:@"Ethernet"]);

    check("the type that gets stored is still the English name the extension compares",
          YES == storedCanonical);

    //put the page back the way it was found, so the checks after this one read a blank network
    [controller.typePopUp selectItemAtIndex:0];
    fire(controller.typePopUp);

    printf("        titles = %s\n", [[titles componentsJoinedByString:@", "] UTF8String]);

    NSTextField* ssidLabel = labelFor(controller.view, controller.ssidField);
    NSTextField* typeLabel = labelFor(controller.view, controller.typePopUp);

    check("the label beside the network name is translated",
          (nil != ssidLabel) && (0 != [ssidLabel.stringValue compare:@"Network name (SSID)"]));

    check("the label beside the type is translated",
          (nil != typeLabel) && (0 != [typeLabel.stringValue compare:@"Type"]));

    NSTextField* intro = topLabel(controller.view);

    check("the page says what it is for in the language it is shown in",
          (nil != intro) &&
          (0 != [intro.stringValue compare:@"Only use this profile on some networks"]) &&
          (YES == [intro.stringValue containsString:@"配置文件"]));

    printf("        title = %s\n", (nil != intro) ? intro.stringValue.UTF8String : "(none)");

    check("a network with nothing written down is named in the language it is shown in",
          (0 != [controller.networksPopUp.itemTitles[0] compare:@"New network"]));

    check("the hint under a field is translated too",
          (0 != [controller.interfaceField.placeholderString compare:@"for example: en0"]));

    //the page has to show the translated explanation, not just have one in the catalog
    NSString* combined = NSLocalizedString(@"Within one network, every field you fill in has to "
                                            @"match. Each network in the list is an alternative.", @"");

    BOOL noteOnPage = NO;

    for(NSView* subview in controller.view.subviews)
    {
        if(YES != isParagraphLabel(subview)) continue;

        if(0 == [((NSTextField*)subview).stringValue compare:combined]) noteOnPage = YES;
    }

    check("the explanation of how the fields combine is on the page in the same language",
          YES == noteOnPage);
}

/* MAIN */

int main(int argc, const char* argv[])
{
    @autoreleasepool
    {
        if(argc < 2)
        {
            fprintf(stderr, "usage: %s <language>\n", argv[0]);
            return 2;
        }

        gLanguage = @(argv[1]);
        logHandle = os_log_create("com.imonior.lulu-plus", "tests");

        //pick the language in-process: the environment is only honored by a launched app
        [[NSUserDefaults standardUserDefaults] setObject:@[gLanguage] forKey:@"AppleLanguages"];

        printf("== profile network conditions (%s) ==\n", gLanguage.UTF8String);

        testConversion();
        testRoundTrip();

        ProfileConditionsViewController* controller = page(nil);

        if(nil != controller)
        {
            testTypeVocabulary(controller);
            testLayout(controller);
            testWiring(controller);
        }

        testEditing();
        testLoading();
        testSwitching();
        testWizardSwap();

        if(nil != controller) testLanguage(controller);

        printf("\n%lu/%lu checks passed\n", (unsigned long)(testsRun - testsFailed),
               (unsigned long)testsRun);

        if(0 != testsFailed)
        {
            printf("FAILED: %lu check(s)\n", (unsigned long)testsFailed);
            return 1;
        }

        printf("All checks passed\n");
    }

    return 0;
}
