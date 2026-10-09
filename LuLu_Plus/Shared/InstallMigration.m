//
//  file: InstallMigration.m
//  project: lulu_plus (shared)
//  description: picks up the rules and preferences a previous install kept in its own directory
//
//  copyright (c) 2026 LuLu_Plus. All rights reserved.
//

#import "InstallMigration.h"
#import "consts.h"

@implementation InstallMigration

+(NSArray<NSString*>*)migratableNames
{
    return @[RULES_FILE, RULES_FILE_V1, PREFS_FILE, PROFILE_DIRECTORY];
}

+(NSArray<NSString*>*)migrateFromDirectory:(NSString*)legacyDirectory
                               toDirectory:(NSString*)directory
                    otherInstallPresent:(BOOL)otherInstallPresent
                             fileManager:(NSFileManager*)fileManager
{
    //what was picked up
    NSMutableArray* migrated = [NSMutableArray array];

    //both ends have to be named
    if(nil == legacyDirectory || nil == directory) return migrated;

    //this build already has a store (even an empty one), so there is nothing to take over
    // note: this also covers the two ends naming the same directory
    if(YES == [fileManager fileExistsAtPath:directory]) return migrated;

    //no previous install
    if(YES != [fileManager fileExistsAtPath:legacyDirectory]) return migrated;

    //make room for what is about to be picked up
    if(YES != [fileManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL])
    {
        return migrated;
    }

    //only what this build reads
    for(NSString* name in [self migratableNames])
    {
        NSString* item = [legacyDirectory stringByAppendingPathComponent:name];

        //not there
        if(YES != [fileManager fileExistsAtPath:item]) continue;

        //the store this build reads was just made, so nothing is in the way
        NSString* target = [directory stringByAppendingPathComponent:name];

        BOOL pickedUp = NO;

        //a working install of the previous name still reads its own files: leave them be
        if(YES == otherInstallPresent)
        {
            pickedUp = [fileManager copyItemAtPath:item toPath:target error:NULL];
        }
        else
        {
            pickedUp = [fileManager moveItemAtPath:item toPath:target error:NULL];

            //a move can fail for a reason a copy can cross, i.e. the two directories sit on
            //        different volumes; take the copy and only then let go of the original
            if(YES != pickedUp)
            {
                pickedUp = [fileManager copyItemAtPath:item toPath:target error:NULL];
                if(YES == pickedUp)
                {
                    [fileManager removeItemAtPath:item error:NULL];
                }
            }
        }

        if(YES == pickedUp)
        {
            [migrated addObject:name];
        }
    }

    //the old directory goes only once it holds nothing
    // note: an install of the old firewall's first release put its own binary there, so a directory
    //       that still has entries is left exactly as it was found
    NSArray<NSString*>* remaining = [fileManager contentsOfDirectoryAtPath:legacyDirectory error:NULL];
    if(0 == [remaining count])
    {
        [fileManager removeItemAtPath:legacyDirectory error:NULL];
    }

    return migrated;
}

@end
