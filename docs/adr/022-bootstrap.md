# ADR 022: 初期運用と環境

日付: 2026-09-06。状態: 採用（初期運用）。

## 背景

入力ZIPは設計資料4ファイルだけで、既存実装はない。
ユーザーは小さなIssue・ブランチ・PRを積極的に使う運用を許可し、
リポジトリを `dijdzv/metonic`、公開で作成するよう指定した。
名称についてはDESIGN.md F-16/ADR 021の保留をこの直接指示で更新する。

## 決定

mainを統合先とし、短命ブランチとsquash PRを使う。通常リリースはタグのみ。
Git Flowのdevelopや常設releaseブランチは、並行保守の必要がない現段階では増やさない。
承認人数は0を基本とし、一人でも作業を止めない。詳細はCONTRIBUTING.md。

ライセンスはユーザーのMIT/Apache希望から `MIT OR Apache-2.0` とする。

miseをタスクの入口とNodeのバージョン固定に使う。
インストール済みmiseのregistryにMoonBitがないため、未検証プラグインは追加しない。
MoonBitは既存0.7.2の実測を初期ベースラインとし、doctorで不一致を拒否する。
Rustは今回のコードに不要なので、実装を導入するPRでrust-toolchain.tomlとCargo.lockを追加する。

CIは、MoonBitの固定バージョンをクリーン環境へ取得する方法を検証してから導入する。
既存ローカル環境の成功だけではクリーンCIの再現を保証できないため、別Issueで追う。
CDは配布物と配布先が決まってから導入する。

## 影響と証拠

新規ユーザー向けのMoonBit自動セットアップはまだない。
古いローカルコンパイラーと現在のドキュメントには差があるため、公開APIは固定しない。
P0-Dは、ローカルのnative/JS/WasmGCで正負のコンパイル試験を実行した。
GPUブリッジ、ブラウザターゲット、gRPC経路の採用判断はまだ行わない。

公式参照: [mise tasks](https://mise.jdx.dev/tasks/)、
[MoonBit package configuration](https://docs.moonbitlang.com/en/latest/toolchain/moon/package.html)。
新しい資料の記載を旧コンパイラーで検証済みとは扱わない。
