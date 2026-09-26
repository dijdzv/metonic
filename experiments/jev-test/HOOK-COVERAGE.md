# 比較対象の全件収集（最新方針）

この資料は以前の実行接続・故障注入を次の優先作業とした記述に優先する。
今後はDiffと対象範囲の全一覧を用いたJev判定比較に集中する。
対象テストの実行、故障注入、フックへの実行接続は今回の作業に含めない。

## 毎回送る範囲

requestsはdossier.testsの全IDを送る。required、force_all、テスト自身の変更、
本文やシンボルの欠落を理由に送信から除外しない。任意情報がない場合はnull。
重複IDをエラーにし、一覧件数と質問件数の一致を確認する。
入力上限によるAPIリクエスト分割は、対象集合を減らす操作ではない。
既存の安全側の選択規則は送信と独立して残るため、モデル提案と最終選択は別物。

既存の1,110項目の保存一覧から1,110質問を生成できることを確認した。
これは送信用JSON生成の確認であり、API送信・全テスト収集完了を意味しない。
以前API送信から除かれていたrequiredの19項目も含む。

## フックの境界

.githooks/pre-commit → mise verify:commit-recorded
.githooks/pre-push → mise verify:push-recorded
実際の検証はscripts/pre-commit.mbtxのcommit/push分岐を照合する。
記録の再利用によりフック自体が省略される場合と、比較用の対象集合を区別する。

| 範囲 | 含めるもの | 現状 |
|---|---|---|
| root MoonBit | JS/WasmGC/Wasm/nativeのrunner一覧 | 1,085実行対象を収集済み。commit/push割当は変更と基準commitに依存 |
| full_gate_tasks | verification.jsonの25タスク | タスク単位で収集済み。全内部テストの列挙ではない |
| push統合部分 | 上記からverify/verify-nativeを除いた23タスク | フック定義で確認 |
| push末尾 | verify-window-fixture-exclusion、verify-window-production-exclusion | 従来の25タスク外。追加対象 |
| commit共通検証 | JS/WasmGC check、static-analysis、verification_impact_cliのWasmテスト、application-build-inputs | 別途対象の対応付けが必要 |
| commit別workspace | browser_host経由のasync_runtime clock/http/application_taskのJSテスト | outlineが生成workspace不足で未取得 |
| commit native workspace | plan-native-verification選択対象、async_runtime clock/http/application_task、rpc_client | 個別一覧と変更依存の割当が未完了 |
| commit契約 | JS/WasmGC/nativeのfrontend実行・verify-types | テストランナー外の検証として列挙が必要 |
| commit条件付き | reactive negative（指定パス変更時） | 条件を満たすDiffで対象に含める |
| commit文書 | verify-docs | 通常の単体テスト一覧とは別 |
| headless内Node | browser-observationの5件 | 個別収集済み。親タスクと重複計上しない |

整形・依存準備は検証の前提として記録し、単体テスト数に加算しない。
条件付きのcommit/push対象を得るには実Diffと比較commitが必要。
全backendを一括した上限集合を、あるフックの正確な対象集合と呼ばない。

## 現在の不足

このworktreeには.work/browser-host-devがなく、browser_host経由のoutline取得が
workspace解決で停止した。テスト実行はしていない。
不足分をゼロ件扱いせず、全件比較用のAPI送信は一覧の整備後に行う。
main/Sol側のフォルダは変更しない。

大きなゲート名だけを1項目渡すことと、内部の全テスト名を渡すことは別である。
現時点で「全テストを網羅」とは扱わない。次は不足moduleの一覧取得と、
ランナー外検証の名前・入口・条件を収集し、範囲内の未収集をなくす。

## 接続修正後の収集更新

- full_gate_tasksは診断2件を加え27件。`gates`で再収集した。
- `push-runtime DOSSIER OUT`を追加。verify/verify-nativeを除いた25件と、
  フック末尾の除外検証2件を列挙する。pushの残りrootテストはこの範囲に含まない。
- extract-node-tests.cjsはフックが呼ぶ4ファイルを扱い、合計34件を列挙する。
  session-failureの2つの定数配列ループも4つのケース名へ展開する。
  未対応の動的名・重複・構文エラーは停止する。汎用JS解析ではない。
- 27件と34件はそれぞれ質問数・ID集合の一致を確認。対象テストは実行していない。
  これは送信用データの生成までであり、APIへの全件比較送信ではない。
- Node34件は親タスク内の内訳。27タスクと加算して61個の独立テストとは数えない。
- browser-host-devの生成準備は完了。次の不足は.work/websys-input/generated。
  browser async outlineはまだ取得できておらず、空一覧として採用しない。

データは.work/jev-metonic/hook-gates-27.json、push-runtime-{dossier,evidence}.json、
hook-node-dossier.json。これらに含むDiffは保存済みlabel-name比較用のもの。
一覧の完全性を調べるための生成であり、最新mainの全件一覧ではない。

## 別moduleの一覧追加

準備済み依存のソースとmanifestをmain作業フォルダからこのworktreeの.workへ
コピーし、browser-host-devは既存準備スクリプトで生成した。mainは変更していない。
コピーは秘密ファイルを含めず、MoonBitソース・manifest・C境界・準備JSに限定。
これは一覧取得用の依存スナップショットであり、再現ビルドの検証ではない。

| 追加対象 | runner項目 | AST対応 |
|---|---:|---:|
| browser_host経由のasync_runtime clock/http/application_task、JS | 53 | 53 |
| native_host経由の同3package、native | 53 | 53 |
| native_host内のtest定義を持つ6package、native | 13 | 13 |

全119項目について本文・参照シンボルを付けた。JSとnativeの同名テストは別ID。
outlineの取得と質問生成のみ実施し、テストは実行していない。
nativeのoutlineはコンパイルを伴う。AccessKitはmain側の準備済みヘッダー/ライブラリを
読み取り専用で利用した。ビルド出力はこのworktree内。

native_hostの全38packageを指定したoutlineは、sdk_mailbox_probe/boundary.cが
../accessibility_probe/navigate.cを参照するがそのファイルがないため失敗した。
test定義を持つ6packageに限定した列挙は成功。テストがない検証用実行ファイルは
この13件とは別のタスク検証として扱い、失敗した全38package列挙を成功扱いしない。
この不足の修正・検証は今回実施していない。

ASTブリッジはlocal/p0に加えlocal/metonic_asyncとlocal/native_hostのパス対応を追加。
未対応moduleは停止する。保存outlineのインポートは呼出側で終了コード0を確認して使う。
全hook内部の個別シナリオや最新mainへの追従は依然として未完了。
データ: browser-async/native-async/native-host-dossier.jsonと各requests.json、
browser-async/native-async/native-host-tests-outline.log（.work/jev-metonic内）。

## 契約ケースと統合カタログ

extract-contracts.cjsでverify-typesの5ケース×3targetを収集。
validはcheck/build成功、その他はcheck失敗かつtype mismatch診断を期待する。
verify-reactive-negativeの7ケース×3targetも抽出し、pre-commitの変更パス条件が
falseならscope_exclusionsへ理由付きで記録する。保存label-name Diffでは21件が
条件外、型契約15件が対象。これはケース列挙であり個別実行コマンドではない。

保存label-name Diffを共通にしたhook-catalog-partial.jsonを生成した。
root1,085＋runtime検証27＋Node34＋別module119＋型契約15＝1,280項目。
hook-catalog-requests.jsonの質問数も1,280で、ID重複を拒否している。
親ゲートと内訳を含むカタログであり、独立したテスト1,280件やフック完全網羅を
意味しない。commit/pushのroot割当、他の独自verifier内部、最新main反映は未完。
今回API評価とテスト実行は行っていない。

sdk_mailbox_probeの欠落includeは移設履歴1c0695cを確認し、実在する
../uia_test_bridge/navigate.cへこのworktree内で修正した。
native:production-integration→production-probesの経路でも必要なファイル。
差分とパスは確認したが、修正後のビルド・テストは未実施。
