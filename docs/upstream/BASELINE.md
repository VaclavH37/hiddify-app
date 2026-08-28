# Baseline

The numbers a catch-up slice must match or beat. Every one is a **measurement**,
not a recollection — this file exists because the campaign opened with two
conflicting remembered test counts (292 and 232) and no way to tell which was
right. It was 292.

Re-measure and update whenever the baseline legitimately moves (a slice that adds
tests, a deliberate lint fix). Never edit it to make a slice pass.

**Measured:** 2026-08-20, re-measured while adding the Apple StoreKit path
**Commit:** Apple IAP client, phases 1–2

---

## Dart — green

| Check | Command | Baseline |
|---|---|---|
| Analyzer | `flutter analyze` | **0 errors · 26 warnings · 264 infos** (290 issues) |
| Tests | `flutter test` | **430 passing**, 0 failing |

`flutter analyze` **exits 1** here, because it treats warnings and infos as
fatal by default. Compare the counts, not the exit code.

A block of the infos are `depend_on_referenced_packages` for `flutter_test` in
`test/**` — noise from `flutter_test` being a dev dependency. They are part of
the baseline; do not "fix" them during a catch-up slice.

### History

- 292/256 → 326/257 in slice S0.7, which added
  `test/design/design_invariants_test.dart` (34 cases). The single extra info was
  that file's own unavoidable `flutter_test` import.
- 326 → 356 tests at the Apple IAP client work: 16 new cases (12 for the
  per-store verify request shape and the finish-after-200 rule, 4 for
  `app_store` in the notification evaluator). That change is deliberately
  **analyzer-neutral** — verified file by file, it contributes 0 warnings and
  0 infos.
- The analyzer row above therefore also corrects a **pre-existing drift**. The
  tree measured 26 warnings / 261 infos *before* the Apple work, against a row
  still claiming 28/257: the 2026-08-02 measurement had gone stale (the suite
  had already grown 326 → 340 with no re-measure). This is a catch-up, not a
  regression introduced by that change.
- 356 → 377 tests at the hub-tier work (`subscription-hub-tier`): 19 cases for
  the tier/countdown/dwell helpers plus 2 for the header allowlist. The single
  extra info is `test/features/profile/hub_tier_test.dart`'s own `flutter_test`
  import — the same unavoidable one every test file here contributes. The lib
  changes are analyzer-neutral, and deleting the unreferenced
  `features/stats/widget/traffic_quota_card.dart` cost nothing either, since it
  contributed no issues.
- 377 → 378 when the hub-tier dwell floor became asymmetric: two tests that
  encoded the symmetric behaviour were replaced by three. Analyzer unchanged at
  288 — the change is a single condition plus comments, in files that already
  existed.
- 378 → 393 at the first Phase 2 reachability work, then 393 → 424 when that
  design was replaced by the precached-standby one
  (`PHASE2-STANDBY-PRECACHE-DESIGN.md`). The second move is a net figure: the
  two-leg probe's 12 cases were deleted along with the API they covered, and 43
  replaced them — the config-slot storage contract and freshness policy, the
  failover guards, lease, retry floor, flap-cap pruning and hub fingerprint, and
  the standby fetch's wire contract including its rejection of a primary-tier
  answer. 424 → 428 adds the post-revert failover backoff, and
  428 → 430 the tier-aware rotation test that stops a quota-tier flip reading
  as a hub rotation.
- The two extra infos are `config_slot_test.dart` and
  `hub_reachability_test.dart` each importing `flutter_test`, which every test
  file in the repo does. The lib changes are analyzer-neutral.

## Go core — green

```bash
go build -ldflags=-checklinkname=0 ./v2/...
go test -tags with_gvisor,with_quic,with_wireguard,with_utls,with_clash_api,with_grpc,with_awg,tfogo_checklinkname0,with_conntrack -ldflags=-checklinkname=0 ./v2/...
```

`-ldflags=-checklinkname=0` is required from hiddify-sing-box `170d8315`
onward: `libbox/internal/oomprofile` uses `//go:linkname` to reach
`runtime/pprof.parseProcSelfMaps`, which the linker rejects by default. It is
already in the Makefile's `LDFLAGS` for production builds; these commands and
`rayn-checks.yml` now carry it too.

Set now rather than when the bump lands, and verified harmless against the
current pin `3a1c923e` — it only disables a check nothing here currently trips,
and the suite is green with it.

| Package | Baseline |
|---|---|
| `go build ./v2/...` | **exit 0** |
| `v2/config` | **ok** — golden, design-invariant and rule-set tests |
| `v2/hcore` | **ok** — debug-gating scans |
| `v2/hcore/tunnelservice` | **ok** (no test files) |
| `v2/profile/test` | **ok** — `TestAddByContent` skipped, see K2 |

`go build ./...` (unscoped) fails at `undefined reference to parseCli` and always
has: `cmd/bydll/clibydll.go` links against a symbol exported from the c-shared
library. Not a regression, not fixable by scoping differently. Use `./v2/...`.

### K1 — resolved 2026-08-02

`v2/hcore/tunnelservice` used to fail `go vet`, which runs before `go test`, so
the package would not build under test and had no coverage at all:

```
admin_service_commander.go:20:25  fmt.Sprint call has possible Printf formatting directive %d
tunnel_platform_service.go:162:15 non-constant format string in call to fmt.Printf
tunnel_platform_service.go:168:15 non-constant format string in call to log.Printf
```

Inherited from upstream, not fork-introduced — the fork's only edits to those
files are the `RaynVPNCli` / `RaynVPNTunnelService` branding strings at other
lines. Line 20 was a real bug: `fmt.Sprint` does not interpret verbs, so
`tunnelServiceAddress` evaluated to the literal `"127.0.0.1:%d18020"`, which is
what `grpc.Dial` received at three call sites in the desktop tunnel-service
commander this fork ships.

Latent rather than live: `grpc.Dial` is lazy and all three sites immediately
`defer conn.Close()` without issuing an RPC, so nothing failed against the
malformed address. It would the moment anyone added a real call.

Fixed by cherry-picking upstream `b6c85f4` — the first row in `LEDGER-core.tsv`.
Note the package builds and vets clean now but still has **no test files**; the
fix removed an obstruction, it did not add coverage.

### K2 — resolved 2026-08-02

`v2/profile/test` `TestAddByContent` fetches a live V2Ray-format WARP
subscription from `raw.githubusercontent.com` and asserts the parsed title is
`🔥 WARP 🔥`. It cannot pass here: fork commit `9a5601d "Remove Ray2Sing"` deleted
the `ray2sing.Ray2SingboxOptions` branch from `v2/config/parser.go`, so parsing
falls through to Clash, which cannot read that format. WARP is removed too, and
the test needs network access it should not have in a gate.

`t.Skip`ped with that reasoning in place, rather than deleted, so the question
resurfaces at the right spot if the parser ever returns. The intent it was
accidentally testing is now pinned offline by `TestV2RayFormatIsNotParsed` in
`v2/config/design_invariants_test.go`, which asserts V2Ray content is rejected —
see [no-v2ray-parser](DESIGN-INVARIANTS.md#no-v2ray-parser).

## Golden configs

Six fixtures under `hiddify-core/v2/config/testdata/golden/`, pinned
byte-for-byte by `v2/config/golden_config_test.go`.

They are built **in-process** via `BuildConfig`, the same way
`block_rulesets_test.go` already does — not by running a `raynconfigdump` core
against live profiles. That was the original plan and this is strictly better:
no native build, no WSL, no live subscription, runs in CI in under a second, and
it is deterministic. The `raynconfigdump` path remains the way to verify a
*shipped binary*; this is the way to catch config drift in review.

| Fixture | sha256 |
|---|---|
| `shipped.json` | `8e7b73891707f4ab743feaf81c2155a7694cc60dc9b93fdcdf3e255d98492cf9` |
| `shipped-blockads-off.json` | `ff3c28809329477eb370c1a137b335adddbdd867366ca17ba5e01efbbda234e2` |
| `shipped-blockquic-off.json` | `fb93053ade213e7402727cf6b6bc75dacb5d97e30319cd7780bc0d6f364ae262` |
| `shipped-debug.json` | `a5761151ec5a1d6c8df328e2f83fd4e9ec58314dc673f59f84a30af214a45697` |
| `shipped-many-outbounds.json` | `6e13d4c94515e38e34c89dbf350ed1473904e3922693f874a478f31750fc43fe` |
| `go-defaults.json` | `245b816a71dcb32cd03af8d422f79f8b87d61245a638eb6edab1141c7d9cf85d` |

Rebaselined at hiddify-core `e3153a6`, which is also the point these fixtures
first became worth much. Until then `canonicalize` marshalled with plain
`encoding/json`, and because sing-box resolves the concrete options of every
inbound, outbound and DNS server through a registry on the context, all of them
were pinned as `{tag, type}` and nothing else — no tun MTU or stack, no DNS
server addresses, no TLS settings, no dialer detours. The commit that fixed the
sing-box 1.14 tunnel regression changed five detours and produced a **zero-byte**
diff against the old fixtures. Marshalling through `MarshalJSONContext` with
`include.Context` added 672 lines of shipped config that had never been pinned.
The earlier hashes above this line were real, just far less load-bearing than
they looked.

Two things worth knowing before trusting these:

**`DefaultHiddifyOptions()` is not the shipped configuration.** The Go defaults
have the tun OFF, `TUNStack: "mixed"`, `BlockAds` off, `DirectPort: 12337` and a
bare `1.1.1.1` resolver. The Flutter client ships tun ON, gvisor, blocking on,
`DirectPort: 0` and DoH. The two configs differ by 1.2 KB. That is why there is
both a `shipped` fixture (transcribed from `singboxConfigOptions` in
`config_option_repository.dart`) and a `go-defaults` one — a matrix built only on
Go defaults would pin a config the product never emits.

**The build was not reproducible until 2026-08-02.** `dns.go` built a DNS rule's
`Domain` list by ranging over a Go map, and Go randomizes map iteration, so the
config differed run to run. Harmless for routing (a domain list is a match set)
but it made "did this change alter the config?" unanswerable. Fixed by sorting;
`TestBuildConfigIsDeterministic` runs 32 rounds to keep it that way — a two-build
check passes half the time on a two-element permutation and did in fact pass
while the bug was live.

---

## Environment

| | |
|---|---|
| Flutter | 3.41.9 stable · revision `00b0c91f06` |
| Dart | 3.11.5 stable |
| Go (WSL Ubuntu-24.04) | **1.25.6** — matches the `go 1.25.6` directive in `hiddify-core/go.mod` exactly |

`go.mod` pins a full patch version with **no `toolchain` directive**, so an older
1.25.x refuses to build rather than auto-upgrading. **Go 1.26 must not be used** —
it produces `.so` files that SIGABRT in Go runtime init.
