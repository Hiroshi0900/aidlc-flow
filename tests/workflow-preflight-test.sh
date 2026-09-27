#!/bin/sh
set -eu
. "$(dirname "$0")/testlib.sh"
root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
. "$root/lib/common.sh"
. "$root/lib/plugin.sh"

tmp=$(new_tmpdir)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
project="$tmp/project"
fake_bin="$tmp/fake-bin"
mkdir -p "$project/aidlc/spaces" "$fake_bin"
printf '%s\n' '#!/bin/sh' 'exit "$FAKE_GREP_STATUS"' > "$fake_bin/grep"
chmod +x "$fake_bin/grep"

set +e
no_match_output=$(
  PATH="$fake_bin:$PATH"
  FAKE_GREP_STATUS=1
  export PATH FAKE_GREP_STATUS
  refuse_active_workflow "$project" 2>&1
)
no_match_status=$?
set -e
assert_eq "$no_match_status" "0" "grep status 1 means no active workflow"
assert_eq "$no_match_output" "" "no-match workflow check is silent"

set +e
active_output=$(
  PATH="$fake_bin:$PATH"
  FAKE_GREP_STATUS=0
  export PATH FAKE_GREP_STATUS
  refuse_active_workflow "$project" 2>&1
)
active_status=$?
set -e
assert_eq "$active_status" "1" "grep status 0 rejects active workflow"
assert_contains "$active_output" "an AI-DLC workflow is active" "active workflow has a diagnostic"

set +e
error_output=$(
  PATH="$fake_bin:$PATH"
  FAKE_GREP_STATUS=2
  export PATH FAKE_GREP_STATUS
  refuse_active_workflow "$project" 2>&1
)
error_status=$?
set -e
assert_eq "$error_status" "1" "grep status 2 is rejected as an inspection error"
assert_contains "$error_output" "unable to inspect AI-DLC workflow status" "grep error has a clear diagnostic"

plugin_project="$tmp/plugin-project"
mkdir -p "$plugin_project"
plugin_project=$(CDPATH= cd -- "$plugin_project" && pwd -P)
refuse_dirty_managed_plugin "$plugin_project" codex

owned_relative=.codex/scopes/flow-slice.md
mkdir -p "$plugin_project/.codex/tools/data" "$plugin_project/.codex/scopes"
printf '%s\n' 'managed scope' > "$plugin_project/$owned_relative"
owned_digest=$(shasum -a 256 "$plugin_project/$owned_relative" | awk '{ print $1 }')
printf '%s\n' '{"schemaVersion":1,"name":"flow","version":"0.1.0","sourceHash":"sha256:0000000000000000000000000000000000000000000000000000000000000000"}' > "$plugin_project/.codex/tools/data/plugin-compose-flow.json"
printf '%s\n' "{\"schemaVersion\":1,\"name\":\"flow\",\"files\":[{\"path\":\"$owned_relative\",\"sha256\":\"sha256:$owned_digest\"}]}" > "$plugin_project/.codex/tools/data/plugin-owned-flow.json"
refuse_dirty_managed_plugin "$plugin_project" codex

mv "$plugin_project/.codex/scopes" "$plugin_project/.codex/real-scopes"
ln -s real-scopes "$plugin_project/.codex/scopes"
set +e
owned_symlink_output=$(refuse_dirty_managed_plugin "$plugin_project" codex 2>&1)
owned_symlink_status=$?
set -e
assert_eq "$owned_symlink_status" "1" "symlink in an owned plugin path is rejected"
assert_contains "$owned_symlink_output" "requires attention" "owned symlink has a safe refusal diagnostic"
rm "$plugin_project/.codex/scopes"
mv "$plugin_project/.codex/real-scopes" "$plugin_project/.codex/scopes"

printf '%s\n' 'hand edited scope' > "$plugin_project/$owned_relative"
set +e
hand_edit_output=$(refuse_dirty_managed_plugin "$plugin_project" codex 2>&1)
hand_edit_status=$?
set -e
assert_eq "$hand_edit_status" "1" "hand-edited managed plugin output is rejected"
assert_contains "$hand_edit_output" "requires attention" "hand edit has a safe refusal diagnostic"

printf '%s\n' 'managed scope' > "$plugin_project/$owned_relative"
mkdir -p "$plugin_project/aidlc/spaces/default/memory"
printf '%s\n' '[degraded] stage contribution was dropped' > "$plugin_project/aidlc/spaces/default/memory/plugin-compose-flow.drops"
set +e
degraded_output=$(refuse_dirty_managed_plugin "$plugin_project" codex 2>&1)
degraded_status=$?
set -e
assert_eq "$degraded_status" "1" "degraded plugin composition is rejected"
assert_contains "$degraded_output" "requires attention" "degraded composition has a safe refusal diagnostic"

rm "$plugin_project/aidlc/spaces/default/memory/plugin-compose-flow.drops"
rm "$plugin_project/.codex/tools/data/plugin-owned-flow.json"
set +e
incomplete_output=$(refuse_dirty_managed_plugin "$plugin_project" codex 2>&1)
incomplete_status=$?
set -e
assert_eq "$incomplete_status" "1" "incomplete plugin evidence is rejected"
assert_contains "$incomplete_output" "requires attention" "incomplete evidence has a safe refusal diagnostic"
printf 'PASS: workflow-preflight-test\n'
