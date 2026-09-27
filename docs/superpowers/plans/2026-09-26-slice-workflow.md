# Vertical Slice Workflow Local-First Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** このPCのCodexとClaude Codeから、公式AI-DLC v2.9.0の状態管理を使う縦切りワークフローを `$flow-slice` / `/flow-slice` で開始できるようにする。

**Architecture:** 公式仕様に適合する `plugins/flow/` をsource of truthとし、scope `flow-slice` と3つのplugin stageをAI-DLCのstage graphへ合成する。`aidlc-flow` は公式source validator/buildでCodex・Claude projectionを生成し、各hostへローカル導入してから、公式plugin sync・scope validation・doctorで確認する。配布の一般化は対象外だが、sourceとprojectionは後から配布できる構造を保つ。

**Tech Stack:** POSIX shell、AI-DLC CLI v2.9.0 plugin API、Bun、Codex/Claude local plugin marketplace、Markdown stage/scope definitions

---

## 完了条件

- `plugins/flow/` がAI-DLC v2.9.0の公式source validatorを通る。
- CodexとClaudeの公式projectionが生成される。
- 隔離した一時プロジェクトで `flow-slice` scopeが次の順に解決される。
  `workspace-scaffold → workspace-detection → state-init → flow-slice-contract → code-generation → build-and-test → flow-slice-review → flow-merge-readiness`
- このPCの実プロジェクトへ `aidlc-flow init` で導入できる。
- Codexでは `$flow-slice`、Claudeでは `/flow-slice` がAI-DLC engineへ接続する。
- 実intentを作成し、scopeと最初のstageがAI-DLCの状態ファイルへ記録される。
- `make check` が成功し、変更は1意図ごとにコミットされる。
- push、PR、main merge、deployは行わない。

## Task 3: Plugin sourceを公式v2.9.0契約へ修正する

**Files:**
- Rename: `plugins/aidlc-flow-slice/` → `plugins/flow/`
- Modify: `plugins/flow/.aidlc-plugin/plugin.json`
- Modify: `plugins/flow/scopes/flow-slice.md`
- Modify: `plugins/flow/stages/inception/flow-slice-contract.md`
- Modify: `plugins/flow/stages/construction/flow-slice-review.md`
- Modify: `plugins/flow/stages/construction/flow-merge-readiness.md`
- Modify: `plugins/flow/contributions/**/*.md`
- Modify: `tests/plugin-source-test.sh`
- Modify: `tests/slice-routing-test.sh`

- [ ] **Step 1: 公式命名とschemaを要求する失敗テストを書く**

テストは次を要求する。

```sh
plugin="$root/plugins/flow"
assert_contains "$(cat "$plugin/.aidlc-plugin/plugin.json")" '"name": "flow"' "manifest name matches root"
assert_contains "$(cat "$plugin/.aidlc-plugin/plugin.json")" '"overlays": "contributions/"' "manifest uses official overlay key"
assert_contains "$(cat "$plugin/scopes/flow-slice.md")" 'name: flow-slice' "scope uses plugin prefix"
assert_contains "$(cat "$plugin/stages/inception/flow-slice-contract.md")" 'slug: flow-slice-contract' "contract stage uses plugin prefix"
```

- [ ] **Step 2: `/bin/sh tests/plugin-source-test.sh && /bin/sh tests/slice-routing-test.sh` を実行し、旧source名で失敗することを確認する**

- [ ] **Step 3: sourceを最小修正する**

manifestは次の公式キーだけを使う。

```json
{
  "name": "flow",
  "version": "0.1.0",
  "description": "Deliver one vertical slice through test, review, and merge readiness.",
  "author": { "name": "aidlc-flow" },
  "dependencies": ["core"],
  "aidlc": {
    "contributes": {
      "stages": "stages/",
      "scopes": "scopes/",
      "overlays": "contributions/"
    }
  }
}
```

plugin所有のscope、stage slug、produces artifactはすべて `flow-` prefixを付ける。core stageへのcontributionは `adds.scopes: [flow-slice]` を使う。

- [ ] **Step 4: 個別テストと `make check` を成功させる**

- [ ] **Step 5: `git commit -m "fix: align slice plugin with aidlc contract"` でコミットする**

## Task 4: 公式source validatorとprojection buildを動かす

**Files:**
- Create: `lib/aidlc-plugin-tools.sh`
- Create: `tests/plugin-build-test.sh`
- Modify: `tests/testlib.sh`
- Modify: `install.sh`
- Modify: `tests/install-test.sh`

- [ ] **Step 1: Bunと公式tool pathを要求する失敗テストを書く**

```sh
require_plugin_toolchain
validate_flow_plugin "$root/plugins/flow"
build_flow_projection codex "$tmp/codex" "$root/plugins/flow"
build_flow_projection claude "$tmp/claude" "$root/plugins/flow"
```

`AIDLC_FLOW_BUN` と `AIDLC_FLOW_AIDLC_HOME` をテスト用に上書き可能にし、本番ではPATH上の`bun`と、active version markerから求めたAI-DLC runtimeを使う。

- [ ] **Step 2: `/bin/sh tests/plugin-build-test.sh` を実行し、helper未実装で失敗することを確認する**

- [ ] **Step 3: 公式TypeScript toolを呼ぶhelperを実装する**

```sh
"$aidlc_flow_bun" "$aidlc_flow_tools/aidlc-plugin-validate.ts" "$plugin_root"
"$aidlc_flow_bun" "$aidlc_flow_tools/aidlc-plugin-build.ts" \
  "$harness" "$output_dir" --plugin-root "$plugin_root"
```

コンパイル済み `aidlc plugin validate/build` はv2.9.0でbundled data pathを誤解決するため使用しない。迂回ではなく、同梱されている公式source toolを公式ガイドどおりBunで実行する。

- [ ] **Step 4: `install.sh` がsourceを配置し、両projectionをtransactionalに生成するよう拡張する**

- [ ] **Step 5: plugin build、installer、全体検査を成功させる**

Run: `/bin/sh tests/plugin-build-test.sh && /bin/sh tests/install-test.sh && make check`

- [ ] **Step 6: `git commit -m "feat: build local slice projections"` でコミットする**

## Task 5: `aidlc-flow init` で両hostへローカル導入する

**Files:**
- Create: `lib/plugin.sh`
- Create: `tests/plugin-install-test.sh`
- Modify: `bin/aidlc-flow`
- Modify: `lib/codex.sh`
- Modify: `lib/claude.sh`
- Modify: `tests/bootstrap-test.sh`
- Modify: `tests/workflow-preflight-test.sh`

- [ ] **Step 1: host導入順序の失敗テストを書く**

Codexはlocal marketplace登録、`flow@aidlc-flow` 有効化、AI-DLC plugin select/syncの順、Claudeも対応するproject-local marketplace/install、select/syncの順を要求する。2回目は同じsourceなら無変更で成功し、異なるsourceの同名marketplaceは上書きせず停止する。

- [ ] **Step 2: `/bin/sh tests/plugin-install-test.sh && /bin/sh tests/bootstrap-test.sh` を実行し、helper未実装で失敗することを確認する**

- [ ] **Step 3: `install_flow_plugin PROJECT HARNESS PROJECTION` を実装する**

host CLIのJSON inventoryを読み、既存設定を壊さずlocal projectionを登録する。その後、プロジェクト内で次を実行する。

```sh
aidlc config project --project-dir "$project" --plugins flow --yes
AIDLC_HARNESS_DIR=".$harness" AIDLC_HARNESS_NAME="$harness" \
  aidlc engine plugin sync
```

- [ ] **Step 4: `aidlc-flow init` を core config → plugin導入/sync → Memory merge → doctor の順へ統合する**

- [ ] **Step 5: 開始表示を `$flow-slice <your slice>` / `/flow-slice <your slice>` へ変更する**

- [ ] **Step 6: 個別テストと `make check` を成功させる**

- [ ] **Step 7: `git commit -m "feat: initialize local slice workflow"` でコミットする**

## Task 6: 実AI-DLCでscopeとintentを検証する

**Files:**
- Create: `tests/plugin-integration-test.sh`
- Modify: `README.md`
- Modify: `tests/cli-test.sh`

- [ ] **Step 1: 隔離したCodex/Claude設定で実projectionを導入する統合テストを書く**

テストは一時Gitリポジトリと一時host homeを使い、利用者の既存設定を書き換えない。両harnessで次を検証する。

```sh
aidlc engine graph validate-scope flow-slice
aidlc engine gen scope-table
aidlc doctor --project-dir "$project" --quiet
aidlc engine orchestrate next --scope flow-slice -- "local slice smoke test"
```

最後の出力がintent作成directiveであること、作成後の状態にscope `flow-slice` と最初のstageが記録されることを確認する。テスト中にpush、PR、merge、deployは行わない。

- [ ] **Step 2: 統合テストを実行し、未導入状態で失敗することを確認する**

- [ ] **Step 3: 必要最小限の導入修正を行い、Codex/Claude双方で統合テストを成功させる**

- [ ] **Step 4: READMEへローカル導入、起動名、AI-DLC stateの確認方法、現在はローカル利用を完了点とすることを記載する**

- [ ] **Step 5: このPCの実インストールへ `install.sh` と `aidlc-flow init` を適用し、`flow-slice` runnerの存在とdoctorを確認する**

- [ ] **Step 6: `make check`、`git diff --check`、`git status --short` を確認する**

- [ ] **Step 7: `git commit -m "test: verify local aidlc slice workflow"` でコミットする**

- [ ] **Step 8: コミット後に `make check && git status --short --branch` を再実行する**

## 実装中の報告ルール

- 「プロジェクト内テストが通った」と「このPCのAI-DLCで起動した」を分けて報告する。
- 失敗時は、ユーザーが実行できる機能への影響を先に説明し、内部名称だけを単独で報告しない。
- ローカル起動が確認できるまで「使える」「完成」と表現しない。
- 外部配布は今回の完了条件に含めない。
