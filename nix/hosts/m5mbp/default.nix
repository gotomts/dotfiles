# このファイルは flake.nix の outputs から `mkHost` を呼ぶときのエントリ。
# 現在は darwin.nix と home.nix を順に組む形で運用するため、
# default.nix は薄い import 集約として置く。
{ inputs, hostname, username, ... }:

{
  imports = [
    ./darwin.nix
  ];
}
