//
//  file: WiFiIdentity.m
//  project: lulu_plus (main app)
//  description: samples the Wi-Fi network this mac is attached to, for the extension
//
//  copyright (c) 2026 LuLu_Plus. All rights reserved.
//

@import Cocoa;
@import CoreLocation;
@import CoreWLAN;
@import OSLog;

#import "consts.h"
#import "WiFiIdentity.h"
#import "XPCDaemonClient.h"

/* GLOBALS */

//log handle
extern os_log_t logHandle;

//xpc for daemon comms
extern XPCDaemonClient* xpcDaemonClient;

/* DEFINES */

//how often we re-sample
// note: the extension only trusts an identity it heard about recently, so this has to be
//       comfortably shorter than that window
#define WIFI_SAMPLE_INTERVAL 15.0

@interface WiFiIdentity ()

//location (com) - the thing the SSID/BSSID read is gated on
@property(nonatomic, strong)CLLocationManager* locationCom;

//serial queue for the sampling itself (and its XPC round-trip)
@property(nonatomic, strong)dispatch_queue_t sampleQueue;

//re-sample timer
@property(nonatomic, strong)dispatch_source_t timer;

//are we already sampling?
@property(nonatomic, assign)BOOL sampling;

@end

@implementation WiFiIdentity

/* CLASS METHODS */

+(instancetype)shared
{
    static WiFiIdentity* instance = nil;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        instance = [[WiFiIdentity alloc] init];
    });

    return instance;
}

/* OBJECT METHODS */

-(instancetype)init
{
    self = [super init];
    if(nil == self) return nil;

    //queue for the reads + the (synchronous) XPC send
    self.sampleQueue = dispatch_queue_create("com.imonior.lulu-plus.wifi-identity", DISPATCH_QUEUE_SERIAL);

    return self;
}

//does the extension have a profile that keys on Wi-Fi identity, and if so can we read it?
-(void)refresh
{
    //ask the extension first
    // ...there is no business asking the user for location access when no profile wants it
    dispatch_async(self.sampleQueue, ^{

        //connected?
        if(nil == xpcDaemonClient) return;

        //does anything need this?
        BOOL needed = [xpcDaemonClient needsWiFiIdentity];

        //dbg msg
        os_log_debug(logHandle, "extension needs wi-fi identity: %{public}@", needed ? @"yes" : @"no");

        //not needed - stop, and let the extension drop what it was holding
        if(YES != needed)
        {
            [self stop];
            return;
        }

        //the location manager (and its prompt) wants the main thread
        dispatch_async(dispatch_get_main_queue(), ^{
            [self start];
        });
    });

    return;
}

//stop sampling
-(void)stop
{
    dispatch_async(dispatch_get_main_queue(), ^{

        //nothing running? then there's nothing to withdraw either
        if(YES != self.sampling) return;

        //stop the timer
        if(nil != self.timer)
        {
            dispatch_source_cancel(self.timer);
            self.timer = nil;
        }

        //mark
        self.sampling = NO;

        //withdraw, so a profile can't keep matching a network we stopped looking at
        dispatch_async(self.sampleQueue, ^{
            [xpcDaemonClient updateNetworkInfo:nil];
        });

        //info msg
        os_log_info(logHandle, "wi-fi identity sampling stopped");
    });

    return;
}

/* HELPER METHODS */

//make sure we have location access, and arm the sampling if we do
// note: runs on the main thread
-(void)start
{
    //alloc the location com (once)
    if(nil == self.locationCom)
    {
        self.locationCom = [[CLLocationManager alloc] init];
        self.locationCom.delegate = self;
    }

    //current status
    CLAuthorizationStatus status = [self currentStatus];

    //never asked? ask now
    if(kCLAuthorizationStatusNotDetermined == status)
    {
        //info msg
        os_log_info(logHandle, "wi-fi identity needs location access - asking for it");

        [self.locationCom requestWhenInUseAuthorization];

        //the delegate call-back (re)starts us once the user answers
        return;
    }

    //not granted? there is nothing to sample - macOS hides the SSID/BSSID without this
    if(YES != [self isGranted:status])
    {
        //err msg
        os_log_error(logHandle, "ERROR: location access not granted (%{public}d), so ssid/bssid conditions cannot match", status);
        return;
    }

    //already ticking?
    if(YES == self.sampling) return;

    //mark
    self.sampling = YES;

    //timer
    self.timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());

    //fire immediately, then every interval (with a second of leeway)
    dispatch_source_set_timer(self.timer, dispatch_walltime(NULL, 0),
                              (uint64_t)(WIFI_SAMPLE_INTERVAL * NSEC_PER_SEC), NSEC_PER_SEC);

    //weak self, so a timer can't keep the object alive
    __weak WiFiIdentity* weakSelf = self;

    dispatch_source_set_event_handler(self.timer, ^{

        __strong WiFiIdentity* strongSelf = weakSelf;
        if(nil == strongSelf) return;

        //the read and the XPC send both belong off the main thread
        dispatch_async(strongSelf.sampleQueue, ^{
            [strongSelf sampleAndReport];
        });
    });

    //start
    dispatch_resume(self.timer);

    //info msg
    os_log_info(logHandle, "wi-fi identity sampling started (every %{public}.0f seconds)", WIFI_SAMPLE_INTERVAL);

    return;
}

//read the network this mac is attached to and hand it over
// note: runs on the sample queue
-(void)sampleAndReport
{
    //wifi interface (nil name == the one in use)
    CWInterface* wifi = [[CWWiFiClient sharedWiFiClient] interfaceWithName:nil];

    //no wi-fi hardware attached (or it's off)? the extension should not be holding ours
    NSString* interface = wifi.interfaceName;
    if(0 == interface.length)
    {
        [xpcDaemonClient updateNetworkInfo:nil];
        return;
    }

    //sample
    // note: these are the two the extension provably cannot read for itself
    NSString* ssid = wifi.ssid;
    NSString* bssid = wifi.bssid;

    //build the payload
    NSMutableDictionary* info = [NSMutableDictionary dictionary];
    info[KEY_NETWORK_INTERFACE] = interface;

    //an open/hidden network really does report an empty SSID - keep it out of the payload
    if(0 != ssid.length) info[KEY_NETWORK_SSID] = ssid;
    if(0 != bssid.length) info[KEY_NETWORK_BSSID] = bssid;

    //hand over
    // note: a 'no' reply just means the extension isn't listening right now; the next tick retries
    BOOL accepted = [xpcDaemonClient updateNetworkInfo:info];

    //dbg msg
    os_log_debug(logHandle, "reported wi-fi identity: %{public}@ ssid=%{public}@ bssid=%{public}@ (accepted: %{public}@)",
                 interface, ssid, bssid, accepted ? @"yes" : @"no");

    return;
}

//the authorization status
-(CLAuthorizationStatus)currentStatus
{
    //the instance property is macOS 11+; the class method is what 10.15 has
    if(@available(macOS 11.0, *))
    {
        return self.locationCom.authorizationStatus;
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return [CLLocationManager authorizationStatus];
#pragma clang diagnostic pop
}

//is this status one where macOS will hand us the SSID?
-(BOOL)isGranted:(CLAuthorizationStatus)status
{
    //there is no 'when in use' state on macOS - a granted app is always authorized
    if(kCLAuthorizationStatusAuthorizedAlways == status) return YES;

    return NO;
}

/*CLLocationManagerDelegate */

//macOS 11+
-(void)locationManagerDidChangeAuthorization:(CLLocationManager*)manager
{
    //ignore if not ours
    if(manager != self.locationCom) return;

    //info msg
    os_log_info(logHandle, "location authorization changed: %{public}d", [self currentStatus]);

    //re-run the check (arms the sampling once the user says yes)
    [self start];

    return;
}

//macOS 10.15
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-implementations"
-(void)locationManager:(CLLocationManager*)manager didChangeAuthorizationStatus:(CLAuthorizationStatus)status
{
    //ignore if not ours
    if(manager != self.locationCom) return;

    //info msg
    os_log_info(logHandle, "location authorization changed: %{public}d", status);

    //re-run the check
    [self start];

    return;
}
#pragma clang diagnostic pop

@end
