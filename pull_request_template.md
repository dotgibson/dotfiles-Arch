<!-- This is the Arch OS-NATIVE layer. The shared Core lives in dotfiles-core and
     is vendored here read-only under core/ — see the boundary check below. -->

## What & why

<!-- One or two lines. What changed in the Arch layer, and why. -->

## Boundary check

- [ ] I did **not** hand-edit `core/` (it is a vendored copy of `dotfiles-core`,
      overwritten on the next `make sync`; fix it upstream, then fan out)
- [ ] The change is genuinely **Arch-specific** — if it would be identical on every
      distro it belongs in Core; if it changes with the operator it belongs in a role repo

## Checks

- [ ] `make lint` is green (same shellcheck/`bash -n`/`zsh -n` gate CI runs)
- [ ] `make test` is green (the `test/` suite; `make check` runs lint + test + a
      bootstrap dry-run in one go)
- [ ] If `install/packages.txt` changed: `make packages-check` resolves every name
- [ ] If `bootstrap.sh` changed: `./bootstrap.sh --dry-run` previews correctly, and
      the change was exercised on a real Arch box or container (CI covers
      `--links-only` and a stubbed `bootstrap_provision()`, never a real install)
- [ ] `CHANGELOG.md` updated under `[Unreleased]` for any user-visible change,
      with a [Conventional Commits](https://www.conventionalcommits.org/) message

## Arch-specific gotchas

<!-- Delete what does not apply. -->

- [ ] No `pacman -Sy <pkg>` was introduced anywhere (partial-upgrade footgun — the
      only sanctioned `-Sy` in this repo is the `archlinux-keyring` refresh in SETUP.md)
- [ ] Anything AUR-only is a documented `paru -S …` hint, not an automated build

## Notes

<!-- Anything reviewers should know: WSL vs bare-metal implications, follow-up sync, etc. -->
