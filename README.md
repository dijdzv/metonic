# metonic

MoonBitを主言語とするGPU UIと、UIから独立した型付きRPCの実験プロジェクト。
Windows nativeを優先し、ブラウザWebGPUも第一級ターゲットとします。

現在はP0の技術検証段階です。GPU UIフレームワークや通信ライブラリとしてはまだ使えません。

## 動かせるもの

`Procedure[Input, Output, DomainError]`、契約専用パッケージ、プロセス内の型付きhandler binding。
native / JS / WasmGCで成功・業務エラーと型不一致の拒否を検証しています。
HTTP・gRPC・GPU描画・IMEは未実装です。

```powershell
mise trust
mise install
mise run doctor
mise run verify
mise run verify-native
```

現時点でmiseがインストールするのはNodeのみです。MoonBitとWindowsのC++ビルド環境は
[環境記録とセットアップ](docs/verification/environment.md)を参照してください。

## 作業の入口

- [開発・Issue・PR・リリース運用](CONTRIBUTING.md)
- [P0検証結果と残作業](docs/verification/p0.md)
- [設計ベースライン v0.2](DESIGN.md)
- [引き継ぎ資料](CODEX_HANDOFF.md) / [元のZIPのREADME](HANDOFF_README.md)
- [名称・運用・環境の決定](docs/adr/022-bootstrap.md)

設計書中の「名称未定」は引き継ぎ時点の記録です。2026-09-06にユーザーが
`metonic` / `dijdzv/metonic` を指定しました。MoonBitの `local/p0` は検証専用の内部module名で、
公開Mooncakesパッケージ名はまだ設定していません。

## ライセンス

Copyright (c) 2026 dijdzv and contributors.

MIT OR Apache-2.0。利用者はいずれかを選択できます。
[MIT](LICENSE-MIT) / [Apache-2.0](LICENSE-APACHE)
