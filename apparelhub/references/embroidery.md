# Embroidery — Printful Embroidered Apparel

Embroidered apparel (Champion Anorak, polos, embroidered hats, jackets) has hard constraints that DO NOT exist for standard printing. Skip this guide and your sync call hard-400s from Printful with an opaque error message. Read this BEFORE constructing any embroidery sync payload.

---

## 1. The core constraint: design colors MUST be a subset of Printful's 15-color thread palette

Embroidery is STITCHED, not printed. Every color in your design maps to ONE thread color from Printful's fixed palette. Any value outside this list rejects the entire sync call.

### The full 15-color palette (memorize for embroidery work)

| Hex | Common name |
|---|---|
| `#FFFFFF` | White |
| `#000000` | Black |
| `#96A1A8` | Gray |
| `#A67843` | Bronze gold |
| `#FFCC00` | Bright yellow / gold |
| `#E25C27` | Orange |
| `#CC3366` | Pink |
| `#CC3333` | Red |
| `#660000` | Dark red / burgundy |
| `#333366` | Navy |
| `#005397` | Royal blue |
| `#3399FF` | Light blue |
| `#6B5294` | Purple |
| `#01784E` | Forest green |
| `#7BA35A` | Sage green |

Build the design so its dominant colors are already palette-aligned. For a forest-green-and-gold crest, prompt for "forest green outline, bright yellow gold fills, bronze gold shading" — maps cleanly to `#01784E` / `#FFCC00` / `#A67843`.

---

## 2. Cap at ~5 thread colors per design

Each additional color increases stitch density and per-unit cost. **2-3 colors is the sweet spot** for a chest crest. A monogram is often just 1 color.

---

## 3. Text must be ≥0.25" tall

For a typical `embroidery_chest_left` placement (~3.5" wide), letters must be at least ~7-8% of the placement width. Thinner strokes blob into illegible stitches. If the user wants smaller text, talk them out of it — embroidered text smaller than 0.25" is unreadable.

---

## 4. "Transparent background" IS correct for embroidery

Same as t-shirts. Where the PNG is transparent, no thread is stitched, and the bare garment fabric shows through. The flood-fill + pre-multiply-white workflow from the standard pipeline (Phase 2) applies.

---

## 5. ⚠️ The placement-of-options trap

This is the gotcha that produces hours of opaque-error bisection if you don't know it upfront.

**`options` MUST sit at the `sync_variants[i]` level, NOT on the file inside `files[]`.**

### What DOES NOT work

File-level options with `id="thread_colors"` → Printful 400s with `thread_colors_chest_left option is missing or incorrect`.

File-level options with the fully-qualified `id="thread_colors_chest_left"` → same 400.

Both shapes feel canonical ("the option logically belongs to the file's placement"). Printful rejects both with the IDENTICAL error message, so you can't distinguish "wrong level" from "missing" without trying both.

### What DOES work (verified end-to-end)

```json
{
  "sync_product": {
    "name": "Paul Oliver Quarter-Zip Anorak",
    "thumbnail": "https://...mockup.png",
    "files": [{ "type": "mockup", "url": "https://...mockup.png" }]
  },
  "sync_variants": [
    {
      "variant_id": 11008,
      "retail_price": "89.99",
      "files": [
        {
          "type": "embroidery_chest_left",
          "url": "https://...transparent-design.png"
        }
      ],
      "options": [
        {
          "id": "thread_colors_chest_left",
          "value": ["#01784E", "#FFCC00", "#A67843"]
        }
      ]
    }
  ]
}
```

### Notes on the exact shape

- **Level**: `options` is a sibling of `files` INSIDE each `sync_variants[i]`. NOT on the file. NOT at the `sync_product` level.
- **`id`**: placement-suffixed (`thread_colors_chest_left`, `thread_colors_chest_right`, `thread_colors_sleeve_left`, `thread_colors_chest_center`, `thread_colors_sleeve_right`, `thread_colors_large_center`). Mirrors the `embroidery_<placement>` file type.
- **`value`**: JSON array of hex strings WITH the `#` prefix. Uppercase hex. Values must be a subset of the 15-color palette; one rejected value = whole call rejected.
- **All variants get the same options** when all variants share the same design.

---

## 6. Multiple placements on one product

Each placement gets its OWN file entry AND its OWN option entry. Option IDs differ by suffix so they don't collide when hoisted to the variant level.

Example: a polo with chest crest + sleeve logo = 2 files + 2 options:
```json
{
  "files": [
    { "type": "embroidery_chest_left", "url": "..." },
    { "type": "embroidery_sleeve_left", "url": "..." }
  ],
  "options": [
    { "id": "thread_colors_chest_left", "value": ["#01784E", "#FFCC00"] },
    { "id": "thread_colors_sleeve_left", "value": ["#FFFFFF"] }
  ]
}
```

---

## 7. The `embroidery_type` option (some catalog items)

Some products have an `embroidery_type` option with values:
- `"flat"` — standard embroidery (default)
- `"3d"` — foam-backed raised lettering (premium feel, costs more, harder to do well)
- `"both"` — combination

**Default to `"flat"`** unless the design explicitly calls for raised lettering (varsity-jacket style, athletic uniform). 3D embroidery on small/thin elements (under 0.5" tall, thin strokes) prints poorly.

---

## 8. Picking thread colors empirically — don't guess

For a finished design, sample the dominant colors then map each to the nearest palette entry:

```python
from PIL import Image
from collections import Counter
img = Image.open(design_path).convert('RGBA')
pixels = [p[:3] for p in img.getdata() if p[3] > 200]
buckets = Counter((p[0]//24*24, p[1]//24*24, p[2]//24*24) for p in pixels)
# Top buckets covering >2% of opaque pixels → match each to nearest palette entry
```

**Use CIE Lab distance, NOT Euclidean RGB.** Raw RGB mis-categorizes a bronze gold (`#A86000`) as `#E25C27` (orange) when the perceptually-closest palette entry is `#A67843`. For hand picks: eyeball the bucket against the palette and pick the one a human would call the same color name.

---

## 9. Always vision-verify BEFORE syncing

Some designs that look fine as PNG stitch badly:
- Small text under 0.25"
- Any gradient effect (no thread can do gradients)
- Anti-aliased edges with intermediate colors not in the palette
- Multi-tone shading requiring colors we don't have
- Photorealism (impossible in embroidery)

If the design has any of these features, regenerate as a simpler flat-color design before attempting the sync.

---

## 10. Champion Packable Anorak reference (Printful product 399)

This is our first-shipped embroidery product. Use it as a known-working reference.

| Field | Value |
|---|---|
| Printful product ID | 399 |
| Placement provider_ref_id | `embroidery_chest_left` |
| Print area | 541 × 541 px |
| Cost (S–XL) | $42.57 |
| Cost (2XL) | $44.57 |
| Recommended retail | $89.99 |

### Black variant IDs

| Size | ID |
|---|---|
| S | 11008 |
| M | 11009 |
| L | 11010 |
| XL | 11011 |
| 2XL | 11012 |

### Complete sync payload (working reference)

See `examples/embroidered-anorak.md` for the full end-to-end walkthrough including design generation, transparency processing, mockup, product create, and the variant-level options shape.
