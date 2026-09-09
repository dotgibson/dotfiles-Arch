# dotfiles-Arch/os/arch.zsh
# ──────────────────────────────────────────────────────────────────────────────
# The Arch OS-native shell layer. Symlinked to ~/.config/zsh/80-os.zsh and loaded
# AFTER Core (tools/aliases/functions). Arch-specific only.
# Works on Arch desktop (Wayland/X11) AND ArchWSL.
#
# NOTE: clipboard logic no longer lives here — it moved to Core's cross-OS
# `clip`/`clip-paste` scripts, which zsh, tmux, and nvim all share. This layer
# just keeps the pbcopy/pbpaste muscle-memory names pointed at them.
# ──────────────────────────────────────────────────────────────────────────────
[[ $- == *i* ]] || return 0

# ── PATH: user-local bins first (Core's `clip` scripts + cargo tools land here)
[[ -d "$HOME/.local/bin" && ":$PATH:" != *":$HOME/.local/bin:"* ]] && export PATH="$HOME/.local/bin${PATH:+:$PATH}"
[[ -d "$HOME/.cargo/bin" && ":$PATH:" != *":$HOME/.cargo/bin:"* ]] && export PATH="$HOME/.cargo/bin${PATH:+:$PATH}"

# ── Detect WSL once (for the niceties below) ──────────────────────────────────
_IS_WSL=0
if [[ -n "${WSL_DISTRO_NAME:-}" ]]; then
  _IS_WSL=1
elif [[ -r /proc/version ]]; then
  # zsh reads the file directly (no grep/cat fork) — WSL kernels tag /proc/version.
  _pv="$(</proc/version)"; _pv=${_pv:l}
  [[ "$_pv" == *microsoft* || "$_pv" == *wsl* ]] && _IS_WSL=1
  unset _pv
fi

# ── Clipboard: delegate to Core's cross-OS scripts (single implementation) ────
command -v clip       >/dev/null && alias pbcopy='clip'
command -v clip-paste >/dev/null && alias pbpaste='clip-paste'

# ── tool completions / shell hooks: OWNED BY CORE, deliberately not here ─────
# direnv/gh/uv/ty were cached here with _cache_eval (parity with the Mac os layer).
# Core does all four itself now: direnv via _cache_eval, and gh/uv/ty via
# _cache_completion, which drops `_<tool>` into the fpath dir for compinit instead
# of SOURCING the generated completion into every shell — dotfiles-core#579 measured
# that at +37 ms/shell, essentially all of it uv's 6,976 lines. This layer loads as
# 80-os.zsh, always AFTER Core's band 00, so anything re-added here is duplication
# that costs startup and wins nothing.

# ── conveniences ──────────────────────────────────────────────────────────────
alias dotsync='cd "$HOME/dotfiles-Arch"'                # jump to this repo
command -v op >/dev/null 2>&1 && alias opsignin='eval "$(op signin)"'
alias localip='ip -brief -4 addr show scope global'     # iface + LAN IP(s)

# ── WSL-only niceties (interop reach-arounds into Windows) ───────────────────
if (( _IS_WSL )); then
  alias open='explorer.exe'                 # `open .` opens the dir in Explorer
  command -v wslview >/dev/null && alias xdg-open='wslview'
  # jump to your Windows user home: set WINHOME in 99-local.zsh, e.g.
  #   export WINHOME="/mnt/c/Users/<you>"
  [[ -n "${WINHOME:-}" ]] && alias cdwin='cd "$WINHOME"'
fi

# ── Arch ships fd as `fd` (not fdfind) — 00-tools.zsh already resolved this. ─────

# ── pacman quality-of-life ────────────────────────────────────────────────────
# The Arch golden rule lives in muscle memory here: there is NO `-Sy <pkg>`
# alias on purpose. Refresh-without-upgrade then installing is the partial-
# upgrade footgun. `pacu` always does a FULL `-Syu`.
alias pacu='sudo pacman -Syu'              # the ONLY blessed way to update
alias paci='sudo pacman -S --needed'       # install (skip already-installed)
alias pacs='pacman -Ss'                    # search remote
alias pacqs='pacman -Qs'                   # search installed
alias pacr='sudo pacman -Rns'              # remove + unneeded deps + config
alias pacwhat='pacman -Qo'                 # which package owns a file/command
alias pacfiles='pacman -Ql'                # list files a package installed
alias pacinfo='pacman -Qi'                 # info on an installed package
alias paclog='tail -n 50 /var/log/pacman.log'   # recent transactions (the "history")

# checkupdates (from pacman-contrib): list available updates WITHOUT touching
# the sync DB — safe, and avoids the -Sy partial-upgrade trap entirely.
command -v checkupdates >/dev/null 2>&1 && alias pacout='checkupdates'

# orphan removal — drop packages nothing depends on anymore.
# ${(f)orphans} — the (f) flag splits on NEWLINES, which is required here and not
# cosmetic: this is zsh, and zsh does NOT word-split unquoted parameters the way
# bash does (SH_WORD_SPLIT is off, and nothing in Core or this layer sets it). A
# bare `$orphans` therefore hands pacman the whole newline-joined list as ONE
# argument and it fails with "target not found: pkg1\npkg2…". `zsh -n` — the only
# zsh check in CI — cannot see this, because the syntax is perfectly valid.
pacorphans() {
  local orphans; orphans="$(pacman -Qtdq 2>/dev/null)"
  if [[ -z "$orphans" ]]; then echo "no orphans 🎉"; return 0; fi
  echo "$orphans"
  echo "--- removing the above ---"
  sudo pacman -Rns ${(f)orphans}
}

# cache cleanup — keep the last N versions (paccache from pacman-contrib).
command -v paccache >/dev/null 2>&1 && alias paccacheclean='sudo paccache -rk2'

# pacman has no true "undo last transaction" (no dnf history undo). The supported
# recovery is to DOWNGRADE from the local package cache. This just shows you the
# cached versions for a package so you can pick one to reinstall:
#   sudo pacman -U /var/cache/pacman/pkg/<pkg>-<oldver>.pkg.tar.zst
pacdowngrade() {
  if [[ -z "$1" ]]; then echo "usage: pacdowngrade <pkgname>  (then pacman -U the chosen file)"; return 1; fi
  ls -1t /var/cache/pacman/pkg/"$1"-*.pkg.tar.* 2>/dev/null || echo "no cached versions of '$1'"
}

# mirror refresh (reflector) — edits /etc/pacman.d/mirrorlist, so it's a manual,
# deliberate action, not an alias that runs sudo behind a short keystroke:
#   sudo reflector --latest 20 --protocol https --sort rate --save /etc/pacman.d/mirrorlist

# ── AUR helper (paru/yay if present; Arch ships neither by default) ──────────
# Build paru once:  sudo pacman -S --needed base-devel git &&
#   git clone https://aur.archlinux.org/paru.git && cd paru && makepkg -si
if command -v paru >/dev/null 2>&1; then
  alias aur='paru -S'
  alias aurs='paru -Ss'
  alias auru='paru -Sua'           # upgrade AUR packages only
elif command -v yay >/dev/null 2>&1; then
  alias aur='yay -S'
  alias aurs='yay -Ss'
  alias auru='yay -Sua'
fi

# ── Flatpak helpers (mostly inert on WSL without WSLg; harmless) ─────────────
alias fpi='flatpak install flathub'
alias fpu='flatpak update'
alias fps='flatpak search'
alias fpl='flatpak list --app'

unset _IS_WSL

# ── auto-start/attach tmux for interactive terminals ─────────────────────────
# Skip inside an existing tmux, VS Code's integrated terminal, non-TTYs, and when
# DOTFILES_NO_AUTOTMUX is set — the fleet's one opt-out name (MacBook, openSUSE and Gentoo
# read it too). Any harness that drives an interactive zsh and must not land in tmux exports
# it: dotfiles-core's README hero render sources this layer from inside vhs, and without the
# knob it attached here and typed its whole tour into a fresh `main` session
# (dotgibson/dotfiles-core#877). Core's gen-hero-tape.sh refuses to render on a layer that
# does not honour it.
if command -v tmux >/dev/null 2>&1 \
   && [[ -z "$TMUX" && -z "${DOTFILES_NO_AUTOTMUX:-}" && -t 1 && "$TERM_PROGRAM" != "vscode" ]]; then
  tmux attach -t main 2>/dev/null || tmux new-session -s main
fi
