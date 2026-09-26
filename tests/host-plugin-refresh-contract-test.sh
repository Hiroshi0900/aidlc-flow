#!/bin/sh
set -eu
. "$(dirname "$0")/testlib.sh"

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
real_codex=$(command -v codex 2>/dev/null) || fail "real Codex CLI is required for refresh contract test"
real_claude=$(command -v claude 2>/dev/null) || fail "real Claude CLI is required for refresh contract test"
bun_bin=$(command -v bun 2>/dev/null) || fail "bun is required for refresh contract test"
aidlc_home=${AIDLC_FLOW_AIDLC_HOME:-"${XDG_DATA_HOME:-$HOME/.local/share}/aidlc/versions/2.9.0"}
[ -d "$aidlc_home" ] || fail "AI-DLC 2.9.0 home is required for refresh contract test"

tmp=$(new_tmpdir)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
tmp=$(CDPATH= cd -- "$tmp" && pwd -P)
home="$tmp/home"
project="$tmp/project"
fake_bin="$tmp/bin"
mkdir -p "$home" "$project" "$fake_bin" "$tmp/codex-home" "$tmp/claude-config"

HOME="$home" \
AIDLC_FLOW_AIDLC_HOME="$aidlc_home" \
AIDLC_FLOW_BUN="$bun_bin" \
AIDLC_FLOW_DATA_HOME="$tmp/share" \
AIDLC_FLOW_BIN_HOME="$tmp/install-bin" \
  /bin/sh "$root/install.sh" >/dev/null

cat > "$fake_bin/codex" <<'SH'
#!/bin/sh
printf 'codex|%s\n' "$*" >> "$REAL_HOST_LOG"
exec "$REAL_CODEX_BIN" "$@"
SH
cat > "$fake_bin/claude" <<'SH'
#!/bin/sh
printf 'claude|%s\n' "$*" >> "$REAL_HOST_LOG"
exec "$REAL_CLAUDE_BIN" "$@"
SH
cat > "$fake_bin/aidlc" <<'SH'
#!/bin/sh
printf 'aidlc|%s\n' "$*" >> "$REAL_HOST_LOG"
exit 0
SH
chmod +x "$fake_bin/codex" "$fake_bin/claude" "$fake_bin/aidlc"

export HOME="$home"
export CODEX_HOME="$tmp/codex-home"
export CLAUDE_CONFIG_DIR="$tmp/claude-config"
export REAL_CODEX_BIN="$real_codex"
export REAL_CLAUDE_BIN="$real_claude"
export REAL_HOST_LOG="$tmp/host.log"
PATH="$fake_bin:$PATH"
export PATH
. "$root/lib/plugin.sh"

project_digest() (
  cd "$project"
  find . -type f -print | LC_ALL=C sort | while IFS= read -r file; do
    shasum -a 256 "$file"
  done | shasum -a 256
)

tree_digest() (
  cd "$1"
  find . -type f -print | LC_ALL=C sort | while IFS= read -r file; do
    shasum -a 256 "$file"
  done | shasum -a 256
)

host_list() {
  case "$1" in
    codex) "$real_codex" plugin list --json ;;
    claude) (cd "$project" && "$real_claude" plugin list --json) ;;
  esac
}

for harness in codex claude; do
  projection="$tmp/share/aidlc-flow/plugin-dist/$harness"
  : > "$REAL_HOST_LOG"
  install_flow_plugin "$project" "$harness" "$projection" >/dev/null
  host_list "$harness" > "$tmp/$harness-before.json"
  project_before=$(project_digest)
  case "$harness" in
    codex) initial_cache="$CODEX_HOME/plugins/cache/aidlc-plugins/aidlc-flow/0.1.0" ;;
    claude)
      initial_cache=$(python3 - "$tmp/$harness-before.json" "$project" <<'PY'
import json, os, sys
entries = json.load(open(sys.argv[1], encoding="utf-8"))
matches = [entry for entry in entries if entry.get("id") == "aidlc-flow@aidlc-plugins" and entry.get("scope") == "project" and os.path.realpath(entry.get("projectPath", "")) == os.path.realpath(sys.argv[2])]
if len(matches) != 1 or not isinstance(matches[0].get("installPath"), str):
    raise SystemExit("Claude project cache is missing")
print(matches[0]["installPath"])
PY
      )
      ;;
  esac
  cache_before=$(tree_digest "$initial_cache")

  printf '\n// immutable-version-mismatch-%s\n' "$harness" >> "$projection/hooks/compose.ts"
  : > "$REAL_HOST_LOG"
  set +e
  mismatch_output=$(install_flow_plugin "$project" "$harness" "$projection" 2>&1)
  mismatch_status=$?
  set -e
  assert_eq "$mismatch_status" 1 "$harness rejects changed content at the installed version"
  assert_contains "$mismatch_output" "bump plugins/flow/.aidlc-plugin/plugin.json version" "$harness mismatch has an actionable diagnostic"
  case "$(cat "$REAL_HOST_LOG")" in
    *'plugin add '*|*'plugin update '*|*'plugin install '*|*'config project'*|*'engine plugin sync'*)
      fail "$harness same-version mismatch mutated host or project state"
      ;;
  esac
  host_list "$harness" > "$tmp/$harness-after-mismatch.json"
  python3 - "$tmp/$harness-before.json" "$tmp/$harness-after-mismatch.json" <<'PY' || fail "same-version refusal changed host inventory"
import json, sys
if json.load(open(sys.argv[1], encoding="utf-8")) != json.load(open(sys.argv[2], encoding="utf-8")):
    raise SystemExit("host inventory changed")
PY
  assert_eq "$(project_digest)" "$project_before" "$harness same-version refusal preserves project config"
  assert_eq "$(tree_digest "$initial_cache")" "$cache_before" "$harness same-version refusal preserves the installed cache"

  perl -pi -e 's/0\.1\.0/0.1.1/g' "$projection/.$harness-plugin/plugin.json" "$projection/.$harness-plugin/marketplace.json"
  marker="version-contract-$harness"
  printf '\n%s\n' "$marker" >> "$projection/scopes/flow-slice.md"
  : > "$REAL_HOST_LOG"
  install_flow_plugin "$project" "$harness" "$projection" >/dev/null
  host_list "$harness" > "$tmp/$harness-updated.json"
  cache=$(python3 - "$tmp/$harness-updated.json" "$harness" "$CODEX_HOME" "$project" <<'PY'
import json, os, sys
value = json.load(open(sys.argv[1], encoding="utf-8"))
harness, codex_home, project = sys.argv[2:]
if harness == "codex":
    entries = value.get("installed", [])
    matches = [entry for entry in entries if entry.get("pluginId") == "aidlc-flow@aidlc-plugins"]
    if len(matches) != 1 or matches[0].get("version") != "0.1.1":
        raise SystemExit("Codex inventory did not update to 0.1.1")
    print(os.path.join(codex_home, "plugins", "cache", "aidlc-plugins", "aidlc-flow", "0.1.1"))
else:
    matches = [entry for entry in value if entry.get("id") == "aidlc-flow@aidlc-plugins" and entry.get("scope") == "project" and os.path.realpath(entry.get("projectPath", "")) == os.path.realpath(project)]
    if len(matches) != 1 or matches[0].get("version") != "0.1.1" or not isinstance(matches[0].get("installPath"), str):
        raise SystemExit("Claude inventory did not update to 0.1.1")
    print(matches[0]["installPath"])
PY
  )
  assert_contains "$(cat "$cache/scopes/flow-slice.md")" "$marker" "$harness version update installs changed content"
  case "$harness" in
    codex) assert_contains "$(cat "$REAL_HOST_LOG")" "codex|plugin add aidlc-flow@aidlc-plugins" "Codex uses plugin add for a new version" ;;
    claude) assert_contains "$(cat "$REAL_HOST_LOG")" "claude|plugin update --scope project --yes aidlc-flow@aidlc-plugins" "Claude uses project plugin update for a new version" ;;
  esac

  : > "$REAL_HOST_LOG"
  install_flow_plugin "$project" "$harness" "$projection" >/dev/null
  case "$(cat "$REAL_HOST_LOG")" in
    *'plugin add '*|*'plugin update '*|*'plugin install '*) fail "unchanged $harness projection must skip host mutation" ;;
  esac
done

printf 'PASS: host-plugin-refresh-contract-test\n'
