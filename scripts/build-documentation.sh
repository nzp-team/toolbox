#!/bin/bash
# @name build-documentation
# @button Build Documentation
# @desc Builds NZ:P documentation as HTML
# @usage nzp build-documentation
set -e

cd /workspace/repos/documentation
./generate_docs.sh $@