#!/bin/sh

die() {
  aidlc_flow_die_code=$1
  shift
  printf 'aidlc-flow: %s\n' "$*" >&2
  exit "$aidlc_flow_die_code"
}

require_git_repo() {
  aidlc_flow_git_project_dir=$1
  if aidlc_flow_git_state=$(git -C "$aidlc_flow_git_project_dir" rev-parse --is-inside-work-tree 2>/dev/null); then
    [ "$aidlc_flow_git_state" = "true" ] ||
      die 2 "not a Git repository: $aidlc_flow_git_project_dir"
  else
    die 2 "not a Git repository: $aidlc_flow_git_project_dir"
  fi
}

require_aidlc() {
  command -v aidlc >/dev/null 2>&1 || die 1 "aidlc is not installed; install it from https://github.com/awslabs/aidlc-workflows/releases/latest"
}

active_space() {
  aidlc_flow_space_project_dir=$1
  aidlc_flow_space_pointer="$aidlc_flow_space_project_dir/aidlc/active-space"
  if [ -f "$aidlc_flow_space_pointer" ]; then
    aidlc_flow_space_value=$(sed -n '1p' "$aidlc_flow_space_pointer")
  else
    aidlc_flow_space_value=default
  fi
  case "$aidlc_flow_space_value" in
    ''|.|..|*[!A-Za-z0-9._-]*) die 1 "invalid AI-DLC active space: $aidlc_flow_space_value" ;;
  esac
  printf '%s\n' "$aidlc_flow_space_value"
}

refuse_active_workflow() {
  aidlc_flow_workflow_project_dir=$1
  aidlc_flow_workflow_intents="$aidlc_flow_workflow_project_dir/aidlc/spaces"
  [ -d "$aidlc_flow_workflow_intents" ] || return 0
  if grep -R -E -q '\*\*Status\*\*: (in_progress|Running|Awaiting|Revising)' "$aidlc_flow_workflow_intents" 2>/dev/null; then
    die 1 "an AI-DLC workflow is active; complete or park it before refreshing configuration"
  else
    aidlc_flow_workflow_grep_status=$?
    case "$aidlc_flow_workflow_grep_status" in
      1) return 0 ;;
      *) die 1 "unable to inspect AI-DLC workflow status: $aidlc_flow_workflow_intents" ;;
    esac
  fi
}

merge_managed_block() {
  aidlc_flow_merge_destination=$1
  aidlc_flow_merge_source_file=$2
  aidlc_flow_merge_key=$3
  aidlc_flow_merge_begin="<!-- BEGIN aidlc-flow:$aidlc_flow_merge_key -->"
  aidlc_flow_merge_end="<!-- END aidlc-flow:$aidlc_flow_merge_key -->"
  aidlc_flow_merge_destination_dir=$(dirname "$aidlc_flow_merge_destination")

  [ -f "$aidlc_flow_merge_source_file" ] && [ -r "$aidlc_flow_merge_source_file" ] || return 1
  mkdir -p "$aidlc_flow_merge_destination_dir" || return 1

  if grep -F -x -q \
    -e "$aidlc_flow_merge_begin" \
    -e "$aidlc_flow_merge_end" \
    "$aidlc_flow_merge_source_file" 2>/dev/null; then
    return 1
  else
    aidlc_flow_merge_grep_status=$?
    [ "$aidlc_flow_merge_grep_status" -eq 1 ] || return 1
  fi

  aidlc_flow_merge_mode=create
  if [ -e "$aidlc_flow_merge_destination" ]; then
    if aidlc_flow_merge_begins=$(grep -F -x -c "$aidlc_flow_merge_begin" "$aidlc_flow_merge_destination" 2>/dev/null); then
      :
    else
      aidlc_flow_merge_grep_status=$?
      [ "$aidlc_flow_merge_grep_status" -eq 1 ] || return 1
    fi
    if aidlc_flow_merge_ends=$(grep -F -x -c "$aidlc_flow_merge_end" "$aidlc_flow_merge_destination" 2>/dev/null); then
      :
    else
      aidlc_flow_merge_grep_status=$?
      [ "$aidlc_flow_merge_grep_status" -eq 1 ] || return 1
    fi

    if [ "$aidlc_flow_merge_begins" -eq 0 ] && [ "$aidlc_flow_merge_ends" -eq 0 ]; then
      aidlc_flow_merge_mode=append
    elif [ "$aidlc_flow_merge_begins" -eq 1 ] && [ "$aidlc_flow_merge_ends" -eq 1 ]; then
      aidlc_flow_merge_mode=replace
    else
      return 1
    fi
  fi

  aidlc_flow_merge_tmp=$(mktemp "$aidlc_flow_merge_destination_dir/.aidlc-flow.XXXXXX") || return 1

  case "$aidlc_flow_merge_mode" in
    create)
      {
        printf '%s\n' "$aidlc_flow_merge_begin" &&
        awk '{ print }' "$aidlc_flow_merge_source_file" &&
        printf '%s\n' "$aidlc_flow_merge_end"
      } > "$aidlc_flow_merge_tmp" || {
        rm -f "$aidlc_flow_merge_tmp"
        return 1
      }
      ;;
    append)
      {
        cat "$aidlc_flow_merge_destination" &&
        printf '\n%s\n' "$aidlc_flow_merge_begin" &&
        awk '{ print }' "$aidlc_flow_merge_source_file" &&
        printf '%s\n' "$aidlc_flow_merge_end"
      } > "$aidlc_flow_merge_tmp" || {
        rm -f "$aidlc_flow_merge_tmp"
        return 1
      }
      ;;
    replace)
      awk \
        -v begin="$aidlc_flow_merge_begin" \
        -v end="$aidlc_flow_merge_end" \
        -v source="$aidlc_flow_merge_source_file" '
          $0 == begin {
            print begin
            while ((source_status = getline line < source) > 0) print line
            if (source_status < 0) exit 4
            close(source)
            managed = 1
            next
          }
          managed && $0 == end { print end; managed = 0; next }
          !managed { print }
          END { if (managed) exit 3 }
        ' "$aidlc_flow_merge_destination" > "$aidlc_flow_merge_tmp" || {
          rm -f "$aidlc_flow_merge_tmp"
          return 1
        }
      ;;
  esac

  if [ -e "$aidlc_flow_merge_destination" ] &&
    cmp -s "$aidlc_flow_merge_destination" "$aidlc_flow_merge_tmp"; then
    rm -f "$aidlc_flow_merge_tmp"
    return $?
  fi
  if mv "$aidlc_flow_merge_tmp" "$aidlc_flow_merge_destination"; then
    return 0
  fi
  rm -f "$aidlc_flow_merge_tmp"
  return 1
}
