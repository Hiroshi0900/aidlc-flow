#!/bin/sh
set -eu
. "$(dirname "$0")/testlib.sh"

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
tmp=$(new_tmpdir)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
tmp=$(CDPATH= cd -- "$tmp" && pwd -P)
project="$tmp/project"
fake_bin="$tmp/bin"
projection="$tmp/plugin-dist/claude"
mkdir -p "$project" "$fake_bin" "$projection/.claude-plugin" "$projection/hooks"
git -C "$project" init -q
printf '%s\n' '{"schema":1,"producer":"aidlc-plugin-build","plugin":"flow","harness":"claude"}' > "$projection/.aidlc-plugin-projection.json"
printf '%s\n' '{"name":"aidlc-flow","version":"0.1.0"}' > "$projection/.claude-plugin/plugin.json"
printf '%s\n' '{"name":"aidlc-plugins","plugins":[{"name":"aidlc-flow","source":".","version":"0.1.0"}]}' > "$projection/.claude-plugin/marketplace.json"
printf '%s\n' 'export async function compose() {}' > "$projection/hooks/compose.ts"

cat > "$fake_bin/claude" <<'SH'
#!/bin/sh
case "$*" in
  'plugin marketplace list --json') printf '%s\n' '[]' ;;
  'plugin list --json') printf '%s\n' '[]' ;;
  'plugin marketplace add --scope project '*|'plugin install --scope project --yes '*) ;;
  *) exit 8 ;;
esac
SH
chmod +x "$fake_bin/claude"

cat > "$fake_bin/aidlc" <<'SH'
#!/bin/sh
if [ "$*" = '--version' ]; then
  printf '%s\n' 'aidlc 2.9.0 (runtime 2.9.0)'
  exit 0
fi
if [ "$*" = 'engine plugin sync' ]; then
  exit 0
fi
if [ "$*" = 'engine plugin select aidlc flow' ]; then
  exit 0
fi
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

AIDLC_FLOW_PLUGIN_DIST="$tmp/plugin-dist" PATH="$fake_bin:$PATH" "$root/bin/aidlc-flow" init --harness claude --project-dir "$project" >/dev/null
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
