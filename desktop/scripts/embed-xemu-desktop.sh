#!/bin/sh
set -eu

if [ "${EFFECTIVE_PLATFORM_NAME:-}" != "-maccatalyst" ]; then
    echo "Skipping desktop xemu embed for ${EFFECTIVE_PLATFORM_NAME:-unknown platform}"
    exit 0
fi

source_app="${XEMU_DESKTOP_APP_SOURCE:-${SRCROOT}/Embedded/Xemu/DukeX.app}"
if [ ! -d "${source_app}" ]; then
    echo "error: desktop xemu app not found at ${source_app}" >&2
    exit 1
fi

app_bundle="${TARGET_BUILD_DIR}/${WRAPPER_NAME}"
if [ -d "${app_bundle}/Contents" ]; then
    embed_root="${app_bundle}/Contents/Library/Xemu"
else
    embed_root="${app_bundle}/Library/Xemu"
fi

destination_app="${embed_root}/DukeX.app"
mkdir -p "${embed_root}"
rm -rf "${embed_root}/xemu.app"
rm -rf "${destination_app}"
ditto "${source_app}" "${destination_app}"

info_plist="${destination_app}/Contents/Info.plist"
if [ -f "${info_plist}" ]; then
    brand_name="DukeX"
    plutil -replace LSUIElement -bool YES "${info_plist}"
    plutil -replace CFBundleExecutable -string "${brand_name}" "${info_plist}"
    plutil -replace CFBundleDisplayName -string "${brand_name}" "${info_plist}"
    plutil -replace CFBundleName -string "${brand_name}" "${info_plist}"
    plutil -replace CFBundleGetInfoString -string "${brand_name}" "${info_plist}"
    plutil -replace CFBundleIdentifier -string "com.maftymanicemu.dukex.game" "${info_plist}"
    plutil -replace CFBundleSignature -string "DUKX" "${info_plist}"

    icon_source="${DUKEX_DESKTOP_ICON_SOURCE:-${SRCROOT}/DukeX/Assets.xcassets/AppIconGC.appiconset/dukex_gc_1024.png}"
    resources_dir="${destination_app}/Contents/Resources"
    iconset_dir="${DERIVED_FILE_DIR:-${TMPDIR:-/tmp}}/DukeXEmbeddedXemu.iconset"
    if [ -f "${icon_source}" ] && command -v sips >/dev/null && command -v iconutil >/dev/null; then
        rm -rf "${iconset_dir}"
        mkdir -p "${iconset_dir}" "${resources_dir}"
        sips -z 16 16 "${icon_source}" --out "${iconset_dir}/icon_16x16.png" >/dev/null
        sips -z 32 32 "${icon_source}" --out "${iconset_dir}/icon_16x16@2x.png" >/dev/null
        sips -z 32 32 "${icon_source}" --out "${iconset_dir}/icon_32x32.png" >/dev/null
        sips -z 64 64 "${icon_source}" --out "${iconset_dir}/icon_32x32@2x.png" >/dev/null
        sips -z 128 128 "${icon_source}" --out "${iconset_dir}/icon_128x128.png" >/dev/null
        sips -z 256 256 "${icon_source}" --out "${iconset_dir}/icon_128x128@2x.png" >/dev/null
        sips -z 256 256 "${icon_source}" --out "${iconset_dir}/icon_256x256.png" >/dev/null
        sips -z 512 512 "${icon_source}" --out "${iconset_dir}/icon_256x256@2x.png" >/dev/null
        sips -z 512 512 "${icon_source}" --out "${iconset_dir}/icon_512x512.png" >/dev/null
        sips -z 1024 1024 "${icon_source}" --out "${iconset_dir}/icon_512x512@2x.png" >/dev/null
        iconutil --convert icns --output "${resources_dir}/DukeX.icns" "${iconset_dir}"
        plutil -replace CFBundleIconFile -string "DukeX" "${info_plist}"
    else
        echo "warning: DukeX sidecar icon could not be generated from ${icon_source}" >&2
    fi
fi

original_executable="${destination_app}/Contents/MacOS/xemu"
xemu_executable="${destination_app}/Contents/MacOS/DukeX"
if [ -x "${original_executable}" ]; then
    mv "${original_executable}" "${xemu_executable}"
fi

if [ ! -x "${xemu_executable}" ]; then
    echo "error: embedded xemu executable is missing or not executable at ${xemu_executable}" >&2
    exit 1
fi

if command -v codesign >/dev/null; then
    codesign --force --deep --sign - "${destination_app}" >/dev/null 2>&1 || true
fi

echo "Embedded desktop xemu at ${destination_app}"
