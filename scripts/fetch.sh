#!/bin/bash
# @name fetch
# @desc Clones and/or pulls repositories needed for Toolbox. Reads from config/repos.json
# @usage nzp fetch
set -e
set -o pipefail

CONFIG="/workspace/config/repos.json"
ROOT="/workspace"

echo "[INFO] Syncing repositories..."

jq -c '.repos[]' "$CONFIG" | while read -r repo; do
    NAME=$(echo "$repo" | jq -r '.name')
    URL=$(echo "$repo" | jq -r '.url')
    LOCAL=$(echo "$repo" | jq -r '.target')
    REQUIRE_FILES=$(echo "$repo" | jq -r '.requirements[]?' || true)

    TARGET="$ROOT/$LOCAL"

    echo ""
    echo "[INFO] ================================"
    echo "[INFO] Repo: $NAME"
    echo "[INFO] URL:  $URL"
    echo "[INFO] Path: $TARGET"
    echo "[INFO] ================================"

    # Clone or Pull repositories.
    if [ ! -d "$TARGET/.git" ]; then
        echo "[INFO] Cloning fresh repository..."
        git clone "$URL" "$TARGET"

        if [ -f "$TARGET/.gitmodules" ]; then
            echo "[INFO] Initializing submodules..."
            git -C "$TARGET" submodule update --init --recursive --remote
        fi
    else
        echo "[INFO] Pulling updates..."
        git -C "$TARGET" pull --rebase || {
            echo "[INFO] Pull failed — attempting to continue..."
        }

        if [ -f "$TARGET/.gitmodules" ]; then
            echo "[INFO] Updating submodules..."
            git -C "$TARGET" submodule sync --recursive
            git -C "$TARGET" submodule update --init --recursive --remote
        fi
    fi

    REQUIRE_FILES=$(echo "$repo" | jq -r '.requirements[]?' || true)

    # Only make a venv if requirements exist
    if [ -n "$REQUIRE_FILES" ]; then
        VENV_PATH="$ROOT/python_envs/$NAME"

        if [ ! -d "$VENV_PATH" ]; then
            echo "[INFO] Creating persistent virtual environment for $NAME..."
            python3 -m venv "$VENV_PATH"
        fi

        . "$VENV_PATH/bin/activate"

        echo "[INFO] Installing Python dependencies for $NAME..."
        while read -r relreq; do
            [ -z "$relreq" ] && continue
            REQ_FILE="$TARGET/$relreq"

            if [ -f "$REQ_FILE" ]; then
                echo " + python3 -m pip install -r $relreq --break-system-packages"
                python3 -m pip install -r "$REQ_FILE" --break-system-packages
            else
                echo "[ERROR] Missing requirements file [$REQ_FILE]!"
            fi
        done <<< "$REQUIRE_FILES"

        deactivate || true
    fi

done

echo ""
echo "[INFO] All repositories synchronized."
