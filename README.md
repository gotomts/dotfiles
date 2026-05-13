# dotfiles

## Initialize Setup

1. Grant Full Disk Access to your terminal app
   (System Settings → Privacy & Security → Full Disk Access)

2. Install Xcode CLT
```terminal
xcode-select --install
```

3. Install Nix and dotfiles
```terminal
git clone https://github.com/gotomts/dotfiles.git ~/.dotfiles
zsh ~/.dotfiles/nix/scripts/install-nix.zsh
cd ~/.dotfiles/nix && nix run nix-darwin -- switch --flake .#default --impure
```

See [`nix/README.md`](nix/README.md) for details.
