#!/bin/zsh
# setup/lib/hermes.zsh
#
# Hermes Agent 側に置かれる RTK 連携プラグインの識別子とパス解決だけを持つ共有ライブラリ。
# 導入する側 (setup/hermes-sync.zsh) と確認する側 (setup/migrate.zsh の health check) が
# 同じ定義を引くためにここへ寄せている (setup/lib/herdr.zsh・setup/lib/notion.zsh と同じ理由)。
#
# パスの出どころ: RTK 公式ドキュメント (docs/guide/getting-started/supported-agents.md) が
# `rtk init --agent hermes` の生成先を `~/.hermes/plugins/rtk-rewrite/` と明記している。
# 生成される実体は Hermes の Python plugin 規約に沿った薄いアダプタで、rewrite 判断自体は
# `rtk rewrite` (Rust 本体) に委譲される。

# rtk が Hermes へ登録するプラグイン名 (plugins.enabled に載る値)。
HERMES_RTK_PLUGIN_ID="rtk-rewrite"

# hermes::home <home_dir>  Hermes のユーザーデータディレクトリ
hermes::home() {
    print -r -- "${1}/.hermes"
}

# hermes::config <home_dir>  Hermes が動的に書き換える running config
hermes::config() {
    print -r -- "$(hermes::home "${1}")/config.yaml"
}

# hermes::is_installed <home_dir>
#   その PC で Hermes が実際に動いているとみなせるなら 0。
#   Hermes は dotfiles の宣言対象ではない (homebrew.nix にも無い) ため、
#   「入っていない PC」は正常な状態として扱う。導入する側も確認する側も同じ判定を使う。
#
#   判定材料に ~/.hermes ディレクトリの有無は使えない。Tier 1 の setup/link.zsh が
#   ~/.hermes/SOUL.md を張る時点でこのディレクトリを作るため、Hermes が入っていない PC でも
#   必ず存在してしまう。Hermes 自身が作る running config (config.yaml) の有無を見る
#   (AGENTS.md「Hermes Agent 設定」: config.yaml は Hermes が動的に書き換えるので
#   symlink・追跡しない = リポジトリ側からは決して作られない)。
hermes::is_installed() {
    [[ -f "$(hermes::config "${1}")" ]]
}

# hermes::rtk_plugin_dir <home_dir>  rtk が生成する Hermes plugin の配置先
hermes::rtk_plugin_dir() {
    print -r -- "$(hermes::home "${1}")/plugins/${HERMES_RTK_PLUGIN_ID}"
}
