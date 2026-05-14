# DukeX / Xemu iOS Developer Handoff

Date: 2026-05-13

This repository is a working iOS port experiment for Xemu, wrapped in a native
Swift shell currently branded as DukeX. The goal is to run original Xbox titles
on iPhone with iOS JIT enabled by StikDebug Universal.js.

This document is written for a developer with no access to the previous AI
conversation. It captures the current state, build commands, important files,
known issues, and the safest next engineering steps.

For the current Insignia/Profile-tab protocol notes, see
`docs/handoff/INSIGNIA_PROFILE_RESEARCH.md`.

## Current Status

The app builds and installs on an iPhone using Xcode. The emulator core is
loaded in-process from `libxemu-ios-core.dylib` via `dlopen` and launched from
Swift.

Current known-good behavior from device testing:

- Universal.js JIT path works when StikDebug is configured for this app.
- Halo 2 boots, reaches the title screen, cutscenes, and gameplay.
- Halo 2 title/menu blue tint, shield/radar HUD, and major menu visuals are
  correct in the current host-depth-off configuration.
- Xbox Live/Insignia connectivity works when the user's real EEPROM is present
  in the app `BIOS` folder.
- Gameplay performance is still not production quality. Cutscenes can be
  smooth, but active gameplay can lag and show rendering artifacts.

Known problematic behavior:

- Rendering is still using a fallback CPU surface download path on iOS.
- MoltenVK/iOS does not expose the Vulkan geometry shader path Xemu expects.
- Some visual artifacts remain in Halo 2 gameplay.
- Halo CE reached menus, but creating a new player profile failed in testing.
- The in-game exit overlay is only an idea. It has not been implemented.
- Per-game custom configs are full replacement TOML files, not merge snippets.

## Current App UX

The Swift shell is in `ios/XemuIOS/XemuIOS`.

Main tabs:

- `Games`: two-column library, `Launch Dashboard`, cover art, long-press game
  actions, and tap-to-launch.
- `Profile`: local gamertag, public Insignia status/active-games view, and an
  official Insignia web-dashboard sign-in sheet.
- `Settings`: JIT/StikDebug toggles, display/network settings, runtime status,
  system file status, import system files, folder locations.

Branding:

- Center nav logo: `Assets.xcassets/DukeXLogo.imageset`.
- App icon: `Assets.xcassets/AppIcon.appiconset/xemu_1024.png`.

Runtime app folders in iOS Documents:

- `BIOS`: user-provided system files.
- `ROMs`: user-provided `.iso` or `.xiso` games.
- `Covers`: user-assigned cover images copied from Photos.
- `GameConfigs`: per-game full replacement config TOML files.
- `XemuLogs/latest.log`: latest stdout/stderr launch log.

The app intentionally does not bundle BIOS, MCPX, EEPROM, HDD, or games.

## Required User Files

The app scans `Documents/BIOS` for:

- Flash BIOS: any `.bin` larger than 512 bytes with a size multiple of 65536.
- MCPX: `.bin` exactly 512 bytes.
- EEPROM: `.bin` exactly 256 bytes, optional but needed for the user's Insignia
  setup.
- HDD: `.qcow2`, `.qcow`, `.img`, `.raw`, `.hdd`, or a suitable large `.bin`.

The app scans `Documents/ROMs` for:

- `.iso`
- `.xiso`

Game titles are parsed from `default.xbe` inside the XISO when possible. The
parser also accepts `default.xeb` as a fallback name. If parsing fails, the UI
falls back to the filename without extension.

## JIT / StikDebug

The intended device workflow uses StikDebug with `Universal.js`.

Swift side:

- `EmulatorFileStore.universalJITEnabled` sets `XEMU_IOS_UNIVERSAL_JIT`.
- `StikDebugAutoJITCoordinator` opens:
  `stikjit://enable-jit?bundle-id=<bundle>&script-name=Universal.js`
- The app waits for StikDebug to return before launching the core.

Core side:

- `tcg/ios-jit.c`
- `include/tcg/ios-jit.h`

In testing, StikDebug already had Universal.js assigned to this app. If a new
developer changes the bundle ID, StikDebug must be updated for that new bundle.

## Current Runtime Flags

`EmulatorCoreRuntime.invoke` currently sets these important flags before
calling `xemu_ios_main`:

```sh
XEMU_IOS_UNIVERSAL_JIT=1 or 0
XEMU_IOS_HOST_DEPTH_INTERPOLATION=0
XEMU_IOS_SURFACE_STATS=1
XEMU_IOS_FALLBACK_GENERATION_FILTER=1
XEMU_IOS_SKIP_GL_FINISH=1
XEMU_IOS_TCG_TRACE=0
XEMU_IOS_IRQ_TRACE=0
XEMU_IOS_TCG_WATCHDOG=off
XEMU_IOS_COROUTINE_PRIME_COUNT=640
XEMU_IOS_SYNC_DMA=0
XEMU_IOS_NV2A_READ_TRACE=0
XEMU_IOS_PCI_TRACE=0
XEMU_IOS_NV2A_WRITE_TRACE=0
XEMU_IOS_SYNC_RAW=0
XEMU_IOS_QCOW2_TRACE=0
XEMU_IOS_BLK_TRACE=0
XEMU_IOS_DMA_TRACE=0
```

Do not casually flip `XEMU_IOS_HOST_DEPTH_INTERPOLATION` back to `1`.
Host-depth interpolation reduced one artifact during testing, but broke Halo 2
menu tint and HUD/radar/shield rendering.

`XEMU_IOS_PRESENT_DOWNLOAD_FPS` was removed from the Swift runtime because the
visible frame cap felt bad during testing.

## Build Prerequisites

This project currently assumes:

- macOS with Xcode capable of building iOS 26.x apps.
- iPhone connected and trusted.
- Apple Development signing identity and provisioning.
- Source path with no spaces or colons. Xemu/QEMU configure rejects such paths.
- arm64-ios vcpkg dependencies.
- MoltenVK iOS framework and headers.

Default local dependency paths in scripts:

```sh
VCPKG_PREFIX or VITA3K_IOS_VCPKG_PREFIX:
  <VCPKG_ROOT>/installed/arm64-ios

MOLTENVK_ROOT:
  /Users/michaelweekley/.local/tools/moltenvk-ios/MoltenVK

MOLTENVK_FRAMEWORK:
  /Users/michaelweekley/.local/tools/moltenvk-ios/MoltenVK/dynamic/MoltenVK.xcframework/ios-arm64/MoltenVK.framework
```

A different developer should either reproduce those paths or pass env overrides.

## Build Commands

From a no-space checkout such as:

```sh
/Users/michaelweekley/xemu-ios-core
```

Build the core dylib:

```sh
XEMU_IOS_NINJA_TARGETS=libxemu-ios-core.dylib ios/scripts/build-core-ios.sh
```

Build the Xcode app wrapper:

```sh
xcodebuild \
  -project ios/XemuIOS/XemuIOS.xcodeproj \
  -scheme XemuIOS \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build-ios-xcode \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=<TEAM_ID> \
  PRODUCT_BUNDLE_IDENTIFIER=<UNIQUE_BUNDLE_ID> \
  build
```

Install without launching:

```sh
xcrun devicectl device install app \
  --device <DEVICE_UDID> \
  build-ios-xcode/Build/Products/Debug-iphoneos/XemuIOS.app
```

Current Michael-specific values used during testing:

```sh
DEVELOPMENT_TEAM=5Q9UYCH8TM
PRODUCT_BUNDLE_IDENTIFIER=com.mafty.DukeX
DEVICE_UDID=00008140-000825E12E68801C
```

Do not assume those values work on another machine or Apple account.

## Launching From Dev Tools

Normal manual test flow:

1. Open the app on the iPhone.
2. Let StikDebug auto-enable JIT if enabled in Settings.
3. Tap a game in the Games tab.

Launch selected game through `devicectl`:

```sh
xcrun devicectl device process launch \
  --device <DEVICE_UDID> \
  --terminate-existing \
  --environment-variables '{"XEMU_IOS_AUTO_LAUNCH_GAME":"1"}' \
  <BUNDLE_ID>
```

Pull latest log:

```sh
xcrun devicectl device copy from \
  --device <DEVICE_UDID> \
  --domain-type appDataContainer \
  --domain-identifier <BUNDLE_ID> \
  --source Documents/XemuLogs/latest.log \
  --destination /tmp/xemu-ios-latest.log \
  --timeout 60
```

## Config Generation

Default generated config is written to `Documents/xemu-ios.toml` by
`XemuLaunchPlan.make`.

Important default settings:

```toml
[display]
renderer = "VULKAN"

[display.ui]
show_menubar = false
show_notifications = true
hide_cursor = true

[perf]
cache_shaders = true

[input]
auto_bind = true
background_input_capture = true

[net]
enable = true
backend = "nat"

[[net.nat.forward_ports]]
host = 3074
guest = 3074
protocol = "udp"

[sys]
mem_limit = "64"
avpack = "hdtv"
```

The Swift launcher also sets:

```sh
XEMU_IOS_NAT_DIRECT_DNS=46.101.64.175
```

Per-game custom configs:

- Gear icon next to a game title imports/replaces a TOML file.
- The file is copied to `Documents/GameConfigs/config-<stable-id>.toml`.
- If present, that full file is used as `-config_path`.
- If absent, the generated default config is used.

Because custom configs are full replacements, they must include the system file
paths and DVD path themselves. A future improvement should support override
snippets merged over the generated default config.

## Key Source Files

Swift shell:

- `ios/XemuIOS/XemuIOS/ContentView.swift`
- `ios/XemuIOS/XemuIOS/EmulatorFileStore.swift`
- `ios/XemuIOS/XemuIOS/EmulatorCoreRuntime.swift`
- `ios/XemuIOS/XemuIOS/XemuLaunchPlan.swift`
- `ios/XemuIOS/XemuIOS/XemuIOSApp.swift`

iOS bridge and build:

- `ios/xemu-ios-main.c`
- `ios/xemu-ios-core.c`
- `ios/scripts/build-core-ios.sh`
- `ios/scripts/embed-core-ios.sh`
- `ios/scripts/run-device-ios.sh`

JIT:

- `tcg/ios-jit.c`
- `include/tcg/ios-jit.h`
- TCG integration is spread across modified `tcg/` and `accel/tcg/` files.

Presentation/rendering:

- `ui/xemu.c`
- `hw/xbox/nv2a/pgraph/vk/renderer.c`
- `hw/xbox/nv2a/pgraph/vk/surface.c`
- `hw/xbox/nv2a/pgraph/vk/shaders.c`
- `hw/xbox/nv2a/pgraph/glsl/psh.c`
- `hw/xbox/nv2a/pgraph/glsl/psh.h`

Networking:

- `ui/xemu-net.c`
- `net/slirp.c`
- `XEMU_IOS_NAT_DIRECT_DNS` support was used for Insignia DNS.

Input:

- `ui/xemu-input.c`
- `GameControllerBootstrap` in `EmulatorCoreRuntime.swift`.

## Important Warning

There is an unfinished experimental field in:

```c
hw/xbox/nv2a/pgraph/glsl/psh.h
```

Specifically:

```c
bool use_host_depth_for_perspective;
```

This was started for a shader/depth experiment and was not completed. It is not
believed to be active in the currently installed app because the latest iPhone
build only rebuilt the Swift wrapper around the existing core dylib. Before a
core rebuild, either finish the experiment or remove that field.

## Current Main Technical Blocker

The largest performance bottleneck is presentation, not JIT.

Current state:

- Vulkan renders through Xemu/NV2A path.
- On iOS, `HAVE_EXTERNAL_MEMORY` is disabled.
- The app falls back to downloading rendered surfaces to CPU memory and uploading
  them for OpenGL ES presentation.
- Logs show `nv2a_tex=0` and high present/download wait costs.

Likely direction:

- Replace the CPU readback presenter with a direct iOS Metal/Vulkan presenter.
- Use a `CAMetalLayer` path through MoltenVK or a Metal presenter.
- XeniOS was referenced only as a design clue for iOS presentation architecture,
  not as code to copy wholesale.

Known XeniOS reference files from prior research:

- `src/xenia/ui/surface_ios.mm`
- `src/xenia/ui/window_ios.mm`
- `src/xenia/ui/metal/metal_presenter.mm`
- `src/xenia/ui/vulkan/vulkan_presenter.cc`

## Current Rendering Issue

MoltenVK/iOS does not provide the Vulkan geometry shader path Xemu expects.
The code logs a warning similar to:

```text
Warning: Vulkan geometry shaders are unavailable; using CPU primitive expansion without host depth interpolation
```

Host-depth interpolation was tested:

- `XEMU_IOS_HOST_DEPTH_INTERPOLATION=1`: reduced one artifact but broke Halo 2
  menu tint and HUD/radar/shield.
- `XEMU_IOS_HOST_DEPTH_INTERPOLATION=0`: current default; restores correct tint
  and HUD/radar/shield, but gameplay artifact remains.

## Backups and Milestones

Local milestone folders on Michael's Desktop:

- `Xemu-iOS-ui-before-library-tabs-20260512-212500`
- `Xemu-iOS-halo2-visual-milestone-build-20260512-200308`
- `Xemu-iOS-halo2-hud-correct-depthoff-20260512-201000`
- `Xemu-iOS-halo2-longrun-candidate-20260512-192750`
- `Xemu-iOS-known-good-insignia-20260512-172250`
- `Xemu-iOS-known-good-20260512-163028`
- `Xemu-iOS-halo2-cutscene-milestone-20260512-180910`

These are local safety snapshots, not part of the source tree.

## Suggested Next Steps

For a developer reviewing this project:

1. Build the existing Xcode wrapper without rebuilding the core to verify local
   signing and install first.
2. Pull `Documents/XemuLogs/latest.log` from a device run and confirm JIT lines.
3. Inspect the presenter path and remove the CPU readback bottleneck.
4. Revisit the geometry-shader fallback/depth artifact only after the presenter
   bottleneck is understood.
5. Add a native in-game overlay with an Exit Game button using a clean core
   shutdown hook.
6. Change per-game configs from full replacements to mergeable override snippets.
7. Add proper controller mapping/status UX once rendering performance stabilizes.

## Legal / Data Boundary

Do not bundle or redistribute:

- Xbox BIOS / flash ROM
- MCPX
- EEPROM
- HDD image
- Game ISOs/XISOs

The app is designed for the user to place those files into the iOS app
Documents folders themselves.
