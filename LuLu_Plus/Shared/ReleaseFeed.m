//
//  file: ReleaseFeed.m
//  project: lulu_plus (shared)
//  description: reads the release this project's update check points at
//
//  copyright (c) 2026 LuLu_Plus. All rights reserved.
//

#import "ReleaseFeed.h"
#import "consts.h"

@implementation ReleaseFeed

+(NSString*)versionFromTag:(NSString*)tag
{
    //nothing to read
    if(YES != [tag isKindOfClass:[NSString class]]) return nil;
    if(0 == tag.length) return nil;

    //a tag written with the usual 'v' in front of the number
    NSString* version = tag;

    if(YES == [version hasPrefix:@"v"])
    {
        version = [version substringFromIndex:1];
    }

    //only a number reaches the comparison the caller makes; a tag that says something else
    // would be read as a version that is somehow past the one installed
    NSUInteger leftover = [[version stringByTrimmingCharactersInSet:
                                [NSCharacterSet characterSetWithCharactersInString:@"0123456789."]] length];

    if(0 != leftover) return nil;

    return version;
}

+(NSDictionary*)releaseFromJSON:(id)json
{
    //a release is an object, and the version lives in its tag
    if(YES != [json isKindOfClass:[NSDictionary class]]) return nil;

    NSString* version = [self versionFromTag:json[@"tag_name"]];
    if(nil == version) return nil;

    return @{LATEST_VERSION: version};
}

+(BOOL)latest:(NSString*)latest isBeyond:(NSString*)current
{
    if(0 == latest.length) return NO;
    if(0 == current.length) return NO;

    return (NSOrderedAscending == [current compare:latest options:NSNumericSearch]);
}

@end
