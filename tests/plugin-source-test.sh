#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/testlib.sh"

REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
PLUGIN_ROOT="$REPO_ROOT/plugins/aidlc-flow-slice"

for source_file in \
  .aidlc-plugin/plugin.json \
  scopes/aidlc-flow-slice.md \
  stages/inception/slice-contract.md \
  stages/construction/slice-review.md \
  stages/construction/merge-readiness.md
do
  [ -f "$PLUGIN_ROOT/$source_file" ] || fail "missing plugin source: $source_file"
done

manifest=$(cat "$PLUGIN_ROOT/.aidlc-plugin/plugin.json")
assert_contains "$manifest" '"name": "flow-slice"' "plugin manifest"

scope=$(cat "$PLUGIN_ROOT/scopes/aidlc-flow-slice.md")
assert_contains "$scope" 'name: aidlc-flow-slice' "scope"
assert_contains "$scope" 'testStrategy: Standard' "scope"
assert_contains "$scope" 'review_cap: none' "scope"
assert_contains "$scope" 'change_control: relaxed' "scope"
assert_contains "$scope" 'learnings: off' "scope"
assert_contains "$scope" 'summary_confirmation: off' "scope"

slice_review=$(cat "$PLUGIN_ROOT/stages/construction/slice-review.md")
assert_contains "$slice_review" 'lead_agent: aidlc-architecture-reviewer-agent' "slice review"
case "$slice_review" in
  *'reviewer:'*) fail "slice review: must not declare reviewer" ;;
esac

printf 'PASS: plugin-source-test\n'
