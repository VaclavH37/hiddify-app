# Baseline

The numbers a catch-up slice must match or beat. Every one is a **measurement**,
not a recollection — this file exists because the campaign opened with two
conflicting remembered test counts (292 and 232) and no way to tell which was
right. It was 292.

Re-measure and update whenever the baseline legitimately moves (a slice that adds
tests, a deliberate lint fix). Never edit it to make a slice pass.

**Measured:** 2026-08-02, re-measured after S0.7
**Commit:** end of Phase 0 slice S0.7

---

## Dart — green

| Check | Command | Baseline |
|---|---|---|
| Analyzer | `flutter analyze` | **0 errors · 28 warnings · 257 infos** (285 issues) |
| Tests | `flutter test` | **326 passing**, 0 failing |

`flutter analyze` **exits 1** here, because it treats warnings and infos as
fatal by default. Compare the counts, not the exit code.

Of the 257 infos, **16** are `depend_on_referenced_packages` for `flutter_test`
in `test/**` — noise from `flutter_test` being a dev dependency. They are part of
the baseline; do not "fix" them during a catch-up slice.

Moved from 292/256 to 326/257 in slice S0.7, which added
`test/design/design_invariants_test.dart` (34 cases). The single extra info is
that file's own unavoidable `flutter_test` import.

## Go core — green

```bash
go build ./v2/...
go test -tags with_gvisor,with_quic,with_wireguard,with_utls,with_clash_api,with_grpc,with_awg,tfogo_checklinkname0,with_conntrack ./v2/...
```

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
| `shipped.json` | `cd5420e251a4614af6fbb60306b78fb40a44a982339a209e3874e5fc299da5dc` |
| `shipped-blockads-off.json` | `0a09dd233b143fc23e309a7b76d4a233becea8bfdbafaecc7d114a2c66ac124e` |
| `shipped-blockquic-off.json` | `f8105577593eed881a011ce3e99900a02a60440ceb13df39da1c5c75e248c26e` |
| `shipped-debug.json` | `a0b8e8e6291fc3ba5ab1f93d4c7510721ce39415427b59cee153496091fc5afd` |
| `shipped-many-outbounds.json` | `b42e9512c1685dee2a9c3255560a2765a2b1e74350bc681ac8a04ed5f13ae93c` |
| `go-defaults.json` | `78dde984b61da456c7c235f3650b60c5e0a2cecd96ca30d38fb9b14ba64c12bc` |

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
