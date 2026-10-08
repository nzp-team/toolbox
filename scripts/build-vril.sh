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
}

TARGET=""
CLEAN=0
MAKE_ARGS=()

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
    *)
        show_help >&2
        exit 2
        ;;
esac

cd /workspace/repos/vril-engine

if [ "$CLEAN" -eq 1 ]; then
    make -f "$MAKEFILE" clean
fi

make -f "$MAKEFILE" -j"$(nproc)" "${MAKE_ARGS[@]}"
