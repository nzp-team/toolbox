#!/bin/bash
# @name build-vril
# @button Build Vril
# @desc Builds Vril executables for specified platforms.
# @usage nzp build-vril --target linux-x86_64 [--clean] [-- make_args...]
set -e

show_help() {
    echo "Usage: nzp build-vril --target <target> [--clean] [-- make_args...]"
    echo "Supported targets:"
    echo "  linux-x86_64"
    echo "  linux-x86"
    echo "  linux-arm64"
    echo "  linux-armhf"
    echo "  psp"
}

TARGET=""
CLEAN=0
MAKE_ARGS=()
TARGET_ARGS=()

while [ "$#" -gt 0 ]; do
    case "$1" in
        --target)
            if [ "$#" -lt 2 ] || [ -n "$TARGET" ]; then
                show_help >&2
                exit 2
            fi
            TARGET="$2"
            shift 2
            ;;
        --clean)
            CLEAN=1
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        --)
            shift
            MAKE_ARGS=("$@")
            break
            ;;
        *)
            show_help >&2
            exit 2
            ;;
    esac
done

case "$TARGET" in
    linux-x86_64)
        MAKEFILE="Makefile.sdl"
        ;;
    linux-x86)
        MAKEFILE="Makefile.sdl"
        TARGET_ARGS=(BUILD=build/sdl/x86 CROSS_COMPILE=i686-linux-gnu-)
        export PKG_CONFIG_LIBDIR=/usr/lib/i386-linux-gnu/pkgconfig:/usr/share/pkgconfig
        ;;
    linux-arm64)
        MAKEFILE="Makefile.sdl"
        TARGET_ARGS=(BUILD=build/sdl/arm64)
        if [ "$(uname -m)" != "aarch64" ]; then
            TARGET_ARGS+=(CROSS_COMPILE=aarch64-linux-gnu-)
            export PKG_CONFIG_LIBDIR=/usr/lib/aarch64-linux-gnu/pkgconfig:/usr/share/pkgconfig
        fi
        ;;
    linux-armhf)
        MAKEFILE="Makefile.sdl"
        TARGET_ARGS=(BUILD=build/sdl/armhf CROSS_COMPILE=arm-linux-gnueabihf-)
        export PKG_CONFIG_LIBDIR=/usr/lib/arm-linux-gnueabihf/pkgconfig:/usr/share/pkgconfig
        ;;
    psp)
        MAKEFILE="Makefile.psp"
        ;;
    *)
        show_help >&2
        exit 2
        ;;
esac

cd /workspace/repos/vril-engine

if [ "$CLEAN" -eq 1 ]; then
    make -f "$MAKEFILE" "${TARGET_ARGS[@]}" clean
fi

make -f "$MAKEFILE" -j"$(nproc)" "${TARGET_ARGS[@]}" "${MAKE_ARGS[@]}"
