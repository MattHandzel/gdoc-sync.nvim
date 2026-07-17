#!/usr/bin/env bash
# Real-API E2E: create → push → pull → diff → status → unlink through the
# plugin, against the real Google API, then trash the test doc.
#
# Needs: an authenticated gdoc-sync CLI (gdoc-sync doctor all green).
# Your real state file is untouched — an isolated config/state pair in a
# temp dir is used throughout.
set -euo pipefail
script_dir="$(cd "$(dirname "$0")" && pwd)"
cd "$script_dir/../.."

command -v gdoc-sync >/dev/null || { echo "gdoc-sync CLI not on PATH"; exit 1; }

work="$(mktemp -d)"
cleanup() {
  # Trash the doc the test created (the lua test saves its id to $work/doc_id
  # before unlinking). Stdlib-only python against the Drive REST API, reusing
  # the CLI's cached token.
  if [ -s "$work/doc_id" ]; then
    doc_id="$(cat "$work/doc_id")"
    echo "Trashing test doc $doc_id"
    python3 "$script_dir/trash_doc.py" "$doc_id" \
      || echo "WARN: could not trash the doc — delete it from Drive manually"
  fi
  rm -rf "$work"
}
trap cleanup EXIT

cat > "$work/config.yaml" <<EOF
state_file: $work/state.yaml
defaults:
  clipboard: false
  share: private
EOF

export E2E_CONFIG="$work/config.yaml"
export E2E_WORK="$work"

nvim --headless --clean -u tests/minimal_init.lua -l tests/e2e/real_api.lua

echo "E2E passed."
