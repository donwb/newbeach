# Volusia Beach Info — top-level targets.
#
# The Go API and ingester have their own Makefile in api/. This one covers
# the Apple release process (flight.conf → ~/dev/flight) and deploying the
# cam restreamer to the Mac Studio (see docs/CAM-RELAY.md).

RESTREAMER_LABEL := com.donwb.cam-restreamer
RESTREAMER_SRC   := scripts/cam-restreamer.sh
RESTREAMER_DEST  := $(HOME)/bin/cam-restreamer.sh
RESTREAMER_ENV   := $(HOME)/.cam-restreamer.env
RESTREAMER_LOG   := /tmp/cam-restreamer.launchd.log
WATCHDOG_LABEL   := com.donwb.cam-watchdog
WATCHDOG_SRC     := scripts/cam-watchdog.sh
WATCHDOG_DEST    := $(HOME)/bin/cam-watchdog.sh
WATCHDOG_PLIST   := $(HOME)/Library/LaunchAgents/$(WATCHDOG_LABEL).plist

.PHONY: help flight flight-check screenshots \
        deploy-restreamer restreamer-status restreamer-diff \
        deploy-watchdog watchdog-status watchdog-test-email

help:  ## Show available targets
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

# ---------------------------------------------------------------- Apple ----

FLIGHT ?= $(HOME)/bin/flight

flight:        ## Bump build, archive, upload to TestFlight (ARGS="--yes" etc.; see flight --help)
	$(FLIGHT) $(ARGS)

flight-check:  ## Archive without uploading (dry run)
	$(FLIGHT) --archive-only $(ARGS)

screenshots:  ## Capture App Store gallery screenshots (iPhone, iPad, watch)
	apple/scripts/screenshots.sh

# ----------------------------------------------------------- Cam relay ----
#
# launchd runs a COPY of the script at ~/bin, not the repo file, so editing
# the repo alone changes nothing on the Studio. That drift cost a debugging
# round trip on 2026-08-15; these targets exist so the copy can't be
# forgotten. Studio-only — the guard below refuses to run anywhere else.

deploy-restreamer:  ## Copy cam-restreamer.sh to ~/bin and restart it (Mac Studio only)
	@launchctl print gui/$$(id -u)/$(RESTREAMER_LABEL) >/dev/null 2>&1 || { \
		echo "✗ $(RESTREAMER_LABEL) is not loaded — this isn't the restreamer host."; \
		echo "  Run this on the Mac Studio. See docs/CAM-RELAY.md."; \
		exit 1; }
	@test -f $(RESTREAMER_SRC) || { echo "✗ $(RESTREAMER_SRC) not found — run from the repo root."; exit 1; }
	@mkdir -p $(HOME)/bin
	@cp $(RESTREAMER_SRC) $(RESTREAMER_DEST)
	@chmod +x $(RESTREAMER_DEST)
	@echo "✓ deployed $(RESTREAMER_SRC) → $(RESTREAMER_DEST)"
	@# An API_BASE in the env file silently overrides the script default. This
	@# is the trap that made a correct-looking script keep using the old host.
	@if [ -f $(RESTREAMER_ENV) ] && grep -qE '^[[:space:]]*(export[[:space:]]+)?API_BASE=' $(RESTREAMER_ENV); then \
		echo "⚠️  $(RESTREAMER_ENV) sets API_BASE — it OVERRIDES the script default:"; \
		grep -nE '^[[:space:]]*(export[[:space:]]+)?API_BASE=' $(RESTREAMER_ENV) | sed 's/^/     /'; \
		echo "   Delete that line to inherit the script's value."; \
	fi
	@launchctl kickstart -k gui/$$(id -u)/$(RESTREAMER_LABEL)
	@echo "✓ restarted $(RESTREAMER_LABEL); waiting for the first roster fetch…"
	@sleep 15
	@grep -iE 'fetching roster|error' $(RESTREAMER_LOG) 2>/dev/null | tail -5 | sed 's/^/   /' || \
		echo "   (nothing in $(RESTREAMER_LOG) yet — check again in a minute)"

restreamer-status:  ## Show the restreamer's launchd state and recent log lines
	@state=$$(launchctl print gui/$$(id -u)/$(RESTREAMER_LABEL) 2>/dev/null | \
		grep -E '^[[:space:]]+(pid|state|last exit code) '); \
	if [ -n "$$state" ]; then echo "$$state" | sed 's/^[[:space:]]*/  /'; \
	else echo "  $(RESTREAMER_LABEL) is not loaded on this machine."; fi
	@echo "  --- last 10 log lines ---"
	@if [ -f $(RESTREAMER_LOG) ]; then tail -10 $(RESTREAMER_LOG) | sed 's/^/  /'; \
	else echo "  no log at $(RESTREAMER_LOG)"; fi
	@echo "  --- cam endpoints (-L: MediaMTX 302s to a cookieCheck URL first) ---"
	@for c in nsb ponce-inlet dunlawton ormond-beach ormond-by-the-sea; do \
		printf "  %-14s %s\n" "$$c" "$$(curl -sL -o /dev/null -w '%{http_code}' --max-time 10 https://cams.donwb.com/$$c/index.m3u8)"; \
	done

restreamer-diff:  ## Show how the deployed script differs from the repo copy
	@if [ ! -f $(RESTREAMER_DEST) ]; then \
		echo "  $(RESTREAMER_DEST) not present — nothing deployed on this machine."; \
	elif diff -u $(RESTREAMER_DEST) $(RESTREAMER_SRC) >/dev/null; then \
		echo "  ✓ deployed script matches the repo"; \
	else \
		echo "  ✗ deployed script has drifted from the repo (- deployed, + repo):"; \
		diff -u $(RESTREAMER_DEST) $(RESTREAMER_SRC) | tail -n +3 | sed 's/^/  /'; \
		echo "  Run 'make deploy-restreamer' to sync."; \
	fi

# The watchdog (scripts/cam-watchdog.sh) checks the relay every 10 min and runs
# the scripted fix / headless-Claude escalation / email alert. Same copy-to-~/bin
# rule as the restreamer: the repo file alone changes nothing.

deploy-watchdog:  ## Copy cam-watchdog.sh to ~/bin, install + (re)load its launchd job (Mac Studio only)
	@launchctl print gui/$$(id -u)/$(RESTREAMER_LABEL) >/dev/null 2>&1 || { \
		echo "✗ $(RESTREAMER_LABEL) is not loaded — this isn't the restreamer host."; exit 1; }
	@mkdir -p $(HOME)/bin $(HOME)/Library/LaunchAgents
	@cp $(WATCHDOG_SRC) $(WATCHDOG_DEST) && chmod +x $(WATCHDOG_DEST)
	@cp scripts/$(WATCHDOG_LABEL).plist $(WATCHDOG_PLIST)
	@launchctl bootout gui/$$(id -u)/$(WATCHDOG_LABEL) 2>/dev/null || true
	@launchctl bootstrap gui/$$(id -u) $(WATCHDOG_PLIST)
	@echo "✓ deployed $(WATCHDOG_SRC) → $(WATCHDOG_DEST); $(WATCHDOG_LABEL) loaded (every 10 min)"
	@$(WATCHDOG_DEST) --status

watchdog-status:  ## Show the watchdog's view: cams, plugin, email config, incident state, recent log
	@$(WATCHDOG_DEST) --status
	@echo "  --- last 15 lines of ~/Library/Logs/cam-watchdog.log ---"
	@tail -15 $(HOME)/Library/Logs/cam-watchdog.log 2>/dev/null | cut -c1-200 | sed 's/^/  /' || echo "  (no log yet)"
	@diff -q $(WATCHDOG_DEST) $(WATCHDOG_SRC) >/dev/null 2>&1 || \
		echo "  ✗ deployed watchdog differs from the repo — run 'make deploy-watchdog'"

watchdog-test-email:  ## Send a test alert email with the configured SMTP settings
	@$(WATCHDOG_DEST) --test-email
