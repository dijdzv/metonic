# 見逃しの確認範囲

2026-09-26。全テスト種別をJevで選択する方向を維持する。削減率の目標は置かない。
以下は故障注入による観測であり、影響対象を漏れなく選べる保証ではない。
候補条件はscore <= 0.5、confidence >= 0.6、P(0) >= 0.6。
これは実験条件であり標準設定やフックへ採用していない。

| root JSの故障 | 全実行で失敗したテスト数 | names/symbols/bodyでの見逃し |
|---|---:|---|
| 名前更新を無効化 | 3 | 0 / 0 / 0 |
| 無効化時のfocus解除を無効化 | 1 | 0 / 0 / 0 |
| navigation cacheのrevision照合を無効化 | 1 | 0 / 0 / 0 |

navigation cacheは全286件を実行して285成功・1失敗。
namesは108件、symbolsは148件、bodyは169件を省略候補とした。
失敗したnavigation_test.mbtのテストは3方式とも残った。
応答と実行ログは.work/jev-metonic/navigation-cache-*-response.jsonおよび
navigation-cache-full.logに保存している。
既存のJS+統合ゲート統一計画でも、名前更新の既知の失敗3件はすべて残った。

## 未確認・不成立

- UTF-16末尾境界を拒否する故障はexamples/p0/browserの初期化時にpanicし、
  全テスト結果が得られなかった。見逃しなしには数えない。ソースは復元済み。
- 統合・E2Eの省略候補は実際の故障検出との照合が未完了。
- JS以外の各backendの一覧は取得済みだが、同じ故障検出結果は保証しない。
- 全リポジトリの独立moduleおよび追加検証をまだ網羅していない。
- 小さなfixtureでは、さらに緩いscore <= 1 / confidence >= 0で見逃しがあった。

必要なのは閾値を単に下げることではなく、全種別のテスト情報の収集と、
省略したテストにも故障を検出するものが含まれないかの比較である。
初期化失敗や未完走は未判定として記録し、成功や見逃しゼロに変換しない。

## 統合検証の追加確認

bootstrap:test相当のコマンド（固定MoonBitによるbootstrap.mbtx --test-promotion）を
このworktreeで実行。正常実装は成功。marker_matchesの文字列比較を == から != に
反転すると210行のassert_falseで失敗した。元ソースはfinallyで復元した。
このdiffと25ゲートの更新済み観測情報をbody方式で評価し、bootstrap:testは
score 1.97、confidence 0.95、P(0)=0.01、探索用計画でもrun=trueとなった。
これは統合検証1件の陽性確認であり、全ゲート実行による見逃し率ではない。
生データは.work/jev-metonic/bootstrap-marker-{full.log,dossier.json,response.json,plan.json}。

収集側の欠陥も修正した。実行コマンドのlocal/native_host/<package>/<artifact>.exeから
対応するnative_host/<package>のMoonBitソースを収集する。従来の
async-pair:native-verifyでは実体async_pair_probe/main.mbtが欠けていた。
修正後は実体を含み、観測情報の上限による省略9件を検出したのでrequired=true。
以前のこのゲートの省略提案は根拠不足として撤回する。
gate-evidence-v3.jsonで342ファイルを解析し、この包含とrequiredを確認した。
動的な実行先や推移的importを完全に解決するものではない。
