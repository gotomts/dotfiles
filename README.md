# dotfiles

## Initialize Setup

1. Grant Full Disk Access to your terminal app
   (System Settings → Privacy & Security → Full Disk Access)

2. Install Xcode CLT
```terminal
xcode-select --install
```

3. Clone dotfiles
```terminal
git clone https://github.com/gotomts/dotfiles.git ~/.dotfiles
```

4. Declare the role for this Mac

以下のどちらかを `/etc/dotfiles-role` に宣言する (machine-wide 設定)。

- `default` — full app set
- `sub-1` — reduced profile (default-only パッケージを除外)

```terminal
echo default | sudo tee /etc/dotfiles-role   # default で運用する場合
echo sub-1   | sudo tee /etc/dotfiles-role   # sub-1 で運用する場合
```

ファイルが存在しない場合は `default` にフォールバックします。

5. Install Nix and apply (Homebrew パッケージ層)
```terminal
zsh ~/.dotfiles/nix/scripts/install-nix.zsh
cd ~/.dotfiles/nix && sudo USER=$USER nix --extra-experimental-features "nix-command flakes" \
  run nix-darwin -- switch --flake .#default --impure
```

`--extra-experimental-features` は、このリポジトリが `/etc/nix/nix.conf` を所有せず
nix-command / flakes の有効・無効をホスト任せにしているため必要。理由と他のコマンド例は
[`nix/README.md`](nix/README.md) の「前提」節を参照。

See [`nix/README.md`](nix/README.md) for details.

6. Place dotfiles symlinks (Tier 1) and run explicit setup scripts (Tier 2)
```terminal
zsh ~/.dotfiles/setup/link.zsh
zsh ~/.dotfiles/setup/languages.zsh
zsh ~/.dotfiles/setup/defaults.zsh
zsh ~/.dotfiles/setup/pam.zsh
zsh ~/.dotfiles/setup/claude-sync.zsh
zsh ~/.dotfiles/setup/codex-sync.zsh
```

新規マシンは home-manager 状態を持たないため `setup/cutover.zsh` は不要（既存 PC を
home-manager 込みの旧構成から移行する場合のみ使う）。詳細は [`setup/README.md`](setup/README.md)
を参照。
