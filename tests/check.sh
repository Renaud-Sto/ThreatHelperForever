#!/bin/sh
# Unit tests, then static analysis (0 warnings required). Works from any directory.
set -e
cd "$(dirname "$0")/.."
luajit tests/run.lua
luacheck ThreatHelperForever tests --config .luacheckrc
