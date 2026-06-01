# Example — Embroidered Champion Anorak End-to-End

A complete walkthrough for the Champion Packable Anorak (Printful product 399) with an `embroidery_chest_left` placement. Same workflow applies to other embroidered apparel — polos, embroidered hats, jackets — adjust `product_ref_id`, variant IDs, and placement provider_ref_id.

**Read `references/embroidery.md` first.** The thread palette and the `thread_colors_<placement>` options trap will absolutely ruin your day if you skip them.

**Invocation convention used throughout this file:**
- All Agent API calls go through `ah_curl` (see `SKILL.md` section 1). Invoke via the full install path `~/.claude/skills/apparelhub/scripts/ah_curl` or as bare `ah_curl` if the scripts dir is on PATH.
- Placeholders like `<image_uuid>`, `<job_uuid>`, `<product_uuid>` — substitute the LITERAL value from the previous step's response. **No shell variables.**

---

## Setup

```bash
export APPARELHUB_API_KEY=ah_...   # one-time
```

Printful prod provider UUID: `c8dff2fa-1a43-4734-93f0-e2ddd03eae53`
Champion Packable Anorak product_ref_id: `399`

---

## Phase 1 — Generate the design (palette-aligned from the start)

The design's dominant colors should be subsets of Printful's 15-color thread palette. Prompt for colors you KNOW map to thread:

- Forest green outline / fills → `#01784E`
- Bright yellow / gold accents → `#FFCC00`
- Bronze gold shading → `#A67843`
- Stick to 2-3 colors total for a chest crest

```bash
ah_curl POST /agents/v1/images/generate -d '{
  "prompt": "flat heraldic crest emblem, bold forest green outline, bright yellow gold fills, simple geometric shapes, no fine detail, designed for embroidery stitching, on solid bright green #00FF00 background",
  "source": "Nano Banana",
  "size": "1024x1024"
}'
```

Capture the `uuid` and `url` from the response.

**Vision-verify before proceeding:**
- Are colors flat (no gradients)?
- Is text (if any) at least 0.25" equivalent? For a 541×541 placement, that's ~38px tall minimum.
- Are there any photorealistic details that won't translate to embroidery? If yes, regenerate.

---

## Phase 2 — Local transparency processing (same as standard apparel)

```bash
# Download the green-background image to /tmp. Substitute the literal URL.
curl -sS "https://apparelhub-production-user-generated-public-objects.s3.amazonaws.com/..." -o /tmp/crest_green.png

# Strip the green background via the packaged script.
python3 ~/.claude/skills/apparelhub/scripts/make_transparent.py \
    /tmp/crest_green.png /tmp/crest_transparent.png \
    --preview /tmp/crest_preview.jpg
```

Inspect `/tmp/crest_preview.jpg` to confirm clean transparency. Then upload:

```bash
# Substitute the literal original image UUID from Phase 1.
ah_curl POST /agents/v1/images/generated/<image_uuid>/transform \
    -F image=@/tmp/crest_transparent.png
```

Capture the NEW transparent-image UUID + URL from the response. Use it for Phase 3 onwards.

---

## Phase 2.5 — Empirically pick thread colors from the design

Don't guess. Sample the dominant colors and map each to the nearest palette entry.

```bash
# Save as /tmp/pick_threads.py and run with `python3 /tmp/pick_threads.py`
python3 /tmp/pick_threads.py
```

Where `/tmp/pick_threads.py` is:
```python
from PIL import Image
from collections import Counter

img = Image.open('/tmp/crest_transparent.png').convert('RGBA')
pixels = [p[:3] for p in img.getdata() if p[3] > 200]  # opaque pixels only
buckets = Counter((p[0]//24*24, p[1]//24*24, p[2]//24*24) for p in pixels)
total = sum(buckets.values())

# Surface buckets covering >2% of opaque pixels
print("Dominant color buckets:")
for color, count in buckets.most_common(10):
    pct = count / total * 100
    if pct >= 2:
        print(f"  RGB({color[0]:3d},{color[1]:3d},{color[2]:3d}) - {pct:.1f}%")
```

**Map each bucket to the nearest palette entry by eye** (or by CIE Lab distance if you want to be rigorous — never by raw RGB Euclidean, which mis-categorizes browns and golds).

Printful's 15 thread colors:
```
#FFFFFF #000000 #96A1A8 #A67843 #FFCC00 #E25C27 #CC3366
#CC3333 #660000 #333366 #005397 #3399FF #6B5294 #01784E #7BA35A
```

For our forest-green-and-gold crest, expected mapping:
- Dominant green → `#01784E` (forest green)
- Gold fills → `#FFCC00` (bright yellow / gold)
- Maybe bronze shading → `#A67843`

**Stop at 2-3 thread colors.** Even if more buckets show up, picking 4+ raises cost and stitch complexity without proportionate visual gain.

---

## Phase 3 — Generate the mockup

```bash
ah_curl POST /agents/v1/merchandise/product/preview -d '{
  "merchandise_provider_uuid": "c8dff2fa-1a43-4734-93f0-e2ddd03eae53",
  "generated_image_uuid": "<transparent_image_uuid>",
  "provider_product_ref_id": "399",
  "templates": [
    {
      "provider_ref_id": "embroidery_chest_left",
      "image_url": "<transparent_image_url>",
      "area_width": 541,
      "area_height": 541,
      "width": 541,
      "height": 541,
      "top": 0,
      "left": 0
    }
  ],
  "variant_ids": [11008, 11009, 11010, 11011, 11012]
}'
```

Capture `job_uuid`.

---

## Phase 3.5 — Poll + verify

```bash
# Poll job status every 5s until status: completed. Substitute literal job UUID.
ah_curl GET /agents/v1/merchandise/product/preview/c8dff2fa-1a43-4734-93f0-e2ddd03eae53/job/<job_uuid>

# Then poll for S3 ingestion every 8s until at least one preview_url != null.
ah_curl GET /agents/v1/merchandise/product/preview-job/<job_uuid>/previews
```

Pick a front-view mockup URL. Visually verify:
- Crest sits on the chest-left correctly (not too high, not too low)
- Colors render as expected on the dark anorak
- Design isn't TOO small to read at a normal viewing distance

---

## Phase 4 — Create the product

Embroidery cost is higher than standard print. Recommended retail $89.99 on the Champion Anorak.

```bash
ah_curl POST /agents/v1/product/create -d '{
  "name": "Heraldic Crest Embroidered Anorak",
  "description": "Classic heraldic crest embroidered on a Champion Packable Anorak. Lightweight, packable, perfect for transitional weather.",
  "generated_image_uuid": "<transparent_image_uuid>",
  "preview_job_uuid": "<job_uuid>",
  "provider_uuid": "c8dff2fa-1a43-4734-93f0-e2ddd03eae53",
  "product_ref_id": "399",
  "price": 89.99,
  "display_image": "<mockup_url>",
  "print_data": [
    {
      "provider_ref_id": "embroidery_chest_left",
      "image_url": "<transparent_image_url>",
      "area_width": 541,
      "area_height": 541,
      "width": 541,
      "height": 541,
      "top": 0,
      "left": 0,
      "options": [
        {
          "id": "thread_colors_chest_left",
          "value": ["#01784E", "#FFCC00", "#A67843"]
        }
      ]
    }
  ]
}'
```

### ⚠️ The `options` field on `print_data`

When ApparelHub builds the Printful sync payload internally, it HOISTS the `options` you pass here up to the `sync_variants[i].options` level (where Printful actually expects them — see `references/embroidery.md` section 5).

Pass `options` on the `print_data[i]` dict at create time. The platform handles the hoisting. Do NOT try to put options at a different level — the field-name flips are documented and this is the canonical shape for the create endpoint.

Capture the product UUID.

---

## Phase 5 — Add variants (5 black sizes)

Substitute the literal product UUID. 2XL costs $2 more — price adjusted.

```bash
ah_curl POST /agents/v1/product/<product_uuid>/variants -d '{"name":"Black","price":89.99,"color":"Black","size":"S","provider_variant_id":11008}'
ah_curl POST /agents/v1/product/<product_uuid>/variants -d '{"name":"Black","price":89.99,"color":"Black","size":"M","provider_variant_id":11009}'
ah_curl POST /agents/v1/product/<product_uuid>/variants -d '{"name":"Black","price":89.99,"color":"Black","size":"L","provider_variant_id":11010}'
ah_curl POST /agents/v1/product/<product_uuid>/variants -d '{"name":"Black","price":89.99,"color":"Black","size":"XL","provider_variant_id":11011}'
ah_curl POST /agents/v1/product/<product_uuid>/variants -d '{"name":"Black","price":91.99,"color":"Black","size":"2XL","provider_variant_id":11012}'
```

---

## Phase 6 + 7 — Store + sync

Same as standard apparel. The embroidery options propagate through fulfillment sync automatically — no extra parameters needed at the sync call.

```bash
ah_curl GET /agents/v1/store
# Capture store UUID.

ah_curl POST /agents/v1/store/<store_uuid>/products -d '{"product_uuids": ["<product_uuid>"]}'

# Fulfillment first.
ah_curl POST /agents/v1/store/<store_uuid>/products/<product_uuid>/sync?target=merchandise
# If this 400s with "thread_colors_chest_left option is missing or incorrect",
# the options probably aren't at the right level. See references/embroidery.md.

# Find Shopify integration.
ah_curl GET /agents/v1/store/<store_uuid>
# Pull integration_uuid from ecommerce_statuses[].

# Sales channel sync, as DRAFT.
ah_curl POST /agents/v1/store/<store_uuid>/products/<product_uuid>/sync?target=ecommerce&integration_uuid=<integration_uuid>
```

---

## Adapting for multiple embroidery placements

For a product with BOTH a chest crest AND a sleeve logo:

```json
"print_data": [
  {
    "provider_ref_id": "embroidery_chest_left",
    "image_url": "<chest_design_url>",
    "area_width": 541, "area_height": 541, "width": 541, "height": 541, "top": 0, "left": 0,
    "options": [
      { "id": "thread_colors_chest_left", "value": ["#01784E", "#FFCC00"] }
    ]
  },
  {
    "provider_ref_id": "embroidery_sleeve_left",
    "image_url": "<sleeve_design_url>",
    "area_width": <sleeve_area_w>, "area_height": <sleeve_area_h>, "width": <...>, "height": <...>, "top": 0, "left": 0,
    "options": [
      { "id": "thread_colors_sleeve_left", "value": ["#FFFFFF"] }
    ]
  }
]
```

Each placement has its OWN file entry AND its OWN options entry. The platform hoists each options block to the corresponding variant-level entry; option IDs differ by suffix so they don't collide.

---

## Reporting back to the user

> "Heraldic Crest Anorak is live in 5 sizes (S–2XL).
>
> - Mockup: `<mockup_url>`
> - 3 embroidery thread colors: forest green, bright gold, bronze
> - Product manager: `https://apparelhub.ai/merchandise/my-products`
> - Synced to your Shopify as DRAFT — review and publish from your Shopify admin when ready.
>
> Note: embroidery is stitched, not printed. Cost is higher than standard print apparel — I priced this at $89.99 to keep healthy margin."
