# CLAUDE.md — dotfiles-Arch

Project memory for Claude Code, auto-loaded every session. For the shared Core
rules (the load order, the "is it Core?" test, the manifest contract) see
`core/README.md` and `core/CONTRIBUTING.md`.

## What this repo is

`dotfiles-Arch` is the **OS-native layer for Arch Linux** in a **ten-repo dotfiles system** built on a three-layer
model (Core → OS-native → Role). Arch is stamped from the Fedora template (see `core/PORTING-MATRIX.md`). Rolling release — never `pacman -Sy <pkg>` without `-u`; partial upgrades break things. Most tools are in the official repos, the rest one `paru -S` away in the AUR.

## The rule that bites

`core/` is a **vendored `git subtree` copy of [dotfiles-core](https://github.com/Gerrrt/dotfiles-core)** — it
is *not* editable here. Anything you change under `core/` is overwritten on the
next sync. To change shared Core config, edit it **in dotfiles-core**, run
`make audit` there, then `make sync` to fan it out to every OS repo.

What belongs **here** is only the OS-native layer: the `pacman`/AUR package list, clipboard + paths, and the bootstrap.

## Where things are

- `os/arch.zsh` — clipboard + package-manager aliases for Arch
- `os/arch.conf`, `os/arch.gitconfig` — tmux + git OS overlays
- `install/packages.txt` — Arch package names
- `bootstrap.sh` — symlinks Core + OS files into place
- `SETUP.md` — the Arch install walkthrough
- `core/` — vendored Core (read-only here; edit upstream in dotfiles-core)
