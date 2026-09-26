#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/testlib.sh"
. "$SCRIPT_DIR/plugin-testlib.sh"

REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
PLUGIN_ROOT=${PLUGIN_ROOT_OVERRIDE:-"$REPO_ROOT/plugins/flow"}
CONTRIBUTIONS_ROOT="$PLUGIN_ROOT/contributions"

list_dir=$(new_tmpdir)
contribution_list="$list_dir/contributions.list"
target_list="$list_dir/targets.list"
find "$CONTRIBUTIONS_ROOT" -type f -name '*.md' -print | sort > "$contribution_list"
[ -s "$contribution_list" ] || fail "no scope contributions found"
: > "$target_list"

while IFS= read -r contribution; do
  frontmatter=$(plugin_frontmatter "$contribution") || fail "scope contribution must have closed frontmatter: $contribution"
  target=$(plugin_yaml_scalar "$frontmatter" target)
  plugin=$(plugin_yaml_scalar "$frontmatter" plugin)
  scopes=$(plugin_yaml_nested_list "$frontmatter" adds scopes)

  case "$target" in
    workspace-scaffold) expected="$CONTRIBUTIONS_ROOT/initialization/workspace-scaffold.md" ;;
    workspace-detection) expected="$CONTRIBUTIONS_ROOT/initialization/workspace-detection.md" ;;
    state-init) expected="$CONTRIBUTIONS_ROOT/initialization/state-init.md" ;;
    code-generation) expected="$CONTRIBUTIONS_ROOT/construction/code-generation.md" ;;
    build-and-test) expected="$CONTRIBUTIONS_ROOT/construction/build-and-test.md" ;;
    *) fail "scope contribution has forbidden or missing target '$target': $contribution" ;;
  esac

  assert_eq "$contribution" "$expected" "scope contribution path must match target"
  assert_eq "$plugin" flow "scope contribution plugin: $contribution"
  assert_eq "$scopes" flow-slice "scope contribution adds.scopes: $contribution"
  printf '%s\n' "$target" >> "$target_list"
done < "$contribution_list"

for required_target in workspace-scaffold workspace-detection state-init code-generation build-and-test; do
  count=$(awk -v target="$required_target" '$0 == target { count++ } END { print count + 0 }' "$target_list")
  assert_eq "$count" 1 "scope contribution target must occur exactly once: $required_target"
done

printf 'PASS: slice-routing-test\n'
