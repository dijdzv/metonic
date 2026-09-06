# Contributor instructions

- 日本語で思考・応答する。
- 設計は DESIGN.md、作業手順は docs/development.md、Git運用は CONTRIBUTING.md を参照する。
- 実装・検証・未実施を区別し、再現可能な技術記録を docs/verification/ に残す。
- 個人的な会話ログやエージェント間の引き継ぎメモはコミットしない。
- mainはPR経由で更新する。force pushや保護設定の緩和を行わない。
- miseタスクを使い、toolchain.jsonに固定した現行MoonBitで検証する。
- MoonBitをUIの主言語とし、Windows優先かつWebGPU第一級、RPCはUIから独立させる。
- 開発用CLI/MCPの接続機構は本番成果物から除外する。アクセシビリティは本番にも残す。
- AccessKitは評価候補。採用にはWindowsでの比較検証とADRの更新が必要。
