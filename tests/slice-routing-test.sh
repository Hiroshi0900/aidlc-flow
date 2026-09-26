#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/testlib.sh"

REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
PLUGIN_ROOT=${PLUGIN_ROOT_OVERRIDE:-"$REPO_ROOT/plugins/flow"}
CONTRIBUTIONS_ROOT="$PLUGIN_ROOT/contributions"

has_closed_frontmatter() {
  awk '
    NR == 1 && $0 == "---" { opened = 1; next }
    opened && $0 == "---" { closed = 1; exit }
    END { exit !(opened && closed) }
  ' "$1"
}

frontmatter_scalar() {
  file=$1
  key=$2
  awk -v key="$key" '
    NR == 1 && $0 == "---" { in_frontmatter = 1; next }
    in_frontmatter && $0 == "---" { exit }
    in_frontmatter && index($0, key ": ") == 1 {
      sub("^" key ": ", "")
      print
    }
  ' "$file"
}

frontmatter_added_scopes() {
  file=$1
  awk '
    NR == 1 && $0 == "---" { in_frontmatter = 1; next }
    in_frontmatter && $0 == "---" { exit }
    in_frontmatter && $0 == "adds:" { in_adds = 1; next }
    in_adds && $0 == "  scopes:" { in_scopes = 1; next }
    in_scopes && /^    - / {
      sub(/^    - /, "")
      print
      next
    }
    in_scopes && $0 !~ /^    / { in_scopes = 0 }
    in_adds && $0 !~ /^  / { in_adds = 0; in_scopes = 0 }
  ' "$file"
}

contribution_files=$(find "$CONTRIBUTIONS_ROOT" -type f -name '*.md' -print | sort)
[ -n "$contribution_files" ] || fail "no scope contributions found"

for contribution in $contribution_files; do
  has_closed_frontmatter "$contribution" || fail "scope contribution must have closed frontmatter: $contribution"
  target=$(frontmatter_scalar "$contribution" target)
  plugin=$(frontmatter_scalar "$contribution" plugin)
  scopes=$(frontmatter_added_scopes "$contribution")

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
done

for required_target in workspace-scaffold workspace-detection state-init code-generation build-and-test; do
  count=0
  for contribution in $contribution_files; do
    target=$(frontmatter_scalar "$contribution" target)
    if [ "$target" = "$required_target" ]; then
      count=$((count + 1))
    fi
  done
  assert_eq "$count" 1 "scope contribution target must occur exactly once: $required_target"
done

printf 'PASS: slice-routing-test\n'
