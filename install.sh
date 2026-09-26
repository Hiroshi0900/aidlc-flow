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
elif [ -e "$command_path" ] && [ ! -L "$command_path" ]; then
  printf 'aidlc-flow: command path is not a symbolic link: %s\n' "$command_path" >&2
  exit 1
fi

require_plugin_toolchain

mkdir -p "$data_home" "$bin_home"
staging="$data_home/aidlc-flow.new"
backup="$data_home/aidlc-flow.old"
destination_had_previous=false
destination_swap_started=false
command_had_previous=false
command_previous_target=
command_update_attempted=false
install_committed=false

rollback_install() {
  rollback_status=$?
  trap - EXIT HUP INT TERM
  set +e

  if [ "$install_committed" != true ]; then
    if [ "$destination_swap_started" = true ]; then
      rm -rf "$destination"
      if [ "$destination_had_previous" = true ] && [ -e "$backup" ]; then
        mv "$backup" "$destination"
      fi
    elif [ "$destination_had_previous" = true ] &&
      [ ! -e "$destination" ] && [ -e "$backup" ]; then
      mv "$backup" "$destination"
    fi

    if [ "$command_update_attempted" = true ]; then
      if [ -L "$command_path" ]; then
        rm -f "$command_path"
      fi
      if [ "$command_had_previous" = true ]; then
        ln -s "$command_previous_target" "$command_path"
      fi
    fi
  fi

  rm -rf "$staging"
  if [ "$install_committed" = true ]; then
    rm -rf "$backup"
  fi
  [ "$rollback_status" -ne 0 ] || rollback_status=1
  exit "$rollback_status"
}

trap rollback_install EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

[ ! -e "$backup" ] && [ ! -L "$backup" ] || {
  printf 'aidlc-flow: install backup path already exists: %s\n' "$backup" >&2
  exit 1
}
rm -rf "$staging"
mkdir -p "$staging"
for directory in bin lib memory plugins; do
  mkdir -p "$staging/$directory"
  cp -R "$root/$directory/." "$staging/$directory/"
done

validate_flow_plugin "$staging/plugins/flow" || {
  printf 'aidlc-flow: failed to validate plugin source\n' >&2
  exit 1
}
mkdir -p "$staging/plugin-dist"
for harness in codex claude; do
  build_flow_projection "$harness" "$staging/plugin-dist/$harness" \
    "$staging/plugins/flow" || {
    printf 'aidlc-flow: failed to build %s plugin projection\n' "$harness" >&2
    exit 1
  }
done
chmod +x "$staging/bin/aidlc-flow"

if [ -L "$command_path" ]; then
  command_had_previous=true
  command_previous_target=$(readlink "$command_path")
fi

if [ -e "$destination" ]; then
  destination_had_previous=true
  mv "$destination" "$backup"
fi
destination_swap_started=true
mv "$staging" "$destination"
command_update_attempted=true
ln -sfn "$destination/bin/aidlc-flow" "$command_path"
install_committed=true
rm -rf "$backup"
trap - EXIT HUP INT TERM
printf 'Installed aidlc-flow at %s\n' "$command_path"
