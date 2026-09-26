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
if [ -e "$destination" ] && [ ! -d "$destination" ]; then
  printf 'aidlc-flow: install destination is not a directory: %s\n' "$destination" >&2
  exit 1
fi
if [ -d "$command_path" ] && [ ! -L "$command_path" ]; then
  printf 'aidlc-flow: command path is a directory: %s\n' "$command_path" >&2
  exit 1
elif [ -e "$command_path" ] && [ ! -L "$command_path" ]; then
  printf 'aidlc-flow: command path is not a symbolic link: %s\n' "$command_path" >&2
  exit 1
fi

validate_existing_destination() {
  [ -d "$destination" ] || return 0
  install_marker="$destination/.aidlc-flow-install"
  if [ -e "$install_marker" ] || [ -L "$install_marker" ]; then
    if [ ! -f "$install_marker" ] || [ -L "$install_marker" ] ||
      [ "$(cat "$install_marker"; printf x)" != "$(printf 'schema=1\nowner=aidlc-flow\nx')" ]; then
      printf 'aidlc-flow: existing install marker is invalid: %s\n' "$install_marker" >&2
      return 1
    fi
  elif [ ! -d "$destination/bin" ] || [ -L "$destination/bin" ] ||
    [ ! -f "$destination/bin/aidlc-flow" ] || [ -L "$destination/bin/aidlc-flow" ] ||
    [ ! -d "$destination/lib" ] || [ -L "$destination/lib" ] ||
    [ ! -d "$destination/memory" ] || [ -L "$destination/memory" ]; then
    printf 'aidlc-flow: existing install destination is not owned by aidlc-flow: %s\n' \
      "$destination" >&2
    return 1
  fi
}

validate_existing_destination

mkdir -p "$data_home"
lock_path="$data_home/.aidlc-flow-install.lock"
lock_owned=false
staging=
backup_root=
backup=
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

  if [ -n "$staging" ]; then
    rm -rf "$staging"
  fi
  if [ "$install_committed" = true ]; then
    if [ -n "$backup_root" ]; then
      rm -rf "$backup_root"
    fi
  elif [ -n "$backup_root" ] && [ ! -e "$backup" ]; then
    rmdir "$backup_root" 2>/dev/null
  fi
  if [ "$lock_owned" = true ]; then
    rmdir "$lock_path" 2>/dev/null
    lock_owned=false
  fi
  [ "$rollback_status" -ne 0 ] || rollback_status=1
  exit "$rollback_status"
}

trap rollback_install EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

if mkdir "$lock_path" 2>/dev/null; then
  lock_owned=true
else
  printf 'aidlc-flow: installation is already in progress; if no installer is running, inspect lock: %s\n' \
    "$lock_path" >&2
  exit 1
fi

validate_existing_destination
require_plugin_toolchain
mkdir -p "$bin_home"

staging=$(mktemp -d "$data_home/.aidlc-flow.new.XXXXXX") || {
  printf 'aidlc-flow: unable to create install staging directory\n' >&2
  exit 1
}
backup_root=$(mktemp -d "$data_home/.aidlc-flow.backup.XXXXXX") || {
  printf 'aidlc-flow: unable to create install backup directory\n' >&2
  exit 1
}
backup="$backup_root/aidlc-flow"
if [ -d "$destination" ]; then
  cp -R "$destination/." "$staging/"
fi
# cp -R preserves optional legacy subtree symlinks. These removals target only
# children of our private staging tree, so rm removes a link rather than its target.
for directory in bin lib memory plugins plugin-dist; do
  rm -rf "$staging/$directory"
done
printf 'schema=1\nowner=aidlc-flow\n' >"$staging/.aidlc-flow-install"
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
rm -rf "$backup_root"
rmdir "$lock_path"
lock_owned=false
trap - EXIT HUP INT TERM
printf 'Installed aidlc-flow at %s\n' "$command_path"
