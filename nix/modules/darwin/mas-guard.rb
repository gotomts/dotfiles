# frozen_string_literal: true
#
# 生成 Brewfile の末尾に連結される Mac App Store 導入ガード。
#
# 前提: 直前の prelude (homebrew.nix が生成) が次のローカル変数を定義していること。
#   mas_apps     — [[アプリ名, App Store ID, CFBundleIdentifier], ...]
#   mas_app_dirs — 走査対象ディレクトリの絶対パス配列 (不在なら無視される)
#
# 同じ CFBundleIdentifier のアプリが走査対象に既にあれば mas を呼ばない。判定は
# 「在るか無いか」だけで、バージョン比較・修復・削除・アップグレードはしない。
#
# Spotlight (mdfind/mdls) を使わないのは、索引が欠けた端末で「未導入」と誤判定し、
# 既存アプリへの再インストールを PackageKit が拒否して activation ごと落ちるため。
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

mas_apps.each do |name, app_id, bundle_id|
  next if installed_bundle_ids.include?(bundle_id)

  mas name, id: app_id
end
