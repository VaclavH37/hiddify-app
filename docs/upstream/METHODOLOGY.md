# Upstream catch-up methodology

How this fork decides what to take from `hiddify/hiddify-app` and
`hiddify/hiddify-core`, and how that decision is recorded so it is only ever
made once.

Read this before starting a catch-up campaign. It is the process; the ledgers
(`LEDGER-app.tsv`, `LEDGER-core.tsv`) are the record; `DESIGN-INVARIANTS.md` is
the list of things a careless adoption would silently undo.

---

## Why this exists

This is a **hard fork**, not a light one. As of campaign 2026-08 the app diverged
by 519 files (+21.7k / −22.5k) across 46 linear commits, and had never merged
from upstream. Whole upstream subsystems are gone: per-app proxy, route-rule
editor, app self-update, onboarding intro, add-profile UI, seven settings
sub-pages, the logs UI, xray, WARP, Sentry.

That shape makes the obvious move wrong. **`git merge upstream/main` is
forbidden.** It produces dozens of modify/delete conflicts whose only resolution
is `git rm`, yielding one enormous commit that is indistinguishable from an
accidental mass deletion and carries no record of intent. Upstream also actively
develops the subsystems this fork deleted, so most of what a merge drags in is
code with nowhere to live.

But not merging is not the same as ignoring. Upstream ships **bug and security
fixes into code this fork still runs**, plus the pinned sing-box engine itself.
The job is to separate those from the noise, deliberately, with evidence.

---

## Ref topology

Per campaign, in **both** repos:

```bash
git fetch upstream --prune
git tag rayn/pre-catchup-<campaign>        custom-main     # escape hatch
git tag rayn/upstream-triaged-<watermark>  <last covered>  # what has been triaged
git tag rayn/upstream-snapshot-<campaign>  upstream/main   # PIN the moving target
git branch rayn/integration-<campaign>     custom-main     # scratch
```

Pinning the snapshot is not optional. Upstream moves; a campaign run against a
moving target never closes. If upstream passes the snapshot mid-campaign, finish
against the tag and open a new campaign — do not chase it.

Tags rather than branches, because tags are immutable and push to `origin`, so a
second machine or agent inherits the state.

**The watermark tag is the entire durable state the next campaign needs:**

```bash
git log --oneline --no-merges rayn/upstream-triaged-<watermark>..upstream/main
```

Branch `main` in each repo tracks `upstream/main` and is a **read-only mirror**.
Never merge it into `custom-main`.

### Watch the merge base

`git merge-base` is authoritative; a stale `upstream/main` ref is not. In
campaign 2026-08 the core's local `upstream/main` was `3a05fb9`, which is
upstream's ezytel **merge commit** and is *not* an ancestor of `custom-main`.
Diffing against it falsely reported all of `v2/ezytel/**` as fork-deleted
(−1761 lines). The true base was `a82d2b8f`. Always:

```bash
git fetch upstream --prune && git merge-base custom-main upstream/main
```

### Required config (both repos)

```bash
git config rerere.enabled    true
git config rerere.autoupdate false
git config merge.renormalize true
git config diff.submodule    log
```

`rerere` earns its place because a campaign hammers the same hot files
(`config_option_repository.dart`, `settings_page.dart`, `en.i18n.json`) across
many picks, and slices get aborted and retried. `autoupdate` stays **false**
deliberately: an auto-applied resolution that silently re-deletes a file is
precisely the failure this process guards against.

`merge.renormalize` matters more than it looks. `core.autocrlf=true` on the build
machine plus upstream files stored CRLF means some diffs are inflated ~40×:
`hiddify-core/v2/hcore/grpc_server.go` reports 296/300 but is **3/7** under
`--ignore-cr-at-eol`. Without renormalization a cherry-pick touching such a file
produces a phantom whole-file conflict. See `.gitattributes` for why this was not
fixed by a bulk normalization pass.

### Lockstep between the two repos

The app's gitlink is the source of truth for **what ships**; core `custom-main`
is the source of truth for **what builds**. They drift silently — at the start of
campaign 2026-08 the gitlink was four core commits stale.

- **Core lands first**, always. `lib/hiddifycore/generated/**` derives from core
  `.proto` files, so core-first makes regeneration deterministic.
- Every core slice ends with a core commit **plus a separate app commit that
  bumps only the gitlink**, message `core: bump to <sha> (<slice>)`. Never bundle
  a gitlink bump with source changes — that destroys independent revertability.
- Pre-flight every slice: `git ls-tree HEAD hiddify-core` must equal
  `git -C hiddify-core rev-parse HEAD`.

---

## Triage

**Never read the whole backlog.** Classify mechanically; read only what survives.
In campaign 2026-08 that was ~25 of 103.

### Step 0 — build the path sets (once)

```bash
git ls-tree -r --name-only custom-main                     > rayn-paths.txt
git diff --name-only --diff-filter=D <base> custom-main    > rayn-deleted.txt
git diff --numstat -M --ignore-cr-at-eol <base> custom-main \
  | awk '$1!="-" && ($1+$2)>=20 {print $3}' | sort         > rayn-hotzone.txt
```

`--ignore-cr-at-eol` is required, not cosmetic — without it the two
CRLF-inflated core files falsely top the hot-zone list.

### Step 1 — one command yields every fact the classifier needs

```bash
git log --reverse --no-merges --name-only \
  --format='%x00%H%x09%as%x09%s' <watermark>..<snapshot>
```

`%x00` is a record separator to split on. Reconcile `--merges` +
`--no-merges` against the total; a merge whose children are all present carries
no unique content.

### Step 2 — mechanical buckets

| Bucket | Test | Action |
|---|---|---|
| `DEAD` | every touched path is in `rayn-deleted.txt`, or under a deleted prefix | auto-reject; row written by script, never human-read |
| `NOISE` | only `*.md`, `docs/`, `.github/ISSUE*`, or non-`en` translations | auto-reject |
| `GEN` | only tracked-generated paths (see below) | never cherry-pick — regenerate |
| `CLEAN` | at least one surviving path, none hot | read the diff |
| `HOT` | at least one path in `rayn-hotzone.txt` | read the diff **and** the fork's version of the file |
| `SPLIT` | touches both deleted and surviving paths | partial re-implementation |

Per-commit primitives:

```bash
# paths upstream touched that this fork does not have.
# if this equals the commit's full path list, the commit is DEAD.
comm -23 <(git show --name-only --format= $SHA | sort -u) <(sort rayn-paths.txt)

# the only part of the commit worth reading
git show $SHA -- $(comm -12 <(git show --name-only --format= $SHA | sort -u) \
                            <(sort rayn-paths.txt))
```

### Step 3 — evidence required before any human decision

A `CLEAN` / `HOT` / `SPLIT` row may not be filled in until all four are answered
with cited command output.

**E1 — does this fork already have it?**

```bash
git log -S'<distinctive token from the upstream hunk>' --oneline <base>..custom-main
grep -n '<token>' <the fork's version of the file>
```

This exists because commit subjects lie. Upstream `3d9f7c93 "treat
subscription-userinfo total=0 as unlimited"` reads like a must-take, but
`profile_parser.dart` **at the merge base** already had
`(total == null || total == 0) ? infiniteTrafficThreshold + 1 : total`.

**E2 — does it touch a recorded design decision?**

```bash
git show $SHA | grep -nE 'Type:\s*"?[Rr]emote|fake[-_]?ip|[Ss]entry|QUERY_ALL_PACKAGES|per_app_proxy|current-config\.json|pprof|xray|warp'
```

Any hit requires a written justification against a named anchor in
`DESIGN-INVARIANTS.md`, or the commit is auto-rejected as `REJECT-DESIGN`.

**E3 — what does it fix, stated in this fork's terms?**

For every `fix:`, describe the failing condition a *Rayn* user actually hits. If
it cannot be described, it is not necessary. "Upstream fixed a bug" is not
evidence that this fork has the bug.

**E4 — is it a security fix?**

Security commits are **`ADAPT`, never `REJECT`**. Upstream `c4530d45` (deep-link
SSRF confirmation) does not apply as a patch here — deep-linking was rewritten to
`rayn://` only — but the vulnerability *class* still applies. Rejecting a
security fix on "that path doesn't exist" grounds is how forks ship CVEs.

### Step 4 — six dispositions, no seventh

| Disposition | Meaning |
|---|---|
| `TAKE` | cherry-picked essentially as-is |
| `ADAPT` | the intent was re-implemented against this fork's code |
| `ALREADY` | this fork already has the fix; `evidence` cites `file:line` |
| `REJECT-DEAD` | every touched path was deleted by this fork; `evidence` cites a deleted path |
| `REJECT-DESIGN` | contradicts a recorded invariant; `invariant` names the anchor |
| `DEFER` | not now — **must** carry an owner and a trigger condition |

A `DEFER` without a trigger is a `REJECT` with extra steps, and the next campaign
re-litigates it.

---

## Application mechanics

```bash
git cherry-pick -x -Xrenormalize <SHA>
```

`-x` records `(cherry picked from commit …)` for free provenance alongside the
`Upstream:` trailer. `-Xrenormalize` defuses the CRLF problem. Never `-n` across
multiple commits — per-commit revertability is the point of slices.

**SPLIT commits** — do not resolve inside the pick:

```bash
git cherry-pick --abort
git show $SHA -- <surviving paths only> | git apply --3way -
```

Commit with a note naming the dropped hunks; that note becomes the ledger's
`evidence`.

**Deleted subsystems** default to `REJECT-DEAD`, with two escalations: security
fixes (E4), and commits that move logic *out of* deleted UI into shared code.
Upstream's routing-page consolidation commits are exactly the second shape —
check each with:

```bash
git show $SHA --stat -- lib/singbox/ lib/features/settings/data/ lib/core/
```

**Translations are a derived artefact and are never cherry-picked.** Upstream
adds keys for features this fork deleted; taking them adds dead strings and
invites a future contributor to wire them up. Run last: diff
`assets/translations/en.i18n.json` against the snapshot, hand-pick only keys
whose owning feature survives, then `dart run slang`. Because
`translations.g.dart` is gitignored, a missing key is a **compile error** — the
analyzer enforces key-set consistency for free.

**Tracked generated files are regenerated, never picked.** The highest-severity
mechanical hazard in a campaign is a cherry-picked `.pb.dart` that does not match
the core's `.proto`: a silent wire-protocol mismatch that only fails at runtime,
in the field. Order is always core `.proto` lands → `make generate_dart_protoc` →
commit the regenerated output as its own commit.

Generated code is **not** tracked in general (`.gitignore` covers `**/*.g.dart`,
`**/*.freezed.dart`, `**/*.mapper.dart`, `**/*.gen.dart`), so nothing compiles
after a pick until codegen runs, and generated files never conflict. The tracked
exceptions that *do* need care:

| Path | Regenerate with |
|---|---|
| `lib/hiddifycore/generated/**` | `make generate_dart_protoc` |
| `lib/gen/hiddify_core_generated_bindings.dart` | `dart run ffigen` (needs `hiddify-core/bin/desktop.h`) |
| `lib/core/db/db.steps.dart` | `dart run build_runner build --delete-conflicting-outputs` |
| `pubspec.lock` | `flutter pub get` |
| `android/.../billing/RaynBilling.g.kt` | `dart run pigeon --input pigeons/rayn_billing.dart` |

**Drift schema.** Absolute rule: **fork schema numbers are append-only; upstream's
numbering is discarded.** Any upstream schema commit is therefore **always
`ADAPT`, never `TAKE`** — see `DESIGN-INVARIANTS.md#drift-schema-numbering`.

---

## The ledger

`LEDGER-app.tsv` and `LEDGER-core.tsv`, tab-separated:

```
upstream_sha  date  subject  bucket  disposition  rayn_sha  invariant  evidence  reviewer  campaign
```

TSV rather than Markdown because the honesty checks are `comm` / `join` / `awk`
and Markdown tables do not `join`. Full 40-character SHAs — abbreviations collide
over a fork's lifetime. `rayn_sha` is required for `TAKE`/`ADAPT`; `invariant` is
required for `REJECT-DESIGN`; `evidence` is one line. A new campaign **appends**;
it never rewrites prior rows.

Rejection is permanent. The next backlog is computed from the watermark tag, so
rejected commits are never re-enumerated. When upstream keeps building on a dead
subsystem, the new commits triage fresh — and the prior `REJECT-DEAD` rows are
the reviewer's shortcut.

### Three honesty checks

**1. Completeness** — every backlog SHA appears exactly once:

```bash
comm -3 <(git log --no-merges --format=%H <watermark>..<snapshot> | sort) \
        <(cut -f1 docs/upstream/LEDGER-app.tsv | tail -n +2 | sort)
# must be empty
```

**2. Non-repudiation** — every `TAKE`/`ADAPT` names a commit that really landed:

```bash
git merge-base --is-ancestor $rayn_sha custom-main
```

**3. Reverse traceability** — every campaign commit carries an `Upstream: <sha>`
or `Upstream: none` trailer:

```bash
git log --format='%H %(trailers:key=Upstream,valueonly)' <watermark>..custom-main
```

Check 3 is what stops something being picked and then not recorded. Worth keeping
permanently, not just during a campaign.

---

## Validation gate

Per slice:

```bash
flutter pub get && dart run slang && dart run build_runner build --delete-conflicting-outputs
flutter analyze          # must not regress against BASELINE.md (exits 1 on warnings)
flutter test             # must not regress against BASELINE.md
```

and in WSL, from `hiddify-core/`:

```bash
go build ./v2/...
go test -tags with_gvisor,with_quic,with_wireguard,with_utls,with_clash_api,with_grpc,with_awg,tfogo_checklinkname0,with_conntrack ./v2/...
```

Three things about the Go commands are not obvious and are easy to get wrong:

- **`go build ./...` does not work and never did.** `cmd/bydll/clibydll.go` is cgo
  that calls `parseCli`, which is exported from the c-shared library built out of
  `platform/desktop`. It cannot link standalone, so `./...` always fails at
  `undefined reference to parseCli`. Scope to `./v2/...`.
- **The tag list is mandatory.** Without it
  `TestBundledRuleSetFilesSatisfyConfig` calls `t.Skipf` and the package reports
  `ok` while checking nothing.
- **`flutter analyze` exits non-zero** on warnings and infos, so CI must compare
  counts against `BASELINE.md` rather than trusting the exit code.

For any slice touching `builder.go`, `dns.go`, `outbound.go`,
`config_option_repository.dart` or `singbox_config_option.dart`: additionally
rebuild the `raynconfigdump` core and diff the generated config against the
goldens in `hiddify-core/v2/config/testdata/golden/`. **That diff, pasted, is the
slice's review artifact.**

A slice ships if and only if every count matches or beats `BASELINE.md` and the
golden diff is empty or explained.

---

## Stop conditions

Abort and escalate; do not work around:

- `BASELINE.md` cannot be reproduced green on a clean `custom-main`.
- The golden config baseline cannot be produced.
- `git submodule status` fails.
- `git status` is not clean at the start of a slice.
- A slice requires editing `hiddify-core/hiddify-sing-box/`. That is a **third
  fork** — full stop.
- Upstream `main` moves past the snapshot mid-campaign.

## Never

- `git merge upstream/main`, or rebase `custom-main` onto it.
- Run `make windows-prepare` / `windows-libs` / `android-libs` / `macos-libs` /
  `linux-*-libs`. They `curl` Hiddify's **prebuilt** core and untar it over the
  custom build. Only `build-*` targets are safe.
- Ship anything built with `EXTRA_TAGS=raynconfigdump`.
- Cherry-pick anything under `lib/hiddifycore/generated/**`, `lib/gen/`,
  `pubspec.lock` or `db.steps.dart`.
- Resurrect a file listed in `rayn-deleted.txt` without a ledger row saying why.
- Renumber, edit or delete Drift steps `from5To6`…`from9To10`, or
  `drift_schema_v6..v10.json`.
- Take upstream's translation files.
- Batch multiple ledger rows into one implementation commit.
- Enable `rerere.autoupdate`.
- Trust a commit subject.
