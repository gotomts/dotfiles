{ config, ... }:

# Hermes Agent (gateway) 用 dotfiles を home-manager で配置する。
#
# Hermes の context file 探索は「最初に見つかった 1 種類だけを読む」方式で、
# `.hermes.md` → `AGENTS.md` (git root → cwd のチェーン) → `CLAUDE.md` →
# `.cursorrules` の順に評価される。チェーンは git root より上へ遡らないため、
# ホーム直下に置いたファイルは cwd がリポジトリへ移った瞬間に失効する。
# 一方 SOUL.md は HERMES_HOME 固定で cwd に依存せず必ず system prompt に入る。
# グローバル規範の注入口として SOUL.md を選んでいるのはこのため。
#
# 中身は claude/rules/ のフラグメントから生成する (aliase/build-agent-rules.zsh)。
# Hermes は `@AGENTS.md` 形式の import を展開しないので、フラット化した生成物が要る。
#
# mkOutOfStoreSymlink で working tree を直接指すため、フラグメント編集 →
# agent-rules-build だけで次のターンに反映される (darwin-rebuild switch 不要)。
#
# ~/.hermes/config.yaml は symlink しない。Hermes が running config として
# 動的に書き換える (channel_prompts / onboarding / telemetry 等) ため、
# ~/.claude.json や ~/.codex/config.toml と同じ理由で追跡対象外とする。
#
# SOUL.md 自体は Hermes 側では「不在」または「旧 install の空テンプレート」の
# ときだけ書き込まれ、カスタマイズ済みのファイルには触れられない。よって
# symlink を置いてもアプリに上書きされない。
let
  dotfiles = "${config.home.homeDirectory}/.dotfiles";
in
{
  home.file = {
    ".hermes/SOUL.md".source =
      config.lib.file.mkOutOfStoreSymlink "${dotfiles}/claude/hermes/SOUL.md";
  };
}
