# home-manager モジュール: corepack によるグローバル pnpm / yarn 供給
#
# 方針: グローバルに pnpm / yarn を使えるようにしつつ、プロジェクトの
# package.json `"packageManager": "pnpm@X.Y.Z"` 宣言を優先する (asdf / mise 相当)。
#
# 実装手段は nixpkgs の `pnpm` パッケージではなく corepack を使う。理由:
#   - nixpkgs の `pnpm` はスタンドアロンの固定バージョンで、package.json の
#     packageManager 宣言を一切見ない → 「プロジェクト宣言優先」の要件を満たせない。
#   - corepack は `pnpm` 実行時に最寄りの package.json の packageManager を読み、
#     宣言があればそのバージョンを自動 DL して使う。宣言が無ければ最新を使う。
#   - corepack は languages.nix の nodejs_24 に同梱済みのため追加パッケージは不要。
#
# shim (pnpm/pnpx/yarn/yarnpkg) は nix store の corepack dist への symlink。
# nodejs_24 が更新されると store path が変わり shim が stale 化するため、
# shim 生成は home.activation に置く (darwin-rebuild switch ごとに現在の node
# store path へ貼り直され、宣言的に追従する)。
#
# pnpm 本体 (packageManager で pin されたバージョン) は COREPACK_HOME 配下に
# 実行時 DL・キャッシュされる (mise / asdf と同じく初回はネットワークが必要)。
#
# 自動注入: pkgs / lib / config (... で受け取る)
{ config, lib, pkgs, ... }:

let
  corepackHome = "${config.home.homeDirectory}/.local/share/corepack";
  corepackBin = "${corepackHome}/bin";
in
{
  home.sessionVariables = {
    COREPACK_HOME = corepackHome;
    # 初回に pin バージョンを DL する際の対話プロンプトを抑止 (非対話シェル対策)。
    COREPACK_ENABLE_DOWNLOAD_PROMPT = "0";
  };

  # shim ディレクトリを PATH に追加。グローバルに pnpm / yarn が解決されるようにする。
  # devbox などプロジェクト固有の devshell が $PWD 配下の bin を PATH 先頭に差し込む
  # ケースでは、そちらが優先されるため共存可能。
  home.sessionPath = [ corepackBin ];

  # corepack shim を宣言的に生成する。
  # writeBoundary 後に実行し、$DRY_RUN_CMD で dry-run (darwin-rebuild build) 時は no-op。
  home.activation.enableCorepack = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    _enable_corepack() {
      set +e
      $DRY_RUN_CMD mkdir -p "${corepackBin}"
      # corepack enable は --install-directory が事前に存在している必要がある。
      $DRY_RUN_CMD ${pkgs.nodejs_24}/bin/corepack enable --install-directory "${corepackBin}" \
        && echo "[corepack.nix] corepack shims を ${corepackBin} に生成" \
        || echo "[corepack.nix] corepack enable 失敗"
    }
    _enable_corepack
  '';
}
