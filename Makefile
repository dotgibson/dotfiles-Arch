# Makefile — a discoverable façade over this repo's entry points.
# ──────────────────────────────────────────────────────────────────────────────
# Mirrors dotfiles-core/Makefile in spirit: it adds NO logic of its own beyond
# reproducing, verbatim, what CI already runs — so `make lint` == the `lint /
# shell lint` job, and a contributor stops finding out about a failure only after
# pushing. Before this file existed the repo had no local commands at all, which
# also made core.lock's own header ("Regenerate … with: make core-lock") false. That
# header was itself the bug: dotfiles-core#454 removed it, and core-lock here is now a
# redirect rather than a second generator of a format Core owns (dotfiles-core#593).
#
# Core's own gate (`make audit`, `make sync`) lives UPSTREAM in dotfiles-core and
# is deliberately not duplicated here — core/ is vendored and read-only in this
# repo. See CLAUDE.md.
#
# NOTE: run these from inside the Linux filesystem, not from Windows over
# \\wsl.localhost — a Windows-side git reads the share as mode 0644 and would
# strip the exec bit off every script. See .gitattributes.
# ──────────────────────────────────────────────────────────────────────────────
.DEFAULT_GOAL := help
# `test` and `check` MUST be listed here for a reason beyond hygiene: a directory named
# test/ now exists, so without .PHONY make would see an up-to-date "file" called test and
# report "nothing to be done" — the exact silent no-op the fleet register calls out.
.PHONY: help lint markdown check dry-run bootstrap-dry test packages-check secrets core-lock core-verify capabilities

# bash explicitly, not make's default /bin/sh: packages-check SOURCES
# core/lib/bootstrap-lib.sh, which is bash (arrays, [[ ]]). Arch happens to point
# /bin/sh at bash, so this would appear to work here and break on any host that
# doesn't — the kind of latent portability bug this repo exists to avoid.
SHELL := /bin/bash

# Path to a dotfiles-core checkout — the reference for the two provenance targets.
# Defaults to a sibling clone, which is the layout sync-core.sh assumes.
CORE_REPO ?= $(CURDIR)/../dotfiles-core

# The same exclusions and suppressions lint-call.yml uses. core/** is excluded
# because it is gated upstream by dotfiles-core's own CI.
SH_FILES   = $(shell git ls-files '*.sh' ':!:core/**')
ZSH_FILES  = $(shell git ls-files '*.zsh' ':!:core/**')
# Same pathspec again, and it is the one lint-call.yml's markdown leg uses — so `make
# markdown` scans exactly what the blocking gate scans, recursively (a '*.md' glob would
# be top-level only and miss pull_request_template.md).
MD_FILES   = $(shell git ls-files '*.md' ':!:core/**')
# The markdown linter is PINNED to the version the blocking gate installs, read from the
# vendored Core pins rather than restated here — one number, one place. See the markdown
# target for why this is npx and not a global binary (dotfiles-core#873).
CORE_PINS := core/scripts/tool-versions.env
MARKDOWNLINT_VERSION := $(shell sed -n 's/^MARKDOWNLINT_VERSION=//p' $(CORE_PINS) 2>/dev/null)
export SHELLCHECK_OPTS = -e SC1090 -e SC1091 -e SC2015 -e SC2088

help: ## Show this help
	@echo "dotfiles-Arch — make targets:"
	@grep -E '^[a-z][a-zA-Z0-9_-]+:.*## ' $(MAKEFILE_LIST) \
		| sed -E 's/:.*## /\t/' | sort | awk -F'\t' '{printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'
	@echo
	@echo "  Core's audit/sync live upstream in dotfiles-core (core/ is vendored, read-only here)."

lint: capabilities markdown ## shellcheck + bash -n on repo-owned *.sh, zsh -n on repo-owned *.zsh, markdownlint on repo-owned *.md (== the CI gate)
	@rc=0; \
	if [ -z "$(SH_FILES)" ]; then echo "no repo-owned .sh"; else \
	  if command -v shellcheck >/dev/null 2>&1; then \
	    echo "shellcheck $(SH_FILES)"; shellcheck -x $(SH_FILES) || rc=1; \
	  else echo "!! shellcheck not installed — install it, or CI is your only gate"; rc=1; fi; \
	  for f in $(SH_FILES); do echo "bash -n $$f"; bash -n "$$f" || rc=1; done; \
	fi; \
	if [ -z "$(ZSH_FILES)" ]; then echo "no repo-owned .zsh"; else \
	  if command -v zsh >/dev/null 2>&1; then \
	    for f in $(ZSH_FILES); do echo "zsh -n $$f"; zsh -n "$$f" || rc=1; done; \
	  else echo "!! zsh not installed — cannot syntax-check $(ZSH_FILES)"; rc=1; fi; \
	fi; \
	[ $$rc -eq 0 ] && echo "lint OK" || echo "lint FAILED"; exit $$rc

# Markdown had no local gate at all, while lint-call.yml's markdown leg has been BLOCKING
# since dotgibson/dotfiles-core#592 — a required check nobody could run before pushing.
# .markdownlint.jsonc has always been here; until now only CI ever read it.
#
# This SKIPS when the linter is absent, unlike the shellcheck arm above which sets rc=1.
# The difference is deliberate: shellcheck is a pacman package, so "not installed" is a
# box that needs fixing; markdownlint-cli2 is npm-only with no reliable repo package, so
# failing on its absence would red `make lint` on most boxes for something the author
# cannot cheaply fix. The message names CI as the remaining gate rather than implying
# coverage. ONE recipe line, so the `exit 0` skips the whole target and not just its
# first line (dotgibson/dotfiles-core#775).
markdown: ## markdownlint the repo-owned *.md against .markdownlint.jsonc (skips if absent)
	@#
	@# npx AND A PIN, not a global markdownlint-cli2 (dotfiles-core#873). The probe used to
	@# be `command -v markdownlint-cli2`, and nothing in this repo's bootstrap installs that
	@# — so on a normal box the guard fired every time and the target never linted anything.
	@# A local mirror of a blocking gate that always skips is not a mirror. And where the
	@# binary DID exist it was whatever npm last put there, while the gate runs the pinned
	@# version, so a rule that changes across a bump reds CI against a green run here.
	@# npx needs only node, fetches the exact pinned version, and REFUSES rather than guess
	@# if the pin is unreadable — a silently-unpinned lint is the thing being fixed.
	@if ! command -v npx >/dev/null 2>&1; then echo "npx not available — skipping markdown"; \
	elif [ -z "$(MARKDOWNLINT_VERSION)" ]; then \
	  echo "!! MARKDOWNLINT_VERSION unreadable from $(CORE_PINS) — refusing to lint unpinned"; exit 1; \
	elif [ -z "$(MD_FILES)" ]; then echo "no repo-owned .md"; \
	else echo "markdownlint-cli2@$(MARKDOWNLINT_VERSION) $(MD_FILES)"; \
	  npx --yes markdownlint-cli2@$(MARKDOWNLINT_VERSION) $(MD_FILES); fi

# ── the canonical fleet verbs (dotgibson/dotfiles-core#691) ───────────────────
# Core declares one `make` vocabulary for every repo that vendors it — help, lint,
# check, dry-run, packages-check, core-verify, test — so that the same word means the
# same thing in nine repos and `make <verb>` resolves in all of them. The requirement is
# that the canonical name EXISTS, not that the historical one dies, so `bootstrap-dry`
# stays as a .PHONY alias: it is in this repo's README, CHANGELOG and muscle memory.
dry-run: ## Preview a full bootstrap (symlink plan + package plan), changing nothing
	@./bootstrap.sh --dry-run

bootstrap-dry: dry-run ## Alias for `dry-run` (the spelling this repo used before #691)

# `check` is the full LOCAL gate: everything that can be run before pushing without
# changing the box. lint is the CI gate verbatim, test is the test/ suite, and the
# dry-run proves bootstrap.sh's plan still builds — the package list parses and the
# preview in bootstrap_check() renders (the driver never enters bootstrap_provision()
# dry; bootstrap.yml runs that with pacman stubbed; see CLAUDE.md).
#
# DELIBERATELY NOT a hermetic `HOME=$$(mktemp -d) ./bootstrap.sh --links-only`, which is
# what dotfiles-Debian and dotfiles-Fedora's `check` do. That run is only hermetic in
# $HOME: the driver's wiring ends in blib_set_login_shell, which appends to /etc/shells and calls
# `chsh` under sudo on any box whose login shell is not already zsh. A local check that
# can change your login shell is not one people run twice. --dry-run reaches the same
# code with BLIB_DRY=1 and touches nothing.
check: lint test ## The full local gate: lint + the test/ suite + a bootstrap dry-run (changes nothing)
	@echo ":: bootstrap.sh --dry-run (plan only, nothing is written)"
	@./bootstrap.sh --dry-run >/dev/null || { echo "bootstrap --dry-run FAILED — re-run it directly to see why"; exit 1; }
	@echo "check OK"

# The test/ floor #691 requires: a real suite, in a directory, run by a workflow
# (.github/workflows/packages.yml runs `make test`). A `test:` target that did not run
# one would render as a no-op in the fleet register, which is why this refuses rather
# than passing when the directory is empty.
#
# The glob is guarded because an unmatched glob stays LITERAL in sh — the same trap the
# capabilities target below documents.
#
# EXIT CODE: keep the highest rc any script returned, not `|| rc=1`. test/check-packages.sh
# documents 1 for usage/env failures and 2 for the drift signal — collapsing both into 1
# would tell a workflow (or a human reading the exit code) that the manifest is fine and
# the environment is broken, when in fact the manifest has drifted. max() over the scripts
# is the only aggregation that survives more than one test file too: two scripts failing
# 1 and 2 should still report 2.
test: ## Run the test/ suite (install/packages.txt resolution + manifest hygiene)
	@rc=0; found=0; \
	for t in test/*.sh; do \
	  [ -x "$$t" ] || continue; found=1; \
	  echo "── $$t"; "$$t"; trc=$$?; \
	  [ $$trc -gt $$rc ] && rc=$$trc; \
	done; \
	if [ "$$found" -eq 0 ]; then \
	  echo "!! no executable test/*.sh — this repo must carry at least one (dotgibson/dotfiles-core#691)"; exit 1; fi; \
	[ $$rc -eq 0 ] && echo "test OK" || echo "test FAILED (rc=$$rc)"; exit $$rc

# The logic used to live INLINE here — a dozen escaped recipe lines sourcing a bash
# library from a make recipe. It moved to test/check-packages.sh in #691 so that it is a
# script the test suite can run, shellcheck can read, and a workflow can invoke by path;
# this target stays because it is a canonical fleet verb and the name people type.
# Behaviour is a superset of the old inline version: same parser, same `pacman -Si`
# resolution, plus a duplicate-name check and a clean skip off-Arch instead of a hard
# "pacman not found" failure.
packages-check: ## Resolve every install/packages.txt name against the repos WITHOUT installing
	@./test/check-packages.sh install/packages.txt

secrets: ## Scan the full git HISTORY for credentials (gitleaks — not just the working tree)
	@command -v gitleaks >/dev/null 2>&1 || { \
	  echo "gitleaks not installed. Core pins 8.30.1 in core/scripts/tool-versions.env:"; \
	  echo "  go install github.com/gitleaks/gitleaks/v8@latest   # or: pacman -S gitleaks"; exit 1; }
	@# -c core/gitleaks.toml — ONE POLICY FILE, Core's, the rule Core's own reusable
	@# lint-call.yml secrets leg states: every repo measured the same way, no repo widening
	@# its own allowlist. The stock rule set is not stricter, it is differently wrong —
	@# several defaults match on credential-shaped POSITION rather than content
	@# (curl-auth-user fires on anything after `curl -u`), so a variable reference, which is
	@# the SECURE shape because the value never enters the file, was reported as a leak.
	@# Concretely: vendored core/CHANGELOG.md documents that allowlist and quotes the example
	@# it was written for, so the stock scan flagged Core's explanation of the rule as a
	@# violation of it, on a sync carrying no credential. That matters more here than in a
	@# working-tree scan: this target reads full HISTORY, and a false positive there cannot
	@# be fixed forward — only by a rewrite — so it would wedge the gate permanently.
	@# Not a blinding — the allowlist is scoped to the matched VALUE, not a path, rule or
	@# repo. Verified both ways with the pinned 8.30.1: the variable-reference form passes,
	@# a literal `curl -sk -u admin:<value>` in the same position still fails.
	@gitleaks detect --source . -c core/gitleaks.toml --redact --verbose

core-lock: ## Explain why core.lock is NOT regenerated here (it is written by Core's fan-out)
	@echo "core.lock is not regenerated in this repo."
	@echo
	@echo "Its format is owned by scripts/sync-core.sh in dotfiles-core, which stamps it in"
	@echo "the SAME commit as the vendor. A second generator here cannot be kept in"
	@echo "step with it, and this one had already drifted (dotgibson/dotfiles-core#593):"
	@echo
	@echo "  * it hardcoded core_branch=main, so regenerating a lock that had been pinned"
	@echo "    to a released commit silently replaced that provenance with a branch name;"
	@echo "  * it re-emitted the 'Regenerate ... with: make core-lock' header line that"
	@echo "    Core removed in #454, reintroducing the instruction this target existed for;"
	@echo "  * Core renamed the field to core_ref in #453, which this never knew about."
	@echo
	@echo "If core/ and core.lock disagree, re-run the fan-out from a dotfiles-core"
	@echo "checkout rather than patching the lock here:"
	@echo
	@echo "    make sync          # in dotfiles-core"
	@echo
	@echo "Then verify this repo with:  make core-verify"


core-verify: ## Verify the vendored core/ is pristine vs core.lock (needs CORE_REPO)
	@[ -x "$(CORE_REPO)/scripts/core-integrity.sh" ] || { \
	  echo "need a dotfiles-core checkout at CORE_REPO=$(CORE_REPO)"; exit 1; }
	@"$(CORE_REPO)/scripts/core-integrity.sh" --self "$(CURDIR)"

# ── the OS capability declaration (Core v5, #663/#667) ────────────────────────
# ONE definition of the schema gates all seven declaring repos: the validator is
# core/scripts/check-capabilities.sh, vendored with Core, so a schema change arrives
# with the next sync instead of needing seven hand-written greps to be updated in
# step. Core's own `make audit` runs the same script over its shipped example and
# sweeps the fleet for these files; this is the local half of that gate.
#
# The glob is guarded because an unmatched glob stays LITERAL in sh — without the
# test this would "validate" a file named `os/*.capabilities` and pass on nothing,
# which is the failure mode a gate must never have.
capabilities: ## Validate os/*.capabilities against Core's schema
	@rc=0; found=0; \
	for f in os/*.capabilities; do \
	  [ -e "$$f" ] || continue; found=1; \
	  core/scripts/check-capabilities.sh "$$f" --packages install/packages.txt || rc=1; \
	done; \
	if [ "$$found" -eq 0 ]; then echo "!! no os/*.capabilities — this repo must declare one (see core/examples/os.capabilities.example)"; rc=1; fi; \
	exit $$rc

