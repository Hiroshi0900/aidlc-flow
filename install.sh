#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
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

if [ -d "$command_path" ] && [ ! -L "$command_path" ]; then
  printf 'aidlc-flow: command path is a directory: %s\n' "$command_path" >&2
  exit 1
fi

mkdir -p "$destination" "$bin_home"
for directory in bin lib memory; do
  rm -rf "$destination/$directory.new"
  mkdir -p "$destination/$directory.new"
  cp -R "$root/$directory/." "$destination/$directory.new/"
  rm -rf "$destination/$directory"
  mv "$destination/$directory.new" "$destination/$directory"
done
chmod +x "$destination/bin/aidlc-flow"
ln -sfn "$destination/bin/aidlc-flow" "$command_path"
printf 'Installed aidlc-flow at %s\n' "$command_path"
