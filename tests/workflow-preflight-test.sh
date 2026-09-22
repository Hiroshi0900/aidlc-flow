#!/bin/sh
set -eu
. "$(dirname "$0")/testlib.sh"
root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
. "$root/lib/common.sh"

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
printf 'PASS: workflow-preflight-test\n'
