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
  mkdir -p "$fixture/.$fixture_harness-plugin" "$fixture/hooks"
  printf '%s\n' "{\"schema\":1,\"producer\":\"aidlc-plugin-build\",\"plugin\":\"flow\",\"harness\":\"$fixture_harness\"}" > "$fixture/.aidlc-plugin-projection.json"
  printf '%s\n' '{"name":"aidlc-flow","version":"0.1.0"}' > "$fixture/.$fixture_harness-plugin/plugin.json"
  printf '%s\n' '{"name":"aidlc-plugins","plugins":[{"name":"aidlc-flow","source":".","version":"0.1.0"}]}' > "$fixture/.$fixture_harness-plugin/marketplace.json"
  printf '%s\n' 'export async function compose() {}' > "$fixture/hooks/compose.ts"
  if [ "$fixture_harness" = codex ]; then
    mkdir -p "$fixture/.agents/plugins"
    printf '%s\n' '{"name":"aidlc-plugins","plugins":[{"name":"aidlc-flow","source":{"source":"local","path":"./"},"policy":{"installation":"AVAILABLE","authentication":"ON_USE"}}]}' > "$fixture/.agents/plugins/marketplace.json"
  fi
}
make_projection codex
make_projection claude

cat > "$fake_bin/codex" <<'SH'
#!/bin/sh
printf 'codex|%s|%s\n' "$PWD" "$*" >> "$HOST_FAKE_LOG"
case "$*" in
  'plugin marketplace list --json')
    if [ -n "${CODEX_MARKETPLACES_JSON:-}" ]; then printf '%s\n' "$CODEX_MARKETPLACES_JSON"; else printf '%s\n' '{"marketplaces":[]}'; fi
    ;;
  'plugin list --json')
    if [ -n "${CODEX_PLUGINS_JSON:-}" ]; then printf '%s\n' "$CODEX_PLUGINS_JSON"; else printf '%s\n' '{"installed":[],"available":[]}'; fi
    ;;
  'plugin marketplace add '*|'plugin add '*) exit "${HOST_FAKE_MUTATE_STATUS:-0}" ;;
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
    if [ -n "${CLAUDE_PLUGINS_JSON:-}" ]; then printf '%s\n' "$CLAUDE_PLUGINS_JSON"; else printf '%s\n' '[]'; fi
    ;;
  'plugin marketplace add --scope project '*|'plugin install --scope project --yes '*) exit "${HOST_FAKE_MUTATE_STATUS:-0}" ;;
  *) exit 92 ;;
esac
SH
cat > "$fake_bin/aidlc" <<'SH'
#!/bin/sh
printf 'aidlc|%s|%s|harness=%s/%s\n' "$PWD" "$*" "${AIDLC_HARNESS_DIR:-}" "${AIDLC_HARNESS_NAME:-}" >> "$HOST_FAKE_LOG"
case "$*" in
  'config project --project-dir '*" --plugins flow --yes") exit "${AIDLC_FAKE_SELECT_STATUS:-0}" ;;
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
install_flow_plugin "$project" codex "$projection_root/codex"
assert_eq "$(cat "$HOST_FAKE_LOG")" "codex|$project|plugin marketplace list --json
codex|$project|plugin marketplace add $projection_root/codex
codex|$project|plugin list --json
codex|$project|plugin add aidlc-flow@aidlc-plugins
aidlc|$project|config project --project-dir $project --plugins flow --yes|harness=/
aidlc|$project|engine plugin sync|harness=.codex/codex" "Codex host install precedes project selection and sync"

: > "$HOST_FAKE_LOG"
CODEX_MARKETPLACES_JSON="{\"marketplaces\":[{\"name\":\"aidlc-plugins\",\"root\":\"$projection_root/codex\",\"marketplaceSource\":{\"sourceType\":\"local\",\"source\":\"$projection_root/codex\"}}]}"
CODEX_PLUGINS_JSON='{"installed":[{"pluginId":"aidlc-flow@aidlc-plugins","enabled":true}],"available":[]}'
export CODEX_MARKETPLACES_JSON CODEX_PLUGINS_JSON
install_flow_plugin "$project" codex "$projection_root/codex"
assert_eq "$(cat "$HOST_FAKE_LOG")" "codex|$project|plugin marketplace list --json
codex|$project|plugin list --json
aidlc|$project|config project --project-dir $project --plugins flow --yes|harness=/
aidlc|$project|engine plugin sync|harness=.codex/codex" "same Codex source is host-idempotent"
unset CODEX_PLUGINS_JSON

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
aidlc|$project|config project --project-dir $project --plugins flow --yes|harness=/
aidlc|$project|engine plugin sync|harness=.claude/claude" "Claude project-local install precedes project selection and sync"

: > "$HOST_FAKE_LOG"
CLAUDE_MARKETPLACES_JSON="[{\"name\":\"aidlc-plugins\",\"source\":\"directory\",\"path\":\"$projection_root/claude\",\"installLocation\":\"$projection_root/claude\"}]"
CLAUDE_PLUGINS_JSON="[{\"id\":\"aidlc-flow@aidlc-plugins\",\"scope\":\"project\",\"enabled\":true,\"projectPath\":\"$project\"}]"
export CLAUDE_MARKETPLACES_JSON CLAUDE_PLUGINS_JSON
install_flow_plugin "$project" claude "$projection_root/claude"
assert_eq "$(cat "$HOST_FAKE_LOG")" "claude|$project|plugin marketplace list --json
claude|$project|plugin list --json
aidlc|$project|config project --project-dir $project --plugins flow --yes|harness=/
aidlc|$project|engine plugin sync|harness=.claude/claude" "same Claude source is host-idempotent"
unset CLAUDE_MARKETPLACES_JSON CLAUDE_PLUGINS_JSON

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
      case "$(cat "$HOST_FAKE_LOG")" in *'engine plugin sync'*) fail "selection failure must stop before sync" ;; esac
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
