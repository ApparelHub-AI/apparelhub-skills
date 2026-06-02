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
  "prompt": "vector flat illustration saguaro cactus silhouette desert sunset, warm orange and red palette, on pure RGB #00FF00 background, fully saturated bright green, NOT yellow-green or olive, NOT chartreuse",
  "source": "Nano Banana",
  "size": "1024x1024"
}'
```

Response shape:
```json
{ "generated_image": { "uuid": "abc-123-def", "url": "https://apparelhub-production-user-generated-public-objects.s3.amazonaws.com/.../abc-123-def.png" } }
```

Capture the `uuid` and `url` in your reasoning context. From now on you'll substitute those LITERAL values into subsequent calls.

**Verify visually.** Download and view the image. Check that:
1. The cactus illustration looks good
2. The background is solid **bright** green — close to pure `#00FF00`, NOT yellow-green / olive / chartreuse. If the AI produced a wrong color, `make_transparent.py` in Phase 2 will reject the keying with a sanity-check failure. Better to regenerate now than wait for that.
3. If the design has any text, vision-check the spelling.

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

The script auto-detects the corner chroma color, runs a sanity check that it's close to pure `#00FF00`, flood-fills + sweeps enclosed regions, writes pre-multiplied white, and **auto-crops to the design's tight bounding box** (so Phase 3 sizing reflects the actual design extent, not the AI canvas + transparent margin).

**Exit code 4 — chroma sanity check failed.** The AI used a yellow-green / olive / muted background. Regenerate the design with the stricter prompt from Phase 1 (do NOT just pass `--force-chroma` — that risks eating warm design colors like the yellow sun in a sunset illustration).

**Exit code 3 — corners not fully transparent.** Some background pixels survived. Re-run with `--dominance --despill`.

**Exit code 0 — success.** The script prints the post-crop dimensions and `corner alpha [0, 0, 0, 0] (want all 0)`. **Inspect `/tmp/design_preview.jpg`** before continuing — that's the no-halo, no-leftover-green gate.

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

Calculate correct `(width, height, left, top)` from the Phase 2 cropped design's aspect ratio + the print area:

```bash
ah_pick_dimensions /tmp/design_transparent.png 728 376 --style chest_fill --out /tmp/dimensions.json
```

The script prints JSON with the computed numbers. For a typical 664×527 cropped saguaro design on the 728×376 print area, you'll get something like `width=413, height=328, left=157, top=48` — height-constrained so the design fits entirely without crop, with a 13% collar padding (~48px / ~0.8") of breathing room between the collar seam and the design.

**Do NOT hand-pick these numbers.** The skill's old "80-90% of area_width" guidance produced too-small prints for square-ish designs, design-overshoot for tall designs, AND `top=0` chest prints that touched the collar. `ah_pick_dimensions` codifies the math AND the breathing-room defaults.

If the merchant wants a TIGHTER or LOOSER look, pass `--collar-padding-pct`:
- `0.05` — design closer to the collar (~0.3" breathing room), more substantial chest-fill
- `0.10` — tighter than default (~0.6")
- `0.13` (default) — typical retail chest print (~0.8")
- `0.15` — design pushed lower (~0.9" breathing room), smaller but well-anchored
- `0.20` — extra generous (~1.2"), design pushed toward mid-chest

Create the preview with ALL 15 variant IDs in one call. Substitute the LITERAL values from `/tmp/dimensions.json` AND the literal transparent-image UUID + URL from Phase 2:

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
      "width": 413,
      "height": 328,
      "top": 48,
      "left": 157
    }
  ],
  "variant_ids": [4016, 4017, 4018, 4019, 4020, 8495, 8496, 8497, 8498, 8499, 4012, 4013, 4014, 4015, 4011]
}'
```

**Your numbers will differ** depending on the design's aspect ratio after cropping. Always source them from `ah_pick_dimensions`, not from this example.

Response includes `job_uuid`. Capture it.

Wait for the job to finish AND for `preview_url` ingestion in ONE call via the packaged script:

```bash
# Substitute literal job UUID. Default polls every 8s, 30-minute timeout.
ah_poll_mockup c8dff2fa-1a43-4734-93f0-e2ddd03eae53 <job_uuid>
```

The script handles BOTH completion phases (provider render finish + our S3 ingestion catching up) and writes the final response to `/tmp/preview_job.json`. Do NOT write an inline `for` loop with `$(...)` substitution — that trips the expansion check on every iteration.

---

## Phase 3.5 — Visual verification

Extract the black front URL with `ah_pick_provider_url`, then download for inspection:

```bash
ah_pick_provider_url /tmp/preview_job.json black front
# Returns: https://apparelhub-production-user-generated-public-objects.s3.amazonaws.com/<uuid>.png

curl -sS -o /tmp/mockup_check.png "https://apparelhub-production-user-generated-public-objects.s3.amazonaws.com/<paste-uuid-from-above>.png"
```

Open `/tmp/mockup_check.png` and verify:
- Cactus design renders correctly (not cut off)
- No white halos around the silhouette
- Color contrast acceptable on black

If anything looks wrong, regenerate the design before continuing. Never ship a broken mockup to product creation — manufacturing follows the mockup.

---

## Phase 4.0 — Build display_image + gallery_images recommendation

One call:

```bash
ah_classify_previews /tmp/preview_job.json --recommend /tmp/picks.json
```

This prints the full (COLOR, ANGLE, URL) table AND writes `/tmp/picks.json` with the recommended dark-color front mockup as `display_image` plus a curated gallery (one front per color darkest-first, then backs). Read the literal URLs from `/tmp/picks.json` and paste them into the Phase 4 product create body.

---

## Phase 4 — Create the product

Substitute literal values throughout: the transparent image UUID + URL from Phase 2, the job UUID from Phase 3, and the `display_image` + `gallery_images` URLs from `/tmp/picks.json` (Phase 4.0).

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
      "width": 413,
      "height": 328,
      "top": 48,
      "left": 157
    }
  ]
}'
```

**Critical:** the `width`/`height`/`top`/`left` numbers MUST match what was sent to the Phase 3 preview call. Source them from `/tmp/dimensions.json` (the `ah_pick_dimensions` output) — don't hardcode them, and don't let the values drift between Phase 3 and Phase 4.

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
