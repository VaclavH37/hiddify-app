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

## Go core — **NOT green**. Two known failures, both understood.

```bash
go build ./v2/...
go test -tags with_gvisor,with_quic,with_wireguard,with_utls,with_clash_api,with_grpc,with_awg,tfogo_checklinkname0,with_conntrack ./v2/...
```

| Package | Baseline |
|---|---|
| `go build ./v2/...` | **exit 0** |
| `v2/config` | **ok** — includes the golden and design-invariant tests |
| `v2/hcore` | **ok** — includes the debug-gating scans |
| `v2/hcore/tunnelservice` | **BUILD FAILED (vet)** — see K1 |
| `v2/profile/test` | **FAIL** `TestAddByContent` — see K2 |

`go build ./...` (unscoped) fails at `undefined reference to parseCli` and always
has: `cmd/bydll/clibydll.go` links against a symbol exported from the c-shared
library. Not a regression, not fixable by scoping differently. Use `./v2/...`.

### K1 — `v2/hcore/tunnelservice` fails `go vet`, so its tests never run

```
admin_service_commander.go:20:25  fmt.Sprint call has possible Printf formatting directive %d
tunnel_platform_service.go:162:15 non-constant format string in call to fmt.Printf
tunnel_platform_service.go:168:15 non-constant format string in call to log.Printf
```

**Inherited from upstream, not fork-introduced.** Verified: the fork's only edits
to these two files are the `RaynVPNCli` / `RaynVPNTunnelService` branding strings
at other lines. Line 20 is byte-identical at the merge base `a82d2b8f` and at
`custom-main`.

Line 20 is a **real bug**, not a lint nit:

```go
tunnelServiceAddress = fmt.Sprint("127.0.0.1:%d", tunnelServicePort)
```

`fmt.Sprint` does not interpret verbs, so this evaluates to the literal
`"127.0.0.1:%d18020"` — and that string is what `grpc.Dial` receives at three
call sites (`admin_service_commander.go:66, 90, 111`), the desktop tunnel-service
commander this fork renamed and actively ships.

**Upstream already fixed it**, in `b6c85f4 "fix: correct fmt usage and formatting
issues"` — one of the pending core commits. `upstream/main` has `fmt.Sprintf`.
This is a Phase 1 `TAKE` candidate, and until it lands the tunnelservice package
has no test coverage at all because vet stops the build.

### K2 — `v2/profile/test` `TestAddByContent` fails, and should

The test fetches a live V2Ray-format WARP subscription from
`raw.githubusercontent.com/hiddify/hiddify-next/.../test.configs/warp` and asserts
the parsed title is `🔥 WARP 🔥`.

It fails with `unable to determine config format` because this fork **deliberately
removed the V2Ray parser**: fork commit `9a5601d "Remove Ray2Sing"` deleted the
`ray2sing.Ray2SingboxOptions` branch from `v2/config/parser.go`, so parsing falls
through to Clash, which cannot read that format. WARP is removed here too.

So this is an upstream test for functionality this fork does not have. It is
**not** evidence of a regression, and it must not be "fixed" by restoring the
parser.

It should be quarantined with an explicit skip so that a *genuine* future failure
in `v2/profile` is visible — right now the package is red for a known reason,
which masks everything else. Not done yet; tracked as a Phase 0 follow-up.

### Consequence for the gate

Until K1 and K2 are resolved, "`go test ./v2/...` is green" is not a usable pass
condition. Compare **per-package** results against the table above: `v2/config`
and `v2/hcore` must stay `ok`, and neither known failure may grow new symptoms.

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
