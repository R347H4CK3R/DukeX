# Changelog

All notable DukeX changes are tracked here. DukeX is still experimental, so
entries focus on user-visible behavior and port-specific runtime changes.

## Unreleased

## v1.0.2 - Expanding the Xbox Experience

### Added

- Added the first native macOS release, built with Mac Catalyst and packaged
  with a nested Xemu fork so desktop users can install DukeX as a single app.
- Added XB.Live Rich Presence reporting so friends can see the currently
  running title while DukeX tracks supported playtime sessions.
- Added a full XB.Live messaging experience with threaded conversations,
  friend messaging, unread indicators, supported game invites, and continued
  compatibility with existing Xbox inbox messages.
- Added expanded XB.Live social features, including friend requests, friend
  management, online presence details, and richer community status throughout
  the Profile experience.
- Added the XB.Live Activity Feed across iOS and macOS, combining XB.Live news,
  friend online status, friend achievement unlocks, and community updates in a
  single timeline.
- Added controller landscape mode on iOS so compatible controllers can drive a
  controller-first library and launch experience.
- Added deeper AirPlay and external-display handling for a more reliable
  console-style setup on supported displays.

### Changed

- Updated the Achievements section with clearer Games, Apps, and Cores grouping
  plus consistent artwork for XB.Live Core, DukeX Core, and special test titles.
- Improved Activity Feed and article handling with cached news metadata,
  cached article details, cached artwork, rounded image presentation, and more
  comfortable reader margins.
- Improved macOS event handling so events, paid events, and tournaments open in
  focused detail windows instead of taking over the full Profile surface.
- Improved game tile sizing and cover masking so library spacing is more even
  across iOS and macOS.
- Updated supported cloud-save sync paths for XB.Live console identity v2,
  content-hash dedupe, and server-assisted cross-console restore handling.

### Fixed

- Fixed achievement progress rounding so time-based progress does not report
  100% before the unlock threshold has actually been reached.
- Fixed iOS touch-control regressions from the v1.0.2 development cycle while
  preserving the existing iOS play interface.

### Notes

- iOS builds continue to support iOS 16.0 or later on Apple A14 Bionic or Apple
  M1 hardware or newer, with iOS 16 support remaining experimental.
- macOS builds are distributed directly through GitHub Releases as a DMG and
  still require users to provide their own legally obtained Xbox system files
  and games.
- XB.Live account access is required for the new Rich Presence, messaging,
  Activity Feed, social, and supported cloud-sync features.

## v1.0.1 - Bringing Xbox Live Back to Your Pocket

### Added

- Added XB.Live profile integration as the foundation for DukeX's collaboration
  with the XB.Live preservation team.
- Added achievement tracking, friends list integration, message history
  support, and multiplayer event tracking for Insignia-hosted and XB.Live-hosted
  community events.
- Added supported cloud sync for game saves and Xbox Live profile data between
  DukeX and real Xbox hardware through XB.Live services.
- Added `.manicskin` touch-control support, with `.deltaskin` and `.gammaskin`
  compatibility for additional community skin formats.
- Added a new default touch-control skin designed by `u/starvingartist12`.
- Added AirPlay support for playing on compatible larger displays.
- Added selectable themes and personalization options.
- Added automatic cover art retrieval for supported titles.
- Added native URL scheme support for external launch requests and Home Screen
  game launch shortcuts.

### Changed

- Overhauled the Profile tab around XB.Live services so Xbox identity features
  are no longer limited to a single device.
- Improved graphics compatibility, rendering stability, and runtime handling
  across a wider range of titles.
- Refined rendering and presentation behavior behind the scenes for smoother
  gameplay on supported hardware.
- Experimentally lowered the minimum supported operating system to iOS 16.0.
- Established the hardware floor at Apple A14 Bionic or Apple M1 hardware or
  newer.

### Notes

- XB.Live account access is required for the new XB.Live profile, community,
  and cloud-sync features.
- DukeX continues to be distributed as a free, open-source project through
  sideloading repositories, with StikStore and SideStore metadata maintained in
  `altsource/source.json`.
- iOS 16 support remains experimental, and users may encounter issues not
  present on newer operating system versions.

### Known Bugs

- There is a known bug where certain touch controls stop functioning as
  intended following device rotation. For this release, to make the best use of
  touch controls, launch the game with the app already in the orientation you
  wish to play in, i.e. portrait or landscape.

## v1.0.0 - Initial Public Release

### Added

- Added favorites, title, Live, and recent sorting to the Games tab.
- Added per-game favorite toggles to each game's long-press menu.
- Added portrait and landscape library column controls in Settings.
- Added canonical AltStore/SideStore source metadata and store-facing image
  assets under `altsource/`.

### Changed

- Updated the game library layout to support orientation-specific column
  counts while preserving the existing iPhone-first presentation.
- Updated AltSource metadata and release-facing documentation for the v1.0.0
  release.
- Reorganized new Games tab code into smaller components for sorting, layout,
  and persisted library state.

### Fixed

- Fixed cover imports being written back into `ROMs`; new and migrated cover
  art now lives in the user-facing `Covers` folder.
- Refreshed Settings folder size indicators whenever the Settings tab becomes
  active.

## v0.1.5 - Alpha Tester Build

### Added

- Added Insignia live indicators to the Games tab for titles with detected
  Xbox Live support.
- Added automatic live-status refresh when the Games tab becomes active.
- Added title ID capture during XISO import so per-title services can key
  against stable game metadata instead of display names alone.

### Changed

- Reorganized the DukeX iOS source tree into app, feature, library, presenter,
  runtime, and service folders.
- Split the large presenter and SwiftUI surface into smaller files for HUD,
  Metal layer setup, exit overlay, game library, profile, and settings code.
- Tuned game tiles for the live badge layout while keeping the existing
  two-column library presentation.

## v0.1.4 - Alpha Tester Build

### Added

- Added iOS 18.x launch support alongside the existing iOS 26+ Universal.js
  flow.
- Added app-owned launch logging under `Documents/DukeXLogs/latest.log` so
  testers can share launch diagnostics from Files.

### Changed

- iOS 18.x now uses QEMU TCG's split W^X mapping path
  (`split-wx=on`) after JIT has been enabled for the DukeX process.
- The iOS 18 W^X path now avoids same-address RWX translated-code mappings,
  which caused early launch stalls or crashes on test devices.
- Launch diagnostics now record the selected JIT path, JIT handoff requirement,
  and Universal.js state.

### Notes

- iOS 26 or later still requires the StikDebug Universal.js workflow.
- iOS 18.x requires JIT to be enabled for the app process, but does
  not use Universal.js.

## v0.1.3 - Alpha Tester Build

### Changed

- Lowered the DukeX app and embedded core deployment target from iOS 26.3 to
  iOS 18.0.
- Preserved the iOS 26+ Universal.js JIT path while avoiding the Universal.js
  handoff on iOS 18.x devices.
- Updated runtime settings copy, build scripts, documentation, and issue
  templates to reflect the iOS 18.0+ install target.
- Bumped the app version to `0.1.3`, build `13`.

### Notes

- iOS 26 or later still requires StikDebug with Universal.js assigned to
  DukeX for JIT.
- iOS 18.x devices use the standard sideload/JIT workflow and are not forced
  through the Universal.js path.

## v0.1.2 - Alpha Tester Build

### Added

- Native SwiftUI game library, profile, and settings interface.
- User-facing `BIOS`, `ROMs`, and `Covers` folders.
- Per-game cover art, config import, shader-cache clearing, and remove-game
  actions.
- Built-in FPS/system statistics overlay for device-side testing.
- Advanced translation block cache size setting.
- Insignia-oriented network settings and Force NAT to Insignia default.
- In-game exit prompt returning to the game library.
- Security reporting policy in `SECURITY.md`.

### Changed

- Bundle identifier changed to `com.mafty.dukex`.
- App display name, app switcher name, and branding standardized on DukeX.
- README and release-facing documentation refreshed for alpha testing.

### Known Issues

- Rendering correctness still varies by title.
- Some Halo 2 HUD effects remain incomplete on the current Vulkan/MoltenVK
  path.
- Apple's Metal HUD does not currently appear for the embedded presenter.
