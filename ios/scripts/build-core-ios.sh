#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SOURCE_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd -P)"

# The workflow's coroutine patch also installs broad diagnostics. Normalize
# those diagnostics and harden GLib context ownership immediately before the
# core is configured/compiled so the generated source is what gets linked.
python3 "${SOURCE_DIR}/.github/scripts/apply_ios_runtime_stability_fix.py"

BUILD_DIR="${XEMU_IOS_BUILD_DIR:-${SOURCE_DIR}/build-ios-arm64}"
IOS_DEPLOYMENT_TARGET="${IOS_DEPLOYMENT_TARGET:-16.0}"
SDK_NAME="${SDK_NAME:-iphoneos}"
VCPKG_PREFIX="${XEMU_IOS_VCPKG_PREFIX:-${VCPKG_ROOT:-}/installed/arm64-ios}"
MOLTENVK_ROOT="${MOLTENVK_ROOT:-}"
MOLTENVK_FRAMEWORK="${MOLTENVK_FRAMEWORK:-}"
# iPhoneOS must never use QEMU's SIGUSR2/sigaltstack coroutine bootstrap.
# LiveContainer/StikDebug return ENOTSUP from pthread_kill for that path.
# Force ucontext instead of allowing a workflow/environment override.
XEMU_IOS_COROUTINE_BACKEND="ucontext"

for path in "${SOURCE_DIR}" "${BUILD_DIR}"; do
  case "${path}" in
    *[[:space:]:]*)
      printf 'xemu configure rejects spaces or colons in source/build paths.\n' >&2
      printf 'Source: %s\nBuild:  %s\n' "${SOURCE_DIR}" "${BUILD_DIR}" >&2
      exit 1
      ;;
  esac
done

if [[ -z "${VCPKG_PREFIX}" || ! -d "${VCPKG_PREFIX}" ]]; then
  printf 'Missing arm64-ios vcpkg prefix. Set XEMU_IOS_VCPKG_PREFIX or VCPKG_ROOT.\n' >&2
  exit 1
fi

if [[ -z "${MOLTENVK_ROOT}" || ! -f "${MOLTENVK_ROOT}/include/vulkan/vulkan.h" ]]; then
  printf 'Missing MoltenVK iOS headers. Set MOLTENVK_ROOT.\n' >&2
  printf 'Expected: %s\n' "${MOLTENVK_ROOT:-<unset>}/include/vulkan/vulkan.h" >&2
  exit 1
fi

if [[ -z "${MOLTENVK_FRAMEWORK}" || ! -f "${MOLTENVK_FRAMEWORK}/MoltenVK" ]]; then
  printf 'Missing MoltenVK iOS framework. Set MOLTENVK_FRAMEWORK.\n' >&2
  printf 'Expected: %s\n' "${MOLTENVK_FRAMEWORK:-<unset>}/MoltenVK" >&2
  exit 1
fi

SDKROOT="$(xcrun --sdk "${SDK_NAME}" --show-sdk-path)"
CLANG="$(xcrun --sdk "${SDK_NAME}" --find clang)"
CLANGXX="$(xcrun --sdk "${SDK_NAME}" --find clang++)"
AR="$(xcrun --sdk "${SDK_NAME}" --find ar)"
RANLIB="$(xcrun --sdk "${SDK_NAME}" --find ranlib)"
NM="$(xcrun --sdk "${SDK_NAME}" --find nm)"
STRIP="$(xcrun --sdk "${SDK_NAME}" --find strip)"
PKG_CONFIG="${PKG_CONFIG:-pkg-config}"
CMAKE="${CMAKE:-$(command -v cmake)}"
TARGET="arm64-apple-ios${IOS_DEPLOYMENT_TARGET}"
MOLTENVK_FRAMEWORK_DIR="$(dirname "${MOLTENVK_FRAMEWORK}")"
COMMON_FLAGS=(
  "-target" "${TARGET}"
  "-isysroot" "${SDKROOT}"
  "-miphoneos-version-min=${IOS_DEPLOYMENT_TARGET}"
  "-I${MOLTENVK_ROOT}/include"
  "-include" "getopt.h"
  "-DVK_ENABLE_BETA_EXTENSIONS=1"
  "-DVK_USE_PLATFORM_METAL_EXT=1"
  "-DXBOX"
)
COMMON_LDFLAGS=(
  "${COMMON_FLAGS[@]}"
  "-framework" "CoreFoundation"
  "-F${MOLTENVK_FRAMEWORK_DIR}"
  "-Wl,-needed_framework,MoltenVK"
  "-Wl,-rpath,@loader_path/Frameworks"
)
EXTRA_CONFIGURE_ARGS=()
if [[ -n "${XEMU_IOS_CONFIGURE_ARGS:-}" ]]; then
  read -r -a EXTRA_CONFIGURE_ARGS <<< "${XEMU_IOS_CONFIGURE_ARGS}"
fi
read -r -a NINJA_TARGETS <<< "${XEMU_IOS_NINJA_TARGETS:-qemu-system-i386 libxemu-ios-core.dylib}"

VULKAN_PKG_CONFIG_DIR="${BUILD_DIR}/ios-pkgconfig"
mkdir -p "${VULKAN_PKG_CONFIG_DIR}"
cat > "${VULKAN_PKG_CONFIG_DIR}/vulkan.pc" <<EOF
prefix=${MOLTENVK_ROOT}
includedir=\${prefix}/include
frameworkdir=${MOLTENVK_FRAMEWORK_DIR}

Name: vulkan
Description: MoltenVK Vulkan implementation for iOS
Version: 1.3.0
Libs: -F\${frameworkdir} -Wl,-needed_framework,MoltenVK
Cflags: -I\${includedir} -DVK_ENABLE_BETA_EXTENSIONS=1 -DVK_USE_PLATFORM_METAL_EXT=1
EOF

export PKG_CONFIG_LIBDIR="${VULKAN_PKG_CONFIG_DIR}:${VCPKG_PREFIX}/lib/pkgconfig:${VCPKG_PREFIX}/debug/lib/pkgconfig"
export PKG_CONFIG_PATH="${PKG_CONFIG_LIBDIR}"
export PKG_CONFIG_SYSROOT_DIR="/"
export AR RANLIB NM STRIP PKG_CONFIG CMAKE

SYSTEM_PYTHON="$(command -v python3)"
HOST_PYTHON_VENV="${BUILD_DIR}/host-python-venv"
"${SYSTEM_PYTHON}" -m venv "${HOST_PYTHON_VENV}"
HOST_PYTHON="${HOST_PYTHON_VENV}/bin/python"
"${HOST_PYTHON}" -m pip install --disable-pip-version-check PyYAML
"${HOST_PYTHON}" -c 'import yaml; print("PyYAML ready:", yaml.__version__)'
export PATH="${HOST_PYTHON_VENV}/bin:${PATH}"
export PYTHON="${HOST_PYTHON}"
export PYTHON3="${HOST_PYTHON}"
printf 'Using host Python: %s\n' "${PYTHON}"
"${PYTHON}" -c 'import sys, yaml; print("Python:", sys.executable); print("PyYAML:", yaml.__version__)'

printf 'Using host CMake for Meson subprojects: %s\n' "${CMAKE}"
"${CMAKE}" --version
printf 'MoltenVK framework will be force-linked for iOS runtime loading: %s\n' "${MOLTENVK_FRAMEWORK}"
printf 'Embedding core rpath: @loader_path/Frameworks\n'
printf 'Using iOS coroutine backend: %s\n' "${XEMU_IOS_COROUTINE_BACKEND}"

# Keep eager priming disabled; normal coroutine creation remains available
# later through QEMU's regular code paths.
"${SYSTEM_PYTHON}" - "${SOURCE_DIR}/ui/xemu.c" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text(encoding="utf-8")
old = '''    if (!value || !*value) {
        return 640;
    }'''
new = '''    if (!value || !*value) {
        return 0;
    }'''
if old in s:
    s = s.replace(old, new, 1)
elif new not in s:
    raise SystemExit("Expected iOS coroutine prime default block not found")
old2 = '''    if (end == value || parsed > 4096) {
        return 640;
    }'''
new2 = '''    if (end == value || parsed > 4096) {
        return 0;
    }'''
if old2 in s:
    s = s.replace(old2, new2, 1)
elif new2 not in s:
    raise SystemExit("Expected iOS coroutine prime fallback block not found")
p.write_text(s, encoding="utf-8")
print("Disabled DukeX iOS coroutine pre-prime default for this build")
PY

grep -A14 -n "static unsigned int ios_coroutine_prime_count" "${SOURCE_DIR}/ui/xemu.c"

# Cached Meson/Ninja state can preserve the previously selected sigaltstack
# source even after --with-coroutine changes. An unstamped or mismatched build
# is reset, while preserving helper directories created above.
BACKEND_STAMP="${BUILD_DIR}/.dukex-ios-coroutine-backend"
CACHED_BACKEND=""
if [[ -f "${BACKEND_STAMP}" ]]; then
  CACHED_BACKEND="$(cat "${BACKEND_STAMP}" || true)"
fi
if [[ -d "${BUILD_DIR}" && "${CACHED_BACKEND}" != "${XEMU_IOS_COROUTINE_BACKEND}" ]]; then
  printf 'Coroutine backend cache mismatch (%s -> %s); resetting compiled core state.\n' \
    "${CACHED_BACKEND:-unstamped}" "${XEMU_IOS_COROUTINE_BACKEND}"
  find "${BUILD_DIR}" -mindepth 1 -maxdepth 1 \
    ! -name 'host-python-venv' ! -name 'ios-pkgconfig' \
    -exec rm -rf {} +
fi
mkdir -p "${BUILD_DIR}"
printf '%s\n' "${XEMU_IOS_COROUTINE_BACKEND}" > "${BACKEND_STAMP}"
cd "${BUILD_DIR}"

"${SOURCE_DIR}/configure" \
  --cross-prefix= \
  --cc="${CLANG}" \
  --cxx="${CLANGXX}" \
  --objcc="${CLANG}" \
  --host-cc=cc \
  --target-list=i386-softmmu \
  --enable-system \
  --enable-tcg \
  --disable-tcg-interpreter \
  --disable-rust \
  --disable-docs \
  --disable-tools \
  --disable-guest-agent \
  --disable-plugins \
  --disable-bsd-user \
  --disable-linux-user \
  --disable-werror \
  --enable-slirp \
  --disable-slirp-smbd \
  --disable-capstone \
  --disable-coreaudio \
  --disable-sdl-image \
  --enable-fdt=internal \
  --enable-sdl \
  --enable-opengl \
  --enable-pixman \
  --audio-drv-list= \
  --with-coroutine="ucontext" \
  --extra-cflags="${COMMON_FLAGS[*]}" \
  --extra-cxxflags="${COMMON_FLAGS[*]}" \
  --extra-objcflags="${COMMON_FLAGS[*]}" \
  --extra-ldflags="${COMMON_LDFLAGS[*]}" \
  "${EXTRA_CONFIGURE_ARGS[@]+"${EXTRA_CONFIGURE_ARGS[@]}"}"

ninja -C "${BUILD_DIR}" "${NINJA_TARGETS[@]}" "$@"

# Refuse to package a core that accidentally contains the iOS sigaltstack
# bootstrap again. The ucontext diagnostic marker is injected by the workflow
# patch and proves the intended backend was linked into the dylib. Avoid
# strings|grep pipelines here because pipefail can turn grep -q's early exit
# into a false negative when strings receives SIGPIPE.
CORE_DYLIB="${BUILD_DIR}/libxemu-ios-core.dylib"
if [[ -f "${CORE_DYLIB}" ]]; then
  CORE_STRINGS="${BUILD_DIR}/.dukex-core-strings.txt"
  strings "${CORE_DYLIB}" > "${CORE_STRINGS}"
  if ! grep -q 'xemu_ios: ucontext coroutine new: enter' "${CORE_STRINGS}"; then
    printf 'ERROR: built iOS core does not contain the ucontext coroutine backend marker.\n' >&2
    rm -f "${CORE_STRINGS}"
    exit 1
  fi
  if grep -q 'coroutine sigaltstack pthread_kill failed' "${CORE_STRINGS}"; then
    printf 'ERROR: sigaltstack coroutine bootstrap leaked into the iOS core.\n' >&2
    rm -f "${CORE_STRINGS}"
    exit 1
  fi
  rm -f "${CORE_STRINGS}"
  printf 'Verified iOS core coroutine backend: ucontext only.\n'
fi
