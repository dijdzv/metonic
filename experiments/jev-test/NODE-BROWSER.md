# 個別実行できるブラウザ診断テストの選択

2026-09-26。browser:headlessの最初のコマンドが実行する
tools/devtools/browser-observation.test.mjsを対象にした。
Playwrightで実ブラウザを起動する5テストで、GPUアプリ本体のE2Eとは別の範囲。

## 収集と実行単位

extract-node-tests.cjs INPUT_DOSSIER OUTはAST-grepで静的なtest呼び出しを抽出する。
テスト名、本文、呼び出しシンボル、ファイル共通のimportを既存評価へ渡す。
モジュール全文は渡さない。IDはファイルと名前で構成する。
このファイルのフラットな5テストだけを監査済みとして対応し、名前の重複、
未対応形式、構文エラー、件数変更は停止する。汎用Node discoveryではない。

各テストにnode --test --test-name-pattern=<escaped exact name> FILEの引数配列を付ける。
正常実装で5コマンドすべてを個別実行し、各コマンドが意図した1件だけを実行して
成功したことを照合した。0件成功を対象テストの成功とは扱わない。
通常のMoonBitランナーへ渡されないようkindはunifiedにする。
自動混合ランナーへの接続はまだ行っていない。

## 故障との比較

正常実装の全5件は成功。browser-observation.mjsのpending.size < 8を< 7へ変更すると
全5件中1件が失敗した（outstanding requests remain bounded and disappear after completion、
7 !== 8）。実ソースはfinallyで元バイト列へ復元した。

探索用閾値score<=0.5、confidence>=0.6、P(0)>=0.6、body入力:

| 変更 | 実行候補 | 省略候補 | API時間 | 入力tokens |
|---|---:|---:|---:|---:|
| 保存済みラベル名変更diff | 0 | 5 | 743ms | 4,316 |
| pending保持数の故障diff | 5 | 0 | 656ms | 4,369 |

故障を検出したテストは実行対象に残った。ただしpending変更では成功した他の4件も
残っており、関連のあるファイル変更を細かく省略する精度はまだ改善の余地がある。
ラベル名変更も実ソースへ適用して省略候補の5件を全実行し、5件すべて成功した。
この変更では省略候補に失敗テストはなかった。検証後に元バイト列へ復元した。
この5件はcoreのビルド成果物を利用しないブラウザ診断テストであり、
アプリ本体のラベル表示に関するE2E検証を代替するものではない。

## 統合時の制約

この5件を省略してもbrowser:headless全体を省略してはいけない。
pixel verifierのテスト、supervisor経由のアプリ検証、必要な準備処理は別に残る。
親ゲート内の元コマンドを置換しないまま追加実行すると二重実行になるため、
現在は独立の選択計画と個別実行検証まで。フックは変更していない。

生データは.work/jev-metonic/node-{label,pending}-{dossier,response,plan}.json、
node-baseline.log、node-pending-full.log、node-label-full.log、node-index-*.log、node-runner-identity.json。
