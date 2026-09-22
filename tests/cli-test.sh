#!/bin/sh
set -eu
. "$(dirname "$0")/testlib.sh"

repo_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
set +e
output=$("$repo_root/bin/aidlc-flow" 2>&1)
status=$?
set -e

assert_eq "$status" "2" "missing command exits with usage error"
assert_contains "$output" "Usage: aidlc-flow init --harness codex|claude" "usage is printed"
printf 'PASS: cli-test\n'
