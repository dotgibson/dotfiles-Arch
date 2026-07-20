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

# ── tool completions / shell hooks (parity with the Mac os layer) ────────────
# direnv/gh/uv/ty emit DETERMINISTIC scripts (the generated hook/completion TEXT is static
# for a given binary; only the runtime hooks vary per-dir/-shell), so route them through
# Core's _cache_eval (00-tools.zsh) — one cheap `source` of a cached file instead of forking
# each generator on EVERY interactive shell. _cache_eval self-guards on the binary being
# present and regenerates only when it's newer than the cache. Falls back to the eager
# eval if this OS layer is sourced without Core's 00-tools.zsh — the fallback
# keeps direnv's stderr visible, while the cached path suppresses the generator's
# stderr (as _cache_eval does); direnv's per-dir runtime warnings are unaffected.
if (( $+functions[_cache_eval] )); then
  _cache_eval direnv direnv hook zsh
  _cache_eval gh gh completion -s zsh
  _cache_eval uv uv generate-shell-completion zsh
  _cache_eval ty ty generate-shell-completion zsh
else
  command -v direnv >/dev/null 2>&1 && eval "$(direnv hook zsh)"
  command -v gh >/dev/null 2>&1 && eval "$(gh completion -s zsh 2>/dev/null)"
  command -v uv >/dev/null 2>&1 && eval "$(uv generate-shell-completion zsh 2>/dev/null)"
  command -v ty >/dev/null 2>&1 && eval "$(ty generate-shell-completion zsh 2>/dev/null)"
fi

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
pacorphans() {
  local orphans; orphans="$(pacman -Qtdq 2>/dev/null)"
  if [[ -z "$orphans" ]]; then echo "no orphans 🎉"; return 0; fi
  echo "$orphans"
  echo "--- removing the above ---"
  sudo pacman -Rns $orphans
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
# Skip inside an existing tmux, VS Code's integrated terminal, and non-TTYs.
if command -v tmux >/dev/null 2>&1 \
   && [[ -z "$TMUX" && -t 1 && "$TERM_PROGRAM" != "vscode" ]]; then
  tmux attach -t main 2>/dev/null || tmux new-session -s main
fi
