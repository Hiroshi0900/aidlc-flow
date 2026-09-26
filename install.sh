#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
. "$root/lib/aidlc-plugin-tools.sh"
data_home=${AIDLC_FLOW_DATA_HOME:-"$HOME/.local/share"}
bin_home=${AIDLC_FLOW_BIN_HOME:-"$HOME/.local/bin"}

case "$data_home" in
  /*) ;;
  *)
    printf 'aidlc-flow: AIDLC_FLOW_DATA_HOME must be an absolute path: %s\n' "$data_home" >&2
    exit 2
    ;;
esac
case "$bin_home" in
  /*) ;;
  *)
    printf 'aidlc-flow: AIDLC_FLOW_BIN_HOME must be an absolute path: %s\n' "$bin_home" >&2
    exit 2
    ;;
esac

destination="$data_home/aidlc-flow"
command_path="$bin_home/aidlc-flow"

[ ! -L "$destination" ] || {
  printf 'aidlc-flow: install destination must not be a symbolic link: %s\n' "$destination" >&2
  exit 1
}
if [ -d "$command_path" ] && [ ! -L "$command_path" ]; then
  printf 'aidlc-flow: command path is a directory: %s\n' "$command_path" >&2
  exit 1
fi

require_plugin_toolchain

cleanup_staging() {
  for staging_name in bin lib memory plugins plugin-dist; do
    rm -rf "$destination/$staging_name.new"
  done
}

replace_installed_tree() {
  installed_name=$1
  rm -rf "$destination/$installed_name.old"
  if [ -e "$destination/$installed_name" ] || [ -L "$destination/$installed_name" ]; then
    mv "$destination/$installed_name" "$destination/$installed_name.old"
  fi
  if mv "$destination/$installed_name.new" "$destination/$installed_name"; then
    rm -rf "$destination/$installed_name.old"
    return 0
  fi
  if [ -e "$destination/$installed_name.old" ] || [ -L "$destination/$installed_name.old" ]; then
    mv "$destination/$installed_name.old" "$destination/$installed_name"
  fi
  return 1
}

mkdir -p "$destination" "$bin_home"
trap cleanup_staging EXIT HUP INT TERM
cleanup_staging
for directory in bin lib memory plugins; do
  rm -rf "$destination/$directory.new"
  mkdir -p "$destination/$directory.new"
  cp -R "$root/$directory/." "$destination/$directory.new/"
done

validate_flow_plugin "$destination/plugins.new/flow" || {
  printf 'aidlc-flow: failed to validate plugin source\n' >&2
  exit 1
}
mkdir -p "$destination/plugin-dist.new"
for harness in codex claude; do
  build_flow_projection "$harness" "$destination/plugin-dist.new/$harness" \
    "$destination/plugins.new/flow" || {
    printf 'aidlc-flow: failed to build %s plugin projection\n' "$harness" >&2
    exit 1
  }
done

for directory in bin lib memory plugins plugin-dist; do
  replace_installed_tree "$directory" || {
    printf 'aidlc-flow: failed to install %s\n' "$directory" >&2
    exit 1
  }
done
chmod +x "$destination/bin/aidlc-flow"
ln -sfn "$destination/bin/aidlc-flow" "$command_path"
trap - EXIT HUP INT TERM
printf 'Installed aidlc-flow at %s\n' "$command_path"
