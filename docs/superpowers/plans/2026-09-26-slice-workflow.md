# Vertical Slice Workflow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `aidlc-flow` に、1 intent・1 PR・mainへのマージを単位とするAI-DLC v2.9.0向け縦切りワークフローを追加する。

**Architecture:** `plugins/aidlc-flow-slice/` を公式AI-DLCプラグインのソースとして管理し、公式のvalidate/buildでCodex・Claude projectionを生成する。`install.sh` がprojectionを安定したインストール先へ置き、`aidlc-flow init` がホストのローカルmarketplace経由でプラグインを有効化してから、公式plugin sync・doctorで検証する。scopeはcore reviewerを停止し、Build and Test後の専用レビューstageだけを独立レビューとして実行する。

**Tech Stack:** POSIX shell、AI-DLC CLI v2.9.0 plugin API、Codex/Claude plugin marketplace、Markdown stage/scope definitions、既存shellテストハーネス

---

## ファイル構成

- `plugins/aidlc-flow-slice/.aidlc-plugin/plugin.json`: plugin source manifest。論理plugin名は `flow-slice`、ホスト上の名前は `aidlc-flow-slice`。
- `plugins/aidlc-flow-slice/scopes/aidlc-flow-slice.md`: Minimal depth、Standard test strategy、review capなしのscope。
- `plugins/aidlc-flow-slice/stages/inception/slice-contract.md`: 1〜3件の受入条件と最初の境界テストを固定する。
- `plugins/aidlc-flow-slice/stages/construction/slice-review.md`: Build and Test後の唯一の独立レビュー。
- `plugins/aidlc-flow-slice/stages/construction/merge-readiness.md`: ローカル、PR、CI、未検証事項、マージ承認を検査する。
- `plugins/aidlc-flow-slice/contributions/**`: core initialization、code-generation、build-and-testをslice scopeへ参加させる。
- `lib/plugin.sh`: バージョン検査、projection検査、ホストplugin導入、選択、syncを担当する。
- `bin/aidlc-flow`: 既存bootstrapへplugin処理を順序どおり組み込む。
- `install.sh`: plugin sourceを配布物へ含め、両harness projectionを生成する。
- `tests/plugin-source-test.sh`: source定義の静的契約。
- `tests/plugin-build-test.sh`: 公式validate/buildと両projectionの契約。
- `tests/version-test.sh`: v2.9.0固定と診断。
- `tests/plugin-install-test.sh`: marketplace、選択、syncの順序と失敗伝播。
- `tests/slice-routing-test.sh`: scopeのstage経路、review重複排除、成果物の契約。
- `tests/install-test.sh`, `tests/bootstrap-test.sh`, `tests/cli-test.sh`: 既存導入・初期化・表示の回帰。
- `README.md`: 導入方法、入口、mainマージ境界、比較測定項目。

## Task 1: Plugin sourceの最小骨格をTDDで追加する

**Files:**
- Create: `tests/plugin-source-test.sh`
- Create: `plugins/aidlc-flow-slice/.aidlc-plugin/plugin.json`
- Create: `plugins/aidlc-flow-slice/scopes/aidlc-flow-slice.md`
- Create: `plugins/aidlc-flow-slice/stages/inception/slice-contract.md`
- Create: `plugins/aidlc-flow-slice/stages/construction/slice-review.md`
- Create: `plugins/aidlc-flow-slice/stages/construction/merge-readiness.md`

- [ ] **Step 1: 存在・所有者・scope方針を固定する失敗テストを書く**

```sh
#!/bin/sh
set -eu
. "$(dirname "$0")/testlib.sh"
root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
plugin="$root/plugins/aidlc-flow-slice"

for file in \
  .aidlc-plugin/plugin.json \
  scopes/aidlc-flow-slice.md \
  stages/inception/slice-contract.md \
  stages/construction/slice-review.md \
  stages/construction/merge-readiness.md
do
  [ -f "$plugin/$file" ] || fail "missing plugin source: $file"
done

assert_contains "$(cat "$plugin/.aidlc-plugin/plugin.json")" '"name": "flow-slice"' "manifest uses stable logical name"
scope=$(cat "$plugin/scopes/aidlc-flow-slice.md")
assert_contains "$scope" 'name: aidlc-flow-slice' "scope has the public runner name"
assert_contains "$scope" 'testStrategy: Standard' "scope requires integration testing"
assert_contains "$scope" 'review_cap: none' "core stage reviewers are disabled"
assert_contains "$scope" 'change_control: relaxed' "small slices avoid reopening unchanged gates"
assert_contains "$scope" 'learnings: off' "slice scope avoids duplicate learning ceremony"
assert_contains "$scope" 'summary_confirmation: off' "slice scope avoids duplicate summary prompts"

review=$(cat "$plugin/stages/construction/slice-review.md")
assert_contains "$review" 'lead_agent: aidlc-architecture-reviewer-agent' "slice review is independent"
case "$review" in
  *'reviewer:'*) fail "slice review must not declare a capped nested reviewer" ;;
esac
printf 'PASS: plugin-source-test\n'
```

- [ ] **Step 2: テストを実行し、source未作成で失敗することを確認する**

Run: `/bin/sh tests/plugin-source-test.sh`

Expected: `FAIL: missing plugin source: .aidlc-plugin/plugin.json`

- [ ] **Step 3: manifestとscopeを作成する**

`plugins/aidlc-flow-slice/.aidlc-plugin/plugin.json`:

```json
{
  "name": "flow-slice",
  "version": "0.1.0",
  "description": "A fast vertical slice from acceptance contract through review and merge readiness.",
  "author": { "name": "aidlc-flow" },
  "dependencies": ["core"],
  "aidlc": {
    "contributes": {
      "stages": "stages/",
      "scopes": "scopes/",
      "contributions": "contributions/"
    }
  }
}
```

`plugins/aidlc-flow-slice/scopes/aidlc-flow-slice.md`:

```markdown
---
name: aidlc-flow-slice
plugin: flow-slice
depth: Minimal
testStrategy: Standard
keywords:
  - vertical slice
  - slice
  - main merge
description: Deliver one testable user-visible slice through review and merge readiness
skeleton: off
runner: true
review_cap: none
change_control: relaxed
sensors: on
learnings: off
summary_confirmation: off
---

# aidlc-flow-slice scope

Use one intent, one branch, and one pull request for a small user-visible slice.
The path is Slice Contract, Code Generation, Build and Test, Slice Review, and
Merge Readiness. Do not create horizontal Units.
```

- [ ] **Step 4: Slice Contract stageを作成する**

`plugins/aidlc-flow-slice/stages/inception/slice-contract.md`:

```markdown
---
slug: slice-contract
name: Slice Contract
plugin: flow-slice
phase: inception
execution: ALWAYS
condition: Define one small user-visible slice before implementation.
lead_agent: aidlc-product-agent
support_agents: []
mode: inline
produces:
  - requirements
  - slice-contract
consumes: []
requires_stage:
  - state-init
sensors:
  - required-sections
scopes:
  - aidlc-flow-slice
summary_confirmation: if-present
required_sections:
  - Acceptance Criteria
  - Boundary Test
  - Merge Safety
inputs: The requested user-visible change and current workspace state
outputs: requirements.md and slice-contract.md under the engine-resolved record directory
---

# Slice Contract

Follow the active stage protocol and keep this contract short.

## Steps

1. State one to three externally observable acceptance criteria under
   `## Acceptance Criteria`.
2. Name the first boundary test that must fail before implementation under
   `## Boundary Test`.
3. List changed external boundaries and required round-trip evidence.
4. Under `## Merge Safety`, decide whether this slice can merge safely in one
   pull request without a feature flag.
5. If it cannot, stop and ask the human to choose slice splitting, a feature
   flag, or bundled delivery. Do not ask when the slice is already safe.
6. Write the same approved contract to `requirements.md` and
   `slice-contract.md` at the directive-resolved output paths.
7. Open one approval gate for the complete contract.
```

- [ ] **Step 5: Slice Review stageを作成する**

`plugins/aidlc-flow-slice/stages/construction/slice-review.md`:

```markdown
---
slug: slice-review
name: Slice Review
plugin: flow-slice
phase: construction
execution: ALWAYS
condition: Review the tested slice once after Build and Test succeeds.
lead_agent: aidlc-architecture-reviewer-agent
support_agents: []
mode: subagent
produces:
  - slice-review
consumes:
  - artifact: slice-contract
    required: true
  - artifact: code-summary
    required: true
  - artifact: build-test-results
    required: true
requires_stage:
  - build-and-test
sensors:
  - required-sections
scopes:
  - aidlc-flow-slice
required_sections:
  - Spec Compliance
  - Findings
  - Verdict
inputs: The approved slice contract, implementation summary, source diff, and passing test evidence
outputs: slice-review.md under the engine-resolved record directory
---

# Slice Review

This is the slice's only independent review. Do not repeat the disabled
Code Generation reviewer.

## Steps

1. Review `## Spec Compliance` first and map every acceptance criterion to
   source and test evidence.
2. Review code quality, error handling, security, and maintainability second.
3. Record every item under `## Findings` as Critical, Important, or Optional.
4. A Critical or Important item blocks approval. Return to implementation,
   rerun affected tests and the repository-wide check, then review only the
   changed and affected diff.
5. Write `## Verdict` as PASS only when no blocking item remains. Otherwise
   write BLOCKED and list the required fixes.
```

- [ ] **Step 6: Merge Readiness stageを作成する**

`plugins/aidlc-flow-slice/stages/construction/merge-readiness.md`:

```markdown
---
slug: merge-readiness
name: Merge Readiness
plugin: flow-slice
phase: construction
execution: ALWAYS
condition: Verify local, pull-request, and human approval evidence before merging to main.
lead_agent: aidlc-delivery-agent
support_agents: []
mode: inline
produces:
  - merge-readiness
consumes:
  - artifact: slice-review
    required: true
  - artifact: build-test-results
    required: true
requires_stage:
  - slice-review
sensors:
  - required-sections
scopes:
  - aidlc-flow-slice
required_sections:
  - Local Readiness
  - Pull Request Readiness
  - Unverified Items
  - Measurements
inputs: Passing tests, the approved review, Git state, pull-request checks, and human approvals
outputs: merge-readiness.md under the engine-resolved record directory
---

# Merge Readiness

Never push, create a pull request, merge, or deploy implicitly.

## Steps

1. Under `## Local Readiness`, record the clean working tree, intended commits,
   latest main integration, repository-wide check command, and fresh result.
2. Ask separately before push and before pull-request creation.
3. Under `## Pull Request Readiness`, record the pull-request URL, green CI,
   resolved Critical and Important findings, and merge-conflict status.
4. Under `## Unverified Items`, list every missing check. An item tied to an
   acceptance criterion blocks merge; any other item requires explicit human
   acceptance.
5. Ask for explicit main-merge approval. Do not deploy.
6. After merge, record the merge commit SHA under `## Pull Request Readiness`.
7. Under `## Measurements`, record elapsed and active time, stage times, human
   interventions, test failures, review returns, available token/cost data,
   changed files and lines, commit count, defect discovery stage, and remaining
   unverified items.
```

- [ ] **Step 7: 静的契約テストを成功させる**

Run: `/bin/sh tests/plugin-source-test.sh`

Expected: `PASS: plugin-source-test`

- [ ] **Step 8: コミットする**

```bash
git add tests/plugin-source-test.sh plugins/aidlc-flow-slice
git commit -m "feat: define vertical slice plugin"
```

## Task 2: Core stageへのscope参加とstage経路をTDDで固定する

**Files:**
- Create: `tests/slice-routing-test.sh`
- Create: `plugins/aidlc-flow-slice/contributions/initialization/workspace-scaffold.md`
- Create: `plugins/aidlc-flow-slice/contributions/initialization/workspace-detection.md`
- Create: `plugins/aidlc-flow-slice/contributions/initialization/state-init.md`
- Create: `plugins/aidlc-flow-slice/contributions/construction/code-generation.md`
- Create: `plugins/aidlc-flow-slice/contributions/construction/build-and-test.md`

- [ ] **Step 1: 必要なcore stageだけを追加する失敗テストを書く**

```sh
#!/bin/sh
set -eu
. "$(dirname "$0")/testlib.sh"
root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
contrib="$root/plugins/aidlc-flow-slice/contributions"

for target in \
  initialization/workspace-scaffold \
  initialization/workspace-detection \
  initialization/state-init \
  construction/code-generation \
  construction/build-and-test
do
  file="$contrib/$target.md"
  [ -f "$file" ] || fail "missing scope contribution: $target"
  assert_contains "$(cat "$file")" 'plugin: flow-slice' "$target has plugin ownership"
  assert_contains "$(cat "$file")" '    - aidlc-flow-slice' "$target joins slice scope"
done

if rg -q 'units-generation|delivery-planning|domain-design|functional-design' "$contrib"; then
  fail "horizontal planning stages must not join the slice scope"
fi
printf 'PASS: slice-routing-test\n'
```

- [ ] **Step 2: テストを実行し、contribution未作成で失敗することを確認する**

Run: `/bin/sh tests/slice-routing-test.sh`

Expected: `FAIL: missing scope contribution: initialization/workspace-scaffold`

- [ ] **Step 3: 5つのscope contributionを作成する**

`contributions/initialization/workspace-scaffold.md`:

```markdown
---
target: workspace-scaffold
plugin: flow-slice
adds:
  scopes:
    - aidlc-flow-slice
---
```

`contributions/initialization/workspace-detection.md`:

```markdown
---
target: workspace-detection
plugin: flow-slice
adds:
  scopes:
    - aidlc-flow-slice
---
```

`contributions/initialization/state-init.md`:

```markdown
---
target: state-init
plugin: flow-slice
adds:
  scopes:
    - aidlc-flow-slice
---
```

`contributions/construction/code-generation.md`:

```markdown
---
target: code-generation
plugin: flow-slice
adds:
  scopes:
    - aidlc-flow-slice
---
```

`contributions/construction/build-and-test.md`:

```markdown
---
target: build-and-test
plugin: flow-slice
adds:
  scopes:
    - aidlc-flow-slice
---
```

本文fragmentは追加しない。

- [ ] **Step 4: stage経路テストを成功させる**

Run: `/bin/sh tests/slice-routing-test.sh`

Expected: `PASS: slice-routing-test`

- [ ] **Step 5: コミットする**

```bash
git add tests/slice-routing-test.sh plugins/aidlc-flow-slice/contributions
git commit -m "feat: route slice scope through core build stages"
```

## Task 3: AI-DLC v2.9.0の公式validatorと両projectionを契約テストにする

**Files:**
- Create: `tests/plugin-build-test.sh`
- Modify: `tests/testlib.sh`

- [ ] **Step 1: command有無を明確にskipではなく失敗させるassertionを追加する**

```sh
assert_command() {
  command_name=$1
  command -v "$command_name" >/dev/null 2>&1 ||
    fail "required command is not installed: $command_name"
}
```

- [ ] **Step 2: 公式validator/buildを実行するテストを書く**

```sh
#!/bin/sh
set -eu
. "$(dirname "$0")/testlib.sh"
root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
plugin="$root/plugins/aidlc-flow-slice"
tmp=$(new_tmpdir)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
assert_command aidlc

aidlc plugin validate "$plugin"
for harness in codex claude; do
  out="$tmp/$harness"
  aidlc plugin build "$harness" "$out" --plugin-root "$plugin"
  [ -f "$out/.aidlc-plugin-projection.json" ] || fail "$harness projection metadata is missing"
  [ -f "$out/scopes/aidlc-flow-slice.md" ] || fail "$harness scope projection is missing"
  [ -f "$out/stages/inception/slice-contract.md" ] || fail "$harness contract stage is missing"
  [ -f "$out/stages/construction/slice-review.md" ] || fail "$harness review stage is missing"
  [ -f "$out/stages/construction/merge-readiness.md" ] || fail "$harness merge stage is missing"
done
printf 'PASS: plugin-build-test\n'
```

- [ ] **Step 3: 両projectionの公式契約テストを実行する**

Run: `/bin/sh tests/plugin-build-test.sh`

Expected: `Plugin validation: VALID`、Codex/Claude build成功、最後に `PASS: plugin-build-test`

- [ ] **Step 4: コミットする**

```bash
git add tests/testlib.sh tests/plugin-build-test.sh plugins/aidlc-flow-slice
git commit -m "test: validate slice plugin projections"
```

## Task 4: v2.9.0固定とprojection配置をinstallerへ追加する

**Files:**
- Create: `tests/version-test.sh`
- Modify: `tests/install-test.sh`
- Modify: `lib/common.sh`
- Modify: `install.sh`

- [ ] **Step 1: 対応バージョンだけを許可する失敗テストを書く**

テスト内に `aidlc --version` を返すfakeを作り、次の3ケースを検証する。

```sh
AIDLC_FAKE_VERSION='aidlc 2.9.0 (runtime 2.9.0)' require_aidlc_version
assert_eq "$?" "0" "2.9.0 is supported"

set +e
unsupported=$(AIDLC_FAKE_VERSION='aidlc 2.10.0 (runtime 2.10.0)' require_aidlc_version 2>&1)
status=$?
set -e
assert_eq "$status" "1" "2.10.0 is rejected until verified"
assert_contains "$unsupported" 'requires aidlc 2.9.0' "version mismatch is actionable"
```

実際のテストではPATH上のfake `aidlc` を使い、関数内にテスト専用分岐を入れない。

- [ ] **Step 2: version testを実行し未定義関数で失敗することを確認する**

Run: `/bin/sh tests/version-test.sh`

Expected: `require_aidlc_version: not found`

- [ ] **Step 3: `require_aidlc_version` を実装する**

```sh
require_aidlc_version() {
  aidlc_flow_version_output=$(aidlc --version 2>&1) ||
    die 1 "unable to read aidlc version"
  case "$aidlc_flow_version_output" in
    'aidlc 2.9.0 (runtime 2.9.0)'*) ;;
    *) die 1 "slice workflow requires aidlc 2.9.0; found: $aidlc_flow_version_output" ;;
  esac
}
```

- [ ] **Step 4: installer testへplugin sourceと両projectionの検査を追加する**

fake `aidlc` は `plugin validate` と `plugin build` を記録し、build先へ `.aidlc-plugin-projection.json`、host manifest、scope、stageを作る。install後に次をassertする。

```sh
[ -f "$tmp/share/aidlc-flow/plugins/aidlc-flow-slice/.aidlc-plugin/plugin.json" ] || fail "plugin source is not installed"
[ -f "$tmp/share/aidlc-flow/plugin-dist/codex/.aidlc-plugin-projection.json" ] || fail "codex projection is not built"
[ -f "$tmp/share/aidlc-flow/plugin-dist/claude/.aidlc-plugin-projection.json" ] || fail "claude projection is not built"
```

- [ ] **Step 5: installerをplugin sourceのcopyと公式buildへ拡張する**

既存のtransactional directory copy対象を次へ変える。

```sh
for directory in bin lib memory plugins; do
  # 既存の .new → mv ロジックをそのまま使う
done
```

copy完了後、`.new` build directoryへCodexとClaudeを生成し、両方成功した場合だけ `plugin-dist` と置き換える。途中失敗時は既存 `plugin-dist` を保持する。

```sh
aidlc plugin validate "$destination/plugins/aidlc-flow-slice"
for harness in codex claude; do
  aidlc plugin build "$harness" "$destination/plugin-dist.new/$harness" \
    --plugin-root "$destination/plugins/aidlc-flow-slice"
done
```

buildが生成する各host manifest directoryの `marketplace.json` は、catalog
`name` だけを `aidlc-plugins` から専用名 `aidlc-flow` へ書き換える。plugin
名、version、sourceは変更しない。これにより他のAI-DLC plugin catalogと
名前が衝突しない。テストでは `name: aidlc-flow` と
`plugins[0].name: aidlc-flow-slice` をassertする。

- [ ] **Step 6: version・installerテストを成功させる**

Run: `/bin/sh tests/version-test.sh && /bin/sh tests/install-test.sh`

Expected: `PASS: version-test` と `PASS: install-test`

- [ ] **Step 7: コミットする**

```bash
git add lib/common.sh install.sh tests/version-test.sh tests/install-test.sh
git commit -m "feat: build supported slice plugin projections"
```

## Task 5: ホストplugin導入と公式syncをTDDで実装する

**Files:**
- Create: `lib/plugin.sh`
- Create: `tests/plugin-install-test.sh`
- Modify: `tests/bootstrap-test.sh`

- [ ] **Step 1: Codex/Claudeでの呼び出し順を記録するfakeテストを書く**

テストは `codex`、`claude`、`aidlc` のfakeをPATHへ置き、`install_slice_plugin PROJECT HARNESS DIST` を呼ぶ。期待ログは次の順に固定する。

```text
codex|plugin marketplace add $projection_root/codex
codex|plugin add aidlc-flow-slice@aidlc-flow
aidlc|config project --project-dir $project --plugins flow-slice --yes
aidlc|engine plugin sync
```

Claudeでは次を期待する。

```text
claude|plugin marketplace add $projection_root/claude --scope project
claude|plugin install aidlc-flow-slice@aidlc-flow --scope project --yes
aidlc|config project --project-dir $project --plugins flow-slice --yes
aidlc|engine plugin sync
```

fakeはmarketplace/pluginが既に存在する2回目の呼び出しも成功させ、同じprojectionからの再実行が成功することを確認する。host CLIのstderrに「already configured」が出る場合だけ許容し、それ以外の非ゼロ終了は伝播させる。

- [ ] **Step 2: テストを実行し、helper未作成で失敗することを確認する**

Run: `/bin/sh tests/plugin-install-test.sh`

Expected: `lib/plugin.sh: No such file or directory`

- [ ] **Step 3: `lib/plugin.sh` を実装する**

公開関数は次の3つに限定する。

```sh
slice_projection_dir() {
  aidlc_flow_projection_root=$1
  aidlc_flow_projection_harness=$2
  printf '%s\n' "$aidlc_flow_projection_root/$aidlc_flow_projection_harness"
}

require_slice_projection() {
  aidlc_flow_projection=$1
  [ -f "$aidlc_flow_projection/.aidlc-plugin-projection.json" ] ||
    die 1 "slice plugin projection is missing; rerun install.sh"
}

install_slice_plugin() {
  aidlc_flow_plugin_project=$1
  aidlc_flow_plugin_harness=$2
  aidlc_flow_plugin_projection=$3
  require_slice_projection "$aidlc_flow_plugin_projection"
  case "$aidlc_flow_plugin_harness" in
    codex)
      codex plugin marketplace add "$aidlc_flow_plugin_projection"
      codex plugin add aidlc-flow-slice@aidlc-flow
      ;;
    claude)
      claude plugin marketplace add "$aidlc_flow_plugin_projection" --scope project
      claude plugin install aidlc-flow-slice@aidlc-flow --scope project --yes
      ;;
    *) die 2 "unsupported harness for slice plugin: $aidlc_flow_plugin_harness" ;;
  esac
  (
    cd "$aidlc_flow_plugin_project"
    aidlc config project --project-dir "$aidlc_flow_plugin_project" --plugins flow-slice --yes
    AIDLC_HARNESS_DIR=".$aidlc_flow_plugin_harness" \
      AIDLC_HARNESS_NAME="$aidlc_flow_plugin_harness" \
      aidlc engine plugin sync
  )
}
```

上のadd/installは、先にhost CLIのJSONを読むprivate helperで囲む。Codexは
`codex plugin marketplace list --json` の `marketplaces[].name/root` と
`codex plugin list --json` の `installed[].pluginId`、Claudeは
`claude plugin marketplace list --json` の各要素の `name/path` と
`claude plugin list --json` の `id/scope/projectPath` をPython標準JSONで読む。
`aidlc-flow` が同じprojection pathを指していればmarketplace addを省略し、
`aidlc-flow-slice@aidlc-flow` が対象scopeにあればplugin installを省略する。
同名marketplaceが異なるpathを指す場合は変更せず
`aidlc-flow: marketplace aidlc-flow points to a different source` で停止する。

- [ ] **Step 4: bootstrap fakeへplugin commandを追加する**

既存fake `aidlc` に `--version`、`config project`、`engine plugin sync` を追加し、fake `codex` と `claude` を用意する。既存のcore config → plugin install/select/sync → Memory merge → doctorという順序をassertする。

- [ ] **Step 5: plugin installとbootstrap回帰を成功させる**

Run: `/bin/sh tests/plugin-install-test.sh && /bin/sh tests/bootstrap-test.sh`

Expected: 両方PASS。host plugin、selection、syncのいずれかが失敗するケースではdoctorと成功表示へ進まない。

- [ ] **Step 6: コミットする**

```bash
git add lib/plugin.sh tests/plugin-install-test.sh tests/bootstrap-test.sh
git commit -m "feat: install and compose slice plugin"
```

## Task 6: `aidlc-flow init` に安全な順序で統合する

**Files:**
- Modify: `bin/aidlc-flow`
- Modify: `lib/common.sh`
- Modify: `lib/codex.sh`
- Modify: `lib/claude.sh`
- Modify: `tests/active-space-test.sh`
- Modify: `tests/workflow-preflight-test.sh`
- Modify: `tests/bootstrap-test.sh`

- [ ] **Step 1: active workflowと管理対象plugin手編集の失敗テストを書く**

次を追加する。

- active intentがある場合、version確認後かつhost CLI呼び出し前に終了する。
- plugin ownership/drop記録が変更・degradedを示す場合、host plugin更新前に終了する。
- unrelated dirty fileは警告だけで続行する。
- managed Memoryの手編集は従来どおり拒否する。

drop検査対象は両harness共通で、active space配下の `.aidlc-engine/hooks-health/plugin-compose-flow-slice.drops` とする。`[degraded]` が1件でもあれば停止し、`[advisory]` だけなら警告して続行する。

- [ ] **Step 2: 新しいテストが現行順序で失敗することを確認する**

Run: `/bin/sh tests/bootstrap-test.sh && /bin/sh tests/workflow-preflight-test.sh`

Expected: plugin呼び出しまたはdrop診断の不足でFAIL

- [ ] **Step 3: init処理を次の順序へ変更する**

```sh
require_aidlc
require_aidlc_version
require_git_repo "$project_dir"
refuse_base_path_symlinks "$project_dir"
space=$(active_space "$project_dir")
refuse_managed_path_symlinks "$project_dir" "$space"
refuse_active_workflow "$project_dir"
refuse_dirty_managed_memory "$project_dir" "$space" "$root/memory/team.md" "$root/memory/phases/construction.md"
refuse_degraded_plugin_state "$project_dir" "$space"

. "$root/lib/$harness.sh"
. "$root/lib/plugin.sh"
configure_harness "$project_dir"
install_slice_plugin "$project_dir" "$harness" "$root/plugin-dist/$harness"
# symlink再検査、Memory merge、doctor、完了表示は既存順序を維持
```

- [ ] **Step 4: 開始ヒントをslice runnerへ変更する**

Codex:

```text
Start Codex in this repository, approve the hook trust prompt, then invoke $aidlc-flow-slice <your slice>.
```

Claude:

```text
Start Claude Code in this repository, approve project hooks, then invoke /aidlc-flow-slice <your slice>.
```

- [ ] **Step 5: preflightとbootstrapを成功させる**

Run: `/bin/sh tests/workflow-preflight-test.sh && /bin/sh tests/bootstrap-test.sh`

Expected: 両方PASS。2回目のinitは管理対象ファイルを変えず成功する。

- [ ] **Step 6: コミットする**

```bash
git add bin/aidlc-flow lib/common.sh lib/codex.sh lib/claude.sh tests/active-space-test.sh tests/workflow-preflight-test.sh tests/bootstrap-test.sh
git commit -m "feat: initialize repositories with slice workflow"
```

## Task 7: 実projectionで経路とdoctorを統合検証する

**Files:**
- Modify: `tests/plugin-build-test.sh`
- Create: `tests/plugin-integration-test.sh`

- [ ] **Step 1: disposable projectでの統合失敗テストを書く**

テストは一時Gitリポジトリを作り、実 `aidlc 2.9.0` でCodexとClaudeを別々に初期化する。生成済みprojectionをローカルmarketplaceとして導入し、次を検証する。

```sh
aidlc engine graph validate-scope aidlc-flow-slice
aidlc engine gen scope-table
aidlc doctor --project-dir "$project" --quiet
```

scope tableから次の順序をassertする。

```text
workspace-scaffold
workspace-detection
state-init
slice-contract
code-generation
build-and-test
slice-review
merge-readiness
```

また `units-generation`、`delivery-planning`、`domain-design` がslice scopeでSKIP、code-generationのeffective reviewが`none`、slice-reviewがEXECUTEであることをassertする。

- [ ] **Step 2: 隔離したhost設定で統合テストを実行する**

テスト実行中は `CODEX_HOME="$tmp/codex-home"` と
`CLAUDE_CONFIG_DIR="$tmp/claude-home"` を設定し、利用者の実host plugin設定を
読み書きしない。marketplace sourceはローカルprojectionだけを使い、ネットワーク
アクセスを行わない。

Run: `/bin/sh tests/plugin-integration-test.sh`

Expected: Codex/Claude双方でscope validationとdoctorが成功し、
`PASS: plugin-integration-test`

- [ ] **Step 3: plugin build契約も続けて成功させる**

Run: `/bin/sh tests/plugin-build-test.sh && /bin/sh tests/plugin-integration-test.sh`

Expected: Codex/Claude双方でscope validationとdoctorが成功し、`PASS: plugin-integration-test`

- [ ] **Step 4: コミットする**

```bash
git add plugins/aidlc-flow-slice lib/plugin.sh tests/plugin-build-test.sh tests/plugin-integration-test.sh
git commit -m "test: verify slice workflow integration"
```

## Task 8: 利用方法と測定方法を文書化し、全検査を通す

**Files:**
- Modify: `README.md`
- Modify: `tests/cli-test.sh`

- [ ] **Step 1: READMEの必須情報を検査する失敗テストを書く**

```sh
readme=$(cat "$repo_root/README.md")
assert_contains "$readme" '$aidlc-flow-slice <slice>' "Codex slice entry is documented"
assert_contains "$readme" '/aidlc-flow-slice <slice>' "Claude slice entry is documented"
assert_contains "$readme" 'AI-DLC v2.9.0' "supported version is documented"
assert_contains "$readme" '1 intent、1ブランチ、1 PR' "slice boundary is documented"
assert_contains "$readme" 'push、PR作成、mainへのマージ' "external approvals are documented"
assert_contains "$readme" '経過時間' "comparison measurement is documented"
```

- [ ] **Step 2: testを実行し、README未更新で失敗することを確認する**

Run: `/bin/sh tests/cli-test.sh`

Expected: `FAIL: Codex slice entry is documented`

- [ ] **Step 3: READMEを更新する**

次の内容を短く記載する。

- prerequisiteをAI-DLC v2.9.0へ固定。
- `install.sh` がslice pluginのCodex/Claude projectionも生成する。
- `aidlc-flow init --harness ...` 後の入口。
- 1 intent、1ブランチ、1 PRであること。
- feature flagは既定で要求せず、安全にmainへ入らない場合だけ確認すること。
- push、PR作成、mainへのマージは個別承認、deployは対象外であること。
- 経過時間、実作業時間、承認回数、差し戻し、token/cost、変更量、不具合発見段階、未検証事項を記録すること。
- AI-DLCなしのcodex-phase比較でも同じ測定項目を使うこと。

- [ ] **Step 4: 全検査を実行する**

Run: `make check`

Expected: 既存テストと追加テストがすべて `PASS`、shell syntax check成功

- [ ] **Step 5: working treeと差分を検査する**

Run: `git diff --check && git status --short`

Expected: whitespace errorなし。Task 8のREADMEとtestだけが未コミット。

- [ ] **Step 6: コミットする**

```bash
git add README.md tests/cli-test.sh
git commit -m "docs: explain vertical slice workflow"
```

- [ ] **Step 7: コミット後の最終証拠を取得する**

Run: `make check && git status --short --branch && git log -8 --oneline`

Expected: 全検査PASS、作業ツリーclean、Task 1〜8の1意図ごとのコミットが表示される。push、PR作成、mainへのマージ、deployは実行しない。
