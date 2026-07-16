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

## 9. Wrap / multi-face placement is handled by the platform — request `print_style: auto`

The print AREA is not always the visible FACE: some templates print one file across several
physical surfaces (sock legs; a drawstring bag or tall tote folded at the bottom; a wallet's
front+back; a notebook's back+spine+front; a duffle's panels), wrap it around a tube (mugs,
bottles, tumblers, glasses, candles), cross a face with a seam (a backpack's pocket), foreshorten
it over a dome (bucket hats, beanies), or render it inverted. Hand-placing art on the AREA lands it
on a fold/seam, wrapped off the sides, or upside down.

**You no longer compute any of this.** The platform composes the correct per-placement print files
server-side — face windows, per-face rotation, solid structural panels, transparent per-face wraps,
interior/label blanking, seam-avoidance, and cylinder/dome insets — from a continuously-updated
calibration set (new garment fixes ship as platform DATA, so the tools improve with no client
update). Just:

- Use **`ship_product`** or **`create_product`** (or call **`prepare-print-data`** directly) with
  **`print_style: "auto"`** (the default). The platform picks fill-vs-placed, composes EVERY
  non-interior placement, and returns `print_data` you pass straight to product-create + the mockup.
  `print_style: "fill"` / `"placed"` override only if you deliberately want one.

### You STILL own the quality gate (unchanged)

Composition is automatic; VERIFYING it is still your job. After the mockup renders, inspect it at
full resolution (§8) and confirm:
- **Upright** — no face/panel rendered rotated or mirrored.
- **No clipped lettering / subject** — nothing cut by a fold, seam, or the print edge; nothing
  wrapped off the sides of a mug/hat.
- **Every placement covered** — no blank/white face on a multi-surface product; interior/label
  surfaces (`inside_*`, `page*`, `label_*`) correctly left unprinted (NOT solid-filled).
- **Not busy/clipped** — structural panels (backpack top/bottom/pocket, duffle sides) read as a
  clean solid, not the full design plastered across them.

If a wrap/multi-face good composes wrong, report the garment ref + what clipped — the fix is a
platform calibration update (a data change), not something you patch in `print_data` by hand.

---

## 10. Cover EVERY placement — the platform does this; the mockup proves it

For fill / all-over goods the design must reach every exterior surface (an unprinted placement is
raw white fabric — the SPAIN backpack white bands). The platform covers the full placement set
automatically when you use `ship_product` / `create_product` / `prepare-print-data`: display faces
get the composed art, exterior structural panels get a matching solid, embroidery + interior/label
placements are excluded. The mockup preview carries the same placement set, so the render PROVES
the coverage — confirm no exterior face is blank before you ship.

---

## 12. Match the design's aspect ratio to the print area

Full-bleed and all-over goods want a design that FILLS the print area edge to edge. A square
design centered on a TALL print area (a phone case, a portrait poster) leaves bare substrate at
the top and bottom; a square design on a WIDE area (a landscape banner, a mug wrap) leaves it at
the sides. Get the shape right — two ways:

### Generate at the print area's aspect (Phase 1)

`POST /images/generate` takes a `size` that sets the output aspect ratio:

| `size` | Aspect | Products it fits |
|---|---|---|
| `1024x1024` | 1:1 (square) | Pillows (18×18 / 22×22), square wall art, luggage tags-ish squares |
| `1024x1792` | 9:16 (tall) | Phone cases, portrait posters, tall banners |
| `1792x1024` | 16:9 (wide) | Landscape doormats, mug wraparound strips, wide banners, landscape wall art |

When you already know the product, pick the matching `size` in Phase 1 so the design is born the
right shape. This is also how you keep resolution up on large-format goods (a tall or wide design
puts 1792px on the long side vs 1024px for a square) — see §11.

Note: this is the print-area SHAPE, not exact pixels. The final print file still fills the full
`area_width` × `area_height` (§4); the platform composes it. Generating at the closest aspect
(tall/wide/square) minimizes stretch and cropping when it does.

### Reshape an existing design — `fit-aspect` (quota-free)

If a design already exists (a square one the user liked, or a gallery image) but its shape is
wrong for the product, reshape it WITHOUT spending an image generation:

```
POST /agents/v1/images/generated/<uuid>/fit-aspect
{ "aspect": "9:16", "mode": "pad", "background": "#RRGGBB" }
```

- **`mode: "pad"`** letterboxes the whole design onto the target ratio (keeps everything). For an
  all-over / full-bleed good, set **`background`** to the design's OWN background color so the added
  margin blends in and the product still reads edge-to-edge (a transparent pad would show white
  substrate at the margins on a fill good — not what you want here).
- **`mode: "crop"`** center-crops to the ratio (trims the outer edges). Use when the design's
  content is centered and losing the margins is fine.
- Returns a NEW gallery image; the source is untouched.

`fit-aspect` is metered as `storage`, NOT an image generation, so reshaping an existing design is
free of the generation quota — prefer it over regenerating when only the shape is wrong. Full
contract + the pad-vs-crop trade-off is in `references/design-rules.md` §5c.

```bash
# Reshape a square all-over design to a wide 16:9 for a landscape doormat,
# padding the margin with the design's own dark-brown background.
curl -sS -X POST "https://api.apparelhub.ai/agents/v1/images/generated/<uuid>/fit-aspect" \
  -H "x-api-key: $APPARELHUB_API_KEY" -H "Content-Type: application/json" -d '{
  "aspect": "16:9",
  "mode": "pad",
  "background": "#3B2A20"
}'
```

`fit-aspect` reshapes; it does not paint new content into the margin. If you need the design's
scene to actually extend into the new aspect, regenerate at the matching `size` (which consumes a
generation), not `fit-aspect`.
