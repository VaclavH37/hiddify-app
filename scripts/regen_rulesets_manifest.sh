#!/usr/bin/env bash
# Regenerates assets/rulesets/MANIFEST after `make fetch-rulesets`. The MANIFEST
# is consumed by lib/core/rulesets/ruleset_extractor.dart: only `version` is
# compared at runtime to decide whether to re-extract, but `fetched_at`,
# `upstream_commit`, and per-file sha256s are useful for audit / CI hygiene.
set -euo pipefail

cd "$(dirname "$0")/.."

RULESETS_DIR="assets/rulesets"
MANIFEST="${RULESETS_DIR}/MANIFEST"
VERSION="$(date -u +%Y-%m-%d)"
FETCHED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Best-effort upstream commit lookup; falls back to "unknown" if jq is missing
# or the GitHub API is rate-limited (unauthenticated requests get 60/hr).
fetch_commit() {
  local repo="$1"
  local sha
  sha="$(curl -sf "https://api.github.com/repos/${repo}/commits/rule-set" 2>/dev/null \
        | sed -n 's/^[[:space:]]*"sha":[[:space:]]*"\([^"]*\)".*/\1/p' \
        | head -n1)"
  if [ -z "${sha}" ]; then
    echo "unknown"
  else
    echo "${sha}"
  fi
}

GEOSITE_COMMIT="$(fetch_commit SagerNet/sing-geosite)"
GEOIP_COMMIT="$(fetch_commit SagerNet/sing-geoip)"

# Local (neutral) names — must match the -o targets in the Makefile
# fetch-rulesets target and the Path: literals in builder.go. The names are
# deliberately region-agnostic so they don't reveal the targeted region in
# `strings libcore.so` or the AAB asset listing. Upstream source -> local:
#   geosite-private         -> direct-private
#   geosite-apple@cn        -> direct-apple
#   geosite-cn              -> direct-regional-sites
#   geoip-cn                -> direct-regional-ips
#
# DO NOT re-add fakeip-remote-sites.srs (geosite-geolocation-!cn): the FakeIP
# DNS path that consumed it was removed, and it was 61% of the bundle size.
# This list must stay in sync with the curl targets in the Makefile's
# fetch-rulesets and with the Path: literals in builder.go.
FILES=(
  "direct-private.srs"
  "direct-apple.srs"
  "direct-regional-sites.srs"
  "direct-regional-ips.srs"
)

files_json=""
for f in "${FILES[@]}"; do
  path="${RULESETS_DIR}/${f}"
  if [ ! -f "${path}" ]; then
    echo "missing: ${path}" >&2
    exit 1
  fi
  sha="$(sha256sum "${path}" | awk '{print $1}')"
  size="$(wc -c < "${path}" | tr -d ' ')"
  [ -z "${files_json}" ] || files_json+=","
  files_json+="
    {\"name\": \"${f}\", \"sha256\": \"${sha}\", \"size\": ${size}}"
done

cat > "${MANIFEST}" <<EOF
{
  "version": "${VERSION}",
  "fetched_at": "${FETCHED_AT}",
  "upstream_commit": {
    "sing-geosite": "${GEOSITE_COMMIT}",
    "sing-geoip": "${GEOIP_COMMIT}"
  },
  "files": [${files_json}
  ]
}
EOF

echo "wrote ${MANIFEST} (version ${VERSION})"
