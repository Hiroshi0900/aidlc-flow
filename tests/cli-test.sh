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

readme=$(cat "$repo_root/README.md")
for required in \
  'AI-DLC 2.9.0' \
  'Bun' \
  './install.sh' \
  'aidlc-flow init --harness codex --project-dir' \
  'aidlc-flow init --harness claude --project-dir' \
  '$flow-slice' \
  '/flow-slice' \
  '1 intent / 1 branch / 1 PR' \
  'feature flag' \
  'push' \
  'PR' \
  'main' \
  'deploy' \
  'local-first' \
  'immutable' \
  'elapsed time' \
  'human interventions' \
  'test failures' \
  'review returns' \
  'changed files and lines' \
  'commit count' \
  'defect discovery stage'
do
  assert_contains "$readme" "$required" "README documents required local workflow guidance"
done
printf 'PASS: cli-test\n'
