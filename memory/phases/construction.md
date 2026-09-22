## Test-Driven Development

- ソース変更を行う Unit はテストファーストで実装する。
- 実装前にテストを実行し、期待した理由で失敗する RED を確認する。
- RED を確認してから、テストを通す最小実装を行う。

## Review Order

- 実装後は最初に仕様適合レビューを行い、欠落と過剰実装を確認する。
- 仕様適合レビューが合格してからコード品質レビューを行う。
- Critical と Important は修正し、同じ観点で再レビューする。

## Completion Evidence

- 完了主張とコミット直前に fresh verification として承認済み検証コマンドを新規実行する。
- コミット後、親が記録された commit SHA の存在、対象差分、検査結果を確認する。
