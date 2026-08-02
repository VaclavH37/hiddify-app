# Design invariants

Decisions this fork has made that an upstream adoption could silently undo.

Each has an anchor. A ledger row with disposition `REJECT-DESIGN` **must** name
the anchor it violates in the `invariant` column. A row with disposition `TAKE`
or `ADAPT` that trips evidence check E2 must carry a written justification
against the named anchor.

`Enforced by` is the honest current state, not an aspiration. An invariant with
`Enforced by: nothing` is one that a careless merge breaks without any test
going red — those are the dangerous ones, and closing that column is the point
of Phase 0 of a catch-up campaign.

---

## Routing and rule-sets

### <a id="no-remote-rulesets"></a>No rule-set may be `Type: Remote`

Every rule-set is bundled in `assets/rulesets/*.srs` and extracted at runtime.
Remote rule-sets reintroduce a `raw.githubusercontent.com` dependency on the
cold-start path and leak the fact that this client fetches Hiddify's geo data.

- **Enforced by:** `hiddify-core/v2/config/block_rulesets_test.go` ·
  `TestNoRemoteRuleSets`
- **Background:** `RULESETS.md`

### <a id="ruleset-tag-filename-map"></a>The rule-set tag ↔ filename map spans four files

`Makefile` `fetch-rulesets`, `scripts/regen_rulesets_manifest.sh` (`FILES`),
`hiddify-core/v2/config/builder.go` (`Path:` literals), and
`block_rulesets_test.go` (`expectedBlockRuleSets`) must all agree. Changing one
alone produces a core that fails to start.

- **Enforced by:** `block_rulesets_test.go` ·
  `TestBundledRuleSetFilesSatisfyConfig` (partial — skips without build tags)
- **Background:** `RULESETS.md`

### <a id="no-ip-ruleset-in-dns-rule"></a>No IP-based rule-set in a DNS rule

A `geoip`/`-ips` set inside a sing-box **DNS** rule cannot match on address
(there is no address at query time), so the rule matches everything and every
domain is leaked to whichever resolver that branch selects. This has bitten this
fork before.

- **Enforced by:** `block_rulesets_test.go` · `TestBlockDNSRuleUsesDomainSetsOnly`

### <a id="no-fakeip"></a>FakeIP stays off

The hub runs `domainStrategy: AsIs` and needs real addresses. FakeIP was removed
along with `fakeip-remote-sites.srs`; `store_fakeip` is false.

- **Enforced by:** *nothing yet* — golden config assertion pending (no `fakeip`
  key, `inet4_range` absent)
- **Background:** `Makefile` `fetch-rulesets` comments, `RULESETS.md`

### <a id="no-ntp"></a>No NTP block in the built config

- **Enforced by:** `hiddify-core/v2/config/ntp_removal_test.go` ·
  `TestBuiltConfigHasNoNTPBlock`

### <a id="balancer-strategy-never-empty"></a>Balancer strategy is never empty

`DefaultHiddifyOptions()` upstream never sets it, and an empty strategy makes
sing-box fail at **service start** with `unknown load balance strategy` whenever
a profile has more than one outbound. The Dart side no longer exposes the
control, so the default must be self-sufficient.

- **Enforced by:** `hiddify-core/v2/config/balancer_strategy_test.go`

---

## Confidentiality of configuration

### <a id="no-plaintext-config-dump"></a>`data/current-config.json` is deleted, not gated

The upstream core writes the fully built config to disk in plaintext and logs
`"Current Config is:"`. That file contains the hub address, per-user UUIDs and
Reality shortIDs. This fork **deleted** the write, rather than putting it behind
a runtime flag — a flag is something a shipped binary can be talked into opening.

If an upstream commit reintroduces the write, the only acceptable adoption is
behind `//go:build raynconfigdump`.

- **Enforced by:** *nothing yet* — assertion pending (the only `SaveCurrentConfig`
  call site must be under the build tag)
- **Background:** `CORE_BUILD.md`

### <a id="config-encrypted-at-rest"></a>Config is encrypted at rest, and LevelDB never holds config content

Profiles live at `configs/<id>.enc` under AES-256-GCM with a per-install keystore
key. The core receives `configContent`, never `configPath`. `saveLastStartRequest`
persists the profile **name** only.

This one is explicitly flagged in `CORE_BUILD.md` as the regression that "silently
undoes everything above while every test still passes".

- **Enforced by:** *nothing yet* — assertion pending (a fixture hub hostname must
  not appear in plaintext in produced artifacts)
- **Background:** `CORE_BUILD.md`

### <a id="rayn-link-wire-format"></a>`rayn://import/<token>` is AES-256-GCM, and is obfuscation not authentication

Symmetric envelope since 2026-07-29; RSA is gone. Because the nonce is random,
cryptolinks must never be string-compared. The URL form must stay
`rayn://import/<token>` — `Uri.host` lowercases the authority and corrupts
case-sensitive base64url.

- **Enforced by:** `test/utils/rayn_link_key_test.dart`,
  `test/utils/rayn_token_test.dart`
- **Background:** `RAYN-LINK-SYMMETRIC-MIGRATION.md`

### <a id="rayn-only-deep-links"></a>Only `rayn://import/<token>` is accepted

Legacy schemes, raw `https` paste, base64 config paste, the manual-URL form and
the `?url=` parameter were all removed. Upstream continues to develop
profile-import deep links; adopting any of it re-opens the surface.

- **Enforced by:** *nothing yet* — parser assertion pending (`hiddify://`, `sn://`,
  `clash://` must be rejected)

---

## Diagnostics

### <a id="pprof-behind-build-tag"></a>pprof and goroutine dumps only exist behind `raynconfigdump`

Upstream starts `net/http/pprof` on `localhost:6060` gated on a **user-settable**
debug flag, and writes a goroutine dump naming sing-box and hiddify-core on any
failed `CloseService()`. Both are compiled out here: the code lives in
`v2/hcore/debugtools.go` / `debugtools_disabled.go` behind the build tag.

A build tag is the only gate a shipped binary cannot be talked into opening.

- **Enforced by:** *nothing yet* — assertion pending (`go list -deps` for a
  shipped-tag build must not contain `net/http/pprof`)
- **Background:** `CORE_BUILD.md`

### <a id="debug-log-level-debug-builds-only"></a>Debug mode and Log level exist only in debug builds

Below `warn` the core logs every connection destination and every DNS lookup,
documenting both the user's activity and this client's routing design. The two
tiles are wrapped in `if (kDebugMode)` so release AOT dead-code-eliminates them
and their string literals.

- **Enforced by:** the `kDebugMode` const itself
- **Background:** `CORE_BUILD.md`, `lib/features/settings/overview/settings_page.dart`

### <a id="never-ship-raynconfigdump"></a>A core built with `raynconfigdump` must never ship

It writes the full built config to `data/debug-built-config.json` in plaintext.

---

## Telemetry and store compliance

### <a id="no-sentry"></a>Sentry stays removed, and no telemetry replaces it

Removed entirely, including the DSN dart-defines in the Makefile and the native
crashpad checkouts under `external/`. No ambient telemetry may be reintroduced
without explicit approval.

- **Enforced by:** *nothing yet* — assertion pending (`sentry` absent from
  `pubspec.lock`; no `import 'package:sentry`)

### <a id="no-query-all-packages"></a>`QUERY_ALL_PACKAGES` is not requested

Removed with the per-app-proxy feature for Play compliance. An upstream manifest
change re-adds a permission that blocks release.

- **Enforced by:** *nothing yet* — assertion pending (absent from the merged
  `AndroidManifest.xml`)
- **Background:** `PLAY-SUBMISSION.md`

### <a id="obfuscate-shipped-artifacts"></a>Every shipped artifact is built with `--obfuscate --split-debug-info`

This is the layer that hides the `rayn://` key derivation. Note obfuscation does
**not** strip string literals, which is why key-path logging is `kDebugMode`-gated
separately.

- **Enforced by:** *nothing yet* — assertion pending (over the Makefile release
  targets)

### <a id="no-upstream-autoupdate"></a>No in-app auto-update

`lib/features/app_update/` and `appcast.xml` were deleted. Upstream continues to
maintain them.

---

## Networking policy

### <a id="auth-host-direct"></a>The auth host is always reached DIRECT, never tunnelled

### <a id="logout-local-only"></a>Logout is local-only

`POST /api/public/logout` must never be called; the server session simply lapses.

### <a id="no-url-rotation-allowlist"></a>No hardcoded domain allowlist for URL rotation

An allowlist for `new-url` / `fallback-url` breaks failover and fingerprints the
install base. The audit finding it came from is resolved by privacy-policy
disclosure, not code.

### <a id="probe-urls-cn-resolvable"></a>Connection-test hostnames must be CN-resolvable, or IP literals

Probe hostnames get force-pinned to `doh.pub` with a 24h TTL and the answer leaks
into browser traffic. Poisoning `gstatic`/`google` previously broke `google.com`.
Prefer IP literals.

### <a id="no-copy-about-censorship"></a>No GFW, China, censorship or country references in user-facing copy

Applies to all strings about routing, split-tunnelling and per-app proxy.
Upstream copy does not follow this rule.

---

## Data layer

### <a id="drift-schema-numbering"></a>Drift schema numbers are append-only; upstream's numbering is discarded

This fork is at `schemaVersion => 10` and owns `from5To6`…`from9To10` plus
`lib/core/db/schemas/drift_schema_v6..v10.json`. Upstream is at 5 and its next
bump will be 6 — a different v6 from this one, while **shipped installs are
pinned to this fork's v6 on disk with no way to tell them apart**.

Therefore any upstream schema commit is **always `ADAPT`, never `TAKE`**:

1. Read upstream's step body; extract the intent (which column or table).
2. Do **not** touch `from5To6`…`from9To10` or `drift_schema_v6..v10.json`. They
   describe installs that already exist.
3. Add the intent as a new `from10To11`, using this fork's `_columnExists()`
   guard idiom (`lib/core/db/db.dart`) — upstream's step will not have it, and the
   guard is what makes the migration re-runnable after a partial upgrade.
4. Bump `schemaVersion => 11`.
5. Regenerate `db.steps.dart`, `drift_schema_v11.json` and
   `test/drift/db/generated/schema_v11.dart`.
6. Add the new import to `test/drift/db/migration_test.dart` — the version loop
   is automatic but the import list is manual, so a version omitted there is
   silently untested.

Never renumber. If upstream's v6 does something this fork already did under a
different number, the disposition is `ALREADY` — but record it, because
upstream's v7, v8 … will keep colliding for the life of the fork.

---

## Core boundary

### <a id="never-edit-singbox"></a>`hiddify-core/hiddify-sing-box/` is never edited

It is an imported upstream dependency, consumed as a nested submodule plus a Go
`replace` directive. Editing it would force maintaining a **third** fork. All core
changes live in `hiddify-core/v2/**`.

Confirmed clean as of campaign 2026-08: the gitlink is byte-identical at the
merge base and at `custom-main`.

### <a id="no-xray"></a>The xray core is removed

### <a id="warp-removed"></a>WARP is removed

Note upstream converged on this independently (`a447f038`), which *reduces*
future divergence.
