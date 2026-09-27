#!/bin/sh

aidlc_flow_required_version=2.9.0
aidlc_flow_required_version_report="aidlc $aidlc_flow_required_version (runtime $aidlc_flow_required_version)"

plugin_toolchain_die() {
  printf 'aidlc-flow: %s\n' "$*" >&2
  return 1
}

require_aidlc_plugin_version() {
  aidlc_flow_reported_version=$(aidlc --version 2>/dev/null) ||
    plugin_toolchain_die "unable to read PATH AI-DLC version" || return
  [ "$aidlc_flow_reported_version" = "$aidlc_flow_required_version_report" ] ||
    plugin_toolchain_die "PATH AI-DLC must report exactly $aidlc_flow_required_version_report; found: $aidlc_flow_reported_version" || return
}

require_plugin_toolchain() {
  if [ -n "${AIDLC_FLOW_BUN:-}" ]; then
    aidlc_flow_bun=$AIDLC_FLOW_BUN
  else
    aidlc_flow_bun=$(command -v bun 2>/dev/null) ||
      plugin_toolchain_die "bun is required to build plugin projections" || return
  fi
  [ -x "$aidlc_flow_bun" ] ||
    plugin_toolchain_die "bun is not executable: $aidlc_flow_bun" || return

  if [ -n "${AIDLC_FLOW_AIDLC_HOME:-}" ]; then
    aidlc_flow_aidlc_home=$AIDLC_FLOW_AIDLC_HOME
    case "$aidlc_flow_aidlc_home" in
      /*) ;;
      *) plugin_toolchain_die "AIDLC_FLOW_AIDLC_HOME must be an absolute path: $aidlc_flow_aidlc_home" || return ;;
    esac
  else
    aidlc_flow_data_root=${XDG_DATA_HOME:-"$HOME/.local/share"}
    case "$aidlc_flow_data_root" in
      /*) ;;
      *) plugin_toolchain_die "AI-DLC data home must be an absolute path: $aidlc_flow_data_root" || return ;;
    esac
    aidlc_flow_active_version_file="$aidlc_flow_data_root/aidlc/active-version"
    [ -f "$aidlc_flow_active_version_file" ] && [ ! -L "$aidlc_flow_active_version_file" ] ||
      plugin_toolchain_die "AI-DLC active-version marker is missing or unsafe: $aidlc_flow_active_version_file" || return
    aidlc_flow_active_version=$(awk 'NR == 1 { value = $0 } NR > 1 { extra = 1 } END { if (NR != 1 || extra) exit 1; print value }' \
      "$aidlc_flow_active_version_file") ||
      plugin_toolchain_die "AI-DLC active-version marker must contain exactly one line" || return
    case "$aidlc_flow_active_version" in
      ''|.|..|.*|*[!0-9A-Za-z._+-]*)
        plugin_toolchain_die "unsafe AI-DLC active version: $aidlc_flow_active_version" || return
        ;;
    esac
    [ "$aidlc_flow_active_version" = "$aidlc_flow_required_version" ] ||
      plugin_toolchain_die "AI-DLC active version must be $aidlc_flow_required_version; found: $aidlc_flow_active_version" || return
    aidlc_flow_aidlc_home="$aidlc_flow_data_root/aidlc/versions/$aidlc_flow_active_version"
  fi

  # The trust boundary begins at the selected version home. HOME/XDG ancestors
  # may legitimately be symlinks, but the version runtime itself must not be.
  [ -d "$aidlc_flow_aidlc_home" ] && [ ! -L "$aidlc_flow_aidlc_home" ] ||
    plugin_toolchain_die "AI-DLC runtime path is missing or unsafe: $aidlc_flow_aidlc_home" || return
  aidlc_flow_selected_aidlc="$aidlc_flow_aidlc_home/aidlc"
  [ -f "$aidlc_flow_selected_aidlc" ] && [ ! -L "$aidlc_flow_selected_aidlc" ] &&
    [ -x "$aidlc_flow_selected_aidlc" ] ||
    plugin_toolchain_die "selected AI-DLC runtime executable is missing or unsafe: $aidlc_flow_selected_aidlc" || return
  aidlc_flow_selected_version=$("$aidlc_flow_selected_aidlc" --version 2>/dev/null) ||
    plugin_toolchain_die "unable to read selected AI-DLC runtime version: $aidlc_flow_selected_aidlc" || return
  [ "$aidlc_flow_selected_version" = "$aidlc_flow_required_version_report" ] ||
    plugin_toolchain_die "selected AI-DLC runtime must report exactly $aidlc_flow_required_version_report; found: $aidlc_flow_selected_version" || return

  for aidlc_flow_runtime_path in \
    "$aidlc_flow_aidlc_home/runtime" \
    "$aidlc_flow_aidlc_home/runtime/claude" \
    "$aidlc_flow_aidlc_home/runtime/claude/.claude"
  do
    [ -d "$aidlc_flow_runtime_path" ] && [ ! -L "$aidlc_flow_runtime_path" ] ||
      plugin_toolchain_die "AI-DLC runtime path is missing or unsafe: $aidlc_flow_runtime_path" || return
  done
  aidlc_flow_tools="$aidlc_flow_aidlc_home/runtime/claude/.claude/tools"
  [ -d "$aidlc_flow_tools" ] && [ ! -L "$aidlc_flow_tools" ] ||
    plugin_toolchain_die "AI-DLC source tools directory is missing or unsafe: $aidlc_flow_tools" || return
  for aidlc_flow_tool in aidlc-plugin-validate.ts aidlc-plugin-build.ts; do
    [ -f "$aidlc_flow_tools/$aidlc_flow_tool" ] && [ ! -L "$aidlc_flow_tools/$aidlc_flow_tool" ] ||
      plugin_toolchain_die "AI-DLC source tool is missing or unsafe: $aidlc_flow_tools/$aidlc_flow_tool" || return
  done
}

validate_flow_plugin() {
  aidlc_flow_plugin_root=$1
  "$aidlc_flow_bun" "$aidlc_flow_tools/aidlc-plugin-validate.ts" "$aidlc_flow_plugin_root"
}

build_flow_projection() {
  aidlc_flow_harness=$1
  aidlc_flow_output_dir=$2
  aidlc_flow_plugin_root=$3
  "$aidlc_flow_bun" "$aidlc_flow_tools/aidlc-plugin-build.ts" \
    "$aidlc_flow_plugin_root" "$aidlc_flow_harness" "$aidlc_flow_output_dir"
}

build_codex_marketplace_adapter() {
  aidlc_flow_codex_projection=$1
  aidlc_flow_codex_manifest_dir="$aidlc_flow_codex_projection/.codex-plugin"
  aidlc_flow_codex_adapter_dir="$aidlc_flow_codex_projection/.agents/plugins"
  [ -d "$aidlc_flow_codex_projection" ] && [ ! -L "$aidlc_flow_codex_projection" ] ||
    plugin_toolchain_die "Codex projection root is missing or unsafe: $aidlc_flow_codex_projection" || return
  for aidlc_flow_codex_manifest in plugin.json marketplace.json; do
    [ -f "$aidlc_flow_codex_manifest_dir/$aidlc_flow_codex_manifest" ] &&
      [ ! -L "$aidlc_flow_codex_manifest_dir/$aidlc_flow_codex_manifest" ] ||
      plugin_toolchain_die "official Codex manifest is missing or unsafe: $aidlc_flow_codex_manifest_dir/$aidlc_flow_codex_manifest" || return
  done
  [ ! -e "$aidlc_flow_codex_projection/.agents" ] ||
    plugin_toolchain_die "Codex marketplace adapter path already exists: $aidlc_flow_codex_projection/.agents" || return
  mkdir -p "$aidlc_flow_codex_adapter_dir" || return
  python3 - \
    "$aidlc_flow_codex_manifest_dir/plugin.json" \
    "$aidlc_flow_codex_manifest_dir/marketplace.json" \
    "$aidlc_flow_codex_adapter_dir/marketplace.json" <<'PY'
import json
import os
import sys

plugin_path, marketplace_path, output_path = sys.argv[1:]
with open(plugin_path, encoding="utf-8") as source:
    plugin = json.load(source)
with open(marketplace_path, encoding="utf-8") as source:
    marketplace = json.load(source)
entries = marketplace.get("plugins") if isinstance(marketplace, dict) else None
if not isinstance(plugin, dict) or not isinstance(entries, list) or len(entries) != 1:
    raise SystemExit("official Codex manifests do not describe exactly one plugin")
entry = entries[0]
if not isinstance(entry, dict):
    raise SystemExit("official Codex marketplace plugin entry is invalid")
name = plugin.get("name")
version = plugin.get("version")
if (
    marketplace.get("name") != "aidlc-plugins"
    or name != "aidlc-flow"
    or entry.get("name") != name
    or entry.get("source") != "."
    or entry.get("version") != version
):
    raise SystemExit("official Codex marketplace and plugin manifests disagree")
adapter = {
    "name": marketplace["name"],
    "plugins": [
        {
            "name": name,
            "source": {"source": "local", "path": "./"},
            "policy": {
                "installation": "AVAILABLE",
                "authentication": "ON_USE",
            },
        }
    ],
}
temporary = output_path + ".tmp"
with open(temporary, "w", encoding="utf-8") as destination:
    json.dump(adapter, destination, indent=2, ensure_ascii=False)
    destination.write("\n")
os.replace(temporary, output_path)
PY
}
