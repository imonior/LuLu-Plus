//
//  file: SigningIdentity.m
//  project: lulu_plus (shared)
//  description: the identity this build was signed with, and the names that follow from it
//
//  copyright (c) 2026 LuLu_Plus. All rights reserved.
//

#import "consts.h"

@import Security;

#import "SigningIdentity.h"

//what the extension's Info.plist uses for whoever signs the build; the build expands it, and a
//build made without a signing team leaves it standing
static NSString* const TeamIdentifierPrefix = @"$(TeamIdentifierPrefix)";

//the oldest app version the extension will talk to
static NSString* const MinimumClientVersion = @"2.0.0";

@implementation SigningIdentity

//the team that signed this process; nil for an unsigned or ad-hoc build
+(NSString*)teamIdentifier
{
    //the team
    NSString* team = nil;

    //this process's signature
    SecCodeRef code = NULL;

    //its signing information
    CFDictionaryRef info = NULL;

    //and the team the signature carries, if any
    id value = nil;

    if(errSecSuccess != SecCodeCopySelf(kSecCSDefaultFlags, &code)) goto bail;
    if(errSecSuccess != SecCodeCopySigningInformation(code, kSecCSSigningInformation, &info)) goto bail;

    //the team rides along in the signing information
    value = ((__bridge NSDictionary*)info)[(__bridge NSString*)kSecCodeInfoTeamIdentifier];
    if(YES == [value isKindOfClass:NSString.class])
    {
        team = value;
    }

bail:

    //free what was allocated
    if(NULL != info) CFRelease(info);
    if(NULL != code) CFRelease(code);

    return team;
}

//what $(TeamIdentifierPrefix) stands for: the team with a dot, or nothing at all
+(NSString*)teamIdentifierPrefixForTeam:(NSString*)team
{
    //the variable carries the dot, so the name that follows is written right against it
    return (0 != team.length) ? [team stringByAppendingString:@"."] : @"";
}

//replace the variable with what the build would have expanded it to
+(NSString*)expandTeamPrefix:(NSString*)name forTeam:(NSString*)team
{
    if(YES != [name isKindOfClass:NSString.class]) return nil;

    return [name stringByReplacingOccurrencesOfString:TeamIdentifierPrefix
                                           withString:[self teamIdentifierPrefixForTeam:team]];
}

//the requirement the extension puts on the app that connects: this build's app, signed by the
//same team
+(NSString*)clientRequirementForTeam:(NSString*)team
{
    //nothing to pin a build that carries no team: the identifier is all there is to go on
    if(0 == team.length)
    {
        return [NSString stringWithFormat:@"identifier \"%@\"", APP_ID];
    }

    //the leaf's OU is the team, so this accepts the app signed by whoever signed the extension,
    //whichever team that is
    return [NSString stringWithFormat:@"anchor apple generic and identifier \"%@\" and certificate leaf [subject.OU] = \"%@\"", APP_ID, team];
}

+(NSString*)clientRequirement
{
    return [self clientRequirementForTeam:[self teamIdentifier]];
}

//...and the variant a macOS 13+ listener hands to the system, which floors the app's version
+(NSString*)listenerRequirementForTeam:(NSString*)team
{
    return [[self clientRequirementForTeam:team] stringByAppendingFormat:@" and info [CFBundleShortVersionString] >= \"%@\"", MinimumClientVersion];
}

+(NSString*)listenerRequirement
{
    return [self listenerRequirementForTeam:[self teamIdentifier]];
}

//the system extension embedded in an app bundle, if there is one
+(NSBundle*)extensionBundleInApp:(NSBundle*)appBundle
{
    //where a built app carries it
    NSString* directory = [appBundle.bundlePath stringByAppendingPathComponent:@"Contents/Library/SystemExtensions"];
    if(0 == directory.length) return nil;

    for(NSString* entry in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:directory error:NULL])
    {
        if(YES != [[entry pathExtension] isEqualToString:@"systemextension"]) continue;

        return [NSBundle bundleWithURL:[NSURL fileURLWithPath:[directory stringByAppendingPathComponent:entry]]];
    }

    return nil;
}

//the mach service name an extension registers under, as its Info.plist spells it
+(NSString*)machServiceNameForExtensionBundle:(NSBundle*)extensionBundle
{
    //what launchd will read out of the file
    NSString* name = extensionBundle.infoDictionary[@"NEMachServiceName"];
    if(YES != [name isKindOfClass:NSString.class]) name = nil;

    //a build made with a team has the variable expanded already; for one made without it, it
    //stands for the (absent) team
    name = [self expandTeamPrefix:name forTeam:[self teamIdentifier]];

    //nothing readable: the name the plists are written from, under this build's team
    if(0 == name.length)
    {
        name = [NSString stringWithFormat:@"%@%@", [self teamIdentifierPrefixForTeam:[self teamIdentifier]], DAEMON_MACH_SERVICE];
    }

    return name;
}

+(NSString*)extensionMachServiceName
{
    return [self machServiceNameForExtensionBundle:[NSBundle mainBundle]];
}

+(NSString*)embeddedExtensionMachServiceName
{
    return [self machServiceNameForExtensionBundle:[self extensionBundleInApp:[NSBundle mainBundle]]];
}

@end
