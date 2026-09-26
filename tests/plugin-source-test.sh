#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/testlib.sh"

REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
PLUGIN_ROOT="$REPO_ROOT/plugins/flow"
OLD_PLUGIN_ROOT="$REPO_ROOT/plugins/aidlc-flow-slice"

[ ! -e "$OLD_PLUGIN_ROOT" ] || fail "legacy plugin root must not exist: plugins/aidlc-flow-slice"

for source_file in \
  .aidlc-plugin/plugin.json \
  scopes/flow-slice.md \
  stages/inception/flow-slice-contract.md \
  stages/construction/flow-slice-review.md \
  stages/construction/flow-merge-readiness.md \
  contributions/initialization/workspace-scaffold.md \
  contributions/initialization/workspace-detection.md \
  contributions/initialization/state-init.md \
  contributions/construction/code-generation.md \
  contributions/construction/build-and-test.md
do
  [ -f "$PLUGIN_ROOT/$source_file" ] || fail "missing plugin source: $source_file"
done

manifest=$(cat "$PLUGIN_ROOT/.aidlc-plugin/plugin.json")
assert_contains "$manifest" '"name": "flow"' "manifest name matches root"
assert_contains "$manifest" '"version": "0.1.0"' "manifest version"
assert_contains "$manifest" '"dependencies": ["core"]' "manifest core dependency"
assert_contains "$manifest" '"stages": "stages/"' "manifest stage path"
assert_contains "$manifest" '"scopes": "scopes/"' "manifest scope path"
assert_contains "$manifest" '"overlays": "contributions/"' "manifest uses official overlay key"
case "$manifest" in
  *'"contributions"'*) fail "manifest must not use unsupported contributions key" ;;
esac

scope=$(cat "$PLUGIN_ROOT/scopes/flow-slice.md")
assert_contains "$scope" 'name: flow-slice' "scope uses plugin prefix"
assert_contains "$scope" 'plugin: flow' "scope owner"
assert_contains "$scope" 'testStrategy: Standard' "scope"
assert_contains "$scope" 'review_cap: none' "scope"
assert_contains "$scope" 'change_control: relaxed' "scope"
assert_contains "$scope" 'learnings: off' "scope"
assert_contains "$scope" 'summary_confirmation: off' "scope"
grep -q '^name: flow-slice$' "$PLUGIN_ROOT/scopes/flow-slice.md" || fail "scope name must equal filename stem"
grep -q '^plugin: flow$' "$PLUGIN_ROOT/scopes/flow-slice.md" || fail "scope owner must equal manifest name"

assert_stage() {
  relative_path=$1
  expected_slug=$2
  expected_artifact=$3
  stage=$(cat "$PLUGIN_ROOT/$relative_path")
  assert_contains "$stage" "slug: $expected_slug" "stage slug: $relative_path"
  assert_contains "$stage" 'plugin: flow' "stage owner: $relative_path"
  assert_contains "$stage" "  - $expected_artifact" "stage artifact namespace: $relative_path"
  assert_contains "$stage" '  - flow-slice' "stage scope: $relative_path"
}

assert_stage stages/inception/flow-slice-contract.md flow-slice-contract flow-slice-contract
assert_stage stages/construction/flow-slice-review.md flow-slice-review flow-slice-review
assert_stage stages/construction/flow-merge-readiness.md flow-merge-readiness flow-merge-readiness

find "$PLUGIN_ROOT/stages" -type f -name '*.md' -print | while IFS= read -r stage_file; do
  stage_slug=${stage_file##*/}
  stage_slug=${stage_slug%.md}
  grep -q "^slug: $stage_slug$" "$stage_file" || fail "stage slug must equal filename: $stage_file"
  grep -q '^plugin: flow$' "$stage_file" || fail "stage owner must equal manifest name: $stage_file"
  awk '
    $0 == "---" { delimiter++; if (delimiter == 2) exit; next }
    delimiter == 1 && ($0 == "produces:" || $0 == "optional_produces:") {
      in_produces = 1
      next
    }
    delimiter == 1 && in_produces && /^  - / {
      artifact = $0
      sub(/^  - /, "", artifact)
      if (artifact !~ /^flow-/) exit 1
      next
    }
    delimiter == 1 && in_produces { in_produces = 0 }
  ' "$stage_file" || fail "produced artifact must use flow- namespace: $stage_file"
done

contract=$(cat "$PLUGIN_ROOT/stages/inception/flow-slice-contract.md")
assert_contains "$contract" '  - flow-requirements' "contract artifact namespace"
assert_contains "$contract" 'outputs: flow-requirements.md and flow-slice-contract.md' "contract output names"

slice_review=$(cat "$PLUGIN_ROOT/stages/construction/flow-slice-review.md")
assert_contains "$slice_review" 'lead_agent: aidlc-architecture-reviewer-agent' "slice review"
assert_contains "$slice_review" '  - artifact: flow-slice-contract' "slice review consumes plugin artifact"
assert_contains "$slice_review" '  - artifact: code-summary' "slice review consumes core artifact"
assert_contains "$slice_review" '  - artifact: build-test-results' "slice review consumes core test artifact"
assert_contains "$slice_review" '  - build-and-test' "slice review requires core stage"
assert_contains "$slice_review" 'outputs: flow-slice-review.md' "slice review output name"
case "$slice_review" in
  *'reviewer:'*) fail "slice review: must not declare reviewer" ;;
esac

merge_readiness=$(cat "$PLUGIN_ROOT/stages/construction/flow-merge-readiness.md")
assert_contains "$merge_readiness" '  - artifact: flow-slice-review' "merge readiness consumes plugin artifact"
assert_contains "$merge_readiness" '  - artifact: build-test-results' "merge readiness consumes core artifact"
assert_contains "$merge_readiness" '  - flow-slice-review' "merge readiness requires plugin stage"
assert_contains "$merge_readiness" 'outputs: flow-merge-readiness.md' "merge readiness output name"

printf 'PASS: plugin-source-test\n'
