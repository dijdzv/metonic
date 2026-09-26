# E2E・統合検証を対象にする（2026-09-26）

従来の8.5秒はroot JSの286テストのみ。通常の全検証時間ではない。
verification.jsonのfull_gate_tasksには25タスクがある（初期調査中の26という報告は誤り）。
pre-commit.mbtxはこれらをmise経由で順次実行し、integration/pushではverifyと
verify-nativeを除外する。さらに最後の除外確認等もあり、25タスクの選択だけで
全フローを網羅したと扱わない。ユーザー報告の約10分は今回再計測していない。

browser:headlessにはbrowser:package、Playwright用のsupervisor、pixel verifier等、
native側にはhost/surface/accessibility等が含まれる。単体テスト一覧からは発見できず、
タスク定義・依存準備・実際に確認する振る舞いを別途持つ必要がある。

## 今回追加

- `gates DOSSIER OUT`: full_gate_tasksを正本に、mise.tomlの各定義とdependsの推移依存を収集。
  同じ評価APIへ渡せる検証タスク一覧にする。未解釈のdepends形式・欠落定義は中止。
- `plan-exploratory DOSSIER RESPONSES OUT`: score<=0.5、confidence>=0.6、P(0)>=0.6で省略候補。
  既存planの標準条件0.1/0.98は維持。方針名を計画に記録する。
- 統合タスクの計画は通常moon test -iランナーへ渡せないよう明示的に拒否。
  現段階は実行候補の比較用であり、既存フックの実行集合は変更しない。

## 実API結果

既に全件実行で不具合確認したlabel-name変更をstateにし、25タスクを1回で評価。
入力9,158 tokens、出力481 tokens、1,181ms。モデルjev-1.13.0。
緩めた候補条件でも25/25を実行対象とした。
例: native:headless-integration score1.72/confidence0.58、
native:window-integration 0.32/0.52、native:binding 0.35/0.48。

名前・コマンド・準備依存だけでは実際の検証内容が足りず、確信の低い応答が多い。
これを省略率を上げるためだけに低confidenceで省略する設定へ変える根拠はない。
前回の単体テスト候補の3〜4割削減を、全検証時間の3〜4割削減と解釈しない。

## 次に必要な情報

タスクごとに「何を観測して成功とするか」「対象アプリ/module/backend」
「共通のビルド・サーバ・配布準備」と「実行時間」を付ける。
準備を共有するタスクは、1つ省略しても準備時間を節約できるとは限らない。
テスト件数ではなく、依存準備を含む実行計画の短縮時間で評価する。
観測契約はverifier内のassertion・シナリオ定義から抽出し、モデルにタスク名から
推測させない。AST-grepを適用する対象はMoonBitだけでなくJS verifierも含む。
実行時間はタスク別計測を別途行う必要があり、今回の結果には未計測の削減分を入れない。

生データは.work/jev-metonic/gate-{dossier,response,plan}.json。

## AST観測情報の追加試験

extract-gate-evidence.cjsを追加。MoonBitとJavaScriptのAST-grepからassert/expect呼び出しを
位置付きで抽出する。scripts/toolsだけでなくnative_host/browser_host/examples/async_runtimeの
Git管理ソースを対象とし、文字列中の参照パスを追う。コード実行や.env読み込みはしない。
動的パス・生成コード・型解決は未対応なので、完全な検証契約の抽出ではない。
1タスク12,000文字、1観測400文字の実験用サイズ制御。省略件数とexcerptを明示する。
省略・切り出し・parse error・観測ゼロの場合はrequiredとして必ず実行に残す。

タスク本文のmise runによる間接呼び出しも収集へ追加した。dependsだけでは
native:headless-integrationとnative:window-integrationの実体が抜けていた。

最初のAST付き試験は25問・79,491入力tokens・3,385ms、4タスクが省略候補となった。
うち2つは観測の省略があり、そのまま使わない。収集修正とrequired適用後は
319ファイルを約821msで解析、19タスクは必須実行、6タスクのみAPI評価へ送信。
6問・13,678入力tokens・910ms。比較用閾値では以下の3つが省略候補:

- async-pair:native-verify
- native:binding
- bootstrap:test

残る22タスクは実行対象。これはラベル名更新の1変更に対するモデル提案であり、
この集合で統合検証を実行して故障検出を照合した結果ではない。速度短縮は未計測。
入力構造・対象が変わると境界付近の判断も変わったため、候補件数を保証しない。
標準閾値・既存フックは引き続き変更していない。

データ: gate-dossier-v2.json、gate-evidence-v2.json、gate-evidence-response-v2.json、
gate-evidence-plan-v2.json（.work/jev-metonic内）。次の対象は大きな検証タスクの
シナリオ分割と、それぞれの観測条件・実行時間・実際の故障検出の対応付け。
