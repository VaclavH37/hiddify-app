#!/usr/bin/env bash
# Analyse a hotspot-crash reproduction capture.
#
#   scripts/analyze_hotspot_repro.sh <box.log> [debug-built-config.json]
#
# Answers the three questions Phase 1 of the hotspot plan exists to settle, from a
# box.log captured with the core at log level `debug` while the crash reproduces:
#
#   1. Did the interface set churn while the client was connected?
#   2. What were the tun-inbound connections actually dialling?
#   3. Is any of that a hub address -- i.e. is the loop real?
#
# Question 3 is the decisive one and needs no timestamps, which matters because
# `builder.go:471` sets Timestamp: false so box.log carries none. Pass the built
# config (from a core built with EXTRA_TAGS=raynconfigdump) to answer it
# automatically; without it the script prints the destinations and you compare by
# eye against the hub address.
#
# Line shapes this parses, confirmed against a real capture:
#   INFO network: updated default interface Wi-Fi, index 6
#   INFO [2216374997 0ms] inbound/tun[tun-in]: inbound connection to 4.213.25.241:443
#   INFO outbound/vless[EXIT-Tokyo, JP]: outbound connection to cp.cloudflare.com:443

set -u

BOX_LOG=${1:-}
BUILT_CONFIG=${2:-}

if [ -z "$BOX_LOG" ] || [ ! -f "$BOX_LOG" ]; then
  echo "usage: $0 <box.log> [debug-built-config.json]" >&2
  exit 2
fi

hr() { printf '%s\n' "------------------------------------------------------------"; }

echo "capture: $BOX_LOG ($(wc -l < "$BOX_LOG" | tr -d ' ') lines)"
hr

# --- 1. interface churn ------------------------------------------------------
# A hotspot appearing, ICS reconfiguring and a client associating each produce an
# interface update. Repeated updates while connected are the trigger the plan
# suspects; a single line at startup is the healthy case.
echo "1. DEFAULT-INTERFACE CHANGES (in order)"
iface_lines=$(grep -c "updated default interface" "$BOX_LOG" || true)
if [ "$iface_lines" -eq 0 ]; then
  echo "   none logged -- was the core at log level debug?"
else
  grep -n "updated default interface" "$BOX_LOG" \
    | sed 's/^\([0-9]*\):.*updated default interface /   line \1: /'
  echo
  echo "   total: $iface_lines"
  if [ "$iface_lines" -gt 3 ]; then
    echo "   >>> churn: the interface set is being re-detected repeatedly."
  fi
fi
hr

# --- 2. what the tun was asked to reach --------------------------------------
inbound_total=$(grep -c "inbound/tun\[.*\]: inbound connection to" "$BOX_LOG" || true)
echo "2. TUN-INBOUND DESTINATIONS (top 15 of $inbound_total)"
grep -oE "inbound/tun\[[^]]*\]: inbound connection to [^ ]+" "$BOX_LOG" \
  | sed 's/.*inbound connection to //' \
  | sed 's/:[0-9]*$//' \
  | sort | uniq -c | sort -rn | head -15 | sed 's/^/   /'
echo
echo "   total tun-inbound connections: $inbound_total"
echo "   A handful of destinations dominating, especially one, is the loop shape."
echo "   A long tail of unrelated public hosts is ordinary forwarding."
hr

# --- 3. the decisive test ----------------------------------------------------
echo "3. LOOP TEST -- does a hub address appear as a tun-inbound destination?"
if [ -n "$BUILT_CONFIG" ] && [ -f "$BUILT_CONFIG" ]; then
  # Server addresses of every outbound in the built config.
  servers=$(grep -oE '"server"[[:space:]]*:[[:space:]]*"[^"]+"' "$BUILT_CONFIG" \
    | sed 's/.*"\([^"]*\)"$/\1/' | sort -u)
  if [ -z "$servers" ]; then
    echo "   no \"server\" keys found in $BUILT_CONFIG"
  else
    hit=0
    while IFS= read -r s; do
      [ -z "$s" ] && continue
      n=$(grep -cE "inbound/tun\[[^]]*\]: inbound connection to ${s}[:.]" "$BOX_LOG" || true)
      if [ "$n" -gt 0 ]; then
        echo "   >>> $s appeared $n time(s) as a TUN-INBOUND destination"
        hit=1
      fi
    done <<EOF
$servers
EOF
    if [ "$hit" -eq 1 ]; then
      echo
      echo "   LOOP CONFIRMED. Our own outbound dial to the hub is being captured by"
      echo "   auto_route and re-entering the tun. Phase 2: refuse tun-inbound"
      echo "   connections destined for the hub, and/or pin the outbound bind."
    else
      echo "   No hub address seen as a tun-inbound destination."
      echo "   Loop NOT confirmed -- this looks like pile-up, not feedback."
    fi
  fi
else
  echo "   (no built config supplied -- rebuild with EXTRA_TAGS=raynconfigdump and pass"
  echo "    <workingDir>/data/debug-built-config.json to answer this automatically)"
  echo
  echo "   Meanwhile: compare the destinations in section 2 against the hub address."
  echo "   The hub appearing there at all is the loop."
fi
hr

# --- 4. which outbound served the traffic ------------------------------------
echo "4. OUTBOUND TAGS USED"
# Node tags carry flag emoji (EXIT-Los Angeles, US<US flag>). Those survive the
# pipeline fine but not always a terminal or a copy-paste into a bug report -- and
# a silently dropped row here reads as "that outbound was never used", which sent
# one investigation chasing a nonexistent anomaly. Transliterate to ASCII so the
# output is safe to paste; the counts are what matter.
grep -oE "outbound/[a-z]+\[[^]]*\]: outbound connection to" "$BOX_LOG" \
  | sed 's/: outbound connection to//' \
  | LC_ALL=C sort | uniq -c | sort -rn | head -10 \
  | LC_ALL=C sed 's/[^[:print:][:space:]]//g' | sed 's/^/   /'
outbound_total=$(grep -c "outbound connection to" "$BOX_LOG" || true)
echo
echo "   total outbound connections: $outbound_total"
if [ "$inbound_total" -gt 0 ] && [ "$outbound_total" -gt 0 ]; then
  echo "   inbound:outbound ratio $inbound_total:$outbound_total -- roughly 1:1 is"
  echo "   normal; outbound far exceeding inbound means dials are being retried or"
  echo "   multiplied."
fi
hr
echo "Remember: box.log carries no timestamps (builder.go:471, Timestamp: false)."
echo "Correlate with app.log, which does, or note wall-clock at start and stop."
