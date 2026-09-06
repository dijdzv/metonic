# 依存の初期記録

| 依存 | 固定/確認バージョン | 区分・対応 | ライセンス確認 |
| --- | --- | --- | --- |
| MoonBit core | 0.7.2+938b1f804 | 標準言語基盤。native/js/wasm-gcで試験済み | 同梱moon.mod.json: Apache-2.0。配布時のNOTICE等は追加確認 |
| MoonBit compiler/moon | environment.md参照 | ビルド時、既存インストールを照合 | 配布条件の全文監査は未実施。バイナリーを同梱しない |
| Node | 24.19.0 | JS試験用。製品nativeの実行時依存ではない | 今回再配布なし |
| MSVC / Windows SDK | environment.md参照 | Windows nativeのビルド時 | 今回再配布なし |

Mooncakesの外部依存、Rust crate、npm packageは追加していない。
gRPCのcodec/runtime、GPU、文字基盤、フォントは未選定。
新規依存採用時にバージョン/commit、ターゲット、ライセンス、配布物を更新する。

metonic自体はMIT OR Apache-2.0。
Apache本文の取得元: https://www.apache.org/licenses/LICENSE-2.0.txt
MIT本文の参照元: https://opensource.org/license/mit
