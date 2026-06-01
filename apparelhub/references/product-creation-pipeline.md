# Product Creation Pipeline — Full Detail

The 7-phase workflow from "user wants a saguaro tee" to "product is live on their Shopify store." Execute the phases IN ORDER. Skipping or reordering a phase produces broken products that look successful but silently fail downstream.

---

## Phase 1 — Generate the design image

```bash
curl -sS -X POST "https://api.apparelhub.ai/agents/v1/images/generate" \
  -H "x-api-key: $APPARELHUB_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "vector flat illustration saguaro cactus silhouette desert sunset, on solid bright green background #00FF00",
    "source": "Nano Banana",
    "size": "1024x1024"
  }'
```

Returns `{ "generated_image": { "uuid": "...", "url": "..." } }`. Save the UUID.

**Before running Phase 1, READ `references/design-rules.md`.** It covers:
- AI prompt anti-patterns (e.g., never say "luggage tag" in the prompt for a luggage tag design)
- Why we prompt for solid bright green `#00FF00` instead of "transparent background"
- Vision-verification of any text in the design
- Which AI source to use for which kind of design (table)

**After Phase 1 — decide whether Phase 2 is required:**

| Garment type | Transparency required? |
|---|---|
| Standard front-print apparel (tees, hoodies, sweatshirts, tanks) | **YES** — go to Phase 2 |
| Embroidered apparel (Champion Anorak, polos, embroidered hats) | **YES** — same flood-fill, but see `references/embroidery.md` |
| All-over-print products (pillows, doormats, area rugs, beach towels, AOP tees, luggage tags, mugs, phone cases) | **NO** — print edge-to-edge including background color. SKIP Phase 2 and use the raw generated image. See `references/all-over-print.md`. |
| User explicitly opts out (vintage look, full-bleed graphic, distressed) | **NO** — break-glass override |

**Break-glass override phrases** (respect user intent — don't strip background):
- "Keep the background"
- "Don't remove the background"
- "I want the [color] background"
- "Make it a vintage [solid color] design"
- "Full-bleed design"
- "Print it as-is"

**Ambiguous case** (user didn't specify): default to TRANSPARENT (safe for 95% of merchant intent), BUT report it:
> "I removed the green background so it sits cleanly on the shirt. If you wanted a solid-color background design, let me know and I'll regenerate."

Don't silently make this call.

---

## Phase 2 — LOCAL transparency processing

**This phase is COMPUTE work on your machine, NOT an API call.** The platform's `/transform` endpoint just stores whatever bytes you upload — it does NOT do flood-fill. You do it locally before uploading.

### Step 2a: Local processing with Pillow

```python
from PIL import Image
import requests
from io import BytesIO

# Download the generated image (has solid green #00FF00 background)
img = Image.open(BytesIO(requests.get(image_url).content)).convert('RGBA')
w, h = img.size

# Flood-fill the green background
# Tolerance accommodates anti-aliased edges
target = (0, 255, 0)
tolerance = 60

def color_match(p, t, tol):
    return all(abs(p[i] - t[i]) < tol for i in range(3))

# Build new pixel data — transparent where it matches background, opaque otherwise
new_data = []
for r, g, b, a in img.getdata():
    if color_match((r, g, b), target, tolerance):
        # Pre-multiplied white: when Printful flattens, it composites against white not black
        new_data.append((255, 255, 255, 0))
    else:
        new_data.append((r, g, b, a))
img.putdata(new_data)

img.save('/tmp/design_transparent.png', 'PNG')
```

### Step 2b: Upload the processed bytes via the transform endpoint

(Which is just an upload — NOT a transformation):

```bash
curl -sS -X POST "https://api.apparelhub.ai/agents/v1/images/generated/<original_image_uuid>/transform" \
  -H "x-api-key: $APPARELHUB_API_KEY" \
  -F "image=@/tmp/design_transparent.png"
```

Returns a NEW image UUID + URL with true RGBA transparency. **Use the NEW UUID for Phase 3 onwards.**

### Phase 2 failure modes worth recognizing

- **Letter loops not transparent.** The inside of B, e, d, M, a, etc. The flood-fill above only reaches connected exterior regions. For text designs, do a second pass: any pixel still matching the background color anywhere in the image becomes transparent too.
- **White halos around edges.** Caused by skipping pre-multiplication. The `(255, 255, 255, 0)` in the snippet prevents this.
- **Faint green ring around the silhouette.** Tolerance too low for anti-aliased edges. Raise `tolerance` from 60 → 80-90.
- **Checkerboard pattern visible on the mockup.** The AI baked a fake checkerboard into RGB pixels instead of producing transparency. Re-do Phase 2 with the right target color (often the AI used a SLIGHTLY different green than `#00FF00` — sample the actual color from a corner pixel).

---

## Phase 3 — Generate the mockup

You need a `provider_uuid` (Printful or Printify) and a `product_ref_id` (the garment type, e.g. `71` for Bella+Canvas 3001 unisex tee).

### ⚠️ FIELD-NAME FLIP between this endpoint and product create

This is the single most common cause of "product was created but doesn't sync" issues. The fields are essentially the same data but have **DIFFERENT names** between the preview endpoint and the create endpoint:

| Phase 3 (preview) | Phase 5 (create) |
|---|---|
| `merchandise_provider_uuid` | `provider_uuid` |
| `provider_product_ref_id` | `product_ref_id` |
| n/a | `price` (NOT `retail_price`) |

Don't copy the names from one phase to the other. Same data, flipped names.

### Step 3a: Browse the catalog if you don't know the `product_ref_id`

```bash
curl -sS "https://api.apparelhub.ai/agents/v1/merchandise/<provider_uuid>/products?fields=provider_ref_id,name,brand" \
  -H "x-api-key: $APPARELHUB_API_KEY"
```

### Step 3b: FETCH the garment's print templates

This gives you `area_width`, `area_height`, and the valid `provider_ref_id` for each print placement. **DO NOT hardcode these dimensions.** They vary per garment.

```bash
curl -sS "https://api.apparelhub.ai/agents/v1/merchandise/<provider_uuid>/product/<product_ref_id>" \
  -H "x-api-key: $APPARELHUB_API_KEY"
```

The response includes `print_templates` (or similar) with each placement's dimensions and `provider_ref_id` (e.g., `"front"`, `"back"`, `"embroidery_chest_left"`, `"default"`).

### Step 3c: CALCULATE design positioning within the print area

For a CHEST-FILLING front print (standard tee):
- `width` = 80-90% of `area_width` (substantial, not a small chest emblem)
- `height` = scale proportionally to maintain design aspect ratio
- `left` = `(area_width - width) / 2` (center horizontally)
- `top` = small positive (10-30) OR 0 to top-align within the print area

Example for Bella+Canvas 3001 front (typical `area_width: 728, area_height: 376`):
- `width: 600` (82% of 728 — chest-filling)
- `height: 600` (square design; OK if it overshoots area_height since it's anchored at top)
- `left: 64` ((728 - 600) / 2)
- `top: 0`

For a small CHEST EMBLEM (logo-style): `width = 200-280` is appropriate.
For a center-back print: same math, use the back placement's area dimensions.
For all-over print: `width = area_width`, `height = area_height`, `top = 0`, `left = 0`. See `references/all-over-print.md`.
For embroidery: tight placement on the chest-left or similar. See `references/embroidery.md` for the 541×541 anorak example.

### Step 3d: Create the preview with the COMPLETE template structure

```bash
curl -sS -X POST "https://api.apparelhub.ai/agents/v1/merchandise/product/preview" \
  -H "x-api-key: $APPARELHUB_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "merchandise_provider_uuid": "<provider_uuid>",
    "generated_image_uuid": "<image_uuid>",
    "provider_product_ref_id": "71",
    "templates": [
      {
        "provider_ref_id": "front",
        "image_url": "<image_url>",
        "area_width": 728,
        "area_height": 376,
        "width": 600,
        "height": 600,
        "top": 0,
        "left": 64
      }
    ],
    "variant_ids": [4016, 4017, 4018, 4019, 4020, 8495, 8496, 8497, 8498, 8499, 4012, 4013, 4014, 4015, 4011]
  }'
```

Notes:
- Include ALL variant_ids across ALL colors in ONE preview call (15 IDs for 3 colors × 5 sizes here). The provider returns separate mockups per color in the same job.
- Missing any template field → 404 with `KeyError` or generic Exception from `merchandise.py`. Common cause of "Error building the standard response for product preview." Always pass the full template object.

Returns a `job_uuid`. Mockup generation is **async** — poll until complete:

```bash
curl -sS "https://api.apparelhub.ai/agents/v1/merchandise/product/preview/<provider_uuid>/job/<job_uuid>" \
  -H "x-api-key: $APPARELHUB_API_KEY"
```

---

## Phase 3.5 — Mockup verification (MANDATORY)

When the job status is `completed`, **DO NOT immediately proceed to product creation.** The pipeline has TWO completion phases:

1. Job status = `completed` means the provider's render job finished, BUT
2. The `preview_url` on each preview row may still be NULL — that's our S3 ingestion catching up. Can take 20+ minutes.

**Poll until at least one preview has a non-null `preview_url`:**

```bash
curl -sS "https://api.apparelhub.ai/agents/v1/merchandise/product/preview-job/<job_uuid>/previews" \
  -H "x-api-key: $APPARELHUB_API_KEY"
```

Once `preview_url` is populated, **visually inspect the mockup**. Download with curl and view, or hand to vision tools. Check for:

- Design renders correctly (not cut off, not distorted)
- Text is legible and spelled correctly
- No white halos around transparent edges
- No checkerboard artifacts where transparency should be
- Color contrast is acceptable on the chosen garment

If anything looks wrong, FIX the design and re-mockup before continuing. Never ship a broken mockup to product creation — manufacturing follows the mockup.

---

## Phase 4.0 — Pick `display_image` + build `gallery_images` from preview rows

Before calling product create, query the preview job's preview rows to pick the BEST mockup for the product thumbnail (`display_image`) AND build a curated gallery (`gallery_images`). The platform picks sensible defaults if you skip this; explicit selection gives the merchant a better product page out of the gate.

```bash
PREVIEWS=$(curl -sS "https://api.apparelhub.ai/agents/v1/merchandise/product/preview-job/<job_uuid>/previews" \
  -H "x-api-key: $APPARELHUB_API_KEY")
```

Each preview row has:
- `uuid` — apparelhub's S3-stored copy ID
- `preview_url` — apparelhub's S3 URL (may be NULL during the ingestion race; see Phase 3.5)
- `provider_preview_ref_url` — the provider's CDN URL; filename contains color + angle (e.g., `unisex-staple-t-shirt-black-front-abc123.png`)
- `thumbnail_url` — 500×500 thumb

### Pick `display_image`

1. Prefer FRONT-view (provider_preview_ref_url contains `-front-` in filename)
2. Among front-views, prefer DARK shirts (black, navy, charcoal, midnight) — best contrast for showing the design
3. Prefer rows with non-null `preview_url` (our S3 mirror) over those with only `provider_preview_ref_url`
4. Use that row's `preview_url` (or fall back to `provider_preview_ref_url`) as `display_image`

### Build `gallery_images`

1. Group previews by color (parse from `provider_preview_ref_url` filename)
2. For each color, take ONE front-view; add to gallery
3. Order: darkest color FIRST (matches the `display_image` choice), then remaining colors
4. Then append back-views of each color
5. Cap at ~10 images

---

## Phase 4 — Create the product

This phase has FOUR FIELD-NAME GOTCHAS that silently break products. Memorize — these are DIFFERENT from the preview endpoint's names:

| ❌ Wrong (intuitive or copy-pasted from Phase 3) | ✅ Correct (product create) |
|---|---|
| `merchandise_provider_uuid` | `provider_uuid` |
| `provider_product_ref_id` | `product_ref_id` |
| `retail_price` | `price` |

Wrong field names create the product "successfully" but with NULL `manufacturing_metadata`, and sync silently fails downstream. The API does not reject the mistake.

```bash
curl -sS -X POST "https://api.apparelhub.ai/agents/v1/product/create" \
  -H "x-api-key: $APPARELHUB_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Saguaro Desert Sunset Tee",
    "description": "Hand-illustrated saguaro silhouette against a warm desert sunset.",
    "generated_image_uuid": "<image_uuid>",
    "preview_job_uuid": "<job_uuid>",
    "provider_uuid": "<provider_uuid>",
    "product_ref_id": "71",
    "price": 27.99,
    "display_image": "<chosen_dark_color_front_preview_url>",
    "gallery_images": [
      "<black_front_url>",
      "<navy_front_url>",
      "<white_front_url>",
      "<black_back_url>",
      "<navy_back_url>"
    ],
    "print_data": [
      {
        "provider_ref_id": "front",
        "image_url": "<original_image_url>",
        "area_width": 728,
        "area_height": 376,
        "width": 600,
        "height": 600,
        "top": 0,
        "left": 64
      }
    ]
  }'
```

### `print_data` vs `display_image` — what each is for

- **`print_data[].image_url` is the RAW DESIGN URL** (the transparent image from Phase 2). This is what Printful uses to actually PRINT. It is NOT a mockup. Never put a mockup URL in `print_data` — that ships shirt-on-a-shirt.

- **`display_image` and `gallery_images` are MOCKUP URLs** (from the preview job). These are what customers see on the product page. Never put the raw design URL here — that shows the design on a green background instead of on a shirt.

If you OMIT `display_image` and `gallery_images`, the platform picks them automatically using the same logic in Phase 4.0. Explicit is preferred when you want a specific dark-color thumbnail.

Returns the new product `uuid`.

---

## Phase 5 — Add variants

Variants are created ONE AT A TIME (no batch endpoint). The product is unsyncable until variants exist.

```bash
for vid in 4016 4017 4018 4019 4020; do
  curl -sS -X POST "https://api.apparelhub.ai/agents/v1/product/<product_uuid>/variants" \
    -H "x-api-key: $APPARELHUB_API_KEY" \
    -H "Content-Type: application/json" \
    -d "{
      \"name\": \"Black\",
      \"price\": 27.99,
      \"color\": \"Black\",
      \"size\": \"M\",
      \"provider_variant_id\": $vid
    }"
done
```

Look up the right variant IDs via:
```bash
curl -sS "https://api.apparelhub.ai/agents/v1/merchandise/<provider_uuid>/product/71" \
  -H "x-api-key: $APPARELHUB_API_KEY"
```

Or use the quick-reference variant tables in `references/garment-catalog.md`.

---

## Phase 6 — Associate the product with the user's store

```bash
# List stores first
curl -sS "https://api.apparelhub.ai/agents/v1/store" \
  -H "x-api-key: $APPARELHUB_API_KEY"

# Then add the product
curl -sS -X POST "https://api.apparelhub.ai/agents/v1/store/<store_uuid>/products" \
  -H "x-api-key: $APPARELHUB_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"product_uuids": ["<product_uuid>"]}'
```

---

## Phase 7 — Sync to fulfillment AND sales channels

Sync targets are different depending on what you're syncing to.

### Fulfillment (Printful/Printify) — REQUIRED FIRST

```bash
curl -sS -X POST "https://api.apparelhub.ai/agents/v1/store/<store_uuid>/products/<product_uuid>/sync?target=merchandise" \
  -H "x-api-key: $APPARELHUB_API_KEY"
```

This creates the product on the fulfillment provider's side. MUST succeed before ecommerce sync — Shopify/Etsy/etc. need the fulfillment SKU to attach.

### Ecommerce (Shopify, Etsy, WooCommerce, Wix)

```bash
curl -sS -X POST "https://api.apparelhub.ai/agents/v1/store/<store_uuid>/products/<product_uuid>/sync?target=ecommerce&integration_uuid=<integration_uuid>" \
  -H "x-api-key: $APPARELHUB_API_KEY"
```

Sync to multiple channels by calling this once per integration UUID.

### Default to DRAFT, not live

For channels that support a draft state (Etsy, Shopify), prefer pushing as a draft first. Tell the merchant:
> "I've synced as drafts so you can review on your storefront before going live. To publish, flip the listing in your channel admin or re-run sync with `?listing_state=active`."

Only push as `active` if the user EXPLICITLY says "make it live" or "publish it." The cost of a too-eager publish (typo'd description in front of real customers) is much higher than the cost of one extra step.

Done — the product is now synced to the user's storefront in draft form.
