#!/bin/sh
set -eu
. "$(dirname "$0")/testlib.sh"
root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
. "$root/lib/common.sh"

tmp=$(new_tmpdir)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
src="$tmp/source.md"
printf '%s\n' 'managed-v1' > "$src"

inline_dst="$tmp/inline.md"
printf '%s\n' \
  'project prefix <!-- BEGIN aidlc-flow:inline --> suffix' \
  'project prefix <!-- END aidlc-flow:inline --> suffix' > "$inline_dst"
merge_managed_block "$inline_dst" "$src" inline
inline_content=$(cat "$inline_dst")
assert_contains "$inline_content" 'project prefix <!-- BEGIN aidlc-flow:inline --> suffix' "inline begin text is preserved"
assert_contains "$inline_content" 'project prefix <!-- END aidlc-flow:inline --> suffix' "inline end text is preserved"
assert_contains "$inline_content" 'managed-v1' "managed block is appended after inline marker text"
inline_begins=$(grep -F -x -c '<!-- BEGIN aidlc-flow:inline -->' "$inline_dst")
inline_ends=$(grep -F -x -c '<!-- END aidlc-flow:inline -->' "$inline_dst")
assert_eq "$inline_begins" "1" "one exact begin marker is appended"
assert_eq "$inline_ends" "1" "one exact end marker is appended"

reverse_dst="$tmp/reverse.md"
printf '%s\n' '<!-- END aidlc-flow:reverse -->' 'owned' '<!-- BEGIN aidlc-flow:reverse -->' > "$reverse_dst"
reverse_before=$(cksum "$reverse_dst")
set +e
merge_managed_block "$reverse_dst" "$src" reverse >/dev/null 2>&1
reverse_status=$?
set -e
assert_eq "$reverse_status" "1" "reversed exact markers are rejected"
assert_eq "$(cksum "$reverse_dst")" "$reverse_before" "reversed markers leave destination untouched"

duplicate_dst="$tmp/duplicate.md"
printf '%s\n' \
  '<!-- BEGIN aidlc-flow:duplicate -->' \
  '<!-- BEGIN aidlc-flow:duplicate -->' \
  '<!-- END aidlc-flow:duplicate -->' > "$duplicate_dst"
duplicate_before=$(cksum "$duplicate_dst")
set +e
merge_managed_block "$duplicate_dst" "$src" duplicate >/dev/null 2>&1
duplicate_status=$?
set -e
assert_eq "$duplicate_status" "1" "duplicate exact markers are rejected"
assert_eq "$(cksum "$duplicate_dst")" "$duplicate_before" "duplicate markers leave destination untouched"
printf 'PASS: memory-marker-validation-test\n'
