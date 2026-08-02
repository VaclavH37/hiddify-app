# sing-box 1.14 bump — open regression, handoff

Branch `rayn/integration-2026-08` (both repos). `custom-main` is untouched,
green, and known-good — there is no pressure to resolve this quickly.

## Symptom

Tunnel enters "connecting" for well under a second, then disconnects. On Windows
the core restarts internally in a loop. `box.log` repeats, forever:

```
INFO monitoring: starting outbound monitoring initialize
INFO monitoring: registered 8 outbounds for monitoring
INFO monitoring: registered 3 outbound groups for monitoring
INFO network: updated default interface Wi-Fi, index 6
```

No ERROR, WARN, FATAL or panic anywhere in the log. The teardown is silent.

`H CORE STARTING:` appears **once** in the console while the block above repeats,
so the restart is internal to the core, below the gRPC entry point — the Flutter
app is not retrying.

## Ruled out, with evidence

| Theory | Evidence |
|---|---|
| Deprecated/removed config option | `TestRealProfileBuildsAValidConfig` passes: the real 4-VLESS profile builds and `CheckConfigOptions` accepts it on `170d8315` — router, DNS, rule-sets, every outbound |
| Zero outbounds | 4 proxy outbounds present and valid |
| DNS rule-action `strategy` migration | Router init succeeds, which is where a bad DNS rule fails |
| Bundled rule-sets | All load once staged |
| The app / Dart side | Same app built against `custom-main`'s core (`3a1c923e`) connects normally. Only app commit on the branch is Android-only Kotlin |
| The log-recursion bug | Fixed in `367e8a1`; log is now quiet and the loop persists |
| `experimental.monitoring` block | Removing it does **not** disable monitoring — 1.14 has it on by default and the block only tunes it. The log still said `monitoring enabled: true` with the block absent. Diagnostic was **invalid**, reverted in `c8eb9cd` |
| The `balance` outbound group | Omitting it verifiably worked (9→8 outbounds, 4→3 groups, balancer line gone) and the loop **persisted**. Reverted in `c91bef8` |

## The remaining lead — untested

Every cycle ends on `network: updated default interface Wi-Fi, index 6`.

Creating the tun **itself changes the default interface**. So the loop may be:

    service start → tun created → default interface changes →
    interface monitor fires → service restarts → tun created → …

That would explain the silence (no error — it is a "legitimate" restart), the
sub-second timing, and why it is Windows-specific in what we have observed so
far. Android is untested.

Things to try, cheapest first:

1. Build with `enable-tun: false` (proxy-only). If the loop stops, tun creation
   is the trigger and the interface monitor is the mechanism.
2. Look at what consumes the interface-monitor callback on the desktop path and
   whether 1.14 changed its debounce or its notion of "changed".
3. `strict_route` / `auto_route` interaction — both are on, and both manipulate
   routes in ways that move the default interface.

## If that fails: bisect

`3a1c923e..170d8315` is linear, 396 commits, ~9 rebuilds.

```
cd hiddify-core/hiddify-sing-box
git bisect start 170d8315 3a1c923e
```

Two things that will otherwise waste steps:

- `9b0342f`'s API migrations (`WARPEndpointOptions`, no `TLSFragmentOptions`, no
  `common/conntrack`) only compile against the **newer** half of the range. Early
  steps will fail to build for reasons unrelated to the bug — `git bisect skip`
  those, do not mark them bad.
- Each step needs `make build-windows-libs EXTRA_TAGS=raynconfigdump`, then
  `flutter build windows --debug`, then a connect attempt.

## Tooling built during this investigation

| Tool | Use |
|---|---|
| `scripts/verify_core_singbox.sh` | Which sing-box a built artifact actually contains. Written because a "rebuilt and tested" run turned out to be the old engine — checkout and artifact disagreed |
| `v2/config/checkconfig_test.go` | Validate a real profile's outbounds against the pinned sing-box, offline, via `RAYN_CHECK_CONFIG=<config.json>` |
| `v2/hcore/log_recursion_test.go` | Guards the platform-writer echo loop from returning |

## Process notes worth keeping

**Always move the submodule with the branch.** `git -C hiddify-core checkout X`
leaves `hiddify-sing-box` where it was; the mismatched tree then fails with
errors that look like real code faults. Cost two builds this session.

    git -C hiddify-core checkout <branch> && \
      git -C hiddify-core submodule update --init hiddify-sing-box

**Verify a diagnostic did what you intended before believing its result.** The
monitoring experiment produced a clean negative that meant nothing, because
removing the config block did not disable the feature. The balancer experiment
was checked against the emitted config first, and its negative is trustworthy.

**The gate cannot see this class of fault.** `go build`, `go test`,
`CheckConfigOptions` and the golden configs all pass. None of them start a
tunnel. A scripted "start the core against a real profile and assert the tunnel
comes up" check would have caught both this and the log recursion, and is the
single highest-value thing to add before the next engine bump.
