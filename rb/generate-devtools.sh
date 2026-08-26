#!/usr/bin/env bash
# Reproduces Bazel's CDP codegen for the selenium-devtools gem, off Bazel:
# for each CDP version, convert the checked-in .pdl protocol to .json
# (common/devtools/convert_protocol_to_json.py) then generate the Ruby client
# (rb/lib/selenium/devtools/support/cdp_client_generator.rb) into vNNN.rb + vNNN/.
# Run under bundler (needs erb/json from the gem bundle on Ruby 3.4+).
# The generator's generated_note.rb is de-Bazelized (repo-relative template
# fallback), so no bazel/runfiles is needed.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEVTOOLS="$ROOT/common/devtools"
GEN="$ROOT/rb/lib/selenium/devtools"
VERSIONS="v150 v151 v152"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

for v in $VERSIONS; do
  python3 "$DEVTOOLS/convert_protocol_to_json.py" \
    "$ROOT/common/devtools/chromium/$v/browser_protocol.pdl" --map_binary_to_string=true "$TMP/${v}_browser.json"
  python3 "$DEVTOOLS/convert_protocol_to_json.py" \
    "$ROOT/common/devtools/chromium/$v/js_protocol.pdl" --map_binary_to_string=true "$TMP/${v}_js.json"
  ( cd "$GEN" && bundle exec ruby support/cdp_client_generator.rb \
      "$TMP/${v}_browser.json" "$TMP/${v}_js.json" "${v}.rb" "$v" )
  echo "generated selenium/devtools/${v}.rb (+ ${v}/ domain modules)"
done
