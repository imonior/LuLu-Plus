//
//  file: test_language.m
//  project: LuLu_Plus (tests)
//  description: drives the language picker: the languages the model offers, what it stores, what
//               the Settings tab shows, and what a restart would apply - against the three real
//               string catalogs, the real Preferences nib, and defaults of the test's own
//
//  usage: test_language <compiled Preferences.nib> <language> <Localizable.xcstrings> <Preferences.xcstrings> <InfoPlist.xcstrings>
//

@import Cocoa;
@import OSLog;

#import "consts.h"
#import "Language.h"
#import "PrefsWindowController.h"
#import "PrefsWindowController+Private.h"

/* GLOBALS (what the app defines at runtime; the sources under test only log through them, and the
   extension's client never gets to talk to anything here) */

os_log_t logHandle = NULL;
XPCDaemonClient* xpcDaemonClient = nil;

//the two keys the model stores its business under
#define TEST_KEY_PICK @"language"
#define TEST_KEY_APPLE_LANGUAGES @"AppleLanguages"

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

//whether a value just read back is the string expected
// note: '[nil compare:...]' answers 0, so the plain '0 == [value compare:x]' idiom reads a value
//       that was never written as the one that was; every read-back of something that should have
//       been stored goes through here instead
static BOOL same(id value, NSString* expected)
{
    return (YES == [value isKindOfClass:NSString.class]) && (0 == [value compare:expected]);
}

/* CATALOGS (the real ones, read the way Xcode writes them) */

static NSDictionary* catalogStrings(NSString* path)
{
    NSData* data = [NSData dataWithContentsOfFile:path];
    if(nil == data) return nil;

    NSDictionary* json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    if(YES != [json isKindOfClass:NSDictionary.class]) return nil;

    id strings = json[@"strings"];

    return (YES == [strings isKindOfClass:NSDictionary.class]) ? strings : nil;
}

//every language any key of a catalog carries
static NSSet<NSString*>* catalogLanguages(NSDictionary* strings)
{
    NSMutableSet<NSString*>* languages = [NSMutableSet set];

    for(NSString* key in strings)
    {
        id localizations = strings[key][@"localizations"];
        if(YES != [localizations isKindOfClass:NSDictionary.class]) continue;

        [languages addObjectsFromArray:[localizations allKeys]];
    }

    return languages;
}

//the value a catalog carries for one key in one language (nil for the source language)
static NSString* catalogValue(NSDictionary* strings, NSString* key, NSString* language)
{
    id value = strings[key][@"localizations"][language][@"stringUnit"][@"value"];

    return (YES == [value isKindOfClass:NSString.class]) ? value : nil;
}

//the languages a catalog has no usable value for; the source language is allowed to carry none
static NSArray<NSString*>* languagesMissing(NSDictionary* strings, NSString* key, NSArray<NSString*>* shipped, BOOL sourceAllowed)
{
    NSMutableArray<NSString*>* missing = [NSMutableArray array];

    for(NSString* language in shipped)
    {
        NSString* value = catalogValue(strings, key, language);

        if((nil != value) && (0 != value.length)) continue;
        if((YES == sourceAllowed) && (0 == [language compare:@"en"])) continue;

        [missing addObject:language];
    }

    return missing;
}

//the languages a catalog carries the English word for, i.e. a translation nobody wrote
static NSArray<NSString*>* languagesUntranslated(NSDictionary* strings, NSString* key, NSArray<NSString*>* shipped)
{
    NSMutableArray<NSString*>* same = [NSMutableArray array];

    for(NSString* language in shipped)
    {
        if(0 == [language compare:@"en"]) continue;

        NSString* value = catalogValue(strings, key, language);
        if((nil != value) && (0 == [value compare:key])) [same addObject:language];
    }

    return same;
}

static void checkCatalogCovers(NSDictionary* strings, NSString* key, NSArray<NSString*>* shipped, BOOL sourceAllowed, const char* description)
{
    NSArray<NSString*>* missing = languagesMissing(strings, key, shipped, sourceAllowed);

    if(0 != missing.count)
    {
        printf("   '%s' is missing in: %s\n", key.UTF8String,
               [[missing componentsJoinedByString:@", "] UTF8String]);
    }

    check(description, 0 == missing.count);

    return;
}

static void checkCatalogTranslated(NSDictionary* strings, NSString* key, NSArray<NSString*>* shipped, const char* description)
{
    NSArray<NSString*>* untranslated = languagesUntranslated(strings, key, shipped);

    if(0 != untranslated.count)
    {
        printf("   '%s' still reads English in: %s\n", key.UTF8String,
               [[untranslated componentsJoinedByString:@", "] UTF8String]);
    }

    check(description, 0 == untranslated.count);

    return;
}

//the note under the picker, and the two other words the tab is made of
static NSString* kNoteKey(void)
{
    return @"LuLu_Plus applies a new language after it is restarted.";
}

//the tab's label in the nib's own catalog
static NSString* kToolbarLabelKey(void)
{
    return @"Lng-Tb-g01.label";
}

static NSDictionary* gLocalizable = nil;
static NSDictionary* gMul = nil;
static NSDictionary* gInfoPlist = nil;

static NSString* gLanguage = nil;
static NSString* gNibPath = nil;

//what the test wrote into the app's own defaults, to be put back before it leaves
static id gSavedPick = nil;
static id gSavedSystemLanguages = nil;

/* THE LANGUAGE MODEL (Shared/Language.m) */

//the names each language is offered under, written in that language
static NSDictionary* expectedNames(void)
{
    return @{
        @"en" : @"English",
        @"de" : @"Deutsch",
        @"es" : @"Español",
        @"fr" : @"Français",
        @"it" : @"Italiano",
        @"ko" : @"한국어",
        @"pl" : @"Polski",
        @"pt-BR" : @"Português (Brasil)",
        @"tr" : @"Türkçe",
        @"uk" : @"Українська",
        @"ur" : @"اردو",
        @"zh-Hans" : @"简体中文",
        @"zh-Hant" : @"繁體中文"
    };
}

//the defaults the model's cases run against; a suite of the test's own, so what the app (or an
// earlier run) has stored can't decide the answer
// note: a suite's search list ends in the global domain, where the Mac's own language list lives,
//       so every case says what it means by *storing* something - an empty list is the Mac having
//       nothing to say, and never -removeObjectForKey:, which would fall back to the real one
static NSUserDefaults* sandboxDefaults(void)
{
    static NSUserDefaults* sandbox = nil;
    static dispatch_once_t once;

    dispatch_once(&once, ^{

        sandbox = [[NSUserDefaults alloc] initWithSuiteName:@"com.example.language-tests.sandbox"];
    });

    return sandbox;
}

static void store(NSUserDefaults* defaults, id pick, NSArray* systemLanguages)
{
    if(nil == pick)
    {
        [defaults removeObjectForKey:TEST_KEY_PICK];
    }
    else
    {
        [defaults setObject:pick forKey:TEST_KEY_PICK];
    }

    [defaults setObject:(nil != systemLanguages) ? systemLanguages : @[] forKey:TEST_KEY_APPLE_LANGUAGES];
    [defaults synchronize];

    return;
}

//what the model offers
static void testShippedLanguages(void)
{
    NSArray<NSString*>* shipped = [Language shippedLanguages];
    NSSet<NSString*>* asSet = [NSSet setWithArray:shipped];
    NSDictionary* names = expectedNames();

    check("English is the language the app starts in", 0 == [[Language defaultLanguage] compare:@"en"]);
    check("English is the one offered first", 0 == [shipped.firstObject compare:@"en"]);
    check("no language is offered twice", shipped.count == asSet.count);

    //the picker offers these names, so a wrong one is what a user would see
    BOOL named = YES;
    NSMutableSet<NSString*>* seen = [NSMutableSet set];

    for(NSString* code in shipped)
    {
        NSString* name = [Language displayNameForLanguage:code];

        if(0 != [name compare:names[code]])
        {
            named = NO;
            printf("   %s is offered as '%s', expected '%s'\n",
                   code.UTF8String, name.UTF8String, [names[code] UTF8String]);
        }

        [seen addObject:name];
    }

    check("every language is offered under its own name", named);
    check("no two languages are offered under the same name", seen.count == asSet.count);
    check("a language the app doesn't offer comes back as its code",
          0 == [[Language displayNameForLanguage:@"ja"] compare:@"ja"]);

    //what counts as a language this build ships
    BOOL accepted = YES;

    for(NSString* code in shipped)
    {
        if(YES != [Language isShippedLanguage:code]) accepted = NO;
    }

    check("every language it offers is accepted", accepted);
    check("a language it doesn't ship is refused",
          (YES != [Language isShippedLanguage:@"ja"]) &&
          (YES != [Language isShippedLanguage:@"zh"]) &&
          (YES != [Language isShippedLanguage:@"pt"]) &&
          (YES != [Language isShippedLanguage:@"en-CN"]) &&
          (YES != [Language isShippedLanguage:@"EN"]) &&
          (YES != [Language isShippedLanguage:@""]) &&
          (YES != [Language isShippedLanguage:nil]));

    return;
}

//the language the UI should run in
static void testResolution(void)
{
    NSUserDefaults* defaults = sandboxDefaults();

    //nothing stored for this app and nothing from the system: English
    store(defaults, nil, @[]);
    check("with nothing chosen anywhere the UI starts in English",
          0 == [[Language resolvedLanguage:defaults] compare:@"en"]);
    check("...and there is nothing to restart for", YES != [Language restartRequired:defaults]);

    //a language macOS was told to run this app in (per-app language in System Settings)
    store(defaults, nil, @[@"zh-Hans"]);
    check("a language chosen outside the app is the one the UI runs in",
          0 == [[Language resolvedLanguage:defaults] compare:@"zh-Hans"]);
    check("...and it is what is already on screen, so no restart is offered",
          YES != [Language restartRequired:defaults]);

    //one this build has no strings for is ignored, the way the bundle ignores it
    store(defaults, nil, @[@"ja"]);
    check("a language we don't ship leaves the UI in English",
          0 == [[Language resolvedLanguage:defaults] compare:@"en"]);

    //the list macOS keeps is ordered by preference
    store(defaults, nil, @[@"uk", @"fr"]);
    check("the system's first language is the one taken",
          0 == [[Language resolvedLanguage:defaults] compare:@"uk"]);

    //the pick the user made in the app wins over the system's
    store(defaults, @"de", @[@"fr"]);
    check("a pick made in the app wins over the system's language",
          0 == [[Language resolvedLanguage:defaults] compare:@"de"]);
    check("the running language is still the one the process loaded",
          0 == [[Language runningLanguage:defaults] compare:@"fr"]);
    check("a pick that differs from the loaded language offers a restart",
          YES == [Language restartRequired:defaults]);

    store(defaults, @"de", @[@"de"]);
    check("a pick the process is already running in clears the restart",
          YES != [Language restartRequired:defaults]);

    //picks this build can't honor: a code from another build, or a value that isn't even text
    store(defaults, @"ja", @[@"ja"]);
    check("a stored pick we don't ship falls back to English",
          0 == [[Language resolvedLanguage:defaults] compare:@"en"]);

    store(defaults, @5, @[@"it"]);
    check("a stored pick that isn't text is ignored",
          0 == [[Language resolvedLanguage:defaults] compare:@"it"]);

    return;
}

//what the app writes down, and what the next launch makes of it
static void testWriting(void)
{
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];

    //only a language the app ships is written down, and the running UI is left alone
    store(defaults, nil, @[@"en"]);
    [Language selectLanguage:@"ja"];
    check("picking a language we don't ship writes nothing down", nil == [defaults stringForKey:TEST_KEY_PICK]);

    [Language selectLanguage:@"de"];
    check("picking a language stores the pick", same([defaults stringForKey:TEST_KEY_PICK], @"de"));
    check("...without swapping the strings of the running UI",
          same([[defaults arrayForKey:TEST_KEY_APPLE_LANGUAGES] firstObject], @"en"));
    check("...so the app offers the restart", YES == [Language restartRequired:defaults]);

    //what the next launch starts in
    store(defaults, @"fr", @[@"de"]);
    [Language applyAtStartup];
    check("at the next launch the stored pick is what the process loads",
          same([[defaults arrayForKey:TEST_KEY_APPLE_LANGUAGES] firstObject], @"fr"));
    check("...and the pick itself is left as the user made it",
          same([defaults stringForKey:TEST_KEY_PICK], @"fr"));

    //a language chosen outside the app is taken over as the pick, so a later change there is not
    //lost to a pick the user never made here
    store(defaults, nil, @[@"uk"]);
    [Language applyAtStartup];
    check("a language chosen outside the app becomes the pick",
          same([defaults stringForKey:TEST_KEY_PICK], @"uk"));
    check("...and is what the process runs in",
          same([[defaults arrayForKey:TEST_KEY_APPLE_LANGUAGES] firstObject], @"uk"));

    //nothing chosen anywhere: English, even on a Mac whose own language is something else
    store(defaults, nil, @[@"ja"]);
    [Language applyAtStartup];
    check("with nothing chosen anywhere the UI is forced to English",
          same([[defaults arrayForKey:TEST_KEY_APPLE_LANGUAGES] firstObject], @"en"));
    check("...and no pick is invented for it", nil == [defaults stringForKey:TEST_KEY_PICK]);

    return;
}

/* THE SETTINGS TAB */

static NSTextField* fieldWithText(NSView* pane, NSString* text)
{
    for(NSView* view in pane.subviews)
    {
        if(YES != [view isKindOfClass:NSTextField.class]) continue;
        if(0 == [[(NSTextField*)view stringValue] compare:text]) return (NSTextField*)view;
    }

    return nil;
}

//what the window shows, and what the pane does with a pick
static void testWindow(void)
{
    PrefsWindowController* controller = [[PrefsWindowController alloc] init];
    controller = [controller initWithWindowNibPath:gNibPath owner:controller];

    //the nib loads the window; -awakeFromNib runs on the way
    NSWindow* window = controller.window;

    check("the settings window loaded from the nib the app ships", nil != window);
    if(nil == window) return;

    NSView* content = window.contentView;

    //the tab: there, once, under the identifier -switchTo: looks up and the tag the handler
    //switches on, and still beside every tab that was there before
    NSToolbarItem* languageTab = nil;
    NSUInteger languageTabs = 0;
    NSMutableSet<NSNumber*>* tags = [NSMutableSet set];

    for(NSToolbarItem* item in controller.toolbar.items)
    {
        if(-1 == item.tag) continue;

        [tags addObject:@(item.tag)];

        if(0 != [item.itemIdentifier compare:TOOLBAR_LANGUAGE_ID]) continue;

        languageTab = item;
        languageTabs++;
    }

    check("the tabs it already had are all still there",
          (YES == [tags containsObject:@(TOOLBAR_RULES)]) &&
          (YES == [tags containsObject:@(TOOLBAR_MODES)]) &&
          (YES == [tags containsObject:@(TOOLBAR_LISTS)]) &&
          (YES == [tags containsObject:@(TOOLBAR_PROFILES)]) &&
          (YES == [tags containsObject:@(TOOLBAR_UPDATE)]));

    check("the language tab is one of them, and only one", (nil != languageTab) && (1 == languageTabs));
    check("the handler's case is the tag the tab carries",
          (nil != languageTab) && (TOOLBAR_LANGUAGE == languageTab.tag));

    //its words come from the nib's catalog, in the language the window is in
    NSString* label = catalogValue(gMul, kToolbarLabelKey(), gLanguage);

    check("the tab is labelled in the language on screen",
          (nil != languageTab) && (nil != label) && (0 == [languageTab.label compare:label]));

    if((nil != languageTab) && (0 != [gLanguage compare:@"en"]))
    {
        check("...and not with the English word",
              YES != [languageTab.label isEqualToString:@"Language"]);
    }

    check("the tab carries the icon the app ships", (nil != languageTab) && (nil != languageTab.image));

    //the pane: what choosing the tab puts on the window
    [controller switchTo:TOOLBAR_LANGUAGE_ID];

    NSView* pane = controller.languageView;

    check("choosing the language tab shows a pane", nil != pane);
    if(nil == pane) return;

    check("the pane is the one on the window", YES == [[content.subviews lastObject] isEqual:pane]);
    check("the pane is as wide as the panes beside it",
          pane.frame.size.width == controller.rulesView.frame.size.width);
    check("the pane starts at the top of the window",
          NSMaxY(pane.frame) == content.bounds.size.height);
    check("the pane is inside the window", NSContainsRect(content.bounds, pane.frame));

    //what the pane is made of
    NSMutableArray<NSTextField*>* fields = [NSMutableArray array];
    NSMutableArray<NSButton*>* buttons = [NSMutableArray array];

    for(NSView* view in pane.subviews)
    {
        //a pop-up is a button too, and is looked at on its own below
        if(YES == [view isKindOfClass:NSPopUpButton.class]) continue;

        if(YES == [view isKindOfClass:NSTextField.class]) [fields addObject:(NSTextField*)view];
        else if(YES == [view isKindOfClass:NSButton.class]) [buttons addObject:(NSButton*)view];
    }

    check("the pane has a title, a note, a picker and a button",
          (2 == fields.count) && (1 == buttons.count) && (nil != controller.languagePicker));

    //the picker: every language the app ships, each under its own name, carrying its own code
    NSPopUpButton* picker = controller.languagePicker;
    NSArray<NSString*>* shipped = [Language shippedLanguages];

    if(nil != picker)
    {
        check("the picker offers every language the app ships",
              picker.numberOfItems == (NSInteger)shipped.count);

        BOOL choices = YES;

        for(NSUInteger i = 0; (i < shipped.count) && ((NSInteger)i < picker.numberOfItems); i++)
        {
            NSMenuItem* item = [picker itemAtIndex:(NSInteger)i];
            id code = item.representedObject;
            NSString* name = [Language displayNameForLanguage:shipped[i]];

            if((YES != [code isKindOfClass:NSString.class]) || (0 != [code compare:shipped[i]]) ||
               (0 != [item.title compare:name]))
            {
                choices = NO;
                printf("   choice %lu: '%s' ('%s'), expected '%s' ('%s')\n", (unsigned long)i,
                       item.title.UTF8String, [code description].UTF8String,
                       name.UTF8String, shipped[i].UTF8String);
            }
        }

        check("each choice is named in its own language and carries the code the pick stores", choices);

        id selected = picker.selectedItem.representedObject;

        check("the picker shows the language the app is running in",
              (YES == [selected isKindOfClass:NSString.class]) && (0 == [selected compare:gLanguage]));
        check("the picker is wired to the handler for a pick",
              (controller == picker.target) &&
              (YES == [NSStringFromSelector(picker.action) isEqualToString:@"languageChanged:"]));
    }

    //the pane's words: the translated ones, and the note has to name the app it is about
    NSString* noteKey = kNoteKey();
    NSString* noteText = catalogValue(gLocalizable, noteKey, gLanguage) ?: noteKey;
    NSString* titleText = catalogValue(gLocalizable, @"Language", gLanguage) ?: @"Language";
    NSString* buttonText = catalogValue(gLocalizable, @"Restart Now", gLanguage) ?: @"Restart Now";

    NSTextField* note = fieldWithText(pane, noteText);
    NSTextField* title = fieldWithText(pane, titleText);
    NSButton* restart = controller.restartButton;

    check("the pane is titled in this language", nil != title);
    check("the pane says what happens with the pick, in this language", nil != note);
    check("...and names the app it is about",
          (nil != note) && (NSNotFound != [note.stringValue rangeOfString:@"LuLu_Plus"].location));

    check("the restart button says what it does, in this language",
          (nil != restart) && (0 == [restart.title compare:buttonText]));
    check("the button is wired to the handler that restarts",
          (nil != restart) && (controller == restart.target) &&
          (YES == [NSStringFromSelector(restart.action) isEqualToString:@"restartNow:"]));

    //nothing picked yet, so the language on screen is the one stored
    check("with nothing picked there is nothing to restart for",
          (nil != restart) && (YES != restart.enabled));

    //the room the words were given, measured with the fonts they are drawn in
    if(nil != note)
    {
        NSRect needed = [note.stringValue boundingRectWithSize:NSMakeSize(note.frame.size.width, CGFLOAT_MAX)
                                                       options:(NSStringDrawingUsesLineFragmentOrigin|NSStringDrawingUsesFontLeading)
                                                    attributes:@{NSFontAttributeName : note.font}];

        check("the note fits the room it is given",
              NSIntegralRect(needed).size.height <= note.frame.size.height);
    }

    if(nil != title)
    {
        NSRect needed = [title.stringValue boundingRectWithSize:NSMakeSize(title.frame.size.width, CGFLOAT_MAX)
                                                        options:(NSStringDrawingUsesLineFragmentOrigin|NSStringDrawingUsesFontLeading)
                                                     attributes:@{NSFontAttributeName : title.font}];

        check("the title fits the room it is given",
              (NSIntegralRect(needed).size.width <= title.frame.size.width) &&
              (NSIntegralRect(needed).size.height <= title.frame.size.height));
    }

    if(nil != restart)
    {
        //the title is drawn in the font it was given, so a width measured before that font was set
        //is how a longer translation ends up cut off
        check("the restart button is wide enough for its title",
              restart.intrinsicContentSize.width <= restart.frame.size.width);
    }

    if(nil != picker)
    {
        check("the picker is wide enough for its widest choice",
              picker.intrinsicContentSize.width <= picker.frame.size.width);
    }

    //nothing on the pane sits on top of anything else, and none of it runs off the pane
    BOOL inside = YES;
    BOOL overlaps = NO;

    for(NSUInteger i = 0; i < pane.subviews.count; i++)
    {
        if(YES != NSContainsRect(pane.bounds, pane.subviews[i].frame))
        {
            inside = NO;
            printf("   off the pane: %s %s\n", NSStringFromClass(pane.subviews[i].class).UTF8String,
                   NSStringFromRect(pane.subviews[i].frame).UTF8String);
        }

        for(NSUInteger j = (i + 1); j < pane.subviews.count; j++)
        {
            if(YES == NSIsEmptyRect(NSIntersectionRect(pane.subviews[i].frame, pane.subviews[j].frame))) continue;

            overlaps = YES;
            printf("   %s on top of %s\n", NSStringFromClass(pane.subviews[i].class).UTF8String,
                   NSStringFromClass(pane.subviews[j].class).UTF8String);
        }
    }

    check("every control is on the pane", inside);
    check("no control sits on top of another", YES != overlaps);

    if((nil == picker) || (nil == restart)) return;

    //the user picks a language other than the one on screen
    NSInteger chosenIndex = (picker.indexOfSelectedItem + 1) % picker.numberOfItems;
    id chosen = [picker itemAtIndex:chosenIndex].representedObject;

    [picker selectItemAtIndex:chosenIndex];
    [picker sendAction:picker.action to:picker.target];

    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];

    check("the pick is written down as the language to use",
          (YES == [chosen isKindOfClass:NSString.class]) &&
          same([defaults stringForKey:TEST_KEY_PICK], chosen));
    check("the running window keeps the language it was built with",
          0 == [[Language runningLanguage:defaults] compare:gLanguage]);
    check("...which is no longer the pick, so the restart is offered", YES == restart.enabled);
    check("the picker shows the pick it just stored",
          same(picker.selectedItem.representedObject, chosen));
    check("the pick is all that is written: the running language is untouched",
          same([[defaults arrayForKey:TEST_KEY_APPLE_LANGUAGES] firstObject], gLanguage));

    //switching away and back: the pane behaves like the ones beside it, and comes back as it was
    [controller switchTo:TOOLBAR_RULES_ID];

    check("switching to another tab takes the language pane off the window",
          YES != [content.subviews containsObject:pane]);
    check("...and shows that tab's pane", YES == [[content.subviews lastObject] isEqual:controller.rulesView]);

    [controller switchTo:TOOLBAR_LANGUAGE_ID];

    check("coming back shows the same pane again", YES == [controller.languageView isEqual:pane]);
    check("...still showing the pick", same(controller.languagePicker.selectedItem.representedObject, chosen));
    check("...and still offering the restart", YES == controller.restartButton.enabled);

    return;
}

/* CATALOGS */

//the languages the app offers are exactly the ones it can render
static void testCatalogs(void)
{
    NSSet<NSString*>* shipped = [NSSet setWithArray:[Language shippedLanguages]];
    NSArray<NSString*>* asList = [Language shippedLanguages];

    check("all three catalogs were read", (nil != gLocalizable) && (nil != gMul) && (nil != gInfoPlist));
    if((nil == gLocalizable) || (nil == gMul) || (nil == gInfoPlist)) return;

    //a language offered but not translated is a UI that silently stays English
    check("the languages the app offers are the ones the code catalog carries",
          [shipped isEqualToSet:catalogLanguages(gLocalizable)]);
    check("...and the ones the window's catalog carries",
          [shipped isEqualToSet:catalogLanguages(gMul)]);
    check("...and the ones the app's Info.plist is translated into",
          [shipped isEqualToSet:catalogLanguages(gInfoPlist)]);

    //the tab's own words
    checkCatalogCovers(gLocalizable, @"Language", asList, YES,
                       "the tab's title is written down in every language");
    checkCatalogCovers(gLocalizable, kNoteKey(), asList, YES,
                       "the note under the picker is written down in every language");
    checkCatalogCovers(gLocalizable, @"Restart Now", asList, YES,
                       "the restart button is written down in every language");
    checkCatalogCovers(gMul, kToolbarLabelKey(), asList, NO,
                       "the tab's own label is written down in every language");
    checkCatalogCovers(gMul, @"Lng-Tb-g01.paletteLabel", asList, NO,
                       "the tab's label in the palette to customize is too");

    checkCatalogTranslated(gLocalizable, @"Language", asList,
                           "the tab's title is translated, not left in English");
    checkCatalogTranslated(gLocalizable, kNoteKey(), asList,
                           "the note is translated, not left in English");
    checkCatalogTranslated(gLocalizable, @"Restart Now", asList,
                           "the restart button is translated, not left in English");
    checkCatalogTranslated(gMul, kToolbarLabelKey(), asList,
                           "the tab's label is translated, not left in English");

    //the sentence keeps the app's name, whichever language it is read in
    BOOL namesApp = YES;

    for(NSString* language in asList)
    {
        NSString* text = catalogValue(gLocalizable, kNoteKey(), language) ?: kNoteKey();
        if(NSNotFound == [text rangeOfString:@"LuLu_Plus"].location) namesApp = NO;
    }

    check("the note names the app in every language", namesApp);

    return;
}

/* MAIN */

int main(int argc, const char* argv[])
{
    @autoreleasepool
    {
        if(argc < 6)
        {
            fprintf(stderr, "usage: %s <Preferences.nib> <language> <Localizable.xcstrings> <Preferences.xcstrings> <InfoPlist.xcstrings>\n", argv[0]);
            return 2;
        }

        logHandle = os_log_create("com.imonior.lulu-plus", "tests");
        gNibPath = [@(argv[1]) copy];
        gLanguage = [@(argv[2]) copy];
        gLocalizable = catalogStrings(@(argv[3]));
        gMul = catalogStrings(@(argv[4]));
        gInfoPlist = catalogStrings(@(argv[5]));

        printf("== the language picker (%s) ==\n", gLanguage.UTF8String);

        //what the app's own defaults hold, put back before the test leaves - the app under test is
        //not the test binary, but both use their own domain
        NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
        gSavedPick = [[defaults objectForKey:TEST_KEY_PICK] copy];
        gSavedSystemLanguages = [[defaults objectForKey:TEST_KEY_APPLE_LANGUAGES] copy];

        //ask AppKit for this language before anything loads a string, the way -applyAtStartup does
        [defaults removeObjectForKey:TEST_KEY_PICK];
        [defaults setObject:@[gLanguage] forKey:TEST_KEY_APPLE_LANGUAGES];
        [defaults synchronize];

        [NSApplication sharedApplication];

        testCatalogs();
        testShippedLanguages();
        testResolution();
        testWindow();
        testWriting();

        [defaults removeObjectForKey:TEST_KEY_PICK];
        [defaults removeObjectForKey:TEST_KEY_APPLE_LANGUAGES];
        if(nil != gSavedPick) [defaults setObject:gSavedPick forKey:TEST_KEY_PICK];
        if(nil != gSavedSystemLanguages) [defaults setObject:gSavedSystemLanguages forKey:TEST_KEY_APPLE_LANGUAGES];
        [defaults synchronize];

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
