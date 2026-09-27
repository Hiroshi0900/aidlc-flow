#!/bin/sh
set -eu
. "$(dirname "$0")/testlib.sh"

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
codex_bin=$(command -v codex 2>/dev/null) || fail "real Codex CLI is required for marketplace contract test"
bun_bin=$(command -v bun 2>/dev/null) || fail "bun is required for marketplace contract test"
aidlc_home=${AIDLC_FLOW_AIDLC_HOME:-"${XDG_DATA_HOME:-$HOME/.local/share}/aidlc/versions/2.9.0"}
[ -d "$aidlc_home" ] || fail "AI-DLC 2.9.0 home is required for marketplace contract test"

tmp=$(new_tmpdir)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
tmp=$(CDPATH= cd -- "$tmp" && pwd -P)
mkdir -p "$tmp/home" "$tmp/codex-home"

HOME="$tmp/home" \
AIDLC_FLOW_AIDLC_HOME="$aidlc_home" \
AIDLC_FLOW_BUN="$bun_bin" \
AIDLC_FLOW_DATA_HOME="$tmp/share" \
AIDLC_FLOW_BIN_HOME="$tmp/bin" \
  /bin/sh "$root/install.sh" >/dev/null

projection="$tmp/share/aidlc-flow/plugin-dist/codex"
[ -f "$projection/.codex-plugin/marketplace.json" ] || fail "official Codex marketplace output is preserved"
[ -f "$projection/.agents/plugins/marketplace.json" ] || fail "Codex marketplace adapter is generated"

HOME="$tmp/home" CODEX_HOME="$tmp/codex-home" \
  "$codex_bin" plugin marketplace add "$projection" --json > "$tmp/marketplace-add.json"
python3 - "$tmp/marketplace-add.json" "$projection" <<'PY' || fail "real Codex accepts generated marketplace adapter"
import json
import os
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    result = json.load(source)
if result.get("marketplaceName") != "aidlc-plugins":
    raise SystemExit(f"unexpected marketplace name: {result!r}")
if os.path.realpath(result.get("installedRoot", "")) != os.path.realpath(sys.argv[2]):
    raise SystemExit(f"unexpected marketplace root: {result!r}")
PY

HOME="$tmp/home" CODEX_HOME="$tmp/codex-home" \
  "$codex_bin" plugin marketplace list --json > "$tmp/marketplace-list.json"
python3 - "$tmp/marketplace-list.json" "$projection" <<'PY' || fail "real Codex inventory contains local marketplace"
import json
import os
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    result = json.load(source)
entries = result.get("marketplaces") if isinstance(result, dict) else None
if not isinstance(entries, list):
    raise SystemExit(f"unexpected marketplace inventory: {result!r}")
matches = [entry for entry in entries if isinstance(entry, dict) and entry.get("name") == "aidlc-plugins"]
if len(matches) != 1:
    raise SystemExit(f"unexpected marketplace entries: {matches!r}")
marketplace_source = matches[0].get("marketplaceSource")
if not isinstance(marketplace_source, dict) or marketplace_source.get("sourceType") != "local":
    raise SystemExit(f"unexpected marketplace source: {matches[0]!r}")
if os.path.realpath(marketplace_source.get("source", "")) != os.path.realpath(sys.argv[2]):
    raise SystemExit(f"unexpected marketplace source path: {matches[0]!r}")
PY

HOME="$tmp/home" CODEX_HOME="$tmp/codex-home" \
  "$codex_bin" plugin add aidlc-flow@aidlc-plugins --json > "$tmp/plugin-add.json"
python3 - "$tmp/plugin-add.json" "$tmp/codex-home" <<'PY' || fail "real Codex installs plugin from generated marketplace adapter"
import json
import os
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    result = json.load(source)
if result.get("pluginId") != "aidlc-flow@aidlc-plugins":
    raise SystemExit(f"unexpected plugin id: {result!r}")
installed = result.get("installedPath")
if not isinstance(installed, str) or os.path.commonpath((os.path.realpath(sys.argv[2]), os.path.realpath(installed))) != os.path.realpath(sys.argv[2]):
    raise SystemExit(f"plugin escaped isolated CODEX_HOME: {result!r}")
PY

HOME="$tmp/home" CODEX_HOME="$tmp/codex-home" \
  "$codex_bin" plugin list --json > "$tmp/plugin-list.json"
python3 - "$tmp/plugin-list.json" "$projection" <<'PY' || fail "real Codex inventory reports installed local plugin"
import json
import os
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    result = json.load(source)
entries = result.get("installed") if isinstance(result, dict) else None
if not isinstance(entries, list):
    raise SystemExit(f"unexpected plugin inventory: {result!r}")
matches = [entry for entry in entries if isinstance(entry, dict) and entry.get("pluginId") == "aidlc-flow@aidlc-plugins"]
if len(matches) != 1 or matches[0].get("enabled") is not True:
    raise SystemExit(f"unexpected plugin entries: {matches!r}")
marketplace_source = matches[0].get("marketplaceSource")
if not isinstance(marketplace_source, dict) or os.path.realpath(marketplace_source.get("source", "")) != os.path.realpath(sys.argv[2]):
    raise SystemExit(f"unexpected plugin marketplace source: {matches[0]!r}")
plugin_source = matches[0].get("source")
if not isinstance(plugin_source, dict) or plugin_source.get("source") != "local":
    raise SystemExit(f"unexpected plugin source: {matches[0]!r}")
if os.path.realpath(plugin_source.get("path", "")) != os.path.realpath(sys.argv[2]):
    raise SystemExit(f"local plugin source did not resolve to projection root: {matches[0]!r}")
PY

printf 'PASS: codex-marketplace-contract-test\n'
