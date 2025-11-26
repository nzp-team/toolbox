#!/bin/bash
# @name build-quakec
# @desc Builds QuakeC source for NZ:P. Really only useful for mods or development, not so much map making.
# @usage nzp build-quakec [--test-mode]
set -e

VENV="/workspace/python_envs/qchashtablegenerator"
. "$VENV/bin/activate"

cd /workspace/repos/quakec
tools/qc-compiler-gnu.sh $@

deactivate || true