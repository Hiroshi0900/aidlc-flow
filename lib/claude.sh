#!/bin/sh

configure_harness() {
  aidlc_flow_claude_project_dir=$1
  (cd "$aidlc_flow_claude_project_dir" && aidlc config --project-dir "$aidlc_flow_claude_project_dir" --harness claude --mcp none --quiet)
}

print_start_hint() {
  printf '%s\n' 'Start Claude Code in this repository, approve project hooks, then invoke /aidlc <your idea>.'
}
