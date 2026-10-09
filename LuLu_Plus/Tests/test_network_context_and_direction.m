//
//  file: test_network_context_and_direction.m
//  project: LuLu_Plus (tests)
//  description: exercises the profile condition model (conditions are OR'd between sets,
//               AND'd within a set), network-change detection, and the 'direction' field of a rule
//
//  note: this links the real sources (Shared/Rule.m, Extension/NetworkContext.m,
//        Shared/utilities.m) - see run_condition_and_direction_tests.sh
//

@import Foundation;
@import OSLog;

#import "Rule.h"
#import "consts.h"
#import "NetworkContext.h"

//defined by the extension at runtime; the sources under test only log through it
os_log_t logHandle = NULL;

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
}

/* helpers */

static const char* cstr(NSString* value)
{
    return (nil != value) ? value.UTF8String : "(nil)";
}

//for the array fields, which aren't strings
static const char* cdesc(id value)
{
    return (nil != value) ? [[value description] UTF8String] : "(nil)";
}

static NetworkContext* context(NSString* interface, NetworkInterfaceType type, NSString* ssid, NSString* bssid, NSString* gateway)
{
    NetworkContext* ctx = [[NetworkContext alloc] init];

    ctx.interface = interface;
    ctx.interfaceType = @(type);
    ctx.ssid = ssid;
    ctx.bssid = bssid;
    ctx.gateway = gateway;
    ctx.ipv4 = @[@"10.0.0.5"];
    ctx.timestamp = [NSDate date];

    return ctx;
}

//a home network, fully observable
static NetworkContext* home(void)
{
    return context(@"en0", NetworkInterfaceTypeWiFi, @"Home", @"AA:BB:CC:DD:EE:FF", @"10.0.0.1");
}

//dictionary -> JSON-ish property list, as -initFromJSON: receives it
static id ruleFromJSON(NSDictionary* overrides)
{
    NSMutableDictionary* info = [NSMutableDictionary dictionaryWithDictionary:
        @{@"key" : @"com.example.app:*:*",
          @"uuid" : [[NSUUID UUID] UUIDString],
          @"path" : @"/Applications/Example.app/Contents/MacOS/Example",
          @"name" : @"Example",
          @"endpointAddr" : @"*",
          @"endpointPort" : @"*",
          @"type" : @(RULE_TYPE_USER),
          @"scope" : @(ACTION_SCOPE_PROCESS),
          @"action" : @(RULE_STATE_ALLOW),
        }];

    [info addEntriesFromDictionary:overrides];

    return [[Rule alloc] initFromJSON:info];
}

/* condition model */

static void testConditions(void)
{
    printf("\nprofile conditions\n");

    NetworkContext* ctx = home();

    //one set: all keys must match
    check("matching single set",
          YES == [ctx satisfiesConditions:@[@{@"ssid" : @"Home"}]]);

    check("set with a non-matching key is not a match",
          YES != [ctx satisfiesConditions:@[@{@"ssid" : @"Work"}]]);

    //AND within a set
    check("set requires every key (partial match is not enough)",
          YES != [ctx satisfiesConditions:@[@{@"ssid" : @"Home", @"gateway" : @"192.168.0.1"}]]);

    check("set matches when every key does",
          YES == [ctx satisfiesConditions:@[@{@"ssid" : @"Home", @"gateway" : @"10.0.0.1"}]]);

    //OR across sets
    check("any set may match (first)",
          YES == [ctx satisfiesConditions:@[@{@"ssid" : @"Home"}, @{@"ssid" : @"Work"}]]);

    check("any set may match (later)",
          YES == [ctx satisfiesConditions:@[@{@"ssid" : @"Work"}, @{@"gateway" : @"10.0.0.1"}]]);

    check("no set matches",
          YES != [ctx satisfiesConditions:@[@{@"ssid" : @"Work"}, @{@"gateway" : @"192.168.0.1"}]]);

    //a profile with no conditions is never a network match
    check("no conditions is not a match",
          YES != [ctx satisfiesConditions:@[]]);

    check("nil conditions is not a match",
          YES != [ctx satisfiesConditions:nil]);

    //an empty set would match every network: refuse it like 'no conditions'
    check("empty condition set is not a match",
          YES != [ctx satisfiesConditions:@[@{}]]);

    //fail closed: anything we can't confirm is not a match
    check("unknown condition key is not a match",
          YES != [ctx satisfiesConditions:@[@{@"vpnProvider" : @"WireGuard"}]]);

    check("condition on an unobservable field is not a match",
          YES != [context(@"en0", NetworkInterfaceTypeWiFi, nil, nil, @"10.0.0.1")
                  satisfiesConditions:@[@{@"ssid" : @"Home"}]]);

    check("non-string condition value is not a match",
          YES != [ctx satisfiesConditions:@[@{@"ssid" : @(1)}]]);

    check("unknown key fails the set it is in, but a later set can still match",
          YES == [ctx satisfiesConditions:@[@{@"ssid" : @"Home", @"vpnProvider" : @"WireGuard"},
                                            @{@"gateway" : @"10.0.0.1"}]]);

    //interface type is compared as its condition string
    check("interface type matches by name",
          YES == [ctx satisfiesConditions:@[@{@"interfaceType" : @"Wi-Fi"}]]);

    check("interface type does not match by number",
          YES != [ctx satisfiesConditions:@[@{@"interfaceType" : @"1"}]]);

    //macs are written in either case; a network name is a name
    check("bssid ignores case",
          YES == [ctx satisfiesConditions:@[@{@"bssid" : @"aa:bb:cc:dd:ee:ff"}]]);

    check("ssid does not ignore case",
          YES != [ctx satisfiesConditions:@[@{@"ssid" : @"home"}]]);
}

/* change detection */

static void testEquality(void)
{
    printf("\nnetwork change detection\n");

    NetworkContext* a = home();
    NetworkContext* b = home();

    check("same network is not a change",
          YES == [a isEqualToContext:b]);

    //macOS re-orders DNS without the network changing
    a.dnsServers = @[@"10.0.0.1", @"1.1.1.1"];
    b.dnsServers = @[@"1.1.1.1", @"10.0.0.1"];

    check("re-ordered dns is not a change",
          YES == [a isEqualToContext:b]);

    b.gateway = @"10.0.0.2";
    check("new gateway is a change",
          YES != [a isEqualToContext:b]);

    b.gateway = @"10.0.0.1";

    //both unavailable: nothing to report
    NetworkContext* noSsidA = context(@"en0", NetworkInterfaceTypeWiFi, nil, nil, @"10.0.0.1");
    NetworkContext* noSsidB = context(@"en0", NetworkInterfaceTypeWiFi, nil, nil, @"10.0.0.1");

    check("missing ssid on both sides is not a change",
          YES == [noSsidA isEqualToContext:noSsidB]);

    check("ssid appearing is a change",
          YES != [noSsidA isEqualToContext:home()]);

    check("ssid disappearing is a change",
          YES != [home() isEqualToContext:noSsidA]);

    //the sample time always differs; it is not a network property
    NetworkContext* c = home();
    c.timestamp = [NSDate dateWithTimeIntervalSinceNow:-60];

    check("sample time is not a change",
          YES == [a isEqualToContext:c]);
}

/* rule direction */

static void testDirection(void)
{
    printf("\nrule direction\n");

    Rule* rule = nil;

    //a rule written before 'direction' existed must not silently read as outbound (0)
    rule = ruleFromJSON(@{});
    check("imported rule with no direction is 'both'",
          TrafficDirectionBoth == rule.direction.integerValue);

    rule = ruleFromJSON(@{@"direction" : @(TrafficDirectionInbound)});
    check("imported inbound stays inbound",
          TrafficDirectionInbound == rule.direction.integerValue);

    rule = ruleFromJSON(@{@"direction" : @(TrafficDirectionOutbound)});
    check("imported outbound stays outbound",
          TrafficDirectionOutbound == rule.direction.integerValue);

    //block lists / import files plists often carry numbers as strings
    rule = ruleFromJSON(@{@"direction" : @"1"});
    check("direction given as a string is parsed",
          TrafficDirectionInbound == rule.direction.integerValue);

    //an unknown value would otherwise be trusted as a valid enum
    rule = ruleFromJSON(@{@"direction" : @(7)});
    check("unknown direction falls back to 'both'",
          TrafficDirectionBoth == rule.direction.integerValue);

    rule = ruleFromJSON(@{@"direction" : @(-1)});
    check("negative direction falls back to 'both'",
          TrafficDirectionBoth == rule.direction.integerValue);

    rule = ruleFromJSON(@{@"direction" : @"both"});
    check("a word for direction is rejected (rule is dropped)",
          nil == rule);

    rule = ruleFromJSON(@{@"direction" : @"1abc"});
    check("a number followed by text is rejected",
          nil == rule);

    rule = ruleFromJSON(@{@"direction" : [NSNull null]});
    check("null direction is rejected",
          nil == rule);

    //the UI path (-init:) sees in-memory numbers
    rule = [[Rule alloc] init:@{@"path" : @"/Applications/Example.app",
                                @"name" : @"Example",
                                @"type" : @(RULE_TYPE_USER),
                                @"action" : @(RULE_STATE_BLOCK),
                                @"scope" : @(ACTION_SCOPE_ENDPOINT)}];
    check("created rule with no direction is 'both'",
          TrafficDirectionBoth == rule.direction.integerValue);

    rule = [[Rule alloc] init:@{@"path" : @"/Applications/Example.app",
                                @"name" : @"Example",
                                @"type" : @(RULE_TYPE_USER),
                                @"action" : @(RULE_STATE_BLOCK),
                                @"scope" : @(ACTION_SCOPE_ENDPOINT),
                                @"direction" : @(TrafficDirectionInbound)}];

    //archive round-trip: rules.plist is what persists this
    NSData* archived = [NSKeyedArchiver archivedDataWithRootObject:rule requiringSecureCoding:YES error:nil];
    Rule* restored = [NSKeyedUnarchiver unarchivedObjectOfClass:Rule.class fromData:archived error:nil];

    check("direction survives the rules.plist round-trip",
          TrafficDirectionInbound == restored.direction.integerValue);

    //what the serialized form looks like, for on-disk inspection
    NSString* json = [rule toJSON];

    check("direction is exported to json",
          nil != json && NSNotFound != [json rangeOfString:@"\"direction\""].location);

    //how the rule reads in the list, which is the model's business, not the table's
    NSString* incoming = NSLocalizedString(@"(incoming)", @"(incoming)");
    NSString* outgoing = NSLocalizedString(@"(outgoing)", @"(outgoing)");

    NSString* inboundNote = rule.directionNote;
    check("an inbound rule is annotated as incoming",
          (nil != inboundNote) && (0 == [incoming compare:inboundNote]));

    NSString* outboundNote = ((Rule*)ruleFromJSON(@{@"direction" : @(TrafficDirectionOutbound)})).directionNote;
    check("an outbound rule is annotated as outgoing",
          (nil != outboundNote) && (0 == [outgoing compare:outboundNote]));

    //the two branches have to say opposite things, or one of them is mis-labelled
    check("the two annotations are different words", 0 != [incoming compare:outgoing]);

    check("a rule that goes either way carries no annotation",
          nil == ((Rule*)ruleFromJSON(@{@"direction" : @(TrafficDirectionBoth)})).directionNote);

    Rule* legacy = ruleFromJSON(@{});
    check("a rule written before rules had directions carries no annotation",
          (nil != legacy) && (nil == legacy.directionNote));

    // -init: and -initWithCoder: both give a rule a direction, but an object put together by hand
    //     may still have none, and reading a missing one as 0 is how 'outbound' used to appear
    //     out of nowhere
    legacy.direction = nil;
    check("a rule whose direction was never set carries no annotation",
          nil == legacy.directionNote);

    check("the annotation survives the rules.plist round-trip",
          0 == [incoming compare:restored.directionNote]);
}

/* app-reported Wi-Fi identity */

//the adoption step is internal to the extension; name it here so the test can drive it directly
@interface NetworkContext (WiFiIntakeTests)
+(void)adoptWiFiIdentityFor:(NetworkContext*)context;
@end

static NSDictionary* wifiInfo(NSString* interface, NSString* ssid, NSString* bssid)
{
    NSMutableDictionary* info = [NSMutableDictionary dictionary];

    if(nil != interface) info[KEY_NETWORK_INTERFACE] = interface;
    if(nil != ssid) info[KEY_NETWORK_SSID] = ssid;
    if(nil != bssid) info[KEY_NETWORK_BSSID] = bssid;

    return info;
}

static void testWiFiIdentityIntake(void)
{
    printf("\napp-reported wi-fi identity\n");

    //the case this exists for: CoreWLAN answered nil in the extension
    NetworkContext* ctx = context(@"en0", NetworkInterfaceTypeWiFi, nil, nil, @"10.0.0.1");

    [NetworkContext noteWiFiIdentity:wifiInfo(@"en0", @"Lab-5G", @"aa:bb:cc:dd:ee:ff")];
    [NetworkContext adoptWiFiIdentityFor:ctx];

    check("the app's ssid fills in what the extension could not see",
          (nil != ctx.ssid) && (0 == [ctx.ssid compare:@"Lab-5G"]));
    check("the app's bssid fills in too",
          (nil != ctx.bssid) && (0 == [ctx.bssid compare:@"aa:bb:cc:dd:ee:ff"]));

    //which is the whole point: a profile keyed on the network can now match
    check("a condition on the app-reported ssid matches",
          YES == [ctx satisfiesConditions:@[@{KEY_CONDITION_SSID : @"Lab-5G"}]]);
    check("a condition on some other network's ssid still does not",
          YES != [ctx satisfiesConditions:@[@{KEY_CONDITION_SSID : @"Cafe-Guest"}]]);

    //a field the extension read for itself is never overwritten
    NetworkContext* own = context(@"en0", NetworkInterfaceTypeWiFi, @"OwnRead", nil, @"10.0.0.1");

    [NetworkContext noteWiFiIdentity:wifiInfo(@"en0", @"FromApp", @"11:22:33:44:55:66")];
    [NetworkContext adoptWiFiIdentityFor:own];

    check("the extension's own ssid is not overwritten",
          (nil != own.ssid) && (0 == [own.ssid compare:@"OwnRead"]));
    check("the app still fills the field the extension could not see",
          (nil != own.bssid) && (0 == [own.bssid compare:@"11:22:33:44:55:66"]));

    //the identity has to be for the interface actually in use
    NetworkContext* other = context(@"en1", NetworkInterfaceTypeWiFi, nil, nil, @"10.0.0.1");

    [NetworkContext noteWiFiIdentity:wifiInfo(@"en0", @"Lab-5G", @"aa:bb:cc:dd:ee:ff")];
    [NetworkContext adoptWiFiIdentityFor:other];

    check("identity sampled for a different interface is not adopted", (nil == other.ssid));

    //a payload with no interface tells us nothing about where it came from
    [NetworkContext noteWiFiIdentity:wifiInfo(nil, @"Lab-5G", nil)];

    NetworkContext* noInterface = context(@"en0", NetworkInterfaceTypeWiFi, nil, nil, @"10.0.0.1");
    [NetworkContext adoptWiFiIdentityFor:noInterface];

    check("a payload without an interface is refused (the last good one still applies)",
          (nil != noInterface.ssid) && (0 == [noInterface.ssid compare:@"Lab-5G"]));

    //not every field arrives: an open or hidden network reports no ssid
    [NetworkContext noteWiFiIdentity:wifiInfo(@"en0", nil, @"de:ad:be:ef:00:01")];

    NetworkContext* hidden = context(@"en0", NetworkInterfaceTypeWiFi, nil, nil, @"10.0.0.1");
    [NetworkContext adoptWiFiIdentityFor:hidden];

    check("a hidden network still reports the access point, and no ssid",
          (nil == hidden.ssid) && (0 == [hidden.bssid compare:@"de:ad:be:ef:00:01"]));

    //a value that isn't a string is 'not seen', never stringified into a match
    [NetworkContext noteWiFiIdentity:@{KEY_NETWORK_INTERFACE : @"en0", KEY_NETWORK_SSID : @(42)}];

    NetworkContext* badValue = context(@"en0", NetworkInterfaceTypeWiFi, nil, nil, @"10.0.0.1");
    [NetworkContext adoptWiFiIdentityFor:badValue];

    check("a non-string ssid is not adopted", (nil == badValue.ssid));

    //nil withdraws: the app stopped looking, so a profile must not keep matching on it
    [NetworkContext noteWiFiIdentity:nil];

    NetworkContext* withdrawn = context(@"en0", NetworkInterfaceTypeWiFi, nil, nil, @"10.0.0.1");
    [NetworkContext adoptWiFiIdentityFor:withdrawn];

    check("withdrawal clears what the app had reported", (nil == withdrawn.ssid));

    //so does anything that isn't a dictionary
    [NetworkContext noteWiFiIdentity:wifiInfo(@"en0", @"Lab-5G", nil)];
    [NetworkContext noteWiFiIdentity:(NSDictionary*)@"not a dictionary"];

    NetworkContext* garbage = context(@"en0", NetworkInterfaceTypeWiFi, nil, nil, @"10.0.0.1");
    [NetworkContext adoptWiFiIdentityFor:garbage];

    check("a payload that isn't a dictionary withdraws instead of half-applying",
          (nil == garbage.ssid));

    //the app re-samples every 15 seconds (see WIFI_SAMPLE_INTERVAL in App/WiFiIdentity.m); if the
    //window it has to live inside ever got shorter than that, identity would expire between two
    //samples and any profile keyed on ssid/bssid would flap
    check("reported identity outlives more than one sampling interval",
          [NetworkContext wifiIdentityMaxAge] > (15.0 * 2.0));

    //end to end: the context the extension samples picks the report up
    NetworkContext* live = [NetworkContext current];

    if(0 == live.ssid.length)
    {
        [NetworkContext noteWiFiIdentity:wifiInfo(live.interface, @"Reported-SSID", nil)];

        NetworkContext* adopted = [NetworkContext current];

        check("-current adopts what the app reported for the interface in use",
              (nil != adopted.ssid) && (0 == [adopted.ssid compare:@"Reported-SSID"]));

        //and the change check now sees the network 'change' when it appears
        NetworkContext* before = [NetworkContext current];
        [NetworkContext noteWiFiIdentity:nil];

        check("withdrawing it reads as a network change",
              (nil != before.ssid) && (YES != [before isEqualToContext:[NetworkContext current]]));
    }
    else
    {
        printf("        (skipped: this process can read the SSID itself, so there is nothing to adopt)\n");
    }

    //leave the shared state clean for the tests that follow
    [NetworkContext noteWiFiIdentity:nil];

    return;
}

/* live sample */

static void testLiveContext(void)
{
    printf("\nlive network sample\n");

    NetworkContext* ctx = [NetworkContext current];

    check("-current returns a context", nil != ctx);

    printf("        interface   = %s\n", cstr(ctx.interface));
    printf("        type        = %s\n", cstr([NetworkContext interfaceTypeString:(NetworkInterfaceType)ctx.interfaceType.integerValue]));
    printf("        ssid        = %s\n", cstr(ctx.ssid));
    printf("        bssid       = %s\n", cstr(ctx.bssid));
    printf("        gateway     = %s\n", cstr(ctx.gateway));
    printf("        ipv4        = %s\n", cdesc(ctx.ipv4));
    printf("        ipv6        = %s\n", cdesc(ctx.ipv6));
    printf("        dns         = %s\n", cdesc(ctx.dnsServers));

    check("interface name is a non-empty string",
          YES == [ctx.interface isKindOfClass:NSString.class] && 0 != ctx.interface.length);

    check("interface type is a known value",
          ctx.interfaceType.integerValue >= NetworkInterfaceTypeOther &&
          ctx.interfaceType.integerValue <= NetworkInterfaceTypeVPN);

    check("gateway is a dotted-quad when present",
          (nil == ctx.gateway) || (4 == [[ctx.gateway componentsSeparatedByString:@"."] count]));

    //sampling twice on the same network must not look like a change
    NetworkContext* again = [NetworkContext current];

    check("re-sampling the same network is not a change",
          YES == [ctx isEqualToContext:again]);

    //every field a profile can condition on resolves, or fails closed
    check("a condition on the real interface matches",
          (nil == ctx.interface) ||
          (YES == [ctx satisfiesConditions:@[@{@"interface" : ctx.interface}]]));

    check("an impossible gateway condition does not match",
          YES != [ctx satisfiesConditions:@[@{@"gateway" : @"240.0.0.1"}]]);
}

int main(int argc, const char * argv[])
{
    @autoreleasepool
    {
        printf("LuLu_Plus: conditions, change detection and direction\n");
        printf("=====================================================\n");

        testConditions();
        testEquality();
        testDirection();
        testWiFiIdentityIntake();
        testLiveContext();

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
