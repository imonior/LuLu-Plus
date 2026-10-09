//
//  file: test_install_migration.m
//  project: LuLu_Plus (tests)
//  description: runs the start-up takeover of a previous install's directory against throwaway
//                trees on disk, and checks what moves, what is copied, and what is left alone
//
//  note: this links the real source (Shared/InstallMigration.m)
//        see run_install_migration_tests.sh
//
//  note: every case builds its own pair of directories under the system temp folder, so no case
//        can be affected by the one before it. What it does NOT cover: /Library itself, and the
//        decision that a previous-named app is still installed (the caller reads
//        /Applications/LuLu.app; here that flag is simply passed in)
//

@import Foundation;

#import "consts.h"
#import "InstallMigration.h"

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

static NSFileManager* fileManager = nil;

//a fresh root for one case, so nothing carries over
static NSString* scratchDirectory(void)
{
    NSString* root = [NSTemporaryDirectory()
        stringByAppendingPathComponent:[NSString stringWithFormat:@"install-migration-%u-%@",
                                        arc4random(), NSUUID.UUID.UUIDString]];

    [fileManager createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:NULL];

    return root;
}

static void removeDirectory(NSString* path)
{
    [fileManager removeItemAtPath:path error:NULL];
}

//write a file, with contents, anywhere under 'root'
static void writeFile(NSString* root, NSString* relativePath, NSString* contents)
{
    NSString* path = [root stringByAppendingPathComponent:relativePath];

    [fileManager createDirectoryAtPath:path.stringByDeletingLastPathComponent
           withIntermediateDirectories:YES
                            attributes:nil
                                 error:NULL];

    [contents writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
}

static BOOL exists(NSString* root, NSString* relativePath)
{
    return (YES == [fileManager fileExistsAtPath:[root stringByAppendingPathComponent:relativePath]]);
}

static NSString* contentsOfFile(NSString* root, NSString* relativePath)
{
    return [NSString stringWithContentsOfFile:[root stringByAppendingPathComponent:relativePath]
                                     encoding:NSUTF8StringEncoding
                                        error:NULL];
}

static NSUInteger countInDirectory(NSString* path)
{
    NSArray<NSString*>* items = [fileManager contentsOfDirectoryAtPath:path error:NULL];

    return items.count;
}

//did 'name' come back in the list of what was picked up
static BOOL reports(NSArray<NSString*>* migrated, NSString* name)
{
    return (YES == [migrated containsObject:name]);
}

#pragma mark - cases

//the names taken are exactly the files and folders this build reads
static void test_the_names_under_migration(void)
{
    printf("\n== the names under migration ==\n");

    NSArray<NSString*>* names = [InstallMigration migratableNames];

    check("the current rules file is migrated", (YES == [names containsObject:RULES_FILE]));
    check("the v1 rules file is migrated", (YES == [names containsObject:RULES_FILE_V1]));
    check("the preferences file is migrated", (YES == [names containsObject:PREFS_FILE]));
    check("the profiles folder is migrated", (YES == [names containsObject:PROFILE_DIRECTORY]));
    check("nothing else is migrated", (4 == [names count]));
}

//no previous install: nothing happens, and no directory is made
static void test_no_previous_install(void)
{
    printf("\n== no previous install ==\n");

    NSString* root = scratchDirectory();

    NSString* legacy = [root stringByAppendingPathComponent:@"old"];
    NSString* current = [root stringByAppendingPathComponent:@"new"];

    NSArray<NSString*>* migrated =
        [InstallMigration migrateFromDirectory:legacy toDirectory:current otherInstallPresent:NO
                                   fileManager:fileManager];

    check("nothing is reported", (0 == [migrated count]));
    check("the destination is not created", (NO == exists(root, @"new")));
    check("the legacy directory is not created", (NO == exists(root, @"old")));

    removeDirectory(root);
}

//this build already has a store: the old one is left exactly where it is
static void test_destination_already_present(void)
{
    printf("\n== this build already has a store ==\n");

    NSString* root = scratchDirectory();

    NSString* legacy = [root stringByAppendingPathComponent:@"old"];
    NSString* current = [root stringByAppendingPathComponent:@"new"];

    writeFile(legacy, RULES_FILE, @"legacy rules");
    writeFile(current, RULES_FILE, @"current rules");

    NSArray<NSString*>* migrated =
        [InstallMigration migrateFromDirectory:legacy toDirectory:current otherInstallPresent:NO
                                   fileManager:fileManager];

    check("nothing is reported", (0 == [migrated count]));
    check("the old rules file stays", (YES == exists(root, @"old/rules.plist")));
    check("the current rules file is untouched",
          (YES == [@"current rules" isEqual:contentsOfFile(root, @"new/rules.plist")]));

    removeDirectory(root);
}

//a store this build has already made, but has not put anything in yet
static void test_destination_present_but_empty(void)
{
    printf("\n== this build's store exists and is still empty ==\n");

    NSString* root = scratchDirectory();

    NSString* legacy = [root stringByAppendingPathComponent:@"old"];
    NSString* current = [root stringByAppendingPathComponent:@"new"];

    writeFile(legacy, RULES_FILE, @"legacy rules");

    [fileManager createDirectoryAtPath:current
           withIntermediateDirectories:YES
                            attributes:nil
                                 error:NULL];

    NSArray<NSString*>* migrated =
        [InstallMigration migrateFromDirectory:legacy toDirectory:current otherInstallPresent:NO
                                   fileManager:fileManager];

    check("nothing is reported", (0 == [migrated count]));
    check("nothing is put into the empty store", (NO == exists(root, @"new/rules.plist")));
    check("the old rules file stays where it is", (YES == exists(root, @"old/rules.plist")));

    removeDirectory(root);
}

//an empty destination still counts as a store: running twice must not re-take
static void test_second_run_is_a_no_op(void)
{
    printf("\n== a second run ==\n");

    NSString* root = scratchDirectory();

    NSString* legacy = [root stringByAppendingPathComponent:@"old"];
    NSString* current = [root stringByAppendingPathComponent:@"new"];

    writeFile(legacy, RULES_FILE, @"rules");

    NSArray<NSString*>* first =
        [InstallMigration migrateFromDirectory:legacy toDirectory:current otherInstallPresent:NO
                                   fileManager:fileManager];

    NSArray<NSString*>* second =
        [InstallMigration migrateFromDirectory:legacy toDirectory:current otherInstallPresent:NO
                                   fileManager:fileManager];

    check("the first run picks the store up", (1 == [first count]));
    check("the second run picks nothing up", (0 == [second count]));

    removeDirectory(root);
}

//both ends named the same directory
static void test_same_directory_both_ends(void)
{
    printf("\n== the same directory on both ends ==\n");

    NSString* root = scratchDirectory();

    NSString* directory = [root stringByAppendingPathComponent:@"same"];

    writeFile(directory, RULES_FILE, @"rules");

    NSArray<NSString*>* migrated =
        [InstallMigration migrateFromDirectory:directory toDirectory:directory otherInstallPresent:NO
                                   fileManager:fileManager];

    check("nothing is reported", (0 == [migrated count]));
    check("the rules file stays", (YES == exists(root, @"same/rules.plist")));

    removeDirectory(root);
}

//a missing name on either end
static void test_missing_arguments(void)
{
    printf("\n== missing arguments ==\n");

    NSString* root = scratchDirectory();

    check("a nil legacy directory is refused",
          (0 == [[InstallMigration migrateFromDirectory:nil toDirectory:root otherInstallPresent:NO
                                            fileManager:fileManager] count]));

    check("a nil destination is refused",
          (0 == [[InstallMigration migrateFromDirectory:root toDirectory:nil otherInstallPresent:NO
                                            fileManager:fileManager] count]));

    removeDirectory(root);
}

//the full takeover
static void test_takeover_moves_the_store(void)
{
    printf("\n== the full takeover ==\n");

    NSString* root = scratchDirectory();

    NSString* legacy = [root stringByAppendingPathComponent:@"old"];
    NSString* current = [root stringByAppendingPathComponent:@"new"];

    writeFile(legacy, RULES_FILE, @"rules");
    writeFile(legacy, RULES_FILE_V1, @"rules v1");
    writeFile(legacy, PREFS_FILE, @"preferences");
    writeFile(legacy, [PROFILE_DIRECTORY stringByAppendingPathComponent:@"Home.plist"], @"home profile");
    writeFile(legacy, @"leftovers.txt", @"not this build's");

    NSArray<NSString*>* migrated =
        [InstallMigration migrateFromDirectory:legacy toDirectory:current otherInstallPresent:NO
                                   fileManager:fileManager];

    check("all four are reported", (4 == [migrated count]));
    check("the rules file is reported", (YES == reports(migrated, RULES_FILE)));
    check("the v1 rules file is reported", (YES == reports(migrated, RULES_FILE_V1)));
    check("the preferences file is reported", (YES == reports(migrated, PREFS_FILE)));
    check("the profiles folder is reported", (YES == reports(migrated, PROFILE_DIRECTORY)));

    check("the destination holds the rules file", (YES == exists(root, @"new/rules.plist")));
    check("the rules file kept its contents",
          (YES == [@"rules" isEqual:contentsOfFile(root, @"new/rules.plist")]));
    check("the preferences file kept its contents",
          (YES == [@"preferences" isEqual:contentsOfFile(root, @"new/preferences.plist")]));

    check("the profiles folder came across whole", (YES == exists(root, @"new/Profiles/Home.plist")));
    check("the profile kept its contents",
          (YES == [@"home profile" isEqual:contentsOfFile(root, @"new/Profiles/Home.plist")]));

    check("the rules file left the old directory", (NO == exists(root, @"old/rules.plist")));
    check("the preferences file left the old directory", (NO == exists(root, @"old/preferences.plist")));
    check("the profiles folder left the old directory", (NO == exists(root, @"old/Profiles")));

    check("a file this build does not read stays in place", (YES == exists(root, @"old/leftovers.txt")));
    check("the old directory survives while it still holds something",
          (NO == exists(root, @"new/leftovers.txt")) && (1 == countInDirectory(legacy)));

    removeDirectory(root);
}

//an old install that holds nothing else goes away
static void test_empty_legacy_directory_is_removed(void)
{
    printf("\n== the old directory once it is empty ==\n");

    NSString* root = scratchDirectory();

    NSString* legacy = [root stringByAppendingPathComponent:@"old"];
    NSString* current = [root stringByAppendingPathComponent:@"new"];

    writeFile(legacy, RULES_FILE, @"rules");

    NSArray<NSString*>* migrated =
        [InstallMigration migrateFromDirectory:legacy toDirectory:current otherInstallPresent:NO
                                   fileManager:fileManager];

    check("the store is picked up", (1 == [migrated count]));
    check("the old directory is deleted", (NO == exists(root, @"old")));

    removeDirectory(root);
}

//an old install that only holds directories it made, and nothing else
static void test_legacy_directory_with_nothing_in_it(void)
{
    printf("\n== the old directory holding nothing at all ==\n");

    NSString* root = scratchDirectory();

    NSString* legacy = [root stringByAppendingPathComponent:@"old"];
    NSString* current = [root stringByAppendingPathComponent:@"new"];

    [fileManager createDirectoryAtPath:legacy withIntermediateDirectories:YES attributes:nil error:NULL];

    NSArray<NSString*>* migrated =
        [InstallMigration migrateFromDirectory:legacy toDirectory:current otherInstallPresent:NO
                                   fileManager:fileManager];

    check("nothing is reported", (0 == [migrated count]));
    check("the old directory is deleted", (NO == exists(root, @"old")));
    check("the destination is there", (YES == exists(root, @"new")));

    removeDirectory(root);
}

//a working install of the previous name still reads its own files
static void test_other_install_copies(void)
{
    printf("\n== the previous name is still installed ==\n");

    NSString* root = scratchDirectory();

    NSString* legacy = [root stringByAppendingPathComponent:@"old"];
    NSString* current = [root stringByAppendingPathComponent:@"new"];

    writeFile(legacy, RULES_FILE, @"rules");
    writeFile(legacy, PREFS_FILE, @"preferences");

    NSArray<NSString*>* migrated =
        [InstallMigration migrateFromDirectory:legacy toDirectory:current otherInstallPresent:YES
                                   fileManager:fileManager];

    check("both are reported", (2 == [migrated count]));

    check("the destination has the rules file", (YES == exists(root, @"new/rules.plist")));
    check("the destination has the preferences file", (YES == exists(root, @"new/preferences.plist")));

    check("the old directory keeps its rules file", (YES == exists(root, @"old/rules.plist")));
    check("the old directory keeps its preferences file", (YES == exists(root, @"old/preferences.plist")));

    check("the copies kept their contents",
          (YES == [@"rules" isEqual:contentsOfFile(root, @"new/rules.plist")]));

    check("the old directory survives - it is still in use", (YES == exists(root, @"old")));

    removeDirectory(root);
}

//the directory this build reads is named for this build
static void test_the_directories_involved(void)
{
    printf("\n== the directories this build names ==\n");

    check("this build's store is the application-support one",
          (YES == [INSTALL_DIRECTORY hasPrefix:@"/Library/Application Support/"]));
    check("this build's store is named for this project",
          (YES == [INSTALL_DIRECTORY hasSuffix:@"lulu_plus"]));
    check("the previous store is named for the old project",
          (YES == [LEGACY_INSTALL_DIRECTORY isEqualToString:@"/Library/Objective-See/LuLu"]));
    check("the two are different directories",
          (NO == [INSTALL_DIRECTORY isEqualToString:LEGACY_INSTALL_DIRECTORY]));
}

#pragma mark - main

int main(int argc, char* argv[])
{
    @autoreleasepool {

        fileManager = NSFileManager.defaultManager;

        printf("== LuLu_Plus: install migration tests ==\n");

        test_the_names_under_migration();
        test_no_previous_install();
        test_destination_already_present();
        test_destination_present_but_empty();
        test_second_run_is_a_no_op();
        test_same_directory_both_ends();
        test_missing_arguments();
        test_takeover_moves_the_store();
        test_empty_legacy_directory_is_removed();
        test_legacy_directory_with_nothing_in_it();
        test_other_install_copies();
        test_the_directories_involved();

        printf("\n%lu tests, %lu failure(s)\n", (unsigned long)testsRun, (unsigned long)testsFailed);

        if(0 != testsFailed) return 1;
    }

    return 0;
}
