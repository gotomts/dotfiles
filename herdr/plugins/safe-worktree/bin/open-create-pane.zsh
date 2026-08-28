#!/bin/zsh
# herdr/plugins/safe-worktree/bin/open-create-pane.zsh
#
# アクション本体（bin/create.zsh）を popup ペインで開くだけの入口。
# アクションコマンドは TTY を持たない状態で実行されるため、ブランチ名の入力と
# 最終確認は popup 側で行う。キーバインドからはこちらを叩く。

set -u

SWT_ROOT="${0:A:h:h}"
source "${SWT_ROOT}/lib/common.zsh"

herdr_bin="$(swt::herdr_bin)"
plugin_id="${HERDR_PLUGIN_ID:-dotfiles.safe-worktree}"

exec "${herdr_bin}" plugin pane open --plugin "${plugin_id}" --entrypoint create
