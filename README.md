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
