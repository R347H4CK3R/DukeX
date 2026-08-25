#!/usr/bin/env bash
set -euo pipefail

if [[ "${PLATFORM_NAME:-}" == iphonesimulator* ]]; then
  echo "Skipping iOS core embed for simulator builds."
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SOURCE_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd -P)"
CORE_DYLIB="${XEMU_IOS_CORE_DYLIB:-${SOURCE_DIR}/build-ios-arm64/libxemu-ios-core.dylib}"
MOLTENVK_FRAMEWORK="${MOLTENVK_FRAMEWORK:-}"

if [[ ! -f "${CORE_DYLIB}" ]]; then
  cat >&2 <<EOF
Missing iOS core dylib:
  ${CORE_DYLIB}

Build it first from the no-space workspace:
  ios/scripts/build-core-ios.sh
EOF
  exit 1
fi

FRAMEWORKS_DIR="${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}"
DESTINATION="${FRAMEWORKS_DIR}/libxemu-ios-core.dylib"
MOLTENVK_DESTINATION="${FRAMEWORKS_DIR}/MoltenVK.framework"

mkdir -p "${FRAMEWORKS_DIR}"
cp "${CORE_DYLIB}" "${DESTINATION}"
chmod 755 "${DESTINATION}"

# libslirp is supplied by vcpkg as a static library and is linked into the
# iOS core during build-core-ios.sh. Do not require or embed a separate
# libslirp.0.dylib here.

if [[ -z "${MOLTENVK_FRAMEWORK}" || ! -d "${MOLTENVK_FRAMEWORK}" ]]; then
  cat >&2 <<EOF
Missing MoltenVK iOS framework:
  ${MOLTENVK_FRAMEWORK:-<unset>}

Set MOLTENVK_FRAMEWORK to the ios-arm64 MoltenVK.framework.
EOF
  exit 1
fi

rm -rf "${MOLTENVK_DESTINATION}"
/usr/bin/ditto "${MOLTENVK_FRAMEWORK}" "${MOLTENVK_DESTINATION}"
chmod 755 "${MOLTENVK_DESTINATION}/MoltenVK"

if [[ "${CODE_SIGNING_ALLOWED:-YES}" != "NO" &&
      -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" &&
      "${EXPANDED_CODE_SIGN_IDENTITY}" != "-" ]]; then
  /usr/bin/codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY}" \
    --timestamp=none "${DESTINATION}"
  /usr/bin/codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY}" \
    --timestamp=none "${MOLTENVK_DESTINATION}"
fi
