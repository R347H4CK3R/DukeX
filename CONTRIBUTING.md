# Contributing To DukeX

DukeX is a focused iOS fork of xemu. The repository keeps the upstream
QEMU/xemu layout intact, so contributions should make the boundary between
upstream code and DukeX-specific work clear.

## Scope

Use the issue templates for bug reports and title-specific compatibility notes.
For code changes, keep the patch narrow and describe the tested device, iOS
version, JIT path, and affected titles where relevant.

Primary DukeX areas:

| Path | Use |
| --- | --- |
| `ios/` | Swift app shell, assets, launch scripts, and iOS bridge code. |
| `docs/ios-port/` | Build, renderer, and release documentation for the iOS port. |
| `hw/xbox/nv2a/pgraph/vk/` | Vulkan renderer changes needed by the iOS/MoltenVK path. |
| `tcg/` | Runtime/JIT integration used by device builds. |

Avoid large cosmetic changes to inherited QEMU/xemu files. They make upstream
syncs harder and obscure the iOS-specific changes that need review.

## Local Artifacts

Do not commit system files, game images, signing assets, built IPAs, crash logs,
device logs, HDD images, save data, or tester-specific notes. Keep those in
ignored local directories.

Before opening a public-facing branch, run:

```sh
git diff --check
git status --short --untracked-files=all
git ls-files README.md CONTRIBUTING.md docs/ios-port ios .github | \
  rg "(\\.ipa|\\.xcarchive|\\.dSYM|\\.p12|\\.cer|\\.mobileprovision|\\.provisionprofile|\\.qcow2|device-artifacts|build-artifacts)"
```

The final command should not print committed project files.

## Build Check

Unsigned device build check:

```sh
MOLTENVK_FRAMEWORK="<path-to-ios-arm64-MoltenVK.framework>" \
xcodebuild \
  -project ios/DukeX/DukeX.xcodeproj \
  -scheme DukeX \
  -configuration Release \
  -sdk iphoneos \
  -destination "generic/platform=iOS" \
  -derivedDataPath build-ios-xcode-public-verify \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  build
```

Signed installs should be produced locally with a private team ID and
provisioning profile.
