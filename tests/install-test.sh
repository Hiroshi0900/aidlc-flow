#!/bin/sh
set -eu
. "$(dirname "$0")/testlib.sh"

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
tmp=$(new_tmpdir)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

AIDLC_FLOW_DATA_HOME="$tmp/share" AIDLC_FLOW_BIN_HOME="$tmp/bin" \
  /bin/sh "$root/install.sh"

installed_cli="$tmp/share/aidlc-flow/bin/aidlc-flow"
command_path="$tmp/bin/aidlc-flow"
[ -x "$installed_cli" ] || fail "installed CLI is executable"
[ -L "$command_path" ] || fail "command path is a symlink"

set +e
output=$("$command_path" 2>&1)
status=$?
set -e

assert_eq "$status" "2" "installed CLI without arguments exits with usage error"
assert_eq "$output" "Usage: aidlc-flow init --harness codex|claude [--project-dir PATH]" \
  "installed CLI prints exact usage"

before=$(find "$tmp" -type f -exec cksum {} \; | sort)
AIDLC_FLOW_DATA_HOME="$tmp/share" AIDLC_FLOW_BIN_HOME="$tmp/bin" \
  /bin/sh "$root/install.sh"
after=$(find "$tmp" -type f -exec cksum {} \; | sort)
assert_eq "$after" "$before" "reinstall is idempotent"

conflict_root="$tmp/conflict"
mkdir -p "$conflict_root/bin/aidlc-flow"
printf 'keep\n' >"$conflict_root/bin/aidlc-flow/sentinel"
conflict_before=$(find "$conflict_root" -type f -exec cksum {} \; | sort)
set +e
conflict_output=$(AIDLC_FLOW_DATA_HOME="$conflict_root/share" \
  AIDLC_FLOW_BIN_HOME="$conflict_root/bin" /bin/sh "$root/install.sh" 2>&1)
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
