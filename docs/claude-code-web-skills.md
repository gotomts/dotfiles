# Claude Code on the web で自作スキルを全リポジトリで使う

## 課題

dotfiles で管理している自作スキル (`claude/skills/`、現在 21 個) は、ローカル
(CLI / デスクトップ) では home-manager が `~/.claude/skills/` に symlink するため、
同一マシン内の全リポジトリ・全セッションで自動的に効く。

一方 **Claude Code on the web** は毎回まっさらな ephemeral コンテナで fresh clone
起動するため、ローカルの `~/.claude/`（dotfiles 由来スキル含む）は一切引き継がれない。
クラウドに引き継がれるのは「作業リポジトリの clone の一部」だけ
（repo 内 `.claude/skills/` `.claude/agents/` `.claude/commands/` は読まれる）。

各リポジトリの `.claude/skills/` にスキル本体をコピーして回るのは、数が多く正本が
分裂してメンテ破綻するため避けたい。**正本は dotfiles 1 か所**に保ちたい。

## 方法

クラウド「環境」の **Setup script**（コンテナ起動時・Claude Code 起動前に root で実行。
書いた内容はスナップショットされ後続セッションに引き継がれる）で、dotfiles の
`claude/skills/` だけを sparse-checkout し **`~/.claude/skills/`（personal スコープ）**
に注入する。

その処理を `claude/web-skills-setup.sh` に集約した（これも dotfiles 管理 = 正本）。
各環境の Setup script フィールドには次の 1 行だけを貼る:

```sh
curl -fsSL https://raw.githubusercontent.com/gotomts/dotfiles/main/claude/web-skills-setup.sh | bash
```

スキル本体もスクリプト本体も dotfiles から実行時に取得するため、スキルを足す/直すのは
**dotfiles の `claude/skills/` を編集するだけ**でよい。各環境の UI を再編集する必要はない。

## なぜ project スコープ (`.claude/skills/`) ではなく personal スコープか

| | personal (`~/.claude/skills/`) ← 採用 | project (作業リポジトリ `.claude/skills/`) |
| --- | --- | --- |
| 適用範囲 | 全リポジトリで自動 | そのリポジトリのみ |
| fresh clone / 環境キャッシュ | リポジトリ外なので影響を受けない | clone で上書き・消失する懸念 |
| 誤コミット | 起こり得ない | `.git/info/exclude` 等の対策が必要 |

クラウドの HOME は `/root`、Claude Code は `~/.claude/skills/` を personal スコープの
skills として discover する（[公式 docs](https://code.claude.com/docs/en/skills) の
scope 表: personal = `~/.claude/skills/<name>/SKILL.md` = "All your projects"）。
Setup script は root で実行され同じ HOME に書くため、注入した skills がそのまま読まれる。

## 前提・注意

- dotfiles はパブリックリポジトリのため、`git clone` に認証は不要。
- ネットワークアクセスは環境の許可レベルに従う。GitHub への到達が必要
  （**Trusted** 既定の allowlist に含まれる）。**None** では失敗する。
- Setup script の出力は環境ごとに初回のみ実行されキャッシュされる。スキルを更新したら
  新しいセッションを開始すれば再取得される（キャッシュ期限 or 環境設定変更時に再実行）。

参考: [Claude Code on the web](https://code.claude.com/docs/en/claude-code-on-the-web)
