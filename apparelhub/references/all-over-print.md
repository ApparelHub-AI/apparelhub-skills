# All-Over Print Products

Products where the design covers the ENTIRE surface — pillows, doormats, area rugs, beach towels, AOP tees, luggage tags, mugs, phone cases. Different rules from standard front-print apparel.

---

## 1. SKIP Phase 2 transparency processing

All-over-print products print edge-to-edge INCLUDING background color. There's no "transparent shows pillow color through" semantic — the pillow fabric is white, and you make it APPEAR a color by filling the design image with that color edge-to-edge.

Use the raw generated image from Phase 1 directly in the mockup and product-create calls.

---

## 2. Background must extend to every edge of the canvas

If the background doesn't reach all four corners, white substrate shows through at the margins on the printed product.

**Verify with a 4-corner pixel check before submitting:**

```python
from PIL import Image
img = Image.open(design_path)
w, h = img.size
corners = [(0,0), (w-1,0), (0,h-1), (w-1,h-1)]
for x, y in corners:
    print(img.getpixel((x, y)))
# All 4 must be the intended background color (or very close — within ±5 per channel)
```

If any corner is white or off-color, regenerate with a more emphatic prompt ("solid burgundy background, fill entire canvas to all four edges, no white margins"), or post-process locally to extend the background.

---

## 3. Generate the design at ~80% of canvas size, with margin

Design content should sit at ~80% of canvas size, centered, with the solid background color filling the remaining 20% margin. This prevents the design from being cut off at the product's edges (every all-over-print product has small bleed/safety margins).

---

## 4. Print at FULL area dimensions in Phase 3 / Phase 4

For all-over-print, the template's `width` and `height` MUST equal `area_width` and `area_height`, with `top: 0, left: 0`. NEVER shrink — that's what causes white edges to show.

Example for an 18×18 pillow (area = 2717 × 2717):
```json
{
  "provider_ref_id": "front",
  "image_url": "<full_canvas_design_url>",
  "area_width": 2717,
  "area_height": 2717,
  "width": 2717,
  "height": 2717,
  "top": 0,
  "left": 0
}
```

For products with a back side (pillows): submit the same solid background color as a flat image on the `back` template.

---

## 5. The "don't name the product in the prompt" trap

AI image generators interpret product names too literally. Saying "luggage tag" in the prompt produces a *picture of a luggage tag* (drawn corners, faux strap hole, edge ornaments), which prints on the real tag and creates image-on-top-of-image artifacts.

NEVER include the product's literal name in the prompt. Always describe the FLAT GRAPHIC, not the product.

| Product | ❌ Don't prompt | ✅ Prompt instead |
|---|---|---|
| Luggage tag | "luggage tag design" | "flat luxury monogram emblem on burgundy" |
| Pillow | "pillow design" | "flat all-over botanical pattern, edge-to-edge teal" |
| Doormat | "doormat design" | "flat landscape graphic, horizontal welcome text, edge-to-edge brown" |
| Phone case | "phone case design" | "flat back-print floral pattern with cream fill" |
| Mug | "mug design" | "wraparound vintage botanical strip on cream" |

**Diagnostic shape**: if the AI output looks like a shrunken version of the FINAL PRODUCT (has the product outline, hardware, decorative edges matching the product's physical edges), the prompt was too literal. Rewrite to describe the printed graphic only, then regenerate.

---

## 6. Product-specific gotchas

### Pillow (Printful product 214)

- Variant sizes: 18"×18" (9515), 20"×12" lumbar (7907), 22"×22" (11077)
- 18×18 area = 2717 × 2717 px
- Submit BOTH `front` and `back` templates. Back can be the same solid background color (flat fill) or a complementary back-graphic.

### Doormat / Area rug (Printful product 924)

- **Doormats MUST be LANDSCAPE orientation** (text reads left-to-right when standing in front)
- Landscape variants: 36"×24" (23705), 60"×36" (23706), 72"×48" (23707)
- Portrait variants exist (24"×36" = 23702, etc.) for wall/decorative rugs ONLY
- For doormats: use a DARK background (dark brown, black) since people step on it
- Do NOT rotate a portrait design 90° — that rotates text sideways. Regenerate natively in landscape composition with horizontal text.
- 36×24 area = 1437 × 972 px

### Water bottle (Printful product 382)

- This is NOT all-over print — the bottle is white, design needs TRUE transparency
- Print area is wide and short (700 × 433 px) — vertical/tall designs work best (botanical strips, tall florals)
- Template `provider_ref_id: "default"`
- To position higher on the bottle: reduce `height`, keep `top: 0`. To center horizontally: adjust `left`.

### Acrylic luggage tag (Printful product 938, 2.4"×4")

The most fragile of the all-over products — has rounded corners on all 4 sides AND a real physical strap hole at the top.

- Print area: **1622 × 2677 px**, single placement `provider_ref_id="default"`, single variant `provider_variant_id=23889`, cost $13.20
- **NEVER include an illustrated strap hole** in the design — the real tag has one. A faux hole prints as a dark circle near the top. If a source design has one, clone-stamp it out: copy a clean region from below the hole and hard-paste over the hole area (no soft mask — Gaussian blur reduces center opacity and leaves residue).
- **NEVER include an illustrated outer tag-shape frame** (chamfered corners, gold border at canvas edge, etc.). The real tag's edge IS the tag shape. A drawn frame conflicts with the rounded tag corners. If you must keep a decorative gold border, place it well INSIDE the canvas with margin so the tag's edges crop only the outer padding, not the gold frame.
- **Use ONE uniform background color** across the entire canvas. Designs that have two shades of the same color (interior textured + outer canvas padding) print as a visible boundary line. See "Pillow uniform-color technique" below for the fix.
- **Margin sweet spot: ~2.5%** padding between the gold/decorative frame and the canvas edge. Larger (4.5%+) reads as a "framed picture" too detached from the edge. Smaller (<1.5%) risks conflicting with the tag's rounded corners.

### AOP Athletic Tee

- True all-over print (front + back + sleeves)
- Design needs to handle the seams; avoid important content at the body-side seam line
- Cost ~$22, recommended retail $44.99

### Phone cases, mugs (when on the catalog)

- Phone case: same rules as luggage tag re: avoid drawing the case shape
- Mug: design "wraps" around the cylinder. The print area is wider than tall (typically ~2480 × 1100 for a 11oz mug)

---

## 7. Pillow uniform-color technique (for accent-color designs)

When a design has a primary background color + accent details (e.g., burgundy with gold monogram on a luggage tag), but the source has SUBTLE color drift between the design body and edge padding, the print shows a visible boundary line.

Fix via Pillow pixel-class replacement — no AI re-generation needed:

```python
from PIL import Image
import numpy as np

img = Image.open(design_path).convert('RGBA')
arr = np.array(img)

# 1. Identify background (burgundy) + accent (gold) pixels via color classification
burgundy_mask = (
    (arr[:,:,0] > 60) & (arr[:,:,0] < 180) &
    (arr[:,:,1] < 60) & (arr[:,:,2] < 80) &
    (arr[:,:,0] > arr[:,:,1] + 30) & (arr[:,:,0] > arr[:,:,2] + 20)
)
gold_mask = (
    (arr[:,:,0] > 100) & (arr[:,:,1] > 60) &
    (arr[:,:,0] > arr[:,:,2] + 30) & (arr[:,:,1] > arr[:,:,2] + 10) &
    ~burgundy_mask
)

# 2. Pick the MEDIAN burgundy as the target uniform color (median is robust against texture noise)
target = tuple(int(np.median(arr[burgundy_mask][:, c])) for c in range(3))

# 3. Replace every non-gold pixel with the uniform target
result = arr.copy()
result[~gold_mask] = (*target, 255)

Image.fromarray(result).save('/tmp/uniform_burgundy.png')
```

Verified output for a Paul Oliver luggage tag: 88.9% uniform burgundy, 11.1% gold, zero "other" pixels.

### QC snippet — verify the fix landed

```python
non_bg = arr.sum(axis=2) > 80
ys, xs = np.where(non_bg)
tag_t, tag_b = ys.min(), ys.max()
body = arr[tag_t + int((tag_b-tag_t)*0.15):tag_b+1, xs.min():xs.max()+1]  # skip strap area
gold = (body[:,:,0]>100)&(body[:,:,1]>60)&(body[:,:,0]>body[:,:,2]+30)
light = (body.sum(axis=2)>400) & ~gold
pct = light.mean() * 100
# PASS if pct < 0.1% — anything higher means substrate showing or two-shade boundary still visible
```

Generalizes to any all-over-print product where the design uses solid-color regions + accent colors.

---

## 8. Mockup verification — extra-critical for all-over print

Visually inspect the mockup for:
- Background reaches all four edges (no white margins)
- No visible boundary line between background "shades"
- **Design is UPRIGHT** (text reads normally) — some templates render the print file rotated (see §9)
- **Design is fully visible on the product face** — not cut off at a fold, hem, or silhouette edge (see §9)
- **NO unprinted surfaces**: every print placement of the product carries a file; an unprinted placement on an all-over product is raw white fabric (see §10)
- **NO BLANK or HALF-COVERED FACES on multi-face / multi-piece merch** — check the back of a wallet, the second ear cup, the far side of a duffle; each face must carry the design, none split across a fold (see §9 "Multi-FACE wraps")
- **NO chroma green anywhere** — if the keying background survived to the print file, stop and recompose
- **Resolution is high enough** — a soft/pixelated print, or a platform "low resolution" QC block, means the design was too small (see §11)
- For doormats: text reads left-to-right when product is oriented normally
- For luggage tags: no faux strap hole visible in the design, no faux tag-frame visible inside the print area
- For pillows: front and back surfaces both look intentional (back can be solid color or complementary graphic — both fine, just not blank)

---

## 11. Design resolution — regenerate (or upscale) when the platform blocks low-res

AI designs are generated at ~1024px and then keyed + auto-cropped to the artwork bounding box,
which can shrink them to e.g. 847×596. Placed on a large print area (accessories like passport
wallets, phone cases, tote panels), the effective print DPI is too low and the fulfillment
platform's QC gate returns a **"low resolution" block** — with no remediation the build
dead-ends (the NORWAY passport wallet).

Rules:
- **Generate designs at the largest size the model offers** (prefer 1792 on the long side over
  1024), so the cropped artwork stays large.
- **Every print file should be ≥ ~2000px on the long side.** Fill/face composition already outputs
  a high-pixel canvas; a raw PLACED design that's smaller is the risk.
- **When a design is below the floor, upscale it (Lanczos) to the print-area resolution before
  create** — this clears the QC gate (it's what every POD tool does). MCP v0.3.7+ does this
  automatically on the placed path (`ensure_resolution.py`) and warns you to regenerate for real
  detail. For raw-API builds, upscale the design yourself and re-upload before create.
- **Upscaling doesn't add detail.** For detail-critical large-format goods, REGENERATE the source
  design at higher resolution rather than relying on the upscale.
- **If an automated run hits a genuine low-res block it can't clear, it must DEFER the item
  (mark it blocked) and move on** — never let one un-buildable product stall the whole run.

---

## 9. The print AREA is not always the visible FACE (wrap goods)

Some templates print ONE file across SEVERAL physical surfaces, or render the file in a
different orientation than you composed it. Centering art on the AREA then lands it on a fold,
a seam, or upside down. These are empirically calibrated facts (grid-file preview renders
against the live providers, 2026-07-09 — the WC26 ENGLAND sock + drawstring incidents):

### Sublimation socks (Printful 882 and similar)

- FOUR placements, all 632×2620: `leg_front_right`, `leg_front_left`, `leg_back_right`, `leg_back_left`. Fill ALL of them or the unprinted strips ship as raw white fabric (one printed strip out of four = one decorated sock side, three white).
- **The FRONT strips render the file ROTATED 180°** (file-top = toe): compose the art upside down in the file so it reads upright on the worn sock.
- **The BACK strips render the file UPRIGHT** (file-top = cuff): compose those files normally. One rotated file on all four strips prints upside down on the backs.
- The strip wraps the leg tube — only the central ~64% of the width stays frontal. Art wider than that clips at the silhouette (art at 86% width = visibly cut-off text). Keep art within x 0.18–0.82 of the strip.

### Drawstring bags (Printify blueprint 414 and similar wrap templates)

- The single `front` area (4950×11100 ≈ 16.5"×37" — note the extreme aspect) is the **front + back in one file, folded at the bottom**. Art centered on the AREA straddles the fold and prints cut off at the hem.
- The visible front = the **top ~50%** of the file; the drawstring channel eats the top ~5% and grommet corner cuts start at ~45%. Compose art centered within y 0.05–0.43; let the background fill the whole file (the back comes out solid — retail-correct).

### Multi-FACE wraps: the design goes on EVERY face (no blank faces)

Some wrap areas carry MORE THAN ONE physical face in a single print file. Centering the art
lands it across the FOLD between faces, splitting it, and leaves each face with half a design.
The rule: **multi-face merch gets the design on ALL faces — never a blank or half-covered face.** Grid-calibrated cases:

- **Zipper / passport wallets** (Printify 708, ~2482×2756, near-square): the area is the front
  AND back exterior folded at the bottom. The front face is the TOP half (renders upright); the
  back face is the BOTTOM half and renders ROTATED 180° past the fold. Compose the design onto
  BOTH halves — upright on top, pre-rotated on the bottom so it reads upright on the back. A
  centered design prints split down the spine (the BELGIUM wallet).
- **Headphone ear-cup shells** (Printify 1666, AirPods Max): the Left and Right cups are SEPARATE
  oval faces (separate placements, same size). Put the design on BOTH — one printed cup next to a
  blank one reads broken (the BELGIUM headphones). Because the face is an oval, inset the art
  (~68% width, centered) so it doesn't clip at the cup edge.
- **Duffles** (Printful 465): the FRONT is the hero display face; keep its art in the central
  frontal window (~x 0.12–0.88, y 0.15–0.75) — it wraps past the top seam, under the base, and
  around the rounded ends, so full-width art clips (the NORWAY duffle). The other panels
  (back/sides/top/bottom/pocket) are STRUCTURAL — give them the **solid background**, NEVER the
  design plastered full-bleed (busy + clipped) and NEVER bare fabric (the NORWAY white strip).
  Every panel must be covered; only the front carries the design (a merchant can request the design
  on the back too).

### DISPLAY faces vs STRUCTURAL panels (the "no white strip, no design-everywhere" rule)

When a product has several print placements, decide per placement:
- **Display face** — a surface the design belongs on (sock leg strips, both headphone cups, a
  wallet's front+back, a duffle's front). Compose the design onto it (windowed/inset as needed).
- **Structural panel** — a wrap/utility surface (duffle sides/top/bottom/pocket, backpack
  top/bottom/pocket, an interior label). Fill it with the **solid background** derived from the
  design's palette. Never leave it blank/white; never stamp the full design across it.

The MCP does this automatically (a placement with a known face layout = display face; otherwise
structural → solid). Building by hand: put the design only on the true display faces and a matching
solid on everything else. The goal: **every face covered, none blank, none busy/clipped.**

### The generic rule

A fill/all-over print area with an extreme aspect (≤ 1:2 or ≥ 2.2:1) that isn't a known
strip/banner product is a SUSPECT WRAP — assume a fold or seam crosses it. A near-square area on a
folding good (wallets, passport covers) is a SUSPECT TWO-FACE wrap. Any product with more than one
same-size print placement (ear cups, cufflinks, two-panel goods) needs the design on EVERY piece.
Run a preview render and check where the art actually lands — and that no face is blank — BEFORE
building the product; never trust a blind center.

The ApparelHub MCP server (v0.3.7+) applies these face layouts, rotations, multi-face composition,
and multi-piece replication automatically. If you build print_data by hand against the raw API,
you must replicate them yourself: enumerate every placement in the garment's `templates[]`, and
give each face/piece a file.

---

## 10. Cover EVERY placement — and match each file to its placement's orientation

`GET /agents/v1/merchandise/<provider_uuid>/product/<ref>` lists every placement under the
variant's `templates[]`. For fill/all-over goods:

- **Same-size sibling placements** (the other sock strips) get an art file composed for THAT placement's orientation (see §9 — sock fronts and backs differ).
- **Different-size siblings** (backpack `top` 3000×857 / `bottom` 2999×535 / `pocket` 2060×1269 on Printful 279) get a **solid canvas in the art's background color** — a solid color stretches to any aspect losslessly, so one file serves all of them. Leaving them out is what shipped the SPAIN backpack with white bands.
- Embroidery placements are never part of a fill set.
- The mockup preview call should carry the SAME template list, so the render proves the coverage.
