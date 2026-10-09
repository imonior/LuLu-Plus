//
//  file: NetworkContext.m
//  project: LuLu_Plus
//  description: the network an interface is attached to (Wi-Fi identity, gateway, addresses, DNS)
//               and the monitor that reports when that changes
//
//  copyright (c) 2026 LuLu_Plus. All rights reserved.
//

#import "NetworkContext.h"
#import "consts.h"

#import <ifaddrs.h>
#import <arpa/inet.h>
#import <net/if.h>

/* GLOBALS */

//log handle
extern os_log_t logHandle;

//how often to re-sample
// note: the extension runs under dispatch_main() (main.m), which drains the main queue but
// owns no run loop, so SCNetworkReachability/SCDynamicStore notification sources never fire
// -> re-sampling runs off a dispatch timer instead
#define NETWORK_CONTEXT_POLL_INTERVAL (5ull * NSEC_PER_SEC)

//dynamic store keys
#define STORE_KEY_IPV4 @"State:/Network/Global/IPv4"
#define STORE_KEY_DNS @"State:/Network/Global/DNS"

//how long Wi-Fi identity reported by the app is trusted for
// note: long enough to survive the app being backgrounded, short enough that a quit app's
//       last network doesn't keep posing as the current one
#define WIFI_IDENTITY_MAX_AGE 60.0

/* Wi-Fi identity reported by the app (see +noteWiFiIdentity:) */

//what the app last saw, and when
// note: guarded with @synchronized([NetworkContext class]) - the class object is a stable token,
//       so there's no half-built lock to race over
static NSString* gWiFiIdentityInterface = nil;
static NSString* gWiFiIdentitySSID = nil;
static NSString* gWiFiIdentityBSSID = nil;
static CFAbsoluteTime gWiFiIdentityAt = 0;

@implementation NetworkContext

+(instancetype)current
{
    NetworkContext* context = [[NetworkContext alloc] init];

    //primary interface + default gateway
    NSDictionary* ipv4State = [self globalStateFor:STORE_KEY_IPV4];
    context.interface = ipv4State[@"PrimaryInterface"];
    context.gateway = ipv4State[@"Router"];

    //no primary interface (offline, or still converging)?
    if(0 == context.interface.length)
    {
        //dbg msg
        os_log_debug(logHandle, "no primary interface, IPv4 state is %{public}@", ipv4State);

        context.timestamp = [NSDate date];
        return context;
    }

    //addresses
    [self addressesFor:context.interface into:context];

    //dns
    context.dnsServers = [self dnsServers];

    //type + Wi-Fi identity
    [self applyWiFiInfoFor:context.interface into:context];

    //SSID/BSSID the app saw, when CoreWLAN won't show them to us
    [self adoptWiFiIdentityFor:context];

    //when
    context.timestamp = [NSDate date];

    return context;
}

//read a dictionary out of the dynamic store
+(NSDictionary*)globalStateFor:(NSString*)key
{
    SCDynamicStoreRef store = SCDynamicStoreCreate(NULL, CFSTR("com.imonior.lulu-plus.networkcontext"), NULL, NULL);
    if(NULL == store) return nil;

    CFPropertyListRef value = SCDynamicStoreCopyValue(store, (__bridge CFStringRef)key);
    NSDictionary* state = ((nil != value) && [(__bridge id)value isKindOfClass:NSDictionary.class]) ? (__bridge NSDictionary*)value : nil;

    if(nil != value) CFRelease(value);
    CFRelease(store);

    return state;
}

//all addresses held by `interface`
+(void)addressesFor:(NSString*)interface into:(NetworkContext*)context
{
    NSMutableArray* ipv4 = [NSMutableArray array];
    NSMutableArray* ipv6 = [NSMutableArray array];

    struct ifaddrs* interfaces = NULL;
    if(0 == getifaddrs(&interfaces))
    {
        for(struct ifaddrs* cursor = interfaces; NULL != cursor; cursor = cursor->ifa_next)
        {
            if(NULL == cursor->ifa_addr) continue;
            if(0 != strcmp(cursor->ifa_name, interface.UTF8String)) continue;

            char buffer[INET6_ADDRSTRLEN] = {0};
            sa_family_t family = cursor->ifa_addr->sa_family;

            if(AF_INET == family)
            {
                struct sockaddr_in* addr = (struct sockaddr_in*)(void*)cursor->ifa_addr;
                if(NULL != inet_ntop(AF_INET, &addr->sin_addr, buffer, sizeof(buffer)))
                {
                    [ipv4 addObject:[NSString stringWithUTF8String:buffer]];
                }
            }
            else if(AF_INET6 == family)
            {
                struct sockaddr_in6* addr = (struct sockaddr_in6*)(void*)cursor->ifa_addr;
                if(NULL != inet_ntop(AF_INET6, &addr->sin6_addr, buffer, sizeof(buffer)))
                {
                    [ipv6 addObject:[NSString stringWithUTF8String:buffer]];
                }
            }
        }

        freeifaddrs(interfaces);
    }

    context.ipv4 = ipv4.count ? ipv4 : nil;
    context.ipv6 = ipv6.count ? ipv6 : nil;
}

//configured resolvers
+(NSArray*)dnsServers
{
    NSArray* servers = [self globalStateFor:STORE_KEY_DNS][@"ServerAddresses"];
    if(YES != [servers isKindOfClass:NSArray.class]) return nil;

    //keep only what we can name as an address
    NSMutableArray* addresses = [NSMutableArray array];
    for(id server in servers)
    {
        if(YES == [server isKindOfClass:NSString.class]) [addresses addObject:server];
    }

    return addresses.count ? addresses : nil;
}

//interface type, plus SSID/BSSID when CoreWLAN will hand them over
+(void)applyWiFiInfoFor:(NSString*)interface into:(NetworkContext*)context
{
    CWInterface* wifi = [[CWWiFiClient sharedWiFiClient] interfaceWithName:interface];

    if(nil != wifi)
    {
        context.interfaceType = @(NetworkInterfaceTypeWiFi);
        context.ssid = wifi.ssid;
        context.bssid = wifi.bssid;

        //macOS 13+ hides SSID/BSSID unless the process is authorized for location services, and a
        //system extension has no UI to ask -> nil is the expected case here. the app can be
        //authorized, and reports what it sees (see +noteWiFiIdentity:)
        if(0 == context.ssid.length)
        {
            os_log_info(logHandle, "adopted Wi-Fi interface '%{public}@', but SSID/BSSID are unavailable to the extension (will use what the app reports)", interface);
        }
    }
    else if([interface hasPrefix:@"utun"] || [interface hasPrefix:@"ipsec"] || [interface hasPrefix:@"ppp"])
    {
        context.interfaceType = @(NetworkInterfaceTypeVPN);
    }
    else if([interface hasPrefix:@"en"] || [interface hasPrefix:@"bridge"])
    {
        context.interfaceType = @(NetworkInterfaceTypeEthernet);
    }
    else
    {
        context.interfaceType = @(NetworkInterfaceTypeOther);
    }
}

//use the Wi-Fi identity the app reported, if we couldn't see it ourselves
// note: ours wins whenever CoreWLAN gave us an SSID, so a location-authorized extension (or a
//       macOS that stops gating this) is unaffected by whatever the app last said
+(void)adoptWiFiIdentityFor:(NetworkContext*)context
{
    //nothing to fill in?
    if((0 != context.ssid.length) && (0 != context.bssid.length)) return;

    //what the app saw
    NSString* interface = nil;
    NSString* ssid = nil;
    NSString* bssid = nil;

    @synchronized(self)
    {
        //nothing reported (yet), or withdrawn?
        if(0 == gWiFiIdentityAt) return;

        //gone stale? (the app quit, slept, or stopped reporting)
        // ...forget it rather than keep switching profiles on a network that isn't ours
        if(CFAbsoluteTimeGetCurrent() - gWiFiIdentityAt > [self wifiIdentityMaxAge])
        {
            gWiFiIdentityInterface = nil;
            gWiFiIdentitySSID = nil;
            gWiFiIdentityBSSID = nil;
            gWiFiIdentityAt = 0;

            return;
        }

        interface = gWiFiIdentityInterface;
        ssid = gWiFiIdentitySSID;
        bssid = gWiFiIdentityBSSID;
    }

    //the app was looking at a different interface than the one in use?
    // ...its Wi-Fi identity isn't ours to adopt
    if(YES != [interface isEqualToString:context.interface]) return;

    //fill in only what we couldn't see
    if((0 == context.ssid.length) && (0 != ssid.length)) context.ssid = ssid;
    if((0 == context.bssid.length) && (0 != bssid.length)) context.bssid = bssid;
}

+(NSTimeInterval)wifiIdentityMaxAge
{
    return WIFI_IDENTITY_MAX_AGE;
}

//take in the Wi-Fi identity the app sampled (nil withdraws it)
+(void)noteWiFiIdentity:(NSDictionary*)info
{
    //withdrawn?
    // ...drop what we were holding, so profiles stop matching on a network the app no longer sees
    if(YES != [info isKindOfClass:[NSDictionary class]])
    {
        @synchronized(self)
        {
            gWiFiIdentityInterface = nil;
            gWiFiIdentitySSID = nil;
            gWiFiIdentityBSSID = nil;
            gWiFiIdentityAt = 0;
        }

        //dbg msg
        os_log_debug(logHandle, "wi-fi identity withdrawn by the app");

        return;
    }

    //extract
    NSString* interface = info[KEY_NETWORK_INTERFACE];
    NSString* ssid = info[KEY_NETWORK_SSID];
    NSString* bssid = info[KEY_NETWORK_BSSID];

    //need an interface to know what it applies to
    if(YES != [interface isKindOfClass:[NSString class]] || 0 == interface.length)
    {
        //err msg
        os_log_error(logHandle, "ERROR: wi-fi identity without an interface: %{public}@", info);
        return;
    }

    //anything that isn't a string counts as 'not seen'
    if(YES != [ssid isKindOfClass:[NSString class]]) ssid = nil;
    if(YES != [bssid isKindOfClass:[NSString class]]) bssid = nil;

    @synchronized(self)
    {
        gWiFiIdentityInterface = [interface copy];
        gWiFiIdentitySSID = [ssid copy];
        gWiFiIdentityBSSID = [bssid copy];
        gWiFiIdentityAt = CFAbsoluteTimeGetCurrent();
    }

    //dbg msg
    os_log_debug(logHandle, "wi-fi identity from the app: %{public}@ ssid=%{public}@ bssid=%{public}@",
                 interface, ssid, bssid);

    return;
}

-(BOOL)isEqualToContext:(NetworkContext*)other
{
    if(self == other) return YES;
    if(nil == other) return NO;

    //what makes it 'a different network'
    // note: DNS is deliberately left out - macOS re-orders it without the network changing.
    // note: nil == nil counts as equal, so an unavailable SSID doesn't read as 'changed'
    return (YES == [self compareIfChanged:self.interface to:other.interface]) &&
           (YES == [self compareIfChanged:self.interfaceType to:other.interfaceType]) &&
           (YES == [self compareIfChanged:self.ssid to:other.ssid]) &&
           (YES == [self compareIfChanged:self.bssid to:other.bssid]) &&
           (YES == [self compareIfChanged:self.gateway to:other.gateway]) &&
           (YES == [self compareIfChanged:self.ipv4 to:other.ipv4]);
}

//YES when both are set the same (either both nil, or equal)
-(BOOL)compareIfChanged:(id)mine to:(id)theirs
{
    if((nil == mine) && (nil == theirs)) return YES;
    if((nil == mine) || (nil == theirs)) return NO;

    return [mine isEqual:theirs];
}

-(BOOL)satisfiesConditions:(NSArray*)conditions
{
    //not a list, or empty?
    // never a match - see the header
    if(YES != [conditions isKindOfClass:NSArray.class] || 0 == conditions.count) return NO;

    //condition sets are OR'd together
    for(id conditionSet in conditions)
    {
        if(YES != [conditionSet isKindOfClass:NSDictionary.class])
        {
            //err msg
            os_log_error(logHandle, "ERROR: profile condition should be a dictionary, not %{public}@", [conditionSet class]);
            continue;
        }

        if(YES == [self satisfiesConditionSet:conditionSet]) return YES;
    }

    return NO;
}

//keys inside one condition set are AND'd together
-(BOOL)satisfiesConditionSet:(NSDictionary*)conditionSet
{
    //empty set would match every network - refuse it, same as having no conditions
    if(0 == conditionSet.count) return NO;

    for(NSString* key in conditionSet)
    {
        //what the profile wants to see
        id expected = conditionSet[key];
        if(YES != [expected isKindOfClass:NSString.class])
        {
            //err msg
            os_log_error(logHandle, "ERROR: condition '%{public}@' should be a string, not %{public}@", key, [expected class]);
            return NO;
        }

        //what we can actually see
        // note: nil covers both 'not a condition we know' and 'not observable here' -
        //       neither can be confirmed, so neither is a match
        NSString* observed = [self valueForConditionKey:key];
        if(0 == observed.length)
        {
            //dbg msg
            os_log_debug(logHandle, "condition '%{public}@' can't be checked against this network", key);
            return NO;
        }

        //macs are written in either case, but a name is a name
        BOOL ignoreCase = (0 == [key compare:KEY_CONDITION_BSSID options:NSCaseInsensitiveSearch]);

        BOOL matches = ignoreCase ? (NSOrderedSame == [observed caseInsensitiveCompare:expected])
                                  : (0 == [observed compare:expected]);
        if(YES != matches) return NO;
    }

    return YES;
}

//the value a condition key looks at
-(NSString*)valueForConditionKey:(NSString*)key
{
    if(0 == [key compare:KEY_CONDITION_INTERFACE]) return self.interface;
    if(0 == [key compare:KEY_CONDITION_INTERFACE_TYPE]) return [NetworkContext interfaceTypeString:(NetworkInterfaceType)self.interfaceType.integerValue];
    if(0 == [key compare:KEY_CONDITION_SSID]) return self.ssid;
    if(0 == [key compare:KEY_CONDITION_BSSID]) return self.bssid;
    if(0 == [key compare:KEY_CONDITION_GATEWAY]) return self.gateway;

    //err msg
    os_log_error(logHandle, "ERROR: unknown profile condition '%{public}@'", key);

    return nil;
}

-(NSDictionary*)toDictionary
{
    NSMutableDictionary* dict = [NSMutableDictionary dictionary];

    if(nil != self.interface) dict[@"interface"] = self.interface;
    if(nil != self.interfaceType) dict[@"interfaceType"] = self.interfaceType;
    if(nil != self.interfaceType) dict[@"interfaceTypeString"] = [NetworkContext interfaceTypeString:(NetworkInterfaceType)self.interfaceType.integerValue];
    if(nil != self.ssid) dict[@"ssid"] = self.ssid;
    if(nil != self.bssid) dict[@"bssid"] = self.bssid;
    if(nil != self.gateway) dict[@"gateway"] = self.gateway;
    if(nil != self.ipv4) dict[@"ipv4"] = self.ipv4;
    if(nil != self.ipv6) dict[@"ipv6"] = self.ipv6;
    if(nil != self.dnsServers) dict[@"dnsServers"] = self.dnsServers;
    if(nil != self.timestamp) dict[@"timestamp"] = self.timestamp;

    return dict;
}

+(NSString*)interfaceTypeString:(NetworkInterfaceType)type
{
    switch(type)
    {
        case NetworkInterfaceTypeWiFi: return KEY_INTERFACE_TYPE_WIFI;
        case NetworkInterfaceTypeEthernet: return KEY_INTERFACE_TYPE_ETHERNET;
        case NetworkInterfaceTypeVPN: return KEY_INTERFACE_TYPE_VPN;
        default: return KEY_INTERFACE_TYPE_OTHER;
    }
}

-(NSString*)description
{
    return [NSString stringWithFormat:@"%@ interface=%@ type=%@ ssid=%@ bssid=%@ gateway=%@ ipv4=%@ dns=%@",
            NSStringFromClass(self.class), self.interface,
            [NetworkContext interfaceTypeString:(NetworkInterfaceType)self.interfaceType.integerValue],
            self.ssid, self.bssid, self.gateway, self.ipv4, self.dnsServers];
}

@end

@implementation NetworkContextManager
{
    //backing store for the readonly currentContext property
    // note: -currentContext is hand-implemented (it reads under @synchronized), which stops
    // auto-synthesis from emitting the ivar
    @public NetworkContext* _currentContext;

    //queue the poll timer (and -refresh) run on
    dispatch_queue_t queue;

    //poll timer
    dispatch_source_t timer;

    //user's change handler
    void (^changeHandler)(NetworkContext*, NetworkContext*);
}

+(instancetype)shared
{
    static NetworkContextManager* manager = nil;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{ manager = [[NetworkContextManager alloc] init]; });

    return manager;
}

-(id)init
{
    if(nil == (self = [super init])) return nil;

    queue = dispatch_queue_create("com.imonior.lulu-plus.network-context", DISPATCH_QUEUE_SERIAL);

    return self;
}

-(void)setChangeHandler:(void (^)(NetworkContext*, NetworkContext*))handler
{
    @synchronized(self) { changeHandler = [handler copy]; }
}

-(void)start
{
    @synchronized(self)
    {
        //already running?
        if(nil != timer) return;

        //sample right away, so profiles can be evaluated before the first tick
        _currentContext = [NetworkContext current];

        //dbg msg
        os_log_debug(logHandle, "network context monitoring started: %{public}@", _currentContext);

        timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
        dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, NETWORK_CONTEXT_POLL_INTERVAL),
                                  NETWORK_CONTEXT_POLL_INTERVAL, (1ull * NSEC_PER_SEC));

        __weak NetworkContextManager* weakself = self;
        dispatch_source_set_event_handler(timer, ^{ [weakself refresh]; });

        dispatch_resume(timer);
    }
}

-(void)stop
{
    @synchronized(self)
    {
        if(nil == timer) return;

        dispatch_source_cancel(timer);
        timer = nil;
    }

    //dbg msg
    os_log_debug(logHandle, "network context monitoring stopped");
}

//most recently sampled context
-(NetworkContext*)currentContext
{
    NetworkContext* context = nil;
    @synchronized(self) { context = _currentContext; }

    return context;
}

//the app can see what we can't (see +noteWiFiIdentity:) - take it in, then re-check right away,
// so moving between conditioned networks doesn't wait for the next poll
-(void)noteWiFiIdentityFromApp:(NSDictionary*)info
{
    [NetworkContext noteWiFiIdentity:info];

    dispatch_async(queue, ^{ [self refresh]; });

    return;
}

//re-sample, and report when it's a different network
-(void)refresh
{
    NetworkContext* previous = nil;
    void (^handler)(NetworkContext*, NetworkContext*) = nil;

    NetworkContext* context = [NetworkContext current];

    @synchronized(self)
    {
        previous = _currentContext;
        handler = changeHandler;

        if(YES == [context isEqualToContext:previous]) return;

        _currentContext = context;
    }

    //info msg
    os_log_info(logHandle, "network changed: %{public}@ -> %{public}@", previous, context);

    //tell whoever cares
    if(nil != handler) handler(previous, context);
}

@end
