# Rayn VPN — Claude Code Implementation Plan
## UI Refinement: Current → Target Mockup

> **Purpose of this document.** This is the operational plan Claude Code should follow when refactoring the Rayn VPN Flutter UI. It is derived from the existing `rayn_vpn_ui_refinement_claude_code_plan.md` design guide and a direct visual diff between the *current* shipped UI and the *target* mockup. Every task is ordered to minimize regression risk and maximize reuse.
>
> **How to use this with Claude Code.** Work top-to-bottom. Each Phase has explicit file paths, expected behavior, and a verification step. Do **not** skip phases — later phases assume earlier primitives exist. After each Phase, commit before moving on.

---

## 0. Visual Diff Summary (Current → Target)

This section captures *exactly* what is changing. Every later task traces back to one of these deltas.

### 0.1 Sidebar / Navigation Rail

| Element | Current | Target |
|---|---|---|
| Top-of-rail branding | None (just a power icon next to "Home") | **Rayn VPN logo + wordmark** |
| Active state | Power-icon styled pill | Soft rounded-rect surface with gold icon + label |
| Inactive items | Outlined icons, white text | Outlined icons, slightly muted text |
| Visual weight | Heavy (large power button) | Calm, hierarchical |

### 0.2 Top Bar (Right Side)

| Element | Current | Target |
|---|---|---|
| Top-right region | Empty | **Notification bell** + **"Auto connect" labeled toggle** |

### 0.3 Ping Display

| Element | Current | Target |
|---|---|---|
| Container | None — bare icon + text floating on background | **Glass pill** with blur + soft border |
| Status indicator | None | **Semantic colored status dot** (green / yellow / red) |
| Typography | Single weight | **Value bold (18) + unit lighter (16, 75% opacity)** |
| Glow | None | Subtle ambient glow inheriting from orb |

### 0.4 Bottom-Left Stats Panel

| Element | Current | Target |
|---|---|---|
| Top affordance | "Show less" button (gold) | **"Protected" status card** (green shield + subtitle) |
| Live + Total traffic | Two separate cards, vertical arrows on left | **Single grouped card**, compact arrow + label rows |
| Monthly quota | Plain text block | **Glass card** with progress bar + meta row |
| Visual cohesion | Three loose blocks | One vertically-grouped glass column |

### 0.5 Server Card

| Element | Current | Target |
|---|---|---|
| Right-side affordance | "Balancer" text label + chevron | **Signal-bar health icon** (green) + chevron |
| Padding | Tight | More vertical breathing room |
| Surface | Flat translucent | Glass surface (shared system) |

### 0.6 Bottom Controls

| Element | Current | Target |
|---|---|---|
| Bottom row | **Segmented switch** (Proxy / System proxy / VPN) | **Three action cards** (Change server / Kill switch / Split tunneling) |
| Information density | Low (mode toggle only) | High (three primary actions surfaced) |

> ⚠️ The Proxy/System-proxy/VPN switch is **removed from the home screen** in the new design. Confirm with stakeholders whether this functionality is moving to Settings or being deprecated **before** Phase 7.

### 0.7 Background

| Element | Current | Target |
|---|---|---|
| Constellation density | Heavy across full canvas | Same identity, but **dimmed behind foreground UI** |
| Orb glow | Bright, broad | Slightly tightened, more focal |

---

## 1. Implementation Order & Rationale

Phases must run in this order. The dependency graph is:

```
Tokens ──▶ Typography ──▶ GlassSurface ──▶ Motion
                                │
                                ▼
                          (consumed by)
                                │
        ┌──────────┬────────────┼────────────┬───────────┐
        ▼          ▼            ▼            ▼           ▼
     Sidebar   PingPill   StatsColumn   ServerCard   ActionCards
                                │
                                ▼
                         BackgroundPass
                                │
                                ▼
                       A11y + Performance
```

| # | Phase | Why this order |
|---|---|---|
| 1 | **Design Tokens** | Every later widget reads from these. Done first to avoid rework. |
| 2 | **Typography System** | Same — a primitive consumed everywhere. |
| 3 | **GlassSurface widget** | The single visual building block for all redesigned cards. |
| 4 | **Motion constants** | Needed by ping pill + connect orb; defined before they're used. |
| 5 | **Sidebar refresh** | Self-contained, low blast radius. Good first integration test of tokens. |
| 6 | **Top bar (bell + Auto connect)** | New component; isolated. |
| 7 | **Ping pill** | Highest-visibility refinement. Validates GlassSurface + motion together. |
| 8 | **Stats column (Protected + Traffic + Quota)** | Larger composition; depends on all primitives. |
| 9 | **Server card refinement** | Smaller change, now that GlassSurface exists. |
| 10 | **Bottom action cards** | Replaces segmented switch — needs product confirmation (see §0.6). |
| 11 | **Background dimming pass** | Tuned last, against the *real* foreground composition. |
| 12 | **A11y + Performance** | Final pass over the whole tree. |

---

## 2. Phase 1 — Design Tokens

### Goal
Centralize every color, spacing value, radius, and shadow used by the new UI.

### Files to create

```
lib/theme/rayn_colors.dart
lib/theme/rayn_spacing.dart
lib/theme/rayn_radius.dart
lib/theme/rayn_shadows.dart
```

### `rayn_colors.dart`

Derive values from the mockup. Suggested starting palette:

```dart
import 'package:flutter/material.dart';

class RaynColors {
  // Background
  static const bgPrimary   = Color(0xFF0B0A0E);
  static const bgSecondary = Color(0xFF14131A);

  // Brand gold
  static const goldPrimary = Color(0xFFE8A317);
  static const goldSoft    = Color(0xFFF2C46B);
  static const goldGlow    = Color(0x55E8A317); // 33% alpha for glow layers

  // Semantic
  static const success = Color(0xFF3DD68C); // ping/protected green
  static const warning = Color(0xFFE8C547);
  static const danger  = Color(0xFFE5484D);

  // Text
  static const textPrimary   = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xB3FFFFFF); // 70%
  static const textMuted     = Color(0x80FFFFFF); // 50%

  // Glass
  static const glass       = Color(0x14FFFFFF); // ~8% white
  static const glassBorder = Color(0x1FFFFFFF); // ~12% white
}
```

### `rayn_spacing.dart`, `rayn_radius.dart`

Use the values from the design guide verbatim (xs=4, sm=8, md=12, lg=16, xl=24, xxl=32; pill=999, card=24, button=18).

### `rayn_shadows.dart`

```dart
class RaynShadows {
  static const ambient = [
    BoxShadow(color: Color(0x66000000), blurRadius: 24, offset: Offset(0, 8)),
  ];
  static const goldGlow = [
    BoxShadow(color: Color(0x33E8A317), blurRadius: 32, spreadRadius: 2),
  ];
}
```

### Verification
- Run `flutter analyze`. No new warnings.
- App still builds and renders identically (tokens not yet consumed).

---

## 3. Phase 2 — Typography System

### File
`lib/theme/rayn_typography.dart`

### Required styles (mapped to UI usage)

| Style | Used by | Spec |
|---|---|---|
| `display` | "33.5GiB" quota number | 32 / w700 |
| `title` | "Connected" under orb | 22 / w600 |
| `body` | Server name, action card titles | 16 / w500 |
| `metric` | Ping value "114" | 18 / w600 |
| `metricUnit` | Ping unit "ms" | 16 / w400 / 75% opacity |
| `label` | "Live traffic", "Monthly quota" | 13 / w500 |
| `caption` | "16.7% used", "24 days left" | 12 / w400 |

### Verification
- Replace one existing Text style with `RaynTypography.body` as a smoke test.
- Visual regression: minimal.

---

## 4. Phase 3 — GlassSurface Component

### File
`lib/widgets/surfaces/glass_surface.dart`

### API contract

```dart
class GlassSurface extends StatelessWidget {
  final Widget child;
  final double blur;        // default 20
  final double opacity;     // default 0.08
  final double radius;      // default RaynRadius.card
  final Color? glowColor;   // optional ambient glow
  final EdgeInsets padding; // default EdgeInsets.all(RaynSpacing.lg)
  final Border? border;     // default 1px RaynColors.glassBorder
  // ...
}
```

### Implementation notes
- Use `BackdropFilter` with `ImageFilter.blur`. Wrap in `ClipRRect` with the shared radius.
- Layer order (bottom → top): blur → fill (glass color at opacity) → border → child.
- If `glowColor != null`, render a `BoxShadow` around the outer container; do **not** stack multiple BackdropFilters for the glow.
- Wrap the whole thing in `RepaintBoundary` (Phase 10 will reinforce this).

### Verification
- Drop a `GlassSurface` containing a `Text("test")` onto the home screen. Confirm blur, transparency, and glow render. Remove after testing.

---

## 5. Phase 4 — Motion Constants

### File
`lib/theme/rayn_motion.dart`

### Required exports

```dart
class RaynMotion {
  // Durations
  static const fast   = Duration(milliseconds: 180);
  static const medium = Duration(milliseconds: 320);
  static const slow   = Duration(milliseconds: 600);

  // Ambient cycles
  static const glowBreath = Duration(seconds: 5);
  static const dotPulse   = Duration(milliseconds: 1800);

  // Curves
  static const standard  = Curves.easeOutCubic;
  static const ambient   = Curves.easeInOut;
  static const emphasis  = Cubic(0.2, 0.8, 0.2, 1.0);
}
```

### Verification
- File compiles. No widget changes yet.

---

## 6. Phase 5 — Sidebar Refresh

### Files to modify
- The existing nav rail widget (search `lib/` for the current `NavigationRail` or custom rail; rename and refactor in-place, do not duplicate).

### Required changes
1. **Add Rayn brand block at the top** of the rail: hexagon logomark + "Rayn VPN" wordmark. Use `RaynTypography.body` (semibold variant).
2. **Remove the standalone power icon** that currently sits next to "Home" — Home is just a normal nav item now.
3. **Active state**: rounded-rect background using `RaynColors.glass`, gold icon, gold label. Inactive: transparent bg, `textSecondary` icon + label.
4. **Hit area**: each row min height 48dp. Padding `EdgeInsets.symmetric(horizontal: 16, vertical: 12)`.
5. Keep route logic identical. Only visual changes.

### Verification
- All four nav items still navigate correctly.
- Active indicator follows current route.
- Logo renders crisply at native + 2x density.

---

## 7. Phase 6 — Top Bar (Notification + Auto Connect)

### New file
`lib/widgets/home/home_top_bar.dart`

### Layout
- Right-aligned `Row` pinned to top of the home content area.
- Two children, gap = `RaynSpacing.md`:
  1. `IconButton` — bell icon, wrapped in a `GlassSurface` (square, radius 16, padding 8).
  2. `Container` (radius `RaynRadius.button`, glass fill) holding `Text("Auto connect")` + `Switch`.

### Switch styling
- Active track: `RaynColors.goldPrimary`. Inactive track: `RaynColors.glass`. Thumb: white.

### Wiring
- The bell icon currently has no destination — leave a `// TODO(notifications)` and a no-op `onPressed`.
- The Auto-connect toggle should bind to whatever existing setting controls auto-connect (search for `autoConnect` in `lib/`). If none exists yet, scaffold a `SettingsProvider.autoConnect` boolean in the appropriate state-management layer (Riverpod / Provider / Bloc — whichever the codebase already uses).

### Verification
- Toggle state persists across app restarts (if a settings store exists).
- Bell button is keyboard-focusable and has a tooltip.

---

## 8. Phase 7 — Ping Pill (Highest-Impact Phase)

This is the most visible single change. Implement it carefully.

### New file
`lib/widgets/home/ping_pill.dart`

### Composition (left → right inside the pill)
1. WiFi icon (`RaynColors.textPrimary`, 18px)
2. **Status dot** — 8px circle, color from semantic logic below
3. Ping value — `RaynTypography.metric`
4. Unit "ms" — `RaynTypography.metricUnit`

Gaps: icon→dot 8, dot→value 8, value→unit 4. Outer padding: H 18 / V 10. Wrap in `GlassSurface(radius: RaynRadius.pill, glowColor: RaynColors.goldGlow)`.

### Semantic dot logic

```dart
Color _statusColor(int? pingMs, bool isConnecting) {
  if (isConnecting) return RaynColors.goldPrimary;
  if (pingMs == null) return RaynColors.textMuted;
  if (pingMs < 120) return RaynColors.success;
  if (pingMs < 250) return RaynColors.warning;
  return RaynColors.danger;
}
```

### Animations (use `RaynMotion`)
1. **Glow breathing** — outer shadow opacity oscillates between 0.3 and 0.5 over `glowBreath`. Use `AnimationController` with `repeat(reverse: true)`.
2. **Status dot pulse** — only when `connected`. Scale 1.0 → 1.15 over `dotPulse`, ease-in-out. Pause when disconnected.
3. **Ping value tween** — when the ping value changes, animate via `TweenAnimationBuilder<int>` over `RaynMotion.medium`.

### Reduced motion
If `MediaQuery.of(context).disableAnimations` is true, render static — no breathing, no pulse, no tween.

### Verification
- Manually feed values 80, 180, 300 — dot turns green, yellow, red.
- Disconnect → reconnect: dot pulse stops then resumes. Pill remains stable (no layout jump).

---

## 9. Phase 8 — Stats Column (Protected + Traffic + Quota)

### New file
`lib/widgets/home/stats_column.dart`

This replaces the loose stack of `Show less / Live traffic / Total traffic / Monthly quota` blocks with a cohesive vertical column, all built from `GlassSurface`.

### Composition

**Card 1 — Protected status**
- Green shield icon (left) + two-line text:
  - Title "Protected" — `RaynTypography.body` weight 600
  - Subtitle "Your connection is secure" — `RaynTypography.caption`
- When disconnected: title "Unprotected", subtitle "Your connection is exposed", icon color → `danger`.

**Card 2 — Traffic (combined)**
- Two rows:
  - `↑ Live traffic   592 B/s`
  - `↓ Total traffic   1.72 KiB`
- Up arrow uses `RaynColors.success`, down arrow uses `RaynColors.textSecondary`. Labels left-aligned, values right-aligned. Use `RaynTypography.label` for labels, `body` for values.

**Card 3 — Monthly quota**
- Header row: "Monthly quota" label.
- Big number: "33.5GiB" (`RaynTypography.display`) + " / 200 GiB" (muted).
- Progress bar: rounded, `RaynColors.goldPrimary` fill on `RaynColors.glass` track. Height 4. Radius pill.
- Footer row: "16.7% used" (left, muted) + "24 days left" (right, gold).

### Spacing
- Between cards: `RaynSpacing.md` (12).
- Inside each card: `RaynSpacing.lg` (16) padding.

### Verification
- "Show less" affordance is **gone** (intentional). If product wants to retain expand/collapse behavior, surface that decision before merging.
- All three cards visually align (same width, same radius, same border treatment).

---

## 10. Phase 9 — Server Card Refinement

### File
The existing server-row widget (search for `JP-TOKYO-PROD` or `Balancer` to find it).

### Changes
1. Wrap the row in `GlassSurface` instead of the current ad-hoc container.
2. Increase vertical padding to `RaynSpacing.lg`.
3. **Replace the right-side "Balancer" text** with a 4-bar signal indicator:
   - Bars rendered as 4 `Container`s of increasing height, separated by 2px.
   - Active bar count derived from ping (≤120ms = 4 bars, ≤200ms = 3, ≤300ms = 2, else 1). Active color `RaynColors.success`, inactive `RaynColors.glass`.
4. Keep the chevron, but use `RaynColors.textSecondary`.
5. Hierarchy: server name (body w600) primary; IP (caption, muted) secondary; flag avatar leading.

### Verification
- Tap still opens the server picker.
- Signal bars update live as ping changes (not on every frame — debounce to 1s).

---

## 11. Phase 10 — Bottom Action Cards

> ⚠️ **Confirm before starting**: the current Proxy / System proxy / VPN segmented switch is removed from the home screen in the target. Confirm whether (a) this is moving to Settings, (b) it's being deprecated, or (c) it should remain alongside the new action cards. Document the decision in this section before implementing.

### New file
`lib/widgets/home/action_card_row.dart`

### Composition
A `Row` of three equal-width `GlassSurface` cards:

| Card | Icon | Primary text | Secondary text | onTap |
|---|---|---|---|---|
| Change server | globe | "Change server" | "Best location" (or current) | open server list |
| Kill switch | shield | "Kill switch" | "On" / "Off" | toggle setting |
| Split tunneling | branch icon | "Split tunneling" | "On" / "Off" | open split-tunnel screen |

### Layout
- Card: padding `RaynSpacing.lg`, radius `RaynRadius.card`.
- Inside: leading icon (24px) at top-left, then `Spacer`, then two-line text block at bottom-left.
- Card height: fixed at 88dp so all three align even if labels wrap.

### State sources
- "Best location" pulls from current selected server.
- "On"/"Off" labels bind to existing kill-switch and split-tunnel settings (search `lib/` to find them; if missing, scaffold the boolean settings).

### Verification
- All three cards tappable, with proper InkWell ripple inside the glass clip.
- Secondary text reflects live state.

---

## 12. Phase 11 — Background Dimming Pass

### Goal
Reduce visual competition between the constellation background and the now-denser foreground UI, **without removing identity**.

### Approach (in priority order, pick the simplest that works)

1. **Radial vignette overlay** behind the foreground content column. A `RadialGradient` from `Colors.black.withOpacity(0.45)` at edges to transparent at center.
2. **Local backdrop dimming**: under the stats column and behind the server/action card row, place a low-opacity black layer (~15%) clipped to those regions.
3. Reduce constellation line opacity in the painter from current value by ~20%.

### Do NOT
- Remove constellation lines.
- Remove the ambient gold network animation.
- Reduce orb brightness.

### Verification
- All foreground text passes WCAG AA against background after dimming.
- Constellation still clearly visible in negative space (top half, sidebar margin).

---

## 13. Phase 12 — Accessibility + Performance Pass

### Accessibility checklist
- [ ] All interactive elements have a `Semantics` label (bell, auto-connect, action cards, server card, sidebar items).
- [ ] Touch targets ≥ 48×48dp. Specifically check: nav rail items, ping pill (if tappable), action cards.
- [ ] Contrast ratios ≥ 4.5:1 for body text, ≥ 3:1 for large text. Use a contrast checker on every text-on-glass surface.
- [ ] `MediaQuery.disableAnimations` honored in: ping pill glow, dot pulse, value tween, orb breathing.
- [ ] Focus order is logical for keyboard users (sidebar → top bar → orb → stats → server card → action cards).

### Performance checklist
- [ ] Wrap each animated element in its own `RepaintBoundary`: orb glow, ping pill, constellation painter, each card with shadow.
- [ ] Audit `BackdropFilter` count. Target: ≤ 6 simultaneously visible. Consolidate if more.
- [ ] Run `flutter run --profile` and capture frame times. 60fps p99 target on a mid-tier desktop.
- [ ] DevTools "Track widget rebuilds" — confirm stats column doesn't rebuild on every ping tick.
- [ ] Shadow audit: blur ≤ 32, spread ≤ 4 anywhere. No nested shadows.

### Reduced-motion override
Add a single helper:

```dart
bool reduceMotion(BuildContext context) =>
  MediaQuery.of(context).disableAnimations;
```

Used by every animation controller's `if (reduceMotion(context)) return;` guard.

---

## 14. Verification Matrix (final acceptance)

Each row must hold true before declaring the redesign complete.

| Criterion | How to verify |
|---|---|
| Sidebar shows Rayn brand at top | Visual |
| Active nav item has glass surface + gold label | Visual |
| Top-right has bell + Auto-connect toggle | Visual |
| Ping pill is glass, has dot, has value+unit hierarchy | Visual + interact (change ping) |
| Status dot color matches latency band | Inject 80, 180, 300 ms |
| Protected card present, color reflects connection state | Disconnect → red; reconnect → green |
| Traffic + Quota cards are unified glass column | Visual |
| Server card uses signal bars, not "Balancer" text | Visual |
| Three action cards present at bottom | Visual + tap each |
| Constellation still visible, foreground readable | Contrast check |
| Reduced motion respected | Toggle OS setting, observe |
| 60 fps profile build | DevTools |
| `flutter analyze` clean | CLI |

---

## 15. Out of Scope (do **not** do in this PR)

- Light theme.
- Localization changes.
- Server picker redesign (that's a separate screen).
- Settings screen redesign.
- Any backend / VPN protocol changes.
- Removing constellation art (explicitly preserved).

---

## 16. Risks & Mitigations

| Risk | Mitigation |
|---|---|
| BackdropFilter performance on lower-end Linux GPUs | Phase 12 enforces budget; fallback to flat translucent fill if frame budget exceeded. |
| Existing state-management is fragmented | Before Phase 6, audit how settings are stored. Reuse existing pattern; do not introduce a new one. |
| Removed Proxy/System-proxy/VPN switch breaks user workflows | Confirm with product before Phase 10. If retained, place in Settings → Connection. |
| Ping value flicker during reconnects | Phase 7 handles via `TweenAnimationBuilder` and a connecting state for the dot. |
| Glass surfaces look muddy on certain wallpapers | The constellation background is fixed; verify only against it. No user wallpapers in scope. |

---

## 17. Suggested Commit Sequence

One commit per phase keeps the diff readable for review:

```text
feat(theme): add Rayn design tokens (colors, spacing, radius, shadows)
feat(theme): add Rayn typography scale
feat(widgets): add GlassSurface primitive
feat(theme): add Rayn motion constants
refactor(nav): apply token-driven sidebar with brand block
feat(home): add top bar with notifications + auto-connect toggle
feat(home): redesign ping pill with semantic status dot
feat(home): unify protected + traffic + quota into stats column
refactor(home): refine server card with signal-bar indicator
feat(home): add bottom action cards (change server / kill switch / split tunnel)
chore(home): apply background dimming + glow tuning
chore(a11y,perf): final accessibility and performance pass
```

---

## 18. Reference

- Original design intent: `rayn_vpn_ui_refinement_claude_code_plan.md` (this plan operationalizes it).
- Target mockup: `NEW_UI_Design.png`.
- Current state: `CURRENT_UI_design.png`.
