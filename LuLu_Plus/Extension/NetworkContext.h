//
//  file: NetworkContext.h
//  project: LuLu_Plus
//  description: the network an interface is attached to (Wi-Fi identity, gateway, addresses, DNS)
//               and the monitor that reports when that changes
//
//  copyright (c) 2026 LuLu_Plus. All rights reserved.
//

@import Foundation;
@import OSLog;
@import CoreWLAN;
@import SystemConfiguration;

//interface types
// note: values are persisted in profile conditions, so don't renumber or rename the strings
typedef NS_ENUM(NSInteger, NetworkInterfaceType) {
    NetworkInterfaceTypeOther = 0,
    NetworkInterfaceTypeWiFi,
    NetworkInterfaceTypeEthernet,
    NetworkInterfaceTypeVPN,
};

@interface NetworkContext : NSObject

/* PROPERTIES */

//interface name (e.g. "en0")
@property(nonatomic, retain)NSString* interface;

//interface type
@property(nonatomic, retain)NSNumber* interfaceType;

//Wi-Fi network name
// note: nil unless location services are authorized (macOS 13+) or the app has reported it;
//       also nil when not on Wi-Fi
@property(nonatomic, retain)NSString* ssid;

//Wi-Fi access point address
@property(nonatomic, retain)NSString* bssid;

//default gateway (IPv4)
// note: the gateway's link-layer address is deliberately not modelled: a route-socket RTM_GET
//       returns the gateway but no lladdr, so a condition on it could never be satisfied
@property(nonatomic, retain)NSString* gateway;

//IPv4 addresses of the interface
@property(nonatomic, retain)NSArray* ipv4;

//IPv6 addresses of the interface
@property(nonatomic, retain)NSArray* ipv6;

//configured DNS servers
@property(nonatomic, retain)NSArray* dnsServers;

//when the context was sampled
@property(nonatomic, retain)NSDate* timestamp;

/* METHODS */

//sample the network the primary interface is attached to
+(instancetype)current;

//hand in the Wi-Fi identity (interface/ssid/bssid) sampled by the app
// note: a system extension can't be granted Location Services (there is no UI to ask with), so on
//       macOS 13+ CoreWLAN answers nil here - the app, which can be authorized, reports what it sees
//       and -current adopts it for the same interface while it stays fresh. pass nil to withdraw it
+(void)noteWiFiIdentity:(NSDictionary*)info;

//how long app-supplied Wi-Fi identity is trusted for
+(NSTimeInterval)wifiIdentityMaxAge;

//fields that can differ between two networks
// note: nil-tolerant on both sides, so nil == nil is equal
-(BOOL)isEqualToContext:(NetworkContext*)other;

//does this network satisfy a profile's conditions?
// note: conditions are an array of dictionaries: it's a match when ANY dictionary matches,
//       and a dictionary matches only when EVERY one of its keys does. a profile with no
//       conditions is never a match - being unconditional isn't the same as being network-driven
-(BOOL)satisfiesConditions:(NSArray*)conditions;

//as a property list
-(NSDictionary*)toDictionary;

//interface type as its condition string ("Wi-Fi", "Ethernet", ...)
+(NSString*)interfaceTypeString:(NetworkInterfaceType)type;

@end

@interface NetworkContextManager : NSObject

/* METHODS */

+(instancetype)shared;

//called on a private queue whenever the sampled context changes
// note: the handler must not block; it runs on the monitor's serial queue
-(void)setChangeHandler:(void (^)(NetworkContext* previous, NetworkContext* current))handler;

//start/stop sampling
// note: safe to call more than once; starting is a no-op while already running
-(void)start;
-(void)stop;

//take in Wi-Fi identity reported by the app, and re-evaluate now rather than on the next tick
-(void)noteWiFiIdentityFromApp:(NSDictionary*)info;

//most recently sampled context (nil before -start)
@property(nonatomic, retain, readonly)NetworkContext* currentContext;

@end
