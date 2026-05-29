# dotfiles-Arch — SETUP (creating this repo from scratch)

This is the **author** path: bringing this repo into existence for the first
time and bootstrapping it onto a fresh machine. It is deliberately separate from
the [`README.md`](./README.md) "Install" section, which is the **consumer** path
— `git clone` a repo that *already* exists on GitHub. You only run through this
doc once per repo; after that, the README flow applies.

The git lifecycle here (init → commit → subtree-add → bootstrap → publish) is
**identical for every OS repo** in the system. Only "Stage 0" below changes per
distro. When you stamp openSUSE / Alpine / Gentoo, copy this file and swap Stage
0; see [the porting note](#porting-this-doc-to-the-next-os-repo) at the bottom.

---

## Stage 0 — make a fresh/minimal box usable (as root)

A clean Arch install (manual, or ArchWSL on first launch) drops you at a **root**
prompt with no user, no `sudo`, and no `git`. `bootstrap.sh` clones nothing but
calls `sudo` everywhere, so none of it can run until you create a wheel user with
`sudo` and install `git`. Do this first, **as root**:

```bash
# ArchWSL only: stale bundled keys are the #1 first-run failure — refresh first
pacman -Sy archlinux-keyring

pacman -Syu                               # golden rule: full upgrade, never -Sy alone
pacman -S --needed git base-devel sudo    # git=clone, sudo=bootstrap, base-devel=AUR later

# generate a UTF-8 locale — a minimal Arch ships NONE, so you land in the C
# locale and bash prints raw \Uxxxx escapes instead of glyphs (the tmux
# netspeed icons are the first thing you'll notice). Do this once.
sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo 'LANG=en_US.UTF-8' > /etc/locale.conf   # applied at next login (WSL: after the Stage 3 restart)

useradd -m -G wheel -s /bin/bash <you>    # bash for now; bootstrap switches login shell to zsh
passwd <you>

# grant the wheel group sudo via a validated drop-in (no editor needed)
echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/10-wheel
chmod 440 /etc/sudoers.d/10-wheel
visudo -c                                 # must print "... parsed OK"

su - <you>                                # become your user for everything below
```

**Skip Stage 0** if your install already handed you a `sudo`-capable user —
`archinstall` and a pre-configured ArchWSL both do. On bare metal, also confirm
the clock (`timedatectl set-ntp true`) and network before the first `pacman`
call; on WSL both are inherited from Windows.

---

## Stage 1 — create the repo (order matters)

You arrive here with the OS-layer files already in `~/dotfiles-Arch`
(`bootstrap.sh`, `install/`, `os/`, `ssh/`, `wsl/`, `README.md`, `.gitignore`). For the
very first Arch repo those came from the provided archive — extract it into
`~/dotfiles-Arch`. For every subsequent distro you'll generate them by stamping
the Fedora template (see `PORTING-MATRIX.md` in `dotfiles-core`).

> **The one ordering rule that bites:** `git subtree add` performs a merge, which
> needs an existing `HEAD`. So you must `git init` **and make the first commit of
> the OS-layer files** *before* vendoring Core. And git won't commit at all until
> it has an identity. Hence the sequence below — don't reorder it.

```bash
cd ~/dotfiles-Arch

# 1. repo-local identity, just so the creation commits succeed. (This writes to
#    .git/config, which bootstrap never touches, so it survives. Your real,
#    everywhere identity gets wired into ~/.config/git/local.gitconfig by
#    bootstrap in Stage 2 — that's the file Core's gitconfig reads from.)
git init -b main
git config user.name  "<You>"
git config user.email "<you@example.com>"

# 2. commit the OS layer FIRST (creates the HEAD that subtree-add requires)
git add -A
git commit -m "Arch OS-native layer (stamped from Fedora template)"

# 3. NOW vendor Core as a squashed subtree under core/
git subtree add --prefix=core https://github.com/<you>/dotfiles-core main --squash
```

If `dotfiles-core` lives only on disk (not yet pushed), step 3 takes a path just
as happily: `git subtree add --prefix=core ~/dotfiles-core main --squash`.

---

## Stage 2 — bootstrap

```bash
./bootstrap.sh
```

It verifies `core/zsh` exists (Stage 1 step 3), does a full `pacman -Syu`,
installs `install/packages.txt`, symlinks Core + the Arch OS layer into
`~/.config` and `~`, seeds `~/.config/git/local.gitconfig`, clones tpm, and sets
zsh as your login shell. On WSL it also writes `/etc/wsl.conf` with you as the
default user.

Then put your real name/email into the seeded identity file (bootstrap reminds
you; it's never tracked):

```bash
$EDITOR ~/.config/git/local.gitconfig     # [user] name + email (+ signingkey if you sign)
```

---

## Stage 3 — apply WSL changes (WSL only)

`bootstrap.sh` wrote `/etc/wsl.conf`, but the default-user + systemd changes only
take effect on a restart. From a **Windows** terminal:

```powershell
wsl.exe --shutdown
```

Reopen Arch — you now land as your user, in zsh, with the prompt and tools live.
(`--shutdown` restarts *all* your WSL distros, not just this one.)

---

## Stage 4 — publish (optional)

Create an **empty** `dotfiles-Arch` repo on GitHub (no README/license — you
already have commits), then:

```bash
cd ~/dotfiles-Arch
git remote add origin git@github.com:<you>/dotfiles-Arch.git
git push -u origin main
```

---

## After setup

This box is now an ordinary consumer of the system. When Core changes, run
`./bin/sync-core.sh` from `dotfiles-core` to fan the update into this repo's
vendored `core/` (commit + push afterward), exactly like every other OS repo. To
re-link without touching packages: `./bootstrap.sh --links-only`.

---

## Porting this doc to the next OS repo

Copy this file into the new repo and change **only Stage 0** — Stages 1–4 are
distro-agnostic. The per-distro essentials:

| Distro | install prereqs | privilege tool + grant | create user |
|---|---|---|---|
| **Arch** | `pacman -S git base-devel sudo` | `sudo`, `/etc/sudoers.d/` | `useradd -m -G wheel` |
| **openSUSE** | `zypper in git-core sudo` | `sudo`, `/etc/sudoers.d/` | `useradd -m -G wheel` |
| **Alpine** | `apk add git doas` | **`doas`**, `/etc/doas.d/` (`permit persist :wheel`) | `adduser` + `addgroup` (busybox); default shell is `ash` |
| **Gentoo** | `emerge dev-vcs/git app-admin/sudo` | `sudo`, `/etc/sudoers.d/` | `useradd -m -G wheel` (expect emerge compile time) |

For the full package-manager command equivalents (refresh/upgrade/install/
search/owns-file) and package-name table, see `PORTING-MATRIX.md` in
`dotfiles-core`. Alpine is the real outlier — `doas` not `sudo`, `apk` not a
sync-DB manager, busybox `adduser` not `useradd`, musl not glibc — so its Stage 0
diverges the most.

**One more Stage-0 item for every distro: a UTF-8 locale.** A minimal **Arch**
or **Alpine** generates none, so you land in `C` and bash renders the tmux
status-bar glyphs as raw `\Uxxxx` escapes until you set one (Arch: edit
`/etc/locale.gen` → `locale-gen` → `/etc/locale.conf`; Alpine: `apk add
musl-locales` + set `LANG`, or use `C.UTF-8`). **openSUSE** and **Gentoo**
installers usually set a locale already — just verify with `locale` before
blaming your font. On WSL the locale applies on the Stage 3 restart.
