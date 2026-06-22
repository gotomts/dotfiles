---
title: claude/AGENTS.md トークン削減 — サマリー（TL;DR）
issue: N/A
design: ./2026-06-21-agents-md-token-reduction-design.md
related:
  - N/A
---

# claude/AGENTS.md トークン削減 — サマリー

> 本書は TL;DR。詳細は design、実装手順は plan を参照（plan は `writing-plans` skill で後続作成）。

## 一言で

`claude/AGENTS.md` を **3.3k → ~2.3k tokens（約 -29%, ~-950 tokens）** に圧縮する。Claude default と重複するルールを削除し、詳細仕様（handoff のパス規約・memory load の仕組み）を独立ファイルに read-on-demand 化することで、全プロジェクト × 全セッションで発生する固定 token コストを削減する。

## 方式の要点

- **削除**: `#6 コードレビュー` セクション全体と `#7 セキュリティ` の OWASP・積極提案行を除去。Claude default の "OWASP top 10... immediately fix" でカバーされる範囲のため。
- **外部化**: `#12 セッション管理` の handoff 詳細仕様を `claude/handoff-policy.md` に、`#17 Local Overrides` の import 経路解説を `docs/memory-loading.md` に切り出す。AGENTS.md には**パス参照のみ**残し、`@import` を使わず read-on-demand とする。
- **統合・圧縮**: `## 出力方針` の単独セクションを `# コミュニケーション方針` に統合。冗長な言い回しを各セクションで引き締める。

## フロー図

```mermaid
flowchart TD
  Start[Claude Code セッション開始] --> Auto[auto-load チェーン]
  Auto --> CMD[~/.claude/CLAUDE.md]
  CMD -->|@import| AG[claude/AGENTS.md<br/>~2.6k tokens]
  CMD -->|@import| LOC[CLAUDE.local.md]
  AG -.->|read-on-demand| HP[claude/handoff-policy.md]
  AG -.->|read-on-demand| ML[docs/memory-loading.md]
  HP -.->|trigger: ハンドオフから再開| Agent[エージェント]
  ML -.->|trigger: /memory デバッグ| Agent
```

## 効いている設計判断

- **外部化は `@import` ではなく `read-on-demand` を選択**: `@import` で読み込ませると結局メモリに乗り、削減目的を達成できない。AGENTS.md にはパス参照だけ残し、必要時にエージェントが Read する形にする。
- **handoff skill 本体は触らない**: skill 本体は upstream（mattpocock/skills）と完全同期する運用。PC 固有の運用規約は AGENTS.md か `claude/handoff-policy.md` 側に置く（後者を採用）。
- **削除はロールバック可能性を担保**: コードレビュー / OWASP セクションの削除で実害が出た場合は `CLAUDE.local.md` 側で個別追加できる。AGENTS.md 全削除と異なり影響範囲が小さい。

## スコープ外

- project AGENTS.md（dotfiles リポジトリ内の 5.2k tokens）の削減。本タスクでは触らない。
- handoff skill 本体の改変。upstream 同期方針を維持する。
- nix 設定の構造変更。`claude/` 配下の symlink 展開は既存設定でカバーされる。

## 確認事項（実装フェーズ）

- AGENTS.md 編集後、Claude Code を再起動して `/context` で token 数が ~2.3k（許容幅 2.1k〜2.5k）に減少しているか目視確認。
- `darwin-rebuild build` が新規ファイル追加後も成功するか確認。
- 別 PC で `CLAUDE.local.md` が無い環境でも `@import` skip が機能するか（既存挙動の維持確認）。
