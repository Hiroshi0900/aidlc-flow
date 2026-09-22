#!/bin/sh
set -eu

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_eq() {
  actual=$1
  expected=$2
  message=$3
  [ "$actual" = "$expected" ] || fail "$message: expected '$expected', got '$actual'"
}

assert_contains() {
  haystack=$1
  needle=$2
  message=$3
  case "$haystack" in
    *"$needle"*) ;;
    *) fail "$message: missing '$needle'" ;;
  esac
}

new_tmpdir() {
  mktemp -d "${TMPDIR:-/tmp}/aidlc-flow-test.XXXXXX"
}
