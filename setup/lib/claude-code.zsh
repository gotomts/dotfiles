#!/bin/zsh
# setup/lib/claude-code.zsh
#
# Claude Code CLI（ネイティブ版）のパス解決だけを持つ共有ライブラリ。導入する側
# (setup/claude-code.zsh) と確認する側 (setup/migrate.zsh の health check) が同じ定義を
# 引くためにここへ寄せている（setup/lib/notion.zsh・setup/lib/herdr.zsh と同じ理由）。
#
# 版は宣言しない。ネイティブ版はバックグラウンドで自動更新する設計で、その自動更新が
# 効くことが Homebrew cask から移行した理由そのものなので、dotfiles 側で版を固定すると
# 「自動更新が走るたびに health check が落ちる」状態になる。版の管理は Claude Code
# 自身に任せ、宣言側は「実体があること」だけを要求する（ntn の NTN_PINNED_VERSION とは
# 意図的に方針が違う）。

# claude_code::bin <home>  <home> を持つユーザーの claude ランチャー実体パス
#
#   公式インストーラは導入先を環境変数で受け付けない（`claude install` が
#   ~/.local/bin/claude にランチャーを置き、実体の版は ~/.local/share/claude/ 配下で
#   自身が管理する）。ここはその固定された契約を 1 箇所に書き留めるためのもので、
#   パスを変える設定ではない。
claude_code::bin() {
    echo "${1}/.local/bin/claude"
}
