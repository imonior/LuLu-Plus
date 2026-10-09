# LuLu_Plus

[简体中文](README_zh-Hans.md) | [正體中文](README_zh-Hant.md)

LuLu_Plus is a free, open-source macOS firewall, developed by [imonior](https://github.com/imonior) and
maintained at [github.com/imonior/LuLu-Plus](https://github.com/imonior/LuLu-Plus).

**Attribution:** \
LuLu_Plus is a fork of [LuLu](https://github.com/objective-see/LuLu), created and maintained by
[Objective-See](https://objective-see.com). It starts from LuLu's `master` branch as of 4 October 2026 -
the code released after 4.5.1 and before 4.5.2 - rather than from the 4.5.1 tag itself. The outbound
firewall, the rule model, the alerting flow, and the system/network-extension plumbing all come from that
project. Thanks to Patrick Wardle and Objective-See for open-sourcing LuLu - this fork builds directly on
their work.

**What this fork adds:**

- rules carry a direction (`both`, `outbound`, `inbound`), and the rules list and the add/edit window say
  and let you set which one a rule means
- inbound flows are decided and reported, so a peer connecting *in* gets its own alert and its own rule
- a profile can name the networks it applies to (interface, interface type, ssid, bssid, gateway), and the
  add-profile wizard has a page for writing those conditions
- the Wi-Fi identity a profile keys on is sampled by the app and handed to the extension over XPC, because
  a system extension can't ask for the location authorization that reading it requires
- a test suite under `LuLu_Plus/Tests`, including a mutation check that re-breaks each fixed bug and expects a
  test to go red

The screenshots, product page and donation links of the upstream project aren't carried over: this fork is
read from its own repository, and its checks are documented in
[`LuLu_Plus/Tests/README.md`](LuLu_Plus/Tests/README.md).

## From an earlier install

This build keeps its rules, preferences and profiles in `/Library/Application Support/lulu_plus`. An install
of the previous name kept them in `/Library/Objective-See/LuLu`, so the first time this build's extension
starts it takes that store over: `rules.plist`, `rules_v1.plist`, `preferences.plist` and the whole `Profiles`
folder come across, and the old directory is deleted once it holds nothing. Anything this build doesn't read
is left exactly where it is, and so is the directory still holding it.

While `/Applications/LuLu.app` is installed, its files are *copied* rather than moved - that firewall reads
them out of that directory for as long as it runs, and taking them away would stop it filtering.

One case isn't taken over: an install of the very first release, which kept its own program in
`/Library/Objective-See/LuLu/LuLu.bundle`. This app won't run alongside it and says so on start-up; the
older install has to go first. [`LuLu_Plus/Tests/README.md`](LuLu_Plus/Tests/README.md) covers the takeover,
and `run_install_migration_tests.sh` runs it against throwaway directory trees.

## Checking for updates

The update check reads this project's latest GitHub release
([`api.github.com/repos/imonior/LuLu-Plus/releases/latest`](https://api.github.com/repos/imonior/LuLu-Plus/releases/latest)),
so a release tagged `v4.5.3` is what a build of 4.5.2 reports as newer. A tag that isn't a version -
`latest`, `nightly`, `v4.5.3-rc1` - is refused rather than read as some future release, and versions are
compared as numbers, so `4.5.10` is correctly past `4.5.2`. The button in the "new version" window opens the
release page, not the API answer.

Unauthenticated, that API is 60 checks an hour per IP address; past that the check simply reports it failed.
Releases don't say which macOS they need, so the check doesn't claim to know one: it only ever says a new
version exists.

## Signing identity

Nobody's name is written into the code: each half reads the team that signed *this* build off the running
signature itself (`SecCodeCopySelf` -> the leaf's team) and builds what it checks from that
(`Shared/SigningIdentity.m`).

- The extension puts a code-signing requirement on every client that connects: this build's app
  (`identifier "com.imonior.lulu-plus.app"`) signed by the same team (`certificate leaf [subject.OU] =
  "<TEAM>"`). It hands that requirement, plus the `info [CFBundleShortVersionString] >= "2.0.0"` floor, to the
  listener on macOS 13+ (`setConnectionCodeSigningRequirement:`), and enforces the version-less variant
  itself with `SecTaskValidateForRequirement` on the connection's audit token. A client signed by another team
  can never match - Apple doesn't put your team in a certificate it didn't sign - so the check answers
  `errSecCSReqFailed` (-67050) and no connection is made. That path also requires a valid signature and the
  hardened runtime (`CS_VALID` and `CS_RUNTIME`), which an unsigned or ad-hoc build of the app fails one step
  earlier. A build whose own signature carries no team has nothing to pin to, so its requirement falls back to
  checking the identifier alone - weaker, and all there is.
- The mach service both halves meet on is derived, not written down: the extension listens on the name its
  `Info.plist` registers (`NEMachServiceName`, written `$(TeamIdentifierPrefix)com.imonior.lulu-plus` and
  expanded by the build to whichever team signs it), read back from that file; the app reads the same key out
  of the system extension it embeds. `DAEMON_MACH_SERVICE` in `Shared/consts.h` is only the base name, used if
  neither file can be read. The two application-group entitlements are written the same way.

So any Developer ID can sign this fork without editing a line: both halves agree on whoever signed them. The
signing *steps* still name the signer, of course - `DEVELOPMENT_TEAM` in
`LuLu_Plus/LuLu_Plus.xcodeproj/project.pbxproj` for Xcode builds, and the `codesign --sign` identity in
`DMG/createDMG.sh` for releases - but the code no longer does.

What that does not remove: the Network Extension and System Extension entitlements are *restricted* - the
system honors them only on a build carrying a provisioning profile issued to a paid Apple Developer Program
membership. A build signed with a free Apple ID, or unsigned, or ad-hoc, compiles, but macOS will not load its
system extension, whatever the XPC checks say. A development machine can be set up to accept a locally signed
extension instead (SIP off, developer mode), which is per-machine and not something a distributed build can
rely on.

The bundle ids also changed (`com.imonior.lulu-plus`, `.app`, `.extension`), and TCC records grants per
bundle id: anything the old app was allowed to do - the location access the ssid/bssid conditions need - has
to be given again to the new one.
