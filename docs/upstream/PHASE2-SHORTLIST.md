# Phase 2 shortlist — app backlog, campaign 2026-08

Output of the mechanical filter over the 81 non-merge commits in
`fbc6cbd4..rayn/upstream-snapshot-2026-08`. The 85 in the raw count include 4
merges, which carry no unique content.

**31 are decided and written to `LEDGER-app.tsv`. 50 remain, listed here so the
evidence pass does not repeat the mechanical work.**

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

## The list that matters: genuine fix candidates

These are the reason the campaign exists. Each still needs E1–E4.

| Commit | Touches | Question to answer |
|---|---|---|
| `116c79e7` | `bootstrap.dart` + 5 notifiers | Riverpod lazy build-phase collision on connection-status change. Six surviving files, the largest real-code footprint in the backlog. Does the fork hit the same collision? |
| `6b116d2f` | `bootstrap.dart` | Makes hiddify-core init non-fatal. The fork rewrote bootstrap (35% churn) — does it already tolerate a failed init? |
| `bf1006d9` | `in_app_notification_controller.dart` | Guards against a missing toast overlay. The fork has its own notification system; is this controller still on a live path? |
| `98bd20bd` | `in_app_notification_controller.dart` | Toast positioning. Same question, same file — triage together. |
| `3d9f7c93` | `profile_parser.dart` | **Likely `ALREADY`.** `(total == null \|\| total == 0)` was already present at the merge base (line 287) and still is (line 494). Confirm what else it changes before rejecting. |
| `ac4d26fd` `787dcf9a` | `linux/packaging/appimage/AppRun` | AppImage launch crash (`%u` args) and desktop-entry localization. Same file, take or reject together. |
| `14654bd0` | `Makefile` | Linux docker build fix **and** a core-download URL fix. The fork rewrote the Makefile heavily and must never adopt a `CORE_URL` change that pulls Hiddify's prebuilt core. Read carefully. |
| `ce76702c` | `lib/utils/validators.dart` | Port-range separator `-` → `:`. Introduced for the route-rule editor, which is deleted — check whether the fork still calls the port-range validator at all. |

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
