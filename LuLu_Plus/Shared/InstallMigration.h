//
//  file: InstallMigration.h
//  project: lulu_plus (shared)
//  description: picks up the rules and preferences a previous install kept in its own directory (header)
//
//  copyright (c) 2026 LuLu_Plus. All rights reserved.
//

#ifndef InstallMigration_h
#define InstallMigration_h

@import Foundation;

@interface InstallMigration : NSObject

//the files this build reads, and so the only ones taken from an older install
// note: anything else that lives in the old directory is left exactly where it is
+(NSArray<NSString*>*)migratableNames;

//move an older install's store into the one this build reads
// ...returns the names it picked up, empty when there was nothing to migrate
// note: when 'otherInstallPresent' is set, the files are copied instead of moved, because a working
//       install of the previous name still reads them out of its own directory
+(NSArray<NSString*>*)migrateFromDirectory:(NSString*)legacyDirectory
                               toDirectory:(NSString*)directory
                      otherInstallPresent:(BOOL)otherInstallPresent
                              fileManager:(NSFileManager*)fileManager;
@end

#endif /* InstallMigration_h */
