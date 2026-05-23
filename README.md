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

`.dotfiles-role` の末尾の値で以下のどちらかを宣言する。

- `default` — full app set
- `sub-1` — reduced profile (default-only パッケージを除外)

```terminal
cp ~/.dotfiles/.dotfiles-role.example ~/.dotfiles/.dotfiles-role
```

`.example` の初期値は `default`。`sub-1` で運用する場合は `.dotfiles-role` を開いて末尾を `sub-1` に書き換える。

5. Install Nix and apply
```terminal
zsh ~/.dotfiles/nix/scripts/install-nix.zsh
cd ~/.dotfiles/nix && sudo USER=$USER HOME=$HOME nix run nix-darwin -- switch --flake .#default --impure
```

See [`nix/README.md`](nix/README.md) for details.
