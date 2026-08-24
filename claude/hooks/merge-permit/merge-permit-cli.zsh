#!/bin/zsh
# merge-permit CLI の zsh エントリポイント。本体は cli.py (JSON/permit ストア
# 操作は Python の方が扱いやすいため)。このラッパーは規約 (zsh シバン・
# emulate -L zsh) に沿った薄い呼び出し層に留める。
#
# 使い方:
#   merge-permit-cli.zsh create --action gh-pr-merge --target 123 --actor hermes
#   merge-permit-cli.zsh list
#   merge-permit-cli.zsh inspect --id mp_xxxxxxxxxxxx
#   merge-permit-cli.zsh revoke --id mp_xxxxxxxxxxxx
#
# 運用フローは ~/.dotfiles/claude/merge-permit-policy.md を参照。

emulate -L zsh
setopt no_unset pipe_fail

local script_dir="${0:A:h}"

exec python3 "${script_dir}/cli.py" "$@"
