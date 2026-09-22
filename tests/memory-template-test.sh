#!/bin/sh
set -eu
. "$(dirname "$0")/testlib.sh"
root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)

team=$(cat "$root/memory/team.md")
construction=$(cat "$root/memory/phases/construction.md")

assert_contains "$team" "プロジェクトの AGENTS.md または CLAUDE.md に、より厳しい指示がある場合はそちらを優先する。" "team memory prioritizes stricter project instructions"
assert_contains "$team" "エージェントの完了報告だけを証拠にせず、親が Git 差分、commit SHA、検査出力を確認する。" "team memory requires parent evidence"
assert_contains "$team" "push、PR作成、deploy は、その操作に対する人間の明示的指示がある場合だけ行う。" "team memory protects external actions"
assert_contains "$team" "\`--no-verify\`、検査の skip 化、閾値引き下げ、失敗無視で検査を迂回しない。" "team memory forbids verification bypass"
assert_contains "$construction" "実装前にテストを実行し、期待した理由で失敗する RED を確認する。" "construction memory requires red verification"
assert_contains "$construction" "仕様適合レビューが合格してからコード品質レビューを行う。" "construction memory orders spec review"
assert_contains "$construction" "Critical と Important は修正し、同じ観点で再レビューする。" "construction memory requires review follow-up"
assert_contains "$construction" "完了主張とコミット直前に fresh verification として承認済み検証コマンドを新規実行する。" "construction memory requires fresh verification"
printf 'PASS: memory-template-test\n'
