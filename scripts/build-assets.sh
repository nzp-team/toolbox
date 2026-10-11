#!/bin/bash
# @name build-assets
# @button Build Assets
# @desc Builds Game Asset sources for NZ:P.
# @usage nzp build-assets
set -e

cd /workspace/repos/assets/tools
./assemble-assets.sh $@

cp -fa /workspace/repos/assets/tmp/pc/. /workspace/game/