//
//  file: Update.m
//  project: lulu_plus (shared)
//  description: checks for new versions of LuLu_Plus
//
//  created by Patrick Wardle
//  copyright (c) 2017 Objective-See. All rights reserved.
//

#import "consts.h"
#import "Update.h"
#import "utilities.h"
#import "ReleaseFeed.h"
#import "AppDelegate.h"

/* GLOBALS */

//log handle
extern os_log_t logHandle;

@implementation Update

//check for an update
// will invoke app delegate method to update UI when check completes
-(void)checkForUpdate:(void (^)(NSUInteger result, NSString* latestVersion))completionHandler
{
    //get latest version in background
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        
        //result
        NSInteger result = Update_None;

        //the release this build checks
        NSDictionary* release = [self getLatestRelease];

        //latest version
        NSString* latestVersion = nil;

        if(nil != release)
        {
            latestVersion = release[LATEST_VERSION];

            //is it past the version installed?
            if(YES == [ReleaseFeed latest:latestVersion isBeyond:getAppVersion()])
            {
                //update available
                result = Update_Available;
            }
        }
        //error
        else
        {
            //err msg
            os_log_error(logHandle, "ERROR: failed to retrieve the latest release (for update check) from %{public}@", PRODUCT_VERSIONS_URL);

            result = Update_Error;
        }

        //invoke app delegate method
        // will update UI/show popup if necessary
        dispatch_async(dispatch_get_main_queue(),
        ^{
            completionHandler(result, latestVersion);
        });
    });
    
    return;
}

//read the release this build's update url points at
// return the info wanted, as ReleaseFeed reads it
-(NSDictionary*)getLatestRelease
{
    //what the feed answered
    id json = nil;

    @try
    {
        //get the release (as JSON) from the remote URL
        NSData* data = [[NSData alloc] initWithContentsOfURL:[NSURL URLWithString:PRODUCT_VERSIONS_URL]];
        if(nil == data)
        {
            //err msg
            os_log_error(logHandle, "ERROR: failed to download the latest release from %{public}@", PRODUCT_VERSIONS_URL);
            return nil;
        }

        //convert
        NSError* error = nil;
        json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
        if(nil != error)
        {
            //err msg
            os_log_error(logHandle, "ERROR: failed to read the latest release (error: %{public}@)", error);
            return nil;
        }
    }
    @catch(NSException* exception)
    {
        //err msg
        os_log_error(logHandle, "ERROR: failed to read the latest release (exception: %{public}@)", exception);
        return nil;
    }

    return [ReleaseFeed releaseFromJSON:json];
}

@end
