# フック対象の全件棚卸し

対象は実験worktreeの5dd06deと現在の修正（診断ゲート2件追加、SDK mailboxのinclude修正）。
別作業中のmainを同じ状態として扱わない。テスト実行・Jev API評価は実施していない。

## 範囲と結果

pre-commit、pre-pushの残件実行、検証記録が使えない場合の全実行の和集合を収録した。
条件付き検証も落とさず条件を記録する。個別Diffでcommit/pushのどちらへ割り当てるかは
この全体一覧とは別の問題。

| 対象 | 件数 |
|---|---:|
| 到達するmiseタスク | 58 |
| 上記タスクのrunコマンド | 111 |
| 参照・解析した検証/準備/実行入口ソース | 114 |
| MoonBit runner項目（backend別） | 1,237 |
| Nodeテスト | 34 |
| 型契約・reactive異常系・不正起動引数ケース | 46 |
| 名前付きパイプのパッチ内テスト | 6 |
| 構文解析器コーパスケース | 299 |
| 静的解析の正例・負例fixture | 5 |

親コマンド・検証スクリプト・準備確認を合わせたカタログは1,880行。
親と子を含むため、独立したテスト1,880件という意味ではない。
全行を質問へ変換し、ID集合・件数一致を確認した。APIには送信していない。

## 網羅性の照合

- verification.jsonの27ゲートから依存と入れ子mise呼出しを追跡。
  111コマンドすべてを収録し、未解釈のタスクコマンドは0。
- pre-commit.mbtx内の直接呼出し・条件・targetループも別に収録。
  末尾の2つの除外検証、commit専用確認、full fallbackを含む。
- Git管理下のMoonBitテスト定義539件をASTで独立走査。
  フック対象の466定義はrunner一覧のファイル/行と対応。未対応0。
  consumerの73定義はフックのmoon test対象外として全件別記した。
- 同期testだけでなくasync testも含む。以前13件としたnative_hostは
  async専用packageが漏れていたため28件へ訂正した。
- フックのNode --testが指定する4ファイルの全34ケースを収録。
  定数配列による動的名も展開。未知の動的名は黙って省かず収集を停止する。
- スクリプト内で直接testを起動する箇所も照合。WGPU13件、
  Windows constraint/captureのフィルターに一致する5件、named pipe6件、
  準備時のtree-sitterコーパス299件を収録した。
- 単独のtest宣言ではない統合・E2E・成果物検証は、実際のコマンドと環境設定、
  スクリプト全体を検証単位とした。内部のassertion一個を独立テストと偽らない。

これは固定したフック定義の静的棚卸し。任意コードの動的呼出し解析や実行成功の
証明ではない。新たなタスク・動的列挙形式・ソース変更時には再生成・再照合する。
全ファイルのダイジェストと対象revisionはcoverage JSONへ記録する。

## フック外と判明したもの

- consumers/metonic-notes: 56定義
- consumers/metonic-quote-board: 17定義

これらのアプリがbuildや統合検証で使われることと、独立moduleの単体テストを
moon testで実行することは別。現在のフックはその単体テストを呼んでいない。
今回の棚卸しでは未収集にせず、全73件の名前/場所/対象外理由を別一覧へ記録した。
またnative:window-displayは文書で明示されたopt-inのため通常フック外。

## 成果物

- `.work/jev-metonic/hook-inventory.md`: 全行とフック外73件の閲覧用一覧
- `.work/jev-metonic/hook-inventory.json`: 比較用全体カタログ
- `.work/jev-metonic/hook-inventory-coverage.json`: 呼出し経路、条件、元ソース、照合結果
- `.work/jev-metonic/hook-inventory-requests.json`: 全1,880行の質問データ（未送信）

再生成の入口はexperiments/jev-test/inventory-hooks.cjs。
既存outline/AST収集ファイルと、固定した構文解析器コーパスを入力に使う。
実行用ランナーへの接続・フックへのJev導入は今回行っていない。
