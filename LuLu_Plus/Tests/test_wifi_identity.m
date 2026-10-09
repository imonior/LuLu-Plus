//
//  file: test_wifi_identity.m
//  project: LuLu_Plus (tests)
//  description: runs the app's Wi-Fi sampler against a stand-in for the extension and checks what
//               it hands over - the keys the extension's intake reads, and when it withdraws
//
//  note: this links the real sources (App/WiFiIdentity.m, Extension/NetworkContext.m)
//        see run_wifi_identity_tests.sh
//
//  note: the sampler only arms once location services are granted, so this drives -sampleAndReport
//        directly. What it does NOT cover: the prompt itself, and the freshness window actually
//        expiring (that needs a minute of waiting, or a clock we could wind)
//

@import Cocoa;
@import OSLog;
@import CoreWLAN;

#import "consts.h"
#import "WiFiIdentity.h"
#import "NetworkContext.h"
#import "XPCDaemonClient.h"

/* GLOBALS (the ones the app defines, which WiFiIdentity.m logs and talks through) */

os_log_t logHandle = NULL;
XPCDaemonClient* xpcDaemonClient = nil;

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

static const char* cstr(id value)
{
    if(nil == value) return "(nil)";
    if([value isKindOfClass:NSString.class]) return [(NSString*)value UTF8String];

    return [[value description] UTF8String];
}

//run the main queue for a moment, so anything the sampler dispatches there actually runs
static void pumpMainQueue(NSTimeInterval seconds)
{
    NSDate* deadline = [NSDate dateWithTimeIntervalSinceNow:seconds];

    while([deadline timeIntervalSinceNow] > 0)
    {
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.05, true);
    }

    return;
}

/* stand-in for the extension */

//records every report the sampler sends, and answers the 'do you need this?' question
// note: deliberately NOT an XPCDaemonClient subclass - the real one opens an XPC connection in
//       -init. WiFiIdentity.m only ever sends these two messages, so an object that answers them
//       is all the sampler can tell apart
@interface FakeExtension : NSObject

@property(nonatomic, retain)NSMutableArray* reports;
@property(nonatomic, assign)NSUInteger needsAsked;
@property(nonatomic, assign)BOOL needs;

@end

@implementation FakeExtension

-(instancetype)init
{
    self = [super init];
    if(nil == self) return nil;

    self.reports = [NSMutableArray array];

    return self;
}

//updateNetworkInfo: - a nil payload is a withdrawal, which still has to be recorded
-(BOOL)updateNetworkInfo:(NSDictionary*)info
{
    [self.reports addObject:(nil != info) ? info : [NSNull null]];

    return YES;
}

-(BOOL)needsWiFiIdentity
{
    self.needsAsked++;

    return self.needs;
}

@end

/* private methods under test */

@interface WiFiIdentity (Tests)
-(void)sampleAndReport;
-(BOOL)isGranted:(CLAuthorizationStatus)status;
@end

//the adoption step is internal to the extension; name it here so the test can drive it directly
@interface NetworkContext (WiFiIntakeTests)
+(void)adoptWiFiIdentityFor:(NetworkContext*)context;
@end

/* CASES */

static void testSampleAndReport(void)
{
    printf("\nwhat the sampler hands over\n");

    FakeExtension* extension = [[FakeExtension alloc] init];
    xpcDaemonClient = (XPCDaemonClient*)extension;

    WiFiIdentity* identity = [WiFiIdentity shared];

    [identity sampleAndReport];

    //what CoreWLAN sees right now, for the same comparison the sampler makes
    CWInterface* wifi = [[CWWiFiClient sharedWiFiClient] interfaceWithName:nil];
    NSString* interface = wifi.interfaceName;

    check("the sampler reported once", (1 == [extension.reports count]));

    //no Wi-Fi hardware: say so, rather than leave the extension holding an old network
    if(0 == interface.length)
    {
        check("without a Wi-Fi interface the sampler withdraws the identity",
              (YES == [[extension.reports objectAtIndex:0] isKindOfClass:[NSNull class]]));

        printf("        (no Wi-Fi interface on this machine, so that is the branch taken)\n");
        return;
    }

    NSDictionary* report = [extension.reports objectAtIndex:0];

    printf("        interface = %s\n", cstr(report[KEY_NETWORK_INTERFACE]));
    printf("        ssid      = %s\n", cstr(report[KEY_NETWORK_SSID]));
    printf("        bssid     = %s\n", cstr(report[KEY_NETWORK_BSSID]));

    check("a Wi-Fi interface is reported as a payload, not a withdrawal",
          YES == [report isKindOfClass:[NSDictionary class]]);

    //the interface name has to be the one the extension is looking at, or it refuses the report
    NSString* reported = report[KEY_NETWORK_INTERFACE];

    check("the interface is named with the key the extension reads",
          (YES == [reported isKindOfClass:NSString.class]) && (0 == [reported compare:interface]));

    //empty fields are left out: an open network's SSID is @"", which is not a name to match on
    check("no field is reported empty",
          (nil == report[KEY_NETWORK_SSID]) || (0 != [report[KEY_NETWORK_SSID] length]));
    check("no field is reported empty (bssid)",
          (nil == report[KEY_NETWORK_BSSID]) || (0 != [report[KEY_NETWORK_BSSID] length]));

    //this is the hand-off the whole feature rests on: the payload the app builds is accepted by
    //the extension's intake, and an ssid travelling in it lands in the sampled context
    // note: ssid is only added for the check - without location access the sampler can't read it,
    //       but the interface key it used is the one under test here
    NSMutableDictionary* withSSID = [report mutableCopy];
    withSSID[KEY_NETWORK_SSID] = @"Reported-By-The-App";

    [NetworkContext noteWiFiIdentity:withSSID];

    //a context for that interface, with nothing CoreWLAN could see for itself
    NetworkContext* context = [[NetworkContext alloc] init];
    context.interface = interface;
    context.interfaceType = @(NetworkInterfaceTypeWiFi);

    [NetworkContext adoptWiFiIdentityFor:context];

    check("the extension takes the report the sampler built, ssid and all",
          (nil != context.ssid) && (0 == [context.ssid compare:@"Reported-By-The-App"]));

    check("a profile condition on that ssid matches",
          YES == [context satisfiesConditions:@[@{KEY_CONDITION_SSID : @"Reported-By-The-App"}]]);

    //and a report for a different interface is not adopted
    NetworkContext* other = [[NetworkContext alloc] init];
    other.interface = [interface stringByAppendingString:@"x"];
    other.interfaceType = @(NetworkInterfaceTypeWiFi);

    [NetworkContext adoptWiFiIdentityFor:other];

    check("a report for another interface is not adopted", (nil == other.ssid));

    [NetworkContext noteWiFiIdentity:nil];

    return;
}

static void testRefreshGate(void)
{
    printf("\nonly ask when the extension wants it\n");

    FakeExtension* extension = [[FakeExtension alloc] init];
    extension.needs = NO;

    xpcDaemonClient = (XPCDaemonClient*)extension;

    WiFiIdentity* identity = [WiFiIdentity shared];

    //nothing keys on Wi-Fi identity -> the app has no business asking for location access,
    //and no business pushing samples at the extension
    [identity refresh];
    pumpMainQueue(0.5);

    check("the sampler asks the extension whether it needs the identity",
          (1 == [extension needsAsked]));
    check("with nothing asking for it, nothing is reported",
          (0 == [extension.reports count]));

    //the promise behind that gate: the app does not go near CoreLocation - and so has no reason
    //to ask the user for location access - until a profile actually keys on the network
    check("with nothing asking for it, no location manager is even created",
          nil == [identity valueForKey:@"locationCom"]);

    return;
}

// note: must run before anything arms the sampler, as it inspects the shared singleton
//the macOS-specific trap: there is no 'while using' authorization state here, so 'granted' has to
//be read off the only authorized value CoreLocation uses on this platform
static void testGranted(void)
{
    printf("\nwhat counts as granted\n");

    WiFiIdentity* identity = [WiFiIdentity shared];

    check("authorized counts as granted",
          YES == [identity isGranted:kCLAuthorizationStatusAuthorizedAlways]);
    check("not determined does not",
          YES != [identity isGranted:kCLAuthorizationStatusNotDetermined]);
    check("denied does not",
          YES != [identity isGranted:kCLAuthorizationStatusDenied]);
    check("restricted does not",
          YES != [identity isGranted:kCLAuthorizationStatusRestricted]);

    return;
}

/* MAIN */

int main(int argc, const char* argv[])
{
    @autoreleasepool
    {
        logHandle = os_log_create("com.imonior.lulu-plus", "tests");

        printf("LuLu_Plus: app-side Wi-Fi identity sampling\n");
        printf("===========================================\n");

        testSampleAndReport();
        testRefreshGate();
        testGranted();

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
