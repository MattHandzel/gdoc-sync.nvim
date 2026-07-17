#!/usr/bin/env bash
# Plugin test suite: module-load test + stub-CLI functional tests.
# No network, no real gdoc-sync needed. Usage: tests/run.sh
set -euo pipefail
cd "$(dirname "$0")/.."

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

echo "== module load =="
nvim --headless --clean -u tests/minimal_init.lua -l tests/test_load.lua

echo
echo "== stub-CLI functional =="
export STUB_LOG="$work/stub.log"
export STUB_WORK="$work"
export STUB_LINKED="$work/note.md"
: > "$STUB_LOG"
PATH="$PWD/tests/stub:$PATH" nvim --headless --clean -u tests/minimal_init.lua -l tests/test_stub.lua

echo
echo "All tests passed."
