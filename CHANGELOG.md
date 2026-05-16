# Changelog

All notable DukeX alpha changes are tracked here. DukeX is still experimental,
so entries focus on tester-visible behavior and port-specific runtime changes.

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
- README and release-facing documentation refreshed for private alpha testing.

### Known Issues

- Rendering correctness still varies by title.
- Some Halo 2 HUD effects remain incomplete on the current Vulkan/MoltenVK
  path.
- Apple's Metal HUD does not currently appear for the embedded presenter.
