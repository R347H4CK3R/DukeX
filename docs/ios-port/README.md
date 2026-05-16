# DukeX iOS Port

DukeX is an iOS-focused xemu fork that embeds the emulator core in a native
Swift application shell. The app manages user-facing library folders, launch
configuration, JIT handoff, and a MoltenVK-backed Metal presenter for rendering
guest output on iPhone.

The iOS shell creates these folders in app Documents:

- `BIOS`: flash BIOS, MCPX boot ROM, EEPROM, and HDD image.
- `ROMs`: XISO game images.
- `Covers`: user-supplied library cover art.
- `GameConfigs`: optional per-game xemu configuration overrides.
- `ShaderCaches`: per-game pipeline cache storage.

Runtime dependencies are intentionally not included in source control. Testers
must provide their own legally obtained Xbox system files and game images.

## Current Status

- Native Swift library/settings/profile UI is functional.
- Launching games through the embedded core works on-device with JIT enabled.
- Rendering uses the Vulkan renderer through MoltenVK and a native
  `CAMetalLayer` presenter.
- Halo 2 reaches gameplay at viable speed on the current performance baseline.
- Known rendering gaps remain around some HUD effects and depth/primitive edge
  cases.

## JIT

DukeX installs on iOS 18.0 or later. iOS 18.x uses the standard
split W^X reprotection path after JIT has been enabled for the process.
On iOS 26 or later, the current device workflow expects StikDebug with
Universal.js assigned to the app bundle identifier. The app can open the
StikDebug URL scheme before launch and then resume the pending game launch
after returning.

The shell passes `XEMU_IOS_UNIVERSAL_JIT=1` to the core only when Universal.js
JIT is enabled in Settings and the device is running iOS 26 or later. iOS 18.x
keeps that variable disabled and relies on W^X reprotection.

## Networking

The app includes a NAT settings section and defaults to Insignia-oriented DNS
routing. The profile tab is app-local UI and does not replace dashboard-side
Insignia registration.

## Review Focus

For renderer review, start with:

- `hw/xbox/nv2a/pgraph/vk/display.c`
- `hw/xbox/nv2a/pgraph/vk/renderer.h`
- `hw/xbox/nv2a/pgraph/vk/shaders.c`
- `hw/xbox/nv2a/pgraph/vk/texture.c`
- `ios/DukeX/DukeX/NativeMetalPresenter.swift`
- `ios/DukeX/DukeX/EmulatorCoreRuntime.swift`

## Related Documents

- `docs/ios-port/BUILDING.md`: local build and signing setup.
- `docs/ios-port/RENDERER.md`: presenter and Vulkan/MoltenVK notes.
- `docs/ios-port/PUBLICATION.md`: public release checklist.
