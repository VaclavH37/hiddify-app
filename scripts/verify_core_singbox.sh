#!/usr/bin/env bash
#
# Which hiddify-sing-box is baked into the built core artifacts?
#
#   ./scripts/verify_core_singbox.sh
#
# Written because a build was reported as testing a sing-box bump when every
# binary on disk had in fact been built against the old pin -- the working tree
# was on custom-main at build time. Timestamps and "I rebuilt it" cannot
# distinguish those; a string that exists in exactly one pin can.
#
# The markers are deprecation-note names, chosen because each exists in only one
# of the two pins:
#
#   legacy-dns-fakeip          3a1c923e only  (removed by 1.14)
#   legacy-dns-rule-strategy   170d8315 only  (added by 1.14)
#
# Both are plain strings in the Go binary, so grep -a finds them in an
# uncompressed artifact. NOTE: .aar and .apk are ZIPs -- absence there proves
# nothing, so those are reported as INCONCLUSIVE rather than OLD. Unzip and
# check the .so inside if you need certainty on Android.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

OLD_MARKER=legacy-dns-fakeip
NEW_MARKER=legacy-dns-rule-strategy

printf '%-52s %s\n' "ARTIFACT" "SING-BOX"
printf '%s\n' "---------------------------------------------------------------------"

found_any=0
for f in \
  hiddify-core/bin/rayn-core.dll \
  hiddify-core/bin/RaynVPNCli.exe \
  build/windows/x64/runner/Debug/rayn-core.dll \
  build/windows/x64/runner/Release/rayn-core.dll \
  android/app/libs/rayn-core.aar
do
  [ -f "$f" ] || continue
  found_any=1
  case "$f" in
    *.aar|*.apk|*.aab|*.zip) verdict="INCONCLUSIVE (compressed archive)" ;;
    *)
      has_old=$(grep -qa "$OLD_MARKER" "$f" && echo y || echo n)
      has_new=$(grep -qa "$NEW_MARKER" "$f" && echo y || echo n)
      if   [ "$has_new" = y ] && [ "$has_old" = n ]; then verdict="NEW (170d8315 or later)"
      elif [ "$has_old" = y ] && [ "$has_new" = n ]; then verdict="OLD (3a1c923e)"
      elif [ "$has_old" = y ] && [ "$has_new" = y ]; then verdict="AMBIGUOUS (both markers)"
      else verdict="UNKNOWN (neither marker -- markers may be stale)"; fi
      ;;
  esac
  printf '%-52s %s  [%s]\n' "$f" "$verdict" "$(date -r "$f" '+%m-%d %H:%M')"
done

[ "$found_any" = 0 ] && echo "  no core artifacts found -- nothing built yet"

echo
echo "source tree currently on:"
echo "  hiddify-core     $(git -C hiddify-core rev-parse --short HEAD)  ($(git -C hiddify-core rev-parse --abbrev-ref HEAD))"
echo "  hiddify-sing-box $(git -C hiddify-core/hiddify-sing-box rev-parse --short HEAD)"
echo
echo "An artifact whose verdict disagrees with the source tree above was built"
echo "from a different checkout. Rebuild before trusting any connect test."
