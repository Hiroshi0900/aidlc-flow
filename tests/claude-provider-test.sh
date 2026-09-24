#!/bin/sh
set -eu
. "$(dirname "$0")/testlib.sh"

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
tmp=$(new_tmpdir)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
project="$tmp/project"
fake_bin="$tmp/bin"
mkdir -p "$project" "$fake_bin"
git -C "$project" init -q

cat > "$fake_bin/aidlc" <<'SH'
#!/bin/sh
command_name=$1
shift
project_dir=$PWD
while [ "$#" -gt 0 ]; do
  case "$1" in
    --project-dir)
      project_dir=$2
      shift 2
      ;;
    *) shift ;;
  esac
done

case "$command_name" in
  config)
    mkdir -p "$project_dir/.claude" "$project_dir/aidlc/spaces/default/memory/phases"
    printf '%s\n' 'default' > "$project_dir/aidlc/active-space"
    printf '%s\n' 'official team seed' > "$project_dir/aidlc/spaces/default/memory/team.md"
    printf '%s\n' 'official construction seed' > "$project_dir/aidlc/spaces/default/memory/phases/construction.md"
    cat > "$project_dir/.claude/settings.json" <<'JSON'
{
  "env": {
    "AWS_AIDLC_DEFAULT_SCOPE": "classic",
    "CLAUDE_CODE_USE_BEDROCK": "1",
    "AWS_REGION": "us-east-1",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "global.anthropic.claude-opus-4-8[1m]"
  }
}
JSON
    ;;
  doctor) ;;
  *) exit 9 ;;
esac
SH
chmod +x "$fake_bin/aidlc"

PATH="$fake_bin:$PATH" "$root/bin/aidlc-flow" init --harness claude --project-dir "$project" >/dev/null
settings=$(cat "$project/.claude/settings.json")

case "$settings" in
  *CLAUDE_CODE_USE_BEDROCK*|*AWS_REGION*|*ANTHROPIC_DEFAULT_OPUS_MODEL*)
    fail "Claude bootstrap must not leave Bedrock provider settings"
    ;;
esac
case "$settings" in
  *AWS_AIDLC_DEFAULT_SCOPE*) ;;
  *) fail "Claude bootstrap must preserve unrelated AI-DLC environment settings" ;;
esac

printf 'PASS: claude-provider-test\n'
