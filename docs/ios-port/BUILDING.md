# Building DukeX for iOS

Use a checkout path without spaces or colons. QEMU/xemu configure resolves the
real path during setup, so a symlink from a clean path is not sufficient.

## Core

Build the embedded iOS core first:

```sh
export VCPKG_ROOT="<path-to-vcpkg-root>"
export MOLTENVK_ROOT="<path-to-MoltenVK-package>"
ios/scripts/build-core-ios.sh
```

Alternatively, set `XEMU_IOS_VCPKG_PREFIX` directly to an existing `arm64-ios`
vcpkg prefix.

Expected output:

- `build-ios-arm64/qemu-system-i386`
- `build-ios-arm64/libxemu-ios-core.dylib`

## App

Build and install through Xcode or `xcodebuild`. Typical command-line build:

```sh
xcodebuild \
  -project ios/DukeX/DukeX.xcodeproj \
  -scheme DukeX \
  -configuration Release \
  -destination "generic/platform=iOS" \
  DEVELOPMENT_TEAM="<APPLE_TEAM_ID>" \
  build
```

The checked-in Xcode project intentionally leaves `DEVELOPMENT_TEAM` blank.
Set it locally in Xcode or pass `DEVELOPMENT_TEAM=<APPLE_TEAM_ID>` on the
command line when building signed device installs.

Useful environment overrides:

- `XEMU_IOS_DEVELOPMENT_TEAM`: Apple development team ID.
- `XEMU_IOS_BUNDLE_ID`: bundle identifier.
- `XEMU_IOS_DEVICE_ID`: target device UDID.
- `XEMU_IOS_LAUNCH=0`: install but do not launch.
- `XEMU_IOS_SKIP_CORE_BUILD=1`: reuse an existing core build.

The app target runs `ios/scripts/embed-core-ios.sh`, which copies
`build-ios-arm64/libxemu-ios-core.dylib` into the app bundle.

Set `MOLTENVK_FRAMEWORK` to the `ios-arm64/MoltenVK.framework` path from your
local MoltenVK package before building the app target.

## Local Files Not Committed

Do not commit signing certificates, provisioning profiles, built IPAs, crash
logs, device logs, copied HDD images, or local Xcode build products.
