#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/testlib.sh"
. "$SCRIPT_DIR/plugin-testlib.sh"

REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
PLUGIN_ROOT=${PLUGIN_ROOT_OVERRIDE:-"$REPO_ROOT/plugins/flow"}
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

python3 - "$PLUGIN_ROOT/.aidlc-plugin/plugin.json" <<'PY' || fail "plugin manifest must exactly match the official contract"
import json
import sys

expected = {
    "name": "flow",
    "version": "0.1.1",
    "description": "Deliver one vertical slice through test, review, and merge readiness.",
    "author": {"name": "aidlc-flow"},
    "dependencies": ["core"],
    "aidlc": {
        "contributes": {
            "stages": "stages/",
            "scopes": "scopes/",
            "overlays": "contributions/",
        }
    },
}

with open(sys.argv[1], encoding="utf-8") as manifest_file:
    actual = json.load(manifest_file)

if not isinstance(actual, dict) or actual != expected:
    raise SystemExit("manifest content differs from expected contract")
PY

scope_frontmatter=$(plugin_frontmatter "$PLUGIN_ROOT/scopes/flow-slice.md") || fail "scope must have closed YAML frontmatter"
assert_eq "$(plugin_yaml_scalar "$scope_frontmatter" name)" flow-slice "scope name must equal filename stem"
assert_eq "$(plugin_yaml_scalar "$scope_frontmatter" plugin)" flow "scope owner must equal manifest name"
assert_eq "$(plugin_yaml_scalar "$scope_frontmatter" depth)" Minimal "scope depth"
assert_eq "$(plugin_yaml_scalar "$scope_frontmatter" testStrategy)" Standard "scope test strategy"
assert_eq "$(plugin_yaml_scalar "$scope_frontmatter" runner)" true "scope runner"
assert_eq "$(plugin_yaml_scalar "$scope_frontmatter" review_cap)" none "scope review cap"
assert_eq "$(plugin_yaml_scalar "$scope_frontmatter" change_control)" relaxed "scope change control"
assert_eq "$(plugin_yaml_scalar "$scope_frontmatter" sensors)" on "scope sensors"
assert_eq "$(plugin_yaml_scalar "$scope_frontmatter" learnings)" off "scope learnings"
assert_eq "$(plugin_yaml_scalar "$scope_frontmatter" summary_confirmation)" off "scope summary confirmation"

assert_stage() {
  relative_path=$1
  expected_slug=$2
  expected_artifacts=$3
  stage_frontmatter=$(plugin_frontmatter "$PLUGIN_ROOT/$relative_path") || fail "stage must have closed YAML frontmatter: $relative_path"
  assert_eq "$(plugin_yaml_scalar "$stage_frontmatter" slug)" "$expected_slug" "stage slug: $relative_path"
  assert_eq "$(plugin_yaml_scalar "$stage_frontmatter" plugin)" flow "stage owner: $relative_path"
  assert_eq "$(plugin_yaml_list "$stage_frontmatter" produces)" "$expected_artifacts" "stage artifacts: $relative_path"
  assert_eq "$(plugin_yaml_list "$stage_frontmatter" scopes)" flow-slice "stage scope: $relative_path"
}

assert_stage stages/inception/flow-slice-contract.md flow-slice-contract 'flow-requirements
flow-slice-contract'
assert_stage stages/construction/flow-slice-review.md flow-slice-review flow-slice-review
assert_stage stages/construction/flow-merge-readiness.md flow-merge-readiness flow-merge-readiness

find "$PLUGIN_ROOT/stages" -type f -name '*.md' -print | while IFS= read -r stage_file; do
  stage_slug=${stage_file##*/}
  stage_slug=${stage_slug%.md}
  stage_frontmatter=$(plugin_frontmatter "$stage_file") || fail "stage must have closed YAML frontmatter: $stage_file"
  assert_eq "$(plugin_yaml_scalar "$stage_frontmatter" slug)" "$stage_slug" "stage slug must equal filename"
  assert_eq "$(plugin_yaml_scalar "$stage_frontmatter" plugin)" flow "stage owner must equal manifest name"
  produced=$(plugin_yaml_list "$stage_frontmatter" produces)
  optional_produced=$(plugin_yaml_list "$stage_frontmatter" optional_produces)
  [ -n "$produced" ] || fail "stage must declare a produced artifact: $stage_file"
  assert_eq "$(plugin_yaml_list "$stage_frontmatter" scopes)" flow-slice "stage must belong only to flow-slice"
  printf '%s\n%s\n' "$produced" "$optional_produced" | while IFS= read -r artifact; do
    [ -z "$artifact" ] && continue
    case "$artifact" in
      flow-*) ;;
      *) fail "produced artifact must use flow- namespace: $stage_file" ;;
    esac
  done
done

contract_frontmatter=$(plugin_frontmatter "$PLUGIN_ROOT/stages/inception/flow-slice-contract.md")
assert_eq "$(plugin_yaml_scalar "$contract_frontmatter" outputs)" 'flow-requirements.md and flow-slice-contract.md under the engine-resolved record directory' "contract output names"

python3 - "$PLUGIN_ROOT/contributions/construction/code-generation.md" <<'PY' || \
  fail "code-generation contribution must connect approved contract artifacts and prose"
import re
import sys

text = open(sys.argv[1], encoding="utf-8").read()
match = re.match(r"^---\n(.*?)\n---\n(.*)$", text, re.S)
if not match:
    raise SystemExit("contribution frontmatter is missing")
frontmatter, body = match.groups()
adds = re.search(r"^adds:\n(.*?)(?=^[a-z_]+:|\Z)", frontmatter, re.M | re.S)
if not adds:
    raise SystemExit("adds block is missing")
consumes = re.findall(
    r"^    - artifact: ([a-z0-9-]+)\n      required: (true|false)$",
    adds.group(1),
    re.M,
)
if consumes != [("flow-requirements", "true"), ("flow-slice-contract", "true")]:
    raise SystemExit(f"unexpected required consumes: {consumes!r}")
fragments = re.findall(
    r"^  - anchor: (\S+)\n    order: (\d+)$", frontmatter, re.M
)
if fragments != [("after-step:1", "100")]:
    raise SystemExit(f"unexpected fragments: {fragments!r}")
for required in (
    "## fragment: after-step:1",
    "flow-requirements.md",
    "flow-slice-contract.md",
    "Acceptance Criteria",
    "Boundary Test",
    "Merge Safety",
    "TDD",
):
    if required not in body:
        raise SystemExit(f"contribution body is missing {required!r}")
PY

slice_review_frontmatter=$(plugin_frontmatter "$PLUGIN_ROOT/stages/construction/flow-slice-review.md")
assert_eq "$(plugin_yaml_scalar "$slice_review_frontmatter" lead_agent)" aidlc-architecture-reviewer-agent "slice review lead agent"
assert_eq "$(plugin_yaml_object_list_field "$slice_review_frontmatter" consumes artifact)" 'flow-slice-contract
code-summary
build-test-results' "slice review consumed artifacts"
assert_eq "$(plugin_yaml_list "$slice_review_frontmatter" requires_stage)" build-and-test "slice review requires core stage"
assert_eq "$(plugin_yaml_scalar "$slice_review_frontmatter" outputs)" 'flow-slice-review.md under the engine-resolved record directory' "slice review output name"
assert_eq "$(plugin_yaml_scalar "$slice_review_frontmatter" reviewer)" '' "slice review must not declare reviewer"

merge_readiness_frontmatter=$(plugin_frontmatter "$PLUGIN_ROOT/stages/construction/flow-merge-readiness.md")
assert_eq "$(plugin_yaml_object_list_field "$merge_readiness_frontmatter" consumes artifact)" 'flow-slice-review
build-test-results' "merge readiness consumed artifacts"
assert_eq "$(plugin_yaml_list "$merge_readiness_frontmatter" requires_stage)" flow-slice-review "merge readiness requires plugin stage"
assert_eq "$(plugin_yaml_scalar "$merge_readiness_frontmatter" outputs)" 'flow-merge-readiness.md under the engine-resolved record directory' "merge readiness output name"

readme=$(cat "$REPO_ROOT/README.md")
assert_contains "$readme" '`flow-requirements`と`flow-slice-contract`をrequired input' \
  "README documents the contract artifact handoff"
assert_contains "$readme" '`requirements`と`unit-of-work`はexpected fallback' \
  "README documents the two exact core fallbacks"
assert_contains "$readme" 'code-generation → build-and-test → flow-slice-review → flow-merge-readiness' \
  "README documents the verified delivery-stage transition range"

printf 'PASS: plugin-source-test\n'
