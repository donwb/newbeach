# flight-preflight.sh — Beach-specific checks, sourced by `flight` (see flight.conf).

# The apps talk to a hardcoded base URL. Shipping a binary still pointed at the
# DigitalOcean default hostname instead of the custom domain is a one-way
# mistake once it's in review, so stop and make it deliberate.
APICLIENT="apple/BeachRamp/BeachStatus/Sources/BeachStatus/Networking/APIClient.swift"
if grep -q 'ondigitalocean\.app' "$APICLIENT" 2>/dev/null; then
  warn "$APICLIENT still points at the DigitalOcean hostname:"
  grep -n 'ondigitalocean\.app' "$APICLIENT" | sed 's/^/     /'
  echo "   Production is https://beach.donwb.com — a submitted binary would ship the DO URL."
  confirm "Ship it pointed at the DigitalOcean hostname anyway?" || exit 1
fi
