#!/bin/sh

configure_harness() {
  aidlc_flow_codex_project_dir=$1
  (cd "$aidlc_flow_codex_project_dir" && aidlc config --project-dir "$aidlc_flow_codex_project_dir" --harness codex --mcp none --quiet)
}

print_start_hint() {
  printf '%s\n' 'Start Codex in this repository, approve the hook trust prompt, then invoke $flow-slice <your slice>.'
}
