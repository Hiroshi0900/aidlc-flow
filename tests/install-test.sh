#!/bin/sh
set -eu
. "$(dirname "$0")/testlib.sh"

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
tmp=$(new_tmpdir)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

fake_aidlc_home="$tmp/fake-aidlc"
fake_tools="$fake_aidlc_home/runtime/claude/.claude/tools"
mkdir -p "$fake_tools"
: >"$fake_tools/aidlc-plugin-validate.ts"
: >"$fake_tools/aidlc-plugin-build.ts"
fake_bun="$tmp/fake-bun"
cat >"$fake_bun" <<'SH'
#!/bin/sh
set -eu
tool=$1
shift
case "${tool##*/}" in
  aidlc-plugin-validate.ts)
    [ "$#" -eq 1 ] && [ -f "$1/.aidlc-plugin/plugin.json" ] || exit 71
    ;;
  aidlc-plugin-build.ts)
    [ "$#" -eq 3 ] || exit 72
    plugin_root=$1
    harness=$2
    output_dir=$3
    [ -f "$plugin_root/.aidlc-plugin/plugin.json" ] || exit 73
    [ "$harness" = codex ] || [ "$harness" = claude ] || exit 74
    [ "${AIDLC_FLOW_FAKE_FAIL_HARNESS:-}" != "$harness" ] || exit 75
    mkdir -p "$output_dir"
    printf '%s\n' "$harness" >"$output_dir/fake-projection"
    ;;
  *) exit 76 ;;
esac
SH
chmod +x "$fake_bun"

AIDLC_FLOW_DATA_HOME="$tmp/share" AIDLC_FLOW_BIN_HOME="$tmp/bin" \
  AIDLC_FLOW_BUN="$fake_bun" AIDLC_FLOW_AIDLC_HOME="$fake_aidlc_home" \
  /bin/sh "$root/install.sh"

installed_cli="$tmp/share/aidlc-flow/bin/aidlc-flow"
command_path="$tmp/bin/aidlc-flow"
[ -x "$installed_cli" ] || fail "installed CLI is executable"
[ -L "$command_path" ] || fail "command path is a symlink"
[ -f "$tmp/share/aidlc-flow/plugins/flow/.aidlc-plugin/plugin.json" ] ||
  fail "plugin source is installed"
assert_eq "$(cat "$tmp/share/aidlc-flow/plugin-dist/codex/fake-projection")" codex \
  "Codex projection is installed"
assert_eq "$(cat "$tmp/share/aidlc-flow/plugin-dist/claude/fake-projection")" claude \
  "Claude projection is installed"

set +e
output=$("$command_path" 2>&1)
status=$?
set -e

assert_eq "$status" "2" "installed CLI without arguments exits with usage error"
assert_eq "$output" "Usage: aidlc-flow init --harness codex|claude [--project-dir PATH]" \
  "installed CLI prints exact usage"

before=$(find "$tmp" -type f -exec cksum {} \; | sort)
AIDLC_FLOW_DATA_HOME="$tmp/share" AIDLC_FLOW_BIN_HOME="$tmp/bin" \
  AIDLC_FLOW_BUN="$fake_bun" AIDLC_FLOW_AIDLC_HOME="$fake_aidlc_home" \
  /bin/sh "$root/install.sh"
after=$(find "$tmp" -type f -exec cksum {} \; | sort)
assert_eq "$after" "$before" "reinstall is idempotent"

printf 'keep previous projection\n' >"$tmp/share/aidlc-flow/plugin-dist/codex/sentinel"
dist_before=$(find "$tmp/share/aidlc-flow/plugin-dist" -type f -exec cksum {} \; | sort)
set +e
build_failure_output=$(AIDLC_FLOW_DATA_HOME="$tmp/share" AIDLC_FLOW_BIN_HOME="$tmp/bin" \
  AIDLC_FLOW_BUN="$fake_bun" AIDLC_FLOW_AIDLC_HOME="$fake_aidlc_home" \
  AIDLC_FLOW_FAKE_FAIL_HARNESS=claude /bin/sh "$root/install.sh" 2>&1)
build_failure_status=$?
set -e
[ "$build_failure_status" -ne 0 ] || fail "projection build failure exits non-zero"
assert_contains "$build_failure_output" "failed to build claude plugin projection" \
  "projection build failure is reported"
dist_after=$(find "$tmp/share/aidlc-flow/plugin-dist" -type f -exec cksum {} \; | sort)
assert_eq "$dist_after" "$dist_before" "failed projection build preserves existing dist"
[ ! -e "$tmp/share/aidlc-flow/plugin-dist.new" ] ||
  fail "failed projection build cleans its staging directory"

conflict_root="$tmp/conflict"
mkdir -p "$conflict_root/bin/aidlc-flow"
printf 'keep\n' >"$conflict_root/bin/aidlc-flow/sentinel"
conflict_before=$(find "$conflict_root" -type f -exec cksum {} \; | sort)
set +e
conflict_output=$(AIDLC_FLOW_DATA_HOME="$conflict_root/share" \
  AIDLC_FLOW_BIN_HOME="$conflict_root/bin" \
  AIDLC_FLOW_BUN="$fake_bun" AIDLC_FLOW_AIDLC_HOME="$fake_aidlc_home" \
  /bin/sh "$root/install.sh" 2>&1)
conflict_status=$?
set -e
[ "$conflict_status" -ne 0 ] || fail "command directory conflict exits non-zero"
assert_eq "$conflict_output" \
  "aidlc-flow: command path is a directory: $conflict_root/bin/aidlc-flow" \
  "command directory conflict reports a clear error"
[ ! -e "$conflict_root/share" ] || fail "command directory conflict does not change data home"
conflict_after=$(find "$conflict_root" -type f -exec cksum {} \; | sort)
assert_eq "$conflict_after" "$conflict_before" \
  "command directory conflict preserves existing directory contents"

relative_data_case="$tmp/relative-data-case"
mkdir -p "$relative_data_case"
set +e
relative_data_output=$(cd "$relative_data_case" && \
  AIDLC_FLOW_DATA_HOME=relative-share AIDLC_FLOW_BIN_HOME="$relative_data_case/bin" \
  AIDLC_FLOW_BUN="$fake_bun" AIDLC_FLOW_AIDLC_HOME="$fake_aidlc_home" \
  /bin/sh "$root/install.sh" 2>&1)
relative_data_status=$?
set -e
assert_eq "$relative_data_status" "2" "relative data home exits with usage error"
assert_eq "$relative_data_output" \
  "aidlc-flow: AIDLC_FLOW_DATA_HOME must be an absolute path: relative-share" \
  "relative data home reports a clear error"
[ ! -e "$relative_data_case/relative-share" ] || fail "relative data home is not created"
[ ! -e "$relative_data_case/bin" ] || fail "bin home is unchanged after relative data rejection"

relative_bin_case="$tmp/relative-bin-case"
mkdir -p "$relative_bin_case"
set +e
relative_bin_output=$(cd "$relative_bin_case" && \
  AIDLC_FLOW_DATA_HOME="$relative_bin_case/share" AIDLC_FLOW_BIN_HOME=relative-bin \
  AIDLC_FLOW_BUN="$fake_bun" AIDLC_FLOW_AIDLC_HOME="$fake_aidlc_home" \
  /bin/sh "$root/install.sh" 2>&1)
relative_bin_status=$?
set -e
assert_eq "$relative_bin_status" "2" "relative bin home exits with usage error"
assert_eq "$relative_bin_output" \
  "aidlc-flow: AIDLC_FLOW_BIN_HOME must be an absolute path: relative-bin" \
  "relative bin home reports a clear error"
[ ! -e "$relative_bin_case/share" ] || fail "data home is unchanged after relative bin rejection"
[ ! -e "$relative_bin_case/relative-bin" ] || fail "relative bin home is not created"

printf 'PASS: install-test\n'
