#!/bin/bash
# @name test-assets
# @button Test Assets
# @desc Runs an assets repository validation test.
# @usage nzp test-assets <test_name>
set -e

if [ "$#" -ne 1 ]; then
    echo "[ERROR] test-assets expects one test name." >&2
    exit 2
fi

test_name="$1"
if [ "$test_name" != "${test_name##*/}" ]; then
    echo "[ERROR] Test name must be a filename in assets/testing/." >&2
    exit 2
fi

test_script="/workspace/repos/assets/testing/${test_name}.sh"
if [ ! -f "$test_script" ]; then
    echo "[ERROR] Assets test not found: $test_script" >&2
    exit 1
fi

exec bash "$test_script"
