#!/bin/sh

# Plugin-contract helpers. Generic assertions remain in testlib.sh.

plugin_frontmatter() {
  awk '
    NR == 1 && $0 == "---" { opened = 1; next }
    opened && $0 == "---" { closed = 1; exit }
    opened { print }
    END { if (!opened || !closed) exit 1 }
  ' "$1"
}

plugin_yaml_scalar() {
  frontmatter=$1
  key=$2
  printf '%s\n' "$frontmatter" | awk -v key="$key" '
    index($0, key ": ") == 1 {
      sub("^" key ": ", "")
      print
    }
  '
}

plugin_yaml_list() {
  frontmatter=$1
  key=$2
  printf '%s\n' "$frontmatter" | awk -v key="$key" '
    $0 == key ":" { in_list = 1; next }
    in_list && /^  - / {
      sub(/^  - /, "")
      print
      next
    }
    in_list && $0 !~ /^  / { in_list = 0 }
  '
}

plugin_yaml_nested_list() {
  frontmatter=$1
  parent=$2
  key=$3
  printf '%s\n' "$frontmatter" | awk -v parent="$parent" -v key="$key" '
    $0 == parent ":" { in_parent = 1; next }
    in_parent && $0 == "  " key ":" { in_list = 1; next }
    in_list && /^    - / {
      sub(/^    - /, "")
      print
      next
    }
    in_list && $0 !~ /^    / { in_list = 0 }
    in_parent && $0 !~ /^  / { in_parent = 0; in_list = 0 }
  '
}

plugin_yaml_object_list_field() {
  frontmatter=$1
  parent=$2
  key=$3
  printf '%s\n' "$frontmatter" | awk -v parent="$parent" -v key="$key" '
    $0 == parent ":" { in_parent = 1; next }
    in_parent && index($0, "  - " key ": ") == 1 {
      sub("^  - " key ": ", "")
      print
      next
    }
    in_parent && $0 !~ /^  / { in_parent = 0 }
  '
}
