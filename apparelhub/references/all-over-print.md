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
- For doormats: text reads left-to-right when product is oriented normally
- For luggage tags: no faux strap hole visible in the design, no faux tag-frame visible inside the print area
- For pillows: front and back surfaces both look intentional (back can be solid color or complementary graphic — both fine, just not blank)
