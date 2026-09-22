#!/bin/sh
set -eu
. "$(dirname "$0")/testlib.sh"
root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
. "$root/lib/common.sh"

tmp=$(new_tmpdir)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
src="$tmp/source.md"
dst="$tmp/memory/team.md"
printf '%s\n' 'rule-v1' > "$src"

merge_managed_block "$dst" "$src" "team"
first=$(cat "$dst")
assert_contains "$first" '<!-- BEGIN aidlc-flow:team -->' "begin marker is written"
assert_contains "$first" 'rule-v1' "managed content is written"

printf '%s\n' 'project-owned' >> "$dst"
printf '%s\n' 'rule-v2' > "$src"
merge_managed_block "$dst" "$src" "team"
second=$(cat "$dst")
assert_contains "$second" 'project-owned' "unmanaged content is preserved"
assert_contains "$second" 'rule-v2' "managed content is updated"

before=$(cksum "$dst")
merge_managed_block "$dst" "$src" "team"
after=$(cksum "$dst")
assert_eq "$after" "$before" "second identical merge is idempotent"

no_newline_src="$tmp/no-newline-source.md"
no_newline_dst="$tmp/memory/no-newline.md"
printf '%s' 'rule-without-newline' > "$no_newline_src"
merge_managed_block "$no_newline_dst" "$no_newline_src" "no-newline"
no_newline_content=$(cat "$no_newline_dst")
assert_contains "$no_newline_content" 'rule-without-newline
<!-- END aidlc-flow:no-newline -->' "end marker starts on its own line"
no_newline_before=$(cksum "$no_newline_dst")
merge_managed_block "$no_newline_dst" "$no_newline_src" "no-newline"
no_newline_after=$(cksum "$no_newline_dst")
assert_eq "$no_newline_after" "$no_newline_before" "no-newline merge is idempotent"

no_newline_append_dst="$tmp/memory/no-newline-append.md"
printf '%s\n' 'project-owned-before-markers' > "$no_newline_append_dst"
merge_managed_block "$no_newline_append_dst" "$no_newline_src" "no-newline-append"
no_newline_append_content=$(cat "$no_newline_append_dst")
assert_contains "$no_newline_append_content" 'rule-without-newline
<!-- END aidlc-flow:no-newline-append -->' "appended end marker starts on its own line"
no_newline_append_before=$(cksum "$no_newline_append_dst")
merge_managed_block "$no_newline_append_dst" "$no_newline_src" "no-newline-append"
no_newline_append_after=$(cksum "$no_newline_append_dst")
assert_eq "$no_newline_append_after" "$no_newline_append_before" "appended no-newline merge is idempotent"

missing_source="$tmp/missing-source.md"
missing_before=$(cksum "$dst")
missing_content_before=$(cat "$dst")
set +e
merge_managed_block "$dst" "$missing_source" "team" >/dev/null 2>&1
missing_status=$?
set -e
missing_after=$(cksum "$dst")
missing_content_after=$(cat "$dst")
assert_eq "$missing_status" "1" "missing source is rejected"
assert_eq "$missing_after" "$missing_before" "missing source leaves existing destination untouched"
assert_eq "$missing_content_after" "$missing_content_before" "missing source preserves existing content"

missing_dst="$tmp/memory/missing.md"
set +e
merge_managed_block "$missing_dst" "$missing_source" "missing" >/dev/null 2>&1
missing_new_status=$?
set -e
assert_eq "$missing_new_status" "1" "missing source for new destination is rejected"
[ ! -e "$missing_dst" ] || fail "missing source must not create a new destination"

printf '%s\n' '<!-- BEGIN aidlc-flow:team -->' > "$tmp/broken.md"
set +e
merge_managed_block "$tmp/broken.md" "$src" "team" >/dev/null 2>&1
status=$?
set -e
assert_eq "$status" "1" "malformed marker is rejected"
assert_eq "$(cat "$tmp/broken.md")" '<!-- BEGIN aidlc-flow:team -->' "malformed file is untouched"
printf 'PASS: memory-merge-test\n'
