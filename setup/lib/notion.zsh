#!/bin/zsh
# setup/lib/notion.zsh
#
# Notion CLI (ntn) の宣言値とパス解決だけを持つ共有ライブラリ。導入する側
# (setup/notion.zsh) と確認する側 (setup/migrate.zsh の health check) が同じ定義を
# 引くためにここへ寄せている。別々に書くと、版を上げたときに片方だけ古い値を見に行く
# （setup/lib/herdr.zsh を分けているのと同じ理由）。

# 宣言する版。上げるときはここを書き換える。
#
# 既存バイナリの自動差し替えはしない。版を上げると health check が fail-closed で
# 落ちるので、人が実体（notion::bin のパス）を削除してから --apply を再実行する。
# 実行中かもしれないバイナリを migrate が黙って置き換えないための取り決め。
NTN_PINNED_VERSION="0.23.4"

# notion::bin <home>  <home> を持つユーザーの ntn 実体パス
notion::bin() {
    echo "${1}/.local/bin/ntn"
}

# notion::installed_version <bin>  実体が報告する版を返す。取得できなければ空文字列。
#   `ntn --version` は `ntn 0.23.4` の形で出すので最終フィールドを取る。
notion::installed_version() {
    "${1}" --version 2>/dev/null | awk 'NR == 1 { print $NF }'
}
