//
//  file: Language.m
//  project: lulu_plus (shared)
//  description: the language the UI runs in (English by default, switchable in Settings)
//
//  copyright (c) 2026 LuLu_Plus. All rights reserved.
//

#import "Language.h"

//where the user's pick is kept
#define PREF_LANGUAGE @"language"

//the key macOS itself honors for a per-app language
#define PREF_APPLE_LANGUAGES @"AppleLanguages"

@implementation Language

//every language the string catalogs carry (English first)
// note: the test suite compares this list with the languages of Shared/Localizable.xcstrings
+(NSArray<NSString*>*)shippedLanguages
{
    return @[@"en", @"de", @"es", @"fr", @"it", @"ko", @"pl", @"pt-BR", @"tr", @"uk", @"ur", @"zh-Hans", @"zh-Hant"];
}

//what the UI runs in when the user never picked
+(NSString*)defaultLanguage
{
    return @"en";
}

//whether a code is one of the shipped ones
+(BOOL)isShippedLanguage:(NSString*)code
{
    return (nil != code) && (YES == [[self shippedLanguages] containsObject:code]);
}

//name of a language, written in that language (unknown codes come back as-is)
+(NSString*)displayNameForLanguage:(NSString*)code
{
    //written in the language itself, so the popup reads the same whichever UI language is loaded
    NSDictionary* names = @{
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

    return names[code] ?: code;
}

//the language the UI should run in
+(NSString*)resolvedLanguage:(NSUserDefaults*)defaults
{
    //the user's own pick wins
    NSString* picked = [defaults stringForKey:PREF_LANGUAGE];
    if(YES == [self isShippedLanguage:picked])
    {
        return picked;
    }

    //no pick yet: adopt a language set for this app in System Settings, so the popup shows what
    // is actually running rather than overwriting the choice at the next launch
    NSString* systemPicked = [[defaults arrayForKey:PREF_APPLE_LANGUAGES] firstObject];
    if(YES == [self isShippedLanguage:systemPicked])
    {
        return systemPicked;
    }

    return [self defaultLanguage];
}

//the language the running process was started with
+(NSString*)runningLanguage:(NSUserDefaults*)defaults
{
    //-applyAtStartup wrote this before the UI was loaded, so it is what is on screen now
    NSString* running = [[defaults arrayForKey:PREF_APPLE_LANGUAGES] firstObject];

    if(YES == [self isShippedLanguage:running])
    {
        return running;
    }

    return [self defaultLanguage];
}

//whether the pick differs from the language currently loaded
+(BOOL)restartRequired:(NSUserDefaults*)defaults
{
    return ![[self resolvedLanguage:defaults] isEqualToString:[self runningLanguage:defaults]];
}

//store the user's pick; the UI only changes after a restart
+(void)selectLanguage:(NSString*)code
{
    //only the languages we ship
    if(YES != [self isShippedLanguage:code])
    {
        return;
    }

    //note: AppleLanguages is deliberately left alone here - the running process has already
    // loaded its strings, and rewriting it mid-flight would only affect the next launch anyway
    [[NSUserDefaults standardUserDefaults] setObject:code forKey:PREF_LANGUAGE];

    return;
}

//write the language into this process's defaults; call before any UI is loaded
+(void)applyAtStartup
{
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];

    //adopted from System Settings below? then it becomes the user's pick, and later changes are
    // made in the popup ... without this, the per-app setting would be re-read at every launch
    if(nil == [defaults stringForKey:PREF_LANGUAGE])
    {
        NSString* adopted = [self resolvedLanguage:defaults];
        if(NO == [adopted isEqualToString:[self defaultLanguage]])
        {
            [defaults setObject:adopted forKey:PREF_LANGUAGE];
        }
    }

    //AppKit reads this when the main nib loads, i.e. after us
    [defaults setObject:@[[self resolvedLanguage:defaults]] forKey:PREF_APPLE_LANGUAGES];

    return;
}

@end
