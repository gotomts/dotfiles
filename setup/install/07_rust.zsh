#!/bin/zsh
source ${HOME}/.dotfiles/setup/util.zsh

util::info 'install Rust toolchain...'

# Rust plugin for mise (uses rustup-init under the hood)
# stable channel = 最新の安定版を追従
mise install rust@stable
mise use --global rust@stable

# rustup 管理の追加コンポーネント
# - rust-analyzer: LSP サーバ (VS Code の rust-analyzer 拡張から利用)
# - rustfmt:       コードフォーマッタ
# - clippy:        リンタ (golangci-lint 相当)
mise reshim
rustup component add rust-analyzer rustfmt clippy

# cargo 経由で入れる開発支援ツール
cargo_installs=(
    cargo-nextest  # 高速テストランナー (出力が見やすい)
    cargo-watch    # ファイル変更時の自動再実行
)

for install in ${cargo_installs[@]}; do
    cargo install ${install}
done

mise reshim

util::info 'Rust toolchain ready.'
