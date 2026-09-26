#!/bin/sh

plugin_toolchain_die() {
  printf 'aidlc-flow: %s\n' "$*" >&2
  return 1
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
    aidlc_flow_aidlc_home="$aidlc_flow_data_root/aidlc/versions/$aidlc_flow_active_version"
  fi

  # The trust boundary begins at the selected version home. HOME/XDG ancestors
  # may legitimately be symlinks, but the version runtime itself must not be.
  for aidlc_flow_runtime_path in \
    "$aidlc_flow_aidlc_home" \
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
