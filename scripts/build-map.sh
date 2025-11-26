#!/bin/bash
# @name build-map
# @desc Builds a map stored in repos/assets into a bsp and builds zone file (if data exists). Default behavior will build all maps.
# @usage nzp build [--map map_name] [--full]
set -e

VENV="/workspace/python_envs/spawn-zone-tool"
. "$VENV/bin/activate"

cd /workspace/repos/assets
tools/compile-maps.sh $@ --zone-tool-path /workspace/repos/spawn-zone-tool

deactivate || true