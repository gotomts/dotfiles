# Tier 1（リアルタイム symlink）実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** dotfiles リポジトリの working tree を `$HOME` 配下へ symlink 配置する仕組み（Tier 1）を、
home-manager を使わない plain zsh script として新設する。一度実行すれば以後の repo 編集は
symlink 越しに即座に反映され、`darwin-rebuild switch` は不要になる。

**Architecture:** `setup/lib/util.zsh`（ログ・確認ヘルパー）+ `setup/lib/fs.zsh`（symlink 安全
プリミティブ）を土台に、`setup/link.zsh` が対応表を 1 行 1 対応で列挙して symlink を作成する。
alias 定義は root 直下 `aliases` ファイルへ集約し、`aliase/`（外部スクリプト置き場）は `scripts/`
へ改名する。git 設定は `config/git/config`／`config/git/ignore` を新設して symlink する。

**Tech Stack:** zsh（シバン `#!/bin/zsh`）、bats-core（既存 `nix/scripts/tests/*.bats` と同じ
テスト規約）。生成・テンプレート化は行わない（1 対応 = 1 行の明示列挙）。

**Spec:** `docs/superpowers/specs/2026-08-21-restore-script-management-inventory.md`
（特に 6 節「ハイブリッド案（D）詳細設計」、7 節「ルート alias SSOT 移行設計」— 本計画が実装する
確定事項はすべてこの spec の 2026-08-22 承認分に基づく）

## Global Constraints

- シバンは `#!/bin/zsh`、環境変数参照は `${VAR}` 形式、パス参照は `${HOME}`（`~` ではなく）
  — `AGENTS.md`「zsh スクリプト規約」
- 絶対パスで `/bin/unlink` `/usr/bin/readlink` を呼ぶ（Claude Code の bash tool 等、PATH に
  `/bin` を含まない非対話実行環境がある — `feedback_bash_tool_minimal_path_for_coreutils` 相当の教訓）
- 生成・抽象化を最小化する。1 対応 = 1 行で読める形にし、ループ・テンプレート化は避ける
  （ユーザー確定要件）
- 本計画は **Tier 1 のみ**を対象とする。Homebrew／言語ランタイム(mise)／macOS defaults／IME／
  フォント／PAM／Claude plugin sync／MCP servers merge／Codex config seed は Tier 2 であり、
  本計画のスコープ外（別途計画を起こす）
- **本計画の実行では以下を一切行わない**: 実機 (`$HOME` が実際のログインユーザーのホーム) への適用、
  `nix/` 配下の既存定義の削除・変更、パッケージのインストール・削除、`git commit`/`push`/PR 作成。
  全ステップはこのリポジトリの working tree 内のファイル作成・bats テスト実行のみで完結する

---

## Task 1: `setup/lib/util.zsh`（ログ・確認ヘルパー）

**Files:**
- Create: `setup/lib/util.zsh`
- Test: `setup/tests/util.bats`

**Interfaces:**
- Produces: `util::info(msg)` `util::warning(msg)` `util::error(msg)` `util::action(msg)`
  `util::skip(msg)` `util::confirm(msg)`（戻り値 0=yes / 4=no、`FORCE=1` で常に yes）。
  Task 2 以降がこれらを `source` して使う。

- [ ] **Step 1: 失敗するテストを書く**

```bash
#!/usr/bin/env bats
# setup/tests/util.bats

SETUP_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"

@test "zsh -n syntax check passes" {
    run zsh -n "${SETUP_DIR}/lib/util.zsh"
    [ "${status}" -eq 0 ]
}

@test "util::info prints the message" {
    run zsh -c "source '${SETUP_DIR}/lib/util.zsh'; util::info 'hello'"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"hello"* ]]
}

@test "util::confirm returns 0 (yes) when FORCE=1" {
    run zsh -c "source '${SETUP_DIR}/lib/util.zsh'; FORCE=1 util::confirm 'proceed?'"
    [ "${status}" -eq 0 ]
}

@test "util::confirm returns 4 (no) on empty stdin without FORCE" {
    run zsh -c "source '${SETUP_DIR}/lib/util.zsh'; echo '' | util::confirm 'proceed?'"
    [ "${status}" -eq 4 ]
}
```

- [ ] **Step 2: テストを実行し失敗を確認する**

Run: `bats setup/tests/util.bats`
Expected: FAIL（`setup/lib/util.zsh` が存在しないため `source` エラー）

- [ ] **Step 3: 実装を書く**

```zsh
#!/bin/zsh
# setup/lib/util.zsh
#
# ログ・確認ヘルパー。旧 setup/util.zsh（Nix 移行前）の役割を復元し、
# nix/scripts/migrate-symlinks.zsh の色分けログ（info/warning/action/skip）命名を踏襲する。

util::info()    { echo "\e[32m[setup] ${1}\e[m" }
util::warning() { echo "\e[33m[setup] ${1}\e[m" }
util::error()   { echo "\e[31m[setup] ${1}\e[m" >&2 }
util::action()  { echo "\e[36m[setup] ${1}\e[m" }
util::skip()    { echo "\e[90m[setup] SKIP: ${1}\e[m" }

# util::confirm <message>
#   FORCE=1 なら常に yes 扱い。それ以外は y/N プロンプト。
#   戻り値 0 = yes、4 = no（旧 setup/util.zsh の終了コードを踏襲）
util::confirm() {
    local message="${1}"

    if [[ "${FORCE:-0}" == "1" ]]; then
        return 0
    fi

    echo "${message} (y/N)"
    read confirmation
    if [[ "${confirmation}" == "y" || "${confirmation}" == "Y" ]]; then
        return 0
    fi

    return 4
}
```

- [ ] **Step 4: テストを実行し成功を確認する**

Run: `bats setup/tests/util.bats`
Expected: PASS（4 テスト全て）

- [ ] **Step 5: commit しない**

本計画は commit/push を行わない（Global Constraints 参照）。working tree に変更を残す。

---

## Task 2: `setup/lib/fs.zsh`（symlink 安全プリミティブ）

**Files:**
- Create: `setup/lib/fs.zsh`
- Test: `setup/tests/fs.bats`

**Interfaces:**
- Consumes: `util::info` `util::warning` `util::error` `util::skip` `util::action`（Task 1）
- Produces: `fs::ensure_dir(path)` `fs::link_file(target, link_path)` `fs::ensure_realfile(path)`。
  Task 7（`setup/link.zsh`）がこれらを呼ぶ。

- [ ] **Step 1: 失敗するテストを書く**

```bash
#!/usr/bin/env bats
# setup/tests/fs.bats

SETUP_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"

_zsh_fs() {
    zsh -c "source '${SETUP_DIR}/lib/util.zsh'; source '${SETUP_DIR}/lib/fs.zsh'; ${1}"
}

setup() {
    TMP="${BATS_TEST_TMPDIR}"
    echo "source content" > "${TMP}/source.txt"
}

@test "zsh -n syntax check passes" {
    run zsh -n "${SETUP_DIR}/lib/fs.zsh"
    [ "${status}" -eq 0 ]
}

@test "fs::link_file creates a symlink to target" {
    run _zsh_fs "fs::link_file '${TMP}/source.txt' '${TMP}/home/.target'"
    [ "${status}" -eq 0 ]
    [ -L "${TMP}/home/.target" ]
    [ "$(readlink "${TMP}/home/.target")" = "${TMP}/source.txt" ]
}

@test "fs::link_file is idempotent on second run" {
    _zsh_fs "fs::link_file '${TMP}/source.txt' '${TMP}/home/.target'"
    run _zsh_fs "fs::link_file '${TMP}/source.txt' '${TMP}/home/.target'"
    [ "${status}" -eq 0 ]
    [ -L "${TMP}/home/.target" ]
}

@test "fs::link_file backs up an existing real file instead of clobbering it" {
    mkdir -p "${TMP}/home"
    echo "existing real content" > "${TMP}/home/.target"
    run _zsh_fs "fs::link_file '${TMP}/source.txt' '${TMP}/home/.target'"
    [ "${status}" -eq 0 ]
    [ -L "${TMP}/home/.target" ]
    [ -f "${TMP}/home/.target.before-setup" ]
    [ "$(cat "${TMP}/home/.target.before-setup")" = "existing real content" ]
}

@test "fs::link_file re-links when the existing symlink points elsewhere" {
    mkdir -p "${TMP}/home"
    echo "other content" > "${TMP}/other.txt"
    ln -s "${TMP}/other.txt" "${TMP}/home/.target"
    run _zsh_fs "fs::link_file '${TMP}/source.txt' '${TMP}/home/.target'"
    [ "${status}" -eq 0 ]
    [ "$(readlink "${TMP}/home/.target")" = "${TMP}/source.txt" ]
}

@test "fs::link_file fails clearly when target does not exist" {
    run _zsh_fs "fs::link_file '${TMP}/does-not-exist.txt' '${TMP}/home/.target'"
    [ "${status}" -eq 1 ]
    [ ! -e "${TMP}/home/.target" ]
}

@test "fs::ensure_realfile creates an empty real file when absent" {
    run _zsh_fs "fs::ensure_realfile '${TMP}/home/.gitconfig'"
    [ "${status}" -eq 0 ]
    [ -f "${TMP}/home/.gitconfig" ]
    [ ! -L "${TMP}/home/.gitconfig" ]
}

@test "fs::ensure_realfile does not overwrite an existing real file" {
    mkdir -p "${TMP}/home"
    echo "pc-local value" > "${TMP}/home/.gitconfig"
    run _zsh_fs "fs::ensure_realfile '${TMP}/home/.gitconfig'"
    [ "${status}" -eq 0 ]
    [ "$(cat "${TMP}/home/.gitconfig")" = "pc-local value" ]
}

@test "fs::ensure_realfile converts an existing symlink into a real file" {
    mkdir -p "${TMP}/home"
    ln -s "${TMP}/source.txt" "${TMP}/home/.gitconfig"
    run _zsh_fs "fs::ensure_realfile '${TMP}/home/.gitconfig'"
    [ "${status}" -eq 0 ]
    [ ! -L "${TMP}/home/.gitconfig" ]
    [ -f "${TMP}/home/.gitconfig" ]
}
```

- [ ] **Step 2: テストを実行し失敗を確認する**

Run: `bats setup/tests/fs.bats`
Expected: FAIL（`setup/lib/fs.zsh` が存在しない）

- [ ] **Step 3: 実装を書く**

```zsh
#!/bin/zsh
# setup/lib/fs.zsh
#
# symlink 配置の安全プリミティブ。「既存の実体ファイル/ディレクトリを黙って上書きしない」ことを
# 最優先する。呼び出し規約: 各関数は ${HOME} 等の環境変数を直接読まず、引数で受け取る。
# lib/util.zsh（util::info 等）が事前に source 済みであることを前提とする。
#
# 絶対パスで /bin/unlink 等を呼ぶ理由: 一部の非対話実行環境（Claude Code の bash tool 等）は
# PATH に /bin を含まないことがあり、素の `unlink` が command not found になる場合がある。

# fs::ensure_dir <path>
#   ディレクトリが無ければ作成する（mkdir -p の薄いラッパ）
fs::ensure_dir() {
    local dir="${1}"
    [[ -d "${dir}" ]] || mkdir -p "${dir}"
}

# fs::link_file <target> <link_path>
#   ${link_path} を ${target} への symlink にする。
#   - 既に ${target} を指す symlink → 何もしない（skip）
#   - 別の場所を指す symlink（nix store 経由の旧 symlink 等）→ unlink して張り直す
#   - 実体ファイル/ディレクトリが既にある → ${link_path}.before-setup に退避してから symlink 作成
#     （home-manager の backupFileExtension = "before-nix" と同じ思想の安全策）
#   - 親ディレクトリが無ければ作成する
fs::link_file() {
    local target="${1}"
    local link_path="${2}"

    if [[ ! -e "${target}" ]]; then
        util::error "リンク元が存在しません: ${target}"
        return 1
    fi

    fs::ensure_dir "${link_path:h}"

    if [[ -L "${link_path}" ]]; then
        local current_target
        current_target="$(/usr/bin/readlink "${link_path}")"
        if [[ "${current_target}" == "${target}" ]]; then
            util::skip "${link_path} は既に ${target} を指しています"
            return 0
        fi
        util::action "symlink 張り替え: ${link_path} (${current_target} -> ${target})"
        /bin/unlink "${link_path}"
    elif [[ -e "${link_path}" ]]; then
        local backup="${link_path}.before-setup"
        util::warning "${link_path} は既に実体があります。${backup} に退避します"
        /bin/mv "${link_path}" "${backup}"
    fi

    ln -sfv "${target}" "${link_path}"
}

# fs::ensure_realfile <path>
#   ${path} を「symlink ではない書き込み可能な実体ファイル」にする。
#   3rd party ツール（coderabbit 等）が ~/.gitconfig に書き込む場合や、Claude Code の
#   .i-have-adhd-always マーカーのように、dotfiles リポジトリで追跡してはいけない値/状態を
#   安全に置くための保護策。
#   - symlink が既にある → unlink してから空の実体ファイルを作る（中身は復元しない。
#     PC 固有の値は各マシンでツールが再生成する前提）
#   - 実体ファイルが既にある → 何もしない（中身を上書きしない）
#   - 何もない → touch で空ファイルを作る
fs::ensure_realfile() {
    # 変数名は `path` を避ける。zsh は `path` を $PATH と束縛された特殊配列として扱うため、
    # local でスカラーを代入すると同一スコープ内でコマンド解決 (mkdir/touch 等) が壊れる。
    local realfile_path="${1}"

    fs::ensure_dir "${realfile_path:h}"

    if [[ -L "${realfile_path}" ]]; then
        util::warning "${realfile_path} は symlink です。unlink して実体ファイルに変換します"
        /bin/unlink "${realfile_path}"
    fi

    if [[ -e "${realfile_path}" ]]; then
        util::skip "${realfile_path} は既に実体ファイルです（中身は変更しません）"
        return 0
    fi

    touch "${realfile_path}"
    util::info "空の実体ファイルを作成しました: ${realfile_path}"
}
```

- [ ] **Step 4: テストを実行し成功を確認する**

Run: `bats setup/tests/fs.bats`
Expected: PASS（9 テスト全て）

> **実装時の発見（2026-08-22）**: 当初 `local path="${1}"` としていたが、zsh は `path` を
> `$PATH` と束縛された特殊配列として扱うため、同一スコープ内で `mkdir`/`touch` の
> コマンド解決が壊れた（`command not found`）。`realfile_path` に変更して解消。

- [ ] **Step 5: commit しない**（Global Constraints 参照）

---

## Task 3: root `aliases` ファイル新設 ＋ `aliase/` → `scripts/` リネーム

**Files:**
- Create: `aliases`（root 直下）
- Create: `scripts/build-agent-rules.zsh`（`aliase/build-agent-rules.zsh` から `git mv`）
- Create: `scripts/claude-board.zsh`（`aliase/claude-board.zsh` から `git mv`）
- Create: `scripts/get-gke-credentials.sh`（`aliase/get-gke-credentials.sh` から `git mv`）
- Delete: `aliase/`（3 ファイル移動後、ディレクトリが空になり自然消滅）
- Test: `setup/tests/aliases.bats`

**Interfaces:**
- Produces: `aliases`（Task 7 が `${DOTFILES_ROOT}/aliases` → `${HOME}/.aliases` として symlink
  する）、`scripts/*.zsh`（Task 7 が `${HOME}/.scripts/*` として symlink する）

- [ ] **Step 1: 失敗するテストを書く**

```bash
#!/usr/bin/env bats
# setup/tests/aliases.bats

REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"

@test "zsh -n syntax check passes for aliases" {
    run zsh -n "${REPO_ROOT}/aliases"
    [ "${status}" -eq 0 ]
}

@test "aliase/ directory no longer exists" {
    [ ! -d "${REPO_ROOT}/aliase" ]
}

@test "scripts/ contains all three helper scripts" {
    [ -f "${REPO_ROOT}/scripts/build-agent-rules.zsh" ]
    [ -f "${REPO_ROOT}/scripts/claude-board.zsh" ]
    [ -f "${REPO_ROOT}/scripts/get-gke-credentials.sh" ]
}

@test "aliases references .scripts (not .aliase) paths" {
    run grep -c '\.scripts/' "${REPO_ROOT}/aliases"
    [ "${status}" -eq 0 ]
    run grep -c '\.aliase/' "${REPO_ROOT}/aliases"
    [ "${status}" -eq 1 ]
}
```

- [ ] **Step 2: テストを実行し失敗を確認する**

Run: `bats setup/tests/aliases.bats`
Expected: FAIL（`aliases` ファイル・`scripts/` ディレクトリとも未作成）

- [ ] **Step 3: 実装する**

```bash
git mv aliase/build-agent-rules.zsh scripts/build-agent-rules.zsh
git mv aliase/claude-board.zsh scripts/claude-board.zsh
git mv aliase/get-gke-credentials.sh scripts/get-gke-credentials.sh
rmdir aliase  # git mv はファイルのみ移動し空ディレクトリを残すため明示的に削除する
```

`aliases`（root 直下、新規作成）:

```zsh
# alias 定義 SSOT — root 直下に配置し ~/.aliases として symlink する（setup/link.zsh）。
# 由来: 旧 nix/modules/home/zsh.nix の shellAliases（Nix 移行前に廃止）+ initContent 内の
# alias -g / tn() 関数。Nix の attrset から zsh 構文への 1:1 変換であり、ロジック変更はしていない。

# general
alias history='history 1'
alias reload='exec $SHELL -l'
alias datetime="date '+%Y%m%d%T' | tr -d ':'"

# tmux
alias tls='tmux ls'              # セッション一覧
alias ta='tmux attach -t'        # ta <name> で接続
alias tad='tmux attach -d -t'    # 他クライアントを切って接続（Mac で全画面再開時）
alias trn='tmux rename-session'  # trn <new> で現セッション rename / trn -t <old> <new> で指定セッション rename

# git
alias gp='git push origin HEAD'
alias gch="git branch --all | tr -d '* ' | grep -v -e '->' | fzf | sed -e 's+remotes/[^/]*/++g' | xargs git checkout"
alias gchb='git checkout -b $1'
alias grsh='git reset --soft HEAD^'
alias gbclear="git branch --merged|egrep -v '\*|develop|main|master'|xargs git branch -d; git fetch -p"

# fzf
alias repo='ghq list -p | fzf'
alias repoc='cd "$(repo)"'

# gcloud
alias gcal='gcloud auth login'
alias gcadl='gcloud auth application-default login'
alias gcpa='gcloud config configurations activate $(gcloud config configurations list | fzf | awk "{print \$1}")'
alias gcps='gcloud config set project $(gcloud projects list | fzf | awk "{print \$1}")'
alias gcgc='bash $HOME/.scripts/get-gke-credentials.sh'

# vscode
alias codeo='code $(repo)'

# docker
alias dcu='docker compose up -d $@'
alias dcn='docker compose down $@'

# nix-darwin — Homebrew（role 別 zap/none）適用のみ担当（Tier 2）。CLAUDE.md「主要コマンド」と
# 同等。USER=$USER は sudo の env_reset 回避、--impure は username 動的解決のため必須
alias darwin-switch='sudo USER=$USER darwin-rebuild switch --flake $HOME/.dotfiles/nix#default --impure'

# claude.ai のチャット / Code を独立 Chrome ウィンドウで一括起動しグリッド整列する
alias claude-board='zsh $HOME/.scripts/claude-board.zsh'

# claude/rules/ のフラグメントから claude/AGENTS.md と claude/hermes/SOUL.md を生成する
alias agent-rules-build='zsh $HOME/.scripts/build-agent-rules.zsh'

# kubectl グローバルエイリアス（alias -g は zsh 構文上ここにまとめる）
alias -g KP='$(kubectl get pods | fzf | awk "{print \$1}")'
alias -g KD='$(kubectl get deploy | fzf | awk "{print \$1}")'
alias -g KS='$(kubectl get svc | fzf | awk "{print \$1}")'
alias -g KI='$(kubectl get ing | fzf | awk "{print \$1}")'
alias -g KJ='$(kubectl get job | fzf | awk "{print \$1}")'
alias -g KA='$(kubectl get all | awk "! /NAME/" | fzf | awk "{print \$1}")'
# kubectle 系は KP/KA グローバルエイリアスを参照するため、展開順を保証するため直後に定義
alias kubectle='kubectl exec -it KP $@'
alias kubectll='kubectl stern $(kubectl get deploy | fzf | awk "{print \$1}")'
alias kubectlo='kubectl get KA -o yaml'

# tmux — カレント dir 名でセッション作成/接続、引数で枝番
# 例: ~/dotfiles で `tn`     → セッション "dotfiles"
#     ~/dotfiles で `tn dev` → セッション "dotfiles-dev"
tn() {
  local name="$(basename "$PWD")${1:+-$1}"
  tmux new -A -s "$name"
}
```

- [ ] **Step 4: テストを実行し成功を確認する**

Run: `bats setup/tests/aliases.bats`
Expected: PASS（4 テスト全て）

- [ ] **Step 5: commit しない**（Global Constraints 参照）

---

## Task 4: `zshrc` 書き換え

**Files:**
- Modify: `zshrc`（既存の陳腐化した内容を、現行 `nix/modules/home/zsh.nix` の挙動に合わせて全面書き換え）
- Test: `setup/tests/zshrc.bats`

**Interfaces:**
- Consumes: `aliases`（Task 3、`~/.aliases` として source する前提）
- Produces: なし（末端ファイル）

**設計判断（spec 6.2 節に基づく）**:
- direnv hook は含めない（廃止確定）
- mise 有効化（`eval "$(mise activate zsh)"`）は `type mise &>/dev/null` ガード付きで含める
  （言語ランタイムの mise 移行が確定しているため。Tier 2 の `setup/languages.zsh` が無くても無害）
- `darwin-switch` alias は維持（Homebrew は nix-darwin に残るため switch 自体は必要）
- `alias -g` ブロックと `tn()` は `aliases` ファイル側に移したため zshrc からは削除

- [ ] **Step 1: 失敗するテストを書く**

```bash
#!/usr/bin/env bats
# setup/tests/zshrc.bats

REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"

@test "zsh -n syntax check passes for zshrc" {
    run zsh -n "${REPO_ROOT}/zshrc"
    [ "${status}" -eq 0 ]
}

@test "zshrc sources ~/.aliases" {
    run grep -c '\.aliases' "${REPO_ROOT}/zshrc"
    [ "${status}" -eq 0 ]
}

@test "zshrc does not reference direnv" {
    run grep -c 'direnv' "${REPO_ROOT}/zshrc"
    [ "${status}" -eq 1 ]
}

@test "zshrc guards mise activation" {
    run grep -c 'type mise' "${REPO_ROOT}/zshrc"
    [ "${status}" -eq 0 ]
}
```

- [ ] **Step 2: テストを実行し失敗を確認する**

Run: `bats setup/tests/zshrc.bats`
Expected: FAIL（現行 `zshrc` は陳腐化した内容で `.aliases` も `mise` ガードも含まない）

- [ ] **Step 3: 実装する**

`zshrc`（全文置換）:

```zsh
# Oh My Zsh
export ZSH="$HOME/.oh-my-zsh"

ZSH_THEME=""  # starship が代替

plugins=(
  git
  kubectl
  terraform
  gcloud
  zsh-autosuggestions
)

source $ZSH/oh-my-zsh.sh

# alias 定義 SSOT（root 直下 aliases ファイルへの symlink、setup/link.zsh が作成）
[[ -f "${HOME}/.aliases" ]] && source "${HOME}/.aliases"

# Homebrew（Apple Silicon）を PATH と env に注入
if [ -x /opt/homebrew/bin/brew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# gcloud path — gcloud-cli（新名）と google-cloud-sdk（旧名）両対応
for _gcloud_inc in \
    '/opt/homebrew/Caskroom/gcloud-cli/latest/google-cloud-sdk/path.zsh.inc' \
    '/opt/homebrew/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/path.zsh.inc'; do
    if [[ -f "${_gcloud_inc}" ]]; then source "${_gcloud_inc}"; break; fi
done
unset _gcloud_inc

# worktrunk shell integration
if command -v wt >/dev/null 2>&1; then eval "$(command wt config shell init zsh)"; fi

# fzf — カスタム履歴ウィジェット（functions/fzf-history を使用）
autoload fzf-history
zle -N fzf-history
bindkey '^r' fzf-history

# stern completion
if [ ${commands[stern]} ]; then
  source <(stern --completion=zsh)
fi

# bison
export PATH="/opt/homebrew/opt/bison/bin:$PATH"

# pipx local bin
export PATH="$PATH:$HOME/.local/bin"

# dart-cli completion
[[ -f "$HOME/.dart-cli-completion/zsh-config.zsh" ]] && . "$HOME/.dart-cli-completion/zsh-config.zsh" || true

# mise（interactive hook）— 言語ランタイムは mise 管理に移行（Tier 2。setup/languages.zsh は別計画）
if type mise &>/dev/null; then
  eval "$(mise activate zsh)"
fi

# starship prompt
eval "$(starship init zsh)"

# firebase / pub-cache
export PATH="$PATH:$HOME/.pub-cache/bin"
```

- [ ] **Step 4: テストを実行し成功を確認する**

Run: `bats setup/tests/zshrc.bats`
Expected: PASS（4 テスト全て）

- [ ] **Step 5: commit しない**（Global Constraints 参照）

---

## Task 5: `zshenv` 書き換え

**Files:**
- Modify: `zshenv`
- Test: `setup/tests/zshenv.bats`

**設計判断**:
- corepack 用の env（`COREPACK_HOME` 等）と PATH 追加を含める（維持確定。Tier 2 の
  `corepack enable` 実行スクリプトは無くても、この env 定義自体は無害）
- mise shims 有効化（`eval "$(mise activate --shims)"`）を `type mise` ガード付きで含める

- [ ] **Step 1: 失敗するテストを書く**

```bash
#!/usr/bin/env bats
# setup/tests/zshenv.bats

REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"

@test "zsh -n syntax check passes for zshenv" {
    run zsh -n "${REPO_ROOT}/zshenv"
    [ "${status}" -eq 0 ]
}

@test "zshenv exports COREPACK_HOME" {
    run grep -c 'COREPACK_HOME' "${REPO_ROOT}/zshenv"
    [ "${status}" -eq 0 ]
}

@test "zshenv guards mise shims activation" {
    run grep -c 'mise activate --shims' "${REPO_ROOT}/zshenv"
    [ "${status}" -eq 0 ]
}
```

- [ ] **Step 2: テストを実行し失敗を確認する**

Run: `bats setup/tests/zshenv.bats`
Expected: FAIL（現行 `zshenv` に `COREPACK_HOME` の記述なし）

- [ ] **Step 3: 実装する**

`zshenv`（全文置換）:

```zsh
# general settings — .functions を fpath に追加
export FPATH=${HOME}/.functions:${FPATH}

# pipx（avoid space in default macOS path）
export PIPX_HOME="${HOME}/.local/pipx"
export PIPX_BIN_DIR="${HOME}/.local/bin"

# fzf
export FZF_DEFAULT_COMMAND='rg --files --hidden --glob "!.git"'
export FZF_DEFAULT_OPTS='--height 40% --reverse --border'

# gcloud
export USE_GKE_GCLOUD_AUTH_PLUGIN=True

# golang
export GOPATH=${HOME}/go
export PATH=${GOPATH}/bin:${PATH}

# corepack（pnpm/yarn グローバル供給。mise 導入の node に対して corepack enable を実行する
# Tier 2 script は別計画。ここでは env/PATH のみ用意しておく — 未 enable でも無害）
export COREPACK_HOME="${HOME}/.local/share/corepack"
export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
export PATH="${COREPACK_HOME}/bin:${PATH}"

# mise（shims — non-interactive シェル向け）
if type mise &>/dev/null; then
  eval "$(mise activate --shims)"
fi

# custom local override
if [[ -f ${HOME}/.zshenv.local ]]; then
  source ${HOME}/.zshenv.local
fi
```

- [ ] **Step 4: テストを実行し成功を確認する**

Run: `bats setup/tests/zshenv.bats`
Expected: PASS（3 テスト全て）

- [ ] **Step 5: commit しない**（Global Constraints 参照）

---

## Task 6: `config/git/config` ＋ `config/git/ignore` 新設

**Files:**
- Create: `config/git/config`
- Create: `config/git/ignore`
- Test: `setup/tests/git-config.bats`

**Interfaces:**
- Produces: Task 7 が `${DOTFILES_ROOT}/config/git/config` → `${HOME}/.config/git/config`、
  `${DOTFILES_ROOT}/config/git/ignore` → `${HOME}/.config/git/ignore` として symlink する

現行 `nix/modules/home/git.nix` の `programs.git.settings`／`programs.git.ignores` の内容を、
Nix の attrset から git の ini 構文へ 1:1 変換したもの（ロジック変更なし）。

- [ ] **Step 1: 失敗するテストを書く**

```bash
#!/usr/bin/env bats
# setup/tests/git-config.bats

REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"

@test "config/git/config is valid git config syntax" {
    run git config --file "${REPO_ROOT}/config/git/config" --list
    [ "${status}" -eq 0 ]
}

@test "config/git/config sets user.email" {
    run git config --file "${REPO_ROOT}/config/git/config" user.email
    [ "${status}" -eq 0 ]
    [ "${output}" = "mh.goto.web@gmail.com" ]
}

@test "config/git/config sets commit.template to ~/.gitmessage" {
    run git config --file "${REPO_ROOT}/config/git/config" commit.template
    [ "${status}" -eq 0 ]
    [ "${output}" = "~/.gitmessage" ]
}

@test "config/git/ignore contains .serena/" {
    run grep -c '^\.serena/$' "${REPO_ROOT}/config/git/ignore"
    [ "${status}" -eq 0 ]
}
```

- [ ] **Step 2: テストを実行し失敗を確認する**

Run: `bats setup/tests/git-config.bats`
Expected: FAIL（`config/git/config` `config/git/ignore` とも未作成）

- [ ] **Step 3: 実装する**

`config/git/config`（新規）:

```ini
[user]
	name = gotomts
	email = mh.goto.web@gmail.com
[core]
	ignorecase = false
	excludesFile = ~/.config/git/ignore
[ghq]
	root = ~/.dotfiles
	root = ~/ghq
[filter "lfs"]
	clean = git-lfs clean -- %f
	smudge = git-lfs smudge -- %f
	process = git-lfs filter-process
	required = true
[rerere]
	enabled = true
[pull]
	autostash = true
[rebase]
	autoStash = true
[commit]
	template = ~/.gitmessage
[alias]
	graph = log --graph --date-order -C -M --pretty=format:\"<%h> %ad [%an] %Cgreen%d%Creset %s\" --all --date=short
```

`config/git/ignore`（新規）:

```
.DS_Store
.claude/settings.local.json
.serena/
```

- [ ] **Step 4: テストを実行し成功を確認する**

Run: `bats setup/tests/git-config.bats`
Expected: PASS（4 テスト全て）

- [ ] **Step 5: commit しない**（Global Constraints 参照）

---

## Task 7: `setup/link.zsh`（Tier 1 本体）

**Files:**
- Create: `setup/link.zsh`
- Test: `setup/tests/link.bats`

**Interfaces:**
- Consumes: `util::info` 等（Task 1）、`fs::link_file` `fs::ensure_realfile`（Task 2）、
  `aliases`（Task 3）、`zshrc` `zshenv`（Task 4・5）、`config/git/config` `config/git/ignore`
  （Task 6）、既存の `gitmessage` `gitignore_global` `ssh/config` `functions/fzf-history`
  `grip/settings.py` `config/{starship,yazi,zed,ghostty,cmux}/*` `claude/{settings.json,
  CLAUDE.md,AGENTS.md,skills,hooks/one-question-per-turn.py,hermes/SOUL.md}`
  （全てリポジトリに現存することを前提。存在しなければ `fs::link_file` がエラーで停止する）
- Produces: `$HOME` 配下の symlink 一式（実行対象は本タスクでは実機ではなく bats のサンドボックス
  `HOME` のみ）

- [ ] **Step 1: 失敗するテストを書く**

```bash
#!/usr/bin/env bats
# setup/tests/link.bats

SETUP_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"

@test "zsh -n syntax check passes" {
    run zsh -n "${SETUP_DIR}/link.zsh"
    [ "${status}" -eq 0 ]
}

@test "link.zsh creates all Tier 1 symlinks in a sandboxed HOME" {
    local tmp_home="${BATS_TEST_TMPDIR}/home"
    mkdir -p "${tmp_home}"
    HOME="${tmp_home}" run zsh "${SETUP_DIR}/link.zsh"
    [ "${status}" -eq 0 ]

    [ -L "${tmp_home}/.zshrc" ]
    [ -L "${tmp_home}/.zshenv" ]
    [ -L "${tmp_home}/.aliases" ]
    [ -L "${tmp_home}/.gitmessage" ]
    [ -L "${tmp_home}/.gitignore_global" ]
    [ -L "${tmp_home}/.config/git/config" ]
    [ -L "${tmp_home}/.config/git/ignore" ]
    [ -f "${tmp_home}/.gitconfig" ]
    [ ! -L "${tmp_home}/.gitconfig" ]
    [ -L "${tmp_home}/.ssh/config" ]
    [ -L "${tmp_home}/.functions/fzf-history" ]
    [ -L "${tmp_home}/.scripts/get-gke-credentials.sh" ]
    [ -L "${tmp_home}/.scripts/claude-board.zsh" ]
    [ -L "${tmp_home}/.scripts/build-agent-rules.zsh" ]
    [ -L "${tmp_home}/.grip/settings.py" ]
    [ -L "${tmp_home}/.config/cmux/config.ghostty" ]
    [ -L "${tmp_home}/.config/starship.toml" ]
    [ -L "${tmp_home}/.config/yazi/yazi.toml" ]
    [ -L "${tmp_home}/.config/yazi/keymap.toml" ]
    [ -L "${tmp_home}/.config/zed/settings.json" ]
    [ -L "${tmp_home}/.config/zed/keymap.json" ]
    [ -L "${tmp_home}/.config/ghostty/config" ]
    [ -L "${tmp_home}/.claude/settings.json" ]
    [ -L "${tmp_home}/.claude/CLAUDE.md" ]
    [ -L "${tmp_home}/.claude/AGENTS.md" ]
    [ -L "${tmp_home}/.claude/skills" ]
    [ -d "${tmp_home}/.claude/hooks" ]
    [ -L "${tmp_home}/.claude/hooks/one-question-per-turn.py" ]
    [ -f "${tmp_home}/.claude/.i-have-adhd-always" ]
    [ -L "${tmp_home}/.codex/AGENTS.md" ]
    [ -L "${tmp_home}/.codex/skills/ctx-agent-history-search" ]
    [ -L "${tmp_home}/.hermes/SOUL.md" ]
}

@test "link.zsh is idempotent on second run" {
    local tmp_home="${BATS_TEST_TMPDIR}/home2"
    mkdir -p "${tmp_home}"
    HOME="${tmp_home}" run zsh "${SETUP_DIR}/link.zsh"
    [ "${status}" -eq 0 ]
    HOME="${tmp_home}" run zsh "${SETUP_DIR}/link.zsh"
    [ "${status}" -eq 0 ]
    [ -L "${tmp_home}/.zshrc" ]
}

@test "link.zsh backs up a pre-existing real .zshrc instead of clobbering it" {
    local tmp_home="${BATS_TEST_TMPDIR}/home3"
    mkdir -p "${tmp_home}"
    echo "pre-existing content" > "${tmp_home}/.zshrc"
    HOME="${tmp_home}" run zsh "${SETUP_DIR}/link.zsh"
    [ "${status}" -eq 0 ]
    [ -L "${tmp_home}/.zshrc" ]
    [ -f "${tmp_home}/.zshrc.before-setup" ]
    [ "$(cat "${tmp_home}/.zshrc.before-setup")" = "pre-existing content" ]
}
```

- [ ] **Step 2: テストを実行し失敗を確認する**

Run: `bats setup/tests/link.bats`
Expected: FAIL（`setup/link.zsh` が存在しない）

- [ ] **Step 3: 実装する**

```zsh
#!/bin/zsh
# setup/link.zsh
#
# Tier 1: dotfiles リポジトリの working tree を $HOME 配下に symlink 配置する。
# 一度実行すれば、以後の repo 編集は symlink 越しに即座に反映される（switch 不要）。
# 再実行が必要なのは「管理対象ファイルの一覧が増えたとき」だけ（冪等）。
#
# 対応表・設計根拠: docs/superpowers/specs/2026-08-21-restore-script-management-inventory.md
# の 6 節・7 節を参照。
#
# 対象外（別スクリプトが担当。Tier 2、本計画のスコープ外）:
#   Homebrew パッケージ / 言語ランタイム(mise) / macOS defaults / IME / フォント / PAM /
#   Claude plugin sync / MCP servers merge / Codex config.toml seed-if-absent
#
# 使い方:
#   zsh ${HOME}/.dotfiles/setup/link.zsh
#
# 終了コード:
#   0  成功
#   1  リンク元ファイルが存在しない等のエラー

set -eu

# このスクリプト自身の絶対パスから 1 階層上（setup/ の親）を dotfiles root とする。
# ${HOME}/.dotfiles 固定にすると worktree やテスト用の一時 clone で動かせないため。
SETUP_DIR="${0:A:h}"
DOTFILES_ROOT="${SETUP_DIR:h}"

source "${SETUP_DIR}/lib/util.zsh"
source "${SETUP_DIR}/lib/fs.zsh"

util::info "=== Tier 1: symlink 配置 (DOTFILES_ROOT=${DOTFILES_ROOT}) ==="

# ---- zsh 設定・alias SSOT --------------------------------------------------
fs::link_file "${DOTFILES_ROOT}/zshrc"   "${HOME}/.zshrc"
fs::link_file "${DOTFILES_ROOT}/zshenv"  "${HOME}/.zshenv"
fs::link_file "${DOTFILES_ROOT}/aliases" "${HOME}/.aliases"

# ---- git --------------------------------------------------------------
# ~/.gitconfig は書き込み可能な実体ファイルとして保護する。git は ~/.gitconfig が存在すれば
# `git config --global` の書き込み先として最優先で選ぶため、symlink のままだと 3rd party ツール
# （coderabbit CLI の machineId 書き込み等）が失敗する。設定本体は ~/.config/git/config を SSOT
# とし、~/.gitconfig は PC 固有値の落書き帳としてのみ使う。
fs::ensure_realfile "${HOME}/.gitconfig"
fs::link_file "${DOTFILES_ROOT}/config/git/config" "${HOME}/.config/git/config"
fs::link_file "${DOTFILES_ROOT}/config/git/ignore" "${HOME}/.config/git/ignore"
fs::link_file "${DOTFILES_ROOT}/gitmessage"         "${HOME}/.gitmessage"
fs::link_file "${DOTFILES_ROOT}/gitignore_global"   "${HOME}/.gitignore_global"

# ---- ssh --------------------------------------------------------------
fs::link_file "${DOTFILES_ROOT}/ssh/config" "${HOME}/.ssh/config"

# ---- functions / scripts（旧 aliase/）--------------------------------------
fs::link_file "${DOTFILES_ROOT}/functions/fzf-history"          "${HOME}/.functions/fzf-history"
fs::link_file "${DOTFILES_ROOT}/scripts/get-gke-credentials.sh" "${HOME}/.scripts/get-gke-credentials.sh"
fs::link_file "${DOTFILES_ROOT}/scripts/claude-board.zsh"       "${HOME}/.scripts/claude-board.zsh"
fs::link_file "${DOTFILES_ROOT}/scripts/build-agent-rules.zsh"  "${HOME}/.scripts/build-agent-rules.zsh"

# ---- grip / cmux --------------------------------------------------------
fs::link_file "${DOTFILES_ROOT}/grip/settings.py"            "${HOME}/.grip/settings.py"
fs::link_file "${DOTFILES_ROOT}/config/cmux/config.ghostty"  "${HOME}/.config/cmux/config.ghostty"

# ---- starship / yazi / zed / ghostty ---------------------------------------
fs::link_file "${DOTFILES_ROOT}/config/starship/starship.toml" "${HOME}/.config/starship.toml"
fs::link_file "${DOTFILES_ROOT}/config/yazi/yazi.toml"         "${HOME}/.config/yazi/yazi.toml"
fs::link_file "${DOTFILES_ROOT}/config/yazi/keymap.toml"       "${HOME}/.config/yazi/keymap.toml"
fs::link_file "${DOTFILES_ROOT}/config/zed/settings.json"      "${HOME}/.config/zed/settings.json"
fs::link_file "${DOTFILES_ROOT}/config/zed/keymap.json"        "${HOME}/.config/zed/keymap.json"
fs::link_file "${DOTFILES_ROOT}/config/ghostty/config"         "${HOME}/.config/ghostty/config"

# ---- Claude Code（静的ファイルのみ。plugin sync / MCP merge は Tier 2、別計画）----------------
fs::link_file "${DOTFILES_ROOT}/claude/settings.json" "${HOME}/.claude/settings.json"
fs::link_file "${DOTFILES_ROOT}/claude/CLAUDE.md"     "${HOME}/.claude/CLAUDE.md"
fs::link_file "${DOTFILES_ROOT}/claude/AGENTS.md"     "${HOME}/.claude/AGENTS.md"
# skills はディレクトリ単位 symlink（内部が gotomts/skills への相対 symlink で完結しており、
# ファイル単位に分解する意味がないための例外）
fs::link_file "${DOTFILES_ROOT}/claude/skills" "${HOME}/.claude/skills"
# hooks はファイル単位 symlink。~/.claude/hooks/ を実体ディレクトリのまま残し、公開リポジトリに
# 載せられない PC 固有 hook と同居できるようにするため。
fs::link_file "${DOTFILES_ROOT}/claude/hooks/one-question-per-turn.py" \
    "${HOME}/.claude/hooks/one-question-per-turn.py"
# i-have-adhd プラグインの常時適用マーカー
fs::ensure_realfile "${HOME}/.claude/.i-have-adhd-always"

# ---- Codex CLI --------------------------------------------------------
fs::link_file "${DOTFILES_ROOT}/claude/AGENTS.md" "${HOME}/.codex/AGENTS.md"
fs::link_file "${DOTFILES_ROOT}/claude/skills/ctx-agent-history-search" \
    "${HOME}/.codex/skills/ctx-agent-history-search"

# ---- Hermes Agent -------------------------------------------------------
fs::link_file "${DOTFILES_ROOT}/claude/hermes/SOUL.md" "${HOME}/.hermes/SOUL.md"

util::info "=== Tier 1 完了 ==="
```

- [ ] **Step 4: テストを実行し成功を確認する**

Run: `bats setup/tests/link.bats`
Expected: PASS（3 テスト全て）

- [ ] **Step 5: commit しない**（Global Constraints 参照）

---

## Task 8: `setup/README.md`（安全策のドキュメント化）

**Files:**
- Create: `setup/README.md`

ユーザー要件（「running config と既存実体ディレクトリを壊さない安全策は、明示的な関数と
ドキュメントで維持してください」）に対応する。

- [ ] **Step 1: 内容を書く**

```markdown
# setup/

Tier 1（リアルタイム symlink）の実装。`darwin-rebuild switch` を使わず、このディレクトリの
script を直接実行して dotfiles を `$HOME` へ配置する。

設計の全体像・Tier 1/Tier 2 の境界・確定した設計判断は
`docs/superpowers/specs/2026-08-21-restore-script-management-inventory.md` を参照。

## 使い方

```sh
zsh ${HOME}/.dotfiles/setup/link.zsh
```

一度実行すれば、以後の repo 編集（`zshrc`/`aliases`/`claude/CLAUDE.md` 等）は symlink 越しに
即座に反映される。再実行が必要なのは「`setup/link.zsh` 自体に新しい対応行を追加したとき」だけ。

## 安全策（明示関数）

- `fs::link_file`（`lib/fs.zsh`）: symlink 先に既に実体ファイル/ディレクトリがある場合、
  黙って上書きせず `<path>.before-setup` に退避してから symlink を作る。誤って手元の変更を
  失わないための安全策。
- `fs::ensure_realfile`（`lib/fs.zsh`）: `~/.gitconfig` や Claude Code のマーカーファイルなど、
  「dotfiles リポジトリで追跡してはいけない値／状態」を書き込み可能な実体ファイルとして保護する。
  3rd party ツール（coderabbit CLI の machineId 書き込み等）や OAuth token を含む running
  config を壊さないための安全策。symlink のままだと read-only 相当の問題やリポジトリへの
  意図しない値の混入が起きる。

## 対象外（Tier 2、別計画）

Homebrew パッケージ・言語ランタイム(mise)・macOS defaults・IME・フォント・PAM・Claude plugin
sync・MCP servers merge・Codex config.toml seed-if-absent は、このディレクトリの対象外。
これらは「編集して即反映」ではなく「明示的にスクリプトを実行した時に反映されればよい」カテゴリ
であり、別途 Tier 2 の実装計画で扱う。
```

- [ ] **Step 2: commit しない**（Global Constraints 参照）

---

## Task 9: `AGENTS.md`「リポジトリ構造」節の更新

**Files:**
- Modify: `AGENTS.md`（root、リポジトリ構造セクション）

- [ ] **Step 1: 更新箇所を特定する**

`AGENTS.md` の「リポジトリ構造」セクションから `aliase/` の行を探す:

```
- `aliase/` — 外部シェルスクリプト（エイリアスから呼び出される）
```

- [ ] **Step 2: 置き換える**

```
- `aliases` — alias 定義の SSOT（root 直下、`~/.aliases` にシンボリックリンク）
- `scripts/` — 外部シェルスクリプト（`aliases` の alias から呼び出される。旧 `aliase/` から改名）
- `config/git/` — git 設定・ignore（`~/.config/git/` にシンボリックリンク）
- `setup/` — Tier 1（リアルタイム symlink）の実装。`darwin-rebuild switch` を使わず
  `zsh setup/link.zsh` で dotfiles を配置する。詳細は `setup/README.md` を参照
```

（`zshrc` `zshenv` の行は既存のまま。symlink 先の生成元が home-manager からこの `setup/link.zsh`
に変わる点は 6 節の spec 側で扱うため、AGENTS.md 本文の記述自体は変更不要）

- [ ] **Step 3: commit しない**（Global Constraints 参照）

---

## 移行順序・互換性切替（実機適用は対象外、手順のみ記録）

本計画のタスクは全て working tree 内で完結し、実機には一切触れない。実機（現在 home-manager が
管理している実際のログインユーザーの `$HOME`）へ適用する際の想定手順は以下（**本計画では実行しない**）:

1. `fs::link_file` は「symlink 済みで別ターゲットを指している場合は張り替える」ため、
   home-manager が作った既存 symlink（nix store 経由、または `mkOutOfStoreSymlink` で
   既に working tree を指しているもの）を検出して安全に置き換える。**別途の事前移行スクリプト
   （`nix/scripts/migrate-symlinks.zsh` のような dir-symlink 変換）は不要**と設計時点で判断
   している（spec 10 節）— ただし実機で `zsh setup/link.zsh` を初回実行する前に、この判断が
   実際の home-manager 生成物（nix store パスの実体、`.before-nix` 退避ファイル等）と整合するか
   を dry-run 相当の確認（`readlink` での事前調査等）をしてから進めることを推奨する。
2. `~/.claude/skills` 等、現行 `mkOutOfStoreSymlink` で既に working tree を直接指している
   項目は、`setup/link.zsh` 実行時にターゲット一致を検出して no-op になる想定（要実機確認）。
3. 実行順序として `setup/link.zsh` は他の何にも依存しない（Tier 2 が未実装でも単独で動く）ため、
   Tier 1 単独でも先行導入できる。
4. 実機適用の可否・タイミングはユーザー判断（本計画のスコープ外）。

## ロールバック

- **本計画のタスク自体**: 全て working tree 内のファイル作成・変更であり `git commit` していない
  ため、`git checkout -- <file>` または `git clean` で即座に元に戻せる。
- **`fs::link_file` の安全策**: 実機適用時に既存の実体ファイルを誤って壊した場合も、
  `<path>.before-setup` に元の内容が退避されているため `mv` で復元できる。
- **Nix 側**: 本計画は `nix/` 配下を一切変更しないため、Tier 1 導入後も
  `darwin-rebuild switch` を実行すれば home-manager が引き続き機能する（Nix 側のロールバック
  経路は本計画の影響を受けない）。

## テスト/検証まとめ

| 対象 | コマンド | 期待結果 |
|---|---|---|
| 全 bats テスト | `bats setup/tests/*.bats` | 全 PASS（Task 1〜7 で新規作成した 7 ファイル、計 27 テスト） |
| 全 zsh 構文 | `zsh -n <file>` を各新設/変更ファイルに対して実行 | 全て exit 0 |
| git config 妥当性 | `git config --file config/git/config --list` | exit 0、想定キーが読める |

`| head` 等で exit code を隠さず、実際の exit code を確認してから結果を報告する
（`feedback_ci_scope_pure_vs_environment` 系の検証規律に準拠）。

## レビュー可能な判断残り

- なし。本計画の全設計判断（symlink 安全策・alias SSOT 配置・`aliase/`→`scripts/` リネーム・
  zshrc/zshenv 内容・git config 分離・Claude/Codex/Hermes symlink 対象）は、いずれもこれまでの
  ユーザー承認済み決定（spec 10 節「解決済み」）に基づく。新規の設計判断は発生していない。
