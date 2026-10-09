//
//  file: WiFiIdentity.h
//  project: lulu_plus (main app)
//  description: samples the Wi-Fi network this mac is attached to, for the extension
//
//  copyright (c) 2026 LuLu_Plus. All rights reserved.
//

@import Cocoa;
@import CoreLocation;

@interface WiFiIdentity : NSObject <CLLocationManagerDelegate>

/* METHODS */

+(instancetype)shared;

//re-check whether the extension wants Wi-Fi identity, and (re)arm sampling
// note: called at launch and whenever profiles or preferences change, because a profile that keys
//       on an SSID is the only reason to ask the user for location access
-(void)refresh;

//stop sampling
-(void)stop;

@end
