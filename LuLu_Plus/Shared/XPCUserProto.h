//
//  file: XPCUserProtocol
//  project: LuLu_Plus (shared)
//  description: protocol for talking to the user (header)
//
//  created by Patrick Wardle
//  copyright (c) 2018 Objective-See. All rights reserved.
//

@import Foundation;

@protocol XPCUserProtocol

//rules changed
-(void)rulesChanged;

//show an alert
-(void)alertShow:(NSDictionary*)alert reply:(void (^)(NSDictionary*))reply;

//more than one profile adopts the current network, so none was activated
-(void)profileConflictDetected:(NSArray*)profiles;

@end

