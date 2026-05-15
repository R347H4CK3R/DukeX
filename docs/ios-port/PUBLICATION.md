# Public Release Checklist

Use this checklist before changing the repository from private to public or
before publishing a tagged tester build.

## Repository Contents

- Do not commit Xbox BIOS, MCPX, EEPROM, HDD, XISO, save data, cover art from
  commercial sources, provisioning profiles, certificates, IPAs, crash logs, or
  device logs.
- Keep Apple signing local. The checked-in Xcode project should leave
  `DEVELOPMENT_TEAM` blank and use a generic bundle identifier.
- Keep build products under ignored directories such as `build-ios-*` or
  Xcode DerivedData.
- Prefer public-facing docs under `docs/ios-port/`; avoid committing private
  handoff notes or tester-specific findings.

## Licensing And Attribution

- DukeX inherits the xemu/QEMU licensing model. Keep `LICENSE`, `COPYING`, and
  existing source headers intact.
- MoltenVK is an external runtime dependency and is not vendored here.
- If code is imported from another project, add the source, license, and commit
  reference in the file header or a dedicated attribution note before release.
- If a change is only inspired by another project, document the design idea in
  prose without copying source text.

## Runtime Requirements

- iPhoneOS arm64 device build.
- iOS 26.3 deployment baseline in the Xcode project and core build scripts.
- StikDebug with Universal.js assigned to the app bundle identifier for JIT.
- A local MoltenVK package:
  - `MOLTENVK_ROOT` for headers during core build.
  - `MOLTENVK_FRAMEWORK` for app embedding.
- An arm64-iOS vcpkg prefix for dependencies used by the embedded core.

## Privacy Scan

Before publishing, run a scan similar to:

```sh
rg -n "YOUR_NAME|YOUR_HANDLE|YOUR_EMAIL|YOUR_TEAM_ID|YOUR_DEVICE_ID|/Users/[^[:space:]]+" \
  ios docs/ios-port README.md .gitignore
```

The scan should not report committed iOS port files. Upstream QEMU/xemu files
may contain unrelated paths, names, or provenance text; review any matches
before editing upstream material.

## Validation

Run these checks before pushing a public-facing branch:

```sh
git diff --check

MOLTENVK_FRAMEWORK="<path-to-ios-arm64-MoltenVK.framework>" \
xcodebuild \
  -project ios/XemuIOS/XemuIOS.xcodeproj \
  -scheme XemuIOS \
  -configuration Release \
  -sdk iphoneos \
  -destination "generic/platform=iOS" \
  -derivedDataPath build-ios-xcode-public-verify \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  build
```

If packaging an unsigned tester IPA, strip or rebuild binaries so local build
paths are not visible in the payload, then scan the unpacked `Payload` before
sharing it.
