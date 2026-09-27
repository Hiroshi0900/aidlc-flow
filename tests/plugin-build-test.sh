#!/bin/sh
set -eu
. "$(dirname "$0")/testlib.sh"

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
tmp=$(new_tmpdir)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

[ -f "$root/lib/aidlc-plugin-tools.sh" ] || fail "plugin toolchain helper exists"
. "$root/lib/aidlc-plugin-tools.sh"

make_fake_aidlc_responder() {
  fixture_home=$1
  fixture_version=$2
  fixture_shape=${3:-line}
  mkdir -p "$fixture_home"
  case "$fixture_shape" in
    line) fixture_print="printf '%s\\n' '$fixture_version'" ;;
    trailing-empty) fixture_print="printf '%s\\n\\n' '$fixture_version'" ;;
    leading-empty) fixture_print="printf '\\n%s\\n' '$fixture_version'" ;;
    multiple) fixture_print="printf '%s\\n%s\\n' '$fixture_version' extra" ;;
    no-newline) fixture_print="printf '%s' '$fixture_version'" ;;
    nul) fixture_print="printf '%s\\000\\n' '$fixture_version'" ;;
    *) fail "unknown fake AI-DLC version shape: $fixture_shape" ;;
  esac
  cat >"$fixture_home/aidlc" <<SH
#!/bin/sh
[ "\${1:-}" = --version ] && [ "\$#" -eq 1 ] || exit 64
$fixture_print
SH
  chmod +x "$fixture_home/aidlc"
}

make_fake_aidlc_runtime() {
  fixture_home=$1
  fixture_version=$2
  fixture_shape=${3:-line}
  fixture_tools="$fixture_home/runtime/claude/.claude/tools"
  mkdir -p "$fixture_tools"
  : >"$fixture_tools/aidlc-plugin-validate.ts"
  : >"$fixture_tools/aidlc-plugin-build.ts"
  make_fake_aidlc_responder "$fixture_home" "$fixture_version" "$fixture_shape"
}

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
if manifest.get("name") != "aidlc-flow" or manifest.get("version") != "0.1.1":
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

  python3 - "$projection/contributions/construction/code-generation.md" "$harness" <<'PY' ||
import re
import sys

path, harness = sys.argv[1:]
text = open(path, encoding="utf-8").read()
match = re.match(r"^---\n(.*?)\n---\n(.*)$", text, re.S)
if not match:
    raise SystemExit(f"{harness} contribution frontmatter is missing")
frontmatter, body = match.groups()
consumes = re.findall(
    r"^    - artifact: ([a-z0-9-]+)\n      required: (true|false)$",
    frontmatter,
    re.M,
)
if consumes != [("flow-requirements", "true"), ("flow-slice-contract", "true")]:
    raise SystemExit(f"{harness} projection lost required consumes: {consumes!r}")
fragments = re.findall(
    r"^  - anchor: (\S+)\n    order: (\d+)$", frontmatter, re.M
)
if fragments != [("after-step:1", "100")]:
    raise SystemExit(f"{harness} projection lost fragment metadata: {fragments!r}")
for required in (
    "flow-requirements.md",
    "flow-slice-contract.md",
    "Acceptance Criteria",
    "Boundary Test",
    "Merge Safety",
    "TDD",
):
    if required not in body:
        raise SystemExit(f"{harness} projection lost contribution prose: {required!r}")
PY
    fail "$harness projection preserves code-generation artifact continuity"
done

unsafe_data_home="$tmp/unsafe-data-home"
mkdir -p "$unsafe_data_home/aidlc"
for unsupported_active_version in 2.8.0 3.0.0; do
  unsupported_home="$unsafe_data_home/aidlc/versions/$unsupported_active_version"
  make_fake_aidlc_runtime "$unsupported_home" \
    "aidlc $unsupported_active_version (runtime $unsupported_active_version)"
  printf '%s\n' "$unsupported_active_version" >"$unsafe_data_home/aidlc/active-version"
  set +e
  unsupported_active_output=$(unset AIDLC_FLOW_AIDLC_HOME; \
    XDG_DATA_HOME="$unsafe_data_home" require_plugin_toolchain 2>&1)
  unsupported_active_status=$?
  set -e
  [ "$unsupported_active_status" -ne 0 ] ||
    fail "active AI-DLC $unsupported_active_version is rejected"
  assert_contains "$unsupported_active_output" \
    "AI-DLC active version must be 2.9.0; found: $unsupported_active_version" \
    "unsupported active version reports the selected version"
done

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

for invalid_report in \
  'aidlc 2.8.0 (runtime 2.8.0)' \
  'aidlc 3.0.0 (runtime 3.0.0)' \
  'prefix aidlc 2.9.0 (runtime 2.9.0)' \
  'aidlc 2.9.0 (runtime 2.9.0) suffix'
do
  invalid_report_home="$tmp/invalid-report-$(printf '%s' "$invalid_report" | cksum | awk '{ print $1 }')"
  make_fake_aidlc_runtime "$invalid_report_home" "$invalid_report"
  set +e
  invalid_report_output=$(AIDLC_FLOW_AIDLC_HOME="$invalid_report_home" \
    require_plugin_toolchain 2>&1)
  invalid_report_status=$?
  set -e
  [ "$invalid_report_status" -ne 0 ] ||
    fail "override runtime version report is exact: $invalid_report"
  assert_contains "$invalid_report_output" \
    "selected AI-DLC runtime must report exactly aidlc 2.9.0 (runtime 2.9.0)" \
    "invalid override runtime report explains the exact contract"
done

for invalid_shape in trailing-empty leading-empty multiple no-newline nul; do
  invalid_shape_home="$tmp/invalid-shape-$invalid_shape"
  make_fake_aidlc_runtime "$invalid_shape_home" \
    'aidlc 2.9.0 (runtime 2.9.0)' "$invalid_shape"
  set +e
  invalid_shape_output=$(AIDLC_FLOW_AIDLC_HOME="$invalid_shape_home" \
    require_plugin_toolchain 2>&1)
  invalid_shape_status=$?
  set -e
  [ "$invalid_shape_status" -ne 0 ] ||
    fail "selected runtime rejects malformed version output shape: $invalid_shape"
  assert_contains "$invalid_shape_output" \
    "selected AI-DLC runtime must report exactly aidlc 2.9.0 (runtime 2.9.0)" \
    "malformed selected runtime version output explains the exact contract"
done

unsafe_executable_home="$tmp/unsafe-executable-home"
make_fake_aidlc_runtime "$unsafe_executable_home" \
  'aidlc 2.9.0 (runtime 2.9.0)'
rm "$unsafe_executable_home/aidlc"
set +e
missing_executable_output=$(AIDLC_FLOW_AIDLC_HOME="$unsafe_executable_home" \
  require_plugin_toolchain 2>&1)
missing_executable_status=$?
set -e
[ "$missing_executable_status" -ne 0 ] || fail "missing selected runtime executable is rejected"
assert_contains "$missing_executable_output" "executable is missing or unsafe" \
  "missing selected runtime executable reports a clear error"

make_fake_aidlc_runtime "$unsafe_executable_home" \
  'aidlc 2.9.0 (runtime 2.9.0)'
chmod -x "$unsafe_executable_home/aidlc"
set +e
non_executable_output=$(AIDLC_FLOW_AIDLC_HOME="$unsafe_executable_home" \
  require_plugin_toolchain 2>&1)
non_executable_status=$?
set -e
[ "$non_executable_status" -ne 0 ] || fail "non-executable selected runtime is rejected"
assert_contains "$non_executable_output" "executable is missing or unsafe" \
  "non-executable selected runtime reports a clear error"

real_selected_executable="$tmp/real-selected-aidlc"
cp "$unsafe_executable_home/aidlc" "$real_selected_executable"
chmod +x "$real_selected_executable"
rm "$unsafe_executable_home/aidlc"
ln -s "$real_selected_executable" "$unsafe_executable_home/aidlc"
set +e
symlink_executable_output=$(AIDLC_FLOW_AIDLC_HOME="$unsafe_executable_home" \
  require_plugin_toolchain 2>&1)
symlink_executable_status=$?
set -e
[ "$symlink_executable_status" -ne 0 ] || fail "symlinked selected runtime executable is rejected"
assert_contains "$symlink_executable_output" "executable is missing or unsafe" \
  "symlinked selected runtime executable reports a clear error"

override_symlink_home="$tmp/override-symlink-home"
override_real_runtime="$tmp/override-real-runtime"
make_fake_aidlc_responder "$override_symlink_home" \
  'aidlc 2.9.0 (runtime 2.9.0)'
mkdir -p "$override_real_runtime/claude/.claude/tools"
: >"$override_real_runtime/claude/.claude/tools/aidlc-plugin-validate.ts"
: >"$override_real_runtime/claude/.claude/tools/aidlc-plugin-build.ts"
ln -s "$override_real_runtime" "$override_symlink_home/runtime"
set +e
override_symlink_output=$(AIDLC_FLOW_AIDLC_HOME="$override_symlink_home" \
  require_plugin_toolchain 2>&1)
override_symlink_status=$?
set -e
[ "$override_symlink_status" -ne 0 ] || fail "override runtime symlink is rejected"
assert_contains "$override_symlink_output" \
  "AI-DLC runtime path is missing or unsafe: $override_symlink_home/runtime" \
  "override runtime symlink reaches the runtime-path guard"

printf 'PASS: plugin-build-test\n'
