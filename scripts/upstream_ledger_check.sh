#!/usr/bin/env bash
#
# The three honesty checks from docs/upstream/METHODOLOGY.md, as something you
# can run rather than something you have to retype.
#
#   ./scripts/upstream_ledger_check.sh [campaign]
#
# Defaults to campaign 2026-08. Exits non-zero if any check fails.
#
# 1. Completeness      every backlog commit appears in the ledger exactly once
# 2. Non-repudiation   every TAKE/ADAPT names a commit that really landed
# 3. Traceability      every campaign commit records its upstream provenance
#
# Run it before closing a campaign, and any time the ledger has been edited by
# hand. Check 1 is the one that catches a commit quietly skipped rather than
# triaged.
set -uo pipefail

CAMPAIGN=${1:-2026-08}
ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT" || exit 1

EXCEPTIONS=docs/upstream/TRACEABILITY-EXCEPTIONS.tsv
CORE=hiddify-core
PRE=rayn/pre-catchup-$CAMPAIGN

# The range a campaign covers is looked up rather than hardcoded. It has to be:
# closing a campaign moves the watermark forward, so a hardcoded one would make
# every past campaign's completeness check silently re-scope itself to a range it
# was never triaged against, and start reporting green for the wrong reason.
CAMPAIGNS=docs/upstream/CAMPAIGNS.tsv
row=$(awk -F'\t' -v c="$CAMPAIGN" '$1==c{print; exit}' "$CAMPAIGNS" 2>/dev/null)
if [ -z "$row" ]; then
  echo "::error::campaign '$CAMPAIGN' is not in $CAMPAIGNS"
  echo "Known campaigns: $(tail -n +2 "$CAMPAIGNS" 2>/dev/null | cut -f1 | paste -sd' ' -)"
  exit 1
fi
WATERMARK_APP=$(echo "$row" | cut -f2)
WATERMARK_CORE=$WATERMARK_APP
SNAPSHOT=$(echo "$row" | cut -f3)

status=0
fail() { echo "  FAIL: $*"; status=1; }

# ---------------------------------------------------------------- check 1

check_completeness() { # repo ledger watermark
  local repo=$1 ledger=$2 watermark=$3
  [ -f "$ledger" ] || { fail "$ledger does not exist"; return; }

  local backlog ledger_shas diff
  backlog=$(git -C "$repo" log --no-merges --format=%H "$watermark..$SNAPSHOT" | sort)
  ledger_shas=$(tail -n +2 "$ledger" | cut -f1 | sort)

  local untriaged stale n_untriaged n_stale
  untriaged=$(comm -23 <(echo "$backlog") <(echo "$ledger_shas") | grep -c . || true)
  stale=$(comm -13 <(echo "$backlog") <(echo "$ledger_shas") | grep -c . || true)
  n_untriaged=$untriaged
  n_stale=$stale

  if [ "$n_untriaged" -eq 0 ] && [ "$n_stale" -eq 0 ]; then
    echo "  ok  $(echo "$backlog" | grep -c .) backlog commits, all present exactly once"
  else
    fail "$(basename "$ledger"): $n_untriaged untriaged, $n_stale row(s) not in the backlog"
    # Only a sample. A campaign that has not started yet reports its whole
    # backlog here, which is true but unreadable.
    comm -23 <(echo "$backlog") <(echo "$ledger_shas") | head -5 \
      | while read -r s; do
          printf '    untriaged  %s  %s\n' "${s:0:8}" \
            "$(git -C "$repo" log -1 --format=%s "$s" 2>/dev/null | cut -c1-50)"
        done
    [ "$n_untriaged" -gt 5 ] && echo "    ... and $((n_untriaged - 5)) more"
    if [ "$n_stale" -gt 0 ]; then
      comm -13 <(echo "$backlog") <(echo "$ledger_shas") | grep . | head -5 \
        | while read -r s; do printf '    not in backlog  %s\n' "${s:0:8}"; done
    fi
  fi

  local dupes
  dupes=$(tail -n +2 "$ledger" | cut -f1 | sort | uniq -d)
  [ -n "$dupes" ] && fail "duplicate ledger rows: $dupes"
}

# ---------------------------------------------------------------- check 2

check_non_repudiation() { # repo ledger
  local repo=$1 ledger=$2
  [ -f "$ledger" ] || return
  local n=0
  while IFS=$'\t' read -r sha _date _subj _bucket disp rayn_sha _rest; do
    case "$disp" in
      TAKE|ADAPT) ;;
      *) continue ;;
    esac
    n=$((n + 1))
    if [ -z "$rayn_sha" ]; then
      fail "${sha:0:8} is $disp but names no rayn_sha"
    elif ! git -C "$repo" cat-file -e "$rayn_sha^{commit}" 2>/dev/null; then
      fail "${sha:0:8} names rayn_sha ${rayn_sha:0:8}, which is not a commit"
    elif ! git -C "$repo" merge-base --is-ancestor "$rayn_sha" custom-main 2>/dev/null; then
      fail "${sha:0:8} names ${rayn_sha:0:8}, not an ancestor of custom-main"
    fi
  done < <(tail -n +2 "$ledger")
  echo "  ok  $n TAKE/ADAPT row(s) verified"
}

# ---------------------------------------------------------------- check 3

# NOTE: deliberately greps the message body instead of using
# %(trailers:key=Upstream,valueonly). git parses only the LAST paragraph of a
# message as trailers, so an `Upstream:` line above a blank line and
# Co-Authored-By is body text to that accessor -- which is how every commit in
# this campaign is written. The accessor reported every commit as missing.
# A revert inherits the provenance of the commit it undoes, so it does not need
# an 'Upstream:' line of its own — `git revert` writes its message for you and
# adding one by hand is easy to forget. Rather than exempt reverts outright, we
# follow the "This reverts commit <sha>." line git generates and require THAT
# commit to carry provenance. A revert of an untraceable commit still fails,
# which is the case actually worth catching.
reverted_target_is_traceable() { # repo sha -> 0 if this is a revert of a traceable commit
  local repo=$1 sha=$2 target
  target=$(git -C "$repo" log -1 --format=%B "$sha" \
    | sed -n 's/^This reverts commit \([0-9a-f]\{7,40\}\)\.$/\1/p' | head -1)
  [ -n "$target" ] || return 1
  git -C "$repo" log -1 --format=%B "$target" 2>/dev/null | grep -q '^Upstream: '
}

check_traceability() { # repo label
  local repo=$1 label=$2
  local missing=0 total=0 reverts=0 waived=0
  for sha in $(git -C "$repo" log --format=%H "$PRE..custom-main" 2>/dev/null); do
    total=$((total + 1))
    if git -C "$repo" log -1 --format=%B "$sha" | grep -q '^Upstream: '; then
      continue
    fi
    if reverted_target_is_traceable "$repo" "$sha"; then
      reverts=$((reverts + 1))
      continue
    fi
    # A narrow, per-SHA allowlist for commits published before the omission was
    # spotted, where the only correction would be rewriting pushed history. The
    # provenance still exists — it is in the ledger row — so what is waived is
    # the location of the record, not the record. Deliberately keyed to exact
    # SHAs so it can never widen to cover a commit nobody looked at.
    if [ -f "$EXCEPTIONS" ] && awk -F'\t' -v s="$sha" -v r="$label" \
         'NR>1 && $1==s && $2==r {found=1} END {exit !found}' "$EXCEPTIONS"; then
      waived=$((waived + 1))
      continue
    fi
    fail "$label ${sha:0:8} has no 'Upstream:' line — $(git -C "$repo" log -1 --format=%s "$sha" | cut -c1-50)"
    missing=$((missing + 1))
  done
  if [ "$missing" -eq 0 ]; then
    local note=""
    [ "$reverts" -gt 0 ] && note=" ($reverts via the commit they revert"
    [ "$reverts" -gt 0 ] && [ "$waived" -gt 0 ] && note="$note, $waived waived in TRACEABILITY-EXCEPTIONS.tsv"
    [ "$reverts" -eq 0 ] && [ "$waived" -gt 0 ] && note=" ($waived waived in TRACEABILITY-EXCEPTIONS.tsv"
    [ -n "$note" ] && note="$note)"
    echo "  ok  $total $label commit(s), all carry provenance$note"
  fi
}

echo "campaign $CAMPAIGN"
echo
echo "1. completeness"
check_completeness "$CORE" docs/upstream/LEDGER-core.tsv "$WATERMARK_CORE"
check_completeness .       docs/upstream/LEDGER-app.tsv  "$WATERMARK_APP"
echo
echo "2. non-repudiation"
check_non_repudiation "$CORE" docs/upstream/LEDGER-core.tsv
check_non_repudiation .       docs/upstream/LEDGER-app.tsv
echo
echo "3. reverse traceability"
check_traceability "$CORE" core
check_traceability .       app
echo
[ $status -eq 0 ] && echo "all checks passed" || echo "CHECKS FAILED"
exit $status
