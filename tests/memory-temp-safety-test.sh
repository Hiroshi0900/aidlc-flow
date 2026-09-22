#!/bin/sh
set -eu
. "$(dirname "$0")/testlib.sh"
root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
. "$root/lib/common.sh"

tmp=$(new_tmpdir)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
src="$tmp/source.md"
destination_dir="$tmp/memory"
destination="$destination_dir/team.md"
victim="$tmp/victim.md"
mkdir -p "$destination_dir"
printf '%s\n' 'managed-content' > "$src"
printf '%s\n' 'victim-content' > "$victim"
ln -s "$victim" "$destination.new"
legacy_target=$(readlink "$destination.new")

merge_managed_block "$destination" "$src" team
assert_eq "$(cat "$victim")" "victim-content" "legacy temp symlink target is untouched"
[ -L "$destination.new" ] || fail "legacy temp symlink is preserved"
assert_eq "$(readlink "$destination.new")" "$legacy_target" "legacy temp symlink target is unchanged"
assert_contains "$(cat "$destination")" 'managed-content' "merge succeeds beside legacy temp symlink"

failure_dir="$tmp/failure"
fake_bin="$tmp/fake-bin"
mkdir -p "$failure_dir" "$fake_bin"
ln -s /usr/bin/false "$fake_bin/awk"
saved_path=$PATH
PATH="$fake_bin:$PATH"
export PATH
set +e
merge_managed_block "$failure_dir/team.md" "$src" failure >/dev/null 2>&1
failure_status=$?
set -e
PATH=$saved_path
export PATH
assert_eq "$failure_status" "1" "writer failure is reported"
[ ! -e "$failure_dir/team.md" ] || fail "writer failure must not create destination"
failure_leftovers=$(find "$failure_dir" -name '.aidlc-flow.*' -print)
assert_eq "$failure_leftovers" "" "writer failure removes unique temporary file"
printf 'PASS: memory-temp-safety-test\n'
