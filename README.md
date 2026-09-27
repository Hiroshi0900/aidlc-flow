# aidlc-flow

公式AI-DLCをCodex CLIまたはClaude Codeへ設定し、1つのユーザー可視sliceをローカルで検証可能な状態まで進める`flow-slice` scopeと、共通のTDD・レビュー・検証ルールをMemoryとして追加するbootstrapです。現在はlocal-firstであり、push以降の操作やdeployは対象外です。

## Prerequisites

- macOS
- Git
- 公式AI-DLC 2.9.0（`aidlc --version`）
- Bun（plugin projectionの検証・buildに使用）
- Codex CLIまたはClaude Codeのplugin対応版

公式AI-DLCは[awslabs/aidlc-workflows](https://github.com/awslabs/aidlc-workflows)のリリース手順で先にインストールしてください。

## Install

```bash
./install.sh
export PATH="$HOME/.local/bin:$PATH"
```

インストール先は`AIDLC_FLOW_DATA_HOME`と`AIDLC_FLOW_BIN_HOME`で変更できます。どちらも絶対パスを指定してください。

## Configure a repository

```bash
aidlc-flow init --harness codex --project-dir /path/to/repository
aidlc-flow init --harness claude --project-dir /path/to/repository
```

Codexではhook trustを承認してから`$flow-slice <slice description>`、Claude Codeではproject hooksを承認してから`/flow-slice <slice description>`を実行します。これは独自の進捗管理ではなく、公式AI-DLC engineのintent、state、audit、stage graphを使うrunnerです。`aidlc engine status`と`aidlc engine intent list --json`で同じ公式stateを確認できます。

Claude Code向け初期化は、公式AI-DLCが生成するAmazon Bedrock用の環境変数を除去し、既存のClaudeサブスクリプションまたはログイン済みfirst-party認証を維持します。

## Artifact handoff and lifecycle verification

`flow-slice-contract`は承認済みのAcceptance Criteria、Boundary Test、Merge
Safetyを`flow-requirements.md`と`flow-slice-contract.md`へ同内容で保存します。
合成後のcore Code Generationは`flow-requirements`と`flow-slice-contract`をrequired inputとして受け取り、両方を他の設計入力より優先します。計画はAcceptance
Criteriaを実装とテストへ対応付け、Boundary Testを最初のTDD Redとし、Merge
Safetyのfeature-flag判断に拘束されます。

このscopeは横断的なUnitを作らないzero-Unit workflowです。core
`requirements`と`unit-of-work`はexpected fallbackであり、directiveの
`consumes_absent`へ`expected: true`として現れます。公式plugin APIにはcore
consumeのremove/replaceがないため、この2件だけはgraph validationの既知の
off-path advisoryとして厳密に検証します。plugin契約の2 artifactは実在pathとして
`consumes`へ入り、fallbackにはなりません。

隔離integration testはCodexとClaudeの両方で、公式validator/build/composeと
engineを使います。契約artifactを作成し、公式reportとUserPromptSubmit hookを
通じて承認した後、`code-generation → build-and-test → flow-slice-review → flow-merge-readiness`
の順に遷移させます。各stageのrequired outputs、workspace source、support-agent
contribution、human-presence gateを無効化せず満たし、最終的にMerge Readinessが
activeであることをstate、audit、statusから直接検証します。これは隔離fixtureによる
engine contractの検証であり、実プロジェクトのLLM実装、push、PR作成、merge、deployを
実行するものではありません。

## Safety

- 既存の未コミット変更は削除、stash、commitしません。
- AI-DLC workflowが進行中の場合は設定更新を拒否します。
- 共通Memoryは`aidlc-flow`マーカー内だけを更新します。
- 作業単位は`1 intent / 1 branch / 1 PR`です。横断的なUnit分割は行いません。
- sliceが1 PRで安全にmergeできなければ、分割、feature flag、同時deliveryのどれにするかを人が判断します。
- ローカル実装後も、push、PR作成、mainへのmergeはそれぞれ別の明示承認が必要です。
- deployはworkflowの対象外で、自動化しません。

## Plugin version policy

host plugin cacheはversionをimmutableなcontent identityとして扱います。同じversionの内容を変更して再配布してはいけません。`plugins/flow/.aidlc-plugin/plugin.json`のversionを上げ、`./install.sh`でprojectionを再build・再installしてください。

## Measurement

Issue 79との比較では、elapsed time、active/stage time、human interventions、test failures、review returns、利用可能なtoken/cost、changed files and lines、commit count、defect discovery stage、未検証項目を記録します。`flow-merge-readiness`のMeasurementsが記録場所です。

## Verify

```bash
make check
aidlc doctor --project-dir /path/to/repository
```

## Update

このリポジトリを更新後、`./install.sh`を再実行し、workflowが動作していない対象リポジトリで、対象に応じて`aidlc-flow init --harness codex`または`aidlc-flow init --harness claude`を再実行します。
