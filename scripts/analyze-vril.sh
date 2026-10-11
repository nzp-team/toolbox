#!/bin/bash
# @name analyze-vril
# @button Analyze Vril
# @desc Runs a static analyzer on Vril Engine.
# @usage nzp analyze-vril --mode cppcheck|clang-analysis
set -e

show_help() {
    echo "Usage: nzp analyze-vril --mode <mode>"
    echo "Supported modes:"
    echo "  cppcheck"
    echo "  clang-analysis"
}

MODE=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --mode)
            if [ "$#" -lt 2 ] || [ -n "$MODE" ]; then
                show_help >&2
                exit 2
            fi
            MODE="$2"
            shift 2
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            show_help >&2
            exit 2
            ;;
    esac
done

case "$MODE" in
    cppcheck|clang-analysis) ;;
    *)
        show_help >&2
        exit 2
        ;;
esac

cd /workspace/repos/vril-engine

case "$MODE" in
    cppcheck)
        exec cppcheck --force --error-exitcode=1 .
        ;;
    clang-analysis)
        exec scan-build --status-bugs make -f Makefile.sdl CC=clang
        ;;
esac
