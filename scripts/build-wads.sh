#!/bin/bash
# @name build-wads
# @desc Builds all map textures in repos/assets into WADs. Does it in mass due to speed.
# @usage nzp build-wads
set -e

cd /workspace/repos/assets
tools/compile-wads.sh
