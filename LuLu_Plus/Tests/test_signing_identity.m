//
//  file: test_signing_identity.m
//  project: LuLu_Plus (tests)
//  description: drives the identity a build derives from its own signature: the requirement the
//               extension puts on the app that connects, and the mach service name both halves
//               look each other up by - against the real source, real Info.plist files in
//               throwaway bundles, and the running (unsigned) test binary
//
//  note: this links the real source (Shared/SigningIdentity.m)
//        see run_signing_identity_tests.sh
//
//  note: what it does NOT cover: that the system accepts a signed pair, or that launchd registers
//        exactly this name - both need a signed build to observe, which cannot be made here. What
//        it pins is what the code derives, and that the identifiers it derives agree with the ones
//        the project actually builds (project file, plists, consts.h), and that no step which does
//        not go through the compiler names another build's signing identity (the project's team
//        settings, the dmg step)
//

@import Foundation;
@import Security;

#import "consts.h"
#import "SigningIdentity.h"

#include <unistd.h>

/* harness */

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
// note: '[nil compare:...]' answers 0, so a plain '0 == [value compare:x]' reads a value that was
//       never produced as the one that was
static BOOL same(id value, NSString* expected)
{
    return (YES == [value isKindOfClass:NSString.class]) && (0 == [value compare:expected]);
}

//the app this project builds; the project file and the requirement both have to name it
static NSString* kAppIdentifier(void)
{
    return @"com.imonior.lulu-plus.app";
}

//the name the extension's Info.plist is written from, before the build expands the team into it
static NSString* kServiceName(void)
{
    return @"$(TeamIdentifierPrefix)com.imonior.lulu-plus";
}

//the files whose agreement with the derived identity is checked below
static NSString* gConstsPath = nil;
static NSString* gExtensionPlistPath = nil;
static NSString* gListenerPath = nil;
static NSString* gClientPath = nil;
static NSString* gProjectPath = nil;
static NSString* gDmgScriptPath = nil;

static NSString* gFixtureRoot = nil;

/* FIXTURES */

//the tree a built app has: <app>/Contents/Library/SystemExtensions/<name>.systemextension
// note: 'infoPlist' nil leaves the extension without a plist, the way a broken embedding would
static NSString* writeAppWithExtension(NSString* appName, NSString* extensionName, NSDictionary* infoPlist)
{
    NSString* appPath = [gFixtureRoot stringByAppendingPathComponent:appName];
    NSString* extensionPath = [[appPath stringByAppendingPathComponent:@"Contents/Library/SystemExtensions"] stringByAppendingPathComponent:extensionName];

    //a plist lives inside Contents/, the way a bundle keeps it
    NSString* directory = (nil != infoPlist) ? [extensionPath stringByAppendingPathComponent:@"Contents"] : extensionPath;

    [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL];

    if(nil != infoPlist)
    {
        [infoPlist writeToFile:[directory stringByAppendingPathComponent:@"Info.plist"] atomically:YES];
    }

    return appPath;
}

static NSBundle* bundleAt(NSString* path)
{
    return [NSBundle bundleWithURL:[NSURL fileURLWithPath:path]];
}

/* THE REQUIREMENT THE EXTENSION IMPOSES */

static void testRequirements(void)
{
    NSString* team = @"ABCDE12345";

    //what the team that signed the extension pins the client to
    NSString* wanted = [NSString stringWithFormat:@"anchor apple generic and identifier \"%@\" and certificate leaf [subject.OU] = \"%@\"", kAppIdentifier(), team];
    check("the requirement names the app, by the team that signed the extension",
          same([SigningIdentity clientRequirementForTeam:team], wanted));

    //the leaf's OU is where a certificate keeps the team
    NSString* requirement = [SigningIdentity clientRequirementForTeam:team];
    check("...and pins it through the team field, not a name",
          (NSNotFound != [requirement rangeOfString:@"[subject.OU] = \"ABCDE12345\""].location) &&
          (NSNotFound == [requirement rangeOfString:@"subject.CN"].location) &&
          (NSNotFound == [requirement rangeOfString:@"Objective-See"].location));

    //a build that carries no team has to lean on the identifier alone, and say so
    check("a build with no team checks the identifier and nothing else",
          same([SigningIdentity clientRequirementForTeam:nil], [NSString stringWithFormat:@"identifier \"%@\"", kAppIdentifier()]));
    check("...nor a lonely empty team",
          same([SigningIdentity clientRequirementForTeam:@""], [NSString stringWithFormat:@"identifier \"%@\"", kAppIdentifier()]));

    //the macOS 13+ variant the system is handed also floors the app's version
    NSString* listenerWanted = [NSString stringWithFormat:@"%@ and info [CFBundleShortVersionString] >= \"2.0.0\"", wanted];
    check("the listener's requirement floors the app at v2.0.0",
          same([SigningIdentity listenerRequirementForTeam:team], listenerWanted));
    check("...and does the same for a build with no team",
          same([SigningIdentity listenerRequirementForTeam:nil],
               [NSString stringWithFormat:@"identifier \"%@\" and info [CFBundleShortVersionString] >= \"2.0.0\"", kAppIdentifier()]));

    //each of them has to be one the system can compile
    SecRequirementRef compiled = NULL;
    BOOL allParse = YES;
    NSArray<NSString*>* all = @[[SigningIdentity clientRequirementForTeam:team],
                                [SigningIdentity clientRequirementForTeam:nil],
                                [SigningIdentity listenerRequirementForTeam:team],
                                [SigningIdentity listenerRequirementForTeam:nil]];

    for(NSString* text in all)
    {
        if(errSecSuccess != SecRequirementCreateWithString((__bridge CFStringRef)text, kSecCSDefaultFlags, &compiled))
        {
            allParse = NO;
            printf("   not a requirement: %s\n", text.UTF8String);
        }

        if(NULL != compiled)
        {
            CFRelease(compiled);
            compiled = NULL;
        }
    }

    check("every requirement the extension can build is one the system compiles", allParse);

    //what this (unsigned) build derives for itself is what it derives for its absent team
    check("an unsigned build reports no team", nil == [SigningIdentity teamIdentifier]);
    check("...so its own requirement is the identifier-only one",
          same([SigningIdentity clientRequirement], [SigningIdentity clientRequirementForTeam:nil]) &&
          same([SigningIdentity listenerRequirement], [SigningIdentity listenerRequirementForTeam:nil]));

    return;
}

/* WHAT THE TEAM PREFIX STANDS FOR */

static void testExpansion(void)
{
    check("the prefix a team stands for carries its dot",
          same([SigningIdentity teamIdentifierPrefixForTeam:@"ABCDE12345"], @"ABCDE12345."));
    check("...and a build without a team stands for nothing",
          same([SigningIdentity teamIdentifierPrefixForTeam:nil], @"") &&
          same([SigningIdentity teamIdentifierPrefixForTeam:@""], @""));

    check("the plist's variable is expanded the way the build would",
          same([SigningIdentity expandTeamPrefix:kServiceName() forTeam:@"ABCDE12345"], @"ABCDE12345.com.imonior.lulu-plus"));
    check("...with no team left standing when there is none",
          same([SigningIdentity expandTeamPrefix:kServiceName() forTeam:nil], @"com.imonior.lulu-plus"));
    check("a name written without the variable comes back as it was",
          same([SigningIdentity expandTeamPrefix:@"com.example.app" forTeam:@"ABCDE12345"], @"com.example.app"));
    check("something that isn't a name at all is refused",
          nil == [SigningIdentity expandTeamPrefix:nil forTeam:@"ABCDE12345"]);

    return;
}

/* THE NAME BOTH HALVES LOOK EACH OTHER UP BY */

static void testMachServiceName(void)
{
    //a build made with a team: the plist carries the expanded name
    NSString* sharp = writeAppWithExtension(@"Sharp.app",
                                             @"com.imonior.lulu-plus.extension.systemextension",
                                             @{@"NEMachServiceName" : @"ABCDE12345.com.imonior.lulu-plus"});

    //a build made without one: the variable is left standing
    NSString* unexpanded = writeAppWithExtension(@"Unexpanded.app",
                                                  @"com.imonior.lulu-plus.extension.systemextension",
                                                  @{@"NEMachServiceName" : kServiceName()});

    //a plist without the key, and an extension without a plist at all
    NSString* keyless = writeAppWithExtension(@"Keyless.app",
                                               @"com.imonior.lulu-plus.extension.systemextension",
                                               @{@"CFBundleIdentifier" : @"com.imonior.lulu-plus.extension"});
    NSString* plistless = writeAppWithExtension(@"Plistless.app",
                                                 @"com.imonior.lulu-plus.extension.systemextension",
                                                 nil);

    //an app whose plug-ins hold something that is not a system extension
    NSString* decoy = writeAppWithExtension(@"Decoy.app",
                                             @"LookAtMe.app",
                                             @{@"NEMachServiceName" : @"ABCDE12345.com.imonior.lulu-plus"});

    //sanity: the fixture reads as the bundle the rest of this leans on
    NSBundle* embedded = [SigningIdentity extensionBundleInApp:bundleAt(sharp)];
    check("the app's embedded extension is found",
          same(embedded.infoDictionary[@"NEMachServiceName"], @"ABCDE12345.com.imonior.lulu-plus"));

    //the extension side: its own Info.plist says the name
    check("...and registers under the name that carries the team",
          same([SigningIdentity machServiceNameForExtensionBundle:embedded], @"ABCDE12345.com.imonior.lulu-plus"));

    //the app side: the same reading, off the extension it embeds - so both halves agree without a
    //constant naming the team
    check("a name whose variable was left standing is read as the base one",
          same([SigningIdentity machServiceNameForExtensionBundle:[SigningIdentity extensionBundleInApp:bundleAt(unexpanded)]],
               @"com.imonior.lulu-plus"));

    //nothing to read: the name the plists are written from
    check("a plist without the key falls back to the base name",
          same([SigningIdentity machServiceNameForExtensionBundle:[SigningIdentity extensionBundleInApp:bundleAt(keyless)]],
               DAEMON_MACH_SERVICE));
    check("an extension without a plist falls back to the base name",
          same([SigningIdentity machServiceNameForExtensionBundle:[SigningIdentity extensionBundleInApp:bundleAt(plistless)]],
               DAEMON_MACH_SERVICE));

    check("a bundle that isn't there falls back to the base name",
          same([SigningIdentity machServiceNameForExtensionBundle:nil], DAEMON_MACH_SERVICE));
    check("an app without an embedded extension yields none",
          nil == [SigningIdentity extensionBundleInApp:bundleAt(decoy)] &&
          same([SigningIdentity machServiceNameForExtensionBundle:[SigningIdentity extensionBundleInApp:bundleAt(decoy)]],
               DAEMON_MACH_SERVICE));

    //the wrappers read this process's own bundle, which is the built test binary
    check("this bundle names no extension, so the extension's own reading falls back too",
          same([SigningIdentity extensionMachServiceName], DAEMON_MACH_SERVICE));
    check("...and so does the app's",
          same([SigningIdentity embeddedExtensionMachServiceName], DAEMON_MACH_SERVICE));

    return;
}

/* WHAT THE BUILD ACTUALLY SHIPS */

static NSString* contents(NSString* path)
{
    return [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
}

//whether the text carries this bit
static BOOL has(NSString* text, NSString* needle)
{
    return (NSNotFound != [text rangeOfString:needle].location);
}

//the wiring no unit test can reach: which name each side asks for, and that no identity from
//another build is written down anywhere
static void testShippedWiring(void)
{
    NSString* consts = contents(gConstsPath);
    NSString* extensionPlist = contents(gExtensionPlistPath);
    NSString* listener = contents(gListenerPath);
    NSString* client = contents(gClientPath);
    NSString* project = contents(gProjectPath);
    NSString* dmg = contents(gDmgScriptPath);

    check("the shipped files are all readable",
          (nil != consts) && (nil != extensionPlist) && (nil != listener) && (nil != client) &&
          (nil != project) && (nil != dmg));
    if((nil == consts) || (nil == extensionPlist) || (nil == listener) || (nil == client) ||
       (nil == project) || (nil == dmg)) return;

    //no identity from another build survives anywhere
    check("no signing identity is written down in consts.h",
          (NO == has(consts, @"VBG97UB4TA")) &&
          (NO == has(consts, @"SIGNING_AUTH")) &&
          (NO == has(consts, @"Objective-See, LLC (")));
    check("the mach name in consts.h is the base one",
          has(consts, @"#define DAEMON_MACH_SERVICE @\"com.imonior.lulu-plus\""));
    check("the requirement text lives in one place",
          (NO == has(listener, @"certificate leaf")) &&
          (NO == has(listener, @"SIGNING_AUTH")));
    check("the client names no service of its own",
          NO == has(client, @"DAEMON_MACH_SERVICE"));

    //the steps that never go through the compiler: the project's signing settings, and the dmg step
    check("the project sets no team but the one each build derives",
          (NO == has(project, @"VBG97UB4TA")) &&
          (NO == has(project, @"Objective-See, LLC (")));
    check("the dmg step takes its identity from whoever builds it",
          (NO == has(dmg, @"VBG97UB4TA")) &&
          (NO == has(dmg, @"Developer ID Application:")) &&
          has(dmg, @"--sign \"$SIGN_IDENTITY\""));

    //and each side asks this build what to use
    check("the extension listens on the name this build registered",
          has(listener, @"[SigningIdentity extensionMachServiceName]"));
    check("...and hands the system the requirement this build derives",
          has(listener, @"[SigningIdentity listenerRequirement]") &&
          has(listener, @"[SigningIdentity clientRequirement]"));
    check("the app looks for the extension this build embeds",
          has(client, @"[SigningIdentity embeddedExtensionMachServiceName]"));

    //the identifiers the requirement names are the ones the project and the plist are built with
    check("the app the project builds carries the identifier the requirement names",
          has(project, @"PRODUCT_BUNDLE_IDENTIFIER = \"com.imonior.lulu-plus.app\";"));
    check("consts.h names the same app",
          has(consts, @"#define APP_ID @\"com.imonior.lulu-plus.app\""));
    check("the extension's plist is written from the name both halves read",
          has(extensionPlist, [NSString stringWithFormat:@"<string>%@</string>", kServiceName()]));

    return;
}

int main(int argc, const char* argv[])
{
    @autoreleasepool
    {
        if(argc < 7)
        {
            fprintf(stderr, "usage: %s <consts.h> <Extension/Info.plist> <XPCListener.m> <XPCDaemonClient.m> <project.pbxproj> <createDMG.sh>\n", argv[0]);
            return 2;
        }

        gConstsPath = [@(argv[1]) copy];
        gExtensionPlistPath = [@(argv[2]) copy];
        gListenerPath = [@(argv[3]) copy];
        gClientPath = [@(argv[4]) copy];
        gProjectPath = [@(argv[5]) copy];
        gDmgScriptPath = [@(argv[6]) copy];

        gFixtureRoot = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"lulu_plus-signing-identity-%d", getpid()]];

        printf("== the identity a build derives from its own signature ==\n");

        testRequirements();
        testExpansion();
        testMachServiceName();
        testShippedWiring();

        [[NSFileManager defaultManager] removeItemAtPath:gFixtureRoot error:NULL];

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
