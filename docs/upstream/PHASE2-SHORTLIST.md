# Phase 2 shortlist — app backlog, campaign 2026-08

Output of the mechanical filter over the 81 non-merge commits in
`fbc6cbd4..rayn/upstream-snapshot-2026-08`. The 85 in the raw count include 4
merges, which carry no unique content.

**COMPLETE.** All 81 have ledger rows and
`./scripts/upstream_ledger_check.sh` passes all three checks. This document is
kept as the reasoning behind those rows — the ledger holds the decisions, this
holds why.

Final dispositions: 70 `REJECT-DEAD`, 4 `ADAPT`, 3 `REJECT-DESIGN`, 2 `DEFER`,
1 `TAKE`, 1 `ALREADY`.

That ratio is the honest shape of a hard fork's backlog, and worth stating
plainly: five commits out of eighty-one were worth landing. The value of the pass
is not the five — it is knowing, with cited evidence, that the other seventy-six
are not silently owed.

| Bucket | n | Status |
|---|---|---|
| DEAD | 17 | rejected — every touched path was deleted by this fork |
| NOISE | 12 | rejected — non-English locale churn for features we lack |
| GEN | 2 | rejected — regenerate from our own core, never pick |
| CLEAN | 11 | needs evidence |
| HOT | 21 | needs evidence |
| SPLIT | 18 | needs evidence |

A second pass classified each undecided commit by its **surviving code
footprint** — the part that could actually land here. Of the 50, five touch no
code at all, and 30 touch exactly one file.

---

## The list that matters: genuine fix candidates — DONE

E1–E4 run on all eight. Four rejected, four landed as slice S2.4. All eight have
ledger rows; the four that landed name the fork commit that carries them.

| Commit | Disposition | Landed as |
|---|---|---|
| `3d9f7c93` | `TAKE` | `55423269` |
| `6b116d2f` | `ADAPT` | `54207334` |
| `116c79e7` | `ADAPT` | `2f763cb1` |
| `ac4d26fd` | `ADAPT` | `87c3af8e` |

`787dcf9a` (AppImage desktop-entry localization) remains untriaged — it touches
the branding block of the same file and is better handled with the outstanding
Linux rebrand than as a fix.

### What landed, and why

**`3d9f7c93` — `TAKE`. A live defect in this fork's own notification feature.**

The most valuable find of the pass, and the one that nearly got rejected on a bad
assumption. It looked like `ALREADY`: the `total == 0` check the subject implies
was present at the merge base and still is (`profile_parser.dart:494`). That is
not what the commit does. It raises `infiniteTrafficThreshold` from
`920_233_720_368` (~857 GiB) to `1_099_511_627_776_000` (1000 TiB).

Upstream cared about display — the sentinel sat below the 10 TB gate in
`isInfinitSize()`, so unlimited plans rendered as a finite cap. **That half does
not apply here**: `isInfinitSize()` has no consumers in this fork, its UI having
been deleted.

The half that does apply is worse. `notification_evaluator.dart:31` reads

```dart
final unlimitedTraffic = subInfo.total > ProfileParser.infiniteTrafficThreshold;
if (!unlimitedTraffic && subInfo.total > 0) { ...80/90/100% quota alerts... }
```

With the threshold at ~857 GiB, **every plan larger than that is classified as
unlimited and receives no quota notifications at all** — no 80%, no 90%, no
100%. Raising the sentinel fixes it for every realistic plan size. Note the
sentinel arithmetic still works afterwards: unlimited is stored as
`threshold + 1`, which stays above the new threshold.

**`6b116d2f` — `TAKE`. One word, into an idiom this fork already uses.**

`await _init("hiddify-core", …)` → `_safeInit`. E1: the fork has the unpatched
line at `bootstrap.dart:118`. E3: `_init` propagates, so a core init failure
kills bootstrap and the app does not start; `_safeInit` logs and continues. The
fork already calls `_safeInit` five times (lines 56, 107, 117, 134, 141), so the
helper and the convention both exist.

**`116c79e7` — `ADAPT`. Largest real footprint in the backlog.**

Riverpod lazy build-phase collision under high-frequency stream updates. E1: the
fork has none of it — `stats_notifier.dart`, `connection_notifier.dart`,
`active_proxy_notifier.dart` and `proxies_overview_notifier.dart` all still carry
the `async*` + `await ref.watch(x.future)` + `yield*` shape upstream replaces
with a synchronous `Stream` return. E3: the fork is structurally exposed —
`connection_button.dart:26-27` watches `connectionNotifierProvider` and
`activeProxyNotifierProvider` in the same build, which is the sibling collision
described.

`ADAPT` rather than `TAKE`: the hunk for `config_option_notifier.dart` will not
apply, since this fork gutted that file from 174 lines to 39. Upstream itself
calls this a temporary patch and recommends a core-communication redesign.

**`ac4d26fd` — `ADAPT`. Real AppImage launch crash.**

Filters the desktop-entry placeholders `%u %U %f %F` out of `$@` before argument
processing; without it a launcher passing `%u` makes AppRun treat it as a real
argument. E1: the fork's `AppRun` changes are branding only (`StartupWMClass`,
`exec ./RaynVPN`), so the argument-handling block is upstream's and carries the
bug. Expect a trivial conflict — upstream's hunk sits next to the `exec` line,
and `./hiddify` must stay `./RaynVPN`.

`787dcf9a` (desktop-entry localization and AppImage update keys) touches the same
file and the branding block this fork rewrote. Lower value; triage with
`ac4d26fd` when that lands.

### Rejected — rows written

| Commit | Disposition | Why |
|---|---|---|
| `bf1006d9` | `REJECT-DEAD` | `inAppNotificationControllerProvider` has no consumers outside its own generated file. This fork replaced the toastification surface with its own bell inbox and swipe banner, so the controller is orphaned and guarding it changes nothing a user can see. |
| `98bd20bd` | `REJECT-DEAD` | Same orphaned controller — repositions a toast this fork never shows. |
| `ce76702c` | `REJECT-DEAD` | The port-range validator has no callers; it existed for the route-rule editor, deleted with `lib/features/route_rules/`. |
| `14654bd0` | `REJECT-DESIGN` | **E2 hit.** Repoints `CORE_URL` from `hiddify-next-core` to `hiddify-core` releases — the URL used by the `*-libs` targets that pull Hiddify's *prebuilt* core over a custom build. Those targets are fenced off; fixing their URL has no value and makes a forbidden path look maintained. |

## Needs a decision, not just evidence

| Commit | Why |
|---|---|
| `e6822e2c` | **The Drift v6 collision, concretely.** Upstream's own `schemaVersion` 6 migration ("replace profileOverride with …"). This fork already owns v6–v10 and shipped installs are pinned to *its* v6. Per [drift-schema-numbering](DESIGN-INVARIANTS.md#drift-schema-numbering) the disposition can only ever be `ADAPT` (as a new `from10To11`) or a rejection — never `TAKE`. First decide whether the *intent* is even wanted: it pairs with `30f30f5d`, and this fork's profile layer is 60–92% rewritten. |
| `0299c1cc` `3f60de68` | Two `pubspec.yaml` dependency removals. Upstream's "unused" is not this fork's unused — `crypto`, `pointycastle`, `flutter_secure_storage` and `pigeon` are load-bearing here. Cross-check before touching. |

## Rejected in all but paperwork

Feature work for subsystems this fork removed or deliberately does not want. They
appear as CLEAN/HOT/SPLIT only because they brush a surviving file — usually a
translation file, a shared enum, or `config_option_repository.dart`.

- **Proxy chaining** (~9): `3383d513` `96516501` `1e53f27e` `702dd17e` `e7ed62a8`
  `6b4b1510` `f996c5e2` `add4d5f7` `31528570`
- **Routing / route-rule editor** (~7): `077ad30c` `350f9437` `f5d66ff7`
  `e5fed9ca` `3fc523ce` `8b0d8c2f` `5af58716`
- **LAN sharing / VPN-share password** (3): `f5d01fd6` `9de86aa4` `961f6115`
- **Psiphon** (1): `fc4631ad` — also touches `profile_parser.dart`, so check what
  rides along before rejecting outright
- **Profile import surface** (2): `c2f9ac72` (file import), `c2db7f09`
  (`triggeredByDeepLink`) — both re-open import paths this fork closed
- **iOS/macOS icon and packaging** (6): `11bc9962` `99bdac0d` `837d2e7b`
  `84f812e6` `cfd39477` `ba426899` — upstream Hiddify branding; this fork is
  rebranded
- **i18n-only** (5): `f996c5e2` `8b0d8c2f` `01f46b4a` `d05adc61` `f9686c9c`
- **Other** (3): `a447f038` (upstream removing WARP — this fork did it first, so
  `ALREADY` in spirit), `c50ce39c` (`.gitignore`), `865ea737` (generated macOS
  plugin registrant, gitignored here), `210548d7` (`update` — bumps the core
  submodule and Podfiles)

---

## Notes from the filter

**The mechanical bucket is not the disposition.** `c4530d45` "fix: add
confirmation for deep link profile addition to prevent SSRF" landed in `DEAD`
because every path it touches is gone. It is a security fix, and
`METHODOLOGY.md` E4 says those are `ADAPT`, never `REJECT` — so it got a real
investigation rather than the bucket's default. The conclusion was still
rejection, but on structural grounds: `deepLinkNotifierProvider` is commented out
at `lib/bootstrap.dart:123`, no call site feeds a deep-linked URL to
`LinkParser.parse`, and import is `rayn://import/<token>` only. The ledger row
says to re-examine it if deep-link import is ever enabled. Had the filter been
trusted blindly, that would have been a one-line rejection of a CVE-class fix.

**`a447f038`** is upstream removing its legacy WARP implementation — converging
on a decision this fork made first. Worth noting because it *reduces* future
divergence rather than adding to it.

**Translations are 12 NOISE commits plus 5 i18n-only ones**, roughly a fifth of
the backlog, and none of them can be cherry-picked. `en.i18n.json` gets a single
hand-picked sweep at the end of the campaign, per `METHODOLOGY.md`.
