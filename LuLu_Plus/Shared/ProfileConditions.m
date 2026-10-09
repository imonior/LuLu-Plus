//
//  ProfileConditions.m
//  project: LuLu_Plus (app)
//  description: see ProfileConditions.h
//

#import "ProfileConditions.h"
#import "consts.h"

@implementation ProfileConditions

+(NSArray<NSString*>*)conditionKeys
{
    //the order the editor shows them in: what kind of network, then its names and addresses
    static NSArray* keys = nil;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        keys = @[KEY_CONDITION_INTERFACE_TYPE, KEY_CONDITION_SSID, KEY_CONDITION_BSSID,
                 KEY_CONDITION_INTERFACE, KEY_CONDITION_GATEWAY];
    });

    return keys;
}

+(BOOL)isConditionKey:(NSString*)key
{
    if(YES != [key isKindOfClass:[NSString class]]) return NO;

    return (YES == [[self conditionKeys] containsObject:key]);
}

//a cell the user left blank (or that only holds spaces) is a key the set shouldn't check
+(NSString*)valueOrNil:(id)value
{
    if(YES != [value isKindOfClass:[NSString class]]) return nil;

    NSString* trimmed = [(NSString*)value stringByTrimmingCharactersInSet:
                            NSCharacterSet.whitespaceAndNewlineCharacterSet];

    return (0 != trimmed.length) ? trimmed : nil;
}

+(NSArray<NSDictionary*>*)conditionSetsFromRows:(NSArray<NSDictionary*>*)rows
{
    NSMutableArray* sets = [NSMutableArray array];

    if(YES != [rows isKindOfClass:[NSArray class]]) return sets;

    for(id row in (NSArray*)rows)
    {
        if(YES != [row isKindOfClass:[NSDictionary class]]) continue;

        NSMutableDictionary* set = [NSMutableDictionary dictionary];

        for(NSString* key in [self conditionKeys])
        {
            NSString* value = [self valueOrNil:row[key]];
            if(nil == value) continue;

            set[key] = value;
        }

        //a set that checks nothing can never be satisfied, so it would quietly switch the profile
        // off; leave it out rather than write a condition the model refuses to match
        if(0 == set.count) continue;

        [sets addObject:[set copy]];
    }

    return sets;
}

+(NSArray<NSDictionary*>*)rowsFromConditionSets:(NSArray*)sets
{
    NSMutableArray* rows = [NSMutableArray array];

    if(YES != [sets isKindOfClass:[NSArray class]]) return rows;

    for(id set in (NSArray*)sets)
    {
        if(YES != [set isKindOfClass:[NSDictionary class]]) continue;

        NSMutableDictionary* row = [NSMutableDictionary dictionary];
        NSUInteger checked = 0;

        for(NSString* key in [self conditionKeys])
        {
            //anything the model can't read (a number, a blank) is shown as an empty cell, so it
            // isn't written back out as a condition the profile never matches
            NSString* value = [self valueOrNil:set[key]];

            row[key] = (nil != value) ? value : @"";
            if(nil != value) checked++;
        }

        if(0 == checked) continue;

        [rows addObject:[row copy]];
    }

    return rows;
}

@end
