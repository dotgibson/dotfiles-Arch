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
#   ./bootstrap.sh --only zsh,nvim # link ONLY these Core module groups
#   ./bootstrap.sh --skip tmux     # link everything EXCEPT these groups
#
# Module groups (for --only/--skip): zsh nvim tmux git prompt tools — they affect
# the wiring steps only, never package provisioning; combine with --links-only to
# re-wire a subset of configs without touching pacman.
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
LINKS_ONLY=0
DO_FLATPAK=1
# --only/--skip are validated by the shared lib (blib_select), sourced AFTER this
# loop — capture the raw values now and apply them below.
ONLY_RAW=""; SKIP_RAW=""; ONLY_SEEN=0; SKIP_SEEN=0

while [[ $# -gt 0 ]]; do case "$1" in
  --links-only) LINKS_ONLY=1 ;;
  --no-flatpak) DO_FLATPAK=0 ;;
  --only) [[ $# -ge 2 ]] || { echo "--only requires module names, e.g. --only zsh,nvim" >&2; exit 1; }; ONLY_RAW="$2"; ONLY_SEEN=1; shift ;;
  --only=*) ONLY_RAW="${1#*=}"; ONLY_SEEN=1 ;;
  --skip) [[ $# -ge 2 ]] || { echo "--skip requires module names, e.g. --skip tmux" >&2; exit 1; }; SKIP_RAW="$2"; SKIP_SEEN=1; shift ;;
  --skip=*) SKIP_RAW="${1#*=}"; SKIP_SEEN=1 ;;
  -h | --help) sed -n '2,17p' "$0"; exit 0 ;;
  *) echo "unknown arg: $1" >&2; exit 1 ;;
esac; shift; done

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

# Apply any --only/--skip module selection now the validator (blib_select) exists;
# it aborts on a malformed selector or an unknown group.
if ((ONLY_SEEN)); then blib_select --only "$ONLY_RAW"; fi
if ((SKIP_SEEN)); then blib_select --skip "$SKIP_RAW"; fi

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

  # ── the few core-doctor tools NOT in the official repos (AUR / Go) ──────────
  # doggo, carapace, sesh, op live only in the AUR. This bootstrap deliberately
  # does NOT build an AUR helper (paru is a documented manual step below), so we
  # install the three Go tools straight from source — best-effort, never fatal
  # under `set -e`. If you already run paru, the native route is:
  #   paru -S doggo-bin carapace-bin sesh-bin 1password-cli
  # NOTE: `go install` drops binaries in $GOBIN (defaults to ~/go/bin), which is
  # NOT on the shell PATH (the Core shell layer prefixes ~/.local/bin + ~/.cargo/
  # bin). Pin GOBIN=~/.local/bin so the tools land somewhere already on PATH.
  _dotfiles_go_install() { # <import-path@version> <binary-name>
    [ "$#" -ge 2 ] || return 0
    if command -v "$2" >/dev/null 2>&1; then return 0; fi
    local gobin="$HOME/.local/bin"
    mkdir -p "$gobin" 2>/dev/null || true
    if command -v go >/dev/null 2>&1; then
      GOBIN="$gobin" go install "$1" >/dev/null 2>&1 ||
        echo "   $2: go install failed — retry later: GOBIN=$gobin go install $1"
    elif command -v mise >/dev/null 2>&1; then
      GOBIN="$gobin" mise exec go@latest -- go install "$1" >/dev/null 2>&1 ||
        echo "   $2: go install failed — retry later: GOBIN=$gobin go install $1"
    else
      echo "   $2: needs Go — install later with: GOBIN=$gobin go install $1"
    fi
    return 0
  }
  blib_say "core-doctor extras not in Arch repos (best-effort via Go)"
  _dotfiles_go_install github.com/mr-karan/doggo/cmd/doggo@latest doggo
  _dotfiles_go_install github.com/carapace-sh/carapace-bin/cmd/carapace@latest carapace
  _dotfiles_go_install github.com/joshmedeski/sesh/v2@latest sesh   # /v2 module path is required
  # op (1Password CLI) is proprietary — no Go route. On Arch it's the AUR
  # `1password-cli` package, whose PKGBUILD verifies AgileBits' PGP key
  # 3FEF9748469ADBE15DA7CA80AC2D62742012EA22 (if the build complains, first run:
  #   gpg --recv-keys 3FEF9748469ADBE15DA7CA80AC2D62742012EA22).
  if ! command -v op >/dev/null 2>&1; then
    echo "   op: 1Password CLI not found — install the AUR '1password-cli' pkg" \
         "(e.g. 'paru -S 1password-cli') or see https://developer.1password.com/docs/cli"
  fi

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
  blib_ok "symlinks wired$(blib_selected_note)"
}

((LINKS_ONLY)) || provision
wire_links
blib_ok "Arch bootstrap complete — open a new shell or: exec zsh"
