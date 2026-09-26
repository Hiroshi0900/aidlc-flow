#!/bin/sh
set -eu
. "$(dirname "$0")/testlib.sh"

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
tmp=$(new_tmpdir)
tmp=$(CDPATH= cd -- "$tmp" && pwd -P)
case ${AIDLC_FLOW_KEEP_INTEGRATION_TMP:-false} in
  true) ;;
  false) trap 'rm -rf "$tmp"' EXIT HUP INT TERM ;;
  *) fail "AIDLC_FLOW_KEEP_INTEGRATION_TMP must be true or false" ;;
esac

runtime=${AIDLC_FLOW_AIDLC_HOME:-"$HOME/.local/share/aidlc/versions/2.9.0"}
source_aidlc_data=$(CDPATH= cd -- "$runtime/../.." && pwd -P)
real_aidlc=$(command -v aidlc) || fail "AI-DLC 2.9.0 is required"
real_bun=$(command -v bun) || fail "Bun is required"
real_codex=$(command -v codex) || fail "Codex CLI with plugin support is required"
real_claude=$(command -v claude) || fail "Claude Code with plugin support is required"

assert_eq "$("$real_aidlc" --version)" "aidlc 2.9.0 (runtime 2.9.0)" \
  "integration test requires the pinned AI-DLC release"
"$real_bun" --version >/dev/null
"$real_codex" plugin --help >/dev/null
"$real_claude" plugin --help >/dev/null

install_data="$tmp/install/share"
install_bin="$tmp/install/bin"
AIDLC_FLOW_DATA_HOME="$install_data" AIDLC_FLOW_BIN_HOME="$install_bin" \
  AIDLC_FLOW_AIDLC_HOME="$runtime" "$root/install.sh" >/dev/null
installed=${AIDLC_FLOW_INTEGRATION_BINARY:-"$install_bin/aidlc-flow"}
case "$installed" in /*) ;; *) fail "integration binary must be an absolute path" ;; esac
[ -x "$installed" ] || fail "integration aidlc-flow binary is executable"

# Clone the machine install so doctor verifies the real local AI-DLC contract
# without giving the test write access to the user's installation.
isolated_aidlc_data="$tmp/machine-data/aidlc"
mkdir -p "$(dirname "$isolated_aidlc_data")"
cp -cR "$source_aidlc_data" "$isolated_aidlc_data"

expected_order='workspace-scaffold
workspace-detection
state-init
flow-slice-contract
code-generation
build-and-test
flow-slice-review
flow-merge-readiness'

assert_scope_graph() {
  scope_path=$1
  grid_path=$2
  assert_eq "$(cat "$scope_path")" "$expected_order" "flow-slice graph order"
  python3 - "$grid_path" <<'PY' || exit 1
import json
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    stages = json.load(source)["flow-slice"]["stages"]
for skipped in ("units-generation", "delivery-planning", "domain-design"):
    if stages.get(skipped) != "SKIP":
        raise SystemExit(f"flow-slice does not skip {skipped}: {stages.get(skipped)!r}")
PY
}

run_harness() {
  harness=$1
  project="$tmp/$harness-project"
  isolated_home="$tmp/$harness-home"
  codex_home="$isolated_home/.codex"
  claude_config="$isolated_home/.claude"
  mkdir -p "$project" "$isolated_home/.local/bin" "$isolated_home/.local/share" \
    "$codex_home" "$claude_config"
  ln -s "$isolated_aidlc_data" "$isolated_home/.local/share/aidlc"
  aidlc_for_harness="$isolated_home/.local/bin/aidlc"
  sed "s#$source_aidlc_data#$isolated_home/.local/share/aidlc#g" \
    "$HOME/.local/bin/aidlc" > "$aidlc_for_harness"
  chmod +x "$aidlc_for_harness"
  printf '%s\n' "$isolated_home/.local/share/aidlc/versions/2.9.0/aidlc" > \
    "$isolated_aidlc_data/active-executable"
  git -C "$project" init -q
  git -C "$project" config user.email smoke@example.invalid
  git -C "$project" config user.name "AI-DLC smoke"
  printf '# integration smoke\n' > "$project/README.md"
  git -C "$project" add README.md
  git -C "$project" commit -qm initial

  HOME="$isolated_home" CODEX_HOME="$codex_home" CLAUDE_CONFIG_DIR="$claude_config" \
    PATH="$isolated_home/.local/bin:$PATH" AIDLC_FLOW_AIDLC_HOME="$runtime" \
    "$installed" init --harness "$harness" --project-dir "$project" </dev/null

  harness_dir=.$harness
  engine() {
    (cd "$project" && HOME="$isolated_home" CODEX_HOME="$codex_home" \
      CLAUDE_CONFIG_DIR="$claude_config" AIDLC_HARNESS_DIR="$harness_dir" \
      AIDLC_HARNESS_NAME="$harness" PATH="$isolated_home/.local/bin:$PATH" \
      "$aidlc_for_harness" engine "$@" </dev/null)
  }

  engine graph validate-scope flow-slice >/dev/null
  engine graph scope flow-slice > "$tmp/$harness-scope.txt"
  assert_scope_graph "$tmp/$harness-scope.txt" \
    "$project/$harness_dir/tools/data/scope-grid.json"
  scope_table=$(engine gen scope-table)
  assert_contains "$scope_table" "flow-slice" "$harness scope table contains flow-slice"

  if ! HOME="$isolated_home" CODEX_HOME="$codex_home" CLAUDE_CONFIG_DIR="$claude_config" \
    PATH="$isolated_home/.local/bin:$PATH" \
    "$aidlc_for_harness" doctor --project-dir "$project" --quiet </dev/null
  then
    HOME="$isolated_home" CODEX_HOME="$codex_home" CLAUDE_CONFIG_DIR="$claude_config" \
      PATH="$isolated_home/.local/bin:$PATH" \
      "$aidlc_for_harness" doctor --project-dir "$project" --verbose </dev/null
    fail "$harness AI-DLC doctor failed"
  fi

  directive="$tmp/$harness-create-directive.json"
  engine orchestrate next --scope flow-slice -- "local slice smoke test" > "$directive"
  python3 - "$directive" "$project" "$aidlc_for_harness" <<'PY'
import json
import re
import shlex
import subprocess
import sys

directive_path, project, aidlc = sys.argv[1:]
with open(directive_path, encoding="utf-8") as source:
    directive = json.load(source)
if directive.get("kind") != "print":
    raise SystemExit(f"expected intent-create print directive: {directive!r}")
message = directive.get("message")
if not isinstance(message, str):
    raise SystemExit("intent-create directive has no message")
match = re.search(r"`([^`]*\bintent create\b[^`]*)`", message)
if not match:
    raise SystemExit(f"directive does not name intent create: {message}")
argv = shlex.split(match.group(1))
if len(argv) < 4 or argv[:4] != ["aidlc", "engine", "intent", "create"]:
    raise SystemExit(f"unexpected intent-create command: {argv!r}")
argv[0] = aidlc
for index, item in enumerate(argv):
    if item == "<2-3 word kebab essence>":
        argv[index] = "local-slice-smoke"
argv.extend(["--project-dir", project])
subprocess.run(argv, cwd=project, check=True)
PY

  first="$tmp/$harness-first-directive.json"
  engine orchestrate next --scope flow-slice > "$first"
  python3 - "$first" <<'PY' || exit 1
import json
import sys
with open(sys.argv[1], encoding="utf-8") as source:
    directive = json.load(source)
if directive.get("kind") not in ("load-steering", "run-stage") or directive.get("stage") != "flow-slice-contract":
    raise SystemExit(f"unexpected first workflow directive: {directive!r}")
PY

  engine status > "$tmp/$harness-status.txt"
  evidence=$(find "$project/aidlc" -maxdepth 8 -type f -print0 | xargs -0 grep -h -E \
    'flow-slice|workspace-scaffold|local slice smoke test')
  assert_contains "$evidence" "flow-slice" "$harness state records the flow-slice scope"
  assert_contains "$evidence" "flow-slice-contract" "$harness state or audit records the first post-init stage"
  assert_contains "$(cat "$tmp/$harness-status.txt")" "flow-slice" \
    "$harness status reports the flow-slice scope"

  case "$harness" in
    codex) [ -f "$project/.agents/skills/flow-slice/SKILL.md" ] || \
      fail "Codex flow-slice runner exists" ;;
    claude) [ -f "$project/.claude/skills/flow-slice/SKILL.md" ] || \
      fail "Claude flow-slice runner exists" ;;
  esac
}

run_harness codex
run_harness claude

if [ "${AIDLC_FLOW_KEEP_INTEGRATION_TMP:-false}" = true ]; then
  printf 'EVIDENCE_ROOT: %s\n' "$tmp"
fi
printf 'PASS: plugin-integration-test\n'
