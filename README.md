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

5. Install Nix and apply
```terminal
zsh ~/.dotfiles/nix/scripts/install-nix.zsh
cd ~/.dotfiles/nix && sudo USER=$USER nix run nix-darwin -- switch --flake .#default --impure
```

See [`nix/README.md`](nix/README.md) for details.
