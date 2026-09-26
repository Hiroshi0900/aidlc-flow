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
    if [ "${AIDLC_FLOW_FAKE_BARRIER:-}" = validate ]; then
      printf 'ready\n' >"$AIDLC_FLOW_FAKE_READY_FIFO"
      IFS= read -r release <"$AIDLC_FLOW_FAKE_RELEASE_FIFO"
      [ "$release" = release ] || exit 77
    fi
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
assert_eq "$(cat "$tmp/share/aidlc-flow/.aidlc-flow-install")" \
  'schema=1
owner=aidlc-flow' "install ownership marker"
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

printf 'keep unknown top-level file\n' >"$tmp/share/aidlc-flow/user-sentinel"
mkdir -p "$tmp/share/aidlc-flow.new"
printf 'do not touch fixed collision\n' >"$tmp/share/aidlc-flow.new/sentinel"
AIDLC_FLOW_DATA_HOME="$tmp/share" AIDLC_FLOW_BIN_HOME="$tmp/bin" \
  AIDLC_FLOW_BUN="$fake_bun" AIDLC_FLOW_AIDLC_HOME="$fake_aidlc_home" \
  /bin/sh "$root/install.sh"
assert_eq "$(cat "$tmp/share/aidlc-flow/user-sentinel")" \
  "keep unknown top-level file" "reinstall preserves unknown top-level files"
assert_eq "$(cat "$tmp/share/aidlc-flow.new/sentinel")" \
  "do not touch fixed collision" "reinstall does not touch fixed staging collision"

concurrent_root="$tmp/concurrent"
mkdir -p "$concurrent_root"
mkfifo "$concurrent_root/ready" "$concurrent_root/release"
AIDLC_FLOW_DATA_HOME="$concurrent_root/share" \
  AIDLC_FLOW_BIN_HOME="$concurrent_root/bin" \
  AIDLC_FLOW_BUN="$fake_bun" AIDLC_FLOW_AIDLC_HOME="$fake_aidlc_home" \
  AIDLC_FLOW_FAKE_BARRIER=validate \
  AIDLC_FLOW_FAKE_READY_FIFO="$concurrent_root/ready" \
  AIDLC_FLOW_FAKE_RELEASE_FIFO="$concurrent_root/release" \
  /bin/sh "$root/install.sh" >"$concurrent_root/first.out" 2>&1 &
first_install_pid=$!
IFS= read -r barrier_ready <"$concurrent_root/ready"
assert_eq "$barrier_ready" ready "first concurrent install reaches deterministic barrier"
set +e
second_concurrent_output=$(AIDLC_FLOW_DATA_HOME="$concurrent_root/share" \
  AIDLC_FLOW_BIN_HOME="$concurrent_root/bin" \
  AIDLC_FLOW_BUN="$fake_bun" AIDLC_FLOW_AIDLC_HOME="$fake_aidlc_home" \
  /bin/sh "$root/install.sh" 2>&1)
second_concurrent_status=$?
set -e
printf 'release\n' >"$concurrent_root/release"
set +e
wait "$first_install_pid"
first_concurrent_status=$?
set -e
assert_eq "$first_concurrent_status" 0 "first concurrent install completes after release"
[ "$second_concurrent_status" -ne 0 ] || fail "second concurrent install exits non-zero"
assert_contains "$second_concurrent_output" "installation is already in progress" \
  "second concurrent install reports busy lock"
[ -f "$concurrent_root/share/aidlc-flow/.aidlc-flow-install" ] ||
  fail "first concurrent install leaves a complete owned destination"
[ -L "$concurrent_root/bin/aidlc-flow" ] && [ -e "$concurrent_root/bin/aidlc-flow" ] ||
  fail "first concurrent install leaves a non-dangling command link"
[ ! -e "$concurrent_root/share/.aidlc-flow-install.lock" ] ||
  fail "successful concurrent install releases its lock"

stale_lock_root="$tmp/stale-lock"
mkdir -p "$stale_lock_root/share/.aidlc-flow-install.lock"
set +e
stale_lock_output=$(AIDLC_FLOW_DATA_HOME="$stale_lock_root/share" \
  AIDLC_FLOW_BIN_HOME="$stale_lock_root/bin" \
  AIDLC_FLOW_BUN="$fake_bun" AIDLC_FLOW_AIDLC_HOME="$fake_aidlc_home" \
  /bin/sh "$root/install.sh" 2>&1)
stale_lock_status=$?
set -e
[ "$stale_lock_status" -ne 0 ] || fail "stale install lock exits non-zero"
assert_contains "$stale_lock_output" "if no installer is running, inspect lock" \
  "stale install lock reports actionable guidance"
[ -d "$stale_lock_root/share/.aidlc-flow-install.lock" ] ||
  fail "installer does not remove an unowned stale lock"
[ ! -e "$stale_lock_root/bin" ] || fail "busy install does not create bin home"
[ ! -e "$stale_lock_root/share/aidlc-flow" ] ||
  fail "busy install does not create destination"

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
staging_leaks=$(find "$tmp/share" -maxdepth 1 -type d -name '.aidlc-flow.new.*' -print)
[ -z "$staging_leaks" ] || fail "failed projection build cleans its staging directory"

fault_bin="$tmp/fault-bin"
mkdir -p "$fault_bin"
real_mv=$(command -v mv)
real_ln=$(command -v ln)
real_chmod=$(command -v chmod)
cat >"$fault_bin/mv" <<'SH'
#!/bin/sh
set -eu
source_path=$1
source_name=${source_path##*/}
if [ "${AIDLC_FLOW_FAULT_MODE:-}" = signal ] &&
  { [ "$source_name" = bin.new ] || [ "$source_name" = aidlc-flow.new ] ||
    [ "${source_name#.aidlc-flow.new.}" != "$source_name" ]; }; then
  "$AIDLC_FLOW_REAL_MV" "$@"
  kill -TERM "$PPID"
  exit 0
fi
exec "$AIDLC_FLOW_REAL_MV" "$@"
SH
cat >"$fault_bin/ln" <<'SH'
#!/bin/sh
set -eu
case "${AIDLC_FLOW_FAULT_MODE:-}" in
  link-failure)
    marker=$AIDLC_FLOW_FAULT_MARKER
    if [ ! -e "$marker" ]; then
      : >"$marker"
      "$AIDLC_FLOW_REAL_LN" "$@"
      exit 91
    fi
    ;;
esac
exec "$AIDLC_FLOW_REAL_LN" "$@"
SH
cat >"$fault_bin/chmod" <<'SH'
#!/bin/sh
set -eu
[ "${AIDLC_FLOW_FAULT_MODE:-}" != chmod-failure ] || exit 92
exec "$AIDLC_FLOW_REAL_CHMOD" "$@"
SH
chmod +x "$fault_bin/mv" "$fault_bin/ln" "$fault_bin/chmod"

for managed_directory in bin lib memory plugins plugin-dist; do
  printf 'old %s\n' "$managed_directory" \
    >"$tmp/share/aidlc-flow/$managed_directory/old-install-sentinel"
done
original_command="$tmp/original-command"
printf 'original command target\n' >"$original_command"
rm -f "$command_path"
ln -s "$original_command" "$command_path"
atomic_before=$(find "$tmp/share/aidlc-flow" -type f -exec cksum {} \; | sort)
command_before=$(readlink "$command_path")
set +e
late_failure_output=$(PATH="$fault_bin:$PATH" AIDLC_FLOW_FAULT_MODE=link-failure \
  AIDLC_FLOW_FAULT_MARKER="$tmp/link-failed" AIDLC_FLOW_REAL_MV="$real_mv" \
  AIDLC_FLOW_REAL_LN="$real_ln" AIDLC_FLOW_REAL_CHMOD="$real_chmod" \
  AIDLC_FLOW_DATA_HOME="$tmp/share" AIDLC_FLOW_BIN_HOME="$tmp/bin" \
  AIDLC_FLOW_BUN="$fake_bun" AIDLC_FLOW_AIDLC_HOME="$fake_aidlc_home" \
  /bin/sh "$root/install.sh" 2>&1)
late_failure_status=$?
set -e
[ "$late_failure_status" -ne 0 ] || fail "late command-link failure exits non-zero"
atomic_after=$(find "$tmp/share/aidlc-flow" -type f -exec cksum {} \; | sort)
assert_eq "$atomic_after" "$atomic_before" \
  "late command-link failure restores the complete previous install tree"
assert_eq "$(readlink "$command_path")" "$command_before" \
  "late command-link failure restores the previous command link"

initial_failure_root="$tmp/initial-failure"
set +e
initial_failure_output=$(PATH="$fault_bin:$PATH" AIDLC_FLOW_FAULT_MODE=chmod-failure \
  AIDLC_FLOW_REAL_MV="$real_mv" AIDLC_FLOW_REAL_LN="$real_ln" \
  AIDLC_FLOW_REAL_CHMOD="$real_chmod" \
  AIDLC_FLOW_DATA_HOME="$initial_failure_root/share" \
  AIDLC_FLOW_BIN_HOME="$initial_failure_root/bin" \
  AIDLC_FLOW_BUN="$fake_bun" AIDLC_FLOW_AIDLC_HOME="$fake_aidlc_home" \
  /bin/sh "$root/install.sh" 2>&1)
initial_failure_status=$?
set -e
[ "$initial_failure_status" -ne 0 ] || fail "initial staging chmod failure exits non-zero"
[ ! -e "$initial_failure_root/share/aidlc-flow" ] ||
  fail "failed initial install leaves no incomplete destination"
initial_staging_leaks=$(find "$initial_failure_root/share" -maxdepth 1 -type d \
  -name '.aidlc-flow.new.*' -print)
[ -z "$initial_staging_leaks" ] || fail "failed initial install cleans the staging tree"
[ ! -e "$initial_failure_root/bin/aidlc-flow" ] ||
  fail "failed initial install leaves no command link"

signal_before=$(find "$tmp/share/aidlc-flow" -type f -exec cksum {} \; | sort)
set +e
signal_output=$(PATH="$fault_bin:$PATH" AIDLC_FLOW_FAULT_MODE=signal \
  AIDLC_FLOW_REAL_MV="$real_mv" AIDLC_FLOW_REAL_LN="$real_ln" \
  AIDLC_FLOW_REAL_CHMOD="$real_chmod" \
  AIDLC_FLOW_DATA_HOME="$tmp/share" AIDLC_FLOW_BIN_HOME="$tmp/bin" \
  AIDLC_FLOW_BUN="$fake_bun" AIDLC_FLOW_AIDLC_HOME="$fake_aidlc_home" \
  /bin/sh "$root/install.sh" 2>&1)
signal_status=$?
set -e
[ "$signal_status" -ne 0 ] || fail "TERM during destination swap exits non-zero"
case "$signal_output" in
  *"Installed aidlc-flow"*) fail "TERM stops installation before success reporting" ;;
esac
signal_after=$(find "$tmp/share/aidlc-flow" -type f -exec cksum {} \; | sort)
assert_eq "$signal_after" "$signal_before" \
  "TERM during destination swap restores the complete previous install tree"
assert_eq "$(readlink "$command_path")" "$command_before" \
  "TERM during destination swap preserves the previous command link"
[ ! -e "$tmp/share/.aidlc-flow-install.lock" ] ||
  fail "TERM rollback releases the owned install lock"

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

file_conflict_root="$tmp/file-conflict"
mkdir -p "$file_conflict_root/bin"
printf 'keep regular command\n' >"$file_conflict_root/bin/aidlc-flow"
file_conflict_before=$(cksum "$file_conflict_root/bin/aidlc-flow")
set +e
file_conflict_output=$(AIDLC_FLOW_DATA_HOME="$file_conflict_root/share" \
  AIDLC_FLOW_BIN_HOME="$file_conflict_root/bin" \
  AIDLC_FLOW_BUN="$fake_bun" AIDLC_FLOW_AIDLC_HOME="$fake_aidlc_home" \
  /bin/sh "$root/install.sh" 2>&1)
file_conflict_status=$?
set -e
[ "$file_conflict_status" -ne 0 ] || fail "regular command conflict exits non-zero"
assert_contains "$file_conflict_output" "command path is not a symbolic link" \
  "regular command conflict reports a clear error"
assert_eq "$(cksum "$file_conflict_root/bin/aidlc-flow")" "$file_conflict_before" \
  "regular command conflict preserves the existing file"
[ ! -e "$file_conflict_root/share" ] ||
  fail "regular command conflict does not change data home"

unowned_root="$tmp/unowned-destination"
mkdir -p "$unowned_root/share/aidlc-flow"
printf 'keep unowned tree\n' >"$unowned_root/share/aidlc-flow/sentinel"
unowned_before=$(find "$unowned_root/share/aidlc-flow" -type f -exec cksum {} \; | sort)
set +e
unowned_output=$(AIDLC_FLOW_DATA_HOME="$unowned_root/share" \
  AIDLC_FLOW_BIN_HOME="$unowned_root/bin" \
  AIDLC_FLOW_BUN="$fake_bun" AIDLC_FLOW_AIDLC_HOME="$fake_aidlc_home" \
  /bin/sh "$root/install.sh" 2>&1)
unowned_status=$?
set -e
[ "$unowned_status" -ne 0 ] || fail "unowned destination exits non-zero"
assert_contains "$unowned_output" "existing install destination is not owned by aidlc-flow" \
  "unowned destination reports a clear error"
unowned_after=$(find "$unowned_root/share/aidlc-flow" -type f -exec cksum {} \; | sort)
assert_eq "$unowned_after" "$unowned_before" "unowned destination is preserved"
[ ! -e "$unowned_root/bin" ] || fail "unowned destination does not create bin home"

legacy_root="$tmp/legacy-destination"
mkdir -p "$legacy_root/share/aidlc-flow/bin" \
  "$legacy_root/share/aidlc-flow/lib" "$legacy_root/share/aidlc-flow/memory"
cp "$root/bin/aidlc-flow" "$legacy_root/share/aidlc-flow/bin/aidlc-flow"
printf 'keep legacy top-level file\n' >"$legacy_root/share/aidlc-flow/legacy-sentinel"
AIDLC_FLOW_DATA_HOME="$legacy_root/share" AIDLC_FLOW_BIN_HOME="$legacy_root/bin" \
  AIDLC_FLOW_BUN="$fake_bun" AIDLC_FLOW_AIDLC_HOME="$fake_aidlc_home" \
  /bin/sh "$root/install.sh"
assert_eq "$(cat "$legacy_root/share/aidlc-flow/legacy-sentinel")" \
  "keep legacy top-level file" "legacy install preserves unknown top-level files"
assert_eq "$(cat "$legacy_root/share/aidlc-flow/.aidlc-flow-install")" \
  'schema=1
owner=aidlc-flow' "legacy install is migrated to ownership marker"

for linked_managed_directory in bin lib memory; do
  linked_case_root="$tmp/legacy-linked-$linked_managed_directory"
  linked_destination="$linked_case_root/share/aidlc-flow"
  linked_external="$linked_case_root/external-$linked_managed_directory"
  mkdir -p "$linked_destination" "$linked_external"
  for managed_directory in bin lib memory; do
    if [ "$managed_directory" != "$linked_managed_directory" ]; then
      mkdir -p "$linked_destination/$managed_directory"
    fi
  done
  if [ "$linked_managed_directory" = bin ]; then
    cp "$root/bin/aidlc-flow" "$linked_external/aidlc-flow"
  else
    cp "$root/bin/aidlc-flow" "$linked_destination/bin/aidlc-flow"
  fi
  printf 'keep external %s\n' "$linked_managed_directory" \
    >"$linked_external/sentinel"
  ln -s "$linked_external" "$linked_destination/$linked_managed_directory"
  linked_destination_before=$(find "$linked_destination" -type f -exec cksum {} \; | sort)
  linked_external_before=$(find "$linked_external" -type f -exec cksum {} \; | sort)
  linked_target_before=$(readlink "$linked_destination/$linked_managed_directory")
  set +e
  linked_output=$(AIDLC_FLOW_DATA_HOME="$linked_case_root/share" \
    AIDLC_FLOW_BIN_HOME="$linked_case_root/bin-home" \
    AIDLC_FLOW_BUN="$fake_bun" AIDLC_FLOW_AIDLC_HOME="$fake_aidlc_home" \
    /bin/sh "$root/install.sh" 2>&1)
  linked_status=$?
  set -e
  [ "$linked_status" -ne 0 ] ||
    fail "linked legacy $linked_managed_directory exits non-zero"
  assert_contains "$linked_output" "existing install destination is not owned by aidlc-flow" \
    "linked legacy $linked_managed_directory reports a clear error"
  linked_destination_after=$(find "$linked_destination" -type f -exec cksum {} \; | sort)
  linked_external_after=$(find "$linked_external" -type f -exec cksum {} \; | sort)
  assert_eq "$linked_destination_after" "$linked_destination_before" \
    "linked legacy $linked_managed_directory preserves destination files"
  assert_eq "$linked_external_after" "$linked_external_before" \
    "linked legacy $linked_managed_directory preserves external files"
  [ -L "$linked_destination/$linked_managed_directory" ] ||
    fail "linked legacy $linked_managed_directory preserves managed symlink"
  assert_eq "$(readlink "$linked_destination/$linked_managed_directory")" \
    "$linked_target_before" "linked legacy $linked_managed_directory preserves symlink target"
  [ ! -e "$linked_case_root/bin-home" ] ||
    fail "linked legacy $linked_managed_directory leaves command path unchanged"
  [ ! -e "$linked_case_root/share/.aidlc-flow-install.lock" ] ||
    fail "linked legacy $linked_managed_directory leaves no lock"
  linked_temporary_leaks=$(find "$linked_case_root/share" -maxdepth 1 -type d \
    \( -name '.aidlc-flow.new.*' -o -name '.aidlc-flow.backup.*' \) -print)
  [ -z "$linked_temporary_leaks" ] ||
    fail "linked legacy $linked_managed_directory leaves no temporary directories"
done

invalid_marker_root="$tmp/invalid-marker"
mkdir -p "$invalid_marker_root/share/aidlc-flow/bin" \
  "$invalid_marker_root/share/aidlc-flow/lib" "$invalid_marker_root/share/aidlc-flow/memory"
cp "$root/bin/aidlc-flow" "$invalid_marker_root/share/aidlc-flow/bin/aidlc-flow"
printf 'schema=2\nowner=someone-else\n' \
  >"$invalid_marker_root/share/aidlc-flow/.aidlc-flow-install"
invalid_marker_before=$(find "$invalid_marker_root/share/aidlc-flow" -type f \
  -exec cksum {} \; | sort)
set +e
invalid_marker_output=$(AIDLC_FLOW_DATA_HOME="$invalid_marker_root/share" \
  AIDLC_FLOW_BIN_HOME="$invalid_marker_root/bin" \
  AIDLC_FLOW_BUN="$fake_bun" AIDLC_FLOW_AIDLC_HOME="$fake_aidlc_home" \
  /bin/sh "$root/install.sh" 2>&1)
invalid_marker_status=$?
set -e
[ "$invalid_marker_status" -ne 0 ] || fail "invalid ownership marker exits non-zero"
assert_contains "$invalid_marker_output" "existing install marker is invalid" \
  "invalid ownership marker reports a clear error"
invalid_marker_after=$(find "$invalid_marker_root/share/aidlc-flow" -type f \
  -exec cksum {} \; | sort)
assert_eq "$invalid_marker_after" "$invalid_marker_before" \
  "invalid ownership marker preserves the existing tree"
[ ! -e "$invalid_marker_root/bin" ] ||
  fail "invalid ownership marker does not create bin home"

destination_file_root="$tmp/destination-file"
mkdir -p "$destination_file_root/share"
printf 'keep destination file\n' >"$destination_file_root/share/aidlc-flow"
destination_file_before=$(cksum "$destination_file_root/share/aidlc-flow")
set +e
destination_file_output=$(AIDLC_FLOW_DATA_HOME="$destination_file_root/share" \
  AIDLC_FLOW_BIN_HOME="$destination_file_root/bin" \
  AIDLC_FLOW_BUN="$fake_bun" AIDLC_FLOW_AIDLC_HOME="$fake_aidlc_home" \
  /bin/sh "$root/install.sh" 2>&1)
destination_file_status=$?
set -e
[ "$destination_file_status" -ne 0 ] || fail "regular destination file exits non-zero"
assert_contains "$destination_file_output" "install destination is not a directory" \
  "regular destination file reports a clear error"
assert_eq "$(cksum "$destination_file_root/share/aidlc-flow")" \
  "$destination_file_before" "regular destination file is preserved"
[ ! -e "$destination_file_root/bin" ] || fail "regular destination file does not create bin home"

destination_link_root="$tmp/destination-link"
mkdir -p "$destination_link_root/share" "$destination_link_root/target"
printf 'keep symlink target\n' >"$destination_link_root/target/sentinel"
ln -s "$destination_link_root/target" "$destination_link_root/share/aidlc-flow"
set +e
destination_link_output=$(AIDLC_FLOW_DATA_HOME="$destination_link_root/share" \
  AIDLC_FLOW_BIN_HOME="$destination_link_root/bin" \
  AIDLC_FLOW_BUN="$fake_bun" AIDLC_FLOW_AIDLC_HOME="$fake_aidlc_home" \
  /bin/sh "$root/install.sh" 2>&1)
destination_link_status=$?
set -e
[ "$destination_link_status" -ne 0 ] || fail "destination symlink exits non-zero"
assert_contains "$destination_link_output" "must not be a symbolic link" \
  "destination symlink reports a clear error"
assert_eq "$(cat "$destination_link_root/target/sentinel")" "keep symlink target" \
  "destination symlink target is preserved"
[ -L "$destination_link_root/share/aidlc-flow" ] || fail "destination symlink is preserved"
[ ! -e "$destination_link_root/bin" ] || fail "destination symlink does not create bin home"

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

temporary_leaks=$(find "$tmp" -type d \( -name '.aidlc-flow.new.*' \
  -o -name '.aidlc-flow.backup.*' \) -print)
[ -z "$temporary_leaks" ] || fail "installer cleans process-specific temporary directories"

printf 'PASS: install-test\n'
