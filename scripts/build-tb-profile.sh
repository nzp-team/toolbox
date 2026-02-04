#!/bin/bash
# @name build-tb-profile
# @desc Builds ready-to-go TrenchBroom Profile and Configuration
# @usage nzp build-tb-profile
set -e

TB_WORKSPACE=/workspace/repos/trenchbroom-profile
ASSETS_WORKSPACE=/workspace/repos/assets

MAP_RUN_PARAMETERS="+map \${MAP_BASE_NAME} +sv_cheats 1"

if [[ "${TOOLBOX_HOST_OS}" == "Windows" ]]; then
    TOOLBOX_BIN_NAME="nzp.cmd"
    GAME_BINARY="nzportable-sdl64.exe"
else
    TOOLBOX_BIN_NAME="nzp"
    GAME_BINARY=$(ls /workspace/game | grep "nzportable")

    # If we downloaded the Windows version for whatever reason, and we aren't
    # on Windows, assume Wine for the binary and append the exe to the run params.
    if [[ "${GAME_BINARY}" == "nzportable-sdl64.exe" ]]; then
        GAME_BINARY="${TOOLBOX_WINE_PATH}"
        MAP_RUN_PARAMETERS="nzportable-sdl64.exe ${MAP_RUN_PARAMETERS}"
    fi
fi

COMPILATION_PROFILE_JSON=$(cat <<EOF
{
	"profiles": [
		{
			"name": "(Toolbox) Full Compile",
			"tasks": [
				{
					"parameters": "build-map --map \${MAP_BASE_NAME} --full",
					"tool": "\${WORK_DIR_PATH}/${TOOLBOX_BIN_NAME}",
					"treatNonZeroResultCodeAsError": true,
					"type": "tool"
				},
				{
					"source": "\${WORK_DIR_PATH}/repos/assets/common/maps/\${MAP_BASE_NAME}.bsp",
					"target": "\${WORK_DIR_PATH}/game/nzp/maps",
					"type": "copy"
				},
				{
					"source": "\${WORK_DIR_PATH}/repos/assets/common/maps/\${MAP_BASE_NAME}.nsz",
					"target": "\${WORK_DIR_PATH}/game/nzp/maps",
					"type": "copy"
				}
			],
			"workdir": "${TOOLBOX_ROOT}"
		},
		{
			"name": "Run",
			"tasks": [
				{
					"parameters": "${MAP_RUN_PARAMETERS}",
					"tool": "${GAME_BINARY}",
					"type": "tool"
				}
			],
			"workdir": "${TOOLBOX_ROOT}/game"
		}
	],
	"version": 1
}
EOF
)

PREFERENCES_JSON=$(cat <<EOF
{
    "Games/Nazi Zombies Portable/Path": "${TOOLBOX_ROOT}/game"
}
EOF
)

# Assume the fgd in assets is newer, so copy that over to trenchbroom-profile
cp "${ASSETS_WORKSPACE}/source/maps/fgd/tb-nzp.fgd" "${TB_WORKSPACE}/"

# Remove build directory in trenchbroom-profile if it exists
rm -rf "${TB_WORKSPACE}/build"

# Make necessary dirs..
mkdir "${TB_WORKSPACE}/build"
mkdir "${TB_WORKSPACE}/build/games"
mkdir "${TB_WORKSPACE}/build/games/nzp"
mkdir "${TB_WORKSPACE}/build/games/Nazi Zombies Portable"

# Copy relevant contents..
cp "${TB_WORKSPACE}/GameConfig.cfg" "${TB_WORKSPACE}/build/games/nzp"
cp "${TB_WORKSPACE}/Icon.png" "${TB_WORKSPACE}/build/games/nzp"
cp "${TB_WORKSPACE}/tb-nzp.fgd" "${TB_WORKSPACE}/build/games/nzp"

# Generate CompilationProfiles.json
printf "%s\n" "$COMPILATION_PROFILE_JSON" >>  "${TB_WORKSPACE}/build/games/Nazi Zombies Portable/CompilationProfiles.json"

# Generate Preferences.json
printf "%s\n" "$PREFERENCES_JSON" >>  "${TB_WORKSPACE}/build/Preferences.json"

echo ""
echo "[INFO] ================================"
echo "[INFO] Successfully generated a configuration for"
echo "[INFO] TrenchBroom 2024.1 to [${TOOLBOX_ROOT}/repos/trenchbroom-profile/build]."
echo "[INFO] Copy the contents of this folder to TrenchBroom"
echo "[INFO] configuration directory, see user path files part"
echo "[INFO] of TrenchBroom manual for location details:"
echo "[INFO] https://trenchbroom.github.io/manual/latest#game_configuration_files"
echo "[INFO] ================================"