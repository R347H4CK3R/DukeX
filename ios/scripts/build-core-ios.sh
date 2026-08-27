#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SOURCE_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd -P)"
BUILD_DIR="${XEMU_IOS_BUILD_DIR:-${SOURCE_DIR}/build-ios-arm64}"
IOS_DEPLOYMENT_TARGET="${IOS_DEPLOYMENT_TARGET:-16.0}"
SDK_NAME="${SDK_NAME:-iphoneos}"
VCPKG_PREFIX="${XEMU_IOS_VCPKG_PREFIX:-${VCPKG_ROOT:-}/installed/arm64-ios}"
MOLTENVK_ROOT="${MOLTENVK_ROOT:-}"
MOLTENVK_FRAMEWORK="${MOLTENVK_FRAMEWORK:-}"
# Avoid QEMU's SIGUSR2/sigaltstack bootstrap on iOS. Under LiveContainer/
# StikDebug the first coroutine can hang before the trampoline completes.
# ucontext does not depend on process-wide signal delivery and is therefore
# the safer backend for the embedded iOS core.
XEMU_IOS_COROUTINE_BACKEND="${XEMU_IOS_COROUTINE_BACKEND:-ucontext}"

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

mkdir -p "${BUILD_DIR}"
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
  --with-coroutine="${XEMU_IOS_COROUTINE_BACKEND}" \
  --extra-cflags="${COMMON_FLAGS[*]}" \
  --extra-cxxflags="${COMMON_FLAGS[*]}" \
  --extra-objcflags="${COMMON_FLAGS[*]}" \
  --extra-ldflags="${COMMON_LDFLAGS[*]}" \
  "${EXTRA_CONFIGURE_ARGS[@]+"${EXTRA_CONFIGURE_ARGS[@]}"}"

ninja -C "${BUILD_DIR}" "${NINJA_TARGETS[@]}" "$@"
