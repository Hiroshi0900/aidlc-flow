#!/bin/sh
set -eu
. "$(dirname "$0")/testlib.sh"
root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
. "$root/lib/common.sh"

tmp=$(new_tmpdir)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

require_git_repo "$root"

non_git="$tmp/non-git"
mkdir -p "$non_git"
set +e
non_git_output=$( (require_git_repo "$non_git") 2>&1)
non_git_status=$?
set -e
assert_eq "$non_git_status" "2" "non-Git directory is rejected"
assert_contains "$non_git_output" "not a Git repository" "non-Git rejection has a diagnostic"

bare_repo="$tmp/bare.git"
git init --bare "$bare_repo" >/dev/null 2>&1
set +e
bare_output=$( (require_git_repo "$bare_repo") 2>&1)
bare_status=$?
set -e
assert_eq "$bare_status" "2" "bare repository is rejected"
assert_contains "$bare_output" "not a Git repository" "bare repository rejection has a diagnostic"
printf 'PASS: git-repo-test\n'
