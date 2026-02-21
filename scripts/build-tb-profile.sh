#!/bin/bash
# @name build-tb-profile
# @button Build TrenchBroom Profile
# @desc Builds ready-to-go TrenchBroom Profile and Configuration
# @usage nzp build-tb-profile
set -e

TOOLBOX_ROOT="${TOOLBOX_ROOT//\\//}"
TB_WORKSPACE=/workspace/repos/trenchbroom-profile
ASSETS_WORKSPACE=/workspace/repos/assets

MAP_RUN_PARAMETERS="+map \${MAP_BASE_NAME} +sv_cheats 1"

if [[ "${TOOLBOX_HOST_OS}" == "Windows" ]]; then
    TOOLBOX_BIN_NAME="nzp.cmd"
    GAME_BINARY="${TOOLBOX_ROOT}/game/nzportable-sdl64.exe"
else
    TOOLBOX_BIN_NAME="nzp"
    GAME_BINARY="${TOOLBOX_ROOT}/game/$(ls /workspace/game | grep 'nzportable')"

    # If we downloaded the Windows version for whatever reason, and we aren't
    # on Windows, assume Wine for the binary and append the exe to the run params.
    if [[ "${GAME_BINARY}" == "${TOOLBOX_ROOT}/game/nzportable-sdl64.exe" ]]; then
        GAME_BINARY="${TOOLBOX_WINE_PATH}"
        MAP_RUN_PARAMETERS="${TOOLBOX_ROOT}/game/nzportable-sdl64.exe ${MAP_RUN_PARAMETERS}"
    fi
fi

GAMEENGINE_PROFILE_CFG=$(cat <<EOF
{
	"profiles": [
		{
			"name": "Nazi Zombies Portable",
			"parameters": "${MAP_RUN_PARAMETERS}",
			"path": "${GAME_BINARY}"
		}
	],
	"version": 1
}
EOF
)

COMPILATION_PROFILE_CFG=$(cat <<EOF
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

# Generate CompilationProfiles.cfg
printf "%s\n" "$COMPILATION_PROFILE_CFG" >>  "${TB_WORKSPACE}/build/games/Nazi Zombies Portable/CompilationProfiles.cfg"

# Generate GameEngineProfiles.cfg
printf "%s\n" "$GAMEENGINE_PROFILE_CFG" >>  "${TB_WORKSPACE}/build/games/Nazi Zombies Portable/GameEngineProfiles.cfg"

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