#!/usr/bin/env bash
# dotfiles-Arch/bootstrap.sh
# ──────────────────────────────────────────────────────────────────────────────
# Provision an Arch Linux box (desktop or WSL/ArchWSL) and wire up dotfiles.
# Idempotent — safe to re-run. This is the OS-NATIVE layer; Core (zsh/tmux/nvim/
# git) is vendored under core/ and symlinked in via core/lib/bootstrap-lib.sh.
#
# Usage:
#   ./bootstrap.sh                 # full: pacman packages + extras + symlinks
#   ./bootstrap.sh --links-only    # just (re)create symlinks
#   ./bootstrap.sh --no-flatpak    # skip Flathub/GUI apps (recommended on WSL)
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
LINKS_ONLY=0
DO_FLATPAK=1

for a in "$@"; do case "$a" in
  --links-only) LINKS_ONLY=1 ;;
  --no-flatpak) DO_FLATPAK=0 ;;
  -h | --help) sed -n '2,11p' "$0"; exit 0 ;;
  *) echo "unknown arg: $a" >&2; exit 1 ;;
esac; done

# ── core/ subtree present? (inline: can't source a lib out of core/ before this) ─
# Validate the SPECIFIC paths we depend on (zsh modules + the two libs sourced
# next) so a missing/partial subtree fails HERE with a precise message, not later
# with a cryptic `source: No such file`.
for _req in core/zsh/loader.zsh core/lib/ux.sh core/lib/bootstrap-lib.sh; do
  if [[ ! -e "$DOTFILES/$_req" ]]; then
    echo "core/ subtree missing or incomplete (need $_req). One-time, run:" >&2
    echo "  git subtree add  --prefix=core <dotfiles-core remote> main --squash   # first time" >&2
    echo "  git subtree pull --prefix=core <dotfiles-core remote> main --squash   # to update" >&2
    exit 1
  fi
done
unset _req

# Shared bash UX palette + provisioning scaffold (vendored under core/lib).
# shellcheck source=core/lib/ux.sh
source "$DOTFILES/core/lib/ux.sh"
# shellcheck source=core/lib/bootstrap-lib.sh
source "$DOTFILES/core/lib/bootstrap-lib.sh"

# ── sanity: confirm we're on Arch ─────────────────────────────────────────────
# Match the ID line specifically so we don't false-positive on a distro that
# merely mentions "arch" in its NAME/pretty string. (ArchWSL keeps ID=arch.)
if ! grep -qE '^ID=arch$' /etc/os-release 2>/dev/null; then
  echo "This bootstrap targets Arch Linux. /etc/os-release doesn't look like Arch (no 'ID=arch')." >&2
  exit 1
fi

IS_WSL=0
if blib_is_wsl; then IS_WSL=1; fi

provision() {
  # ── Arch golden rule: NEVER partial-upgrade ────────────────────────────────
  # `pacman -Sy <pkg>` (refresh without -u) is the classic Arch footgun: it can
  # pull a package built against newer libs than your unupgraded system has. The
  # correct pattern is a full `-Syu` FIRST so the box is current before installs.
  blib_say "pacman full system sync + upgrade (-Syu)"
  sudo pacman -Syu --noconfirm

  blib_say "pacman packages (from install/packages.txt)"
  local -a pkgs=()
  mapfile -t pkgs < <(blib_read_pkgs "$DOTFILES/install/packages.txt")
  # Unlike dnf's --skip-unavailable, pacman aborts the WHOLE transaction if any
  # single target name is wrong. Try the bulk install with --needed (skips
  # already-installed), and on failure fall back to a per-package loop so one bad
  # name can't sink the rest. (System is current from -Syu, so -S is not partial.)
  if sudo pacman -S --needed --noconfirm "${pkgs[@]}"; then
    blib_ok "pacman packages installed (${#pkgs[@]} requested)"
  else
    blib_say "bulk install hit a snag — retrying package-by-package (resilient)"
    local p
    for p in "${pkgs[@]}"; do
      sudo pacman -S --needed --noconfirm "$p" || echo "   skipped (unavailable?): $p"
    done
    blib_ok "per-package install pass complete"
  fi

  # NOTE (vs Fedora): starship, atuin, yazi, mise, lazygit are ALL in Arch's
  # official repos (extra), so they live in packages.txt — no upstream-installer
  # block here. That's the Arch payoff: one package manager, no curl|sh fallbacks.

  # ── WSL: install /etc/wsl.conf (systemd + default user + interop) ───────────
  if ((IS_WSL)); then
    blib_say "installing /etc/wsl.conf (systemd + default user)"
    local user
    user="$(id -un)"
    sed "s/__WSL_USER__/$user/" "$DOTFILES/wsl/wsl.conf" | sudo tee /etc/wsl.conf >/dev/null
    blib_ok "wsl.conf written — run 'wsl.exe --shutdown' from Windows, then reopen, to apply"
  fi

  if ((DO_FLATPAK)) && ! ((IS_WSL)); then
    blib_say "Flathub"
    flatpak remote-add --if-not-exists flathub \
      https://flathub.org/repo/flathub.flatpakrepo >/dev/null 2>&1 || true
  fi

  # ── Optional, NOT automated (documented manual steps) ──────────────────────
  #  • multilib (32-bit / Wine): uncomment [multilib] in /etc/pacman.conf, then -Syu.
  #  • AUR helper: build paru once (sudo pacman -S --needed base-devel git; then
  #    git clone https://aur.archlinux.org/paru.git && makepkg -si).
  #  • Fastest mirrors: sudo reflector --latest 20 --sort rate --save /etc/pacman.d/mirrorlist
}

wire_links() {
  # The shared symlink surface + the Arch OS overlays + the managed .zshrc loader
  # + the default-login-shell switch all live in core/lib/bootstrap-lib.sh.
  blib_link_core "$DOTFILES" "$CONFIG"
  blib_link_os_layer "$DOTFILES" "$CONFIG" arch
  # shellcheck disable=SC2119  # no args is intentional — writes the default module set
  blib_write_zshrc_loader
  blib_set_login_shell
  blib_ok "symlinks wired"
}

((LINKS_ONLY)) || provision
wire_links
blib_ok "Arch bootstrap complete — open a new shell or: exec zsh"
