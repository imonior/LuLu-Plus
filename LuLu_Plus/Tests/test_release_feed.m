//
//  file: test_release_feed.m
//  project: LuLu_Plus (tests)
//  description: reads the release payloads this project's update check points at and checks what
//               the update check is handed back - and what it is refused
//
//  note: this links the real source (Shared/ReleaseFeed.m)
//        see run_release_feed_tests.sh
//
//  note: the payloads below are written the way the GitHub releases API answers them. What it does
//        NOT cover: downloading one - that url is rate limited per ip address, so a test that
//        asked GitHub for a release would go red for reasons that have nothing to do with this
//        build
//

@import Foundation;

#import "consts.h"
#import "ReleaseFeed.h"

/* harness */

static NSUInteger testsRun = 0;
static NSUInteger testsFailed = 0;

static void check(const char* description, BOOL condition)
{
    testsRun++;

    if(YES != condition)
    {
        testsFailed++;
        printf("  FAIL  %s\n", description);
        return;
    }

    printf("  ok    %s\n", description);

    return;
}

//parse JSON the way the update check does
static id jsonOf(NSString* text)
{
    return [NSJSONSerialization JSONObjectWithData:[text dataUsingEncoding:NSUTF8StringEncoding]
                                           options:0
                                             error:NULL];
}

//a release, as the API hands it back, tagged 'tag'
static NSDictionary* releaseTagged(NSString* tag)
{
    return [ReleaseFeed releaseFromJSON:
                jsonOf([NSString stringWithFormat:@"{\"tag_name\": \"%@\"}", tag])];
}

//an answer that carries these fields, and no release
static NSDictionary* releaseFromFields(NSString* fields)
{
    return [ReleaseFeed releaseFromJSON:jsonOf([NSString stringWithFormat:@"{%@}", fields])];
}

//the version out of a release
static NSString* versionOf(NSDictionary* release)
{
    return release[LATEST_VERSION];
}

#pragma mark - cases

//a release as the GitHub API answers it
static void test_a_release(void)
{
    printf("\n== a release ==\n");

    id payload = jsonOf(
        @"{\"url\": \"https://api.github.com/repos/imonior/LuLu-Plus/releases/12345678\", "
        @"\"html_url\": \"https://github.com/imonior/LuLu-Plus/releases/tag/v4.5.3\", "
        @"\"id\": 12345678, "
        @"\"tag_name\": \"v4.5.3\", "
        @"\"target_commitish\": \"main\", "
        @"\"name\": \"LuLu_Plus 4.5.3\", "
        @"\"draft\": false, "
        @"\"prerelease\": false, "
        @"\"published_at\": \"2026-10-01T12:05:00Z\", "
        @"\"assets\": [{\"name\": \"LuLu_Plus-4.5.3.dmg\", \"size\": 3735928, \"download_count\": 12}], "
        @"\"body\": \"## What is new - inbound rules\"}");

    check("the payload is read as JSON", (nil != payload));

    NSDictionary* release = [ReleaseFeed releaseFromJSON:payload];

    check("the release is read", (nil != release));
    check("it carries the version its tag names", (YES == [@"4.5.3" isEqual:versionOf(release)]));
    check("nothing else is made up for the release", (1 == [release count]));
}

//how a tag becomes a version
static void test_the_tag(void)
{
    printf("\n== the tag ==\n");

    check("'v4.5.3' is 4.5.3", (YES == [@"4.5.3" isEqual:[ReleaseFeed versionFromTag:@"v4.5.3"]]));
    check("'4.5.3' is 4.5.3", (YES == [@"4.5.3" isEqual:[ReleaseFeed versionFromTag:@"4.5.3"]]));
    check("a tag of nothing is no version", (nil == [ReleaseFeed versionFromTag:@""]));
    check("a tag that is missing is no version", (nil == [ReleaseFeed versionFromTag:nil]));
    check("a tag that isn't text is no version", (nil == [ReleaseFeed versionFromTag:(id)@(5)]));
    check("'latest' is no version", (nil == [ReleaseFeed versionFromTag:@"latest"]));
    check("a tag with a name in front of the number is no version",
          (nil == [ReleaseFeed versionFromTag:@"LuLu_Plus-4.5.3"]));
    check("a release candidate tag is no version", (nil == [ReleaseFeed versionFromTag:@"v4.5.3-rc1"]));
    check("only one 'v' comes off the front", (nil == [ReleaseFeed versionFromTag:@"vv4.5.3"]));
}

//what isn't a release
static void test_what_is_not_a_release(void)
{
    printf("\n== what isn't a release ==\n");

    //as the API answers it when there is no latest release to hand back
    check("an error payload is no release",
          (nil == releaseFromFields(@"\"message\": \"Not Found\", \"status\": \"404\"")));

    check("a rate-limit payload is no release",
          (nil == releaseFromFields(@"\"message\": \"API rate limit exceeded for 203.0.113.142.\"")));

    check("a release without a tag is no release",
          (nil == releaseFromFields(@"\"name\": \"LuLu_Plus\"")));
    check("a tag that is null is no release",
          (nil == releaseFromFields(@"\"tag_name\": null")));
    check("a tag that isn't text is no release",
          (nil == releaseFromFields(@"\"tag_name\": 453")));
    check("a tag that names nothing is no release",
          (nil == releaseFromFields(@"\"tag_name\": \"\"")));
    check("a tag that isn't a version is no release",
          (nil == releaseFromFields(@"\"tag_name\": \"latest\"")));

    check("an array is no release", (nil == [ReleaseFeed releaseFromJSON:jsonOf(@"[\"v4.5.3\"]")]));
    check("a bare string is no release", (nil == [ReleaseFeed releaseFromJSON:jsonOf(@"\"v4.5.3\"")]));
    check("no JSON at all is no release", (nil == [ReleaseFeed releaseFromJSON:jsonOf(@"{tag")]));
    check("nothing at all is no release", (nil == [ReleaseFeed releaseFromJSON:nil]));
}

//whether a release is past what is installed
static void test_newer(void)
{
    printf("\n== is it past the version installed ==\n");

    check("4.5.3 is past 4.5.2", (YES == [ReleaseFeed latest:@"4.5.3" isBeyond:@"4.5.2"]));
    check("4.5.2 is not past 4.5.3", (NO == [ReleaseFeed latest:@"4.5.2" isBeyond:@"4.5.3"]));
    check("the same version is not past itself",
          (NO == [ReleaseFeed latest:@"4.5.3" isBeyond:@"4.5.3"]));
    check("5.0 is past 4.9.9", (YES == [ReleaseFeed latest:@"5.0" isBeyond:@"4.9.9"]));

    //the reason the comparison is a numeric one: read as text, "4.5.10" sorts before "4.5.2"
    check("4.5.10 is past 4.5.2", (YES == [ReleaseFeed latest:@"4.5.10" isBeyond:@"4.5.2"]));
    check("4.5.2 is not past 4.5.10", (NO == [ReleaseFeed latest:@"4.5.2" isBeyond:@"4.5.10"]));
    check("as plain text, 4.5.10 really would sort before 4.5.2",
          (NSOrderedAscending == [@"4.5.10" compare:@"4.5.2"]));

    check("no version is nothing to update to", (NO == [ReleaseFeed latest:nil isBeyond:@"4.5.2"]));
    check("an empty version is nothing to update to", (NO == [ReleaseFeed latest:@"" isBeyond:@"4.5.2"]));
    check("nothing installed is nothing to compare against",
          (NO == [ReleaseFeed latest:@"4.5.3" isBeyond:nil]));
}

//a release through to the comparison the update check makes
static void test_a_release_through_to_the_comparison(void)
{
    printf("\n== a release through to the comparison ==\n");

    NSDictionary* release = releaseTagged(@"v4.5.10");

    check("the release is read", (nil != release));
    check("and its version is past 4.5.2",
          (YES == [ReleaseFeed latest:versionOf(release) isBeyond:@"4.5.2"]));

    check("a release of the version installed is not an update",
          (NO == [ReleaseFeed latest:versionOf(releaseTagged(@"v4.5.2")) isBeyond:@"4.5.2"]));

    check("a release tagged with something that isn't a version is refused",
          (nil == releaseTagged(@"nightly")));
}

//the feed this project is updated from
static void test_the_feed(void)
{
    printf("\n== the feed ==\n");

    check("the check asks GitHub's API",
          (YES == [PRODUCT_VERSIONS_URL hasPrefix:@"https://api.github.com/repos/"]));
    check("the check asks about this project",
          (YES == [PRODUCT_VERSIONS_URL containsString:@"imonior/LuLu-Plus"]));
    check("the check asks for the latest release",
          (YES == [PRODUCT_VERSIONS_URL hasSuffix:@"/releases/latest"]));
    check("a new version is picked up from this project's releases",
          (YES == [PRODUCT_RELEASES_URL isEqualToString:@"https://github.com/imonior/LuLu-Plus/releases/latest"]));
    check("the project page is this project's",
          (YES == [PRODUCT_URL isEqualToString:@"https://github.com/imonior/LuLu-Plus"]));
    check("what the check downloads is not the page a user is sent to",
          (NO == [PRODUCT_VERSIONS_URL isEqualToString:PRODUCT_RELEASES_URL]));
}

#pragma mark - main

int main(int argc, char* argv[])
{
    @autoreleasepool {

        printf("== LuLu_Plus: release feed tests ==\n");

        test_a_release();
        test_the_tag();
        test_what_is_not_a_release();
        test_newer();
        test_a_release_through_to_the_comparison();
        test_the_feed();

        printf("\n%lu tests, %lu failure(s)\n", (unsigned long)testsRun, (unsigned long)testsFailed);

        if(0 != testsFailed) return 1;
    }

    return 0;
}
