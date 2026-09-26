# Jev test selection experiment

Metonicの変更Diffとフック対象全カタログをJevへ送り、実行が必要な項目を選ぶ試作。
今回の評価は判定と計画生成まで。テスト本体を実行せず、フックへの自動省略も導入しない。

## 現在の資料

確定した方式は`compact-four`で評価し、`plan-four-guarded`で計画する方式。
省略条件はscore < 2、confidence >= 0.6、P0+P1 >= 0.6。
既存の3段階コマンドは比較と互換性のために残す。

- [最終的な分類比較](LEVELS-COMPARISON.md)：5・6段階まで比較し、条件付き4段階を選定。

- [評価条件](EVALUATION-PROTOCOL.md)：固定入力・閾値・完了条件。
- [固定設定の結果](FROZEN-EVALUATION.md)：反復、未使用Diff、費用、限界。
- [全件棚卸し](FULL-INVENTORY.md)：対象1,880項目とフック範囲。
- [シンボル入力](SYMBOL-INPUT.md)：ASTから抽出する情報と制約。
- [4段階の比較](FOUR-LEVEL-PILOT.md)：参考条件での見逃しと、追加条件による改善。
- evaluation-cases.json：調整用10件、未使用評価用10件のDiffと期待ID。

カタログはMoonBit、Node、統合・E2Eのコマンド、契約、準備確認を含む。
親子が共存するため、1,880個の独立テストという意味ではない。
consumer単体73件は現在のフック外。対象スナップショットはFULL-INVENTORY.mdを参照。

## 判定の流れ

1. runner一覧・AST・フック呼出しから対象を収集する。
2. 共通stateへDiffを入れ、全項目の質問を送る。事前に候補を減らさない。
3. APIの入力上限エラー時だけ質問群を二分する。独自の固定質問数・文字数上限は設けない。
4. score、confidence、P(0)+P(1)と応答の妥当性から省略候補を決める。
5. 欠落・不正応答、古い応答、必須対象、変更された検証ファイル自身は実行側に残す。

`symbols`は名前・所在・種別・構文的参照名。型解決や推移的な依存グラフではない。
`compact-symbols`は重複IDとnull項目だけを省き、根拠情報を維持する。
本文とソース全文は送らない。names/body/source/moonbitは以前の比較用として残る。

確定した4段階は0=無関係、1=関係するが結果不変、2=影響の可能性、3=失敗が見込まれる。
以下は旧3段階の比較用コマンドで、確定方式では使わない。
`plan-exploratory`はscore <= 0.5、confidence >= 0.6、P(0) >= 0.6で省略候補。
`plan`は以前の保守的な0.1/0.98を維持する。これらの数値は実際の正解率ではない。

## 評価コマンド

固定MoonBitを使い、以下を`moon -C experiments/jev-test run main --target wasm --`の後へ指定する。
入出力には絶対パスを使う。

```text
requests DOSSIER compact-four OUT
evaluate DOSSIER compact-four OUT
plan-four-guarded DOSSIER RESPONSE OUT
evaluation-report CASES DIRECTORY OUT
```

requestsは送信JSONの生成のみ。evaluateだけがAPIを呼ぶ。
キーはworktreeルートの.envのTYPESAFE_API_KEY。内容を表示・コミットしない。
通信先はhttps://api.typesafe.ai/v1/systemone。TYPESAFE_MODELの既定はjev-latest。
15秒のリクエスト制限があり、通信・解析失敗時は対象を残す。
APIキー、認証ヘッダー、エラー本文は実験結果へ保存しない。

単一MoonBitモジュール向けのcollect/enrich/filter/runもあるが、filterはテスト実行まで行う。
今回の評価では使わない。複合カタログの実行機能は未接続で、runはそれを拒否する。
全件カタログの収集は現Metonicのフック構成に依存し、汎用的な自動検出を保証しない。

## 導入範囲と再現条件

これは固定スナップショットに対する評価器の統合であり、現mainの全テストを
自動収集して省略する完成済みフックではない。全件評価の収集器は保存済みoutline・
AST・ゲート定義を入力にするため、新しいrevisionでは再収集・網羅性照合が必要。
API呼出し前にカタログのrevisionと全IDを確認する。古い1,880行を現mainの一覧とみなさない。

評価・選択・レポート処理はMoonBit。`.cjs`は既存の`@ast-grep/napi`と
動的MoonBit parserを呼び出す構文抽出・カタログ境界であり、選別方針やAPI通信を持たない。
AST入力の再生成には`@ast-grep/napi` 0.45.3を`.work/jev-ast`へ準備し、
`mise run static:verify`が準備するパッチ適用済みparser DLLを
`.work/jev-ast/tree-sitter-moonbit.dll`へ配置する。
各収集器の保存済み入力名はソースと[FULL-INVENTORY.md](FULL-INVENTORY.md)を参照。
クリーン環境から全カタログを作る単一コマンドは未整備。
初期の故障注入用PowerShellハーネスは統合対象外とし、結果記録だけを残した。

評価器自身のオフライン検証は`moon -C experiments/jev-test test --target wasm`。
これにはAPIキーが不要で、Metonic本体のテストや有料APIを起動しない。

## 結果の扱い

.work/jev-metonicに保存した応答を再集計し、有料APIの再呼出しを避ける。
`evaluation-report`は応答とDiffの一致、期待IDの存在を確認し、モデル自身の判断と
安全策適用後の選択を分ける。ソースを含む実験データはGitへ追加しない。

未知の真の影響対象は未確定。今回の結果を実際の見逃し率や所要時間短縮率とは呼ばない。
過去の段階別実験はCOMPARISON.md、METONIC-COMPARISON.md、RECALL.md等を参照。
古い固定バッチ制限や初期の未実装事項は現在の仕様ではない。
