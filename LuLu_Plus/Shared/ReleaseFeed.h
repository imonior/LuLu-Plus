//
//  file: ReleaseFeed.h
//  project: lulu_plus (shared)
//  description: reads the release this project's update check points at (header)
//
//  copyright (c) 2026 LuLu_Plus. All rights reserved.
//

#ifndef ReleaseFeed_h
#define ReleaseFeed_h

@import Foundation;

@interface ReleaseFeed : NSObject

//the version carried by a release tag, nil when the tag doesn't name one
// note: a tag is free text, so only a leading 'v' is taken off; a tag that isn't a version is
//       left as it came, and the comparison the caller makes simply won't move
+(NSString*)versionFromTag:(NSString*)tag;

//what this build wants to know from a release: the version it carries, under LATEST_VERSION
// ...nil when the JSON handed over isn't a release
+(NSDictionary*)releaseFromJSON:(id)json;

//is 'latest' a version past 'current'
// note: versions are compared as numbers, so 4.5.10 is past 4.5.2 where a plain string
//       comparison would put it before 4.5.2
+(BOOL)latest:(NSString*)latest isBeyond:(NSString*)current;

@end

#endif /* ReleaseFeed_h */
