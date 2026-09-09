# Changelog

All notable changes to **dotfiles-Arch** are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

This repo carries **two version lines**, and they mean different things:

- **This repo's own `vX.Y.Z` tag**, cut automatically by `.github/workflows/auto-tag.yml`
  when a Core fan-out lands on `main`. That is what this file documents.
- **The vendored Core version**, recorded in [`core.lock`](core.lock) (`core_version` /
  `core_sha` / `core_tag`). Changes to Core are documented in `dotfiles-core`'s own
  CHANGELOG, not here — a `chore(core): core.lock → …` commit in this repo is a
  pointer, not an authored change.

Entries below therefore cover the **Arch OS-native layer only**: `bootstrap.sh`,
`install/packages.txt`, `os/`, `ssh/`, `wsl/`, and this repo's CI and meta files.

> **History note.** This file was introduced during a production-readiness audit,
> after `auto-tag.yml` had already cut the `v1.3.x` line. Tags prior to that point
> are not reconstructed here — `git log` remains the record for them.

## [Unreleased]

### Added

- **The README opens with a rendered terminal hero** (dotgibson/dotfiles-core#948).
  `assets/demo.gif` is filmed from `assets/demo.tape`, which dotfiles-core generates from
  one shared template for all nine OS and role repos — the same tour everywhere, plus the
  one command that is this repo's own: `up -n` resolving to `sudo pacman -Syu`. The tape
  is generated (edit dotfiles-core's `assets/hero.tape.in`, not the tape); re-render with
  `vhs assets/demo.tape` on an Arch box after a prompt or tooling change, then `gifsicle
  -O3 --lossy=80 --colors 64` — the raw render is over Core's 2 MiB ceiling, the optimised
  one is not.

- **The fleet `make` vocabulary, and a `test/` suite** (dotgibson/dotfiles-core#691,
  reported by dotgibson/dotfiles-core#846). Core declares one canonical set of verbs for
  every repo that vendors it — `help`, `lint`, `check`, `dry-run`, `packages-check`,
  `core-verify`, `test` — so the same word means the same thing in nine repos. This repo
  was missing three of them.
  - **`make dry-run`** is the canonical spelling of what was `make bootstrap-dry`.
    `bootstrap-dry` is kept as a `.PHONY` alias: the requirement is that the canonical
    name *exists*, not that the old one dies.
  - **`make check`** is the full local gate — `lint` + `test` + a `bootstrap.sh
    --dry-run` that proves the whole plan still builds, `provision()` included, which no
    workflow ever executes. Deliberately *not* the hermetic `HOME=$(mktemp -d)
    --links-only` run that Debian's and Fedora's `check` use: that is only hermetic in
    `$HOME`, since `wire_links` ends in `blib_set_login_shell`, which appends to
    `/etc/shells` and runs `chsh` under sudo. `--dry-run` reaches the same code with
    `BLIB_DRY=1` and writes nothing.
  - **`make test`** runs `test/*.sh`, and refuses rather than passing when there is
    nothing to run — a `test:` that runs no suite renders as a no-op in the fleet
    register.
  - **`test/check-packages.sh`** is the suite, modelled on
    `dotfiles-Debian/test/check-packages.sh`. It is the old inline `packages-check`
    recipe promoted to a real script — same parser (`blib_read_pkgs_into`, so it reads
    exactly what `bootstrap.sh` feeds pacman), same `pacman -Si` resolution, now
    shellcheck-visible and invokable by path — **plus** a duplicate-name check, which
    needs no package manager and so runs off-Arch too, and a clean skip instead of a hard
    "pacman not found" failure. It carries **no version floors**: Debian needs them
    because a frozen archive resolves `neovim` at 0.9.5 and calls that healthy, while on
    a rolling release the repos carry current upstream by construction — the drift risk
    here is names *moving* (`doggo` went AUR→extra in 2025) or disappearing.
  - `.github/workflows/packages.yml` now runs **`make test`** rather than `make
    packages-check`, and its path filter gained `test/**`. The floor requires a workflow
    that runs the *suite*; a workflow pinned to one target inside it would silently skip
    the second script anyone adds. `make packages-check` still runs exactly that script
    for anyone who types the verb.

- **`make markdown`, wired into `make lint`.** `lint-call.yml`'s markdown leg has been
  **blocking** since dotgibson/dotfiles-core#592, but this repo had no local target for
  it — a required check nobody could run before pushing, and a `.markdownlint.jsonc` only
  CI ever read. `MD_FILES` uses the gate's own pathspec
  (`git ls-files '*.md' ':!:core/**'`), so the local run scans exactly what CI scans,
  recursively — a `'*.md'` glob would be top-level only and miss
  `pull_request_template.md`. All seven files already pass, so nothing rides along.
  It **skips** when `markdownlint-cli2` is absent rather than failing like the shellcheck
  arm: shellcheck is a pacman package, so missing means a box to fix, while
  markdownlint-cli2 is npm-only. Part of the fleet sweep in dotgibson/dotfiles-core#775.

- **`os/arch.capabilities`** — this repo's Core v5 capability declaration
  (dotgibson/dotfiles-core#663, #667). Core's `up`, maint runner and `core-doctor` now
  dispatch through it rather than through package-manager branches inside portable Core
  modules. `PKG_COUNT_PENDING` is `checkupdates` (from `pacman-contrib`, already in
  `install/packages.txt`), which syncs a copy of the database in user space and never
  touches the real sync DB. **`PKG_ASSUME_YES`, `PKG_UPGRADE_PARTIAL` and
  `MAINT_UNATTENDED_UPGRADE` are deliberately absent**: each omission is a safety
  statement Core honours exactly, so `up -i` refuses a partial upgrade and the scheduled
  runner refuses to upgrade this rolling distro unattended. Do not add them.
- **`make capabilities`** — validates `os/*.capabilities` against Core's schema via the
  vendored `core/scripts/check-capabilities.sh`, and runs as part of `make lint`.
- **`bootstrap.sh --dry-run`** — previews the entire run (package plan + symlink
  plan + `/etc/wsl.conf` handling) and changes nothing. The shared library has
  supported `BLIB_DRY` end-to-end all along; this layer simply never exposed it.
- **Root `Makefile`** — `lint`, `bootstrap-dry`, `packages-check`, `secrets`,
  `core-lock`, `core-verify`. `lint` reproduces the CI gate exactly, so a failure
  is visible before pushing.
- **`packages` workflow** — resolves every `install/packages.txt` name against the
  Arch repos on PR and weekly, without installing. Nothing previously checked the
  package list, on a rolling release where renames are routine.
- **Root `.gitattributes`, `.editorconfig`, `.shellcheckrc`** — Core ships all
  three, but EditorConfig/shellcheck/gitattributes resolution is directory-scoped,
  so they governed `core/**` only and this repo's own files had no policy.
- **`CODEOWNERS`, `pull_request_template.md`, `SECURITY.md`, and this file.**

### Fixed

- **The tmux auto-attach honours `DOTFILES_NO_AUTOTMUX`, the fleet's one opt-out name**
  (dotgibson/dotfiles-core#877). MacBook, openSUSE and Gentoo already read it; this layer
  attached unconditionally for any interactive TTY, which is how dotfiles-core's README hero
  render — a vhs session that sources this layer — typed its whole tour into a fresh `main`
  session. Core's `gen-hero-tape.sh` now refuses to render a hero on a layer that does not
  honour the knob. Export `DOTFILES_NO_AUTOTMUX=1` for any harness that drives an interactive
  zsh and must not land in tmux.

- **`make markdown` probed for a global, unpinned `markdownlint-cli2` — so on a normal box it
  never linted anything** (dotgibson/dotfiles-core#873). Nothing in this repo's bootstrap
  installs `markdownlint-cli2` globally; it is npm-only. So unless the operator had
  separately run `npm i -g markdownlint-cli2`, the guard fired on every invocation and the
  target skipped, cleanly and with exit 0, forever. That is a correct guard doing exactly
  what it says — and a local mirror of a **blocking** CI gate that has never mirrored
  anything. dotgibson/dotfiles-core#775 fixed this target's skip guard and its file scope;
  neither defect could bite while the target never ran at all. And where the binary *was*
  installed it was whatever version npm last put there, while `lint-call.yml` installs the
  pinned `MARKDOWNLINT_VERSION` — so a rule that changes across a bump reds a required check
  against a green local run. It now runs the **pinned** version through `npx`, reading the
  number from the vendored `core/scripts/tool-versions.env` rather than restating it, and
  **refuses** rather than guess if that pin is unreadable — a silently-unpinned lint being
  the thing this fixes. `npx` needs only node, which is far likelier present than a global
  markdownlint install, and still self-skips without it so `make lint` works on a bare box.
  Converges on the shape `dotfiles-Offense` and `dotfiles-Defense` already run.
- **`bootstrap.sh`'s `PATH` is not the shell's `PATH` — adopt `blib_user_bindirs_on_path`**
  (dotgibson/dotfiles-core#748). `go install` pins `GOBIN` to `~/.local/bin`, and `~/.local/bin`, `~/.cargo/bin` and `$GOBIN` reach
  `PATH` only through the zsh layer, i.e. only inside a Core shell — which does not exist
  while `bootstrap.sh` runs. So every `command -v <tool>` guard here was answered by the
  PATH of whatever shell launched the bootstrap: on a fresh box, bash, with none of them.
  That is wasted work when the guard picks whether to reinstall, and a **wrong answer** when
  it picks a branch — `dotfiles-openSUSE` probed `command -v mise` for a mise `mise.run` had
  written to `~/.local/bin` moments earlier, both arms of its Go fallback missed, and the run
  exited 2 on every bootstrap. No stubbed CI leg can see that: a stub installs nothing, so
  "is the tool present afterwards" can never fail under one. Core has shipped
  `blib_user_bindirs_on_path` for exactly this since dotgibson/dotfiles-core#425 — it resolves
  `CARGO_HOME` and `GOBIN`/`GOPATH` rather than hard-coding them, and adds only directories
  that **exist**, so it is called again after an installer creates one. Arch escapes the worse half of this by luck — pacman puts `mise` in `/usr/bin`, so the fallback arm resolves — but `_dotfiles_go_install`'s presence guard could never see a tool an earlier run had installed, so every bootstrap re-ran every `go install`.
- **`bootstrap.sh` could exit 0 having installed nothing.** `blib_read_pkgs`'
  exit status is lost inside the `< <(…)` process substitution, so a missing or
  empty `install/packages.txt` produced an empty array, a failed `pacman -S`, a
  zero-iteration fallback loop, and a success message. It now refuses to continue.
- **`bootstrap.sh` silently swallowed per-package install failures.** The fallback
  loop discarded every error, so a handful of renamed packages yielded a green run
  and a half-provisioned machine. Failures are now collected, reported at the end,
  and produce a non-zero exit — after wiring completes, so the box is still usable.
- **`bootstrap.sh` clobbered an existing `/etc/wsl.conf`.** Every other mutation in
  this system backs up first (`blib_link` → `.pre-dotfiles.<epoch>`); this one
  overwrote, losing any local `[automount]` / `[boot]` / `[network]` settings on a
  re-run of a script documented as idempotent. It now no-ops when already correct
  and backs up otherwise.
- **`pacorphans` passed all orphans to pacman as a single argument.** zsh does not
  word-split unquoted parameters, so `pacman -Rns $orphans` handed over one
  newline-joined string; now `${(f)orphans}`. `zsh -n` cannot catch this — the
  syntax is valid.
- **`--help` was coupled to the file's header line numbers** (`sed -n '2,17p' "$0"`),
  so editing the banner silently drifted the help text. Replaced with a `usage()`
  heredoc, matching the fix `core/scripts/sync-core.sh` already documents.
- **Stale `.gitignore` entry** `zsh/local.zsh` — a pre-v4 path that does not exist
  in this repo. Added credential, `.envrc`/`.direnv` and key-material patterns
  (`direnv` is installed by `packages.txt` and hooked into every shell).

### Changed

- **`make core-lock` no longer regenerates `core.lock`; it explains why and points at the
  fan-out.** (dotgibson/dotfiles-core#593) The target was added here to satisfy
  `core.lock`'s own header instruction, “Regenerate … with: `make core-lock`”. That
  instruction was the bug — Core removed it in dotfiles-core#454, because `core.lock` is
  written by `sync-core.sh` in the same commit as the subtree pull and was never meant to
  have a second writer.

  Keeping the generator meant this repo owned a second definition of a format Core owns,
  and it had already drifted from it in three ways: it hardcoded `core_branch=main`, so
  regenerating a lock that had been pinned to a released commit silently replaced that
  provenance with a branch name; it re-emitted the removed header line, reintroducing the
  very instruction it existed to satisfy; and it predates dotfiles-core#453, which renamed
  the field to `core_ref` — so running it now would emit a lock the rest of the fleet
  disagrees with.

  `core-verify` is unchanged and remains the way to check this repo's vendored `core/`.

- **Privilege escalation goes through the library's `_blib_priv`**, honouring
  `BLIB_SU`, instead of a hardcoded `sudo`. This makes `bootstrap.sh` work as root
  and on `doas`-only boxes — and makes `provision()` runnable in a container, which
  Arch base images (no `sudo`) previously prevented.
- **Arch derivatives are accepted with a warning** rather than refused: the guard
  now falls back to `ID_LIKE=…arch…`, so EndeavourOS/Manjaro/CachyOS work.
- **`go install` for sesh logs its errors** to a file instead of `/dev/null`, and
  the module version is overridable via `SESH_VERSION` (still defaulting to
  `latest` — see the note in `provision()`). carapace is a printed `paru` hint and
  takes no version override, per the analysis in
  [#89](https://github.com/dotgibson/dotfiles-Arch/pull/89): `go install` cannot
  work for any version of it. That error logging is what makes such a failure
  visible in the first place — the old `/dev/null` form is precisely why the
  carapace call could fail on every bootstrap without anyone noticing.
- **A failed run now says where it failed** (`ERR` trap), and a successful one
  prints the wiring tally and points at `core-doctor`.
- **`bootstrap.sh` installs the local `core/` pre-commit guard** on a fresh clone
  (`blib_install_core_guard`), catching a hand-edit at commit time rather than
  waiting for `core-integrity.yml` at PR time.
