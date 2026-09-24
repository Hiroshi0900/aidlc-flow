# aidlc-flow

公式AI-DLCをCodex CLIまたはClaude Codeへ設定し、共通のTDD・レビュー・検証ルールをMemoryとして追加する最小bootstrapです。

## Prerequisites

- macOS
- Git
- 公式`aidlc` CLI

公式AI-DLCは[awslabs/aidlc-workflows](https://github.com/awslabs/aidlc-workflows)のリリース手順で先にインストールしてください。

## Install

```bash
./install.sh
export PATH="$HOME/.local/bin:$PATH"
```

インストール先は`AIDLC_FLOW_DATA_HOME`と`AIDLC_FLOW_BIN_HOME`で変更できます。どちらも絶対パスを指定してください。

## Configure a repository

```bash
cd /path/to/repository
aidlc-flow init --harness codex
# or
aidlc-flow init --harness claude
```

Codexではhook trustを承認してから`$aidlc <idea>`、Claude Codeではproject hooksを承認してから`/aidlc <idea>`を実行します。

Claude Code向け初期化は、公式AI-DLCが生成するAmazon Bedrock用の環境変数を除去し、既存のClaudeサブスクリプションまたはログイン済みfirst-party認証を維持します。

## Safety

- 既存の未コミット変更は削除、stash、commitしません。
- AI-DLC workflowが進行中の場合は設定更新を拒否します。
- 共通Memoryは`aidlc-flow`マーカー内だけを更新します。
- push、PR作成、deployは自動化しません。

## Verify

```bash
make check
aidlc doctor --project-dir /path/to/repository
```

## Update

このリポジトリを更新後、`./install.sh`を再実行し、workflowが動作していない対象リポジトリで、対象に応じて`aidlc-flow init --harness codex`または`aidlc-flow init --harness claude`を再実行します。
