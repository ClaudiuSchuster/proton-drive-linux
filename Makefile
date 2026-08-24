SHELL := /bin/bash
.DEFAULT_GOAL := help

.PHONY: help version check check-units check-display verify install install-with-proton-cli uninstall

help: ## Show this action-free command overview.
	@printf '%s\n' \
		'PDrive developer commands' \
		'' \
		'  make check                    Run the portable repository test suite.' \
		'  make check-units              Validate systemd user units only.' \
		'  make check-display            Run GTK tests on the current display.' \
		'  make verify                   Run diff hygiene and the portable suite.' \
		'  make version                  Print the project version.' \
		'  make install                  Install or update user-local files.' \
		'  make install-with-proton-cli  Also enable the optional Proton CLI updater.' \
		'  make uninstall                Start the guarded interactive uninstaller.'

version: ## Print the canonical project version.
	@cat VERSION

check: ## Run the portable repository test suite.
	./tests/check.sh

check-units: ## Validate systemd user units and project invariants.
	./tests/test-systemd.sh

check-display: ## Run GTK tests against the current desktop display.
	NO_AT_BRIDGE=1 ./tests/test-setup-wizard-ui.sh --use-display
	NO_AT_BRIDGE=1 ./tests/test-ui-widgets.sh --use-display

verify: ## Check diff hygiene and run the portable repository suite.
	git diff --check
	$(MAKE) check

install: ## Install or update user-local project files.
	./install.sh

install-with-proton-cli: ## Install and enable the optional Proton CLI updater.
	./install.sh --with-proton-cli-updater

uninstall: ## Run the queue-guarded interactive uninstaller.
	./uninstall.sh --uninstall
