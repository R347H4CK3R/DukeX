<div align="center">
  <img src="docs/assets/branding/dukex-logo.png" alt="DukeX" width="360">
  <p>
    <strong>Original Xbox emulation for iOS, built from xemu with a native Swift interface.</strong>
  </p>
  <p>
    <img src="https://img.shields.io/badge/status-alpha-8f95c4?style=flat-square" alt="Status: alpha">
    <img src="https://img.shields.io/badge/platform-iOS%2018%2B%20arm64-111827?style=flat-square" alt="Platform: iOS 18+ arm64">
    <img src="https://img.shields.io/badge/renderer-MoltenVK%20%2B%20Metal-1f6feb?style=flat-square" alt="Renderer: MoltenVK and Metal">
    <img src="https://img.shields.io/badge/JIT-version%20aware-2f855a?style=flat-square" alt="JIT: version aware">
  </p>
</div>

DukeX is an experimental iOS-focused frontend for [xemu](https://xemu.app).
It embeds the xemu core in a native Swift shell, provides an iPhone-friendly
library and settings experience, and presents the Vulkan renderer through
MoltenVK and a native `CAMetalLayer`.

> DukeX does not include Xbox system files, game images, or signing
> certificates. Users and testers are required to provide their own legally
> obtained files. DukeX is intended solely for legitimate emulation and
> preservation purposes, and is not designed for use with pirated materials.

## At a Glance

- Device target: iPhoneOS arm64, install target iOS 18.0 or later.
- Runtime: TCG with version-aware JIT setup; iOS 26 or later uses the
  StikDebug Universal.js flow.
- Graphics: xemu Vulkan renderer through MoltenVK with a native Metal
  presenter.
- Interface: native SwiftUI library, profile, and settings tabs.
- Networking: Insignia-oriented NAT defaults with user-configurable settings.
- Known work: rendering correctness, Metal HUD visibility, and title-by-title
  tuning.

## Features

| Category | Details |
| --- | --- |
| Game library | Two-column library, cover artwork, game launch, dashboard launch, and long-press actions. |
| File management | User-accessible `BIOS`, `ROMs`, and `Covers` folders through iOS file sharing. |
| JIT workflow | Optional automatic StikDebug handoff for the iOS 26+ Universal.js JIT flow. |
| Display | MoltenVK-backed Metal presenter with portrait and landscape-aware sizing. |
| Input | Controller support through iOS GameController APIs. |
| Online setup | Insignia-focused NAT defaults plus editable network settings. |
| Per-game tuning | Custom config import and shader-cache clearing from each game menu. |
| Diagnostics | Built-in FPS/system statistics HUD for device-side testing. |
| Advanced runtime | TCG translation block cache size controls for performance testing. |

## Availability

DukeX alpha builds are intended for sideload distribution through StikStore and
SideStore, with release artifacts published through GitHub Releases when public
testing opens.

Compatibility and performance vary by title, device, iOS version, and JIT
availability. DukeX should be treated as early alpha software.

<p align="center">
  <img src="docs/assets/branding/stikstore-badge.png" alt="Available on StikStore" width="170">
  <img src="docs/assets/branding/sidestore-badge.png" alt="Available on SideStore" width="170">
</p>

## Dependencies

### Runtime

- Supported iPhone or iPad hardware for device testing.
- iOS 18.0 or later. iOS 26 or later requires StikDebug with Universal.js
  assigned to the DukeX bundle identifier for JIT; older supported iOS versions
  use the standard sideload JIT path.
- Legally obtained Xbox flash BIOS, MCPX ROM, and HDD image.
- Legally obtained XISO game images.
- Optional Insignia account and registered dashboard for online service testing.

### Build

- macOS with Xcode 26 or newer and the iPhoneOS SDK.
- MoltenVK iOS framework and headers, supplied locally and not committed.
- vcpkg `arm64-ios` dependency prefix used by the embedded xemu core.
- Meson, Ninja, Python, and the standard xemu/QEMU build toolchain.
- Apple signing assets only when creating signed device builds or sideload
  release packages.

## Documentation

- [iOS port overview](docs/ios-port/README.md)
- [iOS build instructions](docs/ios-port/BUILDING.md)
- [Renderer notes](docs/ios-port/RENDERER.md)
- [Public release checklist](docs/ios-port/PUBLICATION.md)

## Repository Layout

DukeX keeps the QEMU/xemu source tree at the repository root because the
upstream build system expects that layout. The main DukeX-specific areas are:

| Path | Purpose |
| --- | --- |
| `ios/` | Native Swift shell, assets, settings UI, and device build scripts. |
| `docs/ios-port/` | DukeX iOS build, renderer, and release notes. |
| `docs/assets/branding/` | README and release-facing DukeX image assets. |
| `hw/xbox/`, `target/i386/`, `tcg/`, `ui/`, `net/`, `block/` | Core emulator code used by the embedded iOS runtime. |
| `docs/upstream/` | Preserved upstream QEMU reference files for provenance and contributor context. |

## Upstream And Licensing

DukeX is based on xemu, which is itself based on QEMU. For upstream xemu
information, visit [xemu.app](https://xemu.app).

QEMU/xemu licensing information remains in `LICENSE`, `COPYING`, and source
file headers throughout the tree. DukeX is not affiliated with Microsoft, Xbox,
or the xemu project.
