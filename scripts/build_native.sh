#!/usr/bin/env bash
# Builds libaltirra_libretro and libaltirra_bridge for Linux and/or Android.
#
# Usage:
#   ./scripts/build_native.sh linux
#   ./scripts/build_native.sh android [arm64-v8a|armeabi-v7a|x86_64]
#   ./scripts/build_native.sh all

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UPSTREAM="$ROOT/third_party/AltirraSDL"
BRIDGE_CMAKE="$ROOT/native/bridge.cmake"
JOBS="${JOBS:-$(nproc 2>/dev/null || echo 4)}"

build_linux() {
    local bdir="$ROOT/build/native-linux"
    local out="$ROOT/native/prebuilt/linux"
    cmake -S "$UPSTREAM" -B "$bdir" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_PROJECT_INCLUDE="$BRIDGE_CMAKE"
    cmake --build "$bdir" --target altirra_bridge -j"$JOBS"
    mkdir -p "$out"
    cp -f "$bdir/libaltirra_bridge.so" "$out/"
    cp -f "$bdir/src/AltirraLibretro/libaltirra_libretro.so" "$out/"
    echo "Linux native libraries copied to $out"
}

build_android_abi() {
    local abi="$1"
    local sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/sdk}}"
    local ndk_ver="${ANDROID_NDK_VERSION:-28.2.13676358}"
    local toolchain="$sdk/ndk/$ndk_ver/build/cmake/android.toolchain.cmake"
    if [[ ! -f "$toolchain" ]]; then
        echo "Android NDK toolchain not found at $toolchain" >&2
        exit 1
    fi
    local bdir="$ROOT/build/native-android-$abi"
    local out="$ROOT/android/app/src/main/jniLibs/$abi"
    cmake -S "$UPSTREAM" -B "$bdir" \
        -DCMAKE_TOOLCHAIN_FILE="$toolchain" \
        -DANDROID_ABI="$abi" \
        -DANDROID_PLATFORM=android-24 \
        -DANDROID_STL=c++_shared \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_PROJECT_INCLUDE="$BRIDGE_CMAKE"
    cmake --build "$bdir" --target altirra_bridge -j"$JOBS"
    mkdir -p "$out"
    cp -f "$bdir/libaltirra_bridge.so" "$out/"
    cp -f "$bdir/src/AltirraLibretro/libaltirra_libretro.so" "$out/"
    local stl="$sdk/ndk/$ndk_ver/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib"
    case "$abi" in
        arm64-v8a)   cp -f "$stl/aarch64-linux-android/libc++_shared.so" "$out/" ;;
        armeabi-v7a) cp -f "$stl/arm-linux-androideabi/libc++_shared.so" "$out/" ;;
        x86_64)      cp -f "$stl/x86_64-linux-android/libc++_shared.so" "$out/" ;;
    esac
    echo "Android ($abi) native libraries copied to $out"
}

case "${1:-all}" in
    linux)
        build_linux
        ;;
    android)
        build_android_abi "${2:-arm64-v8a}"
        ;;
    all)
        build_linux
        build_android_abi arm64-v8a
        ;;
    *)
        echo "Usage: $0 {linux|android [abi]|all}" >&2
        exit 2
        ;;
esac
