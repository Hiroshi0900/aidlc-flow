#!/bin/sh
set -eu
. "$(dirname "$0")/testlib.sh"

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
tmp=$(new_tmpdir)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
tmp=$(CDPATH= cd -- "$tmp" && pwd -P)
project="$tmp/project"
fake_bin="$tmp/bin"
projection_root="$tmp/plugin-dist"
mkdir -p "$project" "$fake_bin"
project=$(CDPATH= cd -- "$project" && pwd -P)

make_projection() {
  fixture_harness=$1
  fixture="$projection_root/$fixture_harness"
  mkdir -p "$fixture/.$fixture_harness-plugin" "$fixture/hooks" "$fixture/scopes"
  printf '%s\n' "{\"schema\":1,\"producer\":\"aidlc-plugin-build\",\"plugin\":\"flow\",\"harness\":\"$fixture_harness\"}" > "$fixture/.aidlc-plugin-projection.json"
  printf '%s\n' '{"name":"aidlc-flow","version":"0.1.0"}' > "$fixture/.$fixture_harness-plugin/plugin.json"
  printf '%s\n' '{"name":"aidlc-plugins","plugins":[{"name":"aidlc-flow","source":".","version":"0.1.0"}]}' > "$fixture/.$fixture_harness-plugin/marketplace.json"
  printf '%s\n' 'export async function compose() {}' > "$fixture/hooks/compose.ts"
  printf '%s\n' 'initial payload' > "$fixture/scopes/flow-slice.md"
  if [ "$fixture_harness" = codex ]; then
    mkdir -p "$fixture/.agents/plugins"
    printf '%s\n' '{"name":"aidlc-plugins","plugins":[{"name":"aidlc-flow","source":{"source":"local","path":"./"},"policy":{"installation":"AVAILABLE","authentication":"ON_USE"}}]}' > "$fixture/.agents/plugins/marketplace.json"
  fi
}
make_projection codex
make_projection claude
codex_cache="$tmp/codex-home/plugins/cache/aidlc-plugins/aidlc-flow/0.1.0"
claude_cache="$tmp/claude-config/plugins/cache/aidlc-plugins/aidlc-flow/0.1.0"
mkdir -p "$(dirname "$codex_cache")"
mkdir -p "$(dirname "$claude_cache")"
cp -R "$projection_root/codex" "$codex_cache"
cp -R "$projection_root/claude" "$claude_cache"
export CODEX_HOME="$tmp/codex-home"
export CLAUDE_CONFIG_DIR="$tmp/claude-config"
export HOST_FAKE_CODEX_CACHE="$codex_cache"
export HOST_FAKE_CLAUDE_CACHE="$claude_cache"
export HOST_FAKE_CODEX_PROJECTION="$projection_root/codex"
export HOST_FAKE_CLAUDE_PROJECTION="$projection_root/claude"

cat > "$fake_bin/codex" <<'SH'
#!/bin/sh
printf 'codex|%s|%s\n' "$PWD" "$*" >> "$HOST_FAKE_LOG"
case "$*" in
  'plugin marketplace list --json')
    if [ -n "${CODEX_MARKETPLACES_JSON:-}" ]; then printf '%s\n' "$CODEX_MARKETPLACES_JSON"; else printf '%s\n' '{"marketplaces":[]}'; fi
    ;;
  'plugin list --json')
    if [ -f "${HOST_FAKE_CODEX_UPDATED:-/nonexistent}" ] && [ -n "${CODEX_PLUGINS_AFTER_JSON:-}" ]; then
      printf '%s\n' "$CODEX_PLUGINS_AFTER_JSON"
    elif [ -n "${CODEX_PLUGINS_JSON:-}" ]; then printf '%s\n' "$CODEX_PLUGINS_JSON"; else printf '%s\n' '{"installed":[],"available":[]}'; fi
    ;;
  'plugin marketplace add '*) exit "${HOST_FAKE_MUTATE_STATUS:-0}" ;;
  'plugin add '*)
    [ "${HOST_FAKE_MUTATE_STATUS:-0}" -eq 0 ] || exit "$HOST_FAKE_MUTATE_STATUS"
    if [ -n "${HOST_FAKE_REFRESH_CODEX:-}" ]; then
      rm -rf "$HOST_FAKE_CODEX_CACHE"
      cp -R "$HOST_FAKE_CODEX_PROJECTION" "$HOST_FAKE_CODEX_CACHE"
      touch "$HOST_FAKE_CODEX_UPDATED"
    fi
    ;;
  *) exit 91 ;;
esac
SH
cat > "$fake_bin/claude" <<'SH'
#!/bin/sh
printf 'claude|%s|%s\n' "$PWD" "$*" >> "$HOST_FAKE_LOG"
case "$*" in
  'plugin marketplace list --json')
    if [ -n "${CLAUDE_MARKETPLACES_JSON:-}" ]; then printf '%s\n' "$CLAUDE_MARKETPLACES_JSON"; else printf '%s\n' '[]'; fi
    ;;
  'plugin list --json')
    if [ -f "${HOST_FAKE_CLAUDE_ENABLED:-/nonexistent}" ] && [ -n "${CLAUDE_PLUGINS_ENABLED_JSON:-}" ]; then
      printf '%s\n' "$CLAUDE_PLUGINS_ENABLED_JSON"
    elif [ -f "${HOST_FAKE_CLAUDE_UPDATED:-/nonexistent}" ] && [ -n "${CLAUDE_PLUGINS_AFTER_JSON:-}" ]; then
      printf '%s\n' "$CLAUDE_PLUGINS_AFTER_JSON"
    elif [ -n "${CLAUDE_PLUGINS_JSON:-}" ]; then printf '%s\n' "$CLAUDE_PLUGINS_JSON"; else printf '%s\n' '[]'; fi
    ;;
  'plugin marketplace add --scope project '*|'plugin install --scope project --yes '*) exit "${HOST_FAKE_MUTATE_STATUS:-0}" ;;
  'plugin update --scope project --yes '*)
    [ "${HOST_FAKE_MUTATE_STATUS:-0}" -eq 0 ] || exit "$HOST_FAKE_MUTATE_STATUS"
    rm -rf "$HOST_FAKE_CLAUDE_CACHE"
    cp -R "$HOST_FAKE_CLAUDE_PROJECTION" "$HOST_FAKE_CLAUDE_CACHE"
    touch "$HOST_FAKE_CLAUDE_UPDATED"
    ;;
  'plugin enable --scope project '*)
    [ "${HOST_FAKE_ENABLE_STATUS:-0}" -eq 0 ] || exit "$HOST_FAKE_ENABLE_STATUS"
    touch "$HOST_FAKE_CLAUDE_ENABLED"
    ;;
  *) exit 92 ;;
esac
SH
cat > "$fake_bin/aidlc" <<'SH'
#!/bin/sh
printf 'aidlc|%s|%s|harness=%s/%s\n' "$PWD" "$*" "${AIDLC_HARNESS_DIR:-}" "${AIDLC_HARNESS_NAME:-}" >> "$HOST_FAKE_LOG"
case "$*" in
  'engine plugin select aidlc flow') exit "${AIDLC_FAKE_SELECT_STATUS:-0}" ;;
  'engine plugin sync') exit "${AIDLC_FAKE_SYNC_STATUS:-0}" ;;
  *) exit 93 ;;
esac
SH
chmod +x "$fake_bin/codex" "$fake_bin/claude" "$fake_bin/aidlc"
export HOST_FAKE_LOG="$tmp/host.log"
PATH="$fake_bin:$PATH"
export PATH

[ -f "$root/lib/plugin.sh" ] || fail "plugin install helper exists"
. "$root/lib/plugin.sh"

: > "$HOST_FAKE_LOG"
cp -R "$projection_root/codex" "$projection_root/codex-missing-adapter"
rm -rf "$projection_root/codex-missing-adapter/.agents"
set +e
missing_adapter_output=$(install_flow_plugin "$project" codex "$projection_root/codex-missing-adapter" 2>&1)
missing_adapter_status=$?
set -e
assert_eq "$missing_adapter_status" 1 "Codex projection without host marketplace adapter is rejected"
assert_contains "$missing_adapter_output" "marketplace adapter" "missing Codex adapter has a diagnostic"
assert_eq "$(cat "$HOST_FAKE_LOG")" "" "missing Codex adapter stops before host CLI"

: > "$HOST_FAKE_LOG"
cp -R "$projection_root/claude" "$projection_root/claude-version-mismatch"
perl -pi -e 's/0\.1\.0/0.1.1/g' "$projection_root/claude-version-mismatch/.claude-plugin/marketplace.json"
set +e
manifest_mismatch_output=$(install_flow_plugin "$project" claude "$projection_root/claude-version-mismatch" 2>&1)
manifest_mismatch_status=$?
set -e
assert_eq "$manifest_mismatch_status" 1 "manifest and marketplace version mismatch is rejected"
assert_contains "$manifest_mismatch_output" "metadata is invalid" "version mismatch has a projection diagnostic"
assert_eq "$(cat "$HOST_FAKE_LOG")" "" "version mismatch stops before host CLI"

: > "$HOST_FAKE_LOG"
install_flow_plugin "$project" codex "$projection_root/codex"
assert_eq "$(cat "$HOST_FAKE_LOG")" "codex|$project|plugin marketplace list --json
codex|$project|plugin marketplace add $projection_root/codex
codex|$project|plugin list --json
codex|$project|plugin add aidlc-flow@aidlc-plugins
aidlc|$project|engine plugin sync|harness=.codex/codex
aidlc|$project|engine plugin select aidlc flow|harness=.codex/codex
aidlc|$project|engine plugin sync|harness=.codex/codex" "Codex host install precedes project selection and sync"

: > "$HOST_FAKE_LOG"
CODEX_MARKETPLACES_JSON="{\"marketplaces\":[{\"name\":\"aidlc-plugins\",\"root\":\"$projection_root/codex\",\"marketplaceSource\":{\"sourceType\":\"local\",\"source\":\"$projection_root/codex\"}}]}"
CODEX_PLUGINS_JSON="{\"installed\":[{\"pluginId\":\"aidlc-flow@aidlc-plugins\",\"enabled\":true,\"version\":\"0.1.0\",\"source\":{\"source\":\"local\",\"path\":\"$projection_root/codex\"}}],\"available\":[]}"
export CODEX_MARKETPLACES_JSON CODEX_PLUGINS_JSON
install_flow_plugin "$project" codex "$projection_root/codex"
assert_eq "$(cat "$HOST_FAKE_LOG")" "codex|$project|plugin marketplace list --json
codex|$project|plugin list --json
aidlc|$project|engine plugin sync|harness=.codex/codex
aidlc|$project|engine plugin select aidlc flow|harness=.codex/codex
aidlc|$project|engine plugin sync|harness=.codex/codex" "same Codex source is host-idempotent"
unset CODEX_PLUGINS_JSON

: > "$HOST_FAKE_LOG"
printf '%s\n' 'changed Codex payload' >> "$projection_root/codex/scopes/flow-slice.md"
CODEX_MARKETPLACES_JSON="{\"marketplaces\":[{\"name\":\"aidlc-plugins\",\"root\":\"$projection_root/codex\",\"marketplaceSource\":{\"sourceType\":\"local\",\"source\":\"$projection_root/codex\"}}]}"
CODEX_PLUGINS_JSON="{\"installed\":[{\"pluginId\":\"aidlc-flow@aidlc-plugins\",\"enabled\":true,\"version\":\"0.1.0\",\"source\":{\"source\":\"local\",\"path\":\"$projection_root/codex\"}}],\"available\":[]}"
export CODEX_MARKETPLACES_JSON CODEX_PLUGINS_JSON
set +e
same_version_output=$(install_flow_plugin "$project" codex "$projection_root/codex" 2>&1)
same_version_status=$?
set -e
assert_eq "$same_version_status" 1 "same-version Codex content mismatch is rejected"
assert_contains "$same_version_output" "bump plugins/flow/.aidlc-plugin/plugin.json version" "Codex mismatch explains the required version bump"
case "$(cat "$HOST_FAKE_LOG")" in *'plugin add '*|*'config project'*|*'engine plugin sync'*) fail "Codex mismatch must stop before mutation" ;; esac
case "$(cat "$codex_cache/scopes/flow-slice.md")" in *'changed Codex payload'*) fail "Codex mismatch changed the old cache" ;; esac

perl -pi -e 's/0\.1\.0/0.1.1/g' "$projection_root/codex/.codex-plugin/plugin.json" "$projection_root/codex/.codex-plugin/marketplace.json"
codex_cache="$tmp/codex-home/plugins/cache/aidlc-plugins/aidlc-flow/0.1.1"
HOST_FAKE_CODEX_CACHE="$codex_cache"
HOST_FAKE_CODEX_UPDATED="$tmp/codex-updated"
CODEX_PLUGINS_AFTER_JSON="{\"installed\":[{\"pluginId\":\"aidlc-flow@aidlc-plugins\",\"enabled\":true,\"version\":\"0.1.1\",\"source\":{\"source\":\"local\",\"path\":\"$projection_root/codex\"}}],\"available\":[]}"
HOST_FAKE_REFRESH_CODEX=1
export HOST_FAKE_CODEX_CACHE HOST_FAKE_CODEX_UPDATED CODEX_PLUGINS_AFTER_JSON HOST_FAKE_REFRESH_CODEX
: > "$HOST_FAKE_LOG"
install_flow_plugin "$project" codex "$projection_root/codex"
assert_contains "$(cat "$HOST_FAKE_LOG")" "plugin add aidlc-flow@aidlc-plugins" "new Codex version uses the supported add update path"
assert_contains "$(cat "$codex_cache/scopes/flow-slice.md")" "changed Codex payload" "Codex version update installs changed payload"
unset CODEX_MARKETPLACES_JSON CODEX_PLUGINS_JSON CODEX_PLUGINS_AFTER_JSON HOST_FAKE_REFRESH_CODEX HOST_FAKE_CODEX_UPDATED

: > "$HOST_FAKE_LOG"
CODEX_MARKETPLACES_JSON="{\"marketplaces\":[{\"name\":\"aidlc-plugins\",\"root\":\"$projection_root/codex\",\"marketplaceSource\":{\"sourceType\":\"local\",\"source\":\"$projection_root/codex\"}}]}"
CODEX_PLUGINS_JSON='{}'
export CODEX_MARKETPLACES_JSON CODEX_PLUGINS_JSON
set +e
invalid_inventory_output=$(install_flow_plugin "$project" codex "$projection_root/codex" 2>&1)
invalid_inventory_status=$?
set -e
assert_eq "$invalid_inventory_status" 1 "invalid plugin inventory is rejected"
assert_contains "$invalid_inventory_output" "invalid Codex plugin inventory" "invalid plugin inventory has a diagnostic"
assert_eq "$(cat "$HOST_FAKE_LOG")" "codex|$project|plugin marketplace list --json
codex|$project|plugin list --json" "invalid plugin inventory stops before mutation"
unset CODEX_MARKETPLACES_JSON CODEX_PLUGINS_JSON

: > "$HOST_FAKE_LOG"
CODEX_MARKETPLACES_JSON='{"marketplaces":[{"name":"aidlc-plugins","root":"/different/source","marketplaceSource":{"sourceType":"local","source":"/different/source"}}]}'
export CODEX_MARKETPLACES_JSON
set +e
collision_output=$(install_flow_plugin "$project" codex "$projection_root/codex" 2>&1)
collision_status=$?
set -e
assert_eq "$collision_status" 1 "different Codex marketplace source is rejected"
assert_contains "$collision_output" "different source" "Codex collision explains refusal"
assert_eq "$(cat "$HOST_FAKE_LOG")" "codex|$project|plugin marketplace list --json" "Codex collision stops before mutation"
unset CODEX_MARKETPLACES_JSON

: > "$HOST_FAKE_LOG"
install_flow_plugin "$project" claude "$projection_root/claude"
assert_eq "$(cat "$HOST_FAKE_LOG")" "claude|$project|plugin marketplace list --json
claude|$project|plugin marketplace add --scope project $projection_root/claude
claude|$project|plugin list --json
claude|$project|plugin install --scope project --yes aidlc-flow@aidlc-plugins
aidlc|$project|engine plugin sync|harness=.claude/claude
aidlc|$project|engine plugin select aidlc flow|harness=.claude/claude
aidlc|$project|engine plugin sync|harness=.claude/claude" "Claude project-local install precedes project selection and sync"

: > "$HOST_FAKE_LOG"
CLAUDE_MARKETPLACES_JSON="[{\"name\":\"aidlc-plugins\",\"source\":\"directory\",\"path\":\"$projection_root/claude\",\"installLocation\":\"$projection_root/claude\"}]"
CLAUDE_PLUGINS_JSON="[{\"id\":\"aidlc-flow@aidlc-plugins\",\"version\":\"0.1.0\",\"scope\":\"project\",\"enabled\":true,\"projectPath\":\"$project\",\"installPath\":\"$claude_cache\"}]"
export CLAUDE_MARKETPLACES_JSON CLAUDE_PLUGINS_JSON
install_flow_plugin "$project" claude "$projection_root/claude"
assert_eq "$(cat "$HOST_FAKE_LOG")" "claude|$project|plugin marketplace list --json
claude|$project|plugin list --json
aidlc|$project|engine plugin sync|harness=.claude/claude
aidlc|$project|engine plugin select aidlc flow|harness=.claude/claude
aidlc|$project|engine plugin sync|harness=.claude/claude" "same Claude source is host-idempotent"
unset CLAUDE_MARKETPLACES_JSON CLAUDE_PLUGINS_JSON

: > "$HOST_FAKE_LOG"
HOST_FAKE_CLAUDE_ENABLED="$tmp/claude-enabled"
CLAUDE_MARKETPLACES_JSON="[{\"name\":\"aidlc-plugins\",\"source\":\"directory\",\"path\":\"$projection_root/claude\",\"installLocation\":\"$projection_root/claude\"}]"
CLAUDE_PLUGINS_JSON="[{\"id\":\"aidlc-flow@aidlc-plugins\",\"version\":\"0.1.0\",\"scope\":\"project\",\"enabled\":false,\"projectPath\":\"$project\",\"installPath\":\"$claude_cache\"}]"
CLAUDE_PLUGINS_ENABLED_JSON="[{\"id\":\"aidlc-flow@aidlc-plugins\",\"version\":\"0.1.0\",\"scope\":\"project\",\"enabled\":true,\"projectPath\":\"$project\",\"installPath\":\"$claude_cache\"}]"
export HOST_FAKE_CLAUDE_ENABLED CLAUDE_MARKETPLACES_JSON CLAUDE_PLUGINS_JSON CLAUDE_PLUGINS_ENABLED_JSON
install_flow_plugin "$project" claude "$projection_root/claude"
assert_contains "$(cat "$HOST_FAKE_LOG")" "plugin enable --scope project aidlc-flow@aidlc-plugins" "disabled current Claude plugin is re-enabled"
: > "$HOST_FAKE_LOG"
install_flow_plugin "$project" claude "$projection_root/claude"
case "$(cat "$HOST_FAKE_LOG")" in *'plugin enable '*|*'plugin update '*|*'plugin install '*) fail "re-enabled current Claude plugin must be host-idempotent" ;; esac
rm -f "$HOST_FAKE_CLAUDE_ENABLED"
: > "$HOST_FAKE_LOG"
HOST_FAKE_ENABLE_STATUS=42
export HOST_FAKE_ENABLE_STATUS
set +e
install_flow_plugin "$project" claude "$projection_root/claude" >/dev/null 2>&1
enable_failure_status=$?
set -e
assert_eq "$enable_failure_status" 42 "Claude enable failure propagates"
case "$(cat "$HOST_FAKE_LOG")" in *'config project'*|*'engine plugin sync'*) fail "Claude enable failure must stop before AI-DLC" ;; esac
unset HOST_FAKE_ENABLE_STATUS HOST_FAKE_CLAUDE_ENABLED CLAUDE_MARKETPLACES_JSON CLAUDE_PLUGINS_JSON CLAUDE_PLUGINS_ENABLED_JSON

: > "$HOST_FAKE_LOG"
CLAUDE_MARKETPLACES_JSON="[{\"name\":\"aidlc-plugins\",\"source\":\"directory\",\"path\":\"$projection_root/claude\",\"installLocation\":\"$projection_root/claude\"}]"
CLAUDE_PLUGINS_JSON="[{\"id\":\"aidlc-flow@aidlc-plugins\",\"version\":\"0.1.0\",\"scope\":\"project\",\"enabled\":\"false\",\"projectPath\":\"$project\",\"installPath\":\"$claude_cache\"}]"
export CLAUDE_MARKETPLACES_JSON CLAUDE_PLUGINS_JSON
set +e
invalid_enabled_output=$(install_flow_plugin "$project" claude "$projection_root/claude" 2>&1)
invalid_enabled_status=$?
set -e
assert_eq "$invalid_enabled_status" 1 "non-boolean Claude enabled state is rejected"
assert_contains "$invalid_enabled_output" "invalid Claude plugin inventory or cache" "invalid enabled state has an inventory diagnostic"
case "$(cat "$HOST_FAKE_LOG")" in *'plugin enable '*|*'plugin update '*|*'plugin install '*|*'config project'*) fail "invalid enabled state must stop before mutation" ;; esac
unset CLAUDE_MARKETPLACES_JSON CLAUDE_PLUGINS_JSON

: > "$HOST_FAKE_LOG"
printf '%s\n' 'changed Claude payload' >> "$projection_root/claude/scopes/flow-slice.md"
CLAUDE_MARKETPLACES_JSON="[{\"name\":\"aidlc-plugins\",\"source\":\"directory\",\"path\":\"$projection_root/claude\",\"installLocation\":\"$projection_root/claude\"}]"
CLAUDE_PLUGINS_JSON="[{\"id\":\"aidlc-flow@aidlc-plugins\",\"version\":\"0.1.0\",\"scope\":\"project\",\"enabled\":false,\"projectPath\":\"$project\",\"installPath\":\"$claude_cache\"}]"
export CLAUDE_MARKETPLACES_JSON CLAUDE_PLUGINS_JSON
set +e
same_version_output=$(install_flow_plugin "$project" claude "$projection_root/claude" 2>&1)
same_version_status=$?
set -e
assert_eq "$same_version_status" 1 "same-version Claude content mismatch is rejected"
assert_contains "$same_version_output" "bump plugins/flow/.aidlc-plugin/plugin.json version" "Claude mismatch explains the required version bump"
case "$(cat "$HOST_FAKE_LOG")" in *'plugin update '*|*'config project'*|*'engine plugin sync'*) fail "Claude mismatch must stop before mutation" ;; esac

perl -pi -e 's/0\.1\.0/0.1.1/g' "$projection_root/claude/.claude-plugin/plugin.json" "$projection_root/claude/.claude-plugin/marketplace.json"
claude_cache="$tmp/claude-config/plugins/cache/aidlc-plugins/aidlc-flow/0.1.1"
HOST_FAKE_CLAUDE_CACHE="$claude_cache"
HOST_FAKE_CLAUDE_UPDATED="$tmp/claude-updated"
HOST_FAKE_CLAUDE_ENABLED="$tmp/claude-enabled-after-update"
CLAUDE_PLUGINS_AFTER_JSON="[{\"id\":\"aidlc-flow@aidlc-plugins\",\"version\":\"0.1.1\",\"scope\":\"project\",\"enabled\":false,\"projectPath\":\"$project\",\"installPath\":\"$claude_cache\"}]"
CLAUDE_PLUGINS_ENABLED_JSON="[{\"id\":\"aidlc-flow@aidlc-plugins\",\"version\":\"0.1.1\",\"scope\":\"project\",\"enabled\":true,\"projectPath\":\"$project\",\"installPath\":\"$claude_cache\"}]"
export HOST_FAKE_CLAUDE_CACHE HOST_FAKE_CLAUDE_UPDATED HOST_FAKE_CLAUDE_ENABLED CLAUDE_PLUGINS_AFTER_JSON CLAUDE_PLUGINS_ENABLED_JSON
: > "$HOST_FAKE_LOG"
install_flow_plugin "$project" claude "$projection_root/claude"
assert_eq "$(cat "$HOST_FAKE_LOG")" "claude|$project|plugin marketplace list --json
claude|$project|plugin list --json
claude|$project|plugin update --scope project --yes aidlc-flow@aidlc-plugins
claude|$project|plugin list --json
claude|$project|plugin enable --scope project aidlc-flow@aidlc-plugins
claude|$project|plugin list --json
aidlc|$project|engine plugin sync|harness=.claude/claude
aidlc|$project|engine plugin select aidlc flow|harness=.claude/claude
aidlc|$project|engine plugin sync|harness=.claude/claude" "disabled Claude version update is verified before enable and sync"
assert_contains "$(cat "$HOST_FAKE_LOG")" "plugin update --scope project --yes aidlc-flow@aidlc-plugins" "new Claude version uses the supported project update path"
assert_contains "$(cat "$HOST_FAKE_LOG")" "plugin enable --scope project aidlc-flow@aidlc-plugins" "disabled Claude version is enabled after update"
assert_contains "$(cat "$claude_cache/scopes/flow-slice.md")" "changed Claude payload" "Claude version update installs changed payload"
unset CLAUDE_MARKETPLACES_JSON CLAUDE_PLUGINS_JSON CLAUDE_PLUGINS_AFTER_JSON CLAUDE_PLUGINS_ENABLED_JSON HOST_FAKE_CLAUDE_UPDATED HOST_FAKE_CLAUDE_ENABLED

for update_harness in codex claude; do
  perl -pi -e 's/0\.1\.1/0.1.2/g' "$projection_root/$update_harness/.$update_harness-plugin/plugin.json" "$projection_root/$update_harness/.$update_harness-plugin/marketplace.json"
  : > "$HOST_FAKE_LOG"
  HOST_FAKE_MUTATE_STATUS=41
  export HOST_FAKE_MUTATE_STATUS
  case "$update_harness" in
    codex)
      CODEX_MARKETPLACES_JSON="{\"marketplaces\":[{\"name\":\"aidlc-plugins\",\"root\":\"$projection_root/codex\",\"marketplaceSource\":{\"sourceType\":\"local\",\"source\":\"$projection_root/codex\"}}]}"
      CODEX_PLUGINS_JSON="{\"installed\":[{\"pluginId\":\"aidlc-flow@aidlc-plugins\",\"enabled\":true,\"version\":\"0.1.1\",\"source\":{\"source\":\"local\",\"path\":\"$projection_root/codex\"}}],\"available\":[]}"
      export CODEX_MARKETPLACES_JSON CODEX_PLUGINS_JSON
      ;;
    claude)
      CLAUDE_MARKETPLACES_JSON="[{\"name\":\"aidlc-plugins\",\"source\":\"directory\",\"path\":\"$projection_root/claude\",\"installLocation\":\"$projection_root/claude\"}]"
      CLAUDE_PLUGINS_JSON="[{\"id\":\"aidlc-flow@aidlc-plugins\",\"version\":\"0.1.1\",\"scope\":\"project\",\"enabled\":true,\"projectPath\":\"$project\",\"installPath\":\"$claude_cache\"}]"
      export CLAUDE_MARKETPLACES_JSON CLAUDE_PLUGINS_JSON
      ;;
  esac
  set +e
  install_flow_plugin "$project" "$update_harness" "$projection_root/$update_harness" >/dev/null 2>&1
  update_failure_status=$?
  set -e
  assert_eq "$update_failure_status" 41 "$update_harness version-update failure propagates"
  case "$(cat "$HOST_FAKE_LOG")" in *'config project'*|*'engine plugin sync'*) fail "$update_harness update failure must stop before AI-DLC" ;; esac
  unset HOST_FAKE_MUTATE_STATUS CODEX_MARKETPLACES_JSON CODEX_PLUGINS_JSON CLAUDE_MARKETPLACES_JSON CLAUDE_PLUGINS_JSON
done

for failure in host select sync; do
  : > "$HOST_FAKE_LOG"
  case "$failure" in
    host) HOST_FAKE_MUTATE_STATUS=31; export HOST_FAKE_MUTATE_STATUS ;;
    select) AIDLC_FAKE_SELECT_STATUS=32; export AIDLC_FAKE_SELECT_STATUS ;;
    sync) AIDLC_FAKE_SYNC_STATUS=33; export AIDLC_FAKE_SYNC_STATUS ;;
  esac
  set +e
  install_flow_plugin "$project" codex "$projection_root/codex" >/dev/null 2>&1
  failure_status=$?
  set -e
  case "$failure" in
    host)
      assert_eq "$failure_status" 31 "host CLI failure propagates"
      case "$(cat "$HOST_FAKE_LOG")" in *'config project'*|*'engine plugin sync'*) fail "host failure must stop before AI-DLC" ;; esac
      unset HOST_FAKE_MUTATE_STATUS
      ;;
    select)
      assert_eq "$failure_status" 32 "selection failure propagates"
      case "$(cat "$HOST_FAKE_LOG")" in *'engine plugin select aidlc flow'*'engine plugin sync'*) fail "selection failure must stop before final sync" ;; esac
      unset AIDLC_FAKE_SELECT_STATUS
      ;;
    sync)
      assert_eq "$failure_status" 33 "sync failure propagates"
      unset AIDLC_FAKE_SYNC_STATUS
      ;;
  esac
done

for unsafe in relative-project relative-projection projection-symlink; do
  : > "$HOST_FAKE_LOG"
  set +e
  case "$unsafe" in
    relative-project)
      (cd "$tmp" && install_flow_plugin project codex "$projection_root/codex") >/dev/null 2>&1
      unsafe_status=$?
      ;;
    relative-projection)
      (cd "$tmp" && install_flow_plugin "$project" codex plugin-dist/codex) >/dev/null 2>&1
      unsafe_status=$?
      ;;
    projection-symlink)
      ln -s "$projection_root/codex/hooks/compose.ts" "$projection_root/codex/hooks/unsafe-link"
      install_flow_plugin "$project" codex "$projection_root/codex" >/dev/null 2>&1
      unsafe_status=$?
      rm -f "$projection_root/codex/hooks/unsafe-link"
      ;;
  esac
  set -e
  [ "$unsafe_status" -ne 0 ] || fail "$unsafe is rejected"
  assert_eq "$(cat "$HOST_FAKE_LOG")" "" "$unsafe stops before host CLI"
done

printf 'PASS: plugin-install-test\n'
