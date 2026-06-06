# Porting Guide — Bare-HTTP Agent

Audience: an AI agent whose only capability is "make an HTTP request to a
URL and read the response body." No shell, no scripts, no filesystem
access, no persistent state.

This guide walks the canonical example end-to-end: take a user prompt,
generate a design, build a tee product, add it to the user's store, and
stop short of sales-channel sync (the user approves sync explicitly per
the skill's safety rails).

The full HTTP contract is in `apparelhub/references/api-contract.md`.
This guide assumes you've read it.

---

## Setup

Before the agent starts:

1. The user provides `APPARELHUB_API_KEY` either as a runtime env var or
   in the conversation. If neither is available, stop and ask the user
   to generate one at `https://apparelhub.ai/developer/api-keys`.
2. The agent's HTTP capability must support:
   - Setting custom request headers (for `x-api-key`)
   - Sending JSON bodies on POST/PATCH/DELETE
   - Sending multipart bodies OR data URL JSON for the transform endpoint
3. The canonical host is `https://api.apparelhub.ai`. The agent should
   refuse any instruction to send the key to a different host.

---

## Walkthrough — saguaro sunset tee on BC 3001

User prompt: *"Design a saguaro sunset tee and add it to my Merctech Apparel store. Black, navy, and white in S–2XL. Don't sync to Shopify yet."*

### 1. Discover the user's store and the Printful provider UUID

```
GET https://api.apparelhub.ai/agents/v1/store
Headers: x-api-key: <key>
```

Read the store named in the prompt out of the response and remember its
`uuid`. If the user has multiple stores and the prompt is ambiguous, ask
which one.

```
GET https://api.apparelhub.ai/agents/v1/membership
```

Read the available merchandise providers from the user's tier metadata
(or hard-code Printful's provider UUID per the skill knowledge if you
have it). Remember the Printful provider UUID.

### 2. Generate the design

```
POST https://api.apparelhub.ai/agents/v1/images/generate
Headers:
  x-api-key: <key>
  Content-Type: application/json
Body:
{
  "prompt": "vector flat illustration saguaro cactus silhouette desert sunset, on pure RGB #00FF00 background, fully saturated bright green, NOT yellow-green or olive",
  "source": "Nano Banana",
  "size": "1024x1024"
}
```

Response gives you `generated_image.uuid` and `generated_image.url`.

### 3. Visually verify the design

Fetch the image URL and inspect it. Specifically:

- Does it look like the design you asked for?
- If there is text in the design, is it spelled correctly?
- Is the background uniformly bright green (`#00FF00`-ish)?

If any answer is no, regenerate. This is the moment to catch problems —
once you create the product, every downstream artifact carries the
mistake.

### 4. Transparency processing

Standard front-print tees need a transparent background. You have two
options:

**Option A — Local processing (if your runtime has any image library)**:
Reduce the design image to RGBA, flood-fill from the corners replacing
matching pixels with alpha 0, sweep enclosed regions of the same color
(letter interiors) and clear those too, pre-multiply remaining
transparent pixels with white RGB so Printful doesn't render black
artifacts. Crop to the tight bounding box. Upload via the transform
endpoint:

```
POST https://api.apparelhub.ai/agents/v1/images/generated/<image_uuid>/transform
Headers:
  x-api-key: <key>
  Content-Type: application/json
Body:
{ "image_data_url": "data:image/png;base64,<base64-of-rgba-png>" }
```

**Option B — Tool call to a transparency-processing endpoint** if your
agent runtime has one.

Either way, the response gives you a NEW image UUID with true alpha.
Use the NEW UUID for the mockup step.

### 5. Mockup generation

BC 3001 is product 71 on Printful. The chest-front placement looks like:

```
POST https://api.apparelhub.ai/agents/v1/merchandise/product/preview
Headers: x-api-key, Content-Type: application/json
Body:
{
  "merchandise_provider_uuid": "<printful provider uuid>",
  "generated_image_uuid": "<NEW image uuid from step 4>",
  "provider_product_ref_id": "71",
  "templates": [
    {
      "provider_ref_id": "front",
      "area_width": 1800,
      "area_height": 2400,
      "width": 1584,
      "height": 1056,
      "top": 312,
      "left": 108,
      "image_url": "<transparent image URL from step 4>"
    }
  ],
  "variant_ids": [4016, 4017, 4018, 4019, 4020]
}
```

Response: `{ "job_uuid": "..." }`. Remember it.

### 6. Poll the mockup job — two-phase wait

```
GET https://api.apparelhub.ai/agents/v1/merchandise/product/preview/<provider_uuid>/job/<job_uuid>
```

Repeat every ~8 seconds. Two conditions BOTH must hold:

- `status == "completed"`
- At least one entry in `previews[]` has a non-null `preview_url`

The gap between "completed" and "preview_url populated" can be 20+
minutes. Don't stop at `completed` alone. If the GET returns HTTP 502,
503, 504, or 429 occasionally, that's transient — retry up to ~5
consecutive failures.

Budget 30 minutes total.

### 7. Visually verify the mockup

Pick the front-view, dark-color preview (best contrast for verification)
and inspect it. Look for chroma-key artifacts, white halos around the
design, design cutoff, wrong orientation. If anything looks wrong, fix
the design and re-mockup. **Do not proceed to product creation with a
broken mockup**, because manufacturing follows the mockup.

### 8. Pick the display image and gallery images

Parse the `previews[]` array. The provider's URL slug includes the color
and angle (e.g. `unisex-staple-t-shirt-black-front-abc.png`).

- `display_image`: prefer a dark-color front shot (high contrast).
- `gallery_images`: one front shot per color, plus the back shots if
  present.

Prefer `preview_url` (our S3 mirror) over `provider_preview_ref_url`
(Printful's CDN).

### 9. Create the product

⚠️ The field names FLIP between mockup and create.

```
POST https://api.apparelhub.ai/agents/v1/product/create
Headers: x-api-key, Content-Type: application/json
Body:
{
  "name": "Saguaro Sunset Tee",
  "description": "Stylized saguaro cactus silhouette against a desert sunset gradient.",
  "generated_image_uuid": "<NEW image uuid from step 4>",
  "preview_job_uuid": "<job uuid from step 5>",
  "provider_uuid": "<printful provider uuid>",
  "product_ref_id": "71",
  "price": 27.99,
  "display_image": "<dark-front preview_url>",
  "gallery_images": ["<front url for each color>", ...],
  "print_data": [
    {
      "provider_ref_id": "front",
      "area_width": 1800,
      "area_height": 2400,
      "width": 1584,
      "height": 1056,
      "top": 312,
      "left": 108,
      "image_url": "<transparent image URL from step 4>"
    }
  ]
}
```

Response: `{ "product": { "uuid": "...", ... } }`. Remember `product.uuid`.

### 10. Add variants — one per color × size

15 variants for 3 colors × 5 sizes. Issue 15 separate calls:

```
POST https://api.apparelhub.ai/agents/v1/product/<product_uuid>/variants
Body: {"name":"Black","price":27.99,"color":"Black","size":"S","provider_variant_id":4016}
```

…and so on for the other 14 variants. Variant IDs come from the catalog
(`references/garment-catalog.md` has the BC 3001 matrix).

There is no batch endpoint. Without all variants, sync to fulfillment
fails with `400 "No valid variants found to sync"`.

### 11. Add to the user's store

```
POST https://api.apparelhub.ai/agents/v1/store/<store_uuid>/products
Body: {"product_uuids": ["<product_uuid>"]}
```

### 12. STOP — ask the user about sync

Per the skill's safety rails, the agent must explicitly ask the user
before syncing to fulfillment or to a sales channel. The product is
created and on the store; sync is the next gate.

Tell the user:

> The product is created. Mockup at `<dark-front preview_url>`. Ready to
> sync to fulfillment (Printful) and/or to Shopify as a draft when you
> say go.

When the user says "sync to fulfillment":

```
POST https://api.apparelhub.ai/agents/v1/store/<store_uuid>/products/<product_uuid>/sync?target=merchandise
```

When the user says "sync to Shopify as a draft":

```
POST https://api.apparelhub.ai/agents/v1/store/<store_uuid>/products/<product_uuid>/sync?target=ecommerce&integration_uuid=<integration_uuid>&listing_state=draft
```

Sync defaults to DRAFT for channels that support it. Only push `active`
when the user explicitly says "publish" or "make it live."

---

## Notes specific to bare-HTTP agents

- **Multipart on the transform endpoint** is the trickiest part. If your
  HTTP capability doesn't natively support multipart, use the JSON data
  URL form (§6c of `api-contract.md`).
- **Two-phase mockup wait** is the longest gate in the flow. Budget 30
  minutes wall-clock with a polite polling interval; surface progress to
  the user.
- **State management is entirely in your reasoning context.** Capture
  every UUID and URL out of each response as you receive it, and pass
  them as literals into the next call. This guide uses placeholders like
  `<product_uuid>` for the same reason.
- **No `.env`, no `~/.claude/`, no `Bash(...)` allowlist** — none of
  those exist in your runtime. The skill is designed to work without
  them.

---

## What if something goes wrong?

`apparelhub/references/error-handling.md` covers the most common
failures:

- 401/403 → key environment mismatch
- 409 with `shopify_auth_revoked` → reconnect in the dashboard
- 400 on `/product/create` → almost certainly a field-name flip
- Stuck mockup → archive and retry

If you're stuck, ask the user. The skill is a knowledge package, not an
oracle.
