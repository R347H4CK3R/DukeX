# DukeX Private Review Build

This branch represents the current DukeX iOS test build after reverting the
MeloNX-style geometry shader experiment back to the pre-GS baseline.

## Current Build Identity

- App display name: `DukeX`
- Bundle identifier: `com.mafty.DukeXGC`
- iOS deployment target: `26.3`
- Test device used locally: iPhone 16 Pro on iOS 26.3.1
- JIT flow: StikDebug with Universal.js assigned to this bundle ID
- Presenter path: Vulkan through MoltenVK/CAMetalLayer

The current build intentionally keeps only the newer icon/bundle identity from
the later DukeX test builds. Rendering code is restored to the pre-GS state.

## What Is Not Included

Do not commit or redistribute user-supplied runtime files:

- Xbox BIOS/flash BIOS
- MCPX ROM
- EEPROM
- HDD image
- XISO/game files
- Apple signing certificates, `.p12`, provisioning profiles, or built `.ipa`
  files

The app expects user files in the app Documents container:

- `BIOS/`
- `ROMs/`
- `Covers/`

## Local Dependencies

This project is built on macOS with Xcode and a local iOS dependency toolchain.

Required locally:

- Xcode with iPhoneOS SDK
- `pkg-config`
- `cmake`
- `ninja`
- `vcpkg` arm64 iOS dependencies
- MoltenVK iOS SDK

The current local defaults used by `ios/scripts/build-core-ios.sh` are:

```sh
MOLTENVK_ROOT=/Users/michaelweekley/.local/tools/moltenvk-ios/MoltenVK
VCPKG_ROOT=<path containing installed/arm64-ios>
IOS_DEPLOYMENT_TARGET=26.3
```

Override them when needed:

```sh
export VCPKG_ROOT=/path/to/vcpkg
export MOLTENVK_ROOT=/path/to/MoltenVK
export IOS_DEPLOYMENT_TARGET=26.3
```

## Build Core

From the repository root:

```sh
ios/scripts/build-core-ios.sh
```

This produces the iOS core artifacts in `build-ios-arm64/`, including:

- `qemu-system-i386`
- `libxemu-ios-core.dylib`

## Build iOS App

For the current private review build:

```sh
xcodebuild \
  -project ios/XemuIOS/XemuIOS.xcodeproj \
  -scheme XemuIOS \
  -configuration Debug \
  -destination "generic/platform=iOS" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=5Q9UYCH8TM \
  build
```

For direct local device build, replace the destination with the connected device:

```sh
xcodebuild \
  -project ios/XemuIOS/XemuIOS.xcodeproj \
  -scheme XemuIOS \
  -configuration Debug \
  -destination "id=<DEVICE_UDID>" \
  -derivedDataPath build-ios-xcode-dukex-pregs-device \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=5Q9UYCH8TM \
  build
```

## Install To Device

```sh
xcrun devicectl device install app \
  --device <DEVICE_UDID> \
  build-ios-xcode-dukex-pregs-device/Build/Products/Debug-iphoneos/DukeX.app
```

## Runtime Notes

- StikDebug must be configured for `com.mafty.DukeXGC`.
- Universal.js JIT must be enabled for iOS 26 or later.
- If JIT is active, logs should include:

```text
xemu-ios: Universal.js JIT probe: result=42
```

- MoltenVK/Metal presenter logs should include:

```text
xemu_ios: using CAMetalLayer Vulkan swapchain presenter
[mvk-info] Created VkDevice to run on GPU Apple A18 Pro GPU
```

## Current Verification

The current local state was verified by:

```sh
ios/scripts/build-core-ios.sh
xcodebuild -project ios/XemuIOS/XemuIOS.xcodeproj \
  -scheme XemuIOS \
  -configuration Debug \
  -destination "id=00008140-000825E12E68801C" \
  -derivedDataPath build-ios-xcode-dukex-pregs-device \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=5Q9UYCH8TM \
  build
xcrun devicectl device install app \
  --device 00008140-000825E12E68801C \
  build-ios-xcode-dukex-pregs-device/Build/Products/Debug-iphoneos/DukeX.app
```

## Reviewer Focus

This snapshot is meant for review of the iOS port baseline before more shader
experiments. The known next areas are:

- MoltenVK/CAMetalLayer presenter correctness
- NV2A Vulkan renderer behavior on iOS
- shader/pipeline caching strategy
- Halo 2 HUD/radar/floor artifact investigation
- gameplay performance after the pre-GS revert
