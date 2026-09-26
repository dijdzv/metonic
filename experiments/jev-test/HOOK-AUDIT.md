# フックの検証範囲の静的監査

2026-09-26。テストは実行していない。
実験worktreeは5dd06de、メイン作業フォルダのHEADは1048b87。
両方のverification.json、scripts/pre-commit.mbtx、hookファイルの一致を確認。
メインのmise.tomlにはcheckbox関連の追加があるため、実験側の一覧を最新全件と扱わない。
Gitのcore.hooksPathは.githooksに設定済み。

## 呼び出し経路

pre-commit → verify:commit-recorded → tools/hook_output →
record-commit-verification.mbtx → verification_impact_cli → pre-commit.mbtx --commit。

pre-push → verify:push-recorded → tools/hook_output → verify-push-recorded.mbtx →
verification_impact_cli。適合するcommit検証記録があれば--push BASEで残りを実行し、
使える記録がなければ引数なしの全検証へ進む。記録再利用は統合検証を無条件に
消す仕組みではない（tools/verification_impact_cli/dispatch.mbt）。

## 既に接続されている種類

- commit: 整形・静的検査、重要/変更関連のrootテスト、別workspaceの非同期テスト、
  型契約・条件付きreactive negative、文書検証など。
- push: 残りのrootテスト、23統合ゲート、最後のfixture/production除外検証2件。
- browser:headless: Nodeブラウザ診断、pixel verifierの単体検証、supervisor経由の
  実ブラウザ検証。browser:async、async-pair:browser-headlessも対象。
- native:headless-integration: headless/control/MCP/session/semantics/client/CLI。
- native:window-integration: window control/attach/RPC/MCP。
- その他: 配布物の開発機能除外、host/surface/binding、RPC、bootstrap復旧検証など。

「フックは単体テストしか実行しない」は該当しない。
一方、すべての既存検証が接続済みという保証もない。

## 少なくとも確認できた非接続候補

| 定義された検証 | 追跡結果 | 次の扱い |
|---|---|---|
| async-pair:diagnostics-browser | full_gate_tasksや他タスクから呼ばれず、supervisor diagnosticsを起動する唯一のmise定義 | pushへ追加する候補 |
| async-pair:diagnostics-test | verify-async-diagnostics.mbtxを起動する定義はあるがフック経路にない | pushへ追加する候補 |
| native:window-display | verify-window-display/verify-window-display-cliの呼出しはこの独立タスク内のみ | 表示環境を要するため常設/別枠を区別して検討 |

上記はメイン側のスクリプト・タスク参照も検索した。静的追跡による候補であり、
全検証の到達性を証明した網羅的解析ではない。今回はフックを変更しない。

逆にtext:verifyは一覧に名前がなくても、native:bindingからverify-wgpu-binding.mbtxを
通じてverify-text-layout.mbtxが呼ばれる。単純なタスク名差分で未接続とは判定しない。
browser buildからの同検証はフォント資産がない場合だけの条件付き呼出し。

## Jev収集との関係

1. フックへの接続有無を整理する。
2. 対象フックの実行条件と内部テスト一覧を収集する。
3. その一覧を全件送って情報形式を比較する。

25ゲート名を渡しただけでは内部の全テスト名を渡したことにならない。
現時点の1,110項目は古いworktreeの部分的な一覧。最新メインのcheckbox追加を
含め、対象revisionと一覧の一致も必要。全件収集の完了とは報告しない。

## 接続整理の結果

このworktreeのverification.jsonへasync-pair:diagnostics-browserと
async-pair:diagnostics-testを追加した。full_gate_tasksは27件、push側はverifyと
verify-nativeを除く25件になる。既存タスクの依存定義をそのまま使用する。
実行はしておらず、実行成功や所要時間は未確認。mainへの統合も未実施。

native:window-displayはdocs/verification/native-control.mdで明示的にopt-inと
定義されていた。未接続の不具合として扱わず、通常フックには追加しない。
フック対象のJev比較からは除外し、任意検証まで含める比較範囲でのみ列挙する。
