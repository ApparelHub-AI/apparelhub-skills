#!/usr/bin/env python3
"""
make_transparent.py — strip a solid chroma (green-screen) background from an
ApparelHub-generated design and write a true-RGBA PNG ready for the /transform
upload (Phase 2 of the product-creation pipeline).

This is the packaged, reviewable version of the local transparency step. The
skill always invokes it BY PATH so it can be whitelisted without granting
arbitrary `python3` execution. It is pure-stdlib + Pillow (no numpy).

What it does, in order:
  1. Detect the chroma color (median of the 4 corners) unless --chroma is given.
  2. Flood-fill from the image border to clear the connected exterior background.
  3. Sweep the whole image for any remaining chroma pixels — this is what makes
     enclosed regions transparent (the holes in B/e/d/o/a, gaps between letters,
     spaces between rays). On by default; disable with --keep-enclosed.
  4. Optionally despill: neutralize residual green fringe on anti-aliased edges.
  5. Write cleared pixels as pre-multiplied white (255,255,255,0) so Printful's
     flatten-against-white does NOT leave dark halos.
  6. Optionally write a dark-background preview JPG to eyeball it on a "shirt".

Usage:
  python3 make_transparent.py IN.png OUT.png
  python3 make_transparent.py IN.png OUT.png --chroma 00FF00 --tolerance 90
  python3 make_transparent.py IN.png OUT.png --dominance          # muted/dark green bg
  python3 make_transparent.py IN.png OUT.png --despill --preview OUT_preview.jpg

Exit codes: 0 = ok, 2 = bad args / file, 3 = result looks wrong (corners not clear).
"""
import argparse
import sys
from collections import deque

try:
    from PIL import Image
except ImportError:
    sys.stderr.write("Pillow is required: pip install pillow\n")
    sys.exit(2)


def parse_hex(s):
    s = s.strip().lstrip("#")
    if len(s) != 6:
        raise argparse.ArgumentTypeError("--chroma must be a 6-digit hex like 00FF00")
    return tuple(int(s[i:i + 2], 16) for i in (0, 2, 4))


def parse_rgb(s):
    parts = s.split(",")
    if len(parts) != 3:
        raise argparse.ArgumentTypeError("expected R,G,B")
    return tuple(int(p) for p in parts)


def detect_chroma(px, w, h):
    """Median per-channel of the four corner pixels — robust to one odd corner."""
    corners = [px[0, 0], px[w - 1, 0], px[0, h - 1], px[w - 1, h - 1]]
    chan = lambda i: sorted(c[i] for c in corners)
    med = lambda v: (v[1] + v[2]) // 2  # mean of the two middle values
    return tuple(med(chan(i)) for i in range(3))


def make_matcher(target, tolerance, dominance):
    """Return is_background(r,g,b) -> bool.

    Default: per-channel distance box around the detected chroma.
    --dominance: 'green dominates' test — catches muted/desaturated green screens
    (e.g. ~129,192,99) and anti-aliased edges that a tight box would miss.
    """
    tr, tg, tb = target
    if dominance:
        def is_bg(r, g, b):
            return (g > r + 20) and (g > b + 20) and (g > 100)
    else:
        def is_bg(r, g, b):
            return abs(r - tr) < tolerance and abs(g - tg) < tolerance and abs(b - tb) < tolerance
    return is_bg


def flood_from_border(px, w, h, is_bg):
    """Clear the connected exterior background reachable from any edge pixel."""
    visited = bytearray(w * h)
    dq = deque()
    for x in range(w):
        dq.append((x, 0)); dq.append((x, h - 1))
    for y in range(h):
        dq.append((0, y)); dq.append((w - 1, y))
    cleared = 0
    while dq:
        x, y = dq.popleft()
        i = y * w + x
        if visited[i]:
            continue
        visited[i] = 1
        r, g, b, a = px[x, y]
        if not is_bg(r, g, b):
            continue
        px[x, y] = (255, 255, 255, 0)
        cleared += 1
        if x > 0: dq.append((x - 1, y))
        if x < w - 1: dq.append((x + 1, y))
        if y > 0: dq.append((x, y - 1))
        if y < h - 1: dq.append((x, y + 1))
    return cleared


def sweep_enclosed(px, w, h, is_bg):
    """Clear any remaining chroma pixels anywhere (letter holes, interior gaps)."""
    swept = 0
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a != 0 and is_bg(r, g, b):
                px[x, y] = (255, 255, 255, 0)
                swept += 1
    return swept


def despill(px, w, h):
    """Neutralize green fringe on remaining opaque/edge pixels: clamp G to max(R,B)."""
    fixed = 0
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            cap = max(r, b)
            if g > cap + 10:
                px[x, y] = (r, cap, b, a)
                fixed += 1
    return fixed


def main():
    ap = argparse.ArgumentParser(description="Strip a solid chroma background to true RGBA transparency.")
    ap.add_argument("input")
    ap.add_argument("output")
    ap.add_argument("--chroma", type=parse_hex, default=None,
                    help="background hex (e.g. 00FF00). Default: auto-detect from corners.")
    ap.add_argument("--tolerance", type=int, default=90,
                    help="per-channel match tolerance for the distance test (default 90).")
    ap.add_argument("--dominance", action="store_true",
                    help="use green-dominance test instead of a color box (for muted/dark green screens).")
    ap.add_argument("--keep-enclosed", action="store_true",
                    help="only flood from the border; do NOT clear enclosed chroma (rarely wanted).")
    ap.add_argument("--despill", action="store_true",
                    help="neutralize residual green fringe on anti-aliased edges.")
    ap.add_argument("--preview", metavar="PATH", default=None,
                    help="also write a composite-over-dark JPG to sanity-check on a dark shirt.")
    ap.add_argument("--preview-bg", type=parse_rgb, default=(18, 18, 18),
                    help="preview background as R,G,B (default 18,18,18).")
    args = ap.parse_args()

    try:
        img = Image.open(args.input).convert("RGBA")
    except Exception as e:
        sys.stderr.write(f"cannot open {args.input}: {e}\n")
        sys.exit(2)

    w, h = img.size
    px = img.load()
    target = args.chroma or detect_chroma(px, w, h)
    is_bg = make_matcher(target, args.tolerance, args.dominance)

    cleared = flood_from_border(px, w, h, is_bg)
    swept = 0 if args.keep_enclosed else sweep_enclosed(px, w, h, is_bg)
    fringe = despill(px, w, h) if args.despill else 0

    img.save(args.output, "PNG")

    total = w * h
    transparent = cleared + swept
    pct = 100.0 * transparent / total
    corners = [px[0, 0][3], px[w - 1, 0][3], px[0, h - 1][3], px[w - 1, h - 1][3]]
    print(f"input        {args.input} ({w}x{h})")
    print(f"chroma       {'auto ' if args.chroma is None else ''}#{target[0]:02X}{target[1]:02X}{target[2]:02X}"
          f"  mode={'dominance' if args.dominance else f'box±{args.tolerance}'}")
    print(f"flood        {cleared:,} px")
    print(f"sweep        {swept:,} px  ({'skipped' if args.keep_enclosed else 'enclosed regions'})")
    if args.despill:
        print(f"despill      {fringe:,} px")
    print(f"transparent  {transparent:,} / {total:,} ({pct:.1f}%)")
    print(f"corner alpha {corners}  (want all 0)")
    print(f"output       {args.output}")

    if args.preview:
        bg = Image.new("RGBA", img.size, tuple(args.preview_bg) + (255,))
        Image.alpha_composite(bg, img).convert("RGB").save(args.preview, "JPEG", quality=85)
        print(f"preview      {args.preview}")

    if any(a != 0 for a in corners):
        sys.stderr.write("WARNING: corners are not fully transparent — try --dominance or raise --tolerance.\n")
        sys.exit(3)


if __name__ == "__main__":
    main()
