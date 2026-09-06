# 環境とセットアップ

確認日: 2026-09-06。ローカルWindowsで実行。

| 項目 | 実測 |
| --- | --- |
| OS | Windows 11 Pro / 10.0.26200 / x64 |
| GPU | NVIDIA GeForce RTX 3060 |
| GPU driver | 32.0.16.1047 |
| mise | 2026.8.5 windows-x64 |
| Node | 24.19.0（miseで固定） |
| moon / moonrun | 0.1.20260119 / be99339 |
| moonc / core | 0.7.2+938b1f804 / 2026-01-20 |
| Rust（今回は未使用） | 1.93.0 / 254b59607 |
| Visual Studio | 2022 Community / Developer PowerShell 17.5.3 |
| Windows SDK include | 10.0.22000.0 |
| ブラウザ / WebGPU実行 | 未検証 |

初回SHA256:

- ZIP: `42D73D462E096D93D8A4D77F0F1256CD781EFDB61633037FCED5AAC4151D72A9`
- moon.exe: `D8324952861D4FAAEB1D30FF4194DAADF6AB6A5560AD7B21FB1D620C3829F57E`
- moonc.exe: `098FBE9222F2CC7FD13DF9AF08EFC3AE978CE9B16F801CAE59011B85171B59F0`

## 現在のセットアップ

1. miseと、記録したMoonBitツールチェーンをPATHへ配置する。
2. Windows nativeを試す場合はVisual StudioのC++ x64ツールとWindows SDKを用意する。
3. `mise trust`、`mise install`、`mise run doctor`。
4. `mise run verify`、Windowsでは追加で `mise run verify-native`。

mise管理下に置いたのはNodeとタスク。MoonBitインストーラーはまだ自動化していない。
新規環境への固定バージョン導入、取得アセットのチェックサム確認、CIは後続のtooling Issue。
`doctor` は異なるMoonBitを黙って使用せず失敗する。更新時は検証結果と一緒に変更する。

## nativeで見つかった問題と解決

既定のbundled tccでは `runtime.c:556: error: include file 'windows.h' not found`。
SDKがないのではなく、今回のtcc経路にincludeが渡っていなかった。
MSVCを `MOON_CC=cl` で選び、Visual Studio DevShellからSDK環境を読み込むと成功した。

この環境の `Launch-VsDevShell.ps1` はvswhereの日本語JSONで変換エラーになった。
DevShell DLLを直接Importし、`Enter-VsDevShell -VsInstallPath ...` を使って回避した。
`VSLANG=1033` は旧moonのコンパイラー出力のUTF-8変換panicを避けるため設定する。
実際のスクリプトは `scripts/verify.ps1`。

## 実行範囲

nativeはコンソールの契約試験のみ。JSはNode、WasmGCはmoonrunで実行。
ブラウザの描画・GPU初期化・日本語IME・アクセシビリティは未実施。
GPU情報の取得はGPU描画の合格証拠ではない。
