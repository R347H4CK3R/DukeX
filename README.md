# DukeX

DukeX is an experimental iOS-focused fork of [xemu](https://xemu.app). It
embeds the xemu core in a native Swift shell, adds an iOS library/settings
interface, and presents the Vulkan renderer through MoltenVK and a native
`CAMetalLayer`.

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
- `hw/xbox/`, `target/i386/`, `tcg/`, `ui/`, `net/`, `block/`: core emulator
  code used by the embedded iOS runtime.
- `docs/upstream/`: preserved upstream QEMU reference files that are useful for
  provenance but not part of the first-stop DukeX workflow.

## Upstream

DukeX is based on xemu, which is itself based on QEMU. For upstream xemu
information, visit [xemu.app](https://xemu.app).

QEMU/xemu licensing information remains in `LICENSE`, `COPYING`, and source
file headers throughout the tree.
