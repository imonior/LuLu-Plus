//
//  ProfileConditions.h
//  project: LuLu_Plus (app)
//  description: turns the rows of the profile's network-conditions editor into the condition sets
//               a profile stores, and back
//
//  The stored form is an array of condition sets: a profile adopts the network it is on when any
//  one set is satisfied, and a set is satisfied when every key it names matches. So one editor row
//  is one set, and a field left blank is a key the set doesn't check.
//

#import <Foundation/Foundation.h>

@interface ProfileConditions : NSObject

//the condition keys the editor offers, in the order it shows them
+(NSArray<NSString*>*)conditionKeys;

//is this a key the profile conditions understand?
+(BOOL)isConditionKey:(NSString*)key;

//editor rows -> condition sets: trims, drops blanks, and drops anything the model can't read
+(NSArray<NSDictionary*>*)conditionSetsFromRows:(NSArray<NSDictionary*>*)rows;

//condition sets -> editor rows: every key present, so the editor has something to show
+(NSArray<NSDictionary*>*)rowsFromConditionSets:(NSArray*)sets;

@end
