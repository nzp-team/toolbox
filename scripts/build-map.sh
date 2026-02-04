#!/bin/bash
# @name build-map
# @desc Builds a map stored in repos/assets into a bsp and builds zone file (if data exists). Default behavior will build all maps.
# @usage nzp build [--map map_name] [--full]
set -e

# Users will probably try to build a map before building WADs,
# so check if zhlt exists and build the WADs for them if it doesn't.
if [ ! -f "/workspace/repos/assets/source/textures/wad/zhlt.wad" ]; then
    echo "[INFO]: WADs do not exist in assets repository, building them for you.."
    /opt/scripts/build-wads.sh
fi

VENV="/workspace/python_envs/spawn-zone-tool"
. "$VENV/bin/activate"

cd /workspace/repos/assets
tools/compile-maps.sh $@ --zone-tool-path /workspace/repos/spawn-zone-tool

deactivate || true