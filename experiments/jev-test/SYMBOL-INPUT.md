# シンボル入力の実体と拡張比較

## 現在渡しているもの

Diff、変更ファイル、テスト名、package、file、kind、IDに、構文上の参照名配列を追加する。
MoonBitはAST-grepのqualified_identifier、qualified_type_identifier、method_expression、
dot_identifierから抽出し、重複除去して並べる。Nodeはcall_expressionのcallee。
ソース全文とテスト本文はsymbolsモードでは送らない。

例: core/semantics/registration_test.mbtの名前変更テストには
set_name、revision、set_selection、assert_eq、.focused、.name、tree、nodeなどが入る。
同じpackageの関数は裸の名前になる。型解決・呼出し先解決・推移的依存解析はしていない。
tree/nodeなどローカル変数や一般的なassertも含む。これを完全な依存グラフとは扱わない。

## 検証用ソースへの拡張

enrich-verifier-symbols.cjsは既存の全1,880 IDと既存シンボルを維持し、空だった
verifier/supporting source 114項目へAST参照名を追加する。
コーパス298項目には期待ASTのgrammar:<node kind>を追加した。
エラーを期待して具体的ASTを持たない1件は空のまま残す。項目自体は除外しない。
元コードの型解決は行わず、JSの複雑なcalleeも構文どおりなので長い項目が一部ある。

## ラベル名変更の実API比較

固定の全1,880項目、同一Diff、探索用0.5/0.6条件。本文全文は未送信。

| 入力 | 除外候補 | API時間 | 入力tokens | 既知失敗3件の除外 |
|---|---:|---:|---:|---:|
| 従来シンボル | 294 | 35,927ms | 589,721 | 0 |
| 検証用ソース・構文種別を追加 | 325 | 44,360ms | 656,231 | 0 |

追加後も1,880件すべてのIDに応答が返った。
script-verifierは2→16、supporting-verificationは5→24が除外候補。
コーパスは両方0で、構文種別の追加だけで改善したとは言えない。
MoonBit249→247など、情報を変えていない項目にも揺れがある。
各条件1回で入力分割も変わるため、差分を全て追加情報の効果と断定しない。
カタログは親子を含み、325件を実行削減数・時間短縮率に換算しない。

テスト実行や新しい故障注入は行わず、以前の既知失敗と選択を照合した。
シンボル付き方式を継続しつつ、verifierの参照情報は候補として維持する。
コーパスの構文種別は現時点で有効性が確認できていない。

データ: .work/jev-metonic/hook-enriched.json、full-enriched-{response,plan,summary}.json。
