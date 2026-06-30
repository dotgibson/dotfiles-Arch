# Arch Linux Aliases Cheat Sheet

OS-specific aliases from `os/arch.zsh`. See `core/` for the universal alias
reference (modern CLI, git, safety nets) that applies on every machine.

> **Arch rule:** Never `pacman -Sy <pkg>` without `-u` — partial upgrades break things.
> Use `pacu` to do a full system upgrade before installing anything new.

## Package Management (pacman)

| Alias | Expands To |
|-------|------------|
| `pacu` | `sudo pacman -Syu` (full system upgrade — always run this first) |
| `paci` | `sudo pacman -S --needed` |
| `pacs` | `pacman -Ss` (search repos) |
| `pacqs` | `pacman -Qs` (search installed) |
| `pacr` | `sudo pacman -Rns` (remove + orphan deps + config) |
| `pacwhat` | `pacman -Qo` (which package owns a file) |
| `pacfiles` | `pacman -Ql` (list files in a package) |
| `pacinfo` | `pacman -Qi` (package info) |
| `paclog` | `tail -n 50 /var/log/pacman.log` |
| `pacout` | `checkupdates` (available updates without applying; requires `pacman-contrib`) |
| `paccacheclean` | `sudo paccache -rk2` (keep last 2 versions; requires `pacman-contrib`) |
| `pacorphans` | List then remove orphaned packages via `sudo pacman -Rns` (function) |
| `pacdowngrade <pkg>` | Downgrade package from local cache (function) |

## AUR (paru preferred; yay as fallback)

| Alias | Expands To |
|-------|------------|
| `aur` | `paru -S` / `yay -S` |
| `aurs` | `paru -Ss` / `yay -Ss` |
| `auru` | `paru -Sua` / `yay -Sua` |

## Flatpak

| Alias | Expands To |
|-------|------------|
| `fpi` | `flatpak install flathub` |
| `fpu` | `flatpak update` |
| `fps` | `flatpak search` |
| `fpl` | `flatpak list --app` |

## Clipboard / WSL2 / Navigation

| Alias | Expands To | Condition |
|-------|-----------|----------|
| `pbcopy` | `clip` | clip available |
| `pbpaste` | `clip-paste` | clip-paste available |
| `dotsync` | `cd "$HOME/dotfiles-Arch"` | always |
| `opsignin` | `eval "$(op signin)"` | 1Password CLI |
| `localip` | `ip -brief -4 addr show scope global` | always |
| `open` | `explorer.exe` | WSL2 |
| `xdg-open` | `wslview` | WSL2 + wslview |
| `cdwin` | `cd "$WINHOME"` | WSL2 + WINHOME set |
