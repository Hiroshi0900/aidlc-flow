#!/bin/sh
set -eu
. "$(dirname "$0")/testlib.sh"
root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
. "$root/lib/common.sh"

tmp=$(new_tmpdir)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
project="$tmp/project"
mkdir -p "$project/aidlc/spaces"
printf '%s\n' 'default' > "$project/aidlc/active-space"
src="$tmp/source.md"
dst="$tmp/destination.md"
printf '%s\n' 'managed' > "$src"

project_dir=caller-project
pointer=caller-pointer
space=caller-space
intents=caller-intents
destination=caller-destination
source_file=caller-source
key=caller-key
begin=caller-begin
end=caller-end
begins=caller-begins
ends=caller-ends

require_git_repo "$root"
active_space "$project" >/dev/null
refuse_active_workflow "$project"
merge_managed_block "$dst" "$src" collision

assert_eq "$project_dir" "caller-project" "project_dir is not overwritten"
assert_eq "$pointer" "caller-pointer" "pointer is not overwritten"
assert_eq "$space" "caller-space" "space is not overwritten"
assert_eq "$intents" "caller-intents" "intents is not overwritten"
assert_eq "$destination" "caller-destination" "destination is not overwritten"
assert_eq "$source_file" "caller-source" "source_file is not overwritten"
assert_eq "$key" "caller-key" "key is not overwritten"
assert_eq "$begin" "caller-begin" "begin is not overwritten"
assert_eq "$end" "caller-end" "end is not overwritten"
assert_eq "$begins" "caller-begins" "begins is not overwritten"
assert_eq "$ends" "caller-ends" "ends is not overwritten"
printf 'PASS: common-variable-test\n'
