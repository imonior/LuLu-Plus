# LuLu_Plus tests

Eleven standalone suites. Ten compile real production sources (or the real nib) rather than copies
of them, so a regression in `Shared/`, `App/` or `Extension/` turns the suite red; the eleventh is
upstream's self-contained passive-mode suite and links its own copies of the logic.

```bash
./run_condition_and_direction_tests.sh   # profile conditions, change detection, rule direction
./run_alert_window_tests.sh              # the alert window an inbound vs. outbound flow produces
./run_wifi_identity_tests.sh             # the app-side ssid/bssid sampler
./run_add_rule_tests.sh                  # the add/edit-rule window, and the rule it writes
./run_profile_conditions_tests.sh        # the wizard page where a profile's networks are named
./run_about_window_tests.sh              # About window layout, in every translated language
./run_language_tests.sh                  # the language picker, in every language the app ships
./run_install_migration_tests.sh         # taking over a previous install's data directory
./run_release_feed_tests.sh              # the release the update check reads
./run_signing_identity_tests.sh          # the identity a build reads off its own signature
./run_passive_mode_tests.sh              # passive-mode FQDN rules (self-contained)
./mutation_check.sh                      # breaks the sources on purpose, expects the suites to go red
```

Each one builds into a throwaway directory under `$TMPDIR` and removes it on success; the build
log is left behind when something fails.

## Conditions, change detection and rule direction

Links `Shared/Rule.m`, `Shared/utilities.m` and `Extension/NetworkContext.m` into a test binary
and checks:

- the profile condition model: condition sets are OR'd, keys inside a set are AND'd
- profiles without conditions, and empty condition sets, never adopt a network
- anything that can't be observed (unknown key, no location authorization, so no SSID)
  fails closed instead of matching
- `bssid` ignores case, `ssid` doesn't
- network change detection: re-ordered DNS and a new sample time aren't changes, a missing
  field on both sides is not a change either
- the Wi-Fi identity the app reports (see below) is what the extension adopts: only for the
  interface in use, only into the fields CoreWLAN left empty, and only while it stays fresh
- a rule with no `direction` is `both` - not the silent `outbound` it used to read as
- `direction` survives the `rules.plist` archive round-trip, and a non-numeric value is
  rejected rather than coerced to 0
- the word the rules list puts after a one-way rule (`Rule.directionNote`) says the opposite
  thing for inbound than for outbound, and says nothing at all for a rule that goes either way
  (including every rule written before directions existed)

The suite also samples the live network and prints what the machine actually exposes:

```
        interface   = en0
        type        = Wi-Fi
        ssid        = (nil)          <- nil unless location services are authorized
        gateway     = 10.20.20.20
```

## The alert window

`NEFilterDataProvider` hands the app a dictionary, the user answers, and the answer becomes a
rule, so the wording and the payload are the interface between the two processes. This suite
compiles `App/Base.lproj/AlertWindow.xib` and the real string catalog, loads them through the
real `AlertWindowController`, and feeds it an outbound and an inbound flow. For `en`, `zh-Hans`
and `zh-Hant` it checks the inbound prompt says a peer is connecting *in* (not that this mac
reached out), names the peer and the port being listened on, and that the user's answer comes
back carrying the inbound direction - otherwise the rule it creates would filter the wrong way.

What it doesn't cover: `Alerts.m -create:`, which builds that dictionary from a live
`NEFilterSocketFlow`. A socket flow can't be constructed in a test, so the suite hand-builds the
payload the way the extension does and checks both ends of it.

## Wi-Fi identity (ssid/bssid conditions)

macOS 13+ only answers `CWWiFiClient`'s ssid/bssid for a process authorized for Location
Services, and a system extension has no UI to ask for that. So the app samples and reports over
XPC. `run_wifi_identity_tests.sh` links `App/WiFiIdentity.m` with the real intake it reports
into (`Extension/NetworkContext.m`) and drives it against a stand-in for the extension, checking
the payload names the interface with the key the extension reads, leaves unreadable fields out
rather than reporting them empty, withdraws when there is no Wi-Fi interface, doesn't touch
CoreLocation at all until a profile actually keys on the network, and treats only
`kCLAuthorizationStatusAuthorizedAlways` as granted (macOS has no 'when in use' state).

What it doesn't cover: the location prompt itself - driving it would pop a system dialog mid-test.
The sampler therefore stops at "only arms once granted", and the freshness window is checked as an
invariant (it must outlive more than one sampling interval) rather than by waiting a minute out.

## The add/edit-rule window

The alert window only answers a connection that is already happening; this window is where a rule
gets written. `run_add_rule_tests.sh` compiles `App/Base.lproj/AddRule.xib` and the real string
catalog, loads them through the real `AddRuleWindowController`, and checks the direction picker the
fork adds: its three choices are the three directions a rule can store, each one tagged with the
value the rule keeps (so nothing has to be re-mapped on the way out), a new rule starts at `both` -
which is what every rule written before the picker existed meant - pressing 'add' hands the chosen
direction over in the rule information, and editing an inbound rule shows it as inbound and keeps it
that way when the user touches nothing else.

For `en`, `zh-Hans` and `zh-Hant` it also measures the picker: it has to sit in the one free band in
that row, inside the window, clear of every other control, right-aligned with the address and port
fields, and stay lined up with them when the window is dragged wider. For the two Chinese languages
it additionally requires the picker's words to come back *translated* - a catalog entry that goes
missing falls back to English, and every `NSLocalizedString` comparison above would accept that
silently.

What it doesn't cover: the rest of the window's validation (path, address and port parsing), which
is upstream's, and whether the window looks right - these are frame measurements, not pixels.

## The profile's network conditions

A profile can say which networks it applies to, but until this page existed those conditions could
only be written by hand into the profile's plist. `run_profile_conditions_tests.sh` links the real
converter (`Shared/ProfileConditions.m`), the real page
(`App/ProfileConditionsViewController.m`) and the real vocabulary
(`Extension/NetworkContext.m`) and checks:

- conversion: one editor row is one condition set, a blank cell is a key the set doesn't check,
  padding spaces and a trailing newline are trimmed, a key the model doesn't understand and a value
  that isn't text are dropped, and a row that ends up checking nothing is dropped rather than
  written as a condition the profile can never satisfy
- the round trip: stored sets load into rows carrying every key, and saving what was loaded changes
  nothing - including a stored set with a hand-edited key, which comes back as just the condition
  the model can read
- vocabulary: every interface type the page offers is one `+[NetworkContext interfaceTypeString:]`
  can report and every one it can report is offered, so the page can't write a condition no network
  will ever match
- filling it in: what is typed lands in the conditions, 'Any' writes no type condition, two fields
  of one network are both written (they AND), the + and - buttons work on the network being looked
  at, and editing one network doesn't change whichever one was selected before it
- switching mid-typing: moving the list to another network writes down the one being left before it
  shows the one being entered, so nothing typed is lost to a click, and what the list counts as the
  network on show is remembered by the page rather than read back off the control
- the list itself: one entry per network, even when two of them read the same - every blank network
  reads 'New network', and building the rows by title made AppKit drop the second one, so pressing
  + on a fresh page added nothing a user could see
- the page itself: each of its eight controls is actually on it (one of them was being built and
  never added, which every other check tolerated and a user could not see), nothing overlaps,
  everything is inside the page, every field has a label beside it that fits the room it is given,
  and the two paragraphs fit their band
- the wizard's habit of unchecking every `NSButton` on a page it swaps in: this page's pop-ups *are*
  `NSButton` subclasses, so the suite runs that sweep and requires the chosen type, the typed
  network and the stored conditions to survive it

For `en`, `zh-Hans` and `zh-Hant` the page has to show its words translated *and* keep storing the
English names the extension compares; those are two separate checks, because a build that translated
the stored value too would look correct on screen while matching nothing.

What it doesn't cover: the wizard around the page. `PrefsWindowController` isn't linked - it wants
the XPC client, `AppDelegate` and its nib - so the page swap in `PrefsWindowController+ProfileWizard.m`,
the step that writes the edited conditions into the new profile's `conditions` key, and the reset that
keep one wizard run's networks from turning up in the next are all read, not run. (They are
syntax-checked with the same flags the app builds with, so at least a break there fails the build
rather than a test.) The suite copies the sweep-and-reposition code out of that handler to hold the
invariant above, so a change there needs a change here. Nor does it say the page looks right: a
label's width is measured with the cell's own fitting size and a paragraph's height with an
`NSString` drawing rect, which approximates what the layout will do.

## About window

Compiles `App/Base.lproj/AboutWindow.xib` with `ibtool` and `Shared/Localizable.xcstrings` with
`xcstringstool`, loads the result through the real `AboutWindowController`, and for `en`,
`zh-Hans` and `zh-Hant` checks the fork attribution is present, names the upstream baseline and
the branch it was taken from, credits Objective-See and Patrick Wardle, fits the band laid out
for it, overlaps no other control and stays inside the window. This is a geometry check, not a
rendering one - it can't tell you the window looks good.

## The language the UI runs in

The app ships 13 languages and runs in English until the user picks another one. The pick is kept
under the app's own `language` default, and what the UI actually runs in is the app's own
`AppleLanguages` entry - the same key System Settings writes when a language is chosen for one app.
`run_language_tests.sh` compiles the real `Preferences.xib`, the code catalog, the window's own
catalog and the real asset catalog into a throwaway bundle, loads the window through the real
`PrefsWindowController`, and - in every language the catalogs carry - checks:

- the model (`Shared/Language.m`): English is the default and is offered first, every language is
  offered under its own name (the autonym the model carries, so the picker reads the same whichever
  UI language is loaded), no two share a name, a code the build doesn't ship (`zh`, `pt`, `en-CN`,
  `EN`, an empty string, nil) is refused rather than accepted, and an unknown code comes back as
  itself
- what the UI runs in: the pick made in the app wins, then the language chosen for this app outside
  it, then English - so a Mac whose own language is neither English nor shipped still gets an
  English UI until something is chosen
- what a pick writes down: only a shipped code is stored, the running window's `AppleLanguages` is
  left alone (the strings only change after a restart), and the restart is offered while - and only
  while - the pick differs from the language on screen
- the next launch: the stored pick is what the process loads, a language chosen outside the app is
  taken over as the pick (so a later change there isn't re-read as if the user had never chosen),
  and with nothing chosen anywhere `AppleLanguages` is forced to English
- the tab: it sits beside the five tabs that were there, under the tag the handler switches on and
  the identifier `-switchTo:` looks up, is labelled from the window's catalog in the language on
  screen, and carries the icon the asset catalog ships
- the pane: the picker offers the model's languages in its order, each named in its own language
  and carrying the code the pick stores, it shows the language the app is running in, the note and
  the button are the translated ones and the note names the app, and picking another language
  stores it, leaves the running strings alone and turns the restart button on
- the room the pane gives its words: every control is on the pane and clear of the others, and the
  title, the note and the button's title fit the room they are given - which is how the button was
  found to be 150pt wide, enough for "Restart Now" and 4pt too narrow for "Jetzt neu starten"
- the catalogs: the languages the model offers are exactly the languages the three catalogs carry,
  the tab's own words are written down in all of them (and translated, not left in English), and
  the note keeps the app's name in every language

What it doesn't cover: the restart itself. `restartNow:` asks the workspace to launch a second copy
of the running bundle; the suite checks the button is wired to it, not that a relaunch works, since
the test's bundle is not the app. Nor does it check what macOS makes of a process's `AppleLanguages`
at launch - that is the key System Settings writes too, and the adoption path is checked on the
model instead.

One trap worth naming: `[nil compare:…]` answers 0, so a read-back written as
`0 == [value compare:expected]` accepts a value that was never stored as the expected one. Every
read-back of something that should have been written goes through a nil-safe helper because of it -
a stored pick that silently wasn't stored passed exactly that way before the helper existed.

## Taking over a previous install's data directory

The rules and preferences live in a directory named for this project now, while an install of the
previous name kept them in `/Library/Objective-See/LuLu`. `+[InstallMigration migrateFromDirectory:…]`
runs at the top of the extension's `main`, before anything reads `INSTALL_DIRECTORY`, and
`run_install_migration_tests.sh` links that real source and drives it against throwaway pairs of
directories under `$TMPDIR` - every case makes its own, so no case inherits another's disk state.
It checks:

- only what this build reads is taken: `rules.plist`, `rules_v1.plist`, `preferences.plist` and the
  `Profiles` folder - and that list is the macros the extension itself reads, not a copy of them
- a folder that doesn't exist is not invented: no previous install leaves no new directory behind
- a store this build has already made is never taken over from, *including* one that exists and is
  still empty - the second run of the same migration reports it picked nothing up
- contents come across whole, the `Profiles` folder with everything in it, and the taken files are
  gone from the old directory
- a file this build doesn't read stays where it is, and so does the old directory around it
- once the old directory holds nothing, it goes - which is what "delete the historical config
  directory" means here, and why an empty-but-present directory is still deleted
- when the previous name is still installed (`/Applications/LuLu.app`), its files are *copied*:
  that firewall reads them out of that directory while it runs, so moving them would break a
  working install out from under it

What it doesn't cover: `/Library` itself (the paths come from `consts.h`, and the suite only checks
the two macros name different directories, one of them this project's), the cross-volume case where
a move fails and the copy-after-letting-go fallback takes over, and the caller's own reading of
`/Applications/LuLu.app` - that flag is simply passed in.

## The release the update check reads

`PRODUCT_VERSIONS_URL` is GitHub's API for this project's latest release, and
`+[ReleaseFeed releaseFromJSON:]` is what turns that answer into a version.
`run_release_feed_tests.sh` links the real source and feeds it the payloads the API answers with -
a release, `{"message": "Not Found"}`, a rate-limit message, an array, a bare string, broken JSON,
a `tag_name` that is null, a number, empty or `latest`. It checks the version out of `v4.5.3` is
`4.5.3`, that a tag which isn't a number is refused rather than read as some future version, and
that the comparison is the numeric one - `4.5.10` is past `4.5.2`, where sorting them as text puts
it *before* `4.5.2` and the update check would sit silent through ten patch releases.

What it doesn't cover: downloading a release. That url is rate limited per ip address (60 checks an
hour without a token), so asking GitHub mid-test would go red for reasons that have nothing to do
with this build. The url itself is checked as text: this project, the latest release, and the API
address rather than the page a user is sent to (`PRODUCT_RELEASES_URL`, which the update window
opens). It also doesn't cover `Update.m`'s dispatch and error plumbing, which needs a network to
exercise; `checkForUpdate:` now has one job left in it - ask, hand the answer to `ReleaseFeed`,
compare against `getAppVersion()`.

## The identity a build derives from its own signature

Upstream wrote its own Developer ID into the sources twice - the string the extension pinned
clients to, and the team id inside the Mach service name - so a fork signed by anyone else built
cleanly and could never connect. The same identity sat where nothing compiles it either: the
project file's `DEVELOPMENT_TEAM` settings and `DMG/createDMG.sh`; both are filled in by whoever
builds now. The sources are identity-free: both halves derive what they need from the signature
itself. `run_signing_identity_tests.sh` links the real `Shared/SigningIdentity.m` and checks:

- the client requirement names the app's identifier and pins the *team* through the certificate's
  OU field (`certificate leaf [subject.OU] = "…"`), never through the common name; the macOS-13
  listener variant adds the version floor `info [CFBundleShortVersionString] >= "2.0.0"`; and a
  build that carries no team (unsigned or ad-hoc) falls back to an identifier-only requirement
  rather than one no signature can satisfy
- every requirement the code can produce is one the system compiles
  (`SecRequirementCreateWithString` accepts it)
- the `$(TeamIdentifierPrefix)` semantics the plists rely on: a team's prefix carries its trailing
  dot, a teamless build leaves the name unchanged, and an absent name is refused rather than
  expanded into a stray dot
- the Mach service name is read from the extension's own `NEMachServiceName` - the key launchd
  registers it under - and only out of a `*.systemextension`; an unexpanded variable left standing
  in the plist, a missing key, a missing plist or a plug-in that isn't the system extension all
  fall back to the base name, and an app embedding no extension yields none
- the shipped wiring, as source text: `consts.h` carries no signing string and no upstream team id,
  neither half contains a requirement or a service name of its own, each asks the new class
  (`… extensionMachServiceName`, `… listenerRequirement`, `… clientRequirement`,
  `… embeddedExtensionMachServiceName`), the project builds the bundle id the requirement names,
  and the extension's `Info.plist` is written from the same name both halves read
- the two steps that never reach a compiler: the project's `DEVELOPMENT_TEAM` settings name nobody
  but stay there to be filled in, and the dmg step signs with `$SIGN_IDENTITY` from the environment,
  failing the build loudly when it isn't set, instead of naming a certificate in the file

The fixtures are fake `.app`/`.systemextension` trees built under `$TMPDIR`. The test binary is
unsigned, so the no-team path is the one that runs live; the named-team path is checked through the
`…ForTeam:` calls.

What it doesn't cover: whether the system accepts any of it. Nothing here signs, registers with
launchd or connects over Mach - observing that needs a signed pair. And whether macOS will load
such a pair at all: the fork's NE/System-Extension entitlements still need a provisioning profile
from the paid Apple Developer Program, which no source text can substitute for.

## When one source file becomes several

Three of the larger sources are each spread over several files now, as *categories of the same
class* and never as new classes: `RulesWindowController` and `PrefsWindowController` are their
nibs' File's Owner, and a new class name would break every outlet and action connection.

| class | the files it is made of |
|-------|-------------------------|
| `FilterDataProvider` | `.m`: the provider's setup, `handleNewFlow:`, alerts and related flows; `+Inbound.m`: `allowNoClient:`, `processInboundEvent:`; `+Outbound.m`: `processEvent:` |
| `RulesWindowController` | `.m`: the window, loading the rules, the add and delete buttons; `+Outline.m`: the outline's data source and delegate, its cells, the delete key; `+RuleActions.m`: the menu on each row and what its items do |
| `PrefsWindowController` | `.m`: the toolbar, the preferences, the profile list; `+ProfileWizard.m`: the steps of the add-profile sheet; `+Language.m`: the language tab, which builds its pane in code because its contents are the languages the build ships |

Each comes with a `+Private.h` saying once what was one file's private business: the verdicts and
the globals in the extension's case, and in the app's the shared `#define`, the same externals, and
the selectors one of the files calls on another.

No suite above links the extension classes - they want the XPC client and a running extension - so a
method left behind in the old file, or written into two of them, would build clean and fail in the
UI. (`PrefsWindowController` is the exception: `run_language_tests.sh` links it against a nil XPC
client, which is enough for the toolbar and the language tab.) `check_split_metadata.sh <binary
before> <binary after>` is the check that exists for the rest: every Objective-C method compiles to
a symbol named `-[Class selector]`, and every outlet a nib reconnects to is an ivar, so it compares
those two lists from the built binaries of the target whose file was split, and reports anything
gone, added or moved.

What it can't see: whether a method that moved still *does* what it did. When these three splits
were made the moved ranges were compared line-for-line against the original files, and the two
binaries' compiled file lists were compared as well; no script here repeats that.

## Passive mode FQDN rule creation

### 🎯 Domain Name Prioritization
- Prioritizes `flow.URL.host` over `flow.remoteHostname` over `remoteEndpoint.hostname`
- Ensures rules use domain names like `github.com` instead of IP addresses like `140.82.112.3`

### 🎨 Smart Port Display
- Hides common ports (80, 443) for cleaner UI display
- Shows uncommon ports (8080, 3000, etc.) to highlight important information
- Preserves full data internally for precise filtering

### 🔗 End-to-End Integration
- Validates complete flow from network traffic to final rule display
- Tests real-world scenarios with complex URLs and various port configurations

### Before/After Examples

| Before (IP-based) | After (Domain-based) |
|------------------|---------------------|
| `140.82.112.3:443` | `github.com` |
| `52.36.184.210:443` | `api.slack.com` |
| `127.0.0.1:8080` | `localhost:8080` |

✅ **9/9 tests pass** covering all functionality

## Files

| file | what it does |
|------|--------------|
| `test_network_context_and_direction.m` | conditions, change detection, app-reported identity, direction |
| `run_condition_and_direction_tests.sh` | builds and runs them against the real sources |
| `test_alert_window_direction.m` | loads the compiled alert nib, feeds it both directions |
| `run_alert_window_tests.sh` | compiles the nib and strings, runs the alert checks per language |
| `test_wifi_identity.m` | drives the app's sampler against a stand-in extension |
| `run_wifi_identity_tests.sh` | builds and runs it with the real intake it reports into |
| `test_add_rule_direction.m` | loads the compiled add-rule nib, picks a direction, presses 'add' |
| `run_add_rule_tests.sh` | compiles the nib and strings, runs the checks per language |
| `test_profile_conditions.m` | fills in the network-conditions page and reads back its conditions |
| `run_profile_conditions_tests.sh` | builds the page with the real converter and runs it per language |
| `test_about_window_layout.m` | loads the compiled About nib and measures the attribution |
| `run_about_window_tests.sh` | compiles the nib and strings, runs the layout checks per language |
| `test_language.m` | the language model, and the Settings tab that shows and stores the pick |
| `run_language_tests.sh` | builds the window with its catalogs and runs it in all 13 languages |
| `test_install_migration.m` | takes a previous install's store across, in trees it makes and throws away |
| `run_install_migration_tests.sh` | builds and runs it against the real `Shared/InstallMigration.m` |
| `test_release_feed.m` | reads release payloads as the GitHub API answers them, and compares versions |
| `run_release_feed_tests.sh` | builds and runs it against the real `Shared/ReleaseFeed.m` |
| `test_signing_identity.m` | the requirement a build derives from its own team, and the service name both halves read |
| `run_signing_identity_tests.sh` | builds and runs it against the real source, the plists, the project file and the dmg step |
| `mutation_check.sh` | reintroduces each fixed bug and reports whether a check catches it |
| `check_split_metadata.sh` | compares two builds' method and ivar lists, for when one class becomes several files |
| `test_passive_mode_improvements.m` | passive-mode rule suite (its own copies of the logic) |
| `run_passive_mode_tests.sh` | builds and runs it |

## Do the checks actually catch anything?

`mutation_check.sh` re-breaks each source the way it was broken before - 97 breaks in all: an unset
direction reading as `outbound`, a condition set stopping being AND'ed, an inbound alert worded as
outbound, an answer losing its direction, the wrong key on a reported ssid, a picker whose choices
are tagged the wrong way round, a list annotation that says the opposite of what the rule means, a
translation that quietly reverts to English, a popup built but never put on the page, a network that
reads the same as another so never reaches the list, a row that loses whatever is still being typed
when the user clicks somewhere else, a store taken over from an install that already has one, the
old directory deleted while it still holds something, a version tag that isn't read as a version,
versions compared as text, a UI starting in a language other than English, a language list that no
longer matches the catalogs, a pick the build can't honor stored anyway, a restart offered exactly
when nothing would change, a language tab tagged with a case the handler doesn't know, a toolbar
label filed under a key the nib doesn't ask for, a restart button pinned to the English width, a
requirement that stops naming the signing team, the certificate's name standing in for its team, a
requirement from another build hardcoded back into a half, the version floor slipping or dropping,
the team prefix losing its dot or wearing one it shouldn't, a fallback naming a service launchd
never registered, any plug-in counting as the system extension, an identity from another build
written back into `consts.h`, the extension registering a name the app won't look up, a team id
pasted back into the project's signing settings, and an identity written back into the dmg step -
and requires a suite to go red for every break. It restores the sources from its own copies and
verifies they come back byte-for-byte; if one break is missed, it says which. Runs take a while:
each break rebuilds and re-runs a suite.
