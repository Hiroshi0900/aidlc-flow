#!/bin/sh
set -eu
. "$(dirname "$0")/testlib.sh"
root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
. "$root/lib/common.sh"

tmp=$(new_tmpdir)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

begin_src="$tmp/begin-source.md"
begin_dst="$tmp/begin-destination.md"
printf '%s\n' 'before' '<!-- BEGIN aidlc-flow:reserved -->' 'after' > "$begin_src"
set +e
merge_managed_block "$begin_dst" "$begin_src" reserved >/dev/null 2>&1
begin_status=$?
set -e
assert_eq "$begin_status" "1" "source exact begin marker is rejected"
[ ! -e "$begin_dst" ] || fail "rejected begin marker source must not create destination"

end_src="$tmp/end-source.md"
end_dst="$tmp/end-destination.md"
printf '%s\n' \
  '<!-- BEGIN aidlc-flow:reserved -->' \
  'managed-old' \
  '<!-- END aidlc-flow:reserved -->' \
  'project-owned' > "$end_dst"
end_before=$(cksum "$end_dst")
printf '%s\n' 'managed-new' '<!-- END aidlc-flow:reserved -->' > "$end_src"
set +e
merge_managed_block "$end_dst" "$end_src" reserved >/dev/null 2>&1
end_status=$?
set -e
assert_eq "$end_status" "1" "source exact end marker is rejected"
assert_eq "$(cksum "$end_dst")" "$end_before" "rejected end marker source leaves destination untouched"

inline_src="$tmp/inline-source.md"
inline_dst="$tmp/inline-destination.md"
printf '%s\n' 'owned <!-- BEGIN aidlc-flow:reserved --> text' > "$inline_src"
merge_managed_block "$inline_dst" "$inline_src" reserved
assert_contains "$(cat "$inline_dst")" 'owned <!-- BEGIN aidlc-flow:reserved --> text' "inline source marker text is allowed"
printf 'PASS: memory-source-marker-test\n'
