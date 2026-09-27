#!/bin/sh

configure_harness() {
  aidlc_flow_claude_project_dir=$1
  (
    cd "$aidlc_flow_claude_project_dir"
    aidlc config --project-dir "$aidlc_flow_claude_project_dir" --harness claude --mcp none --quiet
    aidlc config providers --project-dir "$aidlc_flow_claude_project_dir" --provider other --acknowledge --yes >/dev/null
  )
  remove_bedrock_defaults "$aidlc_flow_claude_project_dir/.claude/settings.json"
}

remove_bedrock_defaults() {
  aidlc_flow_claude_settings=$1
  python3 - "$aidlc_flow_claude_settings" <<'PY'
import json
import os
import re
import sys
import tempfile

path = sys.argv[1]
with open(path, encoding="utf-8") as source:
    settings = json.load(source)

env = settings.get("env")
if isinstance(env, dict):
    for key in list(env):
        if key in {"CLAUDE_CODE_USE_BEDROCK", "AWS_REGION"} or re.fullmatch(
            r"ANTHROPIC_DEFAULT_(?:FABLE|OPUS|SONNET|HAIKU)_MODEL", key
        ):
            del env[key]

directory = os.path.dirname(path)
fd, temporary = tempfile.mkstemp(prefix=".aidlc-flow-settings.", dir=directory)
try:
    with os.fdopen(fd, "w", encoding="utf-8") as destination:
        json.dump(settings, destination, indent=2, ensure_ascii=False)
        destination.write("\n")
    os.replace(temporary, path)
except BaseException:
    try:
        os.unlink(temporary)
    except FileNotFoundError:
        pass
    raise
PY
}

print_start_hint() {
  printf '%s\n' 'Start Claude Code in this repository, approve project hooks, then invoke /flow-slice <your slice>.'
}
