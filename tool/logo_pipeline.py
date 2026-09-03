#!/usr/bin/env python3
"""Generate every derived Rayn logo asset from one 2048x2048 template.

Why this exists rather than a folder of hand-exported PNGs: the brand mark is a
single flat colour plus an alpha channel — verified, all state variants share
one SHA-256-identical alpha and differ only in RGB. So every asset the app needs
(any colour, any size, opaque or transparent, PNG or ICO) is derivable from the
alpha channel alone, losslessly and reproducibly.

That also means resampling only ever touches ALPHA. A general RGBA downscale
would average transparent pixels' RGB into the edges and leave dark halos;
rebuilding `flat colour + resampled alpha` cannot.

Pure stdlib — no PIL. Run from the repo root:

    python tool/logo_pipeline.py            # write assets
    python tool/logo_pipeline.py --check    # verify template, write nothing

Idempotent: re-running produces byte-identical output.
"""
from __future__ import annotations

import argparse
import hashlib
import os
import struct
import sys
import zlib
from array import array

TEMPLATE = "Logo/rayn_frog_centered_v2_white_transparent.png"

# Windows is the one platform that neither masks the icon nor expects a bare
# mark, so it gets purpose-made artwork: an opaque black rounded-square tile
# (corner radius ~8% of width) with the amber mark inside, and TRANSPARENT
# outside the rounding so the corners actually read as round.
#
# It carries two colours, so the alpha-only model above does not apply to it —
# it needs a real premultiplied RGBA resample (see resample_rgba).
WINDOWS_TEMPLATE = "Logo/rayn_vpn_icon_amber_black.png"

# Brand colours. The four states are the same values the connection button
# tints with (RaynPalette.state*); keeping them here means a generated tray
# icon and an in-app tint can never drift apart.
AMBER = (0xF5, 0x9E, 0x0B)   # connected  / brand default
BLUE_LIGHT = (0x3A, 0x84, 0xCA)  # connecting
BLUE_DARK = (0x1E, 0x3A, 0x8A)   # disconnected
RED = (0xF2, 0x44, 0x44)     # error
WHITE = (0xFF, 0xFF, 0xFF)
CHARCOAL = (0x2A, 0x24, 0x1F)
BLACK = (0x00, 0x00, 0x00)


# ---------------------------------------------------------------- PNG decode

def decode_rgba(path: str):
    raw = open(path, "rb").read()
    if raw[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit(f"{path}: not a PNG")
    pos, idat, w, h, depth, ctype = 8, [], None, None, None, None
    while pos < len(raw):
        ln = struct.unpack(">I", raw[pos:pos + 4])[0]
        typ = raw[pos + 4:pos + 8]
        if typ == b"IHDR":
            w, h, depth, ctype = struct.unpack(">IIBB", raw[pos + 8:pos + 18])
        elif typ == b"IDAT":
            idat.append(raw[pos + 8:pos + 8 + ln])
        elif typ == b"IEND":
            break
        pos += 12 + ln
    if (depth, ctype) != (8, 6):
        raise SystemExit(f"{path}: need 8-bit RGBA, got depth={depth} ctype={ctype}")
    buf = zlib.decompress(b"".join(idat))
    bpp, stride = 4, w * 4
    out, prev, o = bytearray(h * stride), bytearray(stride), 0
    for y in range(h):
        f = buf[o]; o += 1
        cur = bytearray(buf[o:o + stride]); o += stride
        if f == 1:
            for i in range(bpp, stride):
                cur[i] = (cur[i] + cur[i - bpp]) & 0xFF
        elif f == 2:
            for i in range(stride):
                cur[i] = (cur[i] + prev[i]) & 0xFF
        elif f == 3:
            for i in range(stride):
                left = cur[i - bpp] if i >= bpp else 0
                cur[i] = (cur[i] + ((left + prev[i]) >> 1)) & 0xFF
        elif f == 4:
            for i in range(stride):
                a = cur[i - bpp] if i >= bpp else 0
                b = prev[i]
                c = prev[i - bpp] if i >= bpp else 0
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                cur[i] = (cur[i] + pr) & 0xFF
        elif f != 0:
            raise SystemExit(f"{path}: bad filter {f} on row {y}")
        out[y * stride:(y + 1) * stride] = cur
        prev = cur
    return w, h, bytes(out)


# ---------------------------------------------------------------- PNG encode

def _chunk(typ: bytes, data: bytes) -> bytes:
    return (struct.pack(">I", len(data)) + typ + data
            + struct.pack(">I", zlib.crc32(typ + data) & 0xFFFFFFFF))


def encode_png(w: int, h: int, samples: bytes, ctype: int) -> bytes:
    """ctype 6 = RGBA (4 bytes/px), 2 = RGB (3 bytes/px). Filter 0, so output
    is deterministic and re-runs are byte-identical."""
    nch = 4 if ctype == 6 else 3
    stride = w * nch
    rows = bytearray()
    for y in range(h):
        rows.append(0)
        rows += samples[y * stride:(y + 1) * stride]
    return (b"\x89PNG\r\n\x1a\n"
            + _chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, ctype, 0, 0, 0))
            + _chunk(b"IDAT", zlib.compress(bytes(rows), 9))
            + _chunk(b"IEND", b""))


# ---------------------------------------------------------- alpha operations

def alpha_of(w: int, h: int, px: bytes) -> array:
    return array("B", px[3::4])


def ink_bbox(w: int, h: int, a: array, thresh: int = 8):
    minx, miny, maxx, maxy = w, h, -1, -1
    for y in range(h):
        row = a[y * w:(y + 1) * w]
        lo = hi = -1
        for x, v in enumerate(row):
            if v > thresh:
                if lo < 0:
                    lo = x
                hi = x
        if lo >= 0:
            miny = min(miny, y); maxy = y
            minx = min(minx, lo); maxx = max(maxx, hi)
    return minx, miny, maxx, maxy


def integral(w: int, h: int, a: array) -> array:
    """Summed-area table, (w+1)*(h+1), so any box mean is 4 lookups."""
    iw = w + 1
    ii = array("L", bytes(4 * iw * (h + 1)))
    for y in range(h):
        rowsum = 0
        base, above, cur = y * w, y * iw, (y + 1) * iw
        for x in range(w):
            rowsum += a[base + x]
            ii[cur + x + 1] = ii[above + x + 1] + rowsum
    return ii


def resample_alpha(w: int, h: int, ii: array, nw: int, nh: int,
                   box=None) -> array:
    """Area-average `box` (default: whole image) of the source down to nw*nh.
    Area averaging is the correct filter for the large reductions here."""
    x0, y0, x1, y1 = box if box else (0, 0, w, h)
    sw, sh = x1 - x0, y1 - y0
    iw = w + 1
    out = array("B", bytes(nw * nh))
    for oy in range(nh):
        sy0 = y0 + (oy * sh) // nh
        sy1 = max(sy0 + 1, y0 + ((oy + 1) * sh) // nh)
        r0, r1 = sy0 * iw, sy1 * iw
        obase = oy * nw
        for ox in range(nw):
            sx0 = x0 + (ox * sw) // nw
            sx1 = max(sx0 + 1, x0 + ((ox + 1) * sw) // nw)
            total = ii[r1 + sx1] - ii[r0 + sx1] - ii[r1 + sx0] + ii[r0 + sx0]
            out[obase + ox] = (total + ((sx1 - sx0) * (sy1 - sy0)) // 2) // ((sx1 - sx0) * (sy1 - sy0))
    return out


def rgba_from_alpha(a: array, rgb) -> bytes:
    r, g, b = rgb
    out = bytearray(len(a) * 4)
    out[0::4] = bytes([r]) * len(a)
    out[1::4] = bytes([g]) * len(a)
    out[2::4] = bytes([b]) * len(a)
    out[3::4] = a.tobytes()
    return bytes(out)


def rgb_over_bg(a: array, fg, bg) -> bytes:
    """Composite a flat `fg` at coverage `a` over opaque `bg` -> RGB, no alpha.
    This is what Apple requires for an app icon."""
    out = bytearray(len(a) * 3)
    for c in range(3):
        f, k = fg[c], bg[c]
        lut = bytes(((f * v + k * (255 - v)) + 127) // 255 for v in range(256))
        out[c::3] = bytes(lut[v] for v in a)
    return bytes(out)


def resample_rgba(w: int, h: int, px: bytes, n: int) -> bytes:
    """Area-average an RGBA image down to n*n, premultiplying alpha first.

    Premultiplication is not optional: averaging straight RGB pulls the colour
    of fully transparent pixels into the edge, which is how downscaled icons
    pick up dark halos. Here the transparent region is black, so a naive
    average would happen to look right — but only by luck, and this stays
    correct if the artwork ever changes.
    """
    out = bytearray(n * n * 4)
    for oy in range(n):
        y0, y1 = (oy * h) // n, max((oy * h) // n + 1, ((oy + 1) * h) // n)
        for ox in range(n):
            x0, x1 = (ox * w) // n, max((ox * w) // n + 1, ((ox + 1) * w) // n)
            sr = sg = sb = sa = 0
            for y in range(y0, y1):
                row = y * w * 4
                for x in range(x0, x1):
                    i = row + x * 4
                    a = px[i + 3]
                    sr += px[i] * a
                    sg += px[i + 1] * a
                    sb += px[i + 2] * a
                    sa += a
            cnt = (x1 - x0) * (y1 - y0)
            o = (oy * n + ox) * 4
            if sa == 0:
                out[o:o + 4] = bytes(4)  # fully transparent
            else:
                out[o] = (sr + sa // 2) // sa          # un-premultiply
                out[o + 1] = (sg + sa // 2) // sa
                out[o + 2] = (sb + sa // 2) // sa
                out[o + 3] = (sa + cnt // 2) // cnt
    return bytes(out)


def place(a: array, sw: int, sh: int, canvas: int, frac: float,
          ii: array, w: int, h: int, box) -> array:
    """Scale the ink box to occupy `frac` of a square canvas, exactly centred."""
    inner = max(1, int(round(canvas * frac)))
    bw, bh = box[2] - box[0], box[3] - box[1]
    if bw >= bh:
        tw, th = inner, max(1, round(inner * bh / bw))
    else:
        th, tw = inner, max(1, round(inner * bw / bh))
    small = resample_alpha(w, h, ii, tw, th, box=(box[0], box[1], box[2], box[3]))
    out = array("B", bytes(canvas * canvas))
    ox, oy = (canvas - tw) // 2, (canvas - th) // 2
    for y in range(th):
        out[(oy + y) * canvas + ox:(oy + y) * canvas + ox + tw] = small[y * tw:(y + 1) * tw]
    return out


# ------------------------------------------------------------------ ICO

def write_ico(path: str, entries):
    """entries: [(size, png_bytes)]. PNG-compressed entries; Vista+ reads them
    at every size, and it keeps a 256px entry from bloating the file."""
    n = len(entries)
    head = struct.pack("<HHH", 0, 1, n)
    offset = 6 + 16 * n
    dirs, blobs = b"", b""
    for size, blob in entries:
        dirs += struct.pack("<BBBBHHII", 0 if size >= 256 else size,
                            0 if size >= 256 else size, 0, 0, 1, 32,
                            len(blob), offset)
        blobs += blob
        offset += len(blob)
    _write(path, head + dirs + blobs)


# ------------------------------------------------------------------ output

WROTE = []


def _write(path: str, blob: bytes):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    old = open(path, "rb").read() if os.path.exists(path) else None
    if old == blob:
        WROTE.append(("same", path, len(blob)))
        return
    open(path, "wb").write(blob)
    WROTE.append(("new " if old is None else "upd ", path, len(blob)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="verify only")
    args = ap.parse_args()

    if not os.path.exists(TEMPLATE):
        raise SystemExit(f"template missing: {TEMPLATE}")

    print(f"decoding {TEMPLATE} ...", flush=True)
    w, h, px = decode_rgba(TEMPLATE)
    a = alpha_of(w, h, px)

    # The template must be a flat single colour, or the alpha-only model is wrong.
    seen = set()
    for i in range(0, len(px), 4 * 97):
        if px[i + 3] > 250:
            seen.add(px[i:i + 3])
            if len(seen) > 1:
                break
    print(f"  {w}x{h}  alpha sha256[:16]={hashlib.sha256(a.tobytes()).hexdigest()[:16]}"
          f"  distinct opaque RGB={len(seen)}")
    if len(seen) > 1:
        raise SystemExit("template is not a flat single colour — the alpha-only "
                         "pipeline would silently discard detail. Aborting.")

    box = ink_bbox(w, h, a)
    print(f"  ink bbox {box} -> {box[2]-box[0]+1}x{box[3]-box[1]+1}", flush=True)
    print("  building summed-area table ...", flush=True)
    ii = integral(w, h, a)

    if args.check:
        print("\ncheck only — nothing written")
        return

    def flat(canvas, rgb, frac=None):
        al = (place(a, w, h, canvas, frac, ii, w, h, box) if frac
              else resample_alpha(w, h, ii, canvas, canvas))
        return al

    # ---- 1. in-app template (white, transparent; tinted at runtime) --------
    for sub, size in (("", 256), ("2.0x/", 512), ("3.0x/", 768)):
        al = flat(size, WHITE)
        _write(f"assets/images/{sub}logo.png",
               encode_png(size, size, rgba_from_alpha(al, WHITE), 6))

    # ---- 2. masters -------------------------------------------------------
    # Opaque, amber on black: legacy launcher icons + both splash screens.
    # 80% framing so the iOS squircle has margin to bite into.
    al80 = flat(1024, AMBER, frac=0.80)
    _write("assets/images/source/logo_black_1024.png",
           encode_png(1024, 1024, rgb_over_bg(al80, AMBER, BLACK), 2))
    # Transparent amber, native framing: Android adaptive foreground. The 16%
    # inset in mipmap-anydpi-v26/ic_launcher.xml supplies the 66% safe zone.
    alnat = flat(1024, AMBER)
    _write("assets/images/source/logo_foreground_1024.png",
           encode_png(1024, 1024, rgba_from_alpha(alnat, AMBER), 6))

    # ---- 3. iOS app icon: 1024, RGB, NO alpha (Apple rejects alpha) -------
    _write("ios/Runner/Assets.xcassets/AppIcon.appiconset/app-icon-1024.png",
           encode_png(1024, 1024, rgb_over_bg(al80, AMBER, BLACK), 2))

    # ---- 4. macOS: pre-rounded convention, so ~80% framing, alpha allowed --
    for size, name in ((16, "16"), (32, "16@2x"), (32, "32"), (64, "32@2x"),
                       (128, "128"), (256, "128@2x"), (256, "256"),
                       (512, "256@2x"), (512, "512"), (1024, "512@2x")):
        al = flat(size, AMBER, frac=0.80)
        _write(f"macos/Runner/Assets.xcassets/AppIcon.appiconset/app-icon-{name}.png",
               encode_png(size, size, rgba_from_alpha(al, AMBER), 6))

    # ---- 5. Android ------------------------------------------------------
    # Adaptive foreground: 108dp canvas, full-bleed; the XML inset pads it.
    for d, size in (("mdpi", 108), ("hdpi", 162), ("xhdpi", 216),
                    ("xxhdpi", 324), ("xxxhdpi", 432)):
        al = flat(size, AMBER)
        _write(f"android/app/src/main/res/drawable-{d}/ic_launcher_foreground.png",
               encode_png(size, size, rgba_from_alpha(al, AMBER), 6))
    # Legacy launcher: pre-composited on black, opaque.
    for d, size in (("mdpi", 48), ("hdpi", 72), ("xhdpi", 96),
                    ("xxhdpi", 144), ("xxxhdpi", 192)):
        al = flat(size, AMBER, frac=0.80)
        blob = encode_png(size, size, rgb_over_bg(al, AMBER, BLACK), 2)
        _write(f"android/app/src/main/res/mipmap-{d}/ic_launcher.png", blob)
        _write(f"android/app/src/main/res/mipmap-{d}/ic_launcher_round.png", blob)
    # Monochrome layer for Android 13+ themed icons: white silhouette, the
    # system recolours it. Same geometry as the foreground.
    for d, size in (("mdpi", 108), ("hdpi", 162), ("xhdpi", 216),
                    ("xxhdpi", 324), ("xxxhdpi", 432)):
        al = flat(size, WHITE)
        _write(f"android/app/src/main/res/drawable-{d}/ic_launcher_monochrome.png",
               encode_png(size, size, rgba_from_alpha(al, WHITE), 6))
    # Notification small icon: Android discards RGB and tints it, so this MUST
    # be a white-on-transparent silhouette or it renders as a solid blob.
    for d, size in (("mdpi", 24), ("hdpi", 36), ("xhdpi", 48),
                    ("xxhdpi", 72), ("xxxhdpi", 96)):
        al = flat(size, WHITE)
        _write(f"android/app/src/main/res/drawable-{d}/ic_stat_logo.png",
               encode_png(size, size, rgba_from_alpha(al, WHITE), 6))

    # ---- 6. desktop tray -------------------------------------------------
    # system_tray_notifier.dart picks by state AND host theme. Note the
    # filenames are historical: `tray_icon_disconnected` is used for
    # Connecting/Disconnecting, and `tray_icon_dark` means "dark ink, for a
    # LIGHT taskbar".
    tray = {"tray_icon_connected": AMBER,      # Connected
            "tray_icon_disconnected": BLUE_LIGHT,  # Connecting / Disconnecting
            "tray_icon": WHITE,                # Disconnected, dark taskbar
            "tray_icon_dark": CHARCOAL}        # Disconnected, light taskbar
    ico_sizes = (16, 20, 24, 32, 40, 48, 64, 128, 256)
    for name, rgb in tray.items():
        al = flat(128, rgb)
        _write(f"assets/images/{name}.png",
               encode_png(128, 128, rgba_from_alpha(al, rgb), 6))
        entries = []
        for s in ico_sizes:
            als = flat(s, rgb)
            entries.append((s, encode_png(s, s, rgba_from_alpha(als, rgb), 6)))
        write_ico(f"assets/images/{name}.ico", entries)
        master = flat(1024, rgb)
        _write(f"assets/images/source/{name}.png",
               encode_png(1024, 1024, rgba_from_alpha(master, rgb), 6))

    # ---- 7. Windows / snap / web ----------------------------------------
    # Windows: from its own pre-rounded tile, keeping alpha so the rounded
    # corners survive. Windows applies no mask of its own.
    if os.path.exists(WINDOWS_TEMPLATE):
        ww, wh, wpx = decode_rgba(WINDOWS_TEMPLATE)
        win = [(s, encode_png(s, s, resample_rgba(ww, wh, wpx, s), 6))
               for s in ico_sizes]
        write_ico("windows/runner/resources/app_icon.ico", win)
    else:
        raise SystemExit(f"missing {WINDOWS_TEMPLATE}")
    # Linux deb/AppImage package icon — linux/packaging/*/make_config.yaml
    # point at this path, so it ships on Linux and must not be left behind.
    _write("assets/images/source/ic_launcher_border.png",
           encode_png(1024, 1024, rgba_from_alpha(flat(1024, AMBER, frac=0.80), AMBER), 6))
    _write("snap/gui/app_icon.png",
           encode_png(256, 256, rgba_from_alpha(flat(256, AMBER, frac=0.80), AMBER), 6))
    for size, path in ((1024, "web/icon.png"), (192, "web/icon-192.png"),
                       (512, "web/icon-512.png")):
        _write(path, encode_png(size, size,
                                rgb_over_bg(flat(size, AMBER, frac=0.80), AMBER, BLACK), 2))

    n_new = sum(1 for s, _, _ in WROTE if s != "same")
    print(f"\n{len(WROTE)} assets, {n_new} changed:\n")
    for state, path, size in WROTE:
        print(f"  {state} {path:<70} {size:>8,} B")


if __name__ == "__main__":
    main()
