# 生成 Brewfile の末尾に連結される Mac App Store の install スキップ判定。
#
# 前提: 直前の prelude (homebrew.nix が生成) が次のローカル変数を定義していること。
#   mas_apps     — [[アプリ名, App Store ID, CFBundleIdentifier], ...]
#   mas_app_dirs — 走査対象ディレクトリの絶対パス配列 (不在なら無視される)
#
# 同じ CFBundleIdentifier のアプリが走査対象に既にあれば、その App Store ID を
# HOMEBREW_BUNDLE_MAS_SKIP に載せて install だけを飛ばす。判定は「在るか無いか」
# だけで、バージョン比較・修復・削除・アップグレードはしない。
#
# mas 行そのものを Brewfile から落とさないのは、`brew bundle cleanup` (default role の
# zap) が「Brewfile に載っている mas エントリ以外」を uninstall 候補にするため
# (Homebrew::Bundle::MacAppStore.cleanup_items)。1 本でも mas 行が残っている状態で
# 別のアプリの行を落とすと、そのアプリが `mas uninstall` される。
#
# 判定に Spotlight (mdfind/mdls) を使わないのは、mas の導入済み一覧 (`mas list`) が
# Spotlight の索引に依存しており、索引が欠けた端末で「未導入」と誤判定して再インス
# トールが走り、PackageKit が既存 app への上書きを拒否して activation ごと落ちた
# 実機事故があるため。
installed_bundle_ids = []

mas_app_dirs.each do |dir|
  next unless File.directory?(dir)

  # base: を使うのは、ディレクトリ側のパスを glob パターンとして解釈させないため。
  # 直下 (/Applications/Foo.app) と 1 階層下 (/Applications/Utilities/Foo.app) を見る。
  app_paths = (Dir.glob("*.app", base: dir) + Dir.glob("*/*.app", base: dir)).map do |rel|
    File.join(dir, rel)
  end

  app_paths.each do |app_path|
    info_plist = File.join(app_path, "Contents", "Info.plist")
    next unless File.file?(info_plist)

    # コマンドは配列で渡すのでシェルを経由しない (空白・引用符を含むパスでも安全)。
    # バイナリ plist も読めるよう plutil を使う。
    bundle_id = IO.popen(
      ["/usr/bin/plutil", "-extract", "CFBundleIdentifier", "raw", "-o", "-", info_plist],
      err: File::NULL
    ) { |io| io.read }.to_s.strip

    installed_bundle_ids << bundle_id unless bundle_id.empty?
  end
end

skip_ids = mas_apps.select do |(_name, _app_id, bundle_id)|
  installed_bundle_ids.include?(bundle_id)
end.map { |(_name, app_id, _bundle_id)| app_id.to_s }

# Homebrew::Bundle::Skipper は環境変数を空白区切りで読み、entry の name か id と
# 照合する。名前は空白を含み得る (例: "RunCat Neo") ので ID で指定する。
# 既存の値は上書きせずに足す (手で export して実行する場合を壊さないため)。
unless skip_ids.empty?
  ENV["HOMEBREW_BUNDLE_MAS_SKIP"] =
    (ENV["HOMEBREW_BUNDLE_MAS_SKIP"].to_s.split + skip_ids).uniq.join(" ")
end
