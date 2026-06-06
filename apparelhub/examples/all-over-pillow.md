# Example — All-Over Print Pillow End-to-End

A complete walkthrough for an 18×18 square pillow with an edge-to-edge floral pattern. Same workflow applies to doormats, area rugs, and other all-over-print products — adjust dimensions and orientation per the product.

**Read `references/all-over-print.md` first.** Don't skip it.

**Invocation convention used throughout this file:**
- All Agent API calls are shown as plain `curl https://api.apparelhub.ai/agents/v1/...` invocations. Use any HTTP client equivalently — the canonical host is hard-pinned (see `../../SECURITY.md`).
- Placeholders like `<image_uuid>`, `<job_uuid>`, `<product_uuid>` — substitute the value the previous step returned.

---

## Setup

```bash
export APPARELHUB_API_KEY=ah_...   # one-time
```

Printful prod provider UUID: `c8dff2fa-1a43-4734-93f0-e2ddd03eae53`
Pillow product_ref_id: `214`

---

## Phase 1 — Generate the design (DO NOT mention "pillow" in the prompt)

The "don't name the product in the prompt" trap (see `references/all-over-print.md` section 5): saying "pillow design" produces an illustration OF a pillow, not a design FOR a pillow.

```bash
# WRONG: "decorative pillow with watercolor flowers"
# RIGHT: "flat watercolor wildflower pattern, edge-to-edge teal background, all-over textile graphic"

curl -sS -X POST "https://api.apparelhub.ai/agents/v1/images/generate" -H "x-api-key: $APPARELHUB_API_KEY" -H "Content-Type: application/json" -d '{
  "prompt": "flat watercolor wildflower pattern, scattered daisies and small pink blooms, edge-to-edge teal #1E7B7B background, all-over textile graphic, repeating motif fills entire canvas including all four corners",
  "source": "Seedream 4.5",
  "size": "1024x1024"
}'
```

Capture the `uuid` and `url` from the response.

**CRITICAL — verify the background reaches all 4 corners:**

```bash
# Substitute the LITERAL url. Download to /tmp, then check corner pixels.
curl -sS "https://apparelhub-production-user-generated-public-objects.s3.amazonaws.com/..." -o /tmp/pillow_design.png

# Quick 4-corner pixel check via Python. Save as /tmp/check_corners.py and run:
python3 /tmp/check_corners.py
```

Where `/tmp/check_corners.py` is:
```python
from PIL import Image
img = Image.open('/tmp/pillow_design.png').convert('RGB')
w, h = img.size
for x, y in [(0,0), (w-1,0), (0,h-1), (w-1,h-1)]:
    print(f"  ({x},{y}): {img.getpixel((x, y))}")
# All 4 corners must be near-teal (R ~30, G ~123, B ~123). If any is white or
# significantly off-color, REGENERATE the design — don't try to fix it; it will
# print with white margins.
```

---

## Phase 2 — SKIP

All-over-print products use the raw image directly. No transparency processing. Move to Phase 3 with the ORIGINAL image UUID + URL from Phase 1.

---

## Phase 3 — Generate the mockup at FULL area dimensions

For an 18×18 pillow, area = 2717 × 2717 px. The template's `width` and `height` MUST equal `area_width` and `area_height`. NEVER shrink.

Verify the print template first:
```bash
curl -sS "https://api.apparelhub.ai/agents/v1/merchandise/c8dff2fa-1a43-4734-93f0-e2ddd03eae53/product/214" -H "x-api-key: $APPARELHUB_API_KEY"
# Expect: front placement with area_width=2717, area_height=2717 for 18×18
```

Create the preview. Substitute the LITERAL image UUID + URL from Phase 1:

```bash
curl -sS -X POST "https://api.apparelhub.ai/agents/v1/merchandise/product/preview" -H "x-api-key: $APPARELHUB_API_KEY" -H "Content-Type: application/json" -d '{
  "merchandise_provider_uuid": "c8dff2fa-1a43-4734-93f0-e2ddd03eae53",
  "generated_image_uuid": "<image_uuid>",
  "provider_product_ref_id": "214",
  "templates": [
    {
      "provider_ref_id": "front",
      "image_url": "<image_url>",
      "area_width": 2717,
      "area_height": 2717,
      "width": 2717,
      "height": 2717,
      "top": 0,
      "left": 0
    },
    {
      "provider_ref_id": "back",
      "image_url": "<image_url>",
      "area_width": 2717,
      "area_height": 2717,
      "width": 2717,
      "height": 2717,
      "top": 0,
      "left": 0
    }
  ],
  "variant_ids": [9515]
}'
```

For lumbar (20×12) or 22×22, swap the variant ID AND the area dimensions to match the catalog response.

---

## Phase 3.5 — Poll + verify

One call handles BOTH completion phases (provider render + S3 ingestion):

```bash
ah_poll_mockup c8dff2fa-1a43-4734-93f0-e2ddd03eae53 <job_uuid>
```

Writes the final response to `/tmp/preview_job.json`. Then extract a mockup URL for visual inspection:

```bash
ah_pick_provider_url /tmp/preview_job.json white front
# Pillows are typically classified as "white" in the provider slug regardless
# of the design color — the "color" refers to the unprinted pillow fabric.
# If that returns no match, run ah_classify_previews to see the actual slug.

curl -sS -o /tmp/mockup_check.png "https://.../<paste-url-from-above>"
```

Open `/tmp/mockup_check.png` and verify:
- Background reaches all four edges (no white margins on the mockup)
- Floral motifs aren't cut off at the pillow seams
- Front and back both look intentional

---

## Phase 4 — Create the product

Pricing for all-over pillows: ~$24 cost, recommended retail $44.99 for 18×18.

```bash
curl -sS -X POST "https://api.apparelhub.ai/agents/v1/product/create" -H "x-api-key: $APPARELHUB_API_KEY" -H "Content-Type: application/json" -d '{
  "name": "Teal Wildflower Throw Pillow",
  "description": "Hand-painted-style watercolor wildflower motif on a deep teal field. 18x18 polyester throw pillow with concealed zipper. Edge-to-edge print on both sides.",
  "generated_image_uuid": "<image_uuid>",
  "preview_job_uuid": "<job_uuid>",
  "provider_uuid": "c8dff2fa-1a43-4734-93f0-e2ddd03eae53",
  "product_ref_id": "214",
  "price": 44.99,
  "display_image": "<mockup_url>",
  "gallery_images": ["<mockup_url>"],
  "print_data": [
    {
      "provider_ref_id": "front",
      "image_url": "<image_url>",
      "area_width": 2717,
      "area_height": 2717,
      "width": 2717,
      "height": 2717,
      "top": 0,
      "left": 0
    },
    {
      "provider_ref_id": "back",
      "image_url": "<image_url>",
      "area_width": 2717,
      "area_height": 2717,
      "width": 2717,
      "height": 2717,
      "top": 0,
      "left": 0
    }
  ]
}'
```

Capture the product `uuid`.

---

## Phase 5 — Add variants

For all 3 sizes (substitute literal product UUID):

```bash
curl -sS -X POST "https://api.apparelhub.ai/agents/v1/product/<product_uuid>/variants" -H "x-api-key: $APPARELHUB_API_KEY" -H "Content-Type: application/json" -d '{"name":"18x18","price":44.99,"size":"18x18","color":"Teal","provider_variant_id":9515}'
curl -sS -X POST "https://api.apparelhub.ai/agents/v1/product/<product_uuid>/variants" -H "x-api-key: $APPARELHUB_API_KEY" -H "Content-Type: application/json" -d '{"name":"20x12 Lumbar","price":42.99,"size":"20x12 Lumbar","color":"Teal","provider_variant_id":7907}'
curl -sS -X POST "https://api.apparelhub.ai/agents/v1/product/<product_uuid>/variants" -H "x-api-key: $APPARELHUB_API_KEY" -H "Content-Type: application/json" -d '{"name":"22x22","price":54.99,"size":"22x22","color":"Teal","provider_variant_id":11077}'
```

---

## Phase 6 + 7 — Store + sync

Identical to the front-print-tee example. Add to store, sync fulfillment FIRST, then sync to sales channel as DRAFT.

```bash
curl -sS "https://api.apparelhub.ai/agents/v1/store" -H "x-api-key: $APPARELHUB_API_KEY"
# Capture store UUID.

curl -sS -X POST "https://api.apparelhub.ai/agents/v1/store/<store_uuid>/products" -H "x-api-key: $APPARELHUB_API_KEY" -H "Content-Type: application/json" -d '{"product_uuids": ["<product_uuid>"]}'

# Fulfillment first
curl -sS -X POST "https://api.apparelhub.ai/agents/v1/store/<store_uuid>/products/<product_uuid>/sync?target=merchandise" -H "x-api-key: $APPARELHUB_API_KEY"

# Find Shopify integration UUID
curl -sS "https://api.apparelhub.ai/agents/v1/store/<store_uuid>" -H "x-api-key: $APPARELHUB_API_KEY"
# Read ecommerce_statuses[] for the Shopify entry's integration_uuid.

# Sales channel sync, as DRAFT
curl -sS -X POST "https://api.apparelhub.ai/agents/v1/store/<store_uuid>/products/<product_uuid>/sync?target=ecommerce&integration_uuid=<integration_uuid>" -H "x-api-key: $APPARELHUB_API_KEY"
```

---

## Adapting for doormats and area rugs

Doormat product 924. Key differences from a pillow:

- **Doormats MUST be landscape** — variant IDs 23705 (36×24), 23706 (60×36), 23707 (72×48)
- Use a DARK background — people step on it. Light backgrounds show dirt.
- Print area is different per size. 36×24 = 1437 × 972 px.
- No back side — single `front` template only.
- Recommended retail: $34.99 (36×24), $49.99 (60×36), $69.99 (72×48)

Adjust the prompt to describe a horizontal layout: "flat landscape graphic, horizontal welcome text reading left-to-right, edge-to-edge dark brown background."

For luggage tags (product 938), see `references/all-over-print.md` section 6 — the rounded corners + real strap hole rules make it the trickiest of the all-over products.

---

## Reporting back to the user

> "Teal Wildflower Pillow is live in 3 sizes (18×18, 20×12 lumbar, 22×22).
>
> - Mockup: `<mockup_url>`
> - Product manager: `https://apparelhub.ai/merchandise/my-products`
> - Synced to your Shopify as DRAFT — review on your Shopify admin, then publish or re-run sync with `?listing_state=active`."
