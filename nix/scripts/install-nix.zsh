#!/bin/zsh
# Determinate Nix を macOS にインストールするための薄いラッパー。
#
# 役割:
#   1. 既に Nix がインストール済みなら skip して exit 0 (idempotent)
#   2. Full Disk Access (FDA) を事前検証し、未付与なら明確なエラーで停止
#   3. Determinate Nix の公式インストーラを非対話モードで起動
#
# 前提:
#   - macOS (Apple Silicon / Intel)
#   - Xcode Command Line Tools がインストール済み
#   - 実行元ターミナル (Terminal.app / iTerm2 等) に Full Disk Access が付与されている
#
# 使い方:
#   zsh ${HOME}/.dotfiles/nix/scripts/install-nix.zsh
#
# 終了コード:
#   0  成功 or 既存 Nix を検出して skip
#   1  Full Disk Access 未付与
#   2  Determinate Nix インストーラ失敗
#
# 関連:
#   - Linear: KISSA-32 (S12)
#   - 公式: https://github.com/DeterminateSystems/nix-installer
#   - nix-darwin との競合解消: nix/darwin.nix `nix.enable = false`

set -eu

# util.zsh の message 関数を共用する。Phase B で setup/ が削除された後は、
# 同等のメッセージ関数をローカル定義に置き換えること。
source "${HOME}/.dotfiles/setup/util.zsh"

# ---- 1. 既存 Nix の検出 ----------------------------------------------------

# Determinate / 公式インストーラのどちらも /nix/var/nix/daemon-socket を作るため、
# nix-daemon が常駐していなくてもこの socket の存在で多重インストールを防げる。
if [[ -S /nix/var/nix/daemon-socket/socket ]] || command -v nix >/dev/null 2>&1; then
    util::info "Nix is already installed. Skipping installation."
    util::info "  /nix exists:  $([[ -d /nix ]] && echo yes || echo no)"
    util::info "  nix in PATH:  $(command -v nix 2>/dev/null || echo not-found)"
    exit 0
fi

# ---- 2. Full Disk Access の事前チェック ------------------------------------

# macOS 15 では root でも /etc 配下への書き込みが TCC で拒否されるため、
# `sudo touch /etc/fstab` の成否が FDA 付与の最も信頼できるシグナルになる。
# Determinate / 公式インストーラのどちらも /etc 配下に書き込むため、これが落ちる
# とインストール途中で必ず失敗する。
util::info "Checking Full Disk Access (FDA) for the calling terminal..."
if ! sudo -n true 2>/dev/null; then
    util::warning "sudo will prompt for your password (required for FDA test)."
fi

if ! sudo touch /etc/fstab 2>/dev/null; then
    util::error "Full Disk Access is NOT granted to the current terminal."
    util::error ""
    util::error "Grant FDA from System Settings > Privacy & Security > Full Disk Access:"
    util::error "  1. Open System Settings.app"
    util::error "  2. Navigate to Privacy & Security > Full Disk Access"
    util::error "  3. Add and enable your terminal application (Terminal.app, iTerm.app, etc.)"
    util::error "  4. Quit the terminal completely and reopen it"
    util::error "  5. Re-run this script"
    exit 1
fi

util::info "Full Disk Access is granted."

# ---- 3. Determinate Nix インストーラ --------------------------------------

# Determinate Nix は nix-darwin の native Nix 管理 (nix.enable) と競合するため、
# nix-darwin 側で `nix.enable = false` を宣言している (nix/darwin.nix)。
# experimental-features (nix-command / flakes) は Determinate がデフォルト有効化済み。
util::info "Installing Determinate Nix..."

if ! curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix \
    | sh -s -- install --determinate --no-confirm; then
    util::error "Determinate Nix installer failed."
    util::error "See https://github.com/DeterminateSystems/nix-installer for troubleshooting."
    exit 2
fi

util::info "Determinate Nix installed successfully."
util::info ""
util::info "NEXT STEPS:"
util::info "  1. Restart your terminal (or run: source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh)"
util::info "  2. cd ${HOME}/.dotfiles/nix"
util::info "  3. nix build .#darwinConfigurations.default.system --no-link --impure  # 副作用なし closure 確認"
util::info "  4. nix run nix-darwin -- switch --flake .#default --impure  # 初回ブートストラップ + 実機適用"
