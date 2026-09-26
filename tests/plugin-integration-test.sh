#!/bin/sh
set -eu
. "$(dirname "$0")/testlib.sh"

reject_guard_bypass() {
  guard_name=$1
  guard_value=$2
  [ -z "$guard_value" ] || fail "guard bypass environment must be unset: $guard_name"
}

reject_guard_bypass AIDLC_SKIP_HUMAN_PRESENCE_GUARD "${AIDLC_SKIP_HUMAN_PRESENCE_GUARD-}"
reject_guard_bypass AIDLC_SKIP_ARTIFACT_GUARD "${AIDLC_SKIP_ARTIFACT_GUARD-}"
reject_guard_bypass AIDLC_DISABLE_ENSEMBLE_EVIDENCE "${AIDLC_DISABLE_ENSEMBLE_EVIDENCE-}"
reject_guard_bypass AIDLC_DISABLE_SENSORS "${AIDLC_DISABLE_SENSORS-}"
reject_guard_bypass AIDLC_SKIP_SOURCE_FRESHNESS "${AIDLC_SKIP_SOURCE_FRESHNESS-}"
reject_guard_bypass AIDLC_DISABLE_PLAN_APPROVAL_GUARD "${AIDLC_DISABLE_PLAN_APPROVAL_GUARD-}"
reject_guard_bypass AIDLC_DISABLE_REVIEWER_SCOPE_HOOK "${AIDLC_DISABLE_REVIEWER_SCOPE_HOOK-}"
reject_guard_bypass AIDLC_DISABLE_REVIEW_FREEZE_HOOK "${AIDLC_DISABLE_REVIEW_FREEZE_HOOK-}"
reject_guard_bypass AIDLC_SKIP_REVIEWER_GATE_GUARD "${AIDLC_SKIP_REVIEWER_GATE_GUARD-}"
reject_guard_bypass AIDLC_SKIP_REVISION_BACKSTOP "${AIDLC_SKIP_REVISION_BACKSTOP-}"
reject_guard_bypass AIDLC_SKIP_SUMMARY_CONFIRMATION_GUARD "${AIDLC_SKIP_SUMMARY_CONFIRMATION_GUARD-}"

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
tmp=$(new_tmpdir)
tmp=$(CDPATH= cd -- "$tmp" && pwd -P)
case ${AIDLC_FLOW_KEEP_INTEGRATION_TMP:-false} in
  true) ;;
  false) trap 'rm -rf "$tmp"' EXIT HUP INT TERM ;;
  *) fail "AIDLC_FLOW_KEEP_INTEGRATION_TMP must be true or false" ;;
esac

detected_aidlc=$(command -v aidlc) || fail "AI-DLC 2.9.0 is required"
real_aidlc=$(python3 - "$detected_aidlc" <<'PY'
import os, sys
path = os.path.realpath(sys.argv[1])
if not os.path.isabs(path) or not os.path.isfile(path) or os.path.islink(path):
    raise SystemExit("detected AI-DLC launcher is not a canonical regular file")
print(path)
PY
) || fail "unable to canonicalize the detected AI-DLC launcher"
runtime=${AIDLC_FLOW_AIDLC_HOME:-"$(dirname "$(dirname "$real_aidlc")")/share/aidlc/versions/2.9.0"}
runtime=$(CDPATH= cd -- "$runtime" && pwd -P) || fail "AI-DLC runtime is missing"
source_aidlc_data=$(CDPATH= cd -- "$runtime/../.." && pwd -P)
python3 - "$real_aidlc" "$runtime/aidlc" "$source_aidlc_data" <<'PY' || \
  fail "detected AI-DLC command is not the pinned native launcher/target pair"
import os, sys
launcher, target, data = sys.argv[1:]
if not os.path.isfile(target) or os.path.islink(target) or not os.access(target, os.X_OK):
    raise SystemExit("pinned AI-DLC target is missing or unsafe")
text = open(launcher, encoding="utf-8").read()
if "# aidlc-native-launcher-v2" not in text:
    raise SystemExit("detected command is not an AI-DLC native launcher")
for expected in (
    os.path.join(data, "active-executable"),
    os.path.join(data, "active-version"),
    os.path.join(data, "versions"),
):
    if repr(expected) not in text:
        raise SystemExit(f"launcher does not bind the expected runtime path: {expected}")
PY
real_bun=$(command -v bun) || fail "Bun is required"
real_codex=$(command -v codex) || fail "Codex CLI with plugin support is required"
real_claude=$(command -v claude) || fail "Claude Code with plugin support is required"

assert_eq "$("$real_aidlc" --version)" "aidlc 2.9.0 (runtime 2.9.0)" \
  "integration test requires the pinned AI-DLC release"
assert_eq "$("$runtime/aidlc" --version)" "aidlc 2.9.0 (runtime 2.9.0)" \
  "detected launcher target requires the pinned AI-DLC release"
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

verify_intent_state() {
  state_path=$1
  grid_path=$2
  python3 - "$state_path" "$grid_path" <<'PY'
import json
import re
import sys

state_path, grid_path = sys.argv[1:]
text = open(state_path, encoding="utf-8").read()
grid = json.load(open(grid_path, encoding="utf-8"))["flow-slice"]["stages"]

def section(name):
    match = re.search(rf"^## {re.escape(name)}\n(.*?)(?=^## |\Z)", text, re.M | re.S)
    if not match:
        raise SystemExit(f"state section is missing: {name}")
    return match.group(1)

def fields(name):
    return dict(re.findall(r"^- \*\*(.+?)\*\*: *(.*)$", section(name), re.M))

project = fields("Project Information")
summary = fields("Execution Plan Summary")
current = fields("Current Status")
resume = fields("Session Resume Point")
expected_fields = {
    "Scope": (project.get("Scope"), "flow-slice"),
    "Total Stages": (summary.get("Total Stages"), "8"),
    "Completed": (summary.get("Completed"), "3"),
    "In Progress": (summary.get("In Progress"), "flow-slice-contract"),
    "Lifecycle Phase": (current.get("Lifecycle Phase"), "INCEPTION"),
    "Current Stage": (current.get("Current Stage"), "flow-slice-contract"),
    "Next Stage": (current.get("Next Stage"), "code-generation"),
    "Status": (current.get("Status"), "Running"),
    "Last Completed Stage": (resume.get("Last Completed Stage"), "state-init"),
}
for label, (actual, expected) in expected_fields.items():
    if actual != expected:
        raise SystemExit(f"state field {label!r}: expected {expected!r}, got {actual!r}")

rows = {}
for checkbox, stage, mode in re.findall(r"^- \[([ x?RS-])\] ([a-z0-9-]+) — (EXECUTE|SKIP)$", section("Stage Progress"), re.M):
    if stage in rows:
        raise SystemExit(f"duplicate stage state: {stage}")
    rows[stage] = (checkbox, mode)
if set(rows) != set(grid):
    raise SystemExit("state stage set differs from the canonical scope grid")
for stage, mode in grid.items():
    expected_checkbox = "x" if stage in {"workspace-scaffold", "workspace-detection", "state-init"} else "-" if stage == "flow-slice-contract" else " "
    if rows[stage] != (expected_checkbox, mode):
        raise SystemExit(f"unexpected state for {stage}: {rows[stage]!r}")
PY
}

verify_intent_audit() {
  audit_dir=$1
  python3 - "$audit_dir" <<'PY'
import glob
import os
import re
import sys

paths = glob.glob(os.path.join(sys.argv[1], "*.md"))
if not paths:
    raise SystemExit("intent audit file is missing")
events = []
for path in paths:
    for block in re.split(r"\n---\n", open(path, encoding="utf-8").read()):
        fields = dict(re.findall(r"^\*\*(.+?)\*\*: *(.*)$", block, re.M))
        if "Event" in fields:
            events.append(fields)
starts = [event for event in events if event.get("Event") == "WORKFLOW_STARTED"]
if len(starts) != 1 or starts[0].get("Scope") != "flow-slice":
    raise SystemExit("audit does not contain the canonical flow-slice workflow start")
completed = {event.get("Stage") for event in events if event.get("Event") == "STAGE_COMPLETED"}
if completed != {"workspace-scaffold", "workspace-detection", "state-init"}:
    raise SystemExit(f"unexpected completed stages in audit: {sorted(completed)}")
if not any(event.get("Event") == "STAGE_STARTED" and event.get("Stage") == "flow-slice-contract" for event in events):
    raise SystemExit("audit does not start flow-slice-contract")
PY
}

verify_intent_status() {
  status_path=$1
  python3 - "$status_path" <<'PY'
import re
import sys

text = open(sys.argv[1], encoding="utf-8").read()
fields = dict(re.findall(r"^([A-Za-z ]+):\s+(.*?)\s*$", text, re.M))
expected = {
    "Scope": "flow-slice",
    "Phase": "INCEPTION",
    "Current Stage": "Slice Contract (2.10)",
    "Status": "Running",
    "Completion": "3/8 stages (38%)",
    "Last Completed": "state-init",
    "Next Stage": "code-generation",
}
for key, value in expected.items():
    if fields.get(key) != value:
        raise SystemExit(f"status field {key!r}: expected {value!r}, got {fields.get(key)!r}")
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
    "$real_aidlc" > "$aidlc_for_harness"
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

  record_human_turn() {
    response=$1
    printf '{"hook_event_name":"UserPromptSubmit","session_id":"integration-%s","prompt":"%s"}\n' \
      "$harness" "$response" |
      (cd "$project" && HOME="$isolated_home" CODEX_HOME="$codex_home" \
        CLAUDE_CONFIG_DIR="$claude_config" AIDLC_HARNESS_DIR="$harness_dir" \
        AIDLC_HARNESS_NAME="$harness" PATH="$isolated_home/.local/bin:$PATH" \
        "$real_bun" "$project/$harness_dir/hooks/aidlc-record-human-turn.ts")
  }

  finish_steering() {
    directive_path=$1
    while [ "$(python3 - "$directive_path" <<'PY'
import json
import sys

print(json.load(open(sys.argv[1], encoding="utf-8")).get("kind", ""))
PY
    )" = load-steering ]; do
      steering_token=$(python3 - "$directive_path" <<'PY'
import json
import sys

print(json.load(open(sys.argv[1], encoding="utf-8"))["continue_token"])
PY
      )
      engine orchestrate continue "$steering_token" >"$directive_path.next"
      mv "$directive_path.next" "$directive_path"
    done
  }

  approve_stage() {
    stage=$1
    engine orchestrate report --stage "$stage" \
      --result awaiting-approval >"$tmp/$harness-$stage-gate.json"
    engine orchestrate report --stage "$stage" \
      --result approved --user-input Approve >"$tmp/$harness-$stage-before-human.json"
    python3 - "$tmp/$harness-$stage-before-human.json" "$stage" <<'PY' || exit 1
import json
import sys

path, stage = sys.argv[1:]
directive = json.load(open(path, encoding="utf-8"))
message = directive.get("message")
if directive.get("kind") != "error" or not isinstance(message, str) or "no new human reply" not in message:
    raise SystemExit(f"{stage} accepted approval before HUMAN_TURN: {directive!r}")
PY
    record_human_turn Approve
    engine orchestrate report --stage "$stage" \
      --result approved --user-input Approve >"$tmp/$harness-$stage-approved.json"
    python3 - "$tmp/$harness-$stage-gate.json" \
      "$tmp/$harness-$stage-approved.json" "$stage" <<'PY' || exit 1
import json
import sys

gate_path, approved_path, stage = sys.argv[1:]
gate = json.load(open(gate_path, encoding="utf-8"))
approved = json.load(open(approved_path, encoding="utf-8"))
if gate.get("kind") != "print" or approved.get("kind") != "done":
    raise SystemExit(f"{stage} approval did not complete through official reports: {gate!r}, {approved!r}")
PY
  }

  graph_stderr="$tmp/$harness-graph-stderr.txt"
  engine graph validate-scope flow-slice >/dev/null 2>"$graph_stderr"
  python3 - "$graph_stderr" <<'PY' || exit 1
import re
import sys

lines = [line.strip() for line in open(sys.argv[1], encoding="utf-8") if line.strip()]
expected = {
    'Stage "code-generation" requires artifact "unit-of-work" whose producer(s) [units-generation] are not on the "flow-slice" path.',
    'Stage "code-generation" requires artifact "requirements" whose producer(s) [requirements-analysis] are not on the "flow-slice" path.',
}
actual = set()
for line in lines:
    match = re.fullmatch(r"\[advisory\] (.*) Ensure existing artifact is current\.", line)
    if not match:
        raise SystemExit(f"unexpected graph validation stderr: {line!r}")
    actual.add(match.group(1))
if actual != expected or len(lines) != 2:
    raise SystemExit(f"expected exactly the zero-Unit fallback advisories, got: {lines!r}")
PY
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

  # Exercise the official ensemble guard on a stock mob stage without changing
  # the approved flow-slice graph (whose support-bearing build stage is inline).
  ensemble_project="$tmp/$harness-ensemble-project"
  cp -cR "$project" "$ensemble_project"
  ensemble_engine() {
    (cd "$ensemble_project" && HOME="$isolated_home" CODEX_HOME="$codex_home" \
      CLAUDE_CONFIG_DIR="$claude_config" AIDLC_HARNESS_DIR="$harness_dir" \
      AIDLC_HARNESS_NAME="$harness" PATH="$isolated_home/.local/bin:$PATH" \
      "$aidlc_for_harness" engine "$@" </dev/null)
  }
  ensemble_engine intent create --scope classic \
    --arguments "ensemble guard control" --label support-guard >/dev/null
  ensemble_directive="$tmp/$harness-ensemble-directive.json"
  ensemble_engine orchestrate next --stage user-stories --single >"$ensemble_directive"
  while [ "$(python3 - "$ensemble_directive" <<'PY'
import json
import sys

print(json.load(open(sys.argv[1], encoding="utf-8")).get("kind", ""))
PY
  )" = load-steering ]; do
    ensemble_token=$(python3 - "$ensemble_directive" <<'PY'
import json
import sys

print(json.load(open(sys.argv[1], encoding="utf-8"))["continue_token"])
PY
    )
    ensemble_engine orchestrate continue "$ensemble_token" >"$ensemble_directive.next"
    mv "$ensemble_directive.next" "$ensemble_directive"
  done
  python3 - "$ensemble_directive" <<'PY' || exit 1
import json
import sys

directive = json.load(open(sys.argv[1], encoding="utf-8"))
if directive.get("kind") != "run-stage" or directive.get("stage") != "user-stories":
    raise SystemExit(f"official ensemble control did not start user-stories: {directive!r}")
PY
  ensemble_engine orchestrate report --single --stage user-stories \
    --result completed >"$tmp/$harness-ensemble-missing-contribution.json"
  python3 - "$tmp/$harness-ensemble-missing-contribution.json" <<'PY' || exit 1
import json
import sys

directive = json.load(open(sys.argv[1], encoding="utf-8"))
message = directive.get("message")
if directive.get("kind") != "error" or not isinstance(message, str) or "collaborator notes are missing" not in message:
    raise SystemExit(f"official ensemble guard accepted missing support contributions: {directive!r}")
PY

  composed_code_generation="$project/$harness_dir/aidlc-common/stages/construction/code-generation.md"
  python3 - "$composed_code_generation" "$harness" \
    "$root/plugins/flow/contributions/construction/code-generation.md" \
    "$project/$harness_dir/tools/data/plugin-contrib-flow.json" <<'PY' || exit 1
import json
import re
import sys

path, harness, contribution_path, sidecar_path = sys.argv[1:]
text = open(path, encoding="utf-8").read()
match = re.match(r"^---\n(.*?)\n---\n(.*)$", text, re.S)
if not match:
    raise SystemExit(f"{harness} composed code-generation frontmatter is missing")
frontmatter, body = match.groups()
consumes = re.findall(
    r"^  - artifact: ([a-z0-9-]+)\n    required: (true|false)(?:\n    conditional_on: \w+)?$",
    frontmatter,
    re.M,
)
if len(consumes) != len(set(consumes)):
    raise SystemExit(f"{harness} composed stage contains duplicate consume entries: {consumes!r}")
for artifact in ("flow-requirements", "flow-slice-contract"):
    if consumes.count((artifact, "true")) != 1:
        raise SystemExit(f"{harness} composed stage lost required consume {artifact!r}")
fragment = re.search(
    r"<!-- plugin:flow:after-step:1:100:([0-9a-f]{8}) -->\n(.*?)\n<!-- /plugin:flow:after-step:1:100:\1 -->",
    body,
    re.S,
)
if not fragment:
    raise SystemExit(f"{harness} composed stage lost exact matching fragment sentinels")

source = open(contribution_path, encoding="utf-8").read()
source_match = re.search(r"^## fragment: after-step:1\s*$\n(.*)\Z", source, re.M | re.S)
if not source_match:
    raise SystemExit("source contribution has no unique after-step:1 prose block")
source_prose = source_match.group(1).strip()
if fragment.group(2) != source_prose:
    raise SystemExit(f"{harness} composed fragment prose differs from its source contribution")

# Official compose hashes JavaScript UTF-16 code units with 32-bit FNV-1a.
fnv = 0x811C9DC5
utf16 = source_prose.encode("utf-16-le")
for index in range(0, len(utf16), 2):
    fnv ^= int.from_bytes(utf16[index:index + 2], "little")
    fnv = (fnv * 0x01000193) & 0xFFFFFFFF
expected_hash = f"{fnv:08x}"
if fragment.group(1) != expected_hash:
    raise SystemExit(
        f"{harness} fragment sentinel hash differs from official FNV-1a: "
        f"{fragment.group(1)!r} != {expected_hash!r}"
    )

sidecar = json.load(open(sidecar_path, encoding="utf-8"))
record = sidecar.get("code-generation")
if not isinstance(record, dict):
    raise SystemExit(f"{harness} contribution sidecar has no code-generation record")
expected_fragments = [{"anchor": "after-step:1", "order": 100, "hash": expected_hash}]
if record.get("fragments") != expected_fragments:
    raise SystemExit(
        f"{harness} contribution sidecar fragment record differs from composed prose: "
        f"{record.get('fragments')!r}"
    )
for required in (
    "flow-requirements.md",
    "flow-slice-contract.md",
    "Acceptance Criteria",
    "Boundary Test",
    "Merge Safety",
    "TDD",
):
    if required not in fragment.group(2):
        raise SystemExit(f"{harness} composed fragment is missing {required!r}")
step_1 = body.find("### Step 1: Read All Unit Artifacts")
step_2 = body.find("### Step 2: PART 1")
if not step_1 < fragment.start() < step_2:
    raise SystemExit(f"{harness} contract fragment is not immediately after Step 1")
PY

  compose_drops="$project/aidlc/spaces/default/intents/.aidlc-engine/hooks-health/plugin-compose-flow.drops"
  python3 - "$compose_drops" "$harness" <<'PY' || exit 1
import sys

path, harness = sys.argv[1:]
lines = open(path, encoding="utf-8").read().splitlines() if __import__("os").path.exists(path) else []
unexpected = [
    line for line in lines
    if "[degraded]" in line
    or "contribution to code-generation" in line
    or 'contribution "code-generation.md"' in line
]
if unexpected:
    raise SystemExit(f"{harness} compose dropped the intended code-generation merge: {unexpected!r}")
PY

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

  intent_list="$tmp/$harness-intents.json"
  engine intent list --json > "$intent_list"
  intent_dir=$(python3 - "$intent_list" <<'PY'
import json, re, sys
value = json.load(open(sys.argv[1], encoding="utf-8"))
space = value.get("space")
active = value.get("active")
intents = value.get("intents")
if not isinstance(space, str) or not re.fullmatch(r"[a-z0-9-]+", space):
    raise SystemExit("intent list has an unsafe space")
matches = [item for item in intents or [] if isinstance(item, dict) and item.get("active") is True and item.get("dirName") == active]
if len(matches) != 1:
    raise SystemExit("intent list does not identify exactly one canonical active intent")
directory = matches[0].get("dirName")
if not isinstance(directory, str) or not re.fullmatch(r"[a-z0-9-]+", directory):
    raise SystemExit("intent list has an unsafe active intent directory")
print(f"{space}/{directory}")
PY
  ) || fail "$harness intent list did not identify the created intent"
  intent_root="$project/aidlc/spaces/${intent_dir%/*}/intents/${intent_dir#*/}"
  [ -d "$intent_root" ] && [ ! -L "$intent_root" ] || fail "$harness canonical intent directory is unsafe"

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

  engine status >"$tmp/$harness-contract-status.txt"
  verify_intent_state "$intent_root/aidlc-state.md" \
    "$project/$harness_dir/tools/data/scope-grid.json"
  verify_intent_audit "$intent_root/audit"
  verify_intent_status "$tmp/$harness-contract-status.txt"

  for mutation in scope current-stage; do
    mutated_state="$tmp/$harness-$mutation-state.md"
    cp "$intent_root/aidlc-state.md" "$mutated_state"
    case "$mutation" in
      scope) perl -pi -e 's/^(- \*\*Scope\*\*: )flow-slice$/${1}classic/' "$mutated_state" ;;
      current-stage) perl -pi -e 's/^(- \*\*Current Stage\*\*: )flow-slice-contract$/${1}code-generation/' "$mutated_state" ;;
    esac
    set +e
    verify_intent_state "$mutated_state" \
      "$project/$harness_dir/tools/data/scope-grid.json" >/dev/null 2>&1
    mutation_status=$?
    set -e
    [ "$mutation_status" -ne 0 ] || \
      fail "$harness state verifier accepts mutated $mutation while audit remains valid"
  done

  engine orchestrate report --stage flow-slice-contract \
    --result awaiting-approval >"$tmp/$harness-contract-missing-artifact.json"
  python3 - "$tmp/$harness-contract-missing-artifact.json" <<'PY' || exit 1
import json
import sys

directive = json.load(open(sys.argv[1], encoding="utf-8"))
if (
    directive.get("kind") != "ask"
    or directive.get("ask_type") != "guard-recovery"
    or directive.get("stage") != "flow-slice-contract"
    or directive.get("reason_codes") != ["REQUIRED_ARTIFACTS_MISSING"]
):
    raise SystemExit(f"contract gate accepted missing required artifacts: {directive!r}")
PY

  contract_dir="$intent_root/inception/flow-slice-contract"
  mkdir -p "$contract_dir"
  for artifact in flow-requirements flow-slice-contract; do
    artifact_path="$contract_dir/$artifact.md"
    {
      printf '# Approved Slice Contract\n\n'
      printf '## Acceptance Criteria\n\n- AC-1: The local slice is observable.\n\n'
      printf '## Boundary Test\n\n- The integration boundary fails before implementation.\n\n'
      printf '## Merge Safety\n\n- Safe in one pull request without a feature flag.\n'
    } >"$artifact_path"
  done

  approve_stage flow-slice-contract

  code_generation_directive="$tmp/$harness-code-generation-directive.json"
  engine orchestrate next --scope flow-slice >"$code_generation_directive"
  finish_steering "$code_generation_directive"
  python3 - "$code_generation_directive" "$intent_root" "$project" <<'PY' || exit 1
import json
import os
import sys

directive_path, intent_root, project = sys.argv[1:]
directive = json.load(open(directive_path, encoding="utf-8"))
if directive.get("kind") != "run-stage" or directive.get("stage") != "code-generation":
    raise SystemExit(f"unexpected post-contract directive: {directive!r}")
expected_consumes = [
    os.path.relpath(
        os.path.join(intent_root, "inception", "flow-slice-contract", f"{name}.md"),
        project,
    ).replace(os.sep, "/")
    for name in ("flow-requirements", "flow-slice-contract")
]
consumes = directive.get("consumes")
if not isinstance(consumes, list) or any(not isinstance(path, str) for path in consumes):
    raise SystemExit(f"code-generation consumes has an unexpected schema: {consumes!r}")
if len(consumes) != len(set(consumes)):
    raise SystemExit(f"code-generation consumes contains duplicate entries: {consumes!r}")
if consumes != expected_consumes:
    raise SystemExit(f"contract artifacts are not the exact inputs: expected {expected_consumes!r}, got {consumes!r}")
for relative, name in zip(consumes, ("flow-requirements", "flow-slice-contract")):
    if os.path.isabs(relative) or os.path.normpath(relative).replace(os.sep, "/") != relative:
        raise SystemExit(f"directive consume path is not canonical project-relative: {relative!r}")
    absolute = os.path.realpath(os.path.join(project, relative))
    expected_absolute = os.path.realpath(
        os.path.join(intent_root, "inception", "flow-slice-contract", f"{name}.md")
    )
    if absolute != expected_absolute or not os.path.isfile(absolute) or os.path.islink(absolute):
        raise SystemExit(f"directive consume does not resolve to its canonical artifact: {relative!r}")

expected_absent = [
    {
        "path": os.path.relpath(
            os.path.join(intent_root, "inception", "units-generation", "unit-of-work.md"),
            project,
        ).replace(os.sep, "/"),
        "expected": True,
    },
    {
        "path": os.path.relpath(
            os.path.join(intent_root, "inception", "requirements-analysis", "requirements.md"),
            project,
        ).replace(os.sep, "/"),
        "expected": True,
    },
]
absent = directive.get("consumes_absent")
if not isinstance(absent, list) or any(not isinstance(entry, dict) for entry in absent):
    raise SystemExit(f"code-generation consumes_absent has an unexpected schema: {absent!r}")
if any(set(entry) != {"path", "expected"} or not isinstance(entry["path"], str) or type(entry["expected"]) is not bool for entry in absent):
    raise SystemExit(f"code-generation consumes_absent entry schema changed: {absent!r}")
absent_keys = [(entry["path"], entry["expected"]) for entry in absent]
if len(absent_keys) != len(set(absent_keys)):
    raise SystemExit(f"code-generation consumes_absent contains duplicate entries: {absent!r}")
if absent != expected_absent:
    raise SystemExit(f"unexpected exact core fallback set: expected {expected_absent!r}, got {absent!r}")
for entry in absent:
    relative = entry["path"]
    if os.path.isabs(relative) or os.path.normpath(relative).replace(os.sep, "/") != relative:
        raise SystemExit(f"absent consume path is not canonical project-relative: {relative!r}")
    absolute = os.path.realpath(os.path.join(project, relative))
    if not absolute.startswith(os.path.realpath(intent_root) + os.sep) or os.path.exists(absolute):
        raise SystemExit(f"expected absent consume is present or escapes the intent: {relative!r}")
PY

  code_generation_dir="$intent_root/construction/code-generation"
  mkdir -p "$code_generation_dir" "$project/src"
  {
    printf '# Code Generation Plan\n\n'
    printf -- '- [x] AC-1: run the boundary test Red, implement Green, then refactor.\n\n'
    printf '## Testing Contract\n\n```json\n{"methodology":"TDD","ordering":"Red, Green, Refactor"}\n```\n'
  } >"$code_generation_dir/code-generation-plan.md"
  {
    printf '# Unit Test Instructions\n\n'
    printf 'Run `/bin/sh tests/boundary-test.sh` for AC-1.\n'
  } >"$code_generation_dir/unit-test-instructions.md"
  {
    printf '# Code Summary\n\n'
    printf 'AC-1 is implemented in `src/slice.js` and verified by the boundary test.\n'
  } >"$code_generation_dir/code-summary.md"
  printf '%s\n' '{"stage":"code-generation","upstream_ids":["AC-1"],"coverage":[{"id":"AC-1","status":"OK","target":"src/slice.js"}],"reverse":[{"id":"AC-1","status":"OK","target":"src/slice.js"}]}' \
    >"$code_generation_dir/traceability.json"
  printf '%s\n' 'export const sliceReady = true;' >"$project/src/slice.js"

  approve_stage code-generation

  build_directive="$tmp/$harness-build-and-test-directive.json"
  engine orchestrate next --scope flow-slice >"$build_directive"
  finish_steering "$build_directive"
  python3 - "$build_directive" <<'PY' || exit 1
import json
import sys

directive = json.load(open(sys.argv[1], encoding="utf-8"))
if directive.get("kind") != "run-stage" or directive.get("stage") != "build-and-test":
    raise SystemExit(f"unexpected build-and-test directive: {directive!r}")
PY

  build_dir="$intent_root/construction/build-and-test"
  mkdir -p "$build_dir/contributions"
  printf '%s\n' '**Collaborator:** aidlc-devsecops-agent' \
    >"$build_dir/contributions/aidlc-devsecops-agent.md"
  for artifact in \
    build-instructions \
    integration-test-instructions \
    performance-test-instructions \
    security-test-instructions \
    build-and-test-summary \
    build-test-results \
    cross-unit-traceability
  do
    {
      printf '# Build and Test Evidence\n\n'
      printf '## Result\n\nPASS for AC-1.\n'
    } >"$build_dir/$artifact.md"
  done

  approve_stage build-and-test

  review_directive="$tmp/$harness-flow-slice-review-directive.json"
  engine orchestrate next --scope flow-slice >"$review_directive"
  finish_steering "$review_directive"
  python3 - "$review_directive" <<'PY' || exit 1
import json
import sys

directive = json.load(open(sys.argv[1], encoding="utf-8"))
if directive.get("kind") != "run-stage" or directive.get("stage") != "flow-slice-review":
    raise SystemExit(f"unexpected flow-slice-review directive: {directive!r}")
PY

  review_dir="$intent_root/construction/flow-slice-review"
  mkdir -p "$review_dir"
  {
    printf '# Slice Review\n\n'
    printf '## Spec Compliance\n\nAC-1 maps to src/slice.js and the passing boundary test.\n\n'
    printf '## Findings\n\nNo Critical or Important findings.\n\n'
    printf '## Verdict\n\nPASS\n'
  } >"$review_dir/flow-slice-review.md"

  approve_stage flow-slice-review

  readiness_directive="$tmp/$harness-flow-merge-readiness-directive.json"
  engine orchestrate next --scope flow-slice >"$readiness_directive"
  finish_steering "$readiness_directive"
  python3 - "$readiness_directive" <<'PY' || exit 1
import json
import sys

directive = json.load(open(sys.argv[1], encoding="utf-8"))
if directive.get("kind") != "run-stage" or directive.get("stage") != "flow-merge-readiness":
    raise SystemExit(f"unexpected flow-merge-readiness directive: {directive!r}")
PY

  engine status > "$tmp/$harness-status.txt"
  python3 - "$intent_root/aidlc-state.md" "$intent_root/audit" \
    "$tmp/$harness-status.txt" "$project/$harness_dir/tools/data/scope-grid.json" \
    "$harness" <<'PY' || exit 1
import glob
import json
import os
import re
import sys

state_path, audit_dir, status_path, grid_path, harness = sys.argv[1:]
state = open(state_path, encoding="utf-8").read()
status = open(status_path, encoding="utf-8").read()

def section(name):
    matches = re.findall(rf"^## {re.escape(name)}\n(.*?)(?=^## |\Z)", state, re.M | re.S)
    if len(matches) != 1:
        raise SystemExit(f"state section {name!r} occurs {len(matches)} times")
    return matches[0]

def unique_fields(text, pattern, owner):
    pairs = re.findall(pattern, text, re.M)
    names = [name for name, _ in pairs]
    duplicates = sorted({name for name in names if names.count(name) > 1})
    if duplicates:
        raise SystemExit(f"{owner} has duplicate fields: {duplicates!r}")
    return dict(pairs)

project_fields = unique_fields(
    section("Project Information"), r"^- \*\*(.+?)\*\*: *(.*)$", "project state"
)
summary = unique_fields(
    section("Execution Plan Summary"), r"^- \*\*(.+?)\*\*: *(.*)$", "summary state"
)
current = unique_fields(
    section("Current Status"), r"^- \*\*(.+?)\*\*: *(.*)$", "current state"
)
resume = unique_fields(
    section("Session Resume Point"), r"^- \*\*(.+?)\*\*: *(.*)$", "resume state"
)
state_expected = {
    "Scope": (project_fields.get("Scope"), "flow-slice"),
    "Total Stages": (summary.get("Total Stages"), "8"),
    "Completed": (summary.get("Completed"), "7"),
    "In Progress": (summary.get("In Progress"), "flow-merge-readiness"),
    "Lifecycle Phase": (current.get("Lifecycle Phase"), "CONSTRUCTION"),
    "Current Stage": (current.get("Current Stage"), "flow-merge-readiness"),
    "Next Stage": (current.get("Next Stage"), "none"),
    "Status": (current.get("Status"), "Running"),
    "Last Completed Stage": (resume.get("Last Completed Stage"), "flow-slice-review"),
    "Next Action": (resume.get("Next Action"), "Execute Merge Readiness"),
    "Pending Artifacts": (resume.get("Pending Artifacts"), "none"),
}
for label, (actual, expected) in state_expected.items():
    if actual != expected:
        raise SystemExit(f"state field {label!r}: expected {expected!r}, got {actual!r}")

grid = json.load(open(grid_path, encoding="utf-8"))["flow-slice"]["stages"]
progress = section("Stage Progress")
progress_pairs = re.findall(
    r"^- \[([ x?RS-])\] ([a-z0-9-]+) — (EXECUTE|SKIP)$", progress, re.M
)
stage_names = [stage for _, stage, _ in progress_pairs]
duplicate_stages = sorted({stage for stage in stage_names if stage_names.count(stage) > 1})
if duplicate_stages:
    raise SystemExit(f"state progress has duplicate rows: {duplicate_stages!r}")
rows = {stage: (checkbox, mode) for checkbox, stage, mode in progress_pairs}
if set(rows) != set(grid):
    raise SystemExit("state progress stage set differs from the canonical scope grid")
expected_execute = {
    "workspace-scaffold": "x",
    "workspace-detection": "x",
    "state-init": "x",
    "flow-slice-contract": "x",
    "code-generation": "x",
    "build-and-test": "x",
    "flow-slice-review": "x",
    "flow-merge-readiness": "-",
}
actual_execute = {
    stage: checkbox for stage, (checkbox, mode) in rows.items() if mode == "EXECUTE"
}
if actual_execute != expected_execute:
    raise SystemExit(f"unexpected exact 8-stage progress: {actual_execute!r}")
for stage, mode in grid.items():
    checkbox, actual_mode = rows[stage]
    if actual_mode != mode:
        raise SystemExit(f"state progress mode differs from scope grid for {stage}")
    if mode == "SKIP" and checkbox != " ":
        raise SystemExit(f"skipped stage has unexpected state for {stage}: {checkbox!r}")

status_fields = unique_fields(
    status, r"^([A-Za-z ]+):[ \t]+(.*?)[ \t]*$", "status output"
)
expected_status = {
    "Project": "local slice smoke test",
    "Scope": "flow-slice",
    "Phase": "CONSTRUCTION",
    "Current Stage": "Merge Readiness (3.9)",
    "Status": "Running",
    "Active Agent": "aidlc-delivery-agent",
    "Change Control": "relaxed (from scope flow-slice)",
    "Sensors": "on (from scope flow-slice)",
    "Learnings": "off (from scope flow-slice)",
    "Summary Confirmation": "off (from scope flow-slice)",
    "Completion": "7/8 stages (88%)",
    "Validity": "Untracked completions - advisory; routing continues",
    "Untracked": "workspace-scaffold, workspace-detection, state-init",
    "Last Completed": "flow-slice-review",
    "Next Stage": "none",
}
if status_fields != expected_status:
    raise SystemExit(f"final status differs from its exact contract: {status_fields!r}")
phase_progress = re.findall(
    r"^Phase Progress:\n((?:  [A-Z]+[ \t]+[^\n]+\n){3})", status, re.M
)
expected_phase_progress = (
    "  INITIALIZATION   ███ 3/3\n"
    "  INCEPTION        █ 1/1\n"
    "  CONSTRUCTION     ███▒ 3/4\n"
)
if phase_progress != [expected_phase_progress]:
    raise SystemExit(f"final phase progress differs from its exact contract: {phase_progress!r}")

events = []
for path in sorted(glob.glob(os.path.join(audit_dir, "*.md"))):
    for block in re.split(r"\n---\n", open(path, encoding="utf-8").read()):
        fields = unique_fields(
            block, r"^\*\*(.+?)\*\*: *(.*)$", f"audit block in {path}"
        )
        if "Event" in fields:
            events.append(fields)

lifecycle = (
    "STAGE_STARTED",
    "STAGE_AWAITING_APPROVAL",
    "GATE_APPROVED",
    "STAGE_COMPLETED",
)
completed_stages = (
    "flow-slice-contract",
    "code-generation",
    "build-and-test",
    "flow-slice-review",
)
for stage in completed_stages:
    indices = {}
    for event_name in lifecycle:
        matches = [
            index for index, event in enumerate(events)
            if event.get("Event") == event_name and event.get("Stage") == stage
        ]
        if len(matches) != 1:
            raise SystemExit(f"audit event {event_name} for {stage} occurs {len(matches)} times")
        indices[event_name] = matches[0]
    humans = [
        index for index, event in enumerate(events)
        if event.get("Event") == "HUMAN_TURN"
        and event.get("Session") == f"integration-{harness}"
        and indices["STAGE_AWAITING_APPROVAL"] < index < indices["GATE_APPROVED"]
    ]
    if len(humans) != 1:
        raise SystemExit(f"audit HUMAN_TURN for {stage} occurs {len(humans)} times")
    actual_order = [
        indices["STAGE_STARTED"],
        indices["STAGE_AWAITING_APPROVAL"],
        humans[0],
        indices["GATE_APPROVED"],
        indices["STAGE_COMPLETED"],
    ]
    if actual_order != sorted(actual_order) or len(set(actual_order)) != 5:
        raise SystemExit(f"audit lifecycle is out of order for {stage}: {actual_order!r}")

all_humans = [
    event for event in events
    if event.get("Event") == "HUMAN_TURN" and event.get("Session") == f"integration-{harness}"
]
if len(all_humans) != len(completed_stages):
    raise SystemExit(f"audit contains unexpected HUMAN_TURN rows: {len(all_humans)}")
readiness_lifecycle = [
    event.get("Event") for event in events
    if event.get("Stage") == "flow-merge-readiness" and event.get("Event") in lifecycle
]
if readiness_lifecycle != ["STAGE_STARTED"]:
    raise SystemExit(f"merge readiness audit is not exactly active: {readiness_lifecycle!r}")
PY

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
