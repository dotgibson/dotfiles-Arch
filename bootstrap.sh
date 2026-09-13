#!/usr/bin/env bash
# dotfiles-Arch/bootstrap.sh
# ──────────────────────────────────────────────────────────────────────────────
# Provision an Arch Linux box (desktop or WSL/ArchWSL) and wire up dotfiles.
# Idempotent — safe to re-run. This is the OS-NATIVE layer; Core (zsh/tmux/nvim/
# git) is vendored under core/ and symlinked in via core/lib/bootstrap-lib.sh.
#
# Run `./bootstrap.sh --help` for usage — see usage() below, which is the single
# definition (deliberately NOT `sed -n '2,17p' "$0"`: that form couples --help to
# this banner's line numbers, so editing the header silently drifts the help text.
# core/scripts/sync-core.sh records the same fix for the same reason.)
# ──────────────────────────────────────────────────────────────────────────────
# `-E` (errtrace) so the ERR trap below fires inside functions too, not just at
# the top level — without it a failure inside provision() aborts with no context.
set -eEuo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
LINKS_ONLY=0
DO_FLATPAK=1
# Packages and tools that could not be installed are recorded in Core's ledger
# (blib_note_fail, core/lib/bootstrap-lib.sh) so the run can finish wiring the box and
# THEN report honestly + exit non-zero. Half-provisioning silently (the old behaviour) is
# the worse failure: you get a green run and a machine missing tools you only discover
# days later. The ledger also holds what the shared lib records itself (the tpm clone).

usage() {
  cat <<'EOF'
bootstrap.sh — provision an Arch box (desktop or WSL/ArchWSL) and wire up dotfiles.

  ./bootstrap.sh                 full: pacman packages + extras + symlinks
  ./bootstrap.sh --links-only    just (re)create symlinks (no pacman)
  ./bootstrap.sh --dry-run       preview EVERYTHING, change nothing
  ./bootstrap.sh --no-flatpak    skip Flathub/GUI apps (recommended on WSL)
  ./bootstrap.sh --only zsh,nvim link ONLY these Core module groups
  ./bootstrap.sh --skip tmux     link everything EXCEPT these groups
  ./bootstrap.sh -h, --help      show this help and exit

Module groups (for --only/--skip): zsh nvim tmux git prompt tools
  They affect the WIRING steps only, never package provisioning. Combine with
  --links-only to re-wire a subset of configs without touching pacman. If both
  --only and --skip are given, --only wins (it is an allowlist).

Env overrides:
  BLIB_SU     privilege escalator. Resolved by Core's blib_resolve_su when unset:
              root runs directly, else sudo, else doas. Set it empty or to `doas`
              to override the probe.
  BLIB_DRY    set to 1 for the same effect as --dry-run
  SESH_VERSION
              Go module version for sesh, the one tool built from source here
              (default: latest — see the note in provision())
EOF
}

# --only/--skip are validated by the shared lib (blib_select), sourced AFTER this
# loop — capture the raw values now and apply them below.
ONLY_RAW=""; SKIP_RAW=""; ONLY_SEEN=0; SKIP_SEEN=0

while [[ $# -gt 0 ]]; do case "$1" in
  --links-only) LINKS_ONLY=1 ;;
  --dry-run | -n) BLIB_DRY=1 ;;
  --no-flatpak) DO_FLATPAK=0 ;;
  --only) [[ $# -ge 2 ]] || { echo "--only requires module names, e.g. --only zsh,nvim" >&2; exit 1; }; ONLY_RAW="$2"; ONLY_SEEN=1; shift ;;
  --only=*) ONLY_RAW="${1#*=}"; ONLY_SEEN=1 ;;
  --skip) [[ $# -ge 2 ]] || { echo "--skip requires module names, e.g. --skip tmux" >&2; exit 1; }; SKIP_RAW="$2"; SKIP_SEEN=1; shift ;;
  --skip=*) SKIP_RAW="${1#*=}"; SKIP_SEEN=1 ;;
  -h | --help) usage; exit 0 ;;
  *) echo "unknown arg: $1" >&2; echo "try: $0 --help" >&2; exit 1 ;;
esac; shift; done

# BLIB_DRY must exist before the lib is sourced (the lib reads it with :- defaults,
# so this is belt-and-braces) and is exported so anything we shell out to agrees.
export BLIB_DRY="${BLIB_DRY:-0}"

# ── vendored core/ present? (inline: can't source a lib out of core/ before this) ─
# Validate the SPECIFIC paths we depend on (zsh modules + the two libs sourced
# next) so a missing/partial vendor fails HERE with a precise message, not later
# with a cryptic `source: No such file`.
for _req in core/zsh/loader.zsh core/lib/ux.sh core/lib/bootstrap-lib.sh; do
  if [[ ! -e "$DOTFILES/$_req" ]]; then
    echo "vendored core/ missing or incomplete (need $_req). To populate it:" >&2
    echo "  make sync                                                          # in dotfiles-core" >&2
    echo "If core/ does not exist AT ALL, the fan-out skips this repo — do the" >&2
    echo "one-time vendor first (a RELEASED TAG, never main), then sync:" >&2
    echo "  git subtree add --prefix=core <dotfiles-core remote> refs/tags/v7 --squash" >&2
    exit 1
  fi
done
unset _req

# Shared bash UX palette + provisioning scaffold (vendored under core/lib).
# shellcheck source=core/lib/ux.sh
source "$DOTFILES/core/lib/ux.sh"
# shellcheck source=core/lib/bootstrap-lib.sh
source "$DOTFILES/core/lib/bootstrap-lib.sh"

# ── PATH prelude: make the presence guards below tell the TRUTH ───────────────
# bootstrap runs in BASH, before any Core shell exists. ~/.local/bin (this script's GOBIN)
# and ~/.cargo/bin reach PATH only via core/zsh/00-tools.zsh and os/arch.zsh, i.e. only
# inside a Core zsh — so `command -v <tool>` here was answered by the PATH of whatever
# shell launched the bootstrap, which on a fresh box is bash with none of them.
#
# Concretely: _dotfiles_go_install's `command -v "$3"` guard could never see a tool an
# EARLIER run had installed into ~/.local/bin, so every bootstrap re-ran every go install.
# Arch escapes the worse half of this only by luck — pacman puts mise in /usr/bin, so the
# `command -v mise` fallback arm resolves. The repos where mise comes from mise.run instead
# had that arm silently fail against a mise they had just installed, and openSUSE shipped a
# bootstrap that exited 2 on every run because of it (dotgibson/dotfiles-core#748).
#
# blib_user_bindirs_on_path is Core's helper for exactly this (core/lib/bootstrap-lib.sh),
# resolving CARGO_HOME and GOBIN/GOPATH rather than hard-coding them. It adds only
# directories that EXIST, so on a box whose ~/.local/bin is first created by the go
# installs themselves it takes effect from the next run — which is precisely the run that
# was doing the redundant work.
blib_user_bindirs_on_path

# Fail LOUD and located. Under `set -e` a mid-run failure used to abort with no
# indication of where — on a fresh box, mid-`pacman`, that is the difference
# between "retry the one step" and "start over".
#
# The BASH_SUBSHELL guard is load-bearing, not defensive: `-E` propagates this trap
# into command/process substitutions, and a perfectly normal `read` returning 1 at
# EOF inside blib_read_pkgs' while-loop runs in the `< <(…)` subshell. Without the
# guard every single run printed a spurious "bootstrap FAILED … IFS= read -r line".
# Only the main shell can actually be failing the bootstrap.
_bootstrap_err() {
  local rc="$1" line="$2" cmd="$3"
  ((BASH_SUBSHELL > 0)) && return 0
  blib_warn "bootstrap FAILED (exit $rc) at ${BASH_SOURCE[0]}:${line}: ${cmd}"
  exit "$rc"
}
trap '_bootstrap_err "$?" "$LINENO" "$BASH_COMMAND"' ERR

# Apply any --only/--skip module selection now the validator (blib_select) exists;
# it aborts on a malformed selector or an unknown group.
if ((ONLY_SEEN)); then blib_select --only "$ONLY_RAW"; fi
if ((SKIP_SEEN)); then blib_select --skip "$SKIP_RAW"; fi
# blib_want treats --only as an allowlist that WINS, so a --skip alongside it is
# silently inert. Say so rather than letting the user believe both applied.
if ((ONLY_SEEN)) && ((SKIP_SEEN)); then
  blib_warn "both --only and --skip given: --only is an allowlist and WINS; --skip '$SKIP_RAW' is ignored"
fi

# ── sanity: confirm we're on Arch ─────────────────────────────────────────────
# Match the ID line specifically so we don't false-positive on a distro that
# merely mentions "arch" in its NAME/pretty string. (ArchWSL keeps ID=arch.)
# Arch DERIVATIVES (EndeavourOS, Manjaro, CachyOS) set their own ID but carry
# ID_LIKE=arch and a working pacman, so they are accepted with a warning rather
# than refused — the package list and every alias in os/arch.zsh still apply.
if ! grep -qE '^ID=arch$' /etc/os-release 2>/dev/null; then
  if grep -qE '^ID_LIKE=.*\barch\b' /etc/os-release 2>/dev/null; then
    blib_warn "not Arch proper, but ID_LIKE=arch (a derivative) — continuing; packages.txt assumes Arch repo names"
  else
    echo "This bootstrap targets Arch Linux. /etc/os-release doesn't look like Arch (no 'ID=arch' or 'ID_LIKE=...arch...')." >&2
    exit 1
  fi
fi

# ── privilege escalation: Core's blib_resolve_su, not a default of `sudo` ─────
# Decides "root" from $EUID, pins the ABSOLUTE path of sudo or doas, and honours an
# explicit BLIB_SU= from the caller — which is what core's bootstrap-test.yml sets, since
# Arch base images ship no sudo. --require only when packages will actually be installed:
# wiring symlinks and a dry run need no privileges. Everything privileged below then goes
# through blib_priv, the lib's PUBLIC wrapper over the same value.
if ((LINKS_ONLY)) || ((BLIB_DRY)); then
  blib_resolve_su || true
else
  blib_resolve_su --require || exit 1
fi

IS_WSL=0
if blib_is_wsl; then IS_WSL=1; fi

provision() {
  # ── Arch golden rule: NEVER partial-upgrade ────────────────────────────────
  # `pacman -Sy <pkg>` (refresh without -u) is the classic Arch footgun: it can
  # pull a package built against newer libs than your unupgraded system has. The
  # correct pattern is a full `-Syu` FIRST so the box is current before installs.
  #
  # Privilege goes through the lib's blib_priv (its public name for the wrapper), NOT
  # a hardcoded `sudo`: it runs under the BLIB_SU that blib_resolve_su pinned above, so
  # this works as root (BLIB_SU=) and on a doas-only box. It is also what makes
  # provision() runnable in a container — Arch base images ship no sudo, which is
  # exactly why core's bootstrap-test.yml has to set BLIB_SU= before invoking this script.

  local -a pkgs=()
  mapfile -t pkgs < <(blib_read_pkgs "$DOTFILES/install/packages.txt")
  # blib_read_pkgs' exit status is LOST inside the process substitution, so a
  # missing or empty packages.txt yields an empty array rather than an error. Left
  # unchecked, `pacman -S` with zero targets fails, the per-package fallback loops
  # zero times, and the run reports success having installed NOTHING. Fail here.
  if ((${#pkgs[@]} == 0)); then
    blib_warn "no packages parsed from $DOTFILES/install/packages.txt (missing, empty, or all comments) — refusing to continue"
    exit 1
  fi

  if _blib_dry; then
    blib_say "would run: pacman -Syu, then install ${#pkgs[@]} packages from install/packages.txt"
    blib_say "would install: ${pkgs[*]}"
    # Spelled as `if` blocks, not `((x)) && say …`: under `set -e` + the ERR trap a
    # false guard makes the whole && list return non-zero, which is exactly the kind
    # of "failed but harmless" status this script now reports loudly.
    if ((IS_WSL)); then install_wsl_conf; fi
    if ((DO_FLATPAK)) && ! ((IS_WSL)); then blib_say "would add the Flathub remote"; fi
    return 0
  fi

  # Core's sudo keepalive: prime once with the prompt visible, refresh in the background
  # so the go builds below cannot leave a later `sudo` blocked at an invisible prompt.
  # A no-op for doas and for root. This function owns the EXIT trap that stops it.
  trap 'blib_sudo_keepalive_stop' EXIT
  blib_sudo_keepalive_start || {
    echo "sudo authentication failed — cannot provision packages." >&2
    exit 1
  }

  blib_say "pacman full system sync + upgrade (-Syu)"
  blib_priv pacman -Syu --noconfirm

  blib_say "pacman packages (${#pkgs[@]} from install/packages.txt)"
  # Unlike dnf's --skip-unavailable, pacman aborts the WHOLE transaction if any
  # single target name is wrong. Try the bulk install with --needed (skips
  # already-installed), and on failure fall back to a per-package loop so one bad
  # name can't sink the rest. (System is current from -Syu, so -S is not partial.)
  if blib_priv pacman -S --needed --noconfirm "${pkgs[@]}"; then
    blib_ok "pacman packages installed (${#pkgs[@]} requested)"
  else
    blib_say "bulk install hit a snag — retrying package-by-package (resilient)"
    local p
    for p in "${pkgs[@]}"; do
      # Record rather than discard. Arch is a ROLLING release: packages get
      # renamed and dropped between runs, and a silently-skipped name is how a
      # box ends up missing a tool with a green bootstrap behind it.
      blib_priv pacman -S --needed --noconfirm "$p" ||
        blib_note_fail "package '$p' — did not install; on a rolling release that usually means a rename or a drop: pacman -Ss $p"
    done
    if (($(blib_failed_count))); then
      blib_warn "$(blib_failed_count) package(s) failed to install (see the summary at the end)"
    else
      blib_ok "per-package install pass complete (all succeeded)"
    fi
  fi

  # NOTE (vs Fedora): starship, atuin, yazi, mise, lazygit are ALL in Arch's
  # official repos (extra), so they live in packages.txt — no upstream-installer
  # block here. That's the Arch payoff: one package manager, no curl|sh fallbacks.

  # ── the few core-doctor tools NOT in the official repos (AUR / Go) ──────────
  # carapace, sesh and op are all absent from Arch's official repos (doggo moved into
  # `extra` — it's in packages.txt now), and this bootstrap deliberately builds NO AUR
  # helper (paru is a documented manual step below). What that means differs per tool,
  # so they are handled three different ways rather than one:
  #   • sesh     — has a working Go route, so it is built from source below: best-effort,
  #                never fatal under `set -e`. The AUR `sesh-bin` is not needed.
  #   • carapace — has NO Go route at all, for any version (see its block below), so it is
  #                a printed `paru` hint instead, like viddy and op.
  #   • op       — proprietary, no Go route either; printed hint.
  # If you already run paru, the native route for all three is:
  #   paru -S carapace-bin sesh-bin 1password-cli
  # NOTE: `go install` drops binaries in $GOBIN (defaults to ~/go/bin), which is
  # NOT on the shell PATH (the Core shell layer prefixes ~/.local/bin + ~/.cargo/
  # bin). Pin GOBIN=~/.local/bin so the tools land somewhere already on PATH —
  # including THIS script's PATH, which the prelude at the top now covers too.
  #
  # VERSION: sesh defaults to `latest`, which is NOT reproducible — a re-run six
  # months from now installs different code. Core pins and SHA-256-verifies every
  # tool it downloads (core/scripts/tool-versions.env); this path cannot reuse that
  # machinery because it builds from source rather than fetching a release asset.
  # Pin deliberately by exporting SESH_VERSION (e.g. v2.19.0), or prefer the AUR
  # route above, which is version-controlled by the PKGBUILD. (There is no
  # CARAPACE_VERSION: carapace has no working Go route at any version — see below.)
  local go_log="${TMPDIR:-/tmp}/dotfiles-go-install.$$.log"
  _dotfiles_go_install() { # <import-path> <version> <binary-name>
    [ "$#" -ge 3 ] || return 0
    if command -v "$3" >/dev/null 2>&1; then return 0; fi
    local gobin="$HOME/.local/bin" spec="$1@$2"
    mkdir -p "$gobin" 2>/dev/null || true
    # Errors go to a LOG, not /dev/null. The old form suppressed stderr entirely,
    # so a compile failure surfaced only as a one-line "retry later" hint with no
    # way to find out why it failed.
    if command -v go >/dev/null 2>&1; then
      GOBIN="$gobin" go install "$spec" >>"$go_log" 2>&1 ||
        blib_note_fail "$3 — go install failed; see $go_log; retry: GOBIN=$gobin go install $spec"
    elif command -v mise >/dev/null 2>&1; then
      GOBIN="$gobin" mise exec go@latest -- go install "$spec" >>"$go_log" 2>&1 ||
        blib_note_fail "$3 — go install failed; see $go_log; retry: GOBIN=$gobin go install $spec"
    else
      blib_note_fail "$3 — needs Go; install later with: GOBIN=$gobin go install $spec"
    fi
    return 0
  }
  blib_say "core-doctor extras not in Arch repos (best-effort via Go)"
  # /v2 module path is required for sesh
  _dotfiles_go_install github.com/joshmedeski/sesh/v2 "${SESH_VERSION:-latest}" sesh
  # carapace is AUR-only here, and — unlike sesh — CANNOT be go-installed at all. Two
  # independent blockers, both properties of how the module is built rather than a break
  # to wait out. core/PORTING-MATRIX.md's carapace footnote ²⁷ — vendored in this tree —
  # carries the full story and the evidence. The blockers:
  #   1. Its go.mod carries `replace` directives, and `go install pkg@version` refuses any
  #      module that does, because a replace would make the build differ from building it
  #      as the main module.
  #   2. The generated sources (pkg/{actions,conditions}/*_generated.go) are not committed;
  #      cmd/carapace/main.go's `go:generate` lines produce them.
  # Checked across the whole tag history: 184 of 184 tags (v0.0.3 2020-08-31 → v1.7.3
  # 2026-06-30) carry a `replace`, and 0 commit the generated sources — so pinning an older
  # @version does not help either. The old `_dotfiles_go_install ...carapace@latest` call
  # here therefore failed on EVERY bootstrap, invisibly — at the time the helper discarded
  # the explanation to /dev/null (it writes to a log now, but the call is gone either way)
  # — and the run just never produced a carapace.
  #
  # A hint rather than an install, deliberately — and Arch is the one target where that is
  # the RIGHT answer rather than a concession. Elsewhere in the fleet (Fedora/openSUSE/Debian)
  # bootstrap installs upstream's release artifact, accepting that nothing then upgrades it.
  # Here a real, upgradable package exists (AUR `carapace-bin`, which repackages that same
  # upstream tarball and which `paru -Syu` refreshes), so lifting the binary out of the
  # tarball by hand would be strictly worse: it lands in ~/.local/bin, which the Core shell
  # layer puts AHEAD of /usr/bin, so a later `paru -S carapace-bin` would be silently
  # shadowed by the stale hand-placed copy forever. Printing the hint keeps the one good
  # path good. Same shape as viddy and op below.
  #
  # `carapace-bin` is the package to name, not `carapace`: the AUR carries both, and the
  # bare `carapace` is a from-source build (x86_64 only, makedepends=go, and its build()
  # runs the same `go generate` dance). `carapace-bin` provides/conflicts `carapace`, covers
  # x86_64/aarch64/i686, and just installs the prebuilt binary.
  if ! command -v carapace >/dev/null 2>&1; then
    echo "   carapace: not found — install the AUR 'carapace-bin' pkg (e.g. 'paru -S carapace-bin') for shell completions. NOT 'go install': impossible for any version — see core/PORTING-MATRIX.md's carapace footnote"
  fi
  # viddy (watch->viddy alias, HAVE_VIDDY-guarded) is a Rust CLI, AUR-only on Arch. This
  # bootstrap builds no AUR helper and installs no rust toolchain (see packages.txt), so
  # it's a manual step — like op below:
  #   paru -S viddy      (or, with a rust toolchain: cargo install viddy)
  if ! command -v viddy >/dev/null 2>&1; then
    echo "   viddy: not found — install the AUR 'viddy' pkg (e.g. 'paru -S viddy')" \
         "for the watch replacement, or 'cargo install viddy' with a rust toolchain"
  fi
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
    install_wsl_conf
  fi

  if ((DO_FLATPAK)) && ! ((IS_WSL)); then
    blib_say "Flathub"
    flatpak remote-add --if-not-exists flathub \
      https://flathub.org/repo/flathub.flatpakrepo >/dev/null 2>&1 ||
      blib_note_fail "Flathub remote — could not be added; retry: flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo"
  fi

  # ── Optional, NOT automated (documented manual steps) ──────────────────────
  #  • multilib (32-bit / Wine): uncomment [multilib] in /etc/pacman.conf, then -Syu.
  #  • AUR helper: build paru once (sudo pacman -S --needed base-devel git; then
  #    git clone https://aur.archlinux.org/paru.git && makepkg -si).
  #  • Fastest mirrors: sudo reflector --latest 20 --sort rate --save /etc/pacman.d/mirrorlist
}

# ── /etc/wsl.conf, written NON-DESTRUCTIVELY ──────────────────────────────────
# This used to be a bare `sed … | sudo tee /etc/wsl.conf`, which clobbered whatever
# was there. Every other mutation in this system backs up first (blib_link moves a
# real file to <dst>.pre-dotfiles.<epoch>), and bootstrap.sh is documented as safe
# to re-run — so a user who had added [automount], [boot] command=, or a hostname
# lost it silently on the second run. Now: no-op when already correct, back up
# otherwise.
install_wsl_conf() {
  local user rendered current="" backup
  user="$(id -un)"
  # Bash string replacement, NOT sed: the username is DATA, and in a sed
  # replacement `&` expands to the whole match and `\` escapes — so a username
  # containing either would be silently mangled. `${var//pat/rep}` has no such
  # metacharacters.
  rendered="$(cat "$DOTFILES/wsl/wsl.conf")"
  rendered="${rendered//__WSL_USER__/$user}"

  [[ -r /etc/wsl.conf ]] && current="$(cat /etc/wsl.conf)"
  if [[ "$current" == "$rendered" ]]; then
    blib_ok "/etc/wsl.conf already current — left alone"
    return 0
  fi

  if _blib_dry; then
    if [[ -e /etc/wsl.conf ]]; then
      blib_say "would back up + rewrite /etc/wsl.conf (default user: $user)"
    else
      blib_say "would write /etc/wsl.conf (default user: $user)"
    fi
    return 0
  fi

  blib_say "installing /etc/wsl.conf (systemd + default user)"
  if [[ -e /etc/wsl.conf ]]; then
    backup="/etc/wsl.conf.pre-dotfiles.$(date +%s)"
    blib_priv cp -a /etc/wsl.conf "$backup"
    blib_warn "existing /etc/wsl.conf backed up to $backup — re-apply any local settings from it"
  fi
  printf '%s\n' "$rendered" | blib_priv tee /etc/wsl.conf >/dev/null
  blib_ok "wsl.conf written — run 'wsl.exe --shutdown' from Windows, then reopen, to apply"
}

wire_links() {
  # The shared symlink surface + the Arch OS overlays + the managed .zshrc loader
  # + the default-login-shell switch all live in core/lib/bootstrap-lib.sh.
  blib_link_core "$DOTFILES" "$CONFIG"
  blib_link_os_layer "$DOTFILES" "$CONFIG" arch
  # shellcheck disable=SC2119  # no args is intentional — writes the default module set
  blib_write_zshrc_loader
  blib_set_login_shell
  # Install the local pre-commit hook that refuses commits touching the
  # vendored core/. core-integrity.yml catches this at PR time; this catches it at
  # COMMIT time, on a fresh clone, before the mistake is ever pushed. Never fatal:
  # the helper returns non-zero when it can't resolve a hooks dir, and a missing
  # guard must not fail a bootstrap.
  _blib_dry || blib_install_core_guard "$DOTFILES" || true
  blib_ok "symlinks wired$(blib_selected_note)"
  blib_wire_summary
}

if ((LINKS_ONLY == 0)); then
  provision
  blib_sudo_keepalive_stop
fi
wire_links

# ── final report ──────────────────────────────────────────────────────────────
if _blib_dry; then
  blib_ok "dry run complete — nothing was changed. Re-run without --dry-run to apply."
  exit 0
fi

# blib_failures_report prints the ledger (packages, go installs, Flathub, and what the
# shared lib recorded itself) and returns non-zero when there was anything in it. The
# box is WIRED by now; exit 1 is the honest answer, as it always was here.
if ! blib_failures_report; then
  blib_warn "on a rolling release a package that did not install usually means a rename or a drop — check with"
  blib_warn "  pacman -Ss <name>   /   https://archlinux.org/packages/  and update install/packages.txt"
  exit 1
fi

blib_ok "Arch bootstrap complete — open a new shell or: exec zsh"
blib_say "then verify with:  core-doctor    (and  core-version  for the vendored Core)"
