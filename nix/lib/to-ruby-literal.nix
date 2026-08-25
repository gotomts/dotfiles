# Nix の値を、Brewfile (Ruby として instance_eval される) に埋め込めるリテラルへ変換する。
#
# JSON は Ruby のリテラルとしても妥当なので、文字列・整数・配列の範囲なら toJSON の
# escape がそのまま使える (空白・引用符・改行・非 ASCII を含む名前でも壊れない)。
# "#" だけは Ruby の式展開 #{...} を招くため escape する。JSON 出力中の "#" は必ず
# 文字列リテラルの内側にしか現れないので、一律 escape して安全 ("\#" は Ruby では "#")。
#
# lib を取らないのは、テストが nixpkgs なしで `nix eval --file` から直接呼べるようにするため。
value: builtins.replaceStrings [ "#" ] [ "\\#" ] (builtins.toJSON value)
