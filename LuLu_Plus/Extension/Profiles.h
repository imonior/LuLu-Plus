//
//  Profiles.h
//
//  Created by Patrick Wardle on 06/21/25.
//  Copyright (c) 2025 Objective-See. All rights reserved.
//

@import OSLog;
@import Foundation;

#import "NetworkContext.h"

@interface Profiles : NSObject

/* PROPERTIES */

//profiles directory
@property(nonatomic, retain)NSString* directory;

/* METHODS */

-(NSMutableArray*)enumerate;
-(NSString*)resolve:(NSString*)name;
-(void)set:(NSString*)profilePath;
-(BOOL)add:(NSString*)name preferences:(NSDictionary*)preferences;
-(BOOL)delete:(NSString*)name;


// Auto profile switching
//
// a profile adopts the current network when its 'conditions' (see KEY_CONDITIONS) are satisfied;
// profiles without conditions are never adopted automatically

//profiles (names) whose conditions `context` satisfies
-(NSMutableArray*)profilesMatchingContext:(NetworkContext*)context;

//switch to the profile at `profilePath` (nil is the default profile)
// note: reloads rules + prefs and tells the app, so use this instead of -set: to actually switch
-(BOOL)activate:(NSString*)profilePath;

//evaluate every profile against the sampled network, and adopt a single match
// note: multiple matches is a conflict - nothing is adopted, and the app is told
-(BOOL)autoSwitchToMatchingProfile;

//does any profile adopt a network by Wi-Fi identity (ssid / bssid)?
// note: those are the two fields a system extension can't read without location access, so this is
//       what tells the app whether it needs to be granted it (and start sampling) at all
-(BOOL)usesWiFiIdentity;

@end
