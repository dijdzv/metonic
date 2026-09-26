# Metonic本体でのAST抽出・選択比較（2026-09-26）

対象は専用worktreeのcommit `5dd06de`。進行中のSol側の最新状態ではない。
変更・ビルド・テストは専用worktree内で実施し、故障注入は元のバイト列へ復元した。

## 規模と対象範囲

- Git管理のMoonBitソース487ファイルからAST上のテスト定義539件を検出。
- root module `local/p0` のJS対象は74ファイル・286テスト。
- `moon test --outline --target js`の全286件とASTの位置を照合し、286件一致。
- この74ファイルに絞った抽出は169〜180ms。全487ファイルの初回解析は9,069ms。
- 全件テストは正常状態で286/286成功。別moduleのasync/browser/nativeやWindows実入力、
  WasmGC、配布ゲートはこの286件に含まれない。したがって全Metonic検証時間とは異なる。

## 実装

既存の静的解析基盤で準備済みのMoonBit parser DLLを実験ディレクトリへコピーして使用。
grammarの上流commitは5435c307c6cf2ef0d508a99047b06f35a4308444。
実際のDLLは既存準備処理によるもの（リポジトリのパッチを含む）で、SHA256は
46e47022f0e855932fa595963cf4ebd71f083dbEadb6e8e0db9b4edff19713d3。
AST-grep Node APIは@ast-grep/napi 0.45.3。

`extract-ast.cjs`は外部AST APIとの境界。モデルへの問い合わせ・選択処理はMoonBit。
`test_definition`から`block_expression`を取得し、qualified_identifier、
qualified_type_identifier、method_expression、dot_identifierを重複除去して抽出する。
これは構文上の名前で、ローカル変数も含み、型解決済みの呼び出しグラフではない。
parser ERRORのあるファイルや位置不一致のテストは本文・参照名を利用不可にする。
body/symbolsモードで必要情報がないテストはAPI評価から外し、欠落応答として必ず実行する。

`collect`→`enrich DOSSIER OUT`→`evaluate`を接続済み。
`filter`のbody/symbolsもAST補完を通す。今回のアダプターはlocal/p0・JSに限定し、
他module/backendを誤って処理しないよう拒否する。実験用依存は.work/jev-ast以下。

準備例（既存静的解析準備後）:
```
npm install --prefix .work/jev-ast --no-audit --no-fund @ast-grep/napi@0.45.3
```
parser DLLを `.work/jev-ast/tree-sitter-moonbit.dll` に配置する。
今回既存の別checkoutからコピーしたが、本来はscripts/prepare-static-analysis.mbtxで
当該worktreeに準備する。上流grammar clone単体のDLLと混同しない。

## 故障注入

core/semantics/model.mbtの2箇所を別々に変更し、それぞれ全286件を実行した。

1. set_nameで新しい名前を書き込まない: 3件失敗。semanticsの登録テストに加え、
   componentのUI root・keyed childrenテストも失敗。
2. set_enabledで無効化時のfocusを解除しない: semanticsの登録テスト1件失敗。

各変更についてnames/symbols/bodyを1回ずつ評価。保存済み応答で候補条件も検討した。
候補条件は score<=0.5、confidence>=0.6、P(0)>=0.6で省略。
この条件は前の合成試験から持ち込んだ探索用で、標準設定へ採用していない。

| 変更 | モード | 候補条件の選択数 / 286 | 実失敗の見逃し | API評価時間 | 入力tokens |
|---|---|---:|---:|---:|---:|
| 名前更新 | names | 246 | 0/3 | 1,879ms | 64,203 |
| 名前更新 | symbols | 238 | 0/3 | 3,917ms | 90,963 |
| 名前更新 | body | 183 | 0/3 | 7,336ms | 156,866 |
| focus解除 | names | 247 | 0/1 | 1,717ms | 64,217 |
| focus解除 | symbols | 229 | 0/1 | 4,116ms | 90,991 |
| focus解除 | body | 152 | 0/1 | 8,093ms | 156,908 |

現行の標準条件は全モード286件選択。標準条件での省略効果はない。
本文付きはAPIのmax_tokens_exceededを実際に受け、質問群の分割で回復した。
名前更新のbodyは286→143+143→143+71+72となり、成功した3バッチのtokens合計を記載。
各値は一回の観測で、サーバ混雑や実行順の影響を分離していない。

## 選択後の実行時間

正常状態へ戻し、bodyの候補集合が触れるファイルをまとめて1回のmoon testへ渡した。
ファイル内の非選択テストも実行する方式なので、細かい選択より多めに実行する。
実行はすべて成功。精密なindex range実行のコマンド数は静的に数え、実行時間は未計測。

| 選択由来 | 細かい選択数 | file数 | ファイル単位の実行数 | 必要な精密range起動数 | ファイル一括実行 | API込み |
|---|---:|---:|---:|---:|---:|---:|
| 名前更新 | 183 | 64 | 254 | 79 | 9,492ms | 16,828ms |
| focus解除 | 152 | 53 | 201 | 60 | 6,560ms | 14,653ms |
| 通常全件 | 286 | 74 | 286 | — | 8,539ms | 8,539ms |

API込みにAST抽出・収集・CLI起動費用は含めていない。それでも高速化しなかった。
単回の時間差を精密な性能差と扱わない。故障注入直後の全件実行はビルドを含み
約10.4秒だったので、暖機後の8.5秒とは条件が異なる。

## 判断

AST抽出は十分軽い。追加情報で省略率は増えるが、Metonic本体では個別本文の費用が
合成fixtureより大きい。全テストへ本文付きで問い合わせる方式は現時点で採用しない。
既存tools/verification_impactはMoonのpackage graphと実装・blackbox・whiteboxの
逆依存を使えるので、まずそこで候補を減らすべき。Jevは残った高コストのテスト群へ
適用し、package/file単位でまとめて実行できる範囲を優先する。
この接続と、native/browser統合ゲートを含む全体での短縮効果はまだ未実装・未測定。
2種類の故障だけで安全性や一般的な見逃し率は結論しない。

データ: `.work/jev-metonic/ast-inventory.json`, `results.json`, `timings.json`,
各responseと全件テストログ。再現用のOSハーネスはcompare-metonic.ps1。
メイン作業フォルダ・既存フック・標準閾値は変更していない。
