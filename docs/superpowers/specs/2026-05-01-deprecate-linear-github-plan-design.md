---
title: linear-plan / github-plan 廃止設計
date: 2026-05-01
status: draft
---

# linear-plan / github-plan 廃止設計

## 1. 目的

`claude/skills/linear-plan/` と `claude/skills/github-plan/` の 2 スキルを廃止し、関連ドキュメント・auto memory を整理する。

## 2. 背景

`create-issue` スキル（spec / plan を入力に Linear / GitHub の親 Issue + sub-issue を自律登録する design-doc 駆動パイプライン）が既に存在し、`feature-team` Phase 2 から呼ばれて実運用されている。

これに対し `linear-plan` / `github-plan` は本質的に「アイデア起点の対話深掘り → Issue 登録」を 1 スキルで完結させるショートカットでしかなく、以下のチェーンと役割が重複している:

```
superpowers:brainstorming → superpowers:writing-plans → /create-issue <tracker> <spec> <plan>
```

`feature-team` も Phase 1-2 で同じチェーンを内包しているため、`linear-plan` / `github-plan` を残し続ける積極的な理由はない。スキル数を減らすことで:

- MEMORY.md / CLAUDE.md / 関連スキル間の整合性メンテが軽くなる
- 「`/create-issue` を中心に据え、対話深掘りは `superpowers:brainstorming` に集約」という責務分離が明快になる
- 認知負荷（10 スキル → 8 スキル）が下がる

## 3. スコープ

### 削除対象

- `claude/skills/linear-plan/` ディレクトリ（`SKILL.md` 含む）
- `claude/skills/github-plan/` ディレクトリ（`SKILL.md` 含む）

### 削除後の標準経路

| ユースケース | 経路 |
|---|---|
| 思いつき → Issue（実装はまだ） | `superpowers:brainstorming` → `superpowers:writing-plans` → `/create-issue <tracker> <spec> <plan>` |
| Issue → 実装・レビュー・PR まで一気通貫 | `/feature-team` |
| spec / plan が既にある状態で Issue だけ登録 | `/create-issue <tracker> <spec> <plan>` |

### 更新対象（参照・棲み分け記述を整理）

| ファイル | 修正内容 |
|---|---|
| `CLAUDE.md` (L53) | `create-issue` 説明末尾の「対話起点の `linear-plan` / `github-plan` とは棲み分け」を削除 |
| `claude/skills/feature-team/SKILL.md` (L155) | `(既存 linear-plan / github-plan のような対話深掘りステップは持たない)` の括弧書きを削除 |
| `claude/skills/feature-team/README.md` (L264-265) | 表の行 N（`既存 linear-plan / github-plan`）を削除 |
| `claude/skills/feature-team/README.md` (L300) | bullet `既存 linear-plan / github-plan を改修せず温存` を削除 |
| `claude/skills/create-issue/SKILL.md` (L3 description) | `既存の linear-plan / github-plan（対話起点の単発用途）とは棲み分ける。` を削除 |
| `claude/skills/create-issue/SKILL.md` (L38) | `対話によるアイデア深掘り（linear-plan / github-plan の役割）` を `対話によるアイデア深掘り（superpowers:brainstorming の役割）` に置換 |
| `claude/skills/create-issue/SKILL.md` (L284) | `（既存の github-plan で確立されたパターン）` の括弧書きのみ削除（バッチパターン自体は残す） |
| `claude/skills/create-issue/SKILL.md` (L323-331) | 末尾「既存スキルとの棲み分け」表と直下の段落を全削除 |
| `~/.claude/projects/-Users-goto--dotfiles/memory/project_feature_team_skill.md` (L15) | `既存 linear-plan / github-plan は無改修で温存` 箇所を削除（feature-team の判断基準のみ残す） |

### 残すもの（履歴的ドキュメント）

- `docs/superpowers/specs/2026-04-08-linear-github-workflow-design.md`
- `docs/superpowers/plans/2026-04-08-linear-github-workflow.md`

→ 2026-04-08 時点の設計・実装記録として温存。当時のスナップショットを書き換えると履歴の整合性が崩れるため触らない。`depends-on` フロントマターも宣言されていないので CLAUDE.md の「Document Dependency Check」ルールにも抵触しない。

## 4. アーキテクチャ

廃止後のアイデア → Issue → 実装パイプライン:

```
[アイデア]
   |
   v
[superpowers:brainstorming]
   |  spec を docs/superpowers/specs/YYYY-MM-DD-*.md に書き出し
   v
[superpowers:writing-plans]
   |  plan を docs/superpowers/plans/YYYY-MM-DD-*.md に書き出し
   v
[/create-issue <tracker> <spec> <plan>]
   |  Linear or GitHub に親 Issue + sub-issue を自律登録
   v
[Issue 登録完了]
   |
   v (実装まで進める場合)
[/feature-team] が Phase 1-6 を回す（または手動で /issue-dev <番号>）
```

`/feature-team` を使う場合は Phase 1（brainstorming）→ Phase 2（create-issue）が同じチェーンを内部で実行するため、ユーザーから見たエントリポイントは 2 つに集約される:

- 単発で Issue だけ立てたい: 上記 3 段チェーン（手動）
- 実装まで一気通貫: `/feature-team`

## 5. 検証観点

事前検証（spec 段階で確認済み）:

- ✅ `aliases` / `functions/` / `claude/settings.json` / `claude/hooks/` に `linear-plan` / `github-plan` の参照がない（grep 確認済み）
- ✅ `/create-issue` 単独で Linear / GitHub 両方に登録可能（既存実装で対応済み）
- ✅ `/feature-team` が Phase 1-2 で `brainstorming → writing-plans → create-issue` を内包（既存実装で対応済み）
- ✅ MEMORY.md インデックスには直接の言及なし（参照先ファイル `project_feature_team_skill.md` 本文のみ要修正）

実装後検証:

- 削除対象ディレクトリが消えていること
- `setup/setup.zsh` 経由の symlink が `~/.claude/skills/linear-plan` / `~/.claude/skills/github-plan` を指していないこと（再 setup で残骸が消えるか手動で除去）
- 更新対象 5 ファイル / 9 箇所から `linear-plan` / `github-plan` への参照が消えていること（grep 確認）
- 履歴的 docs（`2026-04-08-linear-github-workflow-*.md`）には参照が残っていてよいこと（履歴として温存）

## 6. スコープ外（今回やらない）

- `feature-team` への "Issue 作成だけで停止" モード追加 — 廃止後は手動 3 段チェーンで対応可能。必要が出たら別 spec
- `create-issue` の機能追加（Linear project 自動付与の欠落など、auto memory にある既知課題）— 別タスク
- `superpowers:brainstorming` / `superpowers:writing-plans` の改変 — 標準スキルなので触らない

## 7. 受入条件

- [ ] `claude/skills/linear-plan/` ディレクトリが存在しない
- [ ] `claude/skills/github-plan/` ディレクトリが存在しない
- [ ] `~/.claude/skills/linear-plan` / `~/.claude/skills/github-plan` の symlink が存在しない
- [ ] `git grep -E 'linear-plan|github-plan'` の結果が、`docs/superpowers/{specs,plans}/2026-04-08-linear-github-workflow-*.md`（履歴）と本 spec / 後続 plan のみであること
- [ ] auto memory `project_feature_team_skill.md` から `linear-plan` / `github-plan` への言及が消えていること
- [ ] `setup/setup.zsh` を再実行しても残存 symlink がリンクされ直さないこと（symlink 対象に存在しないので自然に消える）
