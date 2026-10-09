//
//  ProfileConditionsViewController.h
//  project: LuLu_Plus (app)
//  description: the page of the add-profile wizard where the networks a profile applies to are
//               written down, instead of hand-edited into the profile's plist
//

#import <Cocoa/Cocoa.h>

@interface ProfileConditionsViewController : NSViewController

//the profile's stored condition sets, loaded into the editor
@property(nonatomic, copy)NSArray<NSDictionary*>* conditionSets;

//what the editor says now, in the form a profile stores
-(NSArray<NSDictionary*>*)editedConditionSets;

//the controls, so a test can drive the page the way a user does
@property(nonatomic, retain)NSPopUpButton* networksPopUp;
@property(nonatomic, retain)NSPopUpButton* typePopUp;
@property(nonatomic, retain)NSTextField* ssidField;
@property(nonatomic, retain)NSTextField* bssidField;
@property(nonatomic, retain)NSTextField* interfaceField;
@property(nonatomic, retain)NSTextField* gatewayField;
@property(nonatomic, retain)NSButton* addButton;
@property(nonatomic, retain)NSButton* removeButton;

@end
