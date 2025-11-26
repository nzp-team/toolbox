#!/bin/bash
set -e

SCRIPTS_DIR="/opt/scripts"

command="$1"
shift || true   # shift so "$@" holds arguments for the subcommand

# --------------------------------------------------------
# Show dynamic help
# --------------------------------------------------------
show_help() {
    echo "== Mapper Toolbox =="
    echo ""

    for script in "$SCRIPTS_DIR"/*.sh; do
        # Extract metadata
        NAME=$(grep -m1 "^# @name" "$script" | cut -d' ' -f3-)
        DESC=$(grep -m1 "^# @desc" "$script" | cut -d' ' -f3-)
        USAGE=$(grep -m1 "^# @usage" "$script" | cut -d' ' -f3-)

        [ -z "$NAME" ] && continue

        echo "  $NAME"
        echo "      $DESC"
        [ -n "$USAGE" ] && echo "      Usage: $USAGE"
        echo ""
    done
}

# Default or help
if [ -z "$command" ] || [ "$command" = "help" ]; then
    show_help
    exit 0
fi

# --------------------------------------------------------
# Dispatch to scripts automatically
# --------------------------------------------------------
script="$SCRIPTS_DIR/$command.sh"

if [ ! -f "$script" ]; then
    echo "[ERROR] Unknown command: $command"
    echo "Try: nzp help"
    exit 1
fi

if [ ! -x "$script" ]; then
    echo "[ERROR] Script exists but is not executable: $script"
    exit 1
fi

exec "$script" "$@"