# rtk overlay
# Phase A の S8 として、flake input から取得した rtk のソースを
# rustPlatform.buildRustPackage でビルドして pkgs.rtk として供給する。
#
# Source repository: https://github.com/rtk-ai/rtk (確認方法: brew info rtk)
# License: Apache-2.0 (homebrew formula および upstream リポジトリ LICENSE ファイルで確認)
# Current stable version: 0.38.0
#
# このファイル単独では機能しない。flake.nix の outputs で:
#
#   1. inputs に追加:
#      rtk-src = {
#        url   = "github:rtk-ai/rtk";
#        flake = false;
#      };
#
#   2. mkHost.nix またはホスト設定で nixpkgs に overlay として適用:
#      pkgs = import nixpkgs {
#        inherit system;
#        overlays = [ (import ./modules/overlays/rtk.nix { inherit inputs; }) ];
#      };
#      または nixpkgs.overlays を使う場合:
#      nixpkgs.overlays = [ (import ./modules/overlays/rtk.nix { inherit inputs; }) ];
#
# 上記 flake.nix 編集は親の integration commit で実施。
#
# Native deps: libc (Unix のみ、nixpkgs が自動提供)、
#              rusqlite は "bundled" feature で SQLite を内包するため追加 buildInputs 不要。
{ inputs }:

final: prev: {
  rtk = prev.rustPlatform.buildRustPackage {
    pname   = "rtk";
    # version: 通常は flake.lock で固定された commit の shortRev (8 桁) が入る。
    # "unknown" フォールバックは flake.lock 未生成または評価失敗時のみ使用される。
    # rtk のメジャーバージョンを示したい場合は inputs.rtk-src.rev からの動的取得を検討。
    version = inputs.rtk-src.shortRev or "unknown";
    src     = inputs.rtk-src;

    cargoLock = {
      lockFile = inputs.rtk-src + /Cargo.lock;
    };

    # libc は nixpkgs が stdenv 経由で自動提供されるため明示不要。
    # rusqlite は "bundled" feature で SQLite をソースからコンパイルするため
    # システムの libsqlite3 に依存しない。追加の buildInputs は不要。
    # nativeBuildInputs = with prev; [ pkg-config ];
    # buildInputs       = with prev; [ openssl ];

    meta = with prev.lib; {
      description = "CLI proxy to minimize LLM token consumption";
      homepage    = "https://github.com/rtk-ai/rtk";
      license     = licenses.asl20; # Apache-2.0
      mainProgram = "rtk";
      platforms   = platforms.unix;
    };
  };
}
