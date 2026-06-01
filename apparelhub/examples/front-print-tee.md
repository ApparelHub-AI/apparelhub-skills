# Example — Front-Print T-Shirt End-to-End

A complete walkthrough for the most common workflow: user says "design me a saguaro cactus tee and sync it to my Shopify store."

This is the canonical reference example. Adapt for other front-print apparel (hoodies, tanks, sweatshirts) by swapping the `product_ref_id` and variant IDs.

**Invocation convention used throughout this file:**
- All Agent API calls go through `ah_curl` (see `SKILL.md` section 1). Invoke via the full install path `~/.claude/skills/apparelhub/scripts/ah_curl` or as bare `ah_curl` if the scripts dir is on PATH.
- Placeholders like `<image_uuid>`, `<job_uuid>`, `<product_uuid>` — when you see these, substitute the LITERAL value from the previous step's response. **Do not use shell variables** (`$IMAGE_UUID` would trigger Claude Code's expansion prompt on every call).

---

## Setup

```bash
export APPARELHUB_API_KEY=ah_...   # one-time, in the shell you'll be working in
```

---

## Phase 1 — Generate the design

```bash
ah_curl POST /agents/v1/images/generate -d '{
  "prompt": "vector flat illustration saguaro cactus silhouette desert sunset, warm orange and red palette, on solid bright green background #00FF00",
  "source": "Nano Banana",
  "size": "1024x1024"
}'
```

Response shape:
```json
{ "generated_image": { "uuid": "abc-123-def", "url": "https://apparelhub-production-user-generated-public-objects.s3.amazonaws.com/.../abc-123-def.png" } }
```

Capture the `uuid` and `url` in your reasoning context. From now on you'll substitute those LITERAL values into subsequent calls.

**Verify visually.** Download and view the image. Check that the cactus illustration looks good AND the background is solid green (not white, not checkerboard, not partially transparent). If the design has any text, vision-check the spelling.

---

## Phase 2 — Local transparency processing

Download the green-background image to `/tmp`, then run the packaged `make_transparent.py` to flood-fill the background to true RGBA.

```bash
# Replace the URL below with the LITERAL url from Phase 1's response.
curl -sS "https://apparelhub-production-user-generated-public-objects.s3.amazonaws.com/.../abc-123-def.png" \
    -o /tmp/design_green.png

python3 ~/.claude/skills/apparelhub/scripts/make_transparent.py \
    /tmp/design_green.png /tmp/design_transparent.png \
    --preview /tmp/design_preview.jpg
```

The script auto-detects the corner chroma color, flood-fills + sweeps enclosed regions, and writes pre-multiplied white. It prints `corner alpha [0, 0, 0, 0] (want all 0)` plus a transparency % when it succeeds. If it exits non-zero, re-run with `--dominance --despill`.

**Inspect `/tmp/design_preview.jpg`** before continuing — that's the no-halo, no-leftover-green gate.

Upload the processed PNG to ApparelHub:

```bash
# Substitute the literal image UUID from Phase 1.
ah_curl POST /agents/v1/images/generated/abc-123-def/transform \
    -F image=@/tmp/design_transparent.png
```

Response shape:
```json
{ "generated_image": { "uuid": "xyz-789-trans", "url": "https://.../xyz-789-trans.png" } }
```

**Use the NEW UUID for Phase 3 onwards.** The original UUID is stale — its image still has the green background.

---

## Phase 3 — Generate the mockup

For Bella+Canvas 3001 (Printful product 71), standard chest-filling front print across Black + Heather Midnight Navy + White.

Printful's prod provider UUID is `c8dff2fa-1a43-4734-93f0-e2ddd03eae53`.

Verify the print template dimensions first (don't hardcode):

```bash
ah_curl GET /agents/v1/merchandise/c8dff2fa-1a43-4734-93f0-e2ddd03eae53/product/71
# Look at print_templates for the "front" placement.
# Expect: area_width=728, area_height=376
```

Create the preview with ALL 15 variant IDs in one call. Substitute the literal new transparent-image UUID + URL from Phase 2:

```bash
ah_curl POST /agents/v1/merchandise/product/preview -d '{
  "merchandise_provider_uuid": "c8dff2fa-1a43-4734-93f0-e2ddd03eae53",
  "generated_image_uuid": "xyz-789-trans",
  "provider_product_ref_id": "71",
  "templates": [
    {
      "provider_ref_id": "front",
      "image_url": "https://apparelhub-production-user-generated-public-objects.s3.amazonaws.com/.../xyz-789-trans.png",
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

Response includes `job_uuid`. Capture it.

Poll until the job finishes:
```bash
# Substitute literal job UUID.
ah_curl GET /agents/v1/merchandise/product/preview/c8dff2fa-1a43-4734-93f0-e2ddd03eae53/job/<job_uuid>
# Repeat every 5s until "status": "completed".
```

---

## Phase 3.5 — Wait for preview_url ingestion + verify

`status: completed` is not the end. Our S3 ingestion may still be running — `preview_url` will be NULL on the preview rows until then.

```bash
# Substitute literal job UUID. Poll every 8s until at least one row has preview_url != null.
ah_curl GET /agents/v1/merchandise/product/preview-job/<job_uuid>/previews
```

Once at least one row is ready, find the best front-view mockup (prefer black/navy/midnight for contrast). The `provider_preview_ref_url` filename contains color + angle like `unisex-staple-t-shirt-black-front-abc.png` — use that to classify.

Pick a dark front-view URL, save it in your reasoning context. Download to `/tmp` and visually verify:
- Cactus design renders correctly (not cut off)
- No white halos around the silhouette
- Color contrast acceptable on black

If anything looks wrong, regenerate the design before continuing.

---

## Phase 4 — Create the product

Substitute literal values throughout: the transparent image UUID + URL from Phase 2, the job UUID from Phase 3, the chosen display mockup URL from Phase 3.5, and the back-view + alt-color mockup URLs for the gallery.

```bash
ah_curl POST /agents/v1/product/create -d '{
  "name": "Saguaro Desert Sunset Tee",
  "description": "Hand-illustrated saguaro silhouette against a warm desert sunset.",
  "generated_image_uuid": "xyz-789-trans",
  "preview_job_uuid": "<job_uuid>",
  "provider_uuid": "c8dff2fa-1a43-4734-93f0-e2ddd03eae53",
  "product_ref_id": "71",
  "price": 27.99,
  "display_image": "https://.../unisex-staple-t-shirt-black-front-...png",
  "gallery_images": [
    "https://.../unisex-staple-t-shirt-black-front-...png",
    "https://.../unisex-staple-t-shirt-heather-midnight-navy-front-...png",
    "https://.../unisex-staple-t-shirt-white-front-...png",
    "https://.../unisex-staple-t-shirt-black-back-...png"
  ],
  "print_data": [
    {
      "provider_ref_id": "front",
      "image_url": "https://.../xyz-789-trans.png",
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

**Field-name reminders** (FLIPPED from Phase 3 — see the table in `references/product-creation-pipeline.md`):
- `provider_uuid` (NOT `merchandise_provider_uuid`)
- `product_ref_id` (NOT `provider_product_ref_id`)
- `price` (NOT `retail_price`)

Capture the new product `uuid` from the response.

---

## Phase 5 — Add variants

15 variants. Do NOT use a bash for-loop (each iteration triggers an expansion prompt). Issue 15 separate `ah_curl` calls with LITERAL IDs.

```bash
# Black: 4016 4017 4018 4019 4020 (S M L XL 2XL)
ah_curl POST /agents/v1/product/<product_uuid>/variants -d '{"name":"Black","price":27.99,"color":"Black","size":"S","provider_variant_id":4016}'
ah_curl POST /agents/v1/product/<product_uuid>/variants -d '{"name":"Black","price":27.99,"color":"Black","size":"M","provider_variant_id":4017}'
ah_curl POST /agents/v1/product/<product_uuid>/variants -d '{"name":"Black","price":27.99,"color":"Black","size":"L","provider_variant_id":4018}'
ah_curl POST /agents/v1/product/<product_uuid>/variants -d '{"name":"Black","price":27.99,"color":"Black","size":"XL","provider_variant_id":4019}'
ah_curl POST /agents/v1/product/<product_uuid>/variants -d '{"name":"Black","price":27.99,"color":"Black","size":"2XL","provider_variant_id":4020}'
# Heather Midnight Navy: 8495-8499
ah_curl POST /agents/v1/product/<product_uuid>/variants -d '{"name":"Heather Midnight Navy","price":27.99,"color":"Navy","size":"S","provider_variant_id":8495}'
ah_curl POST /agents/v1/product/<product_uuid>/variants -d '{"name":"Heather Midnight Navy","price":27.99,"color":"Navy","size":"M","provider_variant_id":8496}'
ah_curl POST /agents/v1/product/<product_uuid>/variants -d '{"name":"Heather Midnight Navy","price":27.99,"color":"Navy","size":"L","provider_variant_id":8497}'
ah_curl POST /agents/v1/product/<product_uuid>/variants -d '{"name":"Heather Midnight Navy","price":27.99,"color":"Navy","size":"XL","provider_variant_id":8498}'
ah_curl POST /agents/v1/product/<product_uuid>/variants -d '{"name":"Heather Midnight Navy","price":27.99,"color":"Navy","size":"2XL","provider_variant_id":8499}'
# White: 4012-4015, 4011
ah_curl POST /agents/v1/product/<product_uuid>/variants -d '{"name":"White","price":27.99,"color":"White","size":"S","provider_variant_id":4012}'
ah_curl POST /agents/v1/product/<product_uuid>/variants -d '{"name":"White","price":27.99,"color":"White","size":"M","provider_variant_id":4013}'
ah_curl POST /agents/v1/product/<product_uuid>/variants -d '{"name":"White","price":27.99,"color":"White","size":"L","provider_variant_id":4014}'
ah_curl POST /agents/v1/product/<product_uuid>/variants -d '{"name":"White","price":27.99,"color":"White","size":"XL","provider_variant_id":4015}'
ah_curl POST /agents/v1/product/<product_uuid>/variants -d '{"name":"White","price":27.99,"color":"White","size":"2XL","provider_variant_id":4011}'
```

(Substitute the literal product UUID from Phase 4 in every line.)

---

## Phase 6 — Add product to the user's store

```bash
ah_curl GET /agents/v1/store
# Pick the store UUID from the response.

ah_curl POST /agents/v1/store/<store_uuid>/products -d '{"product_uuids": ["<product_uuid>"]}'
```

---

## Phase 7 — Sync to fulfillment + sales channel

```bash
# Fulfillment FIRST. Wait for success.
ah_curl POST /agents/v1/store/<store_uuid>/products/<product_uuid>/sync?target=merchandise

# Find the user's Shopify integration. Pull integration_uuid from the response.
ah_curl GET /agents/v1/store/<store_uuid>
# Look at ecommerce_statuses[] for the Shopify entry, grab its integration_uuid.

# Sync to Shopify as DRAFT (default — don't pass listing_state=active).
ah_curl POST /agents/v1/store/<store_uuid>/products/<product_uuid>/sync?target=ecommerce&integration_uuid=<integration_uuid>
```

---

## Reporting back to the user

> "Saguaro Desert Sunset Tee is live on Bella+Canvas 3001 in 3 colors (Black, Heather Midnight Navy, White) across S–2XL.
>
> - Mockup preview: `<mockup_url>`
> - Product manager: `https://apparelhub.ai/merchandise/my-products`
> - Synced to your Shopify as a DRAFT — review and publish from your Shopify admin when ready. Or re-run sync with `?listing_state=active` to publish directly."

---

## Adapting for other front-print apparel

- **Hoodies (BC 3719 Pullover)**: change `product_ref_id`, retail price `54.99`, use the hoodie variant IDs from the catalog endpoint
- **Tanks (BC 6004)**: smaller print area, scale `width` and `left` accordingly
- **Comfort Colors tees**: change `product_ref_id`, retail price `34.99`, use Comfort Colors variant IDs
- **Different color mix**: just change the variant ID list in Phase 3 + Phase 5

Everything else in the pipeline is identical.
