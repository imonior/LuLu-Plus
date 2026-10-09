//
//  file: Language.h
//  project: lulu_plus (shared)
//  description: the language the UI runs in (English by default, switchable in Settings)
//
//  copyright (c) 2026 LuLu_Plus. All rights reserved.
//

@import Foundation;

/* the app's UI follows this, not the system language: it runs in English until the user picks
   another one of the languages the string catalogs carry, and the pick is remembered per user */

@interface Language : NSObject

//every language the string catalogs carry (English first)
+(NSArray<NSString*>*)shippedLanguages;

//what the UI runs in when the user never picked
+(NSString*)defaultLanguage;

//whether a code is one of the shipped ones
+(BOOL)isShippedLanguage:(NSString*)code;

//name of a language, written in that language (unknown codes come back as-is)
+(NSString*)displayNameForLanguage:(NSString*)code;

//the language the UI should run in
+(NSString*)resolvedLanguage:(NSUserDefaults*)defaults;

//the language the running process was started with
+(NSString*)runningLanguage:(NSUserDefaults*)defaults;

//whether the pick differs from the language currently loaded
+(BOOL)restartRequired:(NSUserDefaults*)defaults;

//store the user's pick; the UI only changes after a restart
+(void)selectLanguage:(NSString*)code;

//write the language into this process's defaults; call before any UI is loaded
+(void)applyAtStartup;

@end
