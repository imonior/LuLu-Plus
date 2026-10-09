#!/bin/bash
#
# file: mutation_check.sh
# description: temporarily breaks the production sources the way they were broken before,
#              and shows the tests go red for each break
#
# usage: ./mutation_check.sh
#

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

RULE="$PROJECT_DIR/Shared/Rule.m"
NCTX="$PROJECT_DIR/Extension/NetworkContext.m"
ALERT="$PROJECT_DIR/App/AlertWindowController.m"
WIFI="$PROJECT_DIR/App/WiFiIdentity.m"
ADDRULE="$PROJECT_DIR/App/AddRuleWindowController.m"
PCONDS="$PROJECT_DIR/Shared/ProfileConditions.m"
PCONDSVC="$PROJECT_DIR/App/ProfileConditionsViewController.m"
CATALOG="$PROJECT_DIR/Shared/Localizable.xcstrings"
MIG="$PROJECT_DIR/Shared/InstallMigration.m"
FEED="$PROJECT_DIR/Shared/ReleaseFeed.m"
LANG="$PROJECT_DIR/Shared/Language.m"
PLANG="$PROJECT_DIR/App/PrefsWindowController+Language.m"
PM="$PROJECT_DIR/App/PrefsWindowController.m"
XIB="$PROJECT_DIR/App/Base.lproj/Preferences.xib"
MULCAT="$PROJECT_DIR/App/mul.lproj/Preferences.xcstrings"
SI="$PROJECT_DIR/Shared/SigningIdentity.m"
SIPLIST="$PROJECT_DIR/Extension/Info.plist"
LISTENER="$PROJECT_DIR/Extension/XPCListener.m"
CLIENT="$PROJECT_DIR/App/XPCDaemonClient.m"
CONSTS="$PROJECT_DIR/Shared/consts.h"
PBXPROJ="$PROJECT_DIR/LuLu_Plus.xcodeproj/project.pbxproj"
#the dmg step sits at the top of the repository, beside the project
DMG="$(dirname "$PROJECT_DIR")/DMG/createDMG.sh"

BACKUP="$(mktemp -d)"
cp "$RULE" "$BACKUP/Rule.m" || exit 1
cp "$NCTX" "$BACKUP/NetworkContext.m" || exit 1
cp "$ALERT" "$BACKUP/AlertWindowController.m" || exit 1
cp "$WIFI" "$BACKUP/WiFiIdentity.m" || exit 1
    cp "$ADDRULE" "$BACKUP/AddRuleWindowController.m" || exit 1
    cp "$PCONDS" "$BACKUP/ProfileConditions.m" || exit 1
    cp "$PCONDSVC" "$BACKUP/ProfileConditionsViewController.m" || exit 1
    cp "$CATALOG" "$BACKUP/Localizable.xcstrings" || exit 1
cp "$MIG" "$BACKUP/InstallMigration.m" || exit 1
cp "$FEED" "$BACKUP/ReleaseFeed.m" || exit 1
cp "$LANG" "$BACKUP/Language.m" || exit 1
cp "$PLANG" "$BACKUP/PrefsWindowController+Language.m" || exit 1
cp "$PM" "$BACKUP/PrefsWindowController.m" || exit 1
cp "$XIB" "$BACKUP/Preferences.xib" || exit 1
cp "$MULCAT" "$BACKUP/Preferences.xcstrings" || exit 1
cp "$SI" "$BACKUP/SigningIdentity.m" || exit 1
cp "$SIPLIST" "$BACKUP/Extension-Info.plist" || exit 1
cp "$LISTENER" "$BACKUP/XPCListener.m" || exit 1
cp "$CLIENT" "$BACKUP/XPCDaemonClient.m" || exit 1
cp "$CONSTS" "$BACKUP/consts.h" || exit 1
cp "$PBXPROJ" "$BACKUP/project.pbxproj" || exit 1
cp "$DMG" "$BACKUP/createDMG.sh" || exit 1

restore()
{
    cp "$BACKUP/Rule.m" "$RULE"
    cp "$BACKUP/NetworkContext.m" "$NCTX"
    cp "$BACKUP/AlertWindowController.m" "$ALERT"
    cp "$BACKUP/WiFiIdentity.m" "$WIFI"
    cp "$BACKUP/AddRuleWindowController.m" "$ADDRULE"
    cp "$BACKUP/ProfileConditions.m" "$PCONDS"
    cp "$BACKUP/ProfileConditionsViewController.m" "$PCONDSVC"
    cp "$BACKUP/Localizable.xcstrings" "$CATALOG"
    cp "$BACKUP/InstallMigration.m" "$MIG"
    cp "$BACKUP/ReleaseFeed.m" "$FEED"
    cp "$BACKUP/Language.m" "$LANG"
    cp "$BACKUP/PrefsWindowController+Language.m" "$PLANG"
    cp "$BACKUP/PrefsWindowController.m" "$PM"
    cp "$BACKUP/Preferences.xib" "$XIB"
    cp "$BACKUP/Preferences.xcstrings" "$MULCAT"
    cp "$BACKUP/SigningIdentity.m" "$SI"
    cp "$BACKUP/Extension-Info.plist" "$SIPLIST"
    cp "$BACKUP/XPCListener.m" "$LISTENER"
    cp "$BACKUP/XPCDaemonClient.m" "$CLIENT"
    cp "$BACKUP/consts.h" "$CONSTS"
    cp "$BACKUP/project.pbxproj" "$PBXPROJ"
    cp "$BACKUP/createDMG.sh" "$DMG"
}

trap restore EXIT

#apply a single, exact, unique replacement
mutate()
{
    python3 - "$1" "$2" "$3" <<'PY'
import sys
path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
src = open(path).read()
count = src.count(old)
if count != 1:
    print("   NOT UNIQUE (%d matches) - skipping this mutation" % count)
    sys.exit(3)
open(path, "w").write(src.replace(old, new))
PY
}

mutation()
{
    local title="$1" file="$2" old="$3" new="$4"

    printf '\n--- %s\n' "$title"

    mutate "$file" "$old" "$new"
    if [ $? -ne 0 ]; then return 1; fi

    RUNNER="${RUNNER:-$SCRIPT_DIR/run_condition_and_direction_tests.sh}"
    "$RUNNER" > "$BACKUP/run.log" 2>&1
    local exit=$?
    local failed
    failed=$(grep -c -e '^  FAIL' -e '\[FAIL\]' "$BACKUP/run.log")

    restore

    if [ $exit -eq 0 ]; then
        echo "   PROBLEM: tests still pass, so they don't cover this"
        return 1
    fi

    #the run went red; show which checks said so
    if [ "$failed" != "0" ]; then
        grep -e '^  FAIL' -e '\[FAIL\]' "$BACKUP/run.log" | sed -e 's/^  FAIL  /   catches: /' -e 's/^.*\[FAIL\] /   catches: /'
    else
        #no check got to report: the break takes the process down before any assertion runs,
        #which is a failure a CI run sees, just not a named check
        echo "   catches: nothing - the run aborts (exit=$exit) on this break"
    fi

    return 0
}

#which suite the next mutations are checked against (the alert ones differ)
RUNNER="$SCRIPT_DIR/run_condition_and_direction_tests.sh"

echo "Mutation check: does each break turn a check red?"
echo "================================================"

overall=0

mutation "an unset direction reads as 'outbound' again" \
    "$RULE" \
    '            self.direction = @(TrafficDirectionBoth);
        }' \
    '        }' || overall=1

mutation "a word in the direction field is coerced to 0" \
    "$RULE" \
    '            if((YES != [directionScanner scanInteger:&directionValue]) ||
               (YES != [directionScanner isAtEnd]))' \
    '            if(NO)' || overall=1

mutation "a profile with an empty condition set adopts every network" \
    "$NCTX" \
    '    if(0 == conditionSet.count) return NO;' \
    '    if(0 == conditionSet.count) return YES;' || overall=1

mutation "condition keys inside a set stop being AND'ed" \
    "$NCTX" \
    '        if(YES != matches) return NO;' \
    '        if(YES != matches) continue;' || overall=1

mutation "the bssid condition becomes case-sensitive" \
    "$NCTX" \
    '        BOOL ignoreCase = (0 == [key compare:KEY_CONDITION_BSSID options:NSCaseInsensitiveSearch]);' \
    '        BOOL ignoreCase = NO;' || overall=1

mutation "a condition we cannot observe is treated as satisfied" \
    "$NCTX" \
    '        if(0 == observed.length)' \
    '        if(NO)' || overall=1

#how a rule reads in the rules list (same suite, since the wording is the model's)
mutation "an inbound rule reads as outgoing in the list" \
    "$RULE" \
    '    return (TrafficDirectionInbound == self.direction.intValue) ?' \
    '    return (NO) ?' || overall=1

mutation "a rule that goes either way is still annotated" \
    "$RULE" \
    '    if((nil == self.direction) || (TrafficDirectionBoth == self.direction.intValue)) return nil;' \
    '    if(NO) return nil;' || overall=1

mutation "a rule older than directions reads as outgoing" \
    "$RULE" \
    '    if((nil == self.direction) || (TrafficDirectionBoth == self.direction.intValue)) return nil;' \
    '    if((NO) || (TrafficDirectionBoth == self.direction.intValue)) return nil;' || overall=1



#the alert window: what an inbound prompt says, and what the answer hands back
RUNNER="$SCRIPT_DIR/run_alert_window_tests.sh"

mutation "an inbound alert is worded as if this mac reached out" \
    "$ALERT" \
    '                                (TrafficDirectionInbound == [self.alert[KEY_DIRECTION] integerValue]) ?' \
    '                                (NO) ?' || overall=1

mutation "the user's answer no longer carries the direction back" \
    "$ALERT" \
    '    alertResponse = [self.alert mutableCopy];' \
    '    alertResponse = [self.alert mutableCopy];
    [alertResponse removeObjectForKey:KEY_DIRECTION];' || overall=1

#and the Wi-Fi identity the app reports on the extension's behalf
RUNNER="$SCRIPT_DIR/run_wifi_identity_tests.sh"

mutation "the app names the interface under a key the extension doesn't read" \
    "$WIFI" \
    '    info[KEY_NETWORK_INTERFACE] = interface;' \
    '    info[@"iface"] = interface;' || overall=1

mutation "the app keeps reporting even though the extension never asked for it" \
    "$WIFI" \
    '        if(YES != needed)
        {
            [self stop];
            return;
        }' \
    '        if(NO)
        {
            [self stop];
            return;
        }' || overall=1

mutation "'not determined' counts as location access being granted" \
    "$WIFI" \
    '    if(kCLAuthorizationStatusAuthorizedAlways == status) return YES;' \
    '    if((kCLAuthorizationStatusAuthorizedAlways == status) ||
       (kCLAuthorizationStatusNotDetermined == status)) return YES;' || overall=1

#back to the suite that holds the assertions about what the extension adopts
RUNNER="$SCRIPT_DIR/run_condition_and_direction_tests.sh"

mutation "identity sampled for one interface is applied to another" \
    "$NCTX" \
    "    if(YES != [interface isEqualToString:context.interface]) return;" \
    '    if(NO) return;' || overall=1

mutation "the app's report overwrites what the extension read itself" \
    "$NCTX" \
    '    if((0 == context.ssid.length) && (0 != ssid.length)) context.ssid = ssid;' \
    '    if(0 != ssid.length) context.ssid = ssid;' || overall=1

mutation "the identity expires before the app's next sample" \
    "$NCTX" \
    '#define WIFI_IDENTITY_MAX_AGE 60.0' \
    '#define WIFI_IDENTITY_MAX_AGE 10.0' || overall=1

mutation "a non-string ssid is stringified into the identity" \
    "$NCTX" \
    '    if(YES != [ssid isKindOfClass:[NSString class]]) ssid = nil;' \
    '    if(NO) ssid = ssid;' || overall=1

mutation "a report that doesn't say which interface it is for is accepted" \
    "$NCTX" \
    '    if(YES != [interface isKindOfClass:[NSString class]] || 0 == interface.length)' \
    '    if(NO)' || overall=1

RUNNER="$SCRIPT_DIR/run_add_rule_tests.sh"

mutation "the direction the user picked never reaches the rule" \
    "$ADDRULE" \
    '                  KEY_ACTION:action,
                  KEY_DIRECTION:direction};' \
    '                  KEY_ACTION:action};' || overall=1

mutation "the picker's first choice is tagged with the wrong direction" \
    "$ADDRULE" \
    '    [self.directionPicker itemAtIndex:0].tag = TrafficDirectionOutbound;' \
    '    [self.directionPicker itemAtIndex:0].tag = TrafficDirectionInbound;' || overall=1

mutation "editing a rule doesn't show which way it goes" \
    "$ADDRULE" \
    '        //show which way the rule goes
        [self.directionPicker selectItemWithTag:self.rule.direction.integerValue];' \
    '        //show which way the rule goes' || overall=1

mutation "a new rule defaults to outbound instead of both ways" \
    "$ADDRULE" \
    '    [self.directionPicker selectItemWithTag:TrafficDirectionBoth];' \
    '    [self.directionPicker selectItemWithTag:TrafficDirectionOutbound];' || overall=1

mutation "the picker is dropped onto the buttons in its row" \
    "$ADDRULE" \
    '    CGFloat bandBottom = NSMaxY(self.addButton.frame);' \
    '    CGFloat bandBottom = 0.0;' || overall=1

mutation "the picker is never sized, so it collapses to nothing" \
    "$ADDRULE" \
    '    [self.directionPicker sizeToFit];
    [directionLabel sizeToFit];' \
    '' || overall=1

mutation "the Chinese word for an incoming rule falls back to English" \
    "$CATALOG" \
    '"value" : "（传入）"' \
    '"value" : "(incoming)"' || overall=1

mutation "the picker stops tracking the fields when the window widens" \
    "$ADDRULE" \
    '    self.directionPicker.autoresizingMask = (NSViewMinXMargin | NSViewMaxYMargin);' \
    '    self.directionPicker.autoresizingMask = (NSViewMaxXMargin | NSViewMinYMargin);' || overall=1

#and the page the networks a profile applies to are written down on
RUNNER="$SCRIPT_DIR/run_profile_conditions_tests.sh"

mutation "a cell of spaces is stored as a condition that can never match" \
    "$PCONDS" \
    '    return (0 != trimmed.length) ? trimmed : nil;' \
    '    return (0 != trimmed.length) ? trimmed : value;' || overall=1

mutation "spaces around a value are stored along with it" \
    "$PCONDS" \
    '    NSString* trimmed = [(NSString*)value stringByTrimmingCharactersInSet:
                            NSCharacterSet.whitespaceAndNewlineCharacterSet];' \
    '    NSString* trimmed = (NSString*)value;' || overall=1

mutation "a value that isn't text is copied into the condition" \
    "$PCONDS" \
    '            NSString* value = [self valueOrNil:row[key]];' \
    '            NSString* value = row[key];' || overall=1

mutation "a network that checks nothing is stored as a condition that can never match" \
    "$PCONDS" \
    '        if(0 == set.count) continue;' \
    '        if(NO) continue;' || overall=1

mutation "a loaded row leaves out the keys this network doesn't check" \
    "$PCONDS" \
    '            row[key] = (nil != value) ? value : @"";' \
    '            if(nil != value) row[key] = value;' || overall=1

mutation "a stored set that checks nothing comes back as something to edit" \
    "$PCONDS" \
    '        if(0 == checked) continue;' \
    '        if(NO) continue;' || overall=1

mutation "the type popup is built but never put on the page" \
    "$PCONDSVC" \
    '    [self.view addSubview:self.typePopUp];' \
    '' || overall=1

mutation "'Any' is stored as a type the network can never have" \
    "$PCONDSVC" \
    '    network[KEY_CONDITION_INTERFACE_TYPE] = ((nil == type) || (0 == [type compare:kTypeAny])) ? @"" : type;' \
    '    network[KEY_CONDITION_INTERFACE_TYPE] = ((nil == type)) ? @"" : type;' || overall=1

mutation "the type stored is the word shown, so a translated build stores a different profile" \
    "$PCONDSVC" \
    '        item.representedObject = type;' \
    '        item.representedObject = item.title;' || overall=1

mutation "a network whose line reads the same as another's never reaches the list" \
    "$PCONDSVC" \
    '        [menu addItemWithTitle:[self summaryForNetwork:network] action:NULL keyEquivalent:@""];' \
    '        [self.networksPopUp addItemWithTitle:[self summaryForNetwork:network]];' || overall=1

mutation "the network the fields belong to is read off the list instead of remembered" \
    "$PCONDSVC" \
    '    NSUInteger index = shownNetwork;
    if(index >= networks.count) return;

    NSMutableDictionary* network = networks[index];' \
    '    NSUInteger index = [self pickedNetwork];
    if(index >= networks.count) return;

    NSMutableDictionary* network = networks[index];' || overall=1

mutation "switching networks shows the new one before writing down the one being left" \
    "$PCONDSVC" \
    '    [self commitFields];

    [self showNetwork:[self pickedNetwork]];' \
    '    [self showNetwork:[self pickedNetwork]];

    [self commitFields];' || overall=1

mutation "adding a network loses whatever was being typed into the one before it" \
    "$PCONDSVC" \
    '    [self commitFields];

    [networks addObject:[self blankNetwork]];' \
    '    [networks addObject:[self blankNetwork]];' || overall=1

mutation "the - button removes whichever network comes first" \
    "$PCONDSVC" \
    '    [networks removeObjectAtIndex:index];' \
    '    [networks removeObjectAtIndex:0];' || overall=1

mutation "switching networks keeps showing the first one" \
    "$PCONDSVC" \
    '    NSDictionary* network = networks[index];' \
    '    NSDictionary* network = networks[0];' || overall=1

mutation "a page that was never shown invents conditions instead of handing back its own" \
    "$PCONDSVC" \
    '    if(YES != self.isViewLoaded) return _conditionSets;' \
    '    if(NO) return _conditionSets;' || overall=1

mutation "conditions handed to a page that is already shown are ignored" \
    "$PCONDSVC" \
    '    if(YES == self.isViewLoaded) [self applyConditionSets:_conditionSets];' \
    '    if(NO) [self applyConditionSets:_conditionSets];' || overall=1

mutation "a type the build doesn't know is shown as Wi-Fi" \
    "$PCONDSVC" \
    '    [self.typePopUp selectItemAtIndex:(typeIndex < 0) ? 0 : typeIndex];' \
    '    [self.typePopUp selectItemAtIndex:(typeIndex < 0) ? 1 : typeIndex];' || overall=1

mutation "the Chinese word for Ethernet falls back to English" \
    "$CATALOG" \
    '"value" : "以太网"' \
    '"value" : "Ethernet"' || overall=1

mutation "the hint under the interface field falls back to English" \
    "$CATALOG" \
    '        "zh-Hans" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "例如：en0"' \
    '        "zh-Hans" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "for example: en0"' || overall=1

#and the takeover of a previous install's data directory
RUNNER="$SCRIPT_DIR/run_install_migration_tests.sh"

mutation "an install that already has a store has it taken over from under it" \
    "$MIG" \
    '    //this build already has a store (even an empty one), so there is nothing to take over
    // note: this also covers the two ends naming the same directory
    if(YES == [fileManager fileExistsAtPath:directory]) return migrated;' \
    '' || overall=1

mutation "a store is made for an install that never had a previous one" \
    "$MIG" \
    '    //no previous install
    if(YES != [fileManager fileExistsAtPath:legacyDirectory]) return migrated;' \
    '' || overall=1

mutation "the profiles a user set up are left behind" \
    "$MIG" \
    '    return @[RULES_FILE, RULES_FILE_V1, PREFS_FILE, PROFILE_DIRECTORY];' \
    '    return @[RULES_FILE, RULES_FILE_V1, PREFS_FILE];' || overall=1

mutation "files are copied away even though nothing still reads them" \
    "$MIG" \
    '        if(YES == otherInstallPresent)' \
    '        if(NO)' || overall=1

mutation "the store is left in the old directory after being taken" \
    "$MIG" \
    '            pickedUp = [fileManager moveItemAtPath:item toPath:target error:NULL];' \
    '            pickedUp = [fileManager copyItemAtPath:item toPath:target error:NULL];' || overall=1

mutation "the old directory is deleted while it still holds something" \
    "$MIG" \
    '    if(0 == [remaining count])' \
    '    if((YES) || (0 == [remaining count]))' || overall=1


#and the release the update check reads
RUNNER="$SCRIPT_DIR/run_release_feed_tests.sh"

mutation "a tag written the usual way is no version" \
    "$FEED" \
    '    if(YES == [version hasPrefix:@"v"])
    {
        version = [version substringFromIndex:1];
    }' \
    '' || overall=1

mutation "a tag that isn't a version is read as one" \
    "$FEED" \
    '    NSUInteger leftover = [[version stringByTrimmingCharactersInSet:
                                [NSCharacterSet characterSetWithCharactersInString:@"0123456789."]] length];

    if(0 != leftover) return nil;' \
    '' || overall=1

mutation "any JSON is read as a release" \
    "$FEED" \
    '    if(YES != [json isKindOfClass:[NSDictionary class]]) return nil;' \
    '    if(YES != [json isKindOfClass:[NSString class]]) return nil;' || overall=1

mutation "a release without a usable tag still reports a version" \
    "$FEED" \
    '    if(nil == version) return nil;' \
    '    if(nil != version) return nil;' || overall=1

mutation "versions are read as text, so 4.5.10 sorts before 4.5.2" \
    "$FEED" \
    '    return (NSOrderedAscending == [current compare:latest options:NSNumericSearch]);' \
    '    return (NSOrderedAscending == [current compare:latest]);' || overall=1


#and the language the UI runs in
RUNNER="$SCRIPT_DIR/run_language_tests.sh"

mutation "the UI starts in German instead of English" \
    "$LANG" \
    '    return @"en";' \
    '    return @"de";' || overall=1

mutation "a shipped language is dropped from the list" \
    "$LANG" \
    '@"ko", @"pl", @"pt-BR", @"tr", @"uk", @"ur", @"zh-Hans", @"zh-Hant"];' \
    '@"ko", @"pl", @"pt-BR", @"tr", @"uk", @"ur", @"zh-Hans"];' || overall=1

mutation "any code at all counts as a language we ship" \
    "$LANG" \
    '    return (nil != code) && (YES == [[self shippedLanguages] containsObject:code]);' \
    '    return (nil != code);' || overall=1

mutation "a language is offered under another language's name" \
    "$LANG" \
    '        @"de" : @"Deutsch",' \
    '        @"de" : @"German",' || overall=1

mutation "a pick of a language we don't ship is stored anyway" \
    "$LANG" \
    '    //only the languages we ship
    if(YES != [self isShippedLanguage:code])
    {
        return;
    }' \
    '    //only the languages we ship
    if(NO)
    {
        return;
    }' || overall=1

mutation "the restart is offered exactly when nothing would change" \
    "$LANG" \
    '    return ![[self resolvedLanguage:defaults] isEqualToString:[self runningLanguage:defaults]];' \
    '    return [[self resolvedLanguage:defaults] isEqualToString:[self runningLanguage:defaults]];' || overall=1

mutation "a language chosen outside the app is forgotten again" \
    "$LANG" \
    '    if(nil == [defaults stringForKey:PREF_LANGUAGE])
    {
        NSString* adopted = [self resolvedLanguage:defaults];
        if(NO == [adopted isEqualToString:[self defaultLanguage]])
        {
            [defaults setObject:adopted forKey:PREF_LANGUAGE];
        }
    }' \
    '' || overall=1

mutation "a Mac whose own language is something else decides what the UI runs in" \
    "$LANG" \
    '    [defaults setObject:@[[self resolvedLanguage:defaults]] forKey:PREF_APPLE_LANGUAGES];' \
    '' || overall=1

mutation "the picker offers two languages instead of all of them" \
    "$PLANG" \
    '    for(NSString* code in [Language shippedLanguages])' \
    '    for(NSString* code in @[@"en", @"de"])' || overall=1

mutation "the restart button is always on" \
    "$PLANG" \
    '    self.restartButton.enabled = [Language restartRequired:defaults];' \
    '    self.restartButton.enabled = YES;' || overall=1

mutation "a choice no longer says which language it is" \
    "$PLANG" \
    '        picker.lastItem.representedObject = code;' \
    '' || overall=1

mutation "the restart button is pinned to the English width" \
    "$PLANG" \
    '    CGFloat restartWidth = MAX(150.0, NSWidth(restart.frame));' \
    '    CGFloat restartWidth = 150.0;' || overall=1

mutation "the button's word is written into the code instead of the catalog" \
    "$PLANG" \
    'NSLocalizedString(@"Restart Now", @"Restart Now")' \
    '@"Restart Now"' || overall=1

mutation "the language tab shows the wrong pane" \
    "$PM" \
    '            view = self.languageView;' \
    '            view = self.updateView;' || overall=1

mutation "the pane is shown without reflecting the stored pick" \
    "$PM" \
    '            [self refreshLanguageView];' \
    '' || overall=1

mutation "the language tab is tagged with a case the handler doesn't know" \
    "$XIB" \
    'tag="5" image="PrefsLanguage"' \
    'tag="9" image="PrefsLanguage"' || overall=1

mutation "the toolbar's label sits under a key the nib doesn't ask for" \
    "$MULCAT" \
    '"Lng-Tb-g01.label"' \
    '"Lng-Tb-g01.LABEL"' || overall=1

mutation "the Chinese word for the restart button falls back to English" \
    "$CATALOG" \
    '"value" : "立即重新启动"' \
    '"value" : "Restart Now"' || overall=1

mutation "the Chinese note stops saying which app restarts" \
    "$CATALOG" \
    '"value" : "LuLu_Plus 重新启动后会应用新语言。"' \
    '"value" : "重新启动后会应用新语言。"' || overall=1


#and the identity a build reads off its own signature
RUNNER="$SCRIPT_DIR/run_signing_identity_tests.sh"

mutation "the requirement stops pinning the team that signed the extension" \
    "$SI" \
    ' and certificate leaf [subject.OU] = \"%@\"' \
    '' || overall=1

mutation "the team is read off the certificate's name instead of its team field" \
    "$SI" \
    '[subject.OU]' \
    '[subject.CN]' || overall=1

mutation "a build with no team still demands an Apple-issued certificate" \
    "$SI" \
    '    if(0 == team.length)' \
    '    if(NO)' || overall=1

mutation "the version floor slips a version" \
    "$SI" \
    'static NSString* const MinimumClientVersion = @"2.0.0";' \
    'static NSString* const MinimumClientVersion = @"2.0";' || overall=1

mutation "the version floor is dropped from what the system is handed" \
    "$SI" \
    '    return [[self clientRequirementForTeam:team] stringByAppendingFormat:@" and info [CFBundleShortVersionString] >= \"%@\"", MinimumClientVersion];' \
    '    return [self clientRequirementForTeam:team];' || overall=1

mutation "the team prefix loses its dot" \
    "$SI" \
    '    return (0 != team.length) ? [team stringByAppendingString:@"."] : @"";' \
    '    return (0 != team.length) ? team : @"";' || overall=1

mutation "a build with no team stands for a lonely dot" \
    "$SI" \
    '    return (0 != team.length) ? [team stringByAppendingString:@"."] : @"";' \
    '    return (0 != team.length) ? [team stringByAppendingString:@"."] : @".";' || overall=1

mutation "the plist's variable is left standing for launchd to read" \
    "$SI" \
    '    return [name stringByReplacingOccurrencesOfString:TeamIdentifierPrefix
                                           withString:[self teamIdentifierPrefixForTeam:team]];' \
    '    return name;' || overall=1

mutation "the mach service falls back to a name nobody registered" \
    "$SI" \
    '        name = [NSString stringWithFormat:@"%@%@", [self teamIdentifierPrefixForTeam:[self teamIdentifier]], DAEMON_MACH_SERVICE];' \
    '        name = @"com.imonior.lulu-plus.x";' || overall=1

mutation "the app reads the extension's name off its own bundle" \
    "$SI" \
    '        return [NSBundle bundleWithURL:[NSURL fileURLWithPath:[directory stringByAppendingPathComponent:entry]]];' \
    '        return appBundle;' || overall=1

mutation "any embedded plug-in counts as the system extension" \
    "$SI" \
    '        if(YES != [[entry pathExtension] isEqualToString:@"systemextension"]) continue;' \
    '' || overall=1

mutation "the extension listens on a name written into the code" \
    "$LISTENER" \
    '        serviceName = [SigningIdentity extensionMachServiceName];' \
    '        serviceName = DAEMON_MACH_SERVICE;' || overall=1

mutation "the system is handed a requirement naming another build" \
    "$LISTENER" \
    '            requirement = [SigningIdentity listenerRequirement];' \
    '            requirement = @"anchor apple generic and identifier \"com.imonior.lulu-plus.app\" and certificate leaf [subject.CN] = \"Developer ID Application: Objective-See, LLC (VBG97UB4TA)\" and info [CFBundleShortVersionString] >= \"2.0.0\"";' || overall=1

mutation "the client check stops asking this build" \
    "$LISTENER" \
    '    requirement = [SigningIdentity clientRequirement];' \
    '    requirement = @"anchor apple generic and identifier \"com.imonior.lulu-plus.app\" and certificate leaf [subject.CN] = \"Developer ID Application: Objective-See, LLC (VBG97UB4TA)\"";' || overall=1

mutation "the app looks for a name written into the code" \
    "$CLIENT" \
    '    daemon = [[NSXPCConnection alloc] initWithMachServiceName:[SigningIdentity embeddedExtensionMachServiceName] options:0];' \
    '    daemon = [[NSXPCConnection alloc] initWithMachServiceName:DAEMON_MACH_SERVICE options:0];' || overall=1

mutation "an identity from another build is written down again" \
    "$CONSTS" \
    '#define BUNDLE_ID "com.imonior.lulu-plus"' \
    '#define BUNDLE_ID "com.imonior.lulu-plus"
#define SIGNING_AUTH @"Developer ID Application: Objective-See, LLC (VBG97UB4TA)"' || overall=1

mutation "the mach name carries a team again" \
    "$CONSTS" \
    '#define DAEMON_MACH_SERVICE @"com.imonior.lulu-plus"' \
    '#define DAEMON_MACH_SERVICE @"VBG97UB4TA.com.imonior.lulu-plus"' || overall=1

mutation "the extension registers under a name the app won't look up" \
    "$SIPLIST" \
    '<string>$(TeamIdentifierPrefix)com.imonior.lulu-plus</string>' \
    '<string>$(TeamIdentifierPrefix)com.imonior.lulu-plus.extension</string>' || overall=1

mutation "a team id from another build is pasted into the project again" \
    "$PBXPROJ" \
    '		CDB2CC2A24D61A5000D0EECE /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {' \
    '		CDB2CC2A24D61A5000D0EECE /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				DEVELOPMENT_TEAM = VBG97UB4TA;' || overall=1

mutation "the dmg step writes an identity into the file again" \
    "$DMG" \
    'codesign --force --sign "$SIGN_IDENTITY" "LuLu_Plus_$VERSION.dmg"' \
    'codesign --force --sign "Developer ID Application: Objective-See, LLC (VBG97UB4TA)" "LuLu_Plus_$VERSION.dmg"' || overall=1


echo
restore

if ! cmp -s "$RULE" "$BACKUP/Rule.m" || ! cmp -s "$NCTX" "$BACKUP/NetworkContext.m" ||
   ! cmp -s "$ALERT" "$BACKUP/AlertWindowController.m" ||
   ! cmp -s "$WIFI" "$BACKUP/WiFiIdentity.m" ||
   ! cmp -s "$ADDRULE" "$BACKUP/AddRuleWindowController.m" ||
   ! cmp -s "$PCONDS" "$BACKUP/ProfileConditions.m" ||
   ! cmp -s "$PCONDSVC" "$BACKUP/ProfileConditionsViewController.m" ||
   ! cmp -s "$CATALOG" "$BACKUP/Localizable.xcstrings" ||
   ! cmp -s "$MIG" "$BACKUP/InstallMigration.m" ||
   ! cmp -s "$FEED" "$BACKUP/ReleaseFeed.m" ||
   ! cmp -s "$LANG" "$BACKUP/Language.m" ||
   ! cmp -s "$PLANG" "$BACKUP/PrefsWindowController+Language.m" ||
   ! cmp -s "$PM" "$BACKUP/PrefsWindowController.m" ||
   ! cmp -s "$XIB" "$BACKUP/Preferences.xib" ||
   ! cmp -s "$MULCAT" "$BACKUP/Preferences.xcstrings" ||
   ! cmp -s "$SI" "$BACKUP/SigningIdentity.m" ||
   ! cmp -s "$SIPLIST" "$BACKUP/Extension-Info.plist" ||
   ! cmp -s "$LISTENER" "$BACKUP/XPCListener.m" ||
   ! cmp -s "$CLIENT" "$BACKUP/XPCDaemonClient.m" ||
   ! cmp -s "$CONSTS" "$BACKUP/consts.h" ||
   ! cmp -s "$PBXPROJ" "$BACKUP/project.pbxproj" ||
   ! cmp -s "$DMG" "$BACKUP/createDMG.sh"; then
    echo "ERROR: sources did not restore byte-for-byte"
    exit 1
fi

echo "   sources restored byte-for-byte"

if [ $overall -ne 0 ]; then
    echo "RESULT: some mutations were not caught"
    exit 1
fi

echo "RESULT: every mutation was caught"
