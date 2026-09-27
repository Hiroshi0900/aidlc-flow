#!/bin/sh
set -eu
. "$(dirname "$0")/testlib.sh"

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
tmp=$(new_tmpdir)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
fake_bin="$tmp/bin"
real_bin="$tmp/real-bin"
version_tmp="$tmp/version-tmp"
mkdir -p "$fake_bin" "$real_bin" "$version_tmp"

. "$root/lib/common.sh"
. "$root/lib/aidlc-plugin-tools.sh"

cat >"$real_bin/aidlc" <<'SH'
#!/bin/sh
[ "${1:-}" = --version ] && [ "$#" -eq 1 ] || exit 64
case "${AIDLC_FAKE_VERSION_SHAPE:-line}" in
  line) printf '%s\n' "${AIDLC_FAKE_VERSION_REPORT:-aidlc 2.9.0 (runtime 2.9.0)}" ;;
  trailing-empty) printf '%s\n\n' 'aidlc 2.9.0 (runtime 2.9.0)' ;;
  leading-empty) printf '\n%s\n' 'aidlc 2.9.0 (runtime 2.9.0)' ;;
  multiple) printf '%s\n%s\n' 'aidlc 2.9.0 (runtime 2.9.0)' extra ;;
  no-newline) printf '%s' 'aidlc 2.9.0 (runtime 2.9.0)' ;;
  nul) printf '%s\000\n' 'aidlc 2.9.0 (runtime 2.9.0)' ;;
  failure) exit 23 ;;
  *) exit 65 ;;
esac
SH
chmod +x "$real_bin/aidlc"
ln -s "$real_bin/aidlc" "$fake_bin/aidlc"
system_path=$PATH
guard_path="$fake_bin:$system_path"

TMPDIR="$version_tmp" PATH="$guard_path" require_aidlc ||
  fail "symlinked PATH AI-DLC launcher should pass the command-presence guard"
TMPDIR="$version_tmp" PATH="$guard_path" require_aidlc_plugin_version ||
  fail "symlinked PATH AI-DLC launcher with exact version output should be accepted"
[ -z "$(find "$version_tmp" -mindepth 1 -print)" ] ||
  fail "successful PATH version validation cleans temporary capture state"

assert_path_version_rejected() {
  rejected_shape=$1
  rejected_report=${2:-}
  if rejected_output=$(AIDLC_FAKE_VERSION_SHAPE="$rejected_shape" \
    AIDLC_FAKE_VERSION_REPORT="$rejected_report" TMPDIR="$version_tmp" \
    PATH="$guard_path" require_aidlc_plugin_version 2>&1); then
    fail "PATH AI-DLC version output is rejected: $rejected_shape $rejected_report"
  fi
  assert_contains "$rejected_output" \
    "PATH AI-DLC must report exactly aidlc 2.9.0 (runtime 2.9.0)" \
    "PATH version rejection explains the exact contract"
  [ -z "$(find "$version_tmp" -mindepth 1 -print)" ] ||
    fail "PATH version rejection cleans temporary capture state"
}

for rejected_report in \
  'aidlc 2.8.0 (runtime 2.8.0)' \
  'aidlc 3.0.0 (runtime 3.0.0)' \
  'prefix aidlc 2.9.0 (runtime 2.9.0)' \
  'aidlc 2.9.0 (runtime 2.9.0) suffix'
do
  assert_path_version_rejected line "$rejected_report"
done
for rejected_shape in trailing-empty leading-empty multiple no-newline nul; do
  assert_path_version_rejected "$rejected_shape"
done

if failure_output=$(AIDLC_FAKE_VERSION_SHAPE=failure TMPDIR="$version_tmp" \
  PATH="$guard_path" require_aidlc_plugin_version 2>&1); then
  fail "failing PATH AI-DLC version command is rejected"
fi
assert_contains "$failure_output" "unable to read PATH AI-DLC version" \
  "failing PATH version command reports execution failure"
[ -z "$(find "$version_tmp" -mindepth 1 -print)" ] ||
  fail "failing PATH version command cleans temporary capture state"

missing_bin="$tmp/missing-bin"
mkdir -p "$missing_bin"
if missing_output=$(PATH="$missing_bin" require_aidlc 2>&1); then
  fail "missing PATH AI-DLC is rejected"
fi
assert_contains "$missing_output" "aidlc is not installed" \
  "missing PATH AI-DLC is owned by the command-presence guard"

non_executable_bin="$tmp/non-executable-bin"
mkdir -p "$non_executable_bin"
cp "$real_bin/aidlc" "$non_executable_bin/aidlc"
chmod -x "$non_executable_bin/aidlc"
if non_executable_output=$(PATH="$non_executable_bin" require_aidlc 2>&1); then
  fail "non-executable PATH AI-DLC is rejected"
fi
assert_contains "$non_executable_output" "aidlc is not installed" \
  "non-executable PATH AI-DLC is owned by the command-presence guard"

project="$tmp/project"
mkdir -p "$project"
git -C "$project" init -q
printf 'keep project state\n' >"$project/sentinel"
project_before=$(find "$project" -type f -exec cksum {} \; | sort)
if init_output=$(AIDLC_FAKE_VERSION_SHAPE=trailing-empty TMPDIR="$version_tmp" \
  PATH="$guard_path" "$root/bin/aidlc-flow" init --harness codex \
  --project-dir "$project" 2>&1); then
  fail "init rejects malformed PATH AI-DLC version output"
fi
assert_contains "$init_output" \
  "PATH AI-DLC must report exactly aidlc 2.9.0 (runtime 2.9.0)" \
  "init reports the PATH version contract before mutation"
project_after=$(find "$project" -type f -exec cksum {} \; | sort)
assert_eq "$project_after" "$project_before" \
  "PATH version rejection preserves project state before init mutation"
[ -z "$(find "$version_tmp" -mindepth 1 -print)" ] ||
  fail "init version rejection cleans temporary capture state"

printf 'PASS: aidlc-version-test\n'
