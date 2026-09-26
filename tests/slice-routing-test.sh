#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/testlib.sh"

REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
CONTRIBUTIONS_ROOT="$REPO_ROOT/plugins/flow/contributions"

for target in \
  initialization/workspace-scaffold \
  initialization/workspace-detection \
  initialization/state-init \
  construction/code-generation \
  construction/build-and-test
do
  contribution="$CONTRIBUTIONS_ROOT/$target.md"
  [ -f "$contribution" ] || fail "missing scope contribution: $target"

  target_slug=${target##*/}
  content=$(cat "$contribution")
  assert_contains "$content" "target: $target_slug" "scope contribution target: $target"
  assert_contains "$content" 'plugin: flow' "scope contribution plugin: $target"
  assert_contains "$content" '    - flow-slice' "scope contribution scope: $target"
done

for forbidden_stage in units-generation delivery-planning domain-design functional-design; do
  forbidden=$(find "$CONTRIBUTIONS_ROOT" -name "$forbidden_stage.md" -print -quit)
  [ -z "$forbidden" ] || fail "horizontal planning stages must not join the slice scope"
done

printf 'PASS: slice-routing-test\n'
