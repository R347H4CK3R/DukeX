# DukeX iOS Shell

This folder contains the native iOS application layer for DukeX. It owns file
placement, launch configuration, JIT handoff, the SwiftUI interface, and the
in-process bridge to the embedded xemu core dylib.

Runtime folders created in app Documents:

- `BIOS`: flash BIOS `.bin`, MCPX boot ROM, EEPROM, and HDD image.
- `ROMs`: XISO game files, detected as `.iso` or `.xiso`.
- `Covers`: user-selected game cover art.
- `GameConfigs`: optional per-game xemu configuration overrides.
- `ShaderCaches`: per-title renderer cache storage.

The shell writes `Documents/xemu-ios.toml` with core settings:

- `sys.files.bootrom_path` for the 512-byte MCPX file.
- `sys.files.flashrom_path` for the flash BIOS.
- `sys.files.hdd_path` for the HDD image.
- `sys.files.dvd_path` for the selected game.

Universal.js integration is represented by `XEMU_IOS_UNIVERSAL_JIT=1`. The TCG
hook in `tcg/ios-jit.c` uses this to decide whether to issue the iOS 26
`brk #0xf00d` prepare-region request expected by StikDebug's Universal.js.

Core build note: QEMU/xemu `configure` rejects source and build paths containing
spaces or colons. Core configure/build checks need an actual no-space checkout
or copy, not a symlink, because the Python venv step resolves the real path.

From that no-space workspace, run the first iPhoneOS arm64 build pass with:

```sh
ios/scripts/build-core-ios.sh
```

The script targets an iOS `26.3` deployment baseline.

That build produces:

- `build-ios-arm64/qemu-system-i386`: a standalone diagnostic executable.
- `build-ios-arm64/libxemu-ios-core.dylib`: the in-process core loaded by the
  Swift app.

The Xcode target runs `ios/scripts/embed-core-ios.sh`, then copies
`libxemu-ios-core.dylib`, `libslirp.0.dylib`, and the local MoltenVK framework
into `DukeX.app/Frameworks`. The Swift launch path uses `dlopen`, resolves
`xemu_ios_main`, and passes `-config_path` with the generated
`Documents/xemu-ios.toml`.

For a connected iPhone device pass:

```sh
ios/scripts/run-device-ios.sh
```

The script auto-detects the first connected iPhone/iPad and the first local
Apple Development signing identity. It builds the core, signs/builds the app,
installs it with `devicectl`, then launches the shell. If Xcode reports
`No Account for Team` or `No profiles`, add the Apple ID in Xcode Settings >
Accounts and retry without rebuilding the core:

```sh
XEMU_IOS_SKIP_CORE_BUILD=1 ios/scripts/run-device-ios.sh
```

Useful overrides:

- `XEMU_IOS_DEVELOPMENT_TEAM`: Apple development team ID.
- `XEMU_IOS_BUNDLE_ID`: unique bundle identifier.
- `XEMU_IOS_DEVICE_ID`: target device UDID.
- `XEMU_IOS_LAUNCH=0`: install but do not launch.
