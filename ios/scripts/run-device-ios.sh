#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SOURCE_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd -P)"
PROJECT="${SOURCE_DIR}/ios/DukeX/DukeX.xcodeproj"
SCHEME="${XEMU_IOS_SCHEME:-DukeX}"
BUNDLE_ID="${XEMU_IOS_BUNDLE_ID:-com.mafty.dukex}"
DERIVED_DATA="${XEMU_IOS_DERIVED_DATA:-${SOURCE_DIR}/build-ios-xcode}"
CONFIGURATION="${XEMU_IOS_CONFIGURATION:-Debug}"

if [[ -n "${XEMU_IOS_DISPLAY_NAME:-}" ]]; then
  DISPLAY_NAME="${XEMU_IOS_DISPLAY_NAME}"
elif [[ "${BUNDLE_ID}" == "com.mafty.dukex" || "${BUNDLE_ID}" == "com.mafty.DukeX" ]]; then
  DISPLAY_NAME="DukeX"
else
  DISPLAY_NAME="DukeX"
fi

detect_device_id() {
  xcrun xctrace list devices 2>/dev/null |
    awk '
      /^== Devices ==/ { in_devices = 1; next }
      /^== Simulators ==/ { in_devices = 0 }
      in_devices && /(iPhone|iPad)/ {
        if (match($0, /\(([0-9A-Fa-f-]+)\)$/)) {
          id = substr($0, RSTART + 1, RLENGTH - 2)
          print id
          exit
        }
      }
    '
}

detect_team_id() {
  local subject

  subject="$(
    security find-certificate -c "Apple Development" -p 2>/dev/null |
      openssl x509 -noout -subject -nameopt RFC2253 2>/dev/null ||
      true
  )"

  if [[ "${subject}" =~ OU=([A-Z0-9]{10}) ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi

  security find-identity -v -p codesigning 2>/dev/null |
    sed -n 's/.*"Developer ID Application: .* (\([A-Z0-9][A-Z0-9]*\))".*/\1/p' |
    head -1
}

DEVICE_ID="${XEMU_IOS_DEVICE_ID:-$(detect_device_id)}"
DEVELOPMENT_TEAM="${XEMU_IOS_DEVELOPMENT_TEAM:-$(detect_team_id)}"

if [[ -z "${DEVICE_ID}" ]]; then
  printf 'No connected iPhone or iPad was detected. Set XEMU_IOS_DEVICE_ID.\n' >&2
  exit 1
fi

if [[ -z "${DEVELOPMENT_TEAM}" ]]; then
  printf 'No Apple Development team ID was detected. Set XEMU_IOS_DEVELOPMENT_TEAM.\n' >&2
  exit 1
fi

if [[ "${XEMU_IOS_SKIP_CORE_BUILD:-0}" != "1" ]]; then
  "${SCRIPT_DIR}/build-core-ios.sh"
fi

if ! xcodebuild \
    -project "${PROJECT}" \
    -scheme "${SCHEME}" \
    -configuration "${CONFIGURATION}" \
    -destination "id=${DEVICE_ID}" \
    -derivedDataPath "${DERIVED_DATA}" \
    -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM}" \
    PRODUCT_BUNDLE_IDENTIFIER="${BUNDLE_ID}" \
    XEMU_IOS_DISPLAY_NAME="${DISPLAY_NAME}" \
    build; then
  cat >&2 <<EOF

Device build failed before install.

If Xcode reports "No Account for Team" or "No profiles", open Xcode Settings >
Accounts, add the Apple ID that owns team ${DEVELOPMENT_TEAM}, then retry:

  XEMU_IOS_SKIP_CORE_BUILD=1 ios/scripts/run-device-ios.sh

Override values if needed:
  XEMU_IOS_DEVELOPMENT_TEAM=<team-id>
  XEMU_IOS_BUNDLE_ID=<unique.bundle.id>
  XEMU_IOS_DEVICE_ID=<device-udid>
EOF
  exit 65
fi

APP_PATH="${DERIVED_DATA}/Build/Products/${CONFIGURATION}-iphoneos/${SCHEME}.app"

xcrun devicectl device install app --device "${DEVICE_ID}" "${APP_PATH}"

if [[ "${XEMU_IOS_LAUNCH:-1}" == "1" ]]; then
  launch_args=(device process launch --device "${DEVICE_ID}" --terminate-existing)
  if [[ "${XEMU_IOS_CONSOLE:-0}" == "1" ]]; then
    launch_args+=(--console)
  fi
  launch_args+=("${BUNDLE_ID}")
  xcrun devicectl "${launch_args[@]}"
fi
