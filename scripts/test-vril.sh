#!/bin/bash
# @name test-vril
# @button Run Vril Test
# @desc Runs Vril engine Pull Request tests. Workspace and content path is handled by Toolbox.
# @usage nzp test-vril --platform platform_name --test test_name [--generate] [--mode mode] [--binary binary_path]
set -e

cd /workspace/repos/vril-engine/testing
./run_tests.sh $@ --content "$(pwd)/validate" --working-dir working/