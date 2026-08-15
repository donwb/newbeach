# Beach Ramp Status — top-level targets.
#
# The Go API and ingester have their own Makefile in api/. This one covers
# the Apple release process; see apple/scripts/flight.sh for the details.

.PHONY: help flight flight-ios flight-tv flight-check

help:  ## Show available targets
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

flight:  ## Bump build, archive iOS + tvOS, upload to TestFlight
	apple/scripts/flight.sh

flight-ios:  ## Same, iOS only
	apple/scripts/flight.sh --ios-only

flight-tv:  ## Same, tvOS only
	apple/scripts/flight.sh --tv-only

flight-check:  ## Archive both platforms without uploading (dry run)
	apple/scripts/flight.sh --archive-only --no-bump
