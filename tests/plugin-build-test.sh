#!/bin/sh
set -eu
. "$(dirname "$0")/testlib.sh"

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
tmp=$(new_tmpdir)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

[ -f "$root/lib/aidlc-plugin-tools.sh" ] || fail "plugin toolchain helper exists"
. "$root/lib/aidlc-plugin-tools.sh"

require_plugin_toolchain
validate_flow_plugin "$root/plugins/flow"
build_flow_projection codex "$tmp/codex" "$root/plugins/flow"
build_flow_projection claude "$tmp/claude" "$root/plugins/flow"

for harness in codex claude; do
  projection="$tmp/$harness"
  host_manifest_dir=.$harness-plugin

  [ -f "$projection/.aidlc-plugin-projection.json" ] ||
    fail "$harness projection metadata is generated"
  [ -f "$projection/$host_manifest_dir/plugin.json" ] ||
    fail "$harness host manifest is generated"
  [ -f "$projection/$host_manifest_dir/marketplace.json" ] ||
    fail "$harness marketplace manifest is generated"

  python3 - "$projection/.aidlc-plugin-projection.json" \
    "$projection/$host_manifest_dir/plugin.json" "$harness" <<'PY' ||
import json
import sys

with open(sys.argv[1], encoding="utf-8") as projection_file:
    projection = json.load(projection_file)
with open(sys.argv[2], encoding="utf-8") as manifest_file:
    manifest = json.load(manifest_file)

expected_projection = {
    "schema": 1,
    "producer": "aidlc-plugin-build",
    "plugin": "flow",
    "harness": sys.argv[3],
}
if projection != expected_projection:
    raise SystemExit(f"unexpected projection metadata: {projection!r}")
if manifest.get("name") != "aidlc-flow" or manifest.get("version") != "0.1.0":
    raise SystemExit(f"unexpected host manifest: {manifest!r}")
PY
    fail "$harness projection manifests match the official build contract"

  cmp -s "$root/plugins/flow/scopes/flow-slice.md" \
    "$projection/scopes/flow-slice.md" || fail "$harness projection contains flow-slice scope"

  stage_count=$(find "$projection/stages" -type f -name '*.md' | wc -l | tr -d ' ')
  assert_eq "$stage_count" 3 "$harness projection contains exactly three stages"
  for stage in \
    inception/flow-slice-contract.md \
    construction/flow-slice-review.md \
    construction/flow-merge-readiness.md
  do
    cmp -s "$root/plugins/flow/stages/$stage" "$projection/stages/$stage" ||
      fail "$harness projection contains stage: $stage"
  done

  overlay_count=$(find "$projection/contributions" -type f -name '*.md' | wc -l | tr -d ' ')
  assert_eq "$overlay_count" 5 "$harness projection contains all overlays"
  for overlay in \
    initialization/workspace-scaffold.md \
    initialization/workspace-detection.md \
    initialization/state-init.md \
    construction/code-generation.md \
    construction/build-and-test.md
  do
    cmp -s "$root/plugins/flow/contributions/$overlay" \
      "$projection/contributions/$overlay" ||
      fail "$harness projection contains overlay: $overlay"
  done
done

unsafe_data_home="$tmp/unsafe-data-home"
mkdir -p "$unsafe_data_home/aidlc"
printf '../2.9.0\n' >"$unsafe_data_home/aidlc/active-version"
set +e
unsafe_version_output=$(unset AIDLC_FLOW_AIDLC_HOME; XDG_DATA_HOME="$unsafe_data_home" \
  require_plugin_toolchain 2>&1)
unsafe_version_status=$?
set -e
[ "$unsafe_version_status" -ne 0 ] || fail "unsafe active version is rejected"
assert_contains "$unsafe_version_output" "unsafe AI-DLC active version" \
  "unsafe active version reports a clear error"

printf '2.9.0\n2.8.0\n' >"$unsafe_data_home/aidlc/active-version"
set +e
multiline_version_output=$(unset AIDLC_FLOW_AIDLC_HOME; XDG_DATA_HOME="$unsafe_data_home" \
  require_plugin_toolchain 2>&1)
multiline_version_status=$?
set -e
[ "$multiline_version_status" -ne 0 ] || fail "multi-line active version is rejected"
assert_contains "$multiline_version_output" "must contain exactly one line" \
  "multi-line active version reports a clear error"

set +e
relative_home_output=$(AIDLC_FLOW_AIDLC_HOME=relative-aidlc-home \
  require_plugin_toolchain 2>&1)
relative_home_status=$?
set -e
[ "$relative_home_status" -ne 0 ] || fail "relative AI-DLC home is rejected"
assert_contains "$relative_home_output" "must be an absolute path" \
  "relative AI-DLC home reports a clear error"

printf 'PASS: plugin-build-test\n'
