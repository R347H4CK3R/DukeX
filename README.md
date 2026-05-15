<p align="center">
  <img src="docs/assets/branding/dukex-icon.png" alt="DukeX app icon" width="96">
</p>

<p align="center">
  <img src="docs/assets/branding/dukex-logo.png" alt="DukeX" width="520">
</p>

<p align="center">
  <strong>An experimental iOS-focused original Xbox emulator frontend built on xemu.</strong>
</p>

<p align="center">
  <img src="docs/assets/branding/stikstore-badge.png" alt="Available on StikStore" width="220">
  <img src="docs/assets/branding/sidestore-badge.png" alt="Available on SideStore" width="220">
</p>

DukeX embeds the [xemu](https://xemu.app) core in a native Swift shell, adds an
iOS-first library/settings interface, and presents the Vulkan renderer through
MoltenVK and a native `CAMetalLayer`.

This repository does not include Xbox system files, game images, signing
certificates, provisioning profiles, MoltenVK binaries, or sideloaded release
artifacts. Users and testers must provide their own legally obtained files.

## Current Status

- Device target: iPhoneOS arm64, currently developed against iOS 26.3.
- Runtime: TCG with the iOS Universal.js JIT flow used by StikDebug.
- Renderer: xemu Vulkan renderer through MoltenVK with a native Metal
  presenter.
- UI: native Swift library, profile, and settings tabs.
- Known gaps remain in rendering correctness, Metal HUD visibility, and
  game-by-game performance.

## Features

- Native SwiftUI app shell designed for iPhone rather than desktop xemu UI.
- Two-column game library with cover art, per-game launch, and dashboard launch.
- User-accessible `BIOS`, `ROMs`, and `Covers` folders through iOS file sharing.
- Automatic StikDebug handoff support for the Universal.js JIT workflow.
- MoltenVK-backed Metal presenter with portrait and landscape-aware display
  sizing.
- Controller support through iOS GameController APIs.
- Game Mode entitlement and metadata for supported iOS versions.
- Insignia-oriented networking defaults with configurable NAT settings.
- Per-game configuration import and shader-cache clearing from the game menu.
- Built-in FPS/system statistics HUD for device-side testing.
- Advanced runtime tuning for TCG translation block cache size.

## Distribution

Public alpha builds are intended for sideload distribution through StikStore and
SideStore, with release artifacts published from GitHub Releases when testing
opens. DukeX is currently alpha software; compatibility and performance vary by
title, device, iOS version, and JIT availability.

## Dependencies

Runtime and testing dependencies:

- iPhone or iPad running a supported iOS/iPadOS version.
- StikDebug with Universal.js assigned to the DukeX bundle identifier for JIT on
  iOS 26 or later.
- Legally obtained Xbox flash BIOS, MCPX ROM, HDD image, and XISO game images.
- Optional Insignia account and registered dashboard for online service testing.

Build dependencies:

- macOS with Xcode 26 or newer.
- iPhoneOS SDK and command-line developer tools.
- MoltenVK iOS framework and headers.
- vcpkg `arm64-ios` dependency prefix used by the embedded xemu core.
- Meson, Ninja, Python, and the standard xemu/QEMU build toolchain.
- Apple signing assets only when creating a signed device build.

## Documentation

- [iOS port overview](docs/ios-port/README.md)
- [iOS build instructions](docs/ios-port/BUILDING.md)
- [Renderer notes](docs/ios-port/RENDERER.md)
- [Public release checklist](docs/ios-port/PUBLICATION.md)

## Repository Layout

DukeX keeps the QEMU/xemu source tree at the repository root because the
upstream build system expects that layout. The main DukeX-specific areas are:

- `ios/`: native Swift shell, assets, settings UI, and device build scripts.
- `docs/ios-port/`: DukeX iOS build, renderer, and release notes.
- `docs/assets/branding/`: README and release-facing DukeX image assets.
- `hw/xbox/`, `target/i386/`, `tcg/`, `ui/`, `net/`, `block/`: core emulator
  code used by the embedded iOS runtime.
- `docs/upstream/`: preserved upstream QEMU reference files that are useful for
  provenance but not part of the first-stop DukeX workflow.

## Upstream

DukeX is based on xemu, which is itself based on QEMU. For upstream xemu
information, visit [xemu.app](https://xemu.app).

QEMU/xemu licensing information remains in `LICENSE`, `COPYING`, and source
file headers throughout the tree.
