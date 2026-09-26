#!/bin/sh

plugin_install_die() {
  printf 'aidlc-flow: %s\n' "$*" >&2
  return 1
}

plugin_real_directory() {
  aidlc_flow_real_input=$1
  aidlc_flow_real_label=$2
  case "$aidlc_flow_real_input" in
    /*) ;;
    *) plugin_install_die "$aidlc_flow_real_label must be an absolute path: $aidlc_flow_real_input" || return ;;
  esac
  [ -d "$aidlc_flow_real_input" ] && [ ! -L "$aidlc_flow_real_input" ] ||
    plugin_install_die "$aidlc_flow_real_label is not a real directory: $aidlc_flow_real_input" || return
  aidlc_flow_real_canonical=$(CDPATH= cd -- "$aidlc_flow_real_input" 2>/dev/null && pwd -P) ||
    plugin_install_die "unable to resolve $aidlc_flow_real_label: $aidlc_flow_real_input" || return
  [ "$aidlc_flow_real_canonical" = "$aidlc_flow_real_input" ] ||
    plugin_install_die "$aidlc_flow_real_label must be canonical: $aidlc_flow_real_input" || return
}

validate_flow_projection() {
  aidlc_flow_projection=$1
  aidlc_flow_projection_harness=$2
  aidlc_flow_manifest_dir="$aidlc_flow_projection/.$aidlc_flow_projection_harness-plugin"
  for aidlc_flow_projection_file in \
    "$aidlc_flow_projection/.aidlc-plugin-projection.json" \
    "$aidlc_flow_manifest_dir/plugin.json" \
    "$aidlc_flow_manifest_dir/marketplace.json"
  do
    [ -f "$aidlc_flow_projection_file" ] && [ ! -L "$aidlc_flow_projection_file" ] ||
      plugin_install_die "plugin projection file is missing or unsafe: $aidlc_flow_projection_file" || return
  done
  if [ "$aidlc_flow_projection_harness" = codex ]; then
    aidlc_flow_codex_adapter="$aidlc_flow_projection/.agents/plugins/marketplace.json"
    [ -f "$aidlc_flow_codex_adapter" ] && [ ! -L "$aidlc_flow_codex_adapter" ] ||
      plugin_install_die "Codex marketplace adapter is missing or unsafe: $aidlc_flow_codex_adapter" || return
  fi
  if [ -n "$(find "$aidlc_flow_projection" -type l -print -quit 2>/dev/null)" ]; then
    plugin_install_die "symbolic link is not allowed in plugin projection: $aidlc_flow_projection" || return
  fi
  if ! python3 - "$aidlc_flow_projection" "$aidlc_flow_projection_harness" <<'PY'
import json
import os
import sys

root, harness = sys.argv[1:]
manifest_dir = os.path.join(root, f".{harness}-plugin")
with open(os.path.join(root, ".aidlc-plugin-projection.json"), encoding="utf-8") as source:
    projection = json.load(source)
with open(os.path.join(manifest_dir, "plugin.json"), encoding="utf-8") as source:
    plugin = json.load(source)
with open(os.path.join(manifest_dir, "marketplace.json"), encoding="utf-8") as source:
    marketplace = json.load(source)
expected = {"schema": 1, "producer": "aidlc-plugin-build", "plugin": "flow", "harness": harness}
if projection != expected:
    raise SystemExit("invalid projection metadata")
if plugin.get("name") != "aidlc-flow" or not isinstance(plugin.get("version"), str):
    raise SystemExit("invalid host plugin manifest")
if marketplace.get("name") != "aidlc-plugins":
    raise SystemExit("invalid marketplace name")
entries = marketplace.get("plugins")
if not isinstance(entries, list) or len(entries) != 1:
    raise SystemExit("invalid marketplace plugin list")
entry = entries[0]
if not isinstance(entry, dict) or entry.get("name") != "aidlc-flow" or entry.get("source") != ".":
    raise SystemExit("invalid marketplace plugin entry")
if entry.get("version") != plugin.get("version"):
    raise SystemExit("plugin version mismatch")
if harness == "codex":
    with open(os.path.join(root, ".agents", "plugins", "marketplace.json"), encoding="utf-8") as source:
        adapter = json.load(source)
    expected_adapter = {
        "name": "aidlc-plugins",
        "plugins": [
            {
                "name": "aidlc-flow",
                "source": {"source": "local", "path": "./"},
                "policy": {"installation": "AVAILABLE", "authentication": "ON_USE"},
            }
        ],
    }
    if adapter != expected_adapter:
        raise SystemExit("invalid Codex marketplace adapter")
PY
  then
    plugin_install_die "plugin projection metadata is invalid: $aidlc_flow_projection" || return
  fi
}

refuse_dirty_managed_plugin() {
  aidlc_flow_plugin_project=$1
  aidlc_flow_plugin_harness=$2
  case "$aidlc_flow_plugin_harness" in
    codex|claude) ;;
    *) plugin_install_die "unsupported harness: $aidlc_flow_plugin_harness" || return ;;
  esac
  python3 - "$aidlc_flow_plugin_project" ".$aidlc_flow_plugin_harness" <<'PY' || {
import hashlib
import json
import os
import re
import sys

project, harness_dir = sys.argv[1:]
data_dir = os.path.join(project, harness_dir, "tools", "data")

for path in (
    os.path.join(project, harness_dir),
    os.path.join(project, harness_dir, "tools"),
    data_dir,
):
    if os.path.islink(path):
        raise SystemExit(f"symbolic link in managed plugin path: {path}")

degraded = []
aidlc_root = os.path.join(project, "aidlc")
if os.path.isdir(aidlc_root) and not os.path.islink(aidlc_root):
    for current, directories, files in os.walk(aidlc_root, followlinks=False):
        if any(os.path.islink(os.path.join(current, name)) for name in directories):
            raise SystemExit(f"symbolic link in managed plugin evidence: {current}")
        for name in files:
            if name != "plugin-compose-flow.drops":
                continue
            path = os.path.join(current, name)
            if os.path.islink(path):
                raise SystemExit(f"symbolic link in managed plugin evidence: {path}")
            with open(path, encoding="utf-8") as source:
                if "[degraded]" in source.read():
                    degraded.append(path)
if degraded:
    raise SystemExit(f"degraded plugin composition evidence: {degraded[0]}")

stamp_path = os.path.join(data_dir, "plugin-compose-flow.json")
owned_path = os.path.join(data_dir, "plugin-owned-flow.json")
stamp_exists = os.path.lexists(stamp_path)
owned_exists = os.path.lexists(owned_path)
if not stamp_exists and not owned_exists:
    raise SystemExit(0)
if stamp_exists != owned_exists:
    raise SystemExit("incomplete managed plugin composition evidence")
if os.path.islink(stamp_path) or os.path.islink(owned_path):
    raise SystemExit("symbolic link in managed plugin composition evidence")
try:
    with open(stamp_path, encoding="utf-8") as source:
        stamp = json.load(source)
    with open(owned_path, encoding="utf-8") as source:
        owned = json.load(source)
except (OSError, ValueError) as error:
    raise SystemExit(f"invalid managed plugin composition evidence: {error}")
if (
    stamp.get("schemaVersion") != 1
    or stamp.get("name") != "flow"
    or not isinstance(stamp.get("version"), str)
    or not re.fullmatch(r"sha256:[0-9a-f]{64}", stamp.get("sourceHash", ""))
):
    raise SystemExit("invalid managed plugin composition stamp")
if owned.get("schemaVersion") != 1 or owned.get("name") != "flow" or not isinstance(owned.get("files"), list):
    raise SystemExit("invalid managed plugin ownership record")
project_real = os.path.realpath(project)
for entry in owned["files"]:
    if not isinstance(entry, dict) or not isinstance(entry.get("path"), str):
        raise SystemExit("invalid managed plugin ownership entry")
    relative = entry["path"]
    expected = entry.get("sha256")
    if os.path.isabs(relative) or ".." in relative.replace("\\", "/").split("/"):
        raise SystemExit(f"unsafe managed plugin path: {relative}")
    component = project
    for part in relative.replace("\\", "/").split("/"):
        component = os.path.join(component, part)
        if os.path.islink(component):
            raise SystemExit(f"symbolic link in managed plugin path: {relative}")
    target = os.path.join(project, relative)
    target_real = os.path.realpath(target)
    if os.path.commonpath((project_real, target_real)) != project_real:
        raise SystemExit(f"managed plugin path escapes project: {relative}")
    if os.path.islink(target) or not os.path.isfile(target):
        raise SystemExit(f"managed plugin path is missing or unsafe: {relative}")
    digest = "sha256:" + hashlib.sha256(open(target, "rb").read()).hexdigest()
    if not isinstance(expected, str) or digest != expected:
        raise SystemExit(f"managed plugin path changed since composition: {relative}")
PY
    plugin_install_die "managed plugin state requires attention before configuration" || return
  }
}

install_flow_plugin() (
  set -e
  aidlc_flow_project=$1
  aidlc_flow_harness=$2
  aidlc_flow_projection=$3
  plugin_real_directory "$aidlc_flow_project" "project directory" || exit
  plugin_real_directory "$aidlc_flow_projection" "plugin projection" || exit
  case "$aidlc_flow_harness" in
    codex|claude) ;;
    *) plugin_install_die "unsupported harness: $aidlc_flow_harness"; exit 1 ;;
  esac
  validate_flow_projection "$aidlc_flow_projection" "$aidlc_flow_harness" || exit

  aidlc_flow_inventory=$(mktemp -d "${TMPDIR:-/tmp}/aidlc-flow-host-inventory.XXXXXX") || {
    plugin_install_die "unable to create host inventory staging"
    exit 1
  }
  trap 'rm -rf "$aidlc_flow_inventory"' EXIT HUP INT TERM
  aidlc_flow_marketplaces="$aidlc_flow_inventory/marketplaces.json"
  aidlc_flow_plugins="$aidlc_flow_inventory/plugins.json"

  cd "$aidlc_flow_project"
  case "$aidlc_flow_harness" in
    codex)
      codex plugin marketplace list --json > "$aidlc_flow_marketplaces"
      aidlc_flow_marketplace_state=$(python3 - "$aidlc_flow_marketplaces" "$aidlc_flow_projection" <<'PY'
import json, os, sys
with open(sys.argv[1], encoding="utf-8") as source:
    value = json.load(source)
entries = value.get("marketplaces") if isinstance(value, dict) else None
if not isinstance(entries, list):
    raise SystemExit("invalid Codex marketplace inventory")
matches = [entry for entry in entries if isinstance(entry, dict) and entry.get("name") == "aidlc-plugins"]
if not matches:
    print("missing")
elif len(matches) != 1:
    raise SystemExit("ambiguous Codex marketplace inventory")
else:
    entry = matches[0]
    source = entry.get("marketplaceSource")
    path = source.get("source") if isinstance(source, dict) and source.get("sourceType") == "local" else None
    if not isinstance(path, str):
        print("collision")
    elif os.path.realpath(path) == os.path.realpath(sys.argv[2]):
        print("same")
    else:
        print("collision")
PY
      ) || { plugin_install_die "invalid Codex marketplace inventory"; exit 1; }
      case "$aidlc_flow_marketplace_state" in
        missing) codex plugin marketplace add "$aidlc_flow_projection" ;;
        same) ;;
        collision) plugin_install_die "marketplace aidlc-plugins already uses a different source"; exit 1 ;;
        *) plugin_install_die "invalid Codex marketplace inventory result"; exit 1 ;;
      esac
      codex plugin list --json > "$aidlc_flow_plugins"
      aidlc_flow_plugin_state=$(python3 - "$aidlc_flow_plugins" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as source:
    value = json.load(source)
entries = value.get("installed") if isinstance(value, dict) else None
if not isinstance(entries, list):
    raise SystemExit("invalid Codex plugin inventory")
matches = [entry for entry in entries if isinstance(entry, dict) and entry.get("pluginId") == "aidlc-flow@aidlc-plugins"]
print("enabled" if any(entry.get("enabled") is True for entry in matches) else "missing")
PY
      ) || { plugin_install_die "invalid Codex plugin inventory"; exit 1; }
      case "$aidlc_flow_plugin_state" in
        enabled) ;;
        missing) codex plugin add aidlc-flow@aidlc-plugins ;;
        *) plugin_install_die "invalid Codex plugin inventory result"; exit 1 ;;
      esac
      ;;
    claude)
      claude plugin marketplace list --json > "$aidlc_flow_marketplaces"
      aidlc_flow_marketplace_state=$(python3 - "$aidlc_flow_marketplaces" "$aidlc_flow_projection" <<'PY'
import json, os, sys
with open(sys.argv[1], encoding="utf-8") as source:
    entries = json.load(source)
if not isinstance(entries, list):
    raise SystemExit("invalid Claude marketplace inventory")
matches = [entry for entry in entries if isinstance(entry, dict) and entry.get("name") == "aidlc-plugins"]
if not matches:
    print("missing")
elif len(matches) != 1:
    raise SystemExit("ambiguous Claude marketplace inventory")
else:
    entry = matches[0]
    path = entry.get("path") if entry.get("source") == "directory" else None
    if not isinstance(path, str):
        print("collision")
    elif os.path.realpath(path) == os.path.realpath(sys.argv[2]):
        print("same")
    else:
        print("collision")
PY
      ) || { plugin_install_die "invalid Claude marketplace inventory"; exit 1; }
      case "$aidlc_flow_marketplace_state" in
        missing) claude plugin marketplace add --scope project "$aidlc_flow_projection" ;;
        same) ;;
        collision) plugin_install_die "marketplace aidlc-plugins already uses a different source"; exit 1 ;;
        *) plugin_install_die "invalid Claude marketplace inventory result"; exit 1 ;;
      esac
      claude plugin list --json > "$aidlc_flow_plugins"
      aidlc_flow_plugin_state=$(python3 - "$aidlc_flow_plugins" "$aidlc_flow_project" <<'PY'
import json, os, sys
with open(sys.argv[1], encoding="utf-8") as source:
    entries = json.load(source)
if not isinstance(entries, list):
    raise SystemExit("invalid Claude plugin inventory")
matches = [entry for entry in entries if isinstance(entry, dict) and entry.get("id") == "aidlc-flow@aidlc-plugins"]
enabled = any(
    entry.get("enabled") is True
    and entry.get("scope") == "project"
    and isinstance(entry.get("projectPath"), str)
    and os.path.realpath(entry["projectPath"]) == os.path.realpath(sys.argv[2])
    for entry in matches
)
print("enabled" if enabled else "missing")
PY
      ) || { plugin_install_die "invalid Claude plugin inventory"; exit 1; }
      case "$aidlc_flow_plugin_state" in
        enabled) ;;
        missing) claude plugin install --scope project --yes aidlc-flow@aidlc-plugins ;;
        *) plugin_install_die "invalid Claude plugin inventory result"; exit 1 ;;
      esac
      ;;
  esac

  aidlc config project --project-dir "$aidlc_flow_project" --plugins flow --yes
  AIDLC_HARNESS_DIR=".$aidlc_flow_harness" AIDLC_HARNESS_NAME="$aidlc_flow_harness" \
    aidlc engine plugin sync
)
