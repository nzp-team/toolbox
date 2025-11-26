#!/bin/bash
# @name new-map
# @desc Creates file structure for new map of name, copying template for use.
# @usage nzp new-map --map map_name
set -e

while true; do
    case "$1" in
        -m | --map ) MAP_NAME="$2"; shift 2 ;;
        -- ) shift; break ;;
        * ) break ;;
    esac
done

cd /workspace/repos/assets

if [ -z "${MAP_NAME}" ]; then
    echo "[ERROR]: No map name provided. Bailing!"
    exit 1
fi

mkdir source/maps/${MAP_NAME}
cp source/maps/template.map source/maps/${MAP_NAME}/${MAP_NAME}.map