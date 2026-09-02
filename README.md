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

6. Apply dotfiles

実機で dotfiles を適用する唯一のエントリポイントは `setup/migrate.zsh`。各 step（symlink 配置・
cutover・PAM・言語ランタイム・macOS defaults・各種 sync）を定義された依存順に、冪等かつ
fail-closed で実行する。初回はまだ `~/.aliases` が無いのでスクリプトを直接呼ぶ。

```terminal
# 何が実行されるかを先に確認する（副作用なし）
zsh ~/.dotfiles/setup/migrate.zsh --dry-run

# 適用する（単一の root 起動で全 Phase が完結する）
sudo zsh ~/.dotfiles/setup/migrate.zsh --apply
```

新規マシンは home-manager 状態を持たないため cutover ステップは実質何も移行しない（既存 PC を
home-manager 込みの旧構成から移行する場合にだけ意味を持つ）。個別スクリプト
（`link.zsh`/`languages.zsh` 等）の直接実行はメンテナンス目的のみで、通常運用の手順ではない。
詳細は [`setup/README.md`](setup/README.md) を参照。

## Update

`git pull` で dotfiles を更新した後は、これ 1 コマンドで最新の宣言を適用する。

```terminal
sudo zsh ~/.dotfiles/setup/migrate.zsh --apply
```

pull 直後に開いているシェルの状態（読み込み済みの alias・関数・環境変数）に一切依存しないため、
これが標準の入口。何が実行されるか先に見たいときは `zsh ~/.dotfiles/setup/migrate.zsh --dry-run`
を使う。

`aliases` は同じ適用を起動する `dotfiles-apply` を定義しているが、その定義自体が `git pull` で
更新されるため、pull 直後の既存シェルではまだ読み込まれていない（未定義のことがある）。
以後のログインシェルで使える短縮形として扱い、pull 直後の適用は上の直接コマンドで行う。

`darwin-switch` は Homebrew パッケージ層（Nix/nix-darwin）だけを適用する別コマンドで、意味は
変わらない。
