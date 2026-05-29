---
name: apparelhub
description: Design custom apparel and sync print-on-demand products to merchant stores via the ApparelHub platform. Use whenever the user wants to create AI-generated apparel designs, generate mockups, build products, sync to Shopify/Etsy/WooCommerce/Wix, manage orders, or check fulfillment status.
tools: Bash, WebFetch, Read, Write
---

# ApparelHub Skill

ApparelHub is a print-on-demand design and orchestration platform. Use this skill when the user wants to:

- Design AI-generated apparel (tees, hoodies, water bottles, pillows, doormats, etc.)
- Generate product mockups on physical garments
- Create products and sync them to sales channels (Shopify, Etsy, WooCommerce, Wix)
- Manage orders and fulfillment via Printful / Printify
- Browse the catalog of garments available for printing

You interact with ApparelHub via its Agent API at `https://api.apparelhub.ai/agents/v1/`.

---

## 1. Authentication

Every API call requires the user's ApparelHub API key in the `x-api-key` header.

**Check for the key first:**
```bash
echo "${APPARELHUB_API_KEY:?APPARELHUB_API_KEY not set}"
```

**If missing, tell the user:**
> You need an ApparelHub API key. Generate one at https://apparelhub.ai/developer/api-keys (requires Professional or Enterprise tier). Then run: `export APPARELHUB_API_KEY=ah_xxx...`

**Use it in every call:**
```bash
curl -sS "https://api.apparelhub.ai/agents/v1/store" \
  -H "x-api-key: $APPARELHUB_API_KEY"
```

---

## 2. Live API spec

Before constructing complex calls, fetch the canonical OpenAPI spec so field names are always current:

```bash
curl -sS https://api.apparelhub.ai/openapi-agent.json | head -200
```

The spec evolves; this skill captures the stable workflow logic and the most common endpoints, but field-level details may have shifted. When in doubt, the spec wins.

---

## 3. The Product Creation Pipeline

This is THE core workflow. Going from "user wants a saguaro tee" to "product is live on their Shopify store" takes 7 phases. Execute them IN ORDER.

### Phase 1 — Generate the design image

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

**Source selection — pick the right model:**
| Type of design | Recommended source |
|---|---|
| Photorealistic, exact prompt matching | `Nano Banana` or `Seedream 4.5` |
| Design with text (slogans, brand names) | `Nano Banana` (best text accuracy) → `Seedream 4.0` (second) |
| Abstract / geometric / shapes / colors | `OpenAI` |
| Lifestyle / nature / animals | `Nano Banana`, `Seedream 4.5`, `Google Imagen 4` |
| Cinematic / mood-heavy | `Flux 1.1 Pro` |

Pass the source as the human-readable NAME string, not a UUID.

**Critical design rules** (violating these = unsellable product):

1. **NEVER generate apparel-as-image.** The image IS the design that goes ON the product. Don't ask for "a t-shirt with a cactus" — ask for "a saguaro cactus illustration." The shirt is the medium, not the subject.
2. **Always prompt for a solid contrasting background, NOT "transparent background."** AI models can't actually produce transparency; they bake fake checkerboard patterns into RGB pixels. Always request a solid bright green (`#00FF00`) — you'll strip it locally in Phase 2.
3. **Verify any text in the design with a vision model BEFORE proceeding.** AI models routinely misspell. If the user asked for "STAY WILD" and the image shows "STAY WLID", you must regenerate before creating the product.

**After Phase 1 — decide whether Phase 2 is required:**

| Garment type | Transparency required? |
|---|---|
| Standard front-print apparel (tees, hoodies, sweatshirts, tanks) | **YES, by default** — go to Phase 2 |
| All-over-print products (pillows, doormats, area rugs, beach towels, AOP tees) | **NO** — these print edge-to-edge including background color. SKIP Phase 2 and use the raw generated image |
| User explicitly opts out | **NO** — see "Break-glass override" below |

**Break-glass override:** the user may want a solid-background design intentionally (vintage look, full-bleed graphic, distressed aesthetic). RESPECT their intent. Skip Phase 2 if the user said any of:
- "Keep the background"
- "Don't remove the background"
- "I want the [color] background"
- "Make it a vintage [solid color] design"
- "Full-bleed design"
- "Print it as-is"

**Ambiguous case** (user didn't specify): default to TRANSPARENT (the safe choice for 95% of merchant intent), BUT report it: *"I removed the green background so it sits cleanly on the shirt. If you wanted a solid-color background design, let me know and I'll regenerate."* Don't silently make this call.

### Phase 2 — LOCAL transparency processing (REQUIRED for standard apparel unless break-glass override)

**This phase is COMPUTE work on your machine, NOT an API call.** The platform's transform endpoint just stores whatever bytes you upload — it does NOT do flood-fill. You have to do it yourself before uploading.

**Step 2a: Local processing with Pillow.** Download the image, flood-fill the solid background, pre-multiply transparent pixels with white RGB:

```python
from PIL import Image, ImageDraw
import requests
from io import BytesIO

# Download the generated image (has solid green #00FF00 background)
img = Image.open(BytesIO(requests.get(image_url).content)).convert('RGBA')
w, h = img.size

# Flood-fill the green background from each corner
# Tolerance accommodates anti-aliased edges
target = (0, 255, 0)        # the green background
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

# Save the processed image
img.save('/tmp/design_transparent.png', 'PNG')
```

**Step 2b: Upload the processed bytes via the transform endpoint** (which is just an upload, NOT a transformation):

```bash
curl -sS -X POST "https://api.apparelhub.ai/agents/v1/images/generated/<original_image_uuid>/transform" \
  -H "x-api-key: $APPARELHUB_API_KEY" \
  -F "image=@/tmp/design_transparent.png"
```

This returns a NEW image UUID + URL with true RGBA transparency. Use the NEW UUID for Phase 3 onwards.

**Common Phase 2 failure modes worth checking:**
- Letter loops (the inside of B, e, d, M, a, etc.) not transparent. The flood-fill above only reaches connected exterior regions. For designs with text, do a second sweep: for any pixel matching the background color that's NOT yet transparent, make it transparent too (a per-pixel pass, not just flood-fill).
- White halos around transparent edges. Caused by skipping the pre-multiplication. The `(255, 255, 255, 0)` in the snippet above prevents this.
- Faint green ring around the design's silhouette. Caused by tolerance too low for anti-aliased edges. Raise `tolerance` from 60 to 80-90.

### Phase 3 — Generate the mockup

You need a `provider_uuid` (Printful or Printify) and a `product_ref_id` (the garment type, e.g. `71` for Bella+Canvas 3001 unisex tee).

**⚠️ FIELD-NAME FLIP between this endpoint and the product-create endpoint** — easy to mix up:
- Preview endpoint: `merchandise_provider_uuid`, `provider_product_ref_id` (THIS phase)
- Product create endpoint: `provider_uuid`, `product_ref_id` (Phase 4)

The fields are essentially the same data but with DIFFERENT names. Don't carry over the names between phases.

**Step 3a: browse the catalog if you don't know the ref_id:**
```bash
curl -sS "https://api.apparelhub.ai/agents/v1/merchandise/<provider_uuid>/products?fields=provider_ref_id,name,brand" \
  -H "x-api-key: $APPARELHUB_API_KEY"
```

**Step 3b: FETCH the garment's print templates** — this gives you the `area_width`, `area_height`, and the valid `provider_ref_id` for each print placement. DO NOT hardcode these dimensions; they vary per garment.

```bash
curl -sS "https://api.apparelhub.ai/agents/v1/merchandise/<provider_uuid>/product/<product_ref_id>" \
  -H "x-api-key: $APPARELHUB_API_KEY"
```

The response includes `print_templates` (or similar) with each placement's `area_width`, `area_height`, and `provider_ref_id` (e.g., `"front"`, `"back"`).

**Step 3c: CALCULATE design positioning** within the print area:

For a CHEST-FILLING front print (the standard look for a tee):
- `width` = 80-90% of `area_width` (the design should be substantial, not a small chest emblem)
- `height` = scale proportionally to maintain the design's aspect ratio
- `left` = `(area_width - width) / 2` (center horizontally)
- `top` = small positive number (10-30) OR 0 to top-align within the print area

Example for Bella+Canvas 3001 front print (typical `area_width: 728, area_height: 376`):
- `width: 600` (82% of 728 — chest-filling)
- `height: 600` (square design; OK if it overshoots area_height since it's anchored at top)
- `left: 64` ((728 - 600) / 2)
- `top: 0`

For a small CHEST EMBLEM (logo-style): `width = 200-280` is appropriate.

For a center-back print: same math but use the back placement's area dimensions.

**Step 3d: create the preview** with the COMPLETE template structure:
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

Note: include ALL variant_ids across ALL colors in ONE preview call (15 IDs for 3 colors × 5 sizes). The provider returns separate mockups per color in the same job.

**Missing any template field → 404 error with KeyError or generic Exception from `merchandise.py`.** Common cause of "Error building the standard response for product preview" failures. Always pass the full template object.

Returns a `job_uuid`. Mockup generation is **async** — poll until complete:

```bash
curl -sS "https://api.apparelhub.ai/agents/v1/merchandise/product/preview/<provider_uuid>/job/<job_uuid>" \
  -H "x-api-key: $APPARELHUB_API_KEY"
```

### Phase 3.5 — MANDATORY mockup verification

When the job status is `completed`, **DO NOT immediately proceed to product creation.** The mockup pipeline has two completion phases:

1. Job status = `completed` means the provider's render job finished, BUT
2. The `preview_url` on each preview row may still be NULL — that's our S3 ingestion catching up. Can take 20+ minutes.

**Poll until at least one preview has a non-null `preview_url`:**

```bash
curl -sS "https://api.apparelhub.ai/agents/v1/merchandise/product/preview-job/<job_uuid>/previews" \
  -H "x-api-key: $APPARELHUB_API_KEY"
```

Once `preview_url` is populated, **visually inspect the mockup** (download with curl and view, or use vision tools). Check for:
- Design renders correctly (not cut off, not distorted)
- Text is legible and spelled correctly
- No white halos around transparent edges
- No checkerboard artifacts where transparency should be
- Color contrast is acceptable on the chosen garment

If anything looks wrong, FIX the design and re-mockup before continuing. Never ship a broken mockup to product creation — manufacturing follows the mockup.

### Phase 4.0 — Pick display_image + build gallery_images from preview mockups

Before calling product create, query the preview job's preview rows to pick the BEST mockup for the product thumbnail (`display_image`) AND build a curated gallery (`gallery_images`). The platform has sensible defaults if you skip this, but explicit selection gives the merchant a better product page out of the gate.

```bash
PREVIEWS=$(curl -sS "https://api.apparelhub.ai/agents/v1/merchandise/product/preview-job/<job_uuid>/previews" \
  -H "x-api-key: $APPARELHUB_API_KEY")
```

Each preview row has:
- `uuid` — apparelhub's S3-stored copy ID
- `preview_url` — apparelhub's S3 URL (may be NULL during the two-phase ingestion race; see Phase 3.5)
- `provider_preview_ref_url` — the provider's CDN URL; filename contains color + angle (e.g., `unisex-staple-t-shirt-black-front-abc123.png`)
- `thumbnail_url` — 500x500 thumb

**Pick `display_image`:**
1. Prefer FRONT-view (provider_preview_ref_url contains `-front-` in filename)
2. Among front-views, prefer DARK shirts (black, navy, charcoal, midnight) — best contrast for showing the design
3. Prefer rows with non-null `preview_url` (our S3 mirror) over those with only `provider_preview_ref_url`
4. Use that row's `preview_url` (or fall back to its `provider_preview_ref_url`) as `display_image`

**Build `gallery_images`:**
1. Group previews by color (parse from provider_preview_ref_url filename)
2. For each color, take ONE front-view; add to gallery
3. Order: darkest color FIRST (matches the display_image choice), then remaining colors
4. Then append back-views of each color
5. Cap at ~10 images

### Phase 4 — Create the product

This phase has FOUR FIELD-NAME GOTCHAS that silently break products if you get them wrong. Memorize — these are DIFFERENT from the preview endpoint's names:

| ❌ Wrong (intuitive, OR copy-pasted from Phase 3) | ✅ Correct (product create) |
|---|---|
| `merchandise_provider_uuid` | `provider_uuid` |
| `provider_product_ref_id` | `product_ref_id` |
| `retail_price` | `price` |

Note: Phase 3's preview endpoint uses `merchandise_provider_uuid` + `provider_product_ref_id`. This phase uses `provider_uuid` + `product_ref_id`. Same data, FLIPPED names. Don't copy the names from Phase 3.

Wrong field names create the product "successfully" but with NULL `manufacturing_metadata`, and sync silently fails downstream. The API doesn't reject your mistake.

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

**Important: `print_data[].image_url` is the RAW DESIGN URL** (the image from Phase 2, with transparency). This is what Printful uses to actually PRINT. It is NOT a mockup. Never put a mockup URL in print_data — that ships shirt-on-a-shirt.

**`display_image` and `gallery_images` are MOCKUP URLs** (from preview job). These are what customers see on the product page. Never put the raw design URL here — that shows the design on a green background instead of on a shirt.

If you OMIT `display_image` and `gallery_images`, the platform picks them automatically using the same logic described in Phase 4.0. Explicit is preferred when you want a specific dark-color thumbnail.

Returns the new product `uuid`.

### Phase 5 — Add variants

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

### Phase 6 — Associate the product with the user's store

```bash
# List the user's stores first
curl -sS "https://api.apparelhub.ai/agents/v1/store" \
  -H "x-api-key: $APPARELHUB_API_KEY"

# Then add the product
curl -sS -X POST "https://api.apparelhub.ai/agents/v1/store/<store_uuid>/products" \
  -H "x-api-key: $APPARELHUB_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"product_uuids": ["<product_uuid>"]}'
```

### Phase 7 — Sync to fulfillment provider AND sales channels

Sync targets are different depending on what you're syncing to:

**Fulfillment (Printful/Printify) — REQUIRED FIRST:**
```bash
curl -sS -X POST "https://api.apparelhub.ai/agents/v1/store/<store_uuid>/products/<product_uuid>/sync?target=merchandise" \
  -H "x-api-key: $APPARELHUB_API_KEY"
```

This creates the product on the fulfillment provider's side. MUST succeed before ecommerce sync — Shopify/Etsy/etc. need the fulfillment SKU to attach.

**Ecommerce (Shopify, Etsy, WooCommerce, Wix):**
```bash
curl -sS -X POST "https://api.apparelhub.ai/agents/v1/store/<store_uuid>/products/<product_uuid>/sync?target=ecommerce&integration_uuid=<integration_uuid>" \
  -H "x-api-key: $APPARELHUB_API_KEY"
```

You can sync to multiple channels by calling this once per integration.

**Default to DRAFT, not live.** When syncing to channels that support a draft state (Etsy, Shopify), prefer pushing the product as a draft first. This gives the merchant a chance to review the listing on the channel's side (description, photos, pricing) before it goes live to shoppers. Tell the merchant: *"I've synced as drafts so you can review on your storefront before going live. To publish, either flip the listing in your Shopify/Etsy admin or run the sync again with `?listing_state=active`."*

Only push as `active` (live) if the user EXPLICITLY says "make it live" or "publish it" — otherwise default to draft. The cost of a too-eager publish (typo'd description in front of real customers) is much higher than the cost of one extra step.

Done — the product is now synced to the user's storefront in draft form.

---

## 4. Quick reference — common garments

### Bella+Canvas 3001 (Standard Unisex T-Shirt)

`provider_product_ref_id = "71"` on Printful.

**Variant ID table** — colors × sizes:

| Color | S | M | L | XL | 2XL |
|---|---|---|---|---|---|
| Black | 4016 | 4017 | 4018 | 4019 | 4020 |
| White | 4012 | 4013 | 4014 | 4015 | 4011 |
| Navy (Heather Midnight Navy) | 8495 | 8496 | 8497 | 8498 | 8499 |
| Solid White Blend | 24352 | 24353 | 24354 | 24355 | 24356 |

⚠️ **CRITICAL WARNING:** Variant IDs `4021-4025` are `AQUA`, NOT Navy. If a user asks for navy, use the Heather Midnight Navy IDs (8495-8499). Triple-check via the catalog endpoint if unsure:
```bash
curl -sS "https://api.apparelhub.ai/agents/v1/merchandise/<provider_uuid>/product/71" \
  -H "x-api-key: $APPARELHUB_API_KEY" | python3 -m json.tool
```

### Pricing floors (do NOT price below cost + margin)

Always price competitively. Negative margin = the merchant loses money.

| Garment | Approx cost | Recommended retail |
|---|---|---|
| BC 3001 Standard Tee | ~$11.69 | $27.99 |
| BC 3001 Influencer Tee | ~$11.69 | $29.99 |
| Comfort Colors Tee | ~$14.69 | $34.99 |
| BC 6400 Women's Relaxed | ~$13.69 | $34.99 |
| BC 3719 Pullover Hoodie | ~$25.50 | $54.99 |
| BC 4719 Heavyweight Hoodie | ~$36.50 | $64.99 |
| AOP Athletic Tee | ~$22.00 | $44.99 |
| Youth Tees | ~$10.50 | $24.99 |

**Quality tip:** Comfort Colors tees are higher quality (heavier weight ~6.1oz, true pigment-dyed, softer hand-feel) than Bella+Canvas at the cost of ~$3 more in cost. If the user is building a premium-feel brand or selling at $35+ price points, recommend Comfort Colors over BC 3001. For high-volume / budget-conscious lines, BC 3001 is the right pick.

### Color limit per design

**Max 4 color variants per design.** More than that creates SKU sprawl that hurts conversion. Pick the 4 best colors for the design and stop.

---

## 5. Product-specific design rules

### Standard front-print T-shirts (BC 3001, BC 6400, etc.)
- Design needs TRUE transparency (RGBA with alpha=0) so shirt color shows through
- Use Phase 2 transparency transform after generating
- ALWAYS mockup on BLACK first — dark shirts expose white halos that light shirts hide

### All-over print pillows (product 214)
- Design covers the ENTIRE pillow surface — no "transparent shows pillow color" like t-shirts
- The pillow fabric is white; to make it APPEAR a color, fill the entire image with a solid background color
- Background MUST extend to every edge — check all 4 corner pixels match
- Print at FULL area dimensions (e.g., 2717x2717 for 18×18 inch)

### Water bottle (product 382)
- Design needs TRUE transparency for the white bottle
- Print area is wide and short (700×433) — vertical designs work best
- `provider_ref_id: "default"` for the print template

### Doormat / area rug (product 924)
- ALL-OVER print like the pillow
- Doormats MUST be LANDSCAPE orientation (text reads left-to-right when standing in front)
- Use a dark background since people step on it
- Don't rotate a portrait design 90° — regenerate natively in landscape composition

---

## 6. Working with the user's existing data

### List their stores
```bash
curl -sS "https://api.apparelhub.ai/agents/v1/store" \
  -H "x-api-key: $APPARELHUB_API_KEY"
```

### List products on a specific store
```bash
curl -sS "https://api.apparelhub.ai/agents/v1/store/<store_uuid>/products?fields=uuid,name,price,status,thumbnail_url,fulfillment_status,ecommerce_statuses" \
  -H "x-api-key: $APPARELHUB_API_KEY"
```

Pass `?fields=` to trim response size when you only need card data.

### List the user's AI-generated images
```bash
curl -sS "https://api.apparelhub.ai/agents/v1/images/generated?limit=20&sort=newest" \
  -H "x-api-key: $APPARELHUB_API_KEY"
```

### List orders
```bash
curl -sS "https://api.apparelhub.ai/agents/v1/orders?limit=10" \
  -H "x-api-key: $APPARELHUB_API_KEY"

# Detail for a specific order
curl -sS "https://api.apparelhub.ai/agents/v1/orders/<uuid>" \
  -H "x-api-key: $APPARELHUB_API_KEY"
```

---

## 7. Common patterns

### "Make me 3 designs of a saguaro cactus"
- Run Phase 1 three times with the same prompt + same source
- Show the user all three image URLs
- Let them pick which one(s) to proceed with

### "Create a Mother's Day collection"
- Plan a SET of designs first (theme, color palette, garment mix)
- Generate each design (Phase 1) and verify visually
- Create products in parallel (Phases 2-5 per product)
- Sync the whole set in one batch at the end (Phase 7)

### "Sync this existing product to my Shopify store"
1. Find the product UUID via `GET /agents/v1/product` (filter by name)
2. Find the user's Shopify integration UUID via `GET /agents/v1/store/<uuid>` and look for the `ecommerce_statuses` array
3. Call sync (Phase 7 ecommerce flow)

### "What didn't sync?"
- `GET /agents/v1/store/<uuid>/products` — look at `ecommerce_statuses` array
- Each entry shows the per-integration sync state. Find entries with `sync_status != 'Synced'`

---

## 8. Error handling

| Status | What it means | What to do |
|---|---|---|
| 401 | API key missing or invalid | Ask user to verify `APPARELHUB_API_KEY` env var |
| 403 | User's tier doesn't include API access | Tell them Professional or Enterprise tier required — link to apparelhub.ai/pricing |
| 409 | Conflict — usually integration locked, sales channel uniqueness violation, or duplicate product | Read the error body. For "integration_locked", tell user to unlock in store dashboard. For "sales_channel_uniqueness", the shop is already connected to another account |
| 429 | Rate limited | Backoff exponentially. Default tier is 10 req/sec, 10K/mo |
| 500 | Server error | Retry once. If it persists, capture the response body + tell the user there's a platform issue |

When errors mention sync to channels, common causes:
- Variants not yet created (Phase 5 skipped)
- Fulfillment sync not run before ecommerce sync (Phase 7 ordering matters)
- Integration credentials revoked (user disconnected the channel from apparelhub.ai)

---

## 9. When NOT to use this skill

- **The user wants to BUY a finished product.** ApparelHub is for merchants designing + selling, not for end-shoppers. Direct them to the merchant's storefront.
- **Generic image generation unrelated to apparel.** Use OpenAI/Stability directly; ApparelHub charges against the user's image quota.
- **Platform admin / sales channel app configuration.** Things like "register my Etsy app's webhook URLs" or "rotate my Shopify secret" are platform-admin operations done in the apparelhub.ai web UI, not via the agent API.
- **Bulk operations beyond ~50 products at once.** The agent API enforces rate limits; for true bulk migrations (1000+ products), the user should contact ApparelHub support.

---

## 10. Reporting back to the user

After completing a workflow, give the user a tight summary:

- What you generated (design URL)
- The mockup link (so they can verify visually)
- The product page URL: `https://apparelhub.ai/merchandise/my-products`
- Which channels you synced to + sync status
- Anything that didn't succeed and why

Don't dump raw JSON. The user wants outcomes, not API responses.

---

## Quick links the user might want

- Product manager: `https://apparelhub.ai/merchandise/my-products`
- Generated designs: `https://apparelhub.ai/images/gallery`
- Stores: `https://apparelhub.ai/stores`
- Orders: `https://apparelhub.ai/orders`
- API keys: `https://apparelhub.ai/developer/api-keys`
- Live API docs: `https://apparelhub.ai/developer/api-docs`
- Pricing tiers: `https://apparelhub.ai/pricing`
