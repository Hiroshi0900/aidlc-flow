#!/bin/sh
set -eu
. "$(dirname "$0")/testlib.sh"
root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
. "$root/lib/common.sh"

tmp=$(new_tmpdir)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
project="$tmp/project"
mkdir -p "$project"

assert_eq "$(active_space "$project")" "default" "missing active-space uses default"

mkdir -p "$project/aidlc"
printf '%s\n' 'team-1._' > "$project/aidlc/active-space"
assert_eq "$(active_space "$project")" "team-1._" "valid active-space is returned"

for invalid_space in . .. 'bad/name' ''; do
  printf '%s\n' "$invalid_space" > "$project/aidlc/active-space"
  set +e
  invalid_output=$( (active_space "$project") 2>&1)
  invalid_status=$?
  set -e
  assert_eq "$invalid_status" "1" "invalid active-space '$invalid_space' is rejected"
  assert_contains "$invalid_output" "invalid AI-DLC active space" "invalid active-space has a diagnostic"
done

printf 'PASS: active-space-test\n'
