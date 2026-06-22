#!/usr/bin/env bash
# dotfiles-Arch/bootstrap.sh
# ──────────────────────────────────────────────────────────────────────────────
# Provision an Arch Linux box (desktop or WSL/ArchWSL) and wire up dotfiles.
# Idempotent — safe to re-run. This is the OS-NATIVE layer; Core (zsh/tmux/nvim/
# git) is vendored under core/ via git subtree and symlinked in by this script.
#
# Usage:
#   ./bootstrap.sh                 # full: pacman packages + extras + symlinks
#   ./bootstrap.sh --links-only    # just (re)create symlinks
#   ./bootstrap.sh --no-flatpak    # skip Flathub/GUI apps (recommended on WSL)
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
LINKS_ONLY=0; DO_FLATPAK=1

for a in "$@"; do case "$a" in
  --links-only) LINKS_ONLY=1 ;;
  --no-flatpak) DO_FLATPAK=0 ;;
  -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
  *) echo "unknown arg: $a" >&2; exit 1 ;;
esac; done

say(){ printf '\e[36m::\e[0m %s\n' "$*"; }
ok(){  printf '\e[32m✓\e[0m %s\n' "$*"; }

# ── Detect WSL ────────────────────────────────────────────────────────────────
IS_WSL=0
if [[ -n "${WSL_DISTRO_NAME:-}" ]] || grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null; then
  IS_WSL=1
fi

# ── sanity: confirm we're on Arch ─────────────────────────────────────────────
# Arch's /etc/os-release carries ID=arch. (ArchWSL keeps the same ID.) Match the
# ID line specifically so we don't false-positive on a distro that merely
# mentions "arch" in its NAME/pretty string.
if ! grep -qE '^ID=arch$' /etc/os-release 2>/dev/null; then
  echo "This bootstrap targets Arch Linux. /etc/os-release doesn't look like Arch (no 'ID=arch')." >&2
  exit 1
fi

# ── core/ subtree present? ────────────────────────────────────────────────────
if [[ ! -d "$DOTFILES/core/zsh" ]]; then
  echo "core/ subtree missing. One-time, run:" >&2
  echo "  git subtree add --prefix=core <dotfiles-core remote> main --squash" >&2
  exit 1
fi

link(){  # link SRC -> DST, backing up any existing real file
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  if [[ -L "$dst" ]]; then rm -f "$dst"
  elif [[ -e "$dst" ]]; then mv "$dst" "$dst.pre-dotfiles.$(date +%s)"; fi
  ln -s "$src" "$dst"
}

# ── read a package list, stripping inline (#...) comments + blank lines ───────
read_pkgs(){  # $1 = file; prints clean package names, one per line
  local line
  while IFS= read -r line; do
    line="${line%%#*}"               # drop everything from the first # onward
    line="${line//[[:space:]]/}"     # package names contain no whitespace
    [[ -n "$line" ]] && printf '%s\n' "$line"
  done < "$1"
}

provision() {
  # ── Arch golden rule: NEVER partial-upgrade ────────────────────────────────
  # `pacman -Sy <pkg>` (refresh without -u) is the classic Arch footgun: it can
  # pull a package built against newer libs than your unupgraded system has.
  # The correct pattern is to refresh + upgrade the whole system FIRST, then
  # install. We do a full `-Syu` here so the box is current before any installs.
  say "pacman full system sync + upgrade (-Syu)"
  sudo pacman -Syu --noconfirm

  say "pacman packages (from install/packages.txt)"
  local -a pkgs=()
  mapfile -t pkgs < <(read_pkgs "$DOTFILES/install/packages.txt")
  # Unlike dnf's --skip-unavailable, pacman aborts the WHOLE transaction if any
  # single target name is wrong/unavailable. So: try the bulk install with
  # --needed (skips already-installed), and if that fails fall back to a
  # per-package loop so one bad name can't sink the rest. (System is already
  # current from the -Syu above, so a plain -S here is NOT a partial upgrade.)
  if sudo pacman -S --needed --noconfirm "${pkgs[@]}"; then
    ok "pacman packages installed (${#pkgs[@]} requested)"
  else
    say "bulk install hit a snag — retrying package-by-package (resilient)"
    local p
    for p in "${pkgs[@]}"; do
      sudo pacman -S --needed --noconfirm "$p" \
        || echo "   skipped (unavailable?): $p"
    done
    ok "per-package install pass complete"
  fi

  # NOTE (vs Fedora): starship, atuin, yazi, mise, lazygit are ALL in Arch's
  # official repos (extra), so they live in packages.txt — there is no
  # upstream-installer block here. That's the Arch payoff: one package manager,
  # no curl|sh fallbacks. If you later want the newest mise/yazi than extra
  # ships, install via an AUR helper (paru/yay) or `cargo install` instead.

  # ── WSL: install /etc/wsl.conf (systemd + default user + interop) ───────────
  if (( IS_WSL )); then
    say "installing /etc/wsl.conf (systemd + default user)"
    local user; user="$(id -un)"
    sed "s/__WSL_USER__/$user/" "$DOTFILES/wsl/wsl.conf" | sudo tee /etc/wsl.conf >/dev/null
    ok "wsl.conf written — run 'wsl.exe --shutdown' from Windows, then reopen, to apply"
  fi

  if (( DO_FLATPAK )) && ! (( IS_WSL )); then
    say "Flathub"
    flatpak remote-add --if-not-exists flathub \
      https://flathub.org/repo/flathub.flatpakrepo >/dev/null 2>&1 || true
  fi

  # ── Optional, NOT automated (left as documented manual steps) ──────────────
  #  • multilib (32-bit / Wine tooling): uncomment the [multilib] section in
  #    /etc/pacman.conf, then `sudo pacman -Syu`. We don't edit pacman.conf for
  #    you — it's a system file and the change is a deliberate one.
  #  • AUR helper: Arch ships none. Build paru once, then it manages the AUR:
  #      sudo pacman -S --needed base-devel git
  #      git clone https://aur.archlinux.org/paru.git /tmp/paru && (cd /tmp/paru && makepkg -si)
  #  • Fastest mirrors: `sudo reflector --latest 20 --sort rate --save /etc/pacman.d/mirrorlist`
}

wire_links() {
  say "symlinking Core"
  for f in "$DOTFILES"/core/zsh/*.zsh; do
    link "$f" "$CONFIG/zsh/$(basename "$f")"
  done
  [[ -f "$DOTFILES/core/tmux/tmux.conf" ]] && link "$DOTFILES/core/tmux/tmux.conf" "$CONFIG/tmux/tmux.conf"
  # tmux popup scripts (prefix w/T/f) — symlink the dir + ensure they're runnable
  if [[ -d "$DOTFILES/core/tmux/scripts" ]]; then
    link "$DOTFILES/core/tmux/scripts" "$CONFIG/tmux/scripts"
    chmod +x "$DOTFILES"/core/tmux/scripts/*.sh 2>/dev/null || true
  fi
  # Arch tmux bits (netspeed iface + battery) — optional; tmux.conf sources it
  # with `-q`, so it's fine if os/arch.conf doesn't exist yet.
  [[ -f "$DOTFILES/os/arch.conf" ]] && link "$DOTFILES/os/arch.conf" "$CONFIG/tmux/os.conf"
  # tmux plugin manager (tpm) — clone once so the theme + resurrect/continuum
  # load. Plugins still need one install pass: `prefix+I` in tmux, or headless
  # ~/.config/tmux/plugins/tpm/bin/install_plugins
  if [[ ! -d "$CONFIG/tmux/plugins/tpm" ]]; then
    say "cloning tpm (tmux plugin manager)"
    git clone --depth=1 https://github.com/tmux-plugins/tpm "$CONFIG/tmux/plugins/tpm" >/dev/null 2>&1 \
      && ok "tpm cloned — run prefix+I in tmux to install plugins" \
      || say "tpm clone failed — clone it manually, then prefix+I"
  fi
  # starship prompt theme — symlink to the DEFAULT path (tools.zsh inits starship
  # against ~/.config/starship.toml with no STARSHIP_CONFIG, same as the Mac).
  [[ -f "$DOTFILES/core/starship/starship.toml" ]] && link "$DOTFILES/core/starship/starship.toml" "$CONFIG/starship.toml"
  [[ -d "$DOTFILES/core/nvim" ]]           && link "$DOTFILES/core/nvim"           "$CONFIG/nvim"
  [[ -f "$DOTFILES/core/mise/config.toml" ]] && link "$DOTFILES/core/mise/config.toml" "$CONFIG/mise/config.toml"
  [[ -f "$DOTFILES/core/git/gitconfig" ]]  && link "$DOTFILES/core/git/gitconfig"  "$HOME/.gitconfig"

  # OS-specific git layer (credential helper) -> included by Core's gitconfig
  [[ -f "$DOTFILES/os/arch.gitconfig" ]] && link "$DOTFILES/os/arch.gitconfig" "$CONFIG/git/os.gitconfig"
  # private identity file, seeded ONCE from the example (never tracked)
  if [[ ! -f "$CONFIG/git/local.gitconfig" && -f "$DOTFILES/core/git/local.gitconfig.example" ]]; then
    mkdir -p "$CONFIG/git"
    cp "$DOTFILES/core/git/local.gitconfig.example" "$CONFIG/git/local.gitconfig"
    say "seeded ~/.config/git/local.gitconfig — FILL IN your name & email"
  fi

  # cross-OS helper scripts from Core onto PATH (~/.local/bin)
  if [[ -d "$DOTFILES/core/bin" ]]; then
    mkdir -p "$HOME/.local/bin"
    for s in clip clip-paste; do
      if [[ -f "$DOTFILES/core/bin/$s" ]]; then
        link "$DOTFILES/core/bin/$s" "$HOME/.local/bin/$s"
        chmod +x "$DOTFILES/core/bin/$s" 2>/dev/null || true
      fi
    done
  fi

  # ── SSH client config (keys are NEVER tracked — only ssh/config) ────────────
  # ssh is strict about permissions: ~/.ssh must be 0700, and ControlMaster
  # needs the sockets dir to already exist or multiplexed connections fail.
  if [[ -f "$DOTFILES/ssh/config" ]]; then
    say "symlinking ssh/config"
    mkdir -p "$HOME/.ssh/sockets"
    chmod 700 "$HOME/.ssh" "$HOME/.ssh/sockets"
    chmod 600 "$DOTFILES/ssh/config" 2>/dev/null || true
    link "$DOTFILES/ssh/config" "$HOME/.ssh/config"
    ok "~/.ssh/config linked (generate a key with: ssh-keygen -t ed25519)"
  fi

  say "symlinking Arch OS-native layer"
  link "$DOTFILES/os/arch.zsh" "$CONFIG/zsh/os.zsh"

  if [[ ! -f "$HOME/.zshrc" ]] || ! grep -q "dotfiles-managed v2" "$HOME/.zshrc" 2>/dev/null; then
    say "writing .zshrc loader"
    [[ -f "$HOME/.zshrc" ]] && cp "$HOME/.zshrc" "$HOME/.zshrc.pre-dotfiles.$(date +%s)"
    cat > "$HOME/.zshrc" <<'ZRC'
# dotfiles-managed v2 — do not hand-edit; put local tweaks in ~/.config/zsh/local.zsh
# Arch has no ~/.zshenv from us, so this entry file also sets the env the Core
# modules expect, then sources them in the ONE correct order. Mirror of the Mac.

# ── XDG + env (no zshenv on Arch) ─────────────────────────────────────────────
: "${XDG_CONFIG_HOME:=$HOME/.config}"
: "${XDG_STATE_HOME:=$HOME/.local/state}"
: "${XDG_CACHE_HOME:=$HOME/.cache}"
export EDITOR=nvim VISUAL=nvim
export NOTES_DIR="${NOTES_DIR:-$HOME/Notes}"

# ── Core modules + Arch os layer + local overrides, in canonical order ──
# history.zsh owns HISTFILE/HISTSIZE + history setopts; options.zsh owns the nav/glob
# setopts + compinit + completion zstyles — so this entry file no longer hand-rolls
# them. It declares the load order and sources the vendored Core loader
# (core/zsh/loader.zsh -> $ZSH_CFG/loader.zsh), which byte-compiles + sources each
# module. Loading the FULL set (ui/git/maint/update were silently missing) is the fix.
ZSH_CFG="$XDG_CONFIG_HOME/zsh"
_CORE_MODULES=(tools ui options history aliases git functions fzf bindings plugins op maint update os local)
if [[ -r "$ZSH_CFG/loader.zsh" ]]; then
  source "$ZSH_CFG/loader.zsh"
else
  print -u2 -- "zshrc: loader.zsh not found — run ./bootstrap.sh (Core modules not loaded)."
fi
unset _CORE_MODULES
ZRC
  fi

  # make zsh the default LOGIN shell — a fresh WSL/login session starts the
  # login shell, not `exec zsh`. Idempotent: only acts if it isn't already zsh.
  if command -v zsh >/dev/null; then
    local zsh_path; zsh_path="$(command -v zsh)"
    if ! getent passwd "$USER" | grep -q ":$zsh_path$"; then
      say "setting zsh as default login shell"
      grep -qxF "$zsh_path" /etc/shells || echo "$zsh_path" | sudo tee -a /etc/shells >/dev/null
      sudo chsh -s "$zsh_path" "$USER" && ok "default shell -> zsh (applies to NEW sessions)"
    fi
  fi
  ok "symlinks wired"
}

(( LINKS_ONLY )) || provision
wire_links
ok "Arch bootstrap complete — open a new shell or: exec zsh"
