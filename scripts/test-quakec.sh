#!/bin/bash
# @name test-quakec
# @button Test QuakeC
# @desc Runs QuakeC unit tests.
# @usage nzp test-quakec
set -e

cd /workspace/repos/quakec
exec bash testing/run_unit_tests.sh
