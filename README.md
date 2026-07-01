# 🏛️ dotfiles-Arch

**Arch, ricing-ready.** The Arch layer (pacman + AUR) — rolling-release, over
the shared core.

`pacman` · `aur` · `zsh` · `nvim`

[![showcase](https://img.shields.io/badge/showcase-live-7aa2f7?style=flat-square)](https://dotgibson.github.io/dotfiles-web/) ![Arch](https://img.shields.io/badge/Arch-rolling-7dcfff?style=flat-square)

---

The **OS-native layer** for Arch Linux. Core (zsh/tmux/nvim/git) is vendored
under `core/` from [`dotfiles-core`](../dotfiles-core); this repo adds only what
is genuinely Arch — pacman, the AUR, multilib, mirror management — and leans on
Arch's deep official repos so there are no `curl | sh` fallbacks.

Stamped from the [`dotfiles-Fedora`](../dotfiles-Fedora) template per the
[porting matrix](../dotfiles-core/PORTING-MATRIX.md).

## Stage 0 — prerequisites on a fresh/minimal Arch box (bare metal)

Skip this if you used `archinstall` or ArchWSL — both already give you a user
with `sudo`. But a **manual** install drops you at a root prompt with no user,
no `sudo`, and no `git`, so `bootstrap.sh` (which calls `sudo` everywhere) can't
run yet. Lay the groundwork first, **as root**:

```bash
timedatectl set-ntp true                  # correct clock so mirror TLS works
pacman -Syu                               # golden rule: full upgrade, never -Sy alone
pacman -S --needed git base-devel sudo    # git=clone, sudo=bootstrap, base-devel=AUR

# generate a UTF-8 locale — a minimal Arch ships NONE, so you land in the C
# locale and bash prints raw \Uxxxx escapes instead of glyphs (the tmux
# netspeed icons are the usual first casualty). Do this once.
sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo 'LANG=en_US.UTF-8' > /etc/locale.conf   # read at next login (WSL: after Stage 3 restart)

useradd -m -G wheel -s /bin/bash <you>    # bash for now; bootstrap switches to zsh
passwd <you>

# grant wheel sudo via a validated drop-in (no editor needed)
echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/10-wheel
chmod 440 /etc/sudoers.d/10-wheel
visudo -c                                 # must print "... parsed OK"

su - <you>                                # become your user, then Install below
```

Gotchas at this stage:
- **Keyring/signature errors** (old ISO): `sudo pacman -Sy archlinux-keyring && sudo pacman -Syu`, then retry.
- **Private repo**: HTTPS clone needs a PAT, or set up SSH first
  (`ssh-keygen -t ed25519`, add the `.pub` to GitHub) — Core's gitconfig pushes
  via SSH anyway.
- **No network yet**: `iwctl` (Wi-Fi) or `systemctl enable --now systemd-networkd systemd-resolved` (wired) before any `pacman` call.

## Install (fresh Arch)

```bash
git clone <you>/dotfiles-Arch ~/dotfiles-Arch
cd ~/dotfiles-Arch
# one-time: vendor Core (skip if the repo already contains core/)
git subtree add --prefix=core <you>/dotfiles-core main --squash
./bootstrap.sh
exec zsh
```

Flags: `--links-only` (re-link without touching pacman), `--no-flatpak`.

## Layout

```
bootstrap.sh          pacman provision + Core/OS symlink wiring (idempotent)
install/packages.txt  pacman package list (modern CLI stack)
os/arch.zsh           OS-native shell layer -> symlinked to ~/.config/zsh/os.zsh
os/arch.gitconfig     credential helper      -> ~/.config/git/os.gitconfig
os/arch.conf          tmux netspeed/battery  -> ~/.config/tmux/os.conf
ssh/config            hardened SSH client config -> ~/.ssh/config (keys never tracked)
wsl/wsl.conf          /etc/wsl.conf for ArchWSL (systemd + default user)
core/                 vendored from dotfiles-core (git subtree; do not hand-edit)
```

Load order in `.zshrc`: `core/tools → core/aliases → core/functions → core/fzf →
core/bindings → core/plugins → core/op → os/arch → local`.

## Arch specifics baked in

- **Rolling release — never partial-upgrade.** `pacman -Sy <pkg>` (refresh
  without `-u`) can pull a package built against newer libraries than your
  un-upgraded system, and break things. `bootstrap.sh` always does a full
  `pacman -Syu` before installing, and the shell layer only exposes `pacu`
  (full `-Syu`) — there is deliberately **no** `-Sy <pkg>` alias.
- **Everything is in the official repos.** eza/bat/fd/ripgrep/zoxide/fzf/delta/
  btop/dust/procs/tealdeer plus **starship, atuin, yazi, mise, and lazygit** all
  live in `core`/`extra`. Fedora installs the last five from upstream; Arch just
  `pacman -S`'s them. This is why the matrix calls Arch the cleanest distro for
  this stack.
- **`git subtree` ships inside the `git` package** on Arch — there's no separate
  `git-subtree` package to install (Fedora needs one).
- **`fd` is named `fd`** here (not `fdfind` as on Debian); `core/zsh/tools.zsh`
  resolves the name automatically, so nothing breaks across distros.
- **The AUR is not automated.** Arch ships no AUR helper. Build `paru` once and
  the `aur`/`aurs`/`auru` aliases in `os/arch.zsh` light up:
  ```bash
  sudo pacman -S --needed base-devel git
  git clone https://aur.archlinux.org/paru.git && cd paru && makepkg -si
  ```
- **multilib (32-bit / Wine tooling)** is opt-in: uncomment the `[multilib]`
  section in `/etc/pacman.conf`, then `sudo pacman -Syu`. `bootstrap.sh` does
  **not** edit `pacman.conf` for you — it's a deliberate system change.
- **Mirrors:** `reflector` is installed; rank fresh mirrors with
  `sudo reflector --latest 20 --protocol https --sort rate --save /etc/pacman.d/mirrorlist`.
- **No transaction "undo".** pacman has no `dnf history undo`; recover by
  reinstalling an older build from the cache — `pacdowngrade <pkg>` (in
  `os/arch.zsh`) lists the cached versions, then `sudo pacman -U <file>`.
- **No SELinux.** Arch is permissive by default (AppArmor is opt-in), so the
  Fedora `se-*` helpers are intentionally absent from `os/arch.zsh`.

