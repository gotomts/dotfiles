#!/bin/zsh
# setup/claude-code.zsh
#
# Tier 2: Claude Code CLI（ネイティブ版）を ${HOME}/.local/bin へ導入する。
#
# Homebrew cask (`claude-code`) から移行した。cask 版は Claude Code 自身のバックグラウンド
# 自動更新が効かず、`brew upgrade` を回した PC だけが新しい版になるため、複数台で版が
# 食い違う。公式ドキュメントもネイティブ版を推奨している。
#
# 版は宣言しない（setup/lib/claude-code.zsh のコメント参照）。公式インストーラを引数
# 無しで呼ぶと stable チャンネルが入り、以降の更新は Claude Code 自身が行う。ntn の
# ような版 pin をここに持ち込むと、自動更新が走るたびに health check が落ちる。
#
# 導入先は環境変数で指定しない・できない。インストーラが落とすバイナリの `claude install`
# が ${HOME}/.local/bin/claude にランチャーを置き、版ごとの実体は ${HOME}/.local/share/claude/
# 配下で自身が管理する。PATH への ${HOME}/.local/bin の追加は Tier 1 の zshenv が担当する。
#
# 冪等性: 既に ${HOME}/.local/bin/claude が実行可能なら何もしない。版を上げるのは
# Claude Code 自身の自動更新（または人間の `claude update`）の仕事で、このスクリプトは
# 既存の実体に触れない。
#
# fail-closed: claude は恒久的に宣言したグローバル必須ツールなので、初回ダウンロードの
# 失敗は migrate 全体の失敗として扱う（「入らなかったが成功」を健全な状態にしない）。
# 既にバイナリがある PC では一切ネットワークに出ないため、オフラインでも --apply は通る。
#
# 認証は扱わない: API キーや OAuth トークンをこのスクリプトは読まない・要求しない・
# 保存しない。導入後のログインは人間が `claude` 側の手順で行う（cask からの移行では
# ~/.claude 配下の設定・認証情報はそのまま引き継がれる）。
#
# 使い方:
#   zsh ${HOME}/.dotfiles/setup/claude-code.zsh
#
# 終了コード:
#   0  成功（既に導入済みで skip した場合も含む）
#   1  curl 不在、インストーラの取得/実行の失敗、または実行後に claude が現れなかった

set -eu

SETUP_DIR="${0:A:h}"
source "${SETUP_DIR}/lib/util.zsh"
source "${SETUP_DIR}/lib/claude-code.zsh"

CLAUDE_BIN="$(claude_code::bin "${HOME}")"
# テストではサンドボックス内のスタブを指す URL に差し替える（実ネットワークに触れない）。
CLAUDE_INSTALLER_URL="${CLAUDE_INSTALLER_URL:-https://claude.ai/install.sh}"

util::info "=== Tier 2: Claude Code CLI (native) ==="

# -f も見る: -x だけだとディレクトリ（実行ビットが立っている）を「導入済み」と
# 誤判定し、インストーラを呼ばないまま成功して抜けてしまう。
if [[ -f "${CLAUDE_BIN}" && -x "${CLAUDE_BIN}" ]]; then
    util::skip "${CLAUDE_BIN} は既に実行可能です（インストーラを呼びません）"
    exit 0
fi

if ! command -v curl &>/dev/null; then
    util::error "curl が見つかりません。Claude Code の導入をスキップせず失敗として扱います"
    exit 1
fi

installer="$(mktemp)"
trap '/bin/rm -f "${installer}"' EXIT

util::action "公式インストーラを取得します: ${CLAUDE_INSTALLER_URL}"
# curl を pipe で bash に直結しない。取得失敗時に空スクリプトを実行して「成功」に
# 見えてしまうのを防ぐため、ファイルへ落として取得の exit code を確かめる。
if ! curl -fsSL -o "${installer}" "${CLAUDE_INSTALLER_URL}"; then
    util::error "インストーラの取得に失敗しました: ${CLAUDE_INSTALLER_URL}"
    exit 1
fi

util::action "Claude Code (stable) を ${CLAUDE_BIN:h} へ導入します"
mkdir -p "${CLAUDE_BIN:h}"
# インストーラは bash 前提（#!/bin/bash）なので zsh では実行しない。引数は渡さない
# （引数無し = stable。版を固定しないという宣言側の判断をそのまま表す）。
if ! bash "${installer}"; then
    util::error "インストーラの実行に失敗しました"
    exit 1
fi

if [[ ! -f "${CLAUDE_BIN}" || ! -x "${CLAUDE_BIN}" ]]; then
    util::error "インストーラは成功しましたが ${CLAUDE_BIN} が実行可能になっていません"
    exit 1
fi

util::info "${CLAUDE_BIN} を導入しました"
