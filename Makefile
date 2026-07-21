# Makefile — rdp-connect entry points
# Spec: openspec/specs/test-harness/spec.md (canonical; promoted from the
# strict-tdd-enable delta at archive)
#
# Canonical entry points for tests, lint, install, smoke, and tamper
# verification. CI runs `make ci` (= `lint test`). The strict-tdd-enable change
# (PR1) lands this file; PR2 plugs the .bats suite into `test`; PR3 flips
# strict_tdd now that the flag enforces something real.

SHELL := /usr/bin/env bash
TESTS_DIR := tests

.DEFAULT_GOAL := help

.PHONY: help test lint install smoke verify-manifest ci

# Default goal — lists the canonical entry points (CI invokes `ci` directly).
help:
	@echo "rdp-connect — canonical entry points"
	@echo ""
	@echo "  make test             Run the bats suite (tests/*.bats)"
	@echo "  make lint             shellcheck --severity=warning on all scripts"
	@echo "  make install          Delegate to ./install-rdp-framework.sh"
	@echo "  make smoke            Install + throwaway-HOME rdp-connect --help"
	@echo "  make verify-manifest  sha256sum -c the installer manifest"
	@echo "  make ci               lint + test (run by GitHub Actions)"
	@echo ""
	@echo "See README.md 'Testing' for bats-core install."

# Primary entry point. Runs every *.bats under tests/. Exits non-zero on any
# case failure (bats's own exit code). bats-core is a DEV dependency — see
# README "Testing" for the distro install matrix. The installer does NOT
# install bats (it is not a runtime dep).
test:
	@if ! command -v bats >/dev/null 2>&1; then \
		echo "bats-core is not installed. Install via:"; \
		echo "  Arch:      sudo pacman -S bats"; \
		echo "  Debian:    sudo apt-get install -y bats"; \
		echo "  Fedora:    sudo dnf install -y bats"; \
		echo "  Source:    git clone https://github.com/bats-core/bats-core && ./bats-core/install.sh ~/.local"; \
		echo "See README.md 'Testing' for details."; \
		exit 127; \
	fi
	bats $(TESTS_DIR)/

# Static analysis. shellcheck exits non-zero on any warning. tests/fixtures/
# is excluded (golden files are data, not source).
#
# Lint glob: tests/*.bash (test_helper.bash). The 4 legacy probe scripts
# (tests/{parser,hidpi,pid-path,vpn-trim}-probe.sh) were superseded by
# their .bats counterparts in PR2 task T2.7 and deleted; the tests/*.sh
# glob is no longer needed. The .bats files themselves are NOT in the lint
# glob — they use the bats `@test` DSL which shellcheck does not parse.
lint:
	shellcheck --severity=warning engine/rdp-connect lib/*.bash install-rdp-framework.sh bootstrap.sh \
	           $(wildcard tests/*.bash)

# Idempotent install. Delegates to the installer with no other side effect.
install:
	./install-rdp-framework.sh

# Post-install smoke. Throwaway HOME proves the engine binary is on PATH and
# parses (--help exits 0 at engine L40, BEFORE require_cmd at L47, so this
# works on a host without xfreerdp3/hyprctl installed). Depends on `install`.
smoke: install
	HOME=$$(mktemp -d) ~/.local/bin/rdp-connect --help >/dev/null

# Tamper detection. Reads the installer-written SHA-256 manifest and fails
# naming any deployed file whose checksum no longer matches.
#
# Path: ~/.local/state/rdp/manifest.sha256 (XDG state/, lowercase). Matches the
# installer (install-rdp-framework.sh:219), bootstrap.sh:85, and the canonical
# test-harness spec. (Carry-forward Q1 from strict-tdd-enable was resolved at
# archive: the delta originally said ~/.local/share/rdp/MANIFEST.sha256 — a spec
# bug; amended to match this implementation.)
verify-manifest:
	@if [ ! -f "$$HOME/.local/state/rdp/manifest.sha256" ]; then \
		echo "manifest not found at $$HOME/.local/state/rdp/manifest.sha256 — run 'make install' first"; \
		exit 1; \
	fi
	sha256sum -c ~/.local/state/rdp/manifest.sha256

# CI alias. GitHub Actions invokes this on every PR and on every push to main.
ci: lint test
