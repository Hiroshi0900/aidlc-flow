#!/bin/sh
set -eu
. "$(dirname "$0")/testlib.sh"

assert_not_contains() {
  not_haystack=$1
  not_needle=$2
  not_message=$3
  case "$not_haystack" in
    *"$not_needle"*) fail "$not_message: unexpectedly found '$not_needle'" ;;
  esac
}

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
caller_dir=$(CDPATH= cd -- . && pwd)
tmp=$(new_tmpdir)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
tmp=$(CDPATH= cd -- "$tmp" && pwd -P)
project="$tmp/project"
fake_bin="$tmp/bin"
projection_root="$tmp/plugin-dist"
mkdir -p "$project" "$fake_bin"
project=$(CDPATH= cd -- "$project" && pwd -P)
git -C "$project" init -q
project_link="$tmp/project-link"
ln -s "$project" "$project_link"

for fixture_harness in codex claude; do
  fixture="$projection_root/$fixture_harness"
  mkdir -p "$fixture/.$fixture_harness-plugin" "$fixture/hooks"
  printf '%s\n' "{\"schema\":1,\"producer\":\"aidlc-plugin-build\",\"plugin\":\"flow\",\"harness\":\"$fixture_harness\"}" > "$fixture/.aidlc-plugin-projection.json"
  printf '%s\n' '{"name":"aidlc-flow","version":"0.1.0"}' > "$fixture/.$fixture_harness-plugin/plugin.json"
  printf '%s\n' '{"name":"aidlc-plugins","plugins":[{"name":"aidlc-flow","source":".","version":"0.1.0"}]}' > "$fixture/.$fixture_harness-plugin/marketplace.json"
  printf '%s\n' 'export async function compose() {}' > "$fixture/hooks/compose.ts"
  if [ "$fixture_harness" = codex ]; then
    mkdir -p "$fixture/.agents/plugins"
    printf '%s\n' '{"name":"aidlc-plugins","plugins":[{"name":"aidlc-flow","source":{"source":"local","path":"./"},"policy":{"installation":"AVAILABLE","authentication":"ON_USE"}}]}' > "$fixture/.agents/plugins/marketplace.json"
  fi
done

cat > "$fake_bin/codex" <<'SH'
#!/bin/sh
printf 'codex|%s|%s\n' "$PWD" "$*" >> "$HOST_FAKE_LOG"
[ -z "${BOOTSTRAP_ORDER_LOG:-}" ] || printf 'codex|%s|%s\n' "$PWD" "$*" >> "$BOOTSTRAP_ORDER_LOG"
case "$*" in
  'plugin marketplace list --json') printf '%s\n' '{"marketplaces":[]}' ;;
  'plugin list --json') printf '%s\n' '{"installed":[],"available":[]}' ;;
  'plugin marketplace add '*|'plugin add '*) exit 0 ;;
  *) exit 91 ;;
esac
SH
cat > "$fake_bin/claude" <<'SH'
#!/bin/sh
printf 'claude|%s|%s\n' "$PWD" "$*" >> "$HOST_FAKE_LOG"
[ -z "${BOOTSTRAP_ORDER_LOG:-}" ] || printf 'claude|%s|%s\n' "$PWD" "$*" >> "$BOOTSTRAP_ORDER_LOG"
case "$*" in
  'plugin marketplace list --json') printf '%s\n' '[]' ;;
  'plugin list --json') printf '%s\n' '[]' ;;
  'plugin marketplace add --scope project '*|'plugin install --scope project --yes '*) exit 0 ;;
  *) exit 92 ;;
esac
SH
chmod +x "$fake_bin/codex" "$fake_bin/claude"

cat > "$fake_bin/aidlc" <<'SH'
#!/bin/sh
if [ "$*" = "--version" ]; then
  printf '%s\n' 'aidlc 2.9.0 (runtime 2.9.0)'
  exit 0
fi
printf '%s|%s\n' "$PWD" "$*" >> "$AIDLC_FAKE_LOG"
[ -z "${BOOTSTRAP_ORDER_LOG:-}" ] || printf 'aidlc|%s|%s\n' "$PWD" "$*" >> "$BOOTSTRAP_ORDER_LOG"
if [ "$*" = "engine plugin sync" ]; then
  exit "${AIDLC_FAKE_SYNC_STATUS:-0}"
fi
if [ "${1:-}" = config ] && [ "${2:-}" = project ]; then
  exit "${AIDLC_FAKE_SELECT_STATUS:-0}"
fi
fake_command=$1
shift
fake_project=
while [ "$#" -gt 0 ]; do
  case "$1" in
    --project-dir)
      fake_project=$2
      shift 2
      ;;
    *) shift ;;
  esac
done
[ -n "$fake_project" ] || fake_project=${AIDLC_PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-$PWD}}
case "$fake_command" in
  config)
    fake_status=${AIDLC_FAKE_CONFIG_STATUS:-0}
    [ "$fake_status" -eq 0 ] || exit "$fake_status"
    fake_space=${AIDLC_FAKE_SPACE:-default}
    mkdir -p "$fake_project/.claude" "$fake_project/aidlc/spaces/$fake_space"
    printf '%s\n' "$fake_space" > "$fake_project/aidlc/active-space"
    if [ -n "${AIDLC_FAKE_MEMORY_SYMLINK:-}" ]; then
      ln -s "$AIDLC_FAKE_MEMORY_SYMLINK" "$fake_project/aidlc/spaces/$fake_space/memory"
    else
      mkdir -p "$fake_project/aidlc/spaces/$fake_space/memory/phases"
      [ -e "$fake_project/aidlc/spaces/$fake_space/memory/team.md" ] ||
        printf '%s\n' 'official team seed' > "$fake_project/aidlc/spaces/$fake_space/memory/team.md"
      [ -e "$fake_project/aidlc/spaces/$fake_space/memory/phases/construction.md" ] ||
        printf '%s\n' 'official construction seed' > "$fake_project/aidlc/spaces/$fake_space/memory/phases/construction.md"
    fi
    cat > "$fake_project/.claude/settings.json" <<'JSON'
{"env":{"AWS_AIDLC_DEFAULT_SCOPE":"classic","CLAUDE_CODE_USE_BEDROCK":"1","AWS_REGION":"us-east-1","ANTHROPIC_DEFAULT_OPUS_MODEL":"global.anthropic.claude-opus-4-8[1m]"}}
JSON
    ;;
  doctor)
    fake_status=${AIDLC_FAKE_DOCTOR_STATUS:-0}
    [ "$fake_status" -eq 0 ] || exit "$fake_status"
    ;;
  *) exit 9 ;;
esac
SH
chmod +x "$fake_bin/aidlc"
export AIDLC_FAKE_LOG="$tmp/aidlc.log"
export HOST_FAKE_LOG="$tmp/host.log"
export BOOTSTRAP_ORDER_LOG="$tmp/order.log"
export AIDLC_FLOW_PLUGIN_DIST="$projection_root"
decoy="$tmp/decoy"
mkdir -p "$decoy"

output=$(AIDLC_PROJECT_DIR="$decoy" CLAUDE_PROJECT_DIR="$decoy" PATH="$fake_bin:$PATH" "$root/bin/aidlc-flow" init --harness codex --project-dir "$project_link")
log=$(cat "$AIDLC_FAKE_LOG")
expected_log="$project|config --project-dir $project --harness codex --mcp none --quiet
$project|config project --project-dir $project --plugins flow --yes
$project|engine plugin sync
$caller_dir|doctor --project-dir $project --quiet"
assert_eq "$log" "$expected_log" "codex config and doctor are called in order"
assert_eq "$(cat "$BOOTSTRAP_ORDER_LOG")" "aidlc|$project|config --project-dir $project --harness codex --mcp none --quiet
codex|$project|plugin marketplace list --json
codex|$project|plugin marketplace add $projection_root/codex
codex|$project|plugin list --json
codex|$project|plugin add aidlc-flow@aidlc-plugins
aidlc|$project|config project --project-dir $project --plugins flow --yes
aidlc|$project|engine plugin sync
aidlc|$caller_dir|doctor --project-dir $project --quiet" "bootstrap performs core config, host install, selection, sync, then doctor"
[ ! -e "$decoy/aidlc" ] || fail "codex config ignores a conflicting environment project"
assert_contains "$output" "aidlc-flow: configured codex for $project" "codex completion is printed"
assert_contains "$output" 'invoke $flow-slice <your slice>' "codex start hint is printed"
assert_contains "$(cat "$project/aidlc/spaces/default/memory/team.md")" "official team seed" "official team seed is preserved"
assert_contains "$(cat "$project/aidlc/spaces/default/memory/team.md")" "commit SHA" "team memory is installed"
assert_contains "$(cat "$project/aidlc/spaces/default/memory/phases/construction.md")" "official construction seed" "official construction seed is preserved"
assert_contains "$(cat "$project/aidlc/spaces/default/memory/phases/construction.md")" "RED" "construction memory is installed"

edited_untracked_project="$tmp/edited-untracked-project"
mkdir -p "$edited_untracked_project"
edited_untracked_project=$(CDPATH= cd -- "$edited_untracked_project" && pwd -P)
git -C "$edited_untracked_project" init -q
PATH="$fake_bin:$PATH" "$root/bin/aidlc-flow" init --harness codex --project-dir "$edited_untracked_project" >/dev/null
awk '
  /<!-- END aidlc-flow:team -->/ { print "edited managed content" }
  { print }
' "$edited_untracked_project/aidlc/spaces/default/memory/team.md" > "$tmp/edited-untracked-team.md"
mv "$tmp/edited-untracked-team.md" "$edited_untracked_project/aidlc/spaces/default/memory/team.md"
before=$(cksum "$edited_untracked_project/aidlc/spaces/default/memory/team.md")
: > "$AIDLC_FAKE_LOG"
set +e
output=$(PATH="$fake_bin:$PATH" "$root/bin/aidlc-flow" init --harness codex --project-dir "$edited_untracked_project" 2>"$tmp/edited-untracked.err")
status=$?
set -e
after=$(cksum "$edited_untracked_project/aidlc/spaces/default/memory/team.md")
assert_eq "$status" "1" "edited untracked canonical memory is rejected"
assert_eq "$after" "$before" "edited untracked canonical memory remains byte-identical"
assert_eq "$(cat "$AIDLC_FAKE_LOG")" "" "edited untracked canonical memory stops before config"
assert_not_contains "$output" "aidlc-flow: configured" "edited untracked failure has no success output"

ignored_project="$tmp/ignored-project"
mkdir -p "$ignored_project"
ignored_project=$(CDPATH= cd -- "$ignored_project" && pwd -P)
git -C "$ignored_project" init -q
printf '%s\n' 'aidlc/' > "$ignored_project/.gitignore"
git -C "$ignored_project" add .gitignore
git -C "$ignored_project" -c user.name=Test -c user.email=test@example.com commit -qm "ignore aidlc"
PATH="$fake_bin:$PATH" "$root/bin/aidlc-flow" init --harness codex --project-dir "$ignored_project" >/dev/null
before=$(cksum "$ignored_project/aidlc/spaces/default/memory/team.md" "$ignored_project/aidlc/spaces/default/memory/phases/construction.md")
: > "$AIDLC_FAKE_LOG"
TMPDIR="$tmp" PATH="$fake_bin:$PATH" "$root/bin/aidlc-flow" init --harness codex --project-dir "$ignored_project" >/dev/null
after=$(cksum "$ignored_project/aidlc/spaces/default/memory/team.md" "$ignored_project/aidlc/spaces/default/memory/phases/construction.md")
assert_eq "$after" "$before" "unchanged ignored managed memory is allowed and byte-identical"
assert_eq "$(cat "$AIDLC_FAKE_LOG")" "$ignored_project|config --project-dir $ignored_project --harness codex --mcp none --quiet
$ignored_project|config project --project-dir $ignored_project --plugins flow --yes
$ignored_project|engine plugin sync
$caller_dir|doctor --project-dir $ignored_project --quiet" "unchanged ignored memory completes config then doctor"
awk '
  /<!-- END aidlc-flow:team -->/ { print "edited ignored managed content" }
  { print }
' "$ignored_project/aidlc/spaces/default/memory/team.md" > "$tmp/edited-ignored-team.md"
mv "$tmp/edited-ignored-team.md" "$ignored_project/aidlc/spaces/default/memory/team.md"
before=$(cksum "$ignored_project/aidlc/spaces/default/memory/team.md")
: > "$AIDLC_FAKE_LOG"
set +e
output=$(TMPDIR="$tmp" PATH="$fake_bin:$PATH" "$root/bin/aidlc-flow" init --harness codex --project-dir "$ignored_project" 2>"$tmp/ignored-edited.err")
status=$?
set -e
after=$(cksum "$ignored_project/aidlc/spaces/default/memory/team.md")
assert_eq "$status" "1" "edited ignored managed memory is rejected"
assert_eq "$after" "$before" "edited ignored managed memory remains byte-identical"
assert_eq "$(cat "$AIDLC_FAKE_LOG")" "" "edited ignored managed memory stops before config"
assert_not_contains "$output" "aidlc-flow: configured" "edited ignored failure has no success output"

before=$(cksum "$project/aidlc/spaces/default/memory/team.md" "$project/aidlc/spaces/default/memory/phases/construction.md")
TMPDIR="$tmp" PATH="$fake_bin:$PATH" "$root/bin/aidlc-flow" init --harness codex --project-dir "$project" >/dev/null
after=$(cksum "$project/aidlc/spaces/default/memory/team.md" "$project/aidlc/spaces/default/memory/phases/construction.md")
assert_eq "$after" "$before" "second init keeps memory byte-identical"
assert_eq "$(find "$tmp" -name 'aidlc-flow-memory-check.*' -print)" "" "managed memory comparison leaves no temporary directory"
git -C "$project" add aidlc
git -C "$project" -c user.name=Test -c user.email=test@example.com commit -qm "baseline memory"

: > "$AIDLC_FAKE_LOG"
printf '%s\n' 'keep this change' > "$project/local-note.txt"
output=$(PATH="$fake_bin:$PATH" "$root/bin/aidlc-flow" init --harness codex --project-dir "$project" 2>"$tmp/dirty.err")
assert_contains "$(cat "$tmp/dirty.err")" "existing working-tree changes detected; review after configuration:" "unrelated dirty files produce a factual warning"
assert_contains "$(cat "$project/local-note.txt")" "keep this change" "unrelated dirty file is unchanged"
assert_contains "$(cat "$AIDLC_FAKE_LOG")" "config --project-dir $project --harness codex" "unrelated dirty files do not block config"
rm "$project/local-note.txt"

: > "$AIDLC_FAKE_LOG"
output=$(AIDLC_PROJECT_DIR="$decoy" CLAUDE_PROJECT_DIR="$decoy" PATH="$fake_bin:$PATH" "$root/bin/aidlc-flow" init --harness claude --project-dir "$project")
assert_eq "$(cat "$AIDLC_FAKE_LOG")" "$project|config --project-dir $project --harness claude --mcp none --quiet
$project|config providers --project-dir $project --provider other --acknowledge --yes
$project|config project --project-dir $project --plugins flow --yes
$project|engine plugin sync
$caller_dir|doctor --project-dir $project --quiet" "claude config and doctor are called in order"
assert_contains "$output" "aidlc-flow: configured claude for $project" "claude completion is printed"
assert_contains "$output" "invoke /flow-slice <your slice>" "claude start hint is printed"

awk '
  /<!-- END aidlc-flow:team -->/ { print "locally edited managed content" }
  { print }
' "$project/aidlc/spaces/default/memory/team.md" > "$tmp/edited-team.md"
mv "$tmp/edited-team.md" "$project/aidlc/spaces/default/memory/team.md"
before=$(cksum "$project/aidlc/spaces/default/memory/team.md")
: > "$AIDLC_FAKE_LOG"
set +e
output=$(PATH="$fake_bin:$PATH" "$root/bin/aidlc-flow" init --harness codex --project-dir "$project" 2>"$tmp/managed-dirty.err")
status=$?
set -e
after=$(cksum "$project/aidlc/spaces/default/memory/team.md")
assert_eq "$status" "1" "tracked managed memory changes are rejected"
assert_eq "$after" "$before" "tracked managed memory changes remain byte-identical"
assert_eq "$(cat "$AIDLC_FAKE_LOG")" "" "tracked managed memory changes stop before config"
assert_not_contains "$output" "aidlc-flow: configured" "managed dirty failure has no success output"

untracked_project="$tmp/untracked-project"
mkdir -p "$untracked_project/aidlc/spaces/default/memory"
untracked_project=$(CDPATH= cd -- "$untracked_project" && pwd -P)
git -C "$untracked_project" init -q
printf '%s\n' default > "$untracked_project/aidlc/active-space"
printf '%s\n' 'untracked local memory' > "$untracked_project/aidlc/spaces/default/memory/team.md"
: > "$AIDLC_FAKE_LOG"
set +e
PATH="$fake_bin:$PATH" "$root/bin/aidlc-flow" init --harness codex --project-dir "$untracked_project" >/dev/null 2>"$tmp/untracked-dirty.err"
status=$?
set -e
assert_eq "$status" "1" "untracked managed memory is rejected"
assert_eq "$(cat "$untracked_project/aidlc/spaces/default/memory/team.md")" "untracked local memory" "untracked managed memory is unchanged"
assert_eq "$(cat "$AIDLC_FAKE_LOG")" "" "untracked managed memory stops before config"

symlink_pre_project="$tmp/symlink-pre-project"
symlink_pre_outside="$tmp/symlink-pre-outside"
mkdir -p "$symlink_pre_project/aidlc/spaces/default" "$symlink_pre_outside"
symlink_pre_project=$(CDPATH= cd -- "$symlink_pre_project" && pwd -P)
git -C "$symlink_pre_project" init -q
printf '%s\n' default > "$symlink_pre_project/aidlc/active-space"
printf '%s\n' sentinel > "$symlink_pre_outside/sentinel.txt"
ln -s "$symlink_pre_outside" "$symlink_pre_project/aidlc/spaces/default/memory"
: > "$AIDLC_FAKE_LOG"
set +e
output=$(PATH="$fake_bin:$PATH" "$root/bin/aidlc-flow" init --harness codex --project-dir "$symlink_pre_project" 2>"$tmp/symlink-pre.err")
status=$?
set -e
assert_eq "$status" "1" "pre-existing managed path symlink is rejected"
assert_contains "$(cat "$tmp/symlink-pre.err")" "symbolic link" "pre-existing symlink has a specific diagnostic"
assert_eq "$(cat "$AIDLC_FAKE_LOG")" "" "pre-existing symlink stops before config"
[ ! -e "$symlink_pre_outside/team.md" ] || fail "pre-existing symlink leaves repository-external team memory unchanged"
[ ! -e "$symlink_pre_outside/phases" ] || fail "pre-existing symlink leaves repository-external phase memory unchanged"
assert_not_contains "$output" "aidlc-flow: configured" "pre-existing symlink failure has no success output"

symlink_post_project="$tmp/symlink-post-project"
symlink_post_outside="$tmp/symlink-post-outside"
mkdir -p "$symlink_post_project" "$symlink_post_outside"
symlink_post_project=$(CDPATH= cd -- "$symlink_post_project" && pwd -P)
git -C "$symlink_post_project" init -q
printf '%s\n' sentinel > "$symlink_post_outside/sentinel.txt"
: > "$AIDLC_FAKE_LOG"
set +e
output=$(AIDLC_FAKE_MEMORY_SYMLINK="$symlink_post_outside" PATH="$fake_bin:$PATH" "$root/bin/aidlc-flow" init --harness codex --project-dir "$symlink_post_project" 2>"$tmp/symlink-post.err")
status=$?
set -e
assert_eq "$status" "1" "managed path symlink created by config is rejected"
assert_contains "$(cat "$tmp/symlink-post.err")" "symbolic link" "post-config symlink has a specific diagnostic"
assert_eq "$(cat "$AIDLC_FAKE_LOG")" "$symlink_post_project|config --project-dir $symlink_post_project --harness codex --mcp none --quiet
$symlink_post_project|config project --project-dir $symlink_post_project --plugins flow --yes
$symlink_post_project|engine plugin sync" "post-config symlink stops before doctor"
[ ! -e "$symlink_post_outside/team.md" ] || fail "post-config symlink leaves repository-external team memory unchanged"
[ ! -e "$symlink_post_outside/phases" ] || fail "post-config symlink leaves repository-external phase memory unchanged"
assert_not_contains "$output" "aidlc-flow: configured" "post-config symlink failure has no success output"

config_fail_project="$tmp/config-fail-project"
mkdir -p "$config_fail_project"
config_fail_project=$(CDPATH= cd -- "$config_fail_project" && pwd -P)
git -C "$config_fail_project" init -q
: > "$AIDLC_FAKE_LOG"
set +e
output=$(AIDLC_FAKE_CONFIG_STATUS=23 PATH="$fake_bin:$PATH" "$root/bin/aidlc-flow" init --harness codex --project-dir "$config_fail_project" 2>"$tmp/config-fail.err")
status=$?
set -e
assert_eq "$status" "23" "config failure status is propagated"
assert_eq "$(cat "$AIDLC_FAKE_LOG")" "$config_fail_project|config --project-dir $config_fail_project --harness codex --mcp none --quiet" "config failure stops before doctor"
[ ! -e "$config_fail_project/aidlc" ] || fail "config failure does not create managed memory"
assert_not_contains "$output" "aidlc-flow: configured" "config failure has no success output"

select_fail_project="$tmp/select-fail-project"
mkdir -p "$select_fail_project"
select_fail_project=$(CDPATH= cd -- "$select_fail_project" && pwd -P)
git -C "$select_fail_project" init -q
: > "$AIDLC_FAKE_LOG"
set +e
output=$(AIDLC_FAKE_SELECT_STATUS=25 PATH="$fake_bin:$PATH" "$root/bin/aidlc-flow" init --harness codex --project-dir "$select_fail_project" 2>"$tmp/select-fail.err")
status=$?
set -e
assert_eq "$status" "25" "plugin selection failure status is propagated"
assert_eq "$(cat "$AIDLC_FAKE_LOG")" "$select_fail_project|config --project-dir $select_fail_project --harness codex --mcp none --quiet
$select_fail_project|config project --project-dir $select_fail_project --plugins flow --yes" "selection failure stops before sync and doctor"
assert_not_contains "$output" "aidlc-flow: configured" "selection failure has no success output"

sync_fail_project="$tmp/sync-fail-project"
mkdir -p "$sync_fail_project"
sync_fail_project=$(CDPATH= cd -- "$sync_fail_project" && pwd -P)
git -C "$sync_fail_project" init -q
: > "$AIDLC_FAKE_LOG"
set +e
output=$(AIDLC_FAKE_SYNC_STATUS=26 PATH="$fake_bin:$PATH" "$root/bin/aidlc-flow" init --harness codex --project-dir "$sync_fail_project" 2>"$tmp/sync-fail.err")
status=$?
set -e
assert_eq "$status" "26" "plugin sync failure status is propagated"
assert_eq "$(cat "$AIDLC_FAKE_LOG")" "$sync_fail_project|config --project-dir $sync_fail_project --harness codex --mcp none --quiet
$sync_fail_project|config project --project-dir $sync_fail_project --plugins flow --yes
$sync_fail_project|engine plugin sync" "sync failure stops before doctor"
assert_not_contains "$output" "aidlc-flow: configured" "sync failure has no success output"

active_project="$tmp/active-project"
mkdir -p "$active_project/aidlc/spaces/default/intents"
active_project=$(CDPATH= cd -- "$active_project" && pwd -P)
git -C "$active_project" init -q
printf '%s\n' '**Status**: in_progress' > "$active_project/aidlc/spaces/default/intents/current.md"
: > "$AIDLC_FAKE_LOG"
: > "$HOST_FAKE_LOG"
set +e
output=$(PATH="$fake_bin:$PATH" "$root/bin/aidlc-flow" init --harness codex --project-dir "$active_project" 2>"$tmp/active.err")
status=$?
set -e
assert_eq "$status" "1" "active workflow is rejected"
assert_eq "$(cat "$AIDLC_FAKE_LOG")" "" "active workflow stops before core configuration"
assert_eq "$(cat "$HOST_FAKE_LOG")" "" "active workflow stops before host mutation"
assert_not_contains "$output" "aidlc-flow: configured" "active workflow failure has no success output"

merge_fail_project="$tmp/merge-fail-project"
mkdir -p "$merge_fail_project/aidlc/spaces/default/memory/phases"
merge_fail_project=$(CDPATH= cd -- "$merge_fail_project" && pwd -P)
git -C "$merge_fail_project" init -q
printf '%s\n' default > "$merge_fail_project/aidlc/active-space"
printf '%s\n' '<!-- BEGIN aidlc-flow:team -->' 'malformed managed memory' > "$merge_fail_project/aidlc/spaces/default/memory/team.md"
git -C "$merge_fail_project" add aidlc
git -C "$merge_fail_project" -c user.name=Test -c user.email=test@example.com commit -qm "malformed baseline"
before=$(cksum "$merge_fail_project/aidlc/spaces/default/memory/team.md")
: > "$AIDLC_FAKE_LOG"
set +e
output=$(PATH="$fake_bin:$PATH" "$root/bin/aidlc-flow" init --harness codex --project-dir "$merge_fail_project" 2>"$tmp/merge-fail.err")
status=$?
set -e
after=$(cksum "$merge_fail_project/aidlc/spaces/default/memory/team.md")
assert_eq "$status" "1" "managed memory merge failure exits 1"
assert_eq "$after" "$before" "managed memory merge failure preserves existing memory"
assert_eq "$(cat "$AIDLC_FAKE_LOG")" "$merge_fail_project|config --project-dir $merge_fail_project --harness codex --mcp none --quiet
$merge_fail_project|config project --project-dir $merge_fail_project --plugins flow --yes
$merge_fail_project|engine plugin sync" "managed memory merge failure stops before doctor"
assert_contains "$(cat "$tmp/merge-fail.err")" "failed to update managed memory: $merge_fail_project/aidlc/spaces/default/memory/team.md" "merge failure has a general diagnostic"
assert_not_contains "$output" "aidlc-flow: configured" "merge failure has no success output"

doctor_fail_project="$tmp/doctor-fail-project"
mkdir -p "$doctor_fail_project"
doctor_fail_project=$(CDPATH= cd -- "$doctor_fail_project" && pwd -P)
git -C "$doctor_fail_project" init -q
: > "$AIDLC_FAKE_LOG"
set +e
output=$(AIDLC_FAKE_DOCTOR_STATUS=24 PATH="$fake_bin:$PATH" "$root/bin/aidlc-flow" init --harness codex --project-dir "$doctor_fail_project" 2>"$tmp/doctor-fail.err")
status=$?
set -e
assert_eq "$status" "24" "doctor failure status is propagated"
assert_eq "$(cat "$AIDLC_FAKE_LOG")" "$doctor_fail_project|config --project-dir $doctor_fail_project --harness codex --mcp none --quiet
$doctor_fail_project|config project --project-dir $doctor_fail_project --plugins flow --yes
$doctor_fail_project|engine plugin sync
$caller_dir|doctor --project-dir $doctor_fail_project --quiet" "doctor failure occurs after config and memory merge"
assert_contains "$(cat "$doctor_fail_project/aidlc/spaces/default/memory/team.md")" "commit SHA" "memory is merged before doctor"
assert_not_contains "$output" "aidlc-flow: configured" "doctor failure has no success output"

alternate_project="$tmp/alternate-project"
mkdir -p "$alternate_project"
alternate_project=$(CDPATH= cd -- "$alternate_project" && pwd -P)
git -C "$alternate_project" init -q
: > "$AIDLC_FAKE_LOG"
output=$(AIDLC_FAKE_SPACE=alternate PATH="$fake_bin:$PATH" "$root/bin/aidlc-flow" init --harness claude --project-dir "$alternate_project")
assert_eq "$(cat "$AIDLC_FAKE_LOG")" "$alternate_project|config --project-dir $alternate_project --harness claude --mcp none --quiet
$alternate_project|config providers --project-dir $alternate_project --provider other --acknowledge --yes
$alternate_project|config project --project-dir $alternate_project --plugins flow --yes
$alternate_project|engine plugin sync
$caller_dir|doctor --project-dir $alternate_project --quiet" "alternate active space preserves config then doctor order"
assert_contains "$(cat "$alternate_project/aidlc/spaces/alternate/memory/team.md")" "commit SHA" "team memory is merged into the configured active space"
assert_contains "$(cat "$alternate_project/aidlc/spaces/alternate/memory/phases/construction.md")" "RED" "construction memory is merged into the configured active space"
[ ! -e "$alternate_project/aidlc/spaces/default/memory/team.md" ] || fail "default space is not used when config selects another space"
assert_contains "$output" "aidlc-flow: configured claude for $alternate_project" "alternate active space completes successfully"

set +e
PATH="$fake_bin:$PATH" "$root/bin/aidlc-flow" init --harness cursor --project-dir "$project" >/dev/null 2>&1
status=$?
set -e
assert_eq "$status" "2" "unsupported harness is rejected"
printf 'PASS: bootstrap-test\n'
