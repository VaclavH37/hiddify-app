# sing-box 1.14 bump — tunnel regression, RESOLVED and VERIFIED ON DEVICE

Branch `rayn/integration-2026-08` (both repos).

**Root cause:** five DNS servers detoured to a direct outbound carrying no dial
options, which sing-box 1.14 refuses to start.
**Fix:** hiddify-core `4f1c652`, with the two gate gaps closed in `e3153a6`.
**Status:** closed. Verified in-process, then on Windows and Android devices
(2026-08-03).

## Symptom

Tunnel entered "connecting" for well under a second, then disconnected, and the
core restarted internally, forever. `box.log` repeated:

```
INFO monitoring: starting outbound monitoring initialize
INFO monitoring: registered 8 outbounds for monitoring
INFO monitoring: registered 3 outbound groups for monitoring
INFO network: updated default interface Wi-Fi, index 6
```

No ERROR, WARN, FATAL or panic anywhere. `H CORE STARTING:` appeared once while
the block repeated, so the restart was below the gRPC entry point.

## Cause

sing-box 1.14 added a check in `common/dialer/detour.go`: a detour that resolves
to a direct outbound with no dial options is rejected —
`detour to an empty direct outbound makes no sense`. Five DNS servers did that:

| Server | Detour | Why it is empty |
|---|---|---|
| `dns-direct`, `dns-cn-direct`, `dns-cn-direct-fallback` | `direct §hide§` | always was `&option.DirectOutboundOptions{}` |
| `dns-trick-direct`, `dns-remote-no-warp` | `direct-fragment §hide§` | *became* empty in this bump — 1.14 removed `TLSFragment` from `DialerOptions`, so builder.go's fragment block had to go |

The fix blanks those detours. That is behaviour-preserving: with no detour and
`DefaultOutbound` unset (`dns/transport_dialer.go` never sets it),
`dialer.NewWithOptions` falls through to `NewDefault` — a plain direct system
dial, exactly what detouring to an option-less direct outbound did. Domain
resolution is unchanged; it runs off `DomainResolver`, set either way.

`dns-trick-direct` still fragments — its `#fragment=300` sets fragmentation on
the server's own TLS options, independent of the dialer, and the golden pins it.
What was lost is the dialer-level fragmentation `direct-fragment §hide§` applied
to traffic routed *through* it; its only users were that detour and WARP
(removed), so there is no live consumer. Recorded, not repaired.

## Why the gate missed it — the part worth keeping

**`libbox.CheckConfigOptions` never starts a box.** It calls `box.New` then
`Close`. The detour check runs when the transport's dialer is initialised, in
`Start`. So the real profile validated clean while the shipped core could not
bring a tunnel up. Anything that fails in a `Start(stage)` method was invisible.

**The goldens pinned almost nothing.** `canonicalize` used plain
`encoding/json`. sing-box resolves the concrete options of every inbound,
outbound and DNS server through a registry on the context, so that reduced all
of them to `{tag, type}` — no tun MTU or stack, no DNS addresses, no TLS
settings, no detours. The fix commit changed five detours and produced a
**zero-byte golden diff**. Marshalling through `MarshalJSONContext` with
`include.Context` added 672 lines of previously unpinned shipped config.

Both are closed in `e3153a6`. `TestRealProfileStartsTheBox` starts a real box;
`RAYN_START_CONFIG=synthetic` needs no subscription, so it can run in CI.

## What was ruled out first (all still valid)

| Theory | Evidence |
|---|---|
| Deprecated/removed config option | real profile passed `CheckConfigOptions` |
| Zero outbounds | 4 proxy outbounds present and valid |
| DNS rule-action `strategy` migration | router init succeeded |
| Bundled rule-sets | all load once staged |
| The app / Dart side | same app on `custom-main`'s core connects normally |
| Log recursion | fixed in `367e8a1`; loop persisted |
| `experimental.monitoring` | removing the block does not disable it — diagnostic was **invalid**, reverted in `c8eb9cd` |
| The `balance` outbound group | omitting it verifiably worked and the loop persisted; reverted in `c91bef8` |
| tun creation / interface loop | **wrong lead.** `notifyInterfaceUpdate` only calls `ResetNetwork()`, never restarts. The log said `Wi-Fi`, not the tun adapter — it was the *initial* interface detection, i.e. simply the last line before start died |

The bisect plan drawn up here was never needed and has been dropped.

## Verification status

Done, in WSL, on `170d8315`:

- `go build ./v2/...`, full `go test ./v2/...` — green
- `TestRealProfileStartsTheBox` with `RAYN_START_CONFIG=synthetic` — **`sing-box started (0.08s)`**, where before the fix it failed at `start dns/https[dns-cn-direct]`
- goldens regenerated and reviewed

Done on device, 2026-08-03:

- **Windows** — core + Flutter rebuilt from this branch, tunnel connects and
  holds. Console logging confirmed after the `41abbec` fix.
- **Android** — release built and tested, confirmed working. This was the last
  open gap: the Kotlin platform-interface adaptation (`38a62cc2`) had only ever
  been compile-tested, and the in-process Go test starts a box with tun OFF, so
  tun creation and the platform interface were both unproven until this.

Nothing about the bump remains unverified.

## Tooling built during this investigation

| Tool | Use |
|---|---|
| `v2/config/startprofile_test.go` | actually starts a box; `synthetic` mode needs no real profile |
| `v2/config/checkconfig_test.go` | validates a real profile's outbounds offline (construction only) |
| `scripts/verify_core_singbox.sh` | which sing-box a built artifact actually contains |
| `v2/hcore/log_recursion_test.go` | guards the platform-writer echo loop |

## Process notes worth keeping

**Always move the submodule with the branch.** `git -C hiddify-core checkout X`
leaves `hiddify-sing-box` behind; the mismatched tree then fails with errors that
look like real code faults. Cost two builds.

    git -C hiddify-core checkout <branch> && \
      git -C hiddify-core submodule update --init hiddify-sing-box

**Verify a diagnostic did what you intended before believing its result.** The
monitoring experiment gave a clean negative that meant nothing.

**Reproduce in-process before rebuilding.** Every earlier experiment cost a full
core + Flutter rebuild and returned one bit. The Go test that found this took
minutes, named the failing server, and needed no device. Reach for it first.

**A green gate is only as good as what it executes.** Build, vet, unit tests,
`CheckConfigOptions` and the goldens all passed on a core that could not open a
tunnel — two of them because they were testing far less than they appeared to.
