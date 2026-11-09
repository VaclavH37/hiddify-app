# Upstream catalogue: campaign 2026-11

Every commit Hiddify added between the last alignment check (`rayn/upstream-triaged-2026-08`) and `rayn/upstream-snapshot-2026-11`, which is v5.5.5 plus the few commits after it: 518 app commits and 172 core commits. Each one appears exactly once below. The authoritative record is `LEDGER-app.tsv` and `LEDGER-core.tsv`; this file is the readable version.

**How to read it**

- **Proposed** commits are recommended to bring in. Pick them one at a time. Until one lands, the ledger holds it as `DEFER`.
- **Already in Rayn** needs nothing.
- **Deferred** waits for the named trigger.
- **Rejected** will not be taken, for the reason given. Reasons starting with an anchor refer to `DESIGN-INVARIANTS.md`.

Nothing here was built or run. A commit was either read in full against our code, sampled with its group, or sorted by its files and subject because it changes no code we still run. Sorted and sampled rejections show upstream's own subject line.

| Outcome | Commits |
|---|---|
| Proposed | 45 |
| Already in Rayn | 34 |
| Deferred | 87 |
| Rejected, deleted or absent here | 401 |
| Rejected, against a recorded decision | 123 |
| **Total** | **690** |

## Proposed: Android, iOS and Windows

### 1. Android dead tunnel (landed for 1.6.4 as `5d38fc5a`)

| Commit | What it does | Why, in Rayn's terms |
|---|---|---|
| `0181dfe4` | Keeps the VPN platform interface across a front-core setup | MethodHandler.kt passed null; grpc_server.go:62 overwrites the process-wide interface after closeFront, so the next Restart fails with open /dev/tun: permission denied. Landed, reproduced and confirmed fixed on a phone 2026-11-09. |

### 2. Four seconds wasted on every mobile connect

| Commit | What it does | Why, in Rayn's terms |
|---|---|---|
| `9b152148` | One status wait, and the stream created once | core_interface_mobile.dart:406: the break leaves only the switch, so every mobile connect waits about 4 s extra. Proposed ADAPT. |

### 3. One cancelled call can kill every core stream

| Commit | What it does | Why, in Rayn's terms |
|---|---|---|
| `af389367` | Overrides http2 to 3.1.0 | pubspec.lock:817 is 2.3.1; core_stream_errors.dart documents it. A cancelled stream kills the channel and every core stream fails. Proposed ADAPT. |

### 4. Security: Windows core control port has no authentication

| Commit | What it does | Why, in Rayn's terms |
|---|---|---|
| `092b5ee7` | mTLS for gRPC, desktop half only | core_interface_desktop.dart:128 uses insecure credentials and grpc_server.go:360 has no auth, so any local process can drive the elevated core on port 21978. Security (E4). Proposed ADAPT. |
| `core cbe9a1ca` | mTLS for secure gRPC modes | grpc_server.go:360: the Windows mode has no auth, so any local process can drive the elevated core. Security (E4). Proposed ADAPT with 092b5ee7. |

### 5. Security: local proxy has no password while connected (design first)

| Commit | What it does | Why, in Rayn's terms |
|---|---|---|
| `core 71150af4` | Splits local and LAN ports; closes the VPN-mode port (VPN-mode part only) | builder.go:636: the mixed inbound on 12334 has no password while connected, so any local app can use it. proxyOnly fetches depend on it, so a design comes first. LAN half rejected, no-lan-sharing. Security (E4). Proposed ADAPT. |

### 6. Android back button after Settings

| Commit | What it does | Why, in Rayn's terms |
|---|---|---|
| `511d2e34` | Moves the settings PopScope to the shell | routing_config_notifier.dart:147 keeps a PopScope inside a branch that stays mounted; after visiting Settings, Android back can stop closing the app. Proposed ADAPT. |

### 7. Stuck status after a suspend, and leaked connections

| Commit | What it does | Why, in Rayn's terms |
|---|---|---|
| `8e95f602` | Keeps the last outbound and reopens an ended stream | No doOnDone in active_proxy_notifier.dart; after a suspend the button can stick on Connecting while the tunnel works. Proposed ADAPT. |
| `422a7b2a` | Shuts replaced gRPC channels | core_interface_mobile.dart:188,216 and desktop :84; each resume leaks connections against the iOS extension memory cap. Proposed ADAPT. |
| `364a935a` | Reopen backoff of 2 to 30 s | Goes with 8e95f602; without it, 2 s retries flood the logs. Proposed ADAPT. |
| `2c8b5c10` | Proxies page survives stream loss | proxies_overview_notifier.dart:80; the location list errors after a dropped stream. Proposed ADAPT. |

### 8. First connect behind slow permission dialogs (needs #2)

| Commit | What it does | Why, in Rayn's terms |
|---|---|---|
| `bb6d9785` | Answers the start call after the permission dialogs | MainActivity.kt startService returns immediately; on a fresh install slow dialogs can fail the first connect at about 20 s. Depends on 9b152148. Proposed ADAPT. |

### 9. Core: observers left open, pings stop when idle

| Commit | What it does | Why, in Rayn's terms |
|---|---|---|
| `core a89c3079` | Close also ends the daemon's observers | stop.go:34 calls only CloseService; StartedService.Close exists at our pin and is never called, so observers stay open on every disconnect. Proposed ADAPT. |
| `core 6ba0d6df` | The proxy stream keeps the monitor awake | proxy_info.go:188 never calls Touch, which exists at our pin; pings stop after the core has been idle. Proposed ADAPT. |

### 10. Connect button shows the wrong state

| Commit | What it does | Why, in Rayn's terms |
|---|---|---|
| `85bb1128` | Drops the last session's ping from the connect button | connection_button.dart:182, active_proxy_notifier.dart:27, rayn_core_service.dart:488: startWith(latest) re-emits the old list, so a reconnect briefly shows a false Connected with an old ping. Low severity. Proposed ADAPT, clearing latest on stop. |
| `ef2835ac` | Shows Connecting immediately | connection_notifier.dart:293; the button says Tap to connect for about a second after a tap. Proposed ADAPT. |
| `ff69cf23` | Sets the error before awaiting the failure dialog | connection_notifier.dart:311; a late Started during the dialog is overwritten, leaving an error over a working tunnel. Proposed ADAPT. |
| `390927b5` | Connect button keeps its last value during reload | connection_button.dart:127-167; the button flashes dimmed Starting after the core starts. Proposed ADAPT. |
| `0c357d63` | Shows a Disconnected-with-failure state as a failure | connection_button.dart:127; a failed start can read Tap to connect. Proposed ADAPT. |
| `c90f08ae` | Reads the dialog's dependencies before connecting | connection_notifier.dart:303-310; debug builds lose the failure dialog. Proposed ADAPT, dropping the Sentry lines. |
| `43fb83cf` | Shows Disconnecting on tap | connection_notifier.dart:315; the button stays Connected and tappable during stop. Proposed ADAPT. |
| `9fa1e611` | AnimatedSwitcher duplicate keys | connection_button.dart:302,336; a quick A-B-A flip gives a debug crash and a possible release glitch. Proposed ADAPT. |

### 11. Small visible fixes

| Commit | What it does | Why, in Rayn's terms |
|---|---|---|
| `676a8904` | Stops swallowing the Flutter error report (the idea only) | logger.dart:8 hides Flutter's own error presentation in debug. Proposed ADAPT of the idea: presentError in debug, with library and context in the log. The rest of the logging rewrite is rejected. |
| `567d1ca3` | Friendly dialog for a TUN address clash | Absent at rayn_core_service.dart:344; on Windows another VPN using 172.19.0.1 gives a raw object-already-exists error. Proposed ADAPT. |
| `d52027e6` | Bulk-update toast only when forced | profiles_update_notifier.dart:471; every periodic refresh pops a success toast. Proposed ADAPT. |
| `748fb8eb` | Toast on a failed proxy switch | proxies_overview_notifier.dart:126; a failed tap throws uncaught and looks ignored. Proposed ADAPT. |
| `c49d6edb` | Anchors the iOS share sheet | export_diagnostics.dart:26 and uri_utils.dart:36; iOS share can refuse and fall back to the clipboard. Proposed ADAPT. |
| `1685304f` | Cached ping sort, Android log dedupe, installer (log dedupe only) | rayn_core_service.dart:176-179; Android core lines are exported twice. Proposed ADAPT, dedupe only; the sort needs the core. |
| `247f1b5a` | Blocks a notification repost after close | ServiceNotification.kt updateStatus; an in-flight poll reposts the ongoing notification after stop. Proposed ADAPT. |

### 12. Malformed subscription headers

| Commit | What it does | Why, in Rayn's terms |
|---|---|---|
| `36064f6d` | Skips malformed ';' segments in subscription-userinfo | profile_parser.dart:697 throws on .second; a trailing ';' from the middleware fails every refresh. Whether the middleware can send it is unverified. Proposed TAKE. |
| `7ecc0aee` | Uses tryParse for the update interval | profile_parser.dart:765; a decimal or junk value fails the whole refresh. Proposed TAKE. |
| `4cc86c4e` | Pads a base64 profile-title that has no padding | profile_parser.dart:722; an unpadded title fails the whole refresh. Proposed TAKE. |

### 13. Windows portable download

| Commit | What it does | Why, in Rayn's terms |
|---|---|---|
| `8aaeb368` | Repacks the portable ZIP with Windows tar.exe | Makefile:466 runs GNU tar -a, writing a plain tar named .zip; Explorer shows it empty. Proposed ADAPT. |

## Proposed: macOS, for the Mac App Store port

Brought in during the port's Dart and build phases.

| Commit | What it does | Why, in Rayn's terms |
|---|---|---|
| `b725543c` | System-extension VPN engine; also surfaces changeOptions failures (error check only) | connection_repository.dart:236 ignores the failure. Engine rejected against mas-app-extension-only. Proposed ADAPT for the error check. |
| `e2d686d3` | Resolves relative resources against the core working directory | directories_provider.dart:26 uses the shared path on iOS only; Dart would write where RaynTunnel cannot read. Proposed ADAPT in the macOS port. |
| `76c968c7` | lipo shim splitting Flutter's multi-arch -verify_arch call | project.pbxproj:517,559; needed for a universal build. Proposed ADAPT through configure_macos_xcodeproj.rb. |
| `e69d9b38` | Developer ID identifiers; refuses another instance's core on the same port (port guard only) | core_interface_desktop.dart:93. Rest is Developer ID. Proposed ADAPT for the port guard. |
| `5a4dc4a2` | App Store variant, proxy-only tunnel, unsigned root variant (build recipe only) | Extension present, RaynTunnel.entitlements:12; dist.sh absent. Proposed ADAPT for the App Store recipe, at the first signed build. |
| `819a2f7c` | App Store upload script using altool and an API key | Absent. Proposed ADAPT in the macOS port. |
| `0c5bf7c6` | Fixes ITMS-90255: unreadable LaunchAtLogin helper plist and AppleDouble files | Helper copied at project.pbxproj:599. Proposed ADAPT at the first signed build. |
| `89c6d730` | Cancels gRPC calls cancelled before ready, preventing a 64 KB channel stall | rayn_core_service.dart:463,501,622,700. Proposed ADAPT. |
| `c63fc8fa` | Re-arms listeners only on a real change; bounds stop to 5 s (timeout only) | Guard at rayn_core_service.dart:320; no timeout at :381. Proposed ADAPT. |

## Proposed: Linux, fixes now

Also `787dcf9a` (desktop entry and AppImage update keys, from campaign 2026-08), reopened by the change to `#linux-port-plan`. It is adapted with the Linux rebrand, without the anti-censorship keywords or Hiddify's update URL.

| Commit | What it does | Why, in Rayn's terms |
|---|---|---|
| `33779458` | World-readable AppDir; appimagetool failure stops the build | Makefile:556,566. Proposed ADAPT with the Linux rebrand. |
| `core b841a3a9` | capget overruns its buffer | linux_utils.go:30 passes one CapUserData for a call that writes two. No shipped caller, corruption once Linux ships. Security (E4). Proposed TAKE. |
| `core eeaf27e6` | godebug multipathtcp=0 | Absent in go.mod. Go 1.24+ listens on MPTCP by default on Linux; shipped listeners are loopback only, so the value is for Linux. gomobile builds ignore the line. Security (E4). Proposed ADAPT. |

## Already in Rayn

| Commit | What it does | Where |
|---|---|---|
| `e6e774d0` | Native iOS swipe-back | app_theme.dart:89 Cupertino transitions with GoRoute builder. |
| `606552b3` | Excludes generated code from the analyzer | analysis_options.yaml exclude. |
| `6eeb29c7` | Stop always stops the saved VPN | core_interface_mobile.dart:438. |
| `5141983d` | Friendly extension display name | project.pbxproj:1007. |
| `60b70ae7` | ALREADY_STOPPED is a normal stop; unblocker wiring | core_status.dart:61; the chain half is absent (no-chains). |
| `0a2f9bc7` | Stops after the no-profile dialog | connection_button.dart:197. |
| `9a6dc180` | Screen-reader label on the sheet barrier | dialog_notifier.dart:46 uses showModalBottomSheet. |
| `0cc018e5` | Removes an unused BottomSheetPage export | No such export in lib/utils/utils.dart. |
| `33be933e` | Deletes the temp file | profile_parser.dart:56-63 holds the body in memory. |
| `240fc1fa` | responseType for get | getText at dio_http_client.dart:188. |
| `c8b1a040` | iOS release validation; signing in the pbxproj | Signing present, project.pbxproj:802. iOS validation scripts not assessed. |
| `1b232880` | iOS relaunch status and cert IPC | The fork adopts the bg secret, core_interface_mobile.dart:130-150. Not device-tested. |
| `30bd7d3b` | Forces the app user agent | dio_http_client.dart:61; profile_parser.dart:284. |
| `5039971a` | Removes unused imports | No dart:typed_data import in core_interface_mobile.dart. |
| `ee5f5def` | Drops two this. qualifiers | dio_http_client.dart:61 is already unqualified. |
| `bbd57937` | Reconnects when the service mode changes | No mode exists to change, config_option_repository.dart:264. |
| `67486c85` | Hiddify Store identity; Inno uninstall name and icon | auto_start_notifier.dart:19 matches make_config.yaml:3; the uninstall icon is cosmetic. |
| `e37bc1f1` | Logs an unreachable core at debug | core_stream_errors.dart:32, called from rayn_core_service.dart:735. |
| `4e5f75de` | App Store build compiles out root prompts | None exist: no NSAppleScript, osascript or SMJobBless. |
| `23b06e25` | iOS memory limit forced on | ExtensionProvider.swift:25; start.go. |
| `34650255` | A reconnect is not logged as an error | core_stream_errors.dart:33. |
| `d513e14d` | Xray option off and hidden | Option absent outside generated hiddify_options.pb.dart (no-xray). |
| `core c2fd0b0d` | Omits TUN IPv6 under IPv4Only | Host probe at builder.go:550. |
| `core 23a28461` | Test scaffolding for c2fd0b0d | See c2fd0b0d. |
| `core 083f2370` | Platform writer stops re-logging itself | log_interface.go:51. |
| `core b6ce8dd8` | SelectOutbound errors when the core is stopped | commands.go:229. |
| `core eca1c286` | An empty tag list returns an error | builder.go:335. |
| `core 035c25a3` | Refactors an IPv6 helper | See c2fd0b0d. |
| `core cbe71650` | Same helper, constant swap | See c2fd0b0d. |
| `core 6a6f28d6` | Cert SANs and a TLS 1.2 minimum | grpc_server.go:439. |
| `core f4d1de2b` | gomobile macOS bind target | core Makefile:284. |
| `core fb80a413` | Balancer tolerance of 100 ms plus a ratio | Tolerance at builder.go:320. |
| `core b52cdcff` | UrlTestActive walks to the leaf | commands.go:333 is sufficient at depth two. |
| `core 3594cd9b` | AAAA per proxy, refuses v6 | builder.go:776. |

## Deferred

### Until: sing-box pin move

| Commit | What it does | Notes |
|---|---|---|
| `6506c430` | cancelNotification, package names and a dnsMode gate | Names already in PlatformInterfaceWrapper.kt:73; cancel is not in the pinned libbox; the core never sets dnsMode. |
| `c431fa0b` | libbox stubs for a newer sing-box | Those methods are not in the fork's platform.go until a pin move. |
| `221220d2` | CI signing and libbox signature stubs | CI is not our path; the stubs need the newer engine. |
| `2ab88d92` | Libbox SFTP and SSH signature churn | Those methods are not in the pinned libbox. |
| `b68fd546` | Libbox SFTP and SSH signature churn | Those methods are not in the pinned libbox. |
| `58067507` | Libbox SFTP and SSH signature churn | Those methods are not in the pinned libbox. |
| `core 8209feb6` | Engine migration: Abstract*Options, groupNow, platform stubs | dialDetour equivalent at dns.go:45. |
| `core 40986a16` | Filters dns outbounds and hinvalid placeholders | Partly at builder.go:178. |
| `core 65e674a0` | Engine sync; marks x/crypto direct | go.mod line only, no code. |
| `core 06eaf616` | Sequential DNS group with fallbacks | The group type is missing at 170d8315. |
| `core aaf05d25` | Engine sync; grpc 1.82.1, circl 1.6.4, go-jose 4.1.4 | go.mod only; custom-main has grpc 1.79.1 (go.mod:17). Whether any advisory reaches Rayn is unverified. |
| `core 797ce421` | Hot-reload RPC | daemon.HotReload exists only at the newer pin; a restart works. |
| `core 5d2d7d98` | mieru bump, engine sync | go.mod only. |
| `core 7c80a18b` | Queues start and stop; RPCs answer at once | Lock held at start.go:91; a disconnect waits out a slow connect. |
| `core 7353a741` | Stop interrupts a starting box | Absent at our pin. |
| `core 2ed0bb5f` | Restores dialer TLS fragment; migrates tls_fragment; adds xhttp and http transports | The pin has no dialer TLSFragment (outbound.go:94-98 commented); REALITY returns at outbound.go:32. |
| `core bfb7d0a5` | Adapts to newer engine API (Start scope, SFTP strings, prefixables) | adapter.Scope absent at the pin; builder.go:960 already removed the 10.10.34 rule. |
| `core e6f1c8da` | amneziawg-go v3 bump, engine sync | go.mod only. |
| `core f8c03536` | Status enum, chain display; retries a failed SubscribeGroup; nil-pinfo guard | proxy_info.go:143,192 not hit: streams open only once connected (active_outbound_groups.dart:38, start.go:178). Read only, not run. |
| `core 36f42747` | Points go.mod at engine replace directories | go.mod only; the paths exist only in the newer submodule. |
| `core 87e446dc` | Drops StoreWARP and MASQUE options, engine bump | builder.go:468 keeps StoreWARPConfig; no defect. |
| `core 8c54e88b` | IPv6 gating, sing15 stack, auto_redirect | Absent. |
| `core 3ba4f053` | Engine sync: Xray, XDRIVE, MasterDNS; x/net 0.62, grpc 1.85 | go.mod and a Makefile tag; the xray and DNS-tunnel parts stay barred even then. |
| `core 46eb30a7` | Reorders go.mod require blocks | go.mod only, no fix. |
| `core a5a5091c` | OutboundInfo.error reason | Needs a field at the newer pin. |
| `core dd6ba691` | Engine sync: Soar DNS tunnel, ray2sing | go.mod only; Soar itself is out of the product. |
| `core 3f692daa` | Comment change; engine display types | adapter.DisplayType absent at the pin; proxy_info.go:29 uses detour.DisplayType. |
| `core 8e0e00f4` | Moves the Soar go.mod line | go.mod only. |
| `core 47f500d4` | Release; Mirage mask pin | Pin only. |
| `core 3b61f92c` | Engine bump, amneziawg panic | Pin only; AmneziaWG is not used here. |
| `core f40d9b0e` | Engine bump, cached-conn release | Unsynchronised CachedConn in sing common/bufio/cache.go:39 looks related; the fix could not be read. |

### Until: a macOS CI job is created

| Commit | What it does | Notes |
|---|---|---|
| `ce2c437f` | Makefile alias for an App Store CI job | Absent. |
| `98e60725` | App Store artifact handling in CI | Absent at build.yml:104. |
| `178d70ef` | iOS manual signing; App Store workflow tweaks | iOS part not compared. |
| `fddbb44c` | Copies the App Store pkg into CI output | Absent. |
| `5af6b6ed` | Xcode 26 for an Icon Composer icon | Asset catalog at project.pbxproj:798; icon check only. |

### Until: the owner wants a status badge

| Commit | What it does | Notes |
|---|---|---|
| `d633fa2d` | Dock and taskbar connected badge | Absent; text badge at system_tray_notifier.dart:109. |
| `0b459ae4` | Badge logic in Dart | Absent. |
| `8ab20b01` | Refines the badge and proxy card | Absent. |

### Until: 797ce421 is adopted

| Commit | What it does | Notes |
|---|---|---|
| `core 0aefc425` | HOT_RELOADING state | Absent. |
| `core a1bdfaf3` | Profile name from memory | commands.go:58; a restart resets the stream. |
| `core bcada83c` | Stable tags and a relative tolerance | Absent. |

### Until: a privileged helper is designed in the Linux port plan

| Commit | What it does | Notes |
|---|---|---|
| `core cf7accd2` | Tunnel service mutex and owner watchdog | Dormant at tunnelservice/tunnel_service.go:29; never installed. |
| `core 05708fd8` | Authenticates tunnel control | Security, but dormant: admin_service_commander.go:26 is unreachable, the CLI is unbundled and the flag is never sent. |
| `core ba4fc0a0` | Build-id stamp, ProgramData secret, ExecuteCmd via pkexec then sudo | Dormant here; ExecuteCmd at linux_utils.go:46 matters only if elevation ships. |

### Until: an antivirus detection on the installer

| Commit | What it does | Notes |
|---|---|---|
| `b3af7acf` | Installer stops services via SCM | inno_setup.sas:107-112 uses taskkill/net/sc; AV heuristics only. |
| `6bec3859` | Antivirus-clean packaging, IsAdmin RPC, ICU rename | publisher_name already at make_config.yaml:9; rest absent; needs the core and protobuf. |

### Until: 06eaf616 is adopted

| Commit | What it does | Notes |
|---|---|---|
| `core beacdc6a` | DNS group tries TCP first | Absent. |
| `core d87f314b` | All TCP first, keeps the UDP twin | Absent. |

### Until: cde265c5 is adopted

| Commit | What it does | Notes |
|---|---|---|
| `core d6405e7c` | Atomic log level; connectivity tuning | static_data.go:34. |
| `core 2596440d` | One-proxy connectivity | Absent. |

### Until: chain hops are adopted, against no-chains

| Commit | What it does | Notes |
|---|---|---|
| `core eb6774e8` | chain_hop proto field | Absent. |
| `core f80089d9` | Stops joining tags; chain_hop instead | proxy_info.go:101. |

### Until: the middleware serves non-REALITY TLS

| Commit | What it does | Notes |
|---|---|---|
| `core 8538f438` | System TLS or Chrome uTLS for TLS without a fingerprint | chooseTLSEngine skips REALITY; a new feature, tls_engine files absent. |
| `core 6529035d` | Pointer type-switch so TLS tricks reach VLESS, Trojan and VMess | outbound.go:42-47 inert: REALITY returns at :32; patchOutboundFragment is a no-op at :94. |

### Until: a haptics UX pass

| Commit | What it does | Notes |
|---|---|---|
| `71ca5c69` | Moves the connect haptic to the first valid ping and adds a timeout buzz | connection_notifier.dart:41 fires on Connected; the buzz precedes the orb's Connected, cosmetic. |

### Until: the middleware wants to send fragment values

| Commit | What it does | Notes |
|---|---|---|
| `900fc1d4` | Replaces enable-fragment with a size/sleep header | Absent at profile_parser.dart:101,753; adopting it now would drop the current switch. |

### Until: driven UI tests are adopted

| Commit | What it does | Notes |
|---|---|---|
| `216237d6` | Debug flutter_driver | Absent. |

### Until: any process rule, or FindProcess true

| Commit | What it does | Notes |
|---|---|---|
| `c3696322` | Process lookup inside the tunnel for per-app rules | Throws at ExtensionPlatformInterface.swift:246; not needed because FindProcess is false, builder.go:1525. |

### Until: openTun hangs on the first Mac run

| Commit | What it does | Notes |
|---|---|---|
| `47999d54` | Worker-queue provider; 30 s timeout on blocking Swift calls | No timeout at Extension+RunBlocking.swift:18. |

### Until: the tar.exe route of 8aaeb368 fails on the build machine

| Commit | What it does | Notes |
|---|---|---|
| `0b55084f` | Same bug via 7z or pwsh, upstream's final recipe | Alternative to 8aaeb368. |

### Until: signing material is generated inside the repo root

| Commit | What it does | Notes |
|---|---|---|
| `88de65dd` | Ignores root cert.pem, key.pem and sign.pfx | .gitignore:55-62 lacks *.pem and *.pfx; .gitignore:53 says generate outside the repo. |

### Until: the owner wants desktop to reconnect at launch

| Commit | What it does | Notes |
|---|---|---|
| `6abb675b` | Desktop reconnects at launch if the tunnel was left running | Absent: mayConnect only at app_update_checker.dart:211,395. Changes Windows behaviour too. |

### Until: APK size complaints

| Commit | What it does | Notes |
|---|---|---|
| `88b244a8` | Compresses native libs in the APK | Absent in android/app/build.gradle; size trade-off only. |

### Until: the core gains a HotReload RPC

| Commit | What it does | Notes |
|---|---|---|
| `1839ecf6` | Hot-reload RPC, button look, toast-hover workaround | connection_repository.dart:155 restarts; the toast fix is moot on toastification 2.3.0. |

### Until: 0181dfe4 and 422a7b2a have landed

| Commit | What it does | Notes |
|---|---|---|
| `4fe523c9` | Pause via AppLifecycleListener | app.dart:69 is a no-op, :206 still the hook, :102 compensates; would raise closeFront frequency. |

### Until: a complaint about rows jumping under delay sort

| Commit | What it does | Notes |
|---|---|---|
| `ac5ab163` | Pins the tapped proxy row | Absent; default sort is by name. |

### Until: the product wants QR-from-image

| Commit | What it does | Notes |
|---|---|---|
| `1a575d4b` | Reads a QR code from an image in the scanner | A feature, no defect; the scanner survives at auth_page.dart:63. |

### Until: the core adopts an async Start with a stop signal

| Commit | What it does | Notes |
|---|---|---|
| `38576cc4` | Cancel during connect, outcome from the status stream | Absent; connection_button.dart:133 disables the tap. Large; depends on the core queue. |

### Until: support needs copyable errors

| Commit | What it does | Notes |
|---|---|---|
| `cb416e7f` | Connect debounce and a copyable error dialog | Absent custom_alert_dialog.dart; depends on 38576cc4. |

### Until: desktop gRPC is secured (092b5ee7)

| Commit | What it does | Notes |
|---|---|---|
| `2419e105` | Desktop mTLS smoke test | Absent; insecure at core_interface_desktop.dart:114. |

### Until: support reports about dead selected proxies

| Commit | What it does | Notes |
|---|---|---|
| `353f9341` | Connection health sheet | Absent; large. |

### Until: support needs crash logs

| Commit | What it does | Notes |
|---|---|---|
| `d20fbe86` | Post-crash report dialog | Absent; the diagnostics export exists; needs protobuf 5. |

### Until: a mobile trace shows the tunnel left off after a settings change post-relaunch

| Commit | What it does | Notes |
|---|---|---|
| `47a5496b` | Waits for Disconnected between TUN-change toggles | enableTun is locked; only a null snapshot reaches config_option_notifier.dart:22, so after a relaunch a setting change double-toggles. Race unverified; needs a device run. |

### Until: the core adopts upstream's queued Stop

| Commit | What it does | Notes |
|---|---|---|
| `ddb70b2d` | Retries Start while a queued Stop finishes | Our Stop is synchronous, stop.go:25; the bug is absent here. |

### Until: the middleware serves bare JSON arrays

| Commit | What it does | Notes |
|---|---|---|
| `core 8f449fb5` | Parses bare JSON outbound arrays | parser.go:78; the middleware serves objects. |

### Until: extract-lib breaks on an engine move

| Commit | What it does | Notes |
|---|---|---|
| `core 36c44ce0` | Windows build fetches prebuilt libcronet by sparse git | Own extraction at core Makefile:13. |

### Until: the middleware serves bare outbound JSON

| Commit | What it does | Notes |
|---|---|---|
| `core 7db903ff` | Fixes lone-outbound JSON self-wrap; moves legacy WireGuard via ray2sing | parser.go:65 only yields an error at :84; the middleware always sends outbounds. |

### Until: 7c80a18b is adopted

| Commit | What it does | Notes |
|---|---|---|
| `core fbfed27a` | Cancels starts nobody awaits | Partly at start.go:28; the app only calls Start. |

### Until: the product wants core-owned connection state

| Commit | What it does | Notes |
|---|---|---|
| `core cde265c5` | Core-owned WAITING and no-proxy states | Absent at start.go:178; needs proto regeneration. |

### Until: an antivirus detection on rayn-core.dll

| Commit | What it does | Notes |
|---|---|---|
| `core 453ab75f` | Antivirus-clean Windows launchers and VERSIONINFO | CLI unbundled, windows/CMakeLists.txt:93. |

### Until: Go 1.27 is adopted

| Commit | What it does | Notes |
|---|---|---|
| `core 76344593` | tfo-go v2.4.2 for Go 1.27 | go.mod:68; a consequence of the Go move. |

### Until: the product wants a core crash export

| Commit | What it does | Notes |
|---|---|---|
| `core 27ceadbf` | Crash list and sanitized diagnostics zip | Absent; depends on cbe9a1ca and the pin move. |

### Until: the middleware serves large exit lists

| Commit | What it does | Notes |
|---|---|---|
| `core a3b71db9` | Keep-top prunes big profiles | Absent. |

### Until: the product approves a speed test

| Commit | What it does | Notes |
|---|---|---|
| `core 6ca65079` | Speed tests via speed.cloudflare.com | Absent. |

### Until: the product asks for a speed test or big-profile pruning

| Commit | What it does | Notes |
|---|---|---|
| `core 721c61ff` | fix(speedtest): test one proxy at a time, and share the slots between tests | A feature with no Rayn user asking for it. |

### Until: the app sorts exits by ping

| Commit | What it does | Notes |
|---|---|---|
| `core 3b2ff0a2` | sort_delay for cached ordering | Absent; needs proto regeneration. |

## Rejected against a recorded decision

### `#no-chains`

| Commit | What it does | Notes |
|---|---|---|
| `9621e17b` | ChainMode stored-value fallback | No ChainMode on custom-main. |
| `e7cfdeba` | Chain-aware main list for the card | The core drops empty groups (proxy_info.go:151), so items.first is safe here. |
| `3bf21080` | feat(chain): animated extra security and unblocker icons | Part of upstream's chain, WARP or Psiphon work, which is absent here. |
| `598d146c` | Home card with a chain band | The Rayn card replaced it. Judged from the message and a keyword count, not line by line. |
| `6d1dc1df` | Keeps the user's DNS behind extra security | Extra security absent. |
| `a7406bc9` | Chain hop step states | Chains absent. |
| `a14fef07` | Hop slow and failed timers | Chains absent. |
| `5aca7ebb` | Connection steps rail on the card | Chain card redesign. Judged from the message and a keyword count, not line by line. |
| `b62e7f80` | feat(chain): calm the chain type icons' animations | Part of upstream's chain, WARP or Psiphon work, which is absent here. |
| `b0757ca3` | Radar waits for the chain hop | No hop, no radar. |
| `95e44fce` | Removes the chain badge and check sheet | Never in the orb. |
| `4876c3a5` | feat(home): show the chain hop's state beside the ping | Part of upstream's chain, WARP or Psiphon work, which is absent here. |
| `008478dc` | refactor(home): remove the chain pill beside the ping | Part of upstream's chain, WARP or Psiphon work, which is absent here. |
| `6001a1c1` | Chain badge on the connect button | Chains absent. |
| `35cf174c` | One-line chain row | Chains absent. Judged from the message and a keyword count, not line by line. |
| `57afbec0` | feat(quick-settings): extra security and proxy unblocker as two plain rows | Part of upstream's chain, WARP or Psiphon work, which is absent here. |
| `49767779` | Chain badge glyph | Chains absent. |
| `c2522225` | Hop row labels | Chains absent. |
| `dcd5db9c` | Unblocker door icon | Chains absent. |
| `371a9663` | Drops the hop name after its IP | Chains absent. |
| `03d7253b` | Live hop state | Chains absent. |
| `1d97e109` | Hop label from the core | Chains absent. |
| `1727d9c2` | Alternating slow-hop label | Chains absent. |
| `core e5b8ef20` | Adds extra-security and unblocker chain hops and entry-hop display | chain.go and ChainOptions absent on custom-main. |
| `core 1f38ad75` | Lowers the chain WARP hop MTU to 1000 | chain.go absent; reverted by 7ba1573c. |
| `core 7ba1573c` | Reverts the chain WARP hop MTU to 1280 | chain.go absent; cancels 1f38ad75. |
| `core c5a8d44b` | Fits MTU when WireGuard detours via WireGuard | wireguard_chain.go absent; applies only to WG-in-WG and hubs are VLESS. |
| `core df756bdb` | DoH fallback past the extra-security hop | Gated on ChainStatusExtraSecurity, absent on custom-main. |

### `#fork-owns-its-dependency-set`

| Commit | What it does | Notes |
|---|---|---|
| `a6b3f154` | refactor(logging): add the ring buffer and file sink, wired to nothing | Part of upstream's move from loggy to package:logging. This fork stays on loggy. Sampled as a group. |
| `7e931f0c` | refactor(logging): run the new pipeline alongside loggy | Part of upstream's move from loggy to package:logging. This fork stays on loggy. Sampled as a group. |
| `5688066a` | refactor(logging): move engine logs onto the new pipeline | Part of upstream's move from loggy to package:logging. This fork stays on loggy. Sampled as a group. |
| `b04a5f8a` | refactor(logging): move the crash hooks off loggy | Part of upstream's move from loggy to package:logging. This fork stays on loggy. Sampled as a group. |
| `764bb522` | feat(logging): say where an error came from | Part of upstream's move from loggy to package:logging. This fork stays on loggy. Sampled as a group. |
| `db3ede8c` | refactor(logging): switch the three mixins to package:logging | Part of upstream's move from loggy to package:logging. This fork stays on loggy. Sampled as a group. |
| `1c96a498` | refactor(logging): make the category impossible to get wrong | Part of upstream's move from loggy to package:logging. This fork stays on loggy. Sampled as a group. |
| `3334174e` | feat(logging): split engine logs by their type | Part of upstream's move from loggy to package:logging. This fork stays on loggy. Sampled as a group. |
| `262b2799` | refactor(logging): remove loggy | Part of upstream's move from loggy to package:logging. This fork stays on loggy. Sampled as a group. |
| `9ffb6225` | fix(logging): let a phone share its app logs | Part of upstream's move from loggy to package:logging. This fork stays on loggy. Sampled as a group. |
| `9362e2cb` | fix(logging): point the origin at the caller, and say where logs appear | Part of upstream's move from loggy to package:logging. This fork stays on loggy. Sampled as a group. |
| `b6f5cbb7` | feat(logging): keep the log file across runs, and point at the engine's real one | Part of upstream's move from loggy to package:logging. This fork stays on loggy. Sampled as a group. |
| `e8409959` | feat(logging): give every level one name | Part of upstream's move from loggy to package:logging. This fork stays on loggy. Sampled as a group. |
| `619be585` | feat(logging): drop debug mode, keep only the log level | Part of upstream's move from loggy to package:logging. This fork stays on loggy. Sampled as a group. |
| `f37f06cc` | feat(logging): three log categories instead of five | Part of upstream's move from loggy to package:logging. This fork stays on loggy. Sampled as a group. |
| `5acc1f35` | feat(logging): keep only errors in the app log file | Part of upstream's move from loggy to package:logging. This fork stays on loggy. Sampled as a group. |
| `0ba36439` | Declares archive for zip import | Zip import absent. |
| `core 9ee754fa` | Adds tor, openvpn and openconnect tags | core Makefile:33. |
| `core 65a7696d` | Groups build tags, CI reads the Makefile | core Makefile:33. |

### `#no-lan-sharing`

| Commit | What it does | Notes |
|---|---|---|
| `8166d1ce` | feat(settings): allow hiding the LAN sharing leading icon | LAN sharing and its proxy dialog are not a product feature. |
| `d8b4cecf` | feat(settings): give VPN sharing a permanent generated password | LAN sharing and its proxy dialog are not a product feature. |
| `c6b18091` | LAN proxy QR dialog | No such dialog in dialog_notifier.dart. |
| `3d66551a` | feat(qr): confirm a copy in place instead of with a toast | LAN sharing and its proxy dialog are not a product feature. |
| `850c8ef0` | fix(qr): center the password eye and even out tile padding | LAN sharing and its proxy dialog are not a product feature. |
| `59d7f32b` | LAN QR dialog fallback | LAN sharing dialog absent. |
| `300dc6cd` | Drops LAN QR parameters | LAN sharing dialog absent. |
| `4d97438b` | Transparent ports off by default, passwordless proxy, LAN port | Fixed value at config_option_repository.dart:217. |
| `00d27ddb` | Local and LAN proxy dialog | Dialog absent. |
| `a167e7c8` | feat(proxy): the Other devices tab works like This device | LAN sharing and its proxy dialog are not a product feature. |
| `baf9f666` | feat(proxy): say a side of the proxy dialog is off, with Turn on | LAN sharing and its proxy dialog are not a product feature. |
| `307f728b` | fix(proxy): in VPN mode show only Other devices, never This device off | LAN sharing and its proxy dialog are not a product feature. |
| `86ef669f` | feat(proxy): turn LAN sharing on when Other devices is shown | LAN sharing and its proxy dialog are not a product feature. |
| `42bbb028` | feat(proxy): turn LAN sharing on and off in the Other devices tab | LAN sharing and its proxy dialog are not a product feature. |
| `40c2b3eb` | feat(settings): Connection sharing row in quick settings | LAN sharing and its proxy dialog are not a product feature. |
| `0f5b12bb` | feat(proxy): no Turn off in the dialog, no QR button while sharing is off | LAN sharing and its proxy dialog are not a product feature. |
| `8d1db6a2` | feat(settings): a tap on the sharing row opens the proxy dialog | LAN sharing and its proxy dialog are not a product feature. |

### `#warp-removed`

| Commit | What it does | Notes |
|---|---|---|
| `6cc53c2f` | Merges warp and psiphon headers into extra-security | profile_parser.dart:86 allow-list has no such key. |
| `2ce6cf8e` | Maps warp to warp_auto | No ChainMode on custom-main. |
| `948ee26e` | feat(settings): choose the WARP noise mode from named presets | Part of upstream's chain, WARP or Psiphon work, which is absent here. |
| `da7cd788` | WARP scanner endpoint UI | WARP absent. |
| `1bb54598` | WARP tunnel choice and consent | WARP absent. |
| `3d25a4c3` | Per-hop WARP settings | WARP absent. |
| `43a96d5a` | Extra Security WARP limits | WARP absent. |
| `core 979d6b92` | Deletes WARP generation; Psiphon chain handling; balancer default | builder.go:209 WARP block remains; removal is cleanup, no defect fixed. |
| `core 6bea4708` | Adds with_masque | core Makefile:33. |
| `core 0e4c02c6` | chore: bump ray2sing to 2593a5a (AmneziaWG noise and reserved) | Part of upstream's chain, WARP, Psiphon or xray work, which is absent here. |
| `core 7cf90204` | chore: bump hiddify-sing-box to 27b05bdf3 (AmneziaWG reserved, WireGuard MTU discovery) | Part of upstream's chain, WARP, Psiphon or xray work, which is absent here. |
| `core 26c26284` | chore: bump ray2sing to 9be47b6 (no port rotation for a chained WARP) | Part of upstream's chain, WARP, Psiphon or xray work, which is absent here. |
| `core d21c9327` | WARP behind a detour: IPv6 fallback, scanner off | warpBehindDetour touches only WARP and MASQUE. |
| `core 8a9611a1` | build(deps): bump hiddify-sing-box and ray2sing for noise presets | Part of upstream's chain, WARP, Psiphon or xray work, which is absent here. |
| `core fc3b69e4` | feat(warp): turn on chain WARP noise when its mode names a preset | Part of upstream's chain, WARP, Psiphon or xray work, which is absent here. |
| `core 5a137944` | feat(chain): give each WARP hop the settings the endpoint offers | Part of upstream's chain, WARP, Psiphon or xray work, which is absent here. |

### `#no-xray`

| Commit | What it does | Notes |
|---|---|---|
| `core ff1ae3c1` | Adds parse --xray via libxray | parseToXray absent; CLI only. |
| `core 4434c0fa` | Parser reorder: sing-box, then Clash, then Xray JSON | xray_json.go absent; also needs ray2sing. |
| `core 59d7f1cf` | parse --xray keeps xhttp extra and VMess REALITY | convertShareLinksToXray absent. |
| `core c160e54d` | xray-core as a direct dependency | go.mod only. |
| `core 5f5c40ce` | parse --xray unescapes &amp; in share links | parseToXray absent; the ray2sing half is gone too. |
| `core 6bf6d454` | fix(config): keep the TLS cipherSuites of an Xray JSON config | Part of upstream's chain, WARP, Psiphon or xray work, which is absent here. |
| `core d26ba6ce` | chore: bump hiddify-sing-box to 7d1760f3b (XHTTP server leak) | Part of upstream's chain, WARP, Psiphon or xray work, which is absent here. |
| `core 297ed96f` | feat(config): keep XDRIVE and dialMode in links of Xray JSON outbounds | Part of upstream's chain, WARP, Psiphon or xray work, which is absent here. |
| `core fd05708c` | parse --xray adapts to libxray v1.261031.0 | parseToXray absent. |

### `#mas-app-extension-only`

| Commit | What it does | Notes |
|---|---|---|
| `7a2bef0f` | Reports system-extension approval as a permission failure | App extensions need no such approval. |
| `4d72b56a` | Developer ID signing in CI | Developer ID only. |
| `6042a96e` | Notarization script | Developer ID only. |
| `7806fd96` | Clearer Developer ID signing errors | Developer ID only. |
| `55809348` | Moves the Go tunnel into the core; root service controller | Own bind at core Makefile:284. |
| `072e93d0` | Companion dmg beside the App Store pkg | Direct-download artifact. |
| `e09b3d5b` | Hides Reset VPN in the root-service build | There is no root build. |

### `#never-adopt-prebuilt-core-url`

| Commit | What it does | Notes |
|---|---|---|
| `a22e2aa8` | Re-enables CI jobs that use prebuilt cores | build.yml:79. |
| `8f84cdc4` | Restores the same build matrix | build.yml:79. |
| `5d75faad` | macos-libs downloads a prebuilt tunnel framework | Blocked at Makefile:700. |
| `33626b95` | Upstream core.version bump | Upstream core artifact. |
| `fcfe884b` | Upstream core.version bump | Upstream core artifact. |
| `039488f6` | Release 5.5.1 with a core bump | Upstream core artifact. |

### `#no-ip-lookups`

| Commit | What it does | Notes |
|---|---|---|
| `57453b04` | Custom ipinfo-url | getCurrentIpInfo has no callers; the core makes no lookups. |
| `e2bed98f` | IpInfo.from_cache proto | No IP info here. |
| `ecd9b0e4` | Ignores a cached IP from the last run | No from_cache in custom-main protos. |
| `9ff17221` | Flag loads until this run's IP arrives | The exit comes from tags, node_name.dart:93. |
| `core 1204304b` | Subscription-supplied geolocation endpoint | Would dial a lookup host. |
| `core ad42ec92` | Marks IP info as cached | Absent. |

### `#selector-defaults-to-fastest`

| Commit | What it does | Notes |
|---|---|---|
| `c56401c0` | Select-group default setting | Fastest is the default by design. |
| `core b9aa7bdf` | Names the proxy only for a lowest-delay balancer | Absent. |
| `core 5e48d0cd` | A spreading balancer shows its fastest | Absent. |
| `core f5153860` | Same, main list | Absent. |
| `core 9c8f241b` | Tolerance only on lowest-delay | Absent. |

### `#config-encrypted-at-rest`

| Commit | What it does | Notes |
|---|---|---|
| `225378d3` | CoreInterfaceDesktopTun: proxy in app, TUN in root service | Depends on the root service, which writes plaintext config to a temp file. See linux-port-plan. |
| `8e854547` | Admin background service support, bindings, installers | As 225378d3. |
| `core b4908265` | Root service: pkexec install, full core, plaintext config in a temp file | About 2,750 lines; the pattern informs the Linux port plan only. |

### `#no-v2ray-parser`

| Commit | What it does | Notes |
|---|---|---|
| `core 895ef442` | Stops WireGuard .conf parsing as YAML, via parseShareLinks | No share-link path here; parser.go:91 falls through to a format error. |
| `core 0cc1b1b1` | Fetches subscriptions listed inside a profile | Hooks parseShareLinks, absent; subscription_links.go absent. |
| `core 143b23c3` | Numbers duplicate tags; imports AmneziaWG fields | Needs ray2sing; the Clash half is barred. Middleware tag uniqueness could not be checked here. |

### `#rayn-only-deep-links`

| Commit | What it does | Notes |
|---|---|---|
| `8a75354c` | hiddify:// fragment name | Only rayn://import/<token> is accepted. |

### `#profile-override-is-the-backend-channel`

| Commit | What it does | Notes |
|---|---|---|
| `1bc6e610` | Guards dropping profile_override | The fork keeps the column, db.dart:64. |

### `#self-update-windows-exe-only`

| Commit | What it does | Notes |
|---|---|---|
| `10f33b7b` | Updater that installs outside a store | Absent. |

### `#no-fakeip`

| Commit | What it does | Notes |
|---|---|---|
| `core 864c25d8` | FakeIP rule avoids a legacy-DNS abort | Absent. |

## Rejected: deleted or absent here

### Read in full

| Commit | What it does | Why |
|---|---|---|
| `a75f0c38` | Profile-tile update status indicator | No UpdateProfileNotifier on custom-main; tiles deleted. |
| `5c7ad52a` | Aggregate toast for bulk subscription updates | One profile only; no bulk toast in profiles_update_notifier.dart. |
| `0c0b0564` | Sort dialog, persisted sort, swapped-label fix | Sort UI gone; profile_sort_enum.dart:8 present has no callers. |
| `339f448b` | Pinned profiles with schema v7 | Pin UI gone; schema numbering is ours (drift-schema-numbering). |
| `b49a47b9` | Swaps aider ignores for slang ignores | Tooling only. |
| `21dd0730` | Parses provider URLs without the userinfo header | profile_parser.dart:774; no UI reads webPageUrl or supportUrl. |
| `9cc5c60e` | Provider link chip constants | Chip absent; constants only. |
| `d438d6cd` | RFC 5987 filenames and blank-name handling | The name only labels account_section.dart:102; no failure a Rayn user reaches. |
| `9df39160` | Foundation import for the driver | No driver call in lib/main.dart. |
| `2a3c5ec6` | Driver behind a flag to free the keyboard | No driver call in lib/main.dart. |
| `4bf600c3` | Logs refactor, crash file path | Logs UI gone; log_path_resolver.dart has only coreFile and appFile. |
| `188ab034` | Logs rebuild; level choices to error | Logs UI gone; picker is debug-only (settings_page.dart:118). |
| `6f775ade` | Failure logged at error | Premise is upstream's errors-only file. |
| `502f1ee5` | More file import formats, tolerant decode | No file import; text_utils.dart has no decoder. |
| `c6b69fdf` | Lint and whitespace | No behaviour change. |
| `31ab9d1c` | Deletes upstream's NETWORK_EXTENSION.md | Never here. |
| `85936b33` | IDE settings; drops network_info_plus from Podfile.lock | No Mac behaviour. |
| `e8f8c9f0` | IPv6-aware CIDR validation | validators.dart:81 isIpCidr has no callers. |
| `89bedc6c` | Name labels for more link schemes | profile_parser.dart:819 parses links; the middleware serves JSON. |
| `88d2449d` | Iran free-config data | Test data file only. |
| `c9b30739` | Per-app proxy rename | Per-app routing deleted; renames only. |
| `0441ce39` | Route-rule package picker route | Route-rule editor deleted. |
| `807d272a` | App-based routing switch and migration | Per-app routing deleted. |
| `938f9d2f` | Removes the auto-selection interval pref | Per-app routing deleted. |
| `374554d2` | Auto-selection off-by-user pref | Per-app routing deleted. |
| `d8103ed5` | Removes the route options pref | Routing panel deleted. |
| `e513ff18` | Keeps an edited local name | addLocal has no callers. |
| `57565798` | Comment on auto selection | Per-app routing deleted. |
| `98387fe9` | Upstream 5.0.0 version bump | Upstream release bookkeeping. |
| `c60782d0` | Zip-to-text reader | No file import in text_utils.dart. |
| `9270eaac` | One profile per zip file | Add-profile and multi-profile deleted. |
| `b78aa6c8` | Hot-reload button look | No hot reload; the orb replaced this button. |
| `70a39d32` | Re-reads the options snapshot after a hot reload | No hot reload; core restart.go:28 stops then starts, rebuilding config_option_notifier.dart:14. |
| `e1f0706a` | Zip imported as a single profile | File import absent. |
| `7d400171` | Proxy type overflow | That row is absent here. |
| `26921bfd` | Keeps the port in a shared subscription link | link_parsers.dart has no share-link builder. |
| `13ae2c75` | In-memory inner-link expander rewrite | profile_parser.dart:598 is already in memory; middleware JSON has no line starting with http. |
| `59adf831` | Stops trimming non-link lines | profile_parser.dart:622; harmless for JSON from the middleware. |
| `f9d5ceb4` | Finds links in base64 subscriptions | The middleware serves JSON. |
| `cdd2f981` | Trims CR from links | profile_parser.dart:628; no link lines from the middleware. |
| `a92bd853` | Keeps HTTP proxy lines and logs drops | No link lines from the middleware. |
| `bca19698` | Cancel aborts expansion | No link lines from the middleware. |
| `a55e1a18` | Persists the log level filter | Logs UI gone. |
| `f9e35503` | Persists the log category filter | Logs UI gone. |
| `fe5fd0b8` | Balancer strategy description | Routing panel deleted. |
| `a98e36fc` | Spinner as a single fading child | Absent; the ring is keyed at connection_button.dart:302. See 9fa1e611. |
| `7b1e3ddb` | Driver in profile builds | No driver call in lib/main.dart. |
| `e7b45c9a` | iOS always-on toggle | The fork is always on-demand, VPNManager.swift. |
| `d7426e49` | Eclipse art and Android stop/start settling | Absent; the fork's stop() waits for the port at :381. |
| `30127f1d` | iOS validation additions; Makefile comment | The Mac part is a comment. |
| `93b5d4aa` | Release message and VirusTotal scripts | Upstream's pipeline. |
| `193154f7` | Links ole32.lib in the runner | No failure here: windows/runner/main.cpp:88 CoInitializeEx already ships without it. No build was run. |
| `9d0e7fd6` | DMG background image | macos/packaging removed in c136f449. |
| `1cd04692` | DMG background image | macos/packaging removed in c136f449. |
| `e505771e` | IP parsers become factories | Dead code here. |
| `05a52daf` | Analyzer infos in upstream-only files | Files absent. |
| `7911292e` | Cancels a status subscription | The field does not exist here. |
| `aecfe6c7` | Smaller taskbar status dot | Absent flutter_window.cpp status badge. |
| `a951b2d2` | Analyzer cleanup | GrpcClientIdentity does not exist here. |
| `74ef9ad1` | Null preference write | Only non-null writes here, window_notifier.dart:42. |
| `d627cf63` | Proxy rows show the detour chain | The pinned core still joins detour names (proxy_info.go:101). |
| `ea4ee556` | Notification rewrite | The fork's ServiceNotification.kt already retries and resolves tags. |
| `105d623f` | System TLS setting | Absent in the core. |
| `fec46f05` | Release 5.2.0 | Upstream release bookkeeping. |
| `4d258d5d` | Release 5.2.1 | Upstream release bookkeeping. |
| `29526c06` | Hiddify Store display name | Rayn has its own make_config.yaml:1. |
| `5919a4f7` | Release 5.3.0 | Upstream release bookkeeping. |
| `7d2bcf7a` | Home repaint isolation | RepaintBoundary is already on the orb. |
| `27bc0416` | IPv6 preference | Absent here. |
| `fb65cad3` | Switch-to-lowest card action | Action absent; the default is already Fastest (selector-defaults-to-fastest). |
| `0616449b` | Card switch-button label | Button absent. |
| `a5dc99ee` | Removes the ping-side switch button | Button absent. |
| `40a23c54` | Removes the card switch button | Button absent. |
| `f9f7caa1` | Hides switch for picked groups | Action absent. |
| `d8c55b58` | Proxy row state from core status | Upstream row redesign, not a defect. |
| `0215b921` | Ping number or signal preference | Upstream row redesign. |
| `1229b0a2` | Animated proxy rows, logo signal | Decorative redesign, not adopted. Judged from the message and a keyword count, not line by line. |
| `416ad778` | Signal-style menu switch | Upstream row redesign. |
| `017d2241` | Release 5.4.0 | Upstream release bookkeeping. |
| `c2c5b8de` | Animation leak and a vendored flutter_animate | Absent here. |
| `2b73a15c` | Cosmetic app hunk; the fix is in the core | See the core row 6ba0d6df. |
| `9ae75494` | IPv6 modes and Sing15 | hiddify_option.go:109 removed. |
| `d472e80a` | Short-screen scaling | home_canvas_layout.dart:76-79 already fits. |
| `6f3d3891` | TV picker arrow keys | No RadioGroup, no TV. |
| `b20e50db` | Keep-top and speed test | No keep-top in profile_parser.dart:86. |
| `9a97f7e9` | Stops auto-update after 3 failing days | Retrying is how a blocked user recovers. |
| `809b215f` | Upload test gauge icon | Speed test absent. |
| `f9ddf413` | Keep-tags and a two-way speed test | Feature absent. |
| `229cb276` | Persisted speeds, picker changes | Feature absent. |
| `1b846c92` | One bad profile no longer fails the list | One row only, and headers are always written. |
| `a3472bce` | Release 5.5.0 | Upstream release bookkeeping. |
| `48c045d7` | Proxy failure reason dialog | The dialog is absent. |
| `5a277122` | Share dialog; fixes a percent-encoded share path | uri_utils.dart:35 tryShareFile has no callers. |
| `690889b7` | Release 5.5.5 | Upstream release bookkeeping. |
| `ea08fb5b` | Test config rename | Test data file only. |
| `core d7884443` | Build-time Psiphon config embedding and secrets | cmd/internal/encryptconfig and chain.go absent; the Makefile hunks are Psiphon-only. |
| `core d8746e38` | App route-rule list replacing block-ads, bypass-lan and region rules | route_rules.go and RouteRule absent; a new feature. |
| `core 8e373b48` | Waits on the chain hop's ping | Path absent. |
| `core ff0d6931` | Reverts the hop wait | Path absent. |
| `core 1f52288a` | OpenWrt packages, feed and installer | release/openwrt absent; a router target is not shipped. |
| `core 145d32a0` | User-chosen keep-tags for keep-top | KeepTop and keep_top.go absent on custom-main. |
| `core 12071e31` | Keeps speed-test results; ClearSpeedTests RPC | speedtest.go and clearSpeedTests absent. |
| `core 5737bb5f` | Removes OpenWrt feed releases | OpenWrt CI and installer text only. |
| `core 2abb1845` | Release bump; build-tag reshuffle | Rayn macOS builds via gomobile (Makefile:286); TUNNEL_TAGS absent. |
| `core 2aa1fe9e` | System proxy on the IPv4 listener only | Path absent; the app sends false. |
| `core 1f3f702e` | Region into DNS-tunnel smart_pool discovery | Only dnstt, masterdns and soar options; DNS tunnels absent. |
| `core b15784dd` | Well-known SIDs for the secret's ACL | That path does not exist here. |
| `core 25b22434` | adminbg allowlist for new RPCs | That path does not exist here. |

### Translations (87)

Translation files only. Translations are a derived artefact here and are never cherry-picked.

| Commit | Upstream's subject |
|---|---|
| `024c0888` | chore(i18n): localize new profile update and sort strings |
| `b3856957` | chore(i18n): drop translation keys orphaned by profile changes |
| `1503bbde` | feat(profile): add pin/unpin labels (en) |
| `f29d6129` | chore(i18n): localize pin/unpin |
| `1dffbd29` | feat(i18n): add provider link and unverified-link warning strings |
| `39539c63` | feat(settings): rename VPN sharing to Secure VPN sharing |
| `649a74b9` | chore(l10n): drop the removed VPN sharing password keys |
| `dfea6ace` | chore(i18n): align English strings with Material Design 3 |
| `c4b0f248` | fix(l10n): apply the translation principles to all ten locales |
| `f73458d7` | chore(i18n): tighten English against UI-writing and warning guidance |
| `5f2b8e61` | chore(i18n): keep "connection profile" in the empty-profile message |
| `e6192f5c` | chore(l10n): sync the ten locales with the reworked English |
| `da1603a4` | docs(i18n): write the full Material Design 3 rules into CLAUDE.md |
| `3662764c` | chore(i18n): bring English fully in line with Material Design 3 |
| `8ca9fdf8` | chore(i18n): drop "we" from the unverified-link warning |
| `90586c69` | chore(l10n): apply the Material Design 3 rules to the ten locales |
| `25654662` | docs(i18n): replace copied writing rules with captured sources and links |
| `94784db3` | docs(i18n): move the writing rules out of docs/ into .claude/ |
| `48d61e9a` | fix(readme): render the Google Play badge in local previews |
| `92363b6b` | fix(i18n): apply the writing rules to the English strings |
| `7321b83a` | chore(l10n): carry the English wording fixes into the ten locales |
| `bfff303a` | fix(i18n): drop the tap gesture from the empty routing rules state |
| `5e4e0045` | chore(l10n): carry the routing empty state into the ten locales |
| `ffbcac6e` | feat(logs): word the new logs page |
| `62648809` | feat(logs): translate the new logs page |
| `72b49223` | feat(logs): name the app log file for what it now holds |
| `abcd338f` | feat(logs): translate the renamed app log entry |
| `90b262ad` | docs(claude): note hot reload and build_runner watch |
| `b0ffbebe` | refactor(i18n): move the routing text keys to match the UI |
| `1a6f4b46` | chore(l10n): move the routing text keys in the ten locales |
| `0ca66373` | feat(i18n): English texts for app-based routing and built-in rules |
| `ad71a6c9` | chore(l10n): carry app-based routing and built-in rule texts into the ten locales |
| `34d2e9c2` | feat(i18n): shorter titles for two built-in rules |
| `f9904e0c` | chore(l10n): carry the shorter built-in rule titles into the ten locales |
| `008810fd` | feat(i18n): English texts for the new QR dialog |
| `643bb4dc` | chore(l10n): carry the QR dialog texts into the ten locales |
| `090012fc` | feat(i18n): a "Copied" text for the QR dialog |
| `b0e3c876` | chore(l10n): carry the QR dialog "Copied" text into the ten locales |
| `9cab7354` | feat(i18n): texts for a failed connect on the connect button |
| `d7f4c285` | chore(l10n): carry the failed-connect texts into the ten locales |
| `22f507de` | feat(i18n): texts for the dialog when another VPN holds the TUN |
| `326f0d3c` | fix(i18n): shorten the administrator warning for VPN mode |
| `87e5c7f6` | chore(l10n): carry the VPN dialog texts into the ten locales |
| `16734847` | fix(i18n): call the hot reload state "Applying changes?" |
| `26a93700` | chore(l10n): carry the applying-changes text into the ten locales |
| `faa17bfd` | feat(i18n): add the text for a failed proxy switch |
| `4f08c933` | chore(l10n): carry the failed proxy switch text into the ten locales |
| `c8dd01bc` | feat(i18n): add the text describing each balancer strategy |
| `021f6787` | chore(l10n): carry the balancer strategy texts into the ten locales |
| `f6bc6697` | feat(i18n): rename the scan button to QR code and add the no-QR-in-image text |
| `c18a1b5b` | chore(l10n): carry the QR code texts into the ten locales |
| `96c2dcb9` | chore(claude): remove CLAUDE.md and the writing rules |
| `5614f93d` | feat(i18n): texts for LAN sharing on 127.0.0.1 |
| `c33a0ed1` | chore(l10n): carry the LAN sharing 127.0.0.1 texts into the ten locales |
| `442227fb` | docs(windows): record VirusTotal results of the final rebuild |
| `a121d00c` | feat(i18n): add English texts for the proxy card's connection steps |
| `9aeb2260` | feat(i18n): translate the proxy card's connection step texts |
| `fc0d7807` | feat(i18n): translate the admin, always-on VPN and system TLS texts |
| `b03a46c7` | fix(i18n): follow the writing rules in the admin and system TLS texts |
| `e343df04` | fix(i18n): match the reworded admin and system TLS texts |
| `1b8aad2c` | fix(i18n): drop the connection check texts and fix two apostrophes |
| `86789fc3` | feat(i18n): translate the button's connection texts and WARP noise modes |
| `fa480d2e` | fix(i18n): say "Switch to fastest" on both switch buttons |
| `93f1c366` | fix(i18n): match "Switch to fastest" in the other locales |
| `e44127d0` | feat(i18n): add the English text for an unavailable proxy |
| `c78f01da` | feat(i18n): translate the text for an unavailable proxy |
| `860e6743` | feat(i18n): bring back the English texts of the connection check |
| `34a1b136` | feat(i18n): translate the connection check texts |
| `ec74e701` | feat(i18n): add the proxy info dialog's status texts |
| `f41ebf06` | feat(i18n): translate the proxy info dialog's status texts |
| `86b7d205` | feat(i18n): add the proxy row's status and signal style texts |
| `ba514cd8` | feat(i18n): translate the proxy row's status and signal style texts |
| `1115ce58` | i18n(ru): polish the Russian locale |
| `97c86560` | feat(proxy): texts for the This device tab of the proxy dialog |
| `76a83c8b` | feat(proxy): translate the This device tab texts |
| `e9ab565e` | feat(proxy): texts for the Other devices tab of the proxy dialog |
| `fdd000f5` | feat(proxy): translate the Other devices tab texts |
| `8e6bf88b` | feat(proxy): texts for a proxy dialog side that is off |
| `abdd0b77` | feat(proxy): translate the texts for a side that is off |
| `d9be1ef4` | refactor(proxy): drop the texts of the sharing-off card |
| `dcc25272` | refactor(proxy): drop the translated texts of the sharing-off card |
| `63824032` | feat(proxy): texts to turn LAN sharing on and off in the proxy dialog |
| `16f5cd1f` | feat(proxy): translate the texts to turn LAN sharing on and off |
| `8d752cd9` | feat(settings): text for the Connection sharing row of quick settings |
| `66590448` | feat(settings): translate the Connection sharing row's text |
| `8daba122` | refactor(proxy): drop the Turn off text |
| `48918dcc` | refactor(proxy): drop the translated Turn off text |

### Routing and per-app (50)

Per-app proxy, app-based routing and the route-rule editor were deleted by this fork.

| Commit | Upstream's subject |
|---|---|
| `b898135a` | fix(a11y): name the routing rules FAB and its menu for screen readers |
| `47f85090` | refactor(i18n): fix the notAvailabeInThisPlatform key spelling |
| `37a0c71d` | test: cover region picker labels across locales |
| `b3ac2004` | feat(rules): give each new rule a numbered name |
| `dfe7bd66` | feat(rules): built-in rules instead of predefined ones |
| `8253f423` | fix(routing): tapping an auto-picked app goes auto, removed, yours |
| `aed22756` | fix(routing): an empty auto selection list means no list |
| `f151a416` | feat(region): give the region's name without its code |
| `50278046` | feat(routing): keep auto selection's loading and result in state |
| `8193d817` | feat(routing): turn App-based routing on and off, and change its mode |
| `0b27c7c3` | feat(routing): a region change turns auto selection off |
| `a6f83b61` | perf(routing): fetch each app logo once per run |
| `0252882c` | feat(routing): share the lists the share sheet shows |
| `81f8f525` | chore(routing): name the exported file after App-based routing |
| `717b44b9` | feat(routing): search the app list by package name too |
| `495b08ae` | feat(routing): tag auto picks in the app list |
| `1b0b245f` | feat(routing): the app list follows the mode chosen on the routing page |
| `b1416b47` | refactor(routing): auto selection leaves the app list page |
| `2d4312ba` | feat(routing): chips to hide system apps and restore auto picks |
| `b6bda018` | feat(routing): share the list's changes from a bar, after a preview |
| `0e0fd8d2` | feat(routing): a plain button adds a rule |
| `264de0e0` | feat(routing): the region as a chip in the app bar |
| `96368e2e` | feat(routing): the rules list fills the page |
| `19e6f9e8` | feat(routing): the general options head the rules list |
| `4b2936dc` | feat(routing): App-based routing section above the rules |
| `b0ccb9bd` | feat(routing): show App-based routing's apps as logos |
| `53ab9550` | feat(routing): auto selection row under App-based routing |
| `6c005c93` | fix(routing): skip an auto selection list that loaded too late |
| `8f53cbb2` | fix(routing): a mode whose list fails leaves auto selection off |
| `4072096b` | refactor(routing): drop the last-update clear that never ran |
| `9d05a6a3` | fix(routing): the app list survives being rebuilt |
| `41d6e55b` | refactor(routing): auto selection fetches only what it's asked for |
| `374a20a8` | refactor(routing): fewer hops in App-based routing |
| `901ae0b3` | fix(routing): auto selection's loading bar waits for every run |
| `21ca31d4` | fix(routing): importing app lists replaces them |
| `d96e9a40` | fix(rules): Proxy only with no apps keeps every app in the VPN |
| `a51c9935` | refactor(rules): save the rules without sorting them again |
| `ac1e608b` | refactor(rules): one set tracks the built-in rules still missing |
| `f75dc8ee` | fix(rules): a new install gets the default rule order |
| `37cb3ac6` | fix(routing): the region chip resets DNS even if the page closes |
| `3fcf1ea3` | fix(routing): count the days since an update across clock changes |
| `3c361ed7` | fix(routing): sharp app logos at any screen density |
| `6a0f345e` | refactor(routing): build the rules menu when it opens |
| `5939559a` | fix(rules): rule chips keep their tint with dynamic colors |
| `4f789ded` | fix(routing): the region chip leaves the direct DNS server alone |
| `40ea655f` | feat(rules): keep a rule's name on one line |
| `19a9630a` | feat(rules): a lock marks built-in rules after their name |
| `9f5ea359` | feat(routing): Apple services built-in rule, read-only built-in rules, duplicate and copy |
| `e0e59faa` | feat(routing): the system services rule follows the platform |
| `b449e45e` | fix(routing): the system services rule is off by default |

### CI and tooling (31)

Upstream's CI, tooling or tests for code absent here. No surviving code changes.

| Commit | Upstream's subject |
|---|---|
| `8177bbcf` | fix: update Android SDK setup to install platform-tools |
| `bd2d1dd2` | chore: update GitHub Actions workflows and submodule reference |
| `479b245a` | test |
| `f62bdf5b` | test |
| `41a3de3f` | fix |
| `630bba10` | style(connection): end two files with a newline |
| `410c0bd6` | test(profile): cover name preservation across protocols |
| `e7f06a80` | test(profile): verify renamed profiles persist across edits |
| `74454905` | feat: add Profile.xcconfig and update project settings for new configuration |
| `320c11c8` | test(profile): cover the shared subscription link |
| `2f70a69e` | test(profile): cover the temp file cleanup |
| `3a72d4eb` | test(rules): cover the built-in rules |
| `b3bf66ec` | test(proxy): cover a failed proxy switch |
| `d1ecbfe3` | test(proxy): cover the pinned proxy row |
| `a694f0b1` | Remove stale bot; issue triage is now handled manually |
| `d937aa7b` | chore: update release message and CI scripts for asset handling |
| `34aa0c57` | chore: update CI workflow for asset naming and target handling |
| `a39c7181` | test(profile): update warp mode expectation to "warp_auto" for compatibility |
| `c174e46e` | delete(test): remove fallback tests for DioHttpClient |
| `b346c287` | fix(build): enable android-aab target in build workflow |
| `4682b3f2` | fix(release): grant the release workflow the same token permissions as CI |
| `b11a91f7` | docs: add agent guide for pull requests in hiddify-app |
| `5be946b5` | fix(workflow): update MSSTORE_PRODUCT_ID reference to use secrets |
| `3bd0479d` | ci(virustotal): skip the IPA and show the counts as static badges |
| `c156fc62` | style(proxy): space the This device buttons like the Other devices tab |
| `b388dca5` | style(proxy): Turn off in the look of Turn on sharing |
| `core e71636e7` | update: improve libcronet extraction process |
| `core 84b47e91` | feat(cmd): grpcweb, a browser tester for the core |
| `core a00a694c` | fix(build): improve debsigs patching process in CI workflow |
| `core 22735d8f` | chore: comment out pull_request paths-ignore section in CI workflow |
| `core ae0c0b70` | docs: add rules for AI agents and contributors |

### Engine pointer bumps (25)

Moves upstream's engine pointer only. Our pin is decided as a whole, never by replaying upstream's bumps (campaign plan, step 6).

| Commit | Upstream's subject |
|---|---|
| `core 5296bd6f` | chore: update subproject commits for hiddify-sing-box and ray2sing |
| `core 40039dba` | chore: update subproject commit for hiddify-sing-box |
| `core c5687ee6` | fix: update subproject commit for hiddify-sing-box |
| `core 9db67398` | update: update subproject commits for hiddify-sing-box and ray2sing |
| `core 7a6aed4e` | update: update subproject commit for hiddify-sing-box |
| `core 399f1eba` | update(submodule): update hiddify-sing-box to latest commit |
| `core a1104ab7` | chore(submodule): update hiddify-sing-box submodule to latest commit |
| `core 45ae90d7` | chore: bump hiddify-sing-box and ray2sing |
| `core e89fabc4` | chore: update ray2sing subproject commit hash |
| `core f976bf98` | chore: bump hiddify-sing-box and ray2sing |
| `core 9bc28c9b` | chore: bump hiddify-sing-box to 1a80d857c (no IP of the previous run) |
| `core 33ac0d23` | chore: bump hiddify-sing-box to fda14fcdb (monitoring fixes) |
| `core ab6b3888` | chore: bump ray2sing to 1e3825c (TLS cipherSuites from links) |
| `core 0a6733a4` | chore: bump ray2sing to 414913b (skip unknown cipher suites) |
| `core b23fd805` | build(deps): bump hiddify-sing-box to 347f887c4 (selected proxy's ping at once, stuck tests given up on) |
| `core ef75d701` | chore(deps): hiddify-sing-box with IPv6 by outbound |
| `core 79e08dec` | build(deps): bump hiddify-sing-box to 1ff4d3808 |
| `core f17a10c9` | build(deps): bump hiddify-sing-box to e33a72aed |
| `core 9a09660b` | build(deps): bump hiddify-sing-box to the pool tuned past MasterDnsVPN's balancer |
| `core 4e467c13` | build(deps): bump hiddify-sing-box, the quick check's uploads bounded |
| `core b5f50638` | build(deps): bump hiddify-sing-box, benchmark query sizes and parallel runs |
| `core a06d94a2` | build(deps): bump hiddify-sing-box to f1b2bd401 |
| `core baf1e282` | build(deps): bump ray2sing to 600622d |
| `core 3281bb63` | chore: hiddify-sing-box with one ping per proxy and a steady lowest-delay pick |
| `core 4c8b1eff` | chore: hiddify-sing-box with cached pings that only order, and the lowest-delay stay |

### Release and packaging (23)

Upstream release, OpenWrt or Docker packaging.

| Commit | Upstream's subject |
|---|---|
| `core 7854a77e` | release: version 5.0.0 |
| `core f54dbabd` | Update WRT package HASH. |
| `core dbf3ffbf` | Update WRT package HASH. |
| `core 7ca37285` | release: version 5.0.1 |
| `core cd5f5b7a` | Update WRT package HASH. |
| `core 5da46bf6` | release: version 5.0.2 |
| `core 6e76f575` | Update WRT package HASH. |
| `core 00a84b00` | release: version 5.0.3 |
| `core 39d1f4e2` | Update WRT package HASH. |
| `core c08b678f` | release: version 5.1.0 |
| `core 87fae0b9` | Update WRT package HASH. |
| `core 68416086` | Update WRT package HASH. |
| `core 5fae35db` | Update WRT package HASH. |
| `core f896546e` | release: version 5.2.0 |
| `core 31b8faa4` | Update WRT package HASH. |
| `core db79454d` | release: version 5.3.0 |
| `core abfe3a95` | Update WRT package HASH. |
| `core b097daad` | release: version 5.4.0 |
| `core 41b61cfc` | release: version 5.5.0 |
| `core f69381e2` | release: version 5.5.0 |
| `core a471089f` | release: version 5.5.5 |
| `core e9d423bd` | release: version 5.5.5 |
| `core ad83d757` | release: version 5.5.5 |

### Core pointer bumps (19)

Moves upstream's hiddify-core pointer. Ours points at our own core fork and advances only by the lockstep rule; upstream core commits are triaged in LEDGER-core.tsv.

| Commit | Upstream's subject |
|---|---|
| `e4518328` | chore: bump hiddify-core to db74dfc |
| `876a52a4` | fix: leak issue |
| `e0218094` | chore(core): update hiddify-core to the latest main (84b47e9) |
| `7a424bc8` | chore(core): update hiddify-core to the latest main (5fae35d) |
| `f6b35ed7` | chore(core): update hiddify-core to the latest main (e89fabc) |
| `cb9389cc` | chore(core): update hiddify-core to the plain proxy lists (8e373b4) |
| `06244432` | build(core): bump hiddify-core for named noise presets |
| `f3421218` | chore(deps): hiddify-core with IPv6 by outbound |
| `764f7c33` | build: hiddify-core with XDRIVE, Xray-core v26.10.31 finalmask and MasterDNS |
| `6c072f9f` | build: hiddify-core with the libxray share link fix and the DNS tunnel benchmark |
| `3d40a047` | build: hiddify-core with the smart pool tuned past MasterDnsVPN's balancer |
| `b615c58d` | build: hiddify-core with the bounded quick check |
| `8bbe034a` | build: hiddify-core with the benchmark's query sizes and parallel runs |
| `36056144` | build: hiddify-core with keep-top and the upload and download speed tests |
| `c436b36f` | chore(core): hiddify-core without the OpenWrt feed releases |
| `e7e92034` | chore(core): hiddify-core with the Docker image fixed |
| `05749098` | chore(core): hiddify-core with Fake DNS, WARP and MASQUE fixes |
| `8377e001` | chore(core): hiddify-core with Soar, soar:// links and shared resolver discovery |
| `8996efde` | chore(core): hiddify-core with display types that show why a proxy failed |

### Proxy list and home redesign (18)

Upstream's proxy-list, home or logs redesign. No surviving code changes beyond translations and tests.

| Commit | Upstream's subject |
|---|---|
| `8614ad73` | refactor(dialog): move radio selection onto RadioGroup |
| `474b4631` | fix(ui): move the version label separator out of the translation |
| `29a770ae` | fix(toast): alert toasts start on the reading side |
| `f9b02976` | fix(connection): warn when VPN mode needs administrator rights |
| `d8c74ffc` | fix(connection): show the core's text when a start fails |
| `af480314` | refactor(connection): tidy the checks on a failed core start |
| `2e6ebd06` | chore(notification): delete the toast hover workaround and its test |
| `b1b9bd37` | fix(home): keep the radar out of the connect button's logo |
| `7b8ac208` | fix(home): keep the H in one piece while the bars light up |
| `b857fb53` | fix(proxy): a new connection no longer shows the last one's proxies |
| `c258d522` | fix(home): draw the connect button's rays and flares at full size |
| `321c2607` | feat(home): one capsule for an unavailable proxy and the way out |
| `d27cd3e7` | fix(home): an unavailable proxy reads like a ping and a tap tests it again |
| `a363deb8` | feat(home): change the connect button's label with a calm fade through |
| `063babdd` | feat(home): offer "Switch to fastest" in the ping row |
| `670f23e6` | feat(connection): bring back the connection check sheet, fixed |
| `e65b817a` | feat(proxy): show the proxy's status in the proxy info dialog |
| `514d939f` | feat(proxy): the proxy details show the home card's proxies live and fade cached results |

### Multi-profile, import, editor, updater (14)

Multi-profile management, import surfaces, the config editor, TV, upstream's updater or IP info. No surviving code changes beyond translations and tests.

| Commit | Upstream's subject |
|---|---|
| `5e0ff136` | fix(profile): keep tile state stable when the list re-sorts |
| `fb4d51a8` | refactor(profile): overlay the sort and update buttons on the list |
| `2eca5bac` | feat(core): add a curated trusted-link list |
| `f415d297` | feat(dialog): hold back the open button on unverified links |
| `ae125a79` | refactor(profile): use the plural remaining-days string |
| `038bde88` | fix(profile): name the real host in the deep-link import warning |
| `94320eef` | fix(profile): drop .mobileconfig from the accepted import formats |
| `410b3154` | refactor: remove unused WifiManager and update readWIFIState implementation |
| `4c0dc49f` | feat(profile): accept zip files in the file import |
| `305a16ad` | fix(profile): keep the config editor's type dropdown from crashing on unknown values |
| `c5dca91e` | fix(profile): open the profile editor at once and show the whole config editor |
| `c0f07948` | feat(json-editor): add a masterdns outbound template |
| `c2210c80` | feat(profiles): add a link to Android TV from a phone on the same Wi-Fi |
| `8ca4a8df` | feat(json-editor): a soar outbound template |

### Toast replacement (10)

Upstream's SnackBar replacement for toasts. This fork keeps toastification with RaynToast. Sampled as a group.

| Commit | Upstream's subject |
|---|---|
| `e25a0840` | feat(toast): flat toasts with an optional action button |
| `08eca241` | feat(notification): add a SnackBar layer above every screen |
| `0232e952` | feat(notification): show in-app messages as SnackBars |
| `f27086eb` | feat(notification): give SnackBars a type icon and medium text |
| `2085fc3d` | feat(notification): round SnackBars and space them like the toast |
| `93327f82` | feat(notification): show a close button on hover in SnackBars |
| `889e4181` | refactor: replace CustomToast with InAppNotificationController |
| `295de58d` | refactor(app): remove ToastificationWrapper |
| `31316af1` | build(deps): remove toastification |
| `fa3d7ec3` | feat(notification): pause the SnackBar timer on hover |

### Analyzer sweeps (7)

Cosmetic analyzer sweep, mostly on deleted paths; this fork did its own clean-up (BASELINE.md). Sampled as a group.

| Commit | Upstream's subject |
|---|---|
| `3cd9118c` | chore: apply dart fix across lib and test |
| `914542b3` | chore(analysis): clear the remaining analyzer warnings |
| `b3c9f71d` | chore(analysis): replace deprecated withOpacity with withValues |
| `0004e1f5` | chore(analysis): use plain Ref instead of the deprecated per-provider refs |
| `554257d4` | chore(analysis): drop the last two deprecated Riverpod APIs |
| `6933a9a4` | build: declare flutter_test as a dev dependency |
| `45bf09bd` | chore(analysis): clear the last analyzer infos |

### Home visuals (4)

Upstream's home-screen visuals, tied to its painter and new core states; any defect fix hidden in them is listed separately. Sampled as a group.

| Commit | Upstream's subject |
|---|---|
| `d76c64e8` | feat(home): ring, ripple and error text for the connect button |
| `33b62baf` | feat(home): show the traffic as an eclipse round the connect button |
| `1930c63f` | feat(connection): update EclipseLook states to include stopping and adjust animation logic |
| `75839d12` | feat(proxy):refactor the whole connection diagarm in ios and android enhance connection state handling and UI updates |

### Windows CI (3)

Upstream's Windows signing and VirusTotal CI; ci.yml does not run on custom-main. Sampled as a group.

| Commit | Upstream's subject |
|---|---|
| `f43e9349` | feat: integrate VirusTotal scanning into release workflow |
| `a032153d` | feat: enhance release notes with VirusTotal integration and SHA-256 digest automation |
| `a05fe903` | ci(windows): pass signing credentials to the zip step that runs the fastforge sign hook |

### Release bookkeeping (1)

Upstream release bookkeeping.

| Commit | Upstream's subject |
|---|---|
| `7804cada` | release: version 5.5.5 |

### DNS tunnels and new protocols (1)

A protocol the middleware does not serve.

| Commit | Upstream's subject |
|---|---|
| `core 375a33bd` | docs(history): MasterDNS, SlipNet and dnst:// links, the per-outbound smart pool |
