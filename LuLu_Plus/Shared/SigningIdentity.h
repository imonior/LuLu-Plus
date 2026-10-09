//
//  file: SigningIdentity.h
//  project: lulu_plus (shared)
//  description: who signed this build, and the names that follow from it (header)
//
//  copyright (c) 2026 LuLu_Plus. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface SigningIdentity : NSObject

//the team that signed this process; nil for an unsigned or ad-hoc build
+(NSString*)teamIdentifier;

//what $(TeamIdentifierPrefix) stands for: the team with a dot, or nothing at all
+(NSString*)teamIdentifierPrefixForTeam:(NSString*)team;

//replace the variable with what the build would have expanded it to
+(NSString*)expandTeamPrefix:(NSString*)name forTeam:(NSString*)team;

//the requirement the extension puts on the app that connects: this build's app, signed by the
//same team
+(NSString*)clientRequirementForTeam:(NSString*)team;
+(NSString*)clientRequirement;

//...and the variant a macOS 13+ listener hands to the system, which floors the app's version
+(NSString*)listenerRequirementForTeam:(NSString*)team;
+(NSString*)listenerRequirement;

//the system extension embedded in an app bundle, if there is one
+(NSBundle*)extensionBundleInApp:(NSBundle*)appBundle;

//the mach service name an extension registers under, as its Info.plist spells it
+(NSString*)machServiceNameForExtensionBundle:(NSBundle*)extensionBundle;

//the name this process's own bundle registers under (the extension's call)
+(NSString*)extensionMachServiceName;

//and the one the app looks for, read from the extension it embeds
+(NSString*)embeddedExtensionMachServiceName;

@end
