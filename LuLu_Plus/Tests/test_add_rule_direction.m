//
//  file: test_add_rule_direction.m
//  project: LuLu_Plus (tests)
//  description: loads the add/edit-rule window the app ships, picks a direction, and checks the
//               rule information the window hands to the extension says which way it goes
//
//  usage: test_add_rule_direction <path/to/AddRule.nib> <language>
//

@import Cocoa;
@import OSLog;

#import "consts.h"
#import "Rule.h"
#import "AddRuleWindowController.h"

/* GLOBALS (the one AddRuleWindowController.m expects) */

os_log_t logHandle = NULL;

static NSUInteger testsRun = 0;
static NSUInteger testsFailed = 0;

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

static NSString* cstr(id value)
{
    if(nil == value) return @"(nil)";
    if([value isKindOfClass:NSString.class]) return value;

    return [value description];
}

/* helpers */

static NSString* gLanguage = nil;

//the window, loaded from the nib the app ships
static AddRuleWindowController* loaded(Rule* existing)
{
    NSString* nibPath = [NSProcessInfo.processInfo.arguments objectAtIndex:1];

    AddRuleWindowController* controller = [[AddRuleWindowController alloc] init];
    controller = [controller initWithWindowNibPath:nibPath owner:controller];

    //set before touching -window, which is what loads the nib and runs -awakeFromNib
    controller.rule = existing;

    if(nil == controller.window)
    {
        check("the add-rule window loaded from the nib", NO);
        return nil;
    }

    check("the add-rule window loaded from the nib", YES);

    return controller;
}

//fill in what the window needs before it will accept a rule
static void fill(AddRuleWindowController* controller, NSString* address, NSString* port)
{
    controller.path.stringValue = @"/bin/ls";
    controller.endpointAddr.stringValue = address;
    controller.endpointPort.stringValue = port;

    return;
}

//the picker's items, as the window laid them out
static NSPopUpButton* picker(AddRuleWindowController* controller)
{
    NSPopUpButton* popup = controller.directionPicker;

    if(nil == popup)
    {
        check("the window has a direction picker", NO);
        return nil;
    }

    check("the window has a direction picker", YES);

    return popup;
}

//the word beside the picker, which the window adds next to the picker itself
static NSTextField* directionLabel(AddRuleWindowController* controller)
{
    NSString* wanted = NSLocalizedString(@"Direction", @"Direction");

    for(NSView* view in controller.window.contentView.subviews)
    {
        if(YES != [view isKindOfClass:NSTextField.class]) continue;
        if(0 == [[(NSTextField*)view stringValue] compare:wanted]) return (NSTextField*)view;
    }

    return nil;
}

static NSInteger indexOfTag(NSPopUpButton* popup, TrafficDirection tag)
{
    for(NSUInteger i = 0; i < popup.numberOfItems; i++)
    {
        if(tag == [popup itemAtIndex:(NSInteger)i].tag) return (NSInteger)i;
    }

    return NSNotFound;
}

/* CASES */

//a brand new rule: what the picker offers, and what a click on 'add' produces
static void testAuthoring(void)
{
    AddRuleWindowController* controller = loaded(nil);
    if(nil == controller) return;

    //the nib's title promised "outgoing connections", which a direction picker undoes
    NSString* title = controller.window.title;

    check("the window no longer says the rule is only for outgoing connections",
          (nil != title) && (NSNotFound == [title rangeOfString:@"outgoing" options:NSCaseInsensitiveSearch].location));

    NSPopUpButton* popup = picker(controller);
    if(nil == popup) return;

    check("the picker offers the three directions a rule can have", (3 == popup.numberOfItems));

    //a new rule covers either way, which is what every rule written before this picker meant
    check("a new rule starts out covering either direction",
          TrafficDirectionBoth == popup.selectedItem.tag);

    //the labels come from the catalog, not from literals in the code
    check("the picker's labels are the translated ones",
          (YES == [popup.itemTitles containsObject:NSLocalizedString(@"Outgoing", @"Outgoing")]) &&
          (YES == [popup.itemTitles containsObject:NSLocalizedString(@"Incoming", @"Incoming")]) &&
          (YES == [popup.itemTitles containsObject:NSLocalizedString(@"Both", @"Both")]));

    check("the picker is labelled, in the language the window is in",
          nil != directionLabel(controller));

    //a string that comes back as its own key means the catalog has no value for this language:
    //    the checks above compare against NSLocalizedString, which quietly falls back to English
    if((nil != gLanguage) && (0 != [gLanguage compare:@"en"]))
    {
        check("the choices are translated, not the English keys",
              (YES != [popup.itemTitles containsObject:@"Outgoing"]) &&
              (YES != [popup.itemTitles containsObject:@"Incoming"]) &&
              (YES != [popup.itemTitles containsObject:@"Both"]));

        NSTextField* words = directionLabel(controller);
        check("the label beside it is translated too",
              (nil != words) && (0 != [[words stringValue] compare:@"Direction"]));

        //the rule list marks which way a rule goes, and that has to be in the same language
        Rule* shown = [[Rule alloc] init:@{@"path" : @"/bin/ls",
                                           @"name" : @"Example",
                                           @"type" : @(RULE_TYPE_USER),
                                           @"action" : @(RULE_STATE_BLOCK),
                                           @"scope" : @(ACTION_SCOPE_ENDPOINT),
                                           @"direction" : @(TrafficDirectionInbound)}];

        NSString* note = shown.directionNote;
        check("the list's word for an inbound rule is translated too",
              (nil != note) && (0 != [note compare:@"(incoming)"]));
    }

    //the tags are what the rule stores, so a swap here silently mis-files every rule
    check("each choice is tagged with the direction it names",
          (TrafficDirectionOutbound == indexOfTag(popup, TrafficDirectionOutbound)) &&
          (TrafficDirectionInbound == indexOfTag(popup, TrafficDirectionInbound)) &&
          (TrafficDirectionBoth == indexOfTag(popup, TrafficDirectionBoth)));

    return;
}

//choose `direction` and press 'add'
static void testAnswer(TrafficDirection direction)
{
    AddRuleWindowController* controller = loaded(nil);
    if(nil == controller) return;

    NSPopUpButton* popup = picker(controller);
    if(nil == popup) return;

    NSInteger index = indexOfTag(popup, direction);
    if(NSNotFound == index)
    {
        check("the picker can be set to the direction under test", NO);
        return;
    }

    [popup selectItemAtIndex:index];

    fill(controller, @"203.0.113.7", @"548");

    [controller addButtonHandler:controller.addButton];

    NSDictionary* info = controller.info;

    if(nil == info)
    {
        check("pressing 'add' produced rule information", NO);
        return;
    }

    check("pressing 'add' produced rule information", YES);

    //the direction has to travel with the rule, or it lands in the wrong half of the firewall
    check("the rule the window hands over carries the chosen direction",
          direction == [info[KEY_DIRECTION] integerValue]);

    //and not just in the dictionary - in the rule the extension will build from it
    Rule* rule = [[Rule alloc] init:info];

    check("the rule built from it keeps that direction",
          direction == rule.direction.integerValue);

    check("the rule keeps the endpoint the user typed",
          (0 == [cstr(info[KEY_ENDPOINT_ADDR]) compare:@"203.0.113.7"]) &&
          (0 == [cstr(info[KEY_ENDPOINT_PORT]) compare:@"548"]));

    check("the rule is the user's own", RULE_TYPE_USER == [info[KEY_TYPE] integerValue]);

    return;
}

//editing an existing rule: the picker has to show what the rule actually is
static void testPrefill(void)
{
    NSMutableDictionary* info = [@{KEY_PATH:@"/usr/bin/whoever",
                                   KEY_ENDPOINT_ADDR:@"192.168.1.50",
                                   KEY_ENDPOINT_PORT:@"548",
                                   KEY_TYPE:@RULE_TYPE_USER,
                                   KEY_ACTION:@RULE_STATE_BLOCK,
                                   KEY_DIRECTION:@(TrafficDirectionInbound)} mutableCopy];

    Rule* rule = [[Rule alloc] init:info];

    AddRuleWindowController* controller = loaded(rule);
    if(nil == controller) return;

    NSPopUpButton* popup = picker(controller);
    if(nil == popup) return;

    check("editing an inbound rule shows it as inbound",
          TrafficDirectionInbound == popup.selectedItem.tag);

    //and pressing 'add' keeps it inbound, without the user touching the picker
    fill(controller, rule.endpointAddr, rule.endpointPort);
    [controller addButtonHandler:controller.addButton];

    check("editing a rule without touching the picker keeps its direction",
          TrafficDirectionInbound == [cstr(controller.info[KEY_DIRECTION]) integerValue]);

    return;
}

//the picker is laid out in code, next to controls the nib owns
static void testGeometry(void)
{
    AddRuleWindowController* controller = loaded(nil);
    if(nil == controller) return;

    NSPopUpButton* popup = picker(controller);
    if(nil == popup) return;

    NSView* content = controller.window.contentView;
    [content layoutSubtreeIfNeeded];

    NSRect bounds = [popup convertRect:popup.bounds toView:content];

    printf("   picker at %.0f,%.0f %.0fx%.0f in a %.0fx%.0f window\n",
           bounds.origin.x, bounds.origin.y, bounds.size.width, bounds.size.height,
           content.bounds.size.width, content.bounds.size.height);

    check("the picker has a size (it fits its widest choice)",
          (bounds.size.width > 60) && (bounds.size.height > 10));

    check("the picker is inside the window", NSContainsRect(content.bounds, bounds));

    //it is meant to read as part of the column of fields above it
    check("its right edge lines up with the address and port fields",
          (fabs(NSMaxX(bounds) - NSMaxX(controller.endpointPort.frame)) <= 1.0));

    //...and nothing else in the window, which is every control the nib owns plus the label
    //    the window adds beside the picker
    NSTextField* label = directionLabel(controller);
    BOOL overlaps = NO;

    for(NSView* neighbour in content.subviews)
    {
        if((neighbour == popup) || (neighbour == label)) continue;

        NSRect hit = NSIntersectionRect(bounds, [neighbour convertRect:neighbour.bounds toView:content]);
        if(YES == NSIsEmptyRect(hit)) continue;

        overlaps = YES;
        printf("   overlaps %s hit at %.0f,%.0f %.0fx%.0f, neighbour %.0f,%.0f %.0fx%.0f\n",
               NSStringFromClass(neighbour.class).UTF8String,
               hit.origin.x, hit.origin.y, hit.size.width, hit.size.height,
               neighbour.frame.origin.x, neighbour.frame.origin.y,
               neighbour.frame.size.width, neighbour.frame.size.height);
    }

    check("the picker overlaps no other control", YES != overlaps);

    //the label belongs with the picker, not on top of it
    if(nil != label)
    {
        NSRect labelRect = [label convertRect:label.bounds toView:content];
        check("the label beside the picker doesn't overlap it",
              YES == NSIsEmptyRect(NSIntersectionRect(labelRect, bounds)));
    }

    //and it has to stay put when the user drags the window wider (it is resizable)
    NSSize original = content.bounds.size;
    [controller.window setContentSize:NSMakeSize(800, original.height)];
    [content layoutSubtreeIfNeeded];

    NSRect wide = [popup convertRect:popup.bounds toView:content];

    check("widening the window keeps the picker inside it",
          NSContainsRect(content.bounds, wide));

    NSRect widened = NSIntersectionRect(wide, [controller.allowButton convertRect:controller.allowButton.bounds toView:content]);
    check("widening the window keeps the picker clear of the block/allow buttons",
          YES == NSIsEmptyRect(widened));

    //it belongs with the fields above it, so it has to travel with them
    NSRect wideFields = [controller.endpointPort convertRect:controller.endpointPort.bounds toView:content];
    check("widening the window keeps the picker lined up with the fields",
          (fabs(NSMaxX(wide) - NSMaxX(wideFields)) <= 1.0));

    //back to the nib's own size, so nothing downstream sees a resized window
    [controller.window setContentSize:original];

    return;
}

/* MAIN */

int main(int argc, const char* argv[])
{
    @autoreleasepool
    {
        if(argc < 3)
        {
            fprintf(stderr, "usage: %s <AddRule.nib> <language>\n", argv[0]);
            return 2;
        }

        logHandle = os_log_create("com.imonior.lulu-plus", "tests");
        gLanguage = [@(argv[2]) copy];

        //pick the language in-process: the environment is only honored by a launched app
        [[NSUserDefaults standardUserDefaults] setObject:@[gLanguage, @"en"] forKey:@"AppleLanguages"];
        [[NSUserDefaults standardUserDefaults] synchronize];

        printf("== add-rule window direction (%s) ==\n", gLanguage.UTF8String);

        testAuthoring();
        testAnswer(TrafficDirectionInbound);
        testAnswer(TrafficDirectionOutbound);
        testAnswer(TrafficDirectionBoth);
        testPrefill();
        testGeometry();

        printf("\n%lu/%lu checks passed\n", (unsigned long)(testsRun - testsFailed), (unsigned long)testsRun);

        if(0 != testsFailed)
        {
            printf("FAILED: %lu check(s)\n", (unsigned long)testsFailed);
            return 1;
        }

        printf("All checks passed\n");
    }

    return 0;
}
