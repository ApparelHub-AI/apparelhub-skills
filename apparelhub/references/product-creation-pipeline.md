# Product Creation Pipeline — Full Detail

The 7-phase workflow from "user wants a saguaro tee" to "product is live on their Shopify store." Execute the phases IN ORDER. Skipping or reordering a phase produces broken products that look successful but silently fail downstream.

**All Agent API calls in this document use the `ah_curl` wrapper** (see `SKILL.md` section 1). When you see `ah_curl METHOD /agents/v1/...` below, invoke via the full path `~/.claude/skills/apparelhub/scripts/ah_curl ...` (or the bare `ah_curl` if the user has the scripts dir on PATH). When you see placeholders like `<image_uuid>` or `<job_uuid>`, substitute the LITERAL value from the previous step's response — never a shell variable.

---

## Phase 1 — Generate the design image

```bash
ah_curl POST /agents/v1/images/generate -d '{
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
- **`POST /images/generate` ALSO supports img2img edit** when the user wants to iterate on an existing design — pass `source_image_uuid` (gallery) or `images=@...` (upload). Only Nano Banana and OpenAI support edit mode. See section 5b in design-rules.md for the request shape + field-name gotchas.

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

### Step 2a: Local processing with the packaged script

Use the bundled helper at `scripts/make_transparent.py` (relative to this skill's base directory). It does border flood-fill + an enclosed-region sweep (so letter holes go transparent), auto-detects the actual chroma color from the corners (AI green is rarely exactly `#00FF00`), writes pre-multiplied white to avoid halos, and can emit a dark-background preview. It is the single, reviewable entry point for this step — invoke it BY PATH so it stays inside the whitelist (see `settings.recommended.json`); do NOT paste an inline `python3 -c`/heredoc version, which would prompt on every run.

```bash
# Download the generated image (it has a solid green background).
# Use the LITERAL URL from Phase 1's response — don't store it in a shell var.
curl -sS "https://apparelhub-production-user-generated-public-objects.s3.amazonaws.com/<literal-image-path>.png" \
    -o /tmp/design_green.png

# Strip the background -> true RGBA. Invoke make_transparent.py by literal path
# (the allowlist pattern is `Bash(python3 *apparelhub/scripts/make_transparent.py *)`
# so any path ending in apparelhub/scripts/make_transparent.py matches).
python3 ~/.claude/skills/apparelhub/scripts/make_transparent.py \
    /tmp/design_green.png /tmp/design_transparent.png \
    --preview /tmp/design_preview.jpg
```

It auto-detects the chroma and prints `corner alpha [0, 0, 0, 0] (want all 0)` plus a transparency %. Then **look at `/tmp/design_preview.jpg`** before continuing — that's your no-halo, no-leftover-green gate.

Useful flags:
- `--dominance` — for muted / desaturated / dark green screens (e.g. corners come back like `#52C06E`, `#95D052`). Uses a "green dominates" test instead of a color box; reach for this if the default leaves green fringe or the corner-alpha warning fires.
- `--despill` — neutralize a faint green rim on anti-aliased edges.
- `--chroma 00FF00` — force a specific background color instead of auto-detect.
- `--tolerance N` — widen/narrow the color-box match (default 90).

The script exits non-zero and warns if the corners aren't fully transparent — if that happens, re-run with `--dominance` (and optionally `--despill`).

### Step 2b: Upload the processed bytes via the transform endpoint

(Which is just an upload — NOT a transformation):

```bash
ah_curl POST /agents/v1/images/generated/<original_image_uuid>/transform \
    -F image=@/tmp/design_transparent.png
```

`ah_curl` detects the `-F` flag and skips the default `Content-Type: application/json` so curl sets the multipart boundary correctly.

Returns a NEW image UUID + URL with true RGBA transparency. **Use the NEW UUID for Phase 3 onwards.**

### Phase 2 failure modes worth recognizing

The script already handles the first three automatically — they're listed so you recognize them if you ever process an image by hand:

- **Letter loops not transparent.** The inside of B, e, d, M, a, etc. A plain border flood-fill only reaches connected exterior regions. The script's enclosed-region sweep clears these (disable only with `--keep-enclosed`).
- **White halos around edges.** Caused by skipping pre-multiplication. The script writes cleared pixels as `(255, 255, 255, 0)` so Printful's flatten-against-white leaves no dark rim.
- **Faint green ring around the silhouette.** Anti-aliased edges just outside the match window. Add `--despill`, and/or switch to `--dominance`.
- **Checkerboard pattern visible on the mockup.** The AI baked a fake checkerboard into RGB pixels instead of leaving a solid background — this is a *generation* failure, not a Phase 2 one. Regenerate the design with a clean solid green background; no amount of keying fixes baked-in checkerboard.

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
ah_curl GET /agents/v1/merchandise/<provider_uuid>/products?fields=provider_ref_id,name,brand
```

### Step 3b: FETCH the garment's print templates

This gives you `area_width`, `area_height`, and the valid `provider_ref_id` for each print placement. **DO NOT hardcode these dimensions.** They vary per garment.

```bash
ah_curl GET /agents/v1/merchandise/<provider_uuid>/product/<product_ref_id>
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
ah_curl POST /agents/v1/merchandise/product/preview -d '{
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
ah_curl GET /agents/v1/merchandise/product/preview/<provider_uuid>/job/<job_uuid>
```

---

## Phase 3.5 — Mockup verification (MANDATORY)

When the job status is `completed`, **DO NOT immediately proceed to product creation.** The pipeline has TWO completion phases:

1. Job status = `completed` means the provider's render job finished, BUT
2. The `preview_url` on each preview row may still be NULL — that's our S3 ingestion catching up. Can take 20+ minutes.

**Poll until at least one preview has a non-null `preview_url`:**

```bash
ah_curl GET /agents/v1/merchandise/product/preview-job/<job_uuid>/previews
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
ah_curl GET /agents/v1/merchandise/product/preview-job/<job_uuid>/previews
# Parse the response JSON in your reasoning context. Don't shove it into a
# shell variable — you'll need to reference individual preview URLs literally
# in the product create body anyway.
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
ah_curl POST /agents/v1/product/create -d '{
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

**Do NOT use a shell for-loop with `$vid`** — that triggers a prompt on every iteration. Issue separate `ah_curl` calls with LITERAL variant IDs:

```bash
# One ah_curl call per variant, literal IDs substituted. Substitute the real
# product UUID from Phase 4's response wherever you see <product_uuid>.
ah_curl POST /agents/v1/product/<product_uuid>/variants -d '{"name":"Black","price":27.99,"color":"Black","size":"S","provider_variant_id":4016}'
ah_curl POST /agents/v1/product/<product_uuid>/variants -d '{"name":"Black","price":27.99,"color":"Black","size":"M","provider_variant_id":4017}'
ah_curl POST /agents/v1/product/<product_uuid>/variants -d '{"name":"Black","price":27.99,"color":"Black","size":"L","provider_variant_id":4018}'
ah_curl POST /agents/v1/product/<product_uuid>/variants -d '{"name":"Black","price":27.99,"color":"Black","size":"XL","provider_variant_id":4019}'
ah_curl POST /agents/v1/product/<product_uuid>/variants -d '{"name":"Black","price":27.99,"color":"Black","size":"2XL","provider_variant_id":4020}'
# ...repeat for Navy (8495-8499) and White (4012-4015, 4011)
```

Look up the right variant IDs via:
```bash
ah_curl GET /agents/v1/merchandise/<provider_uuid>/product/71
```

Or use the quick-reference variant tables in `references/garment-catalog.md`.

---

## Phase 6 — Associate the product with the user's store

```bash
# List stores first
ah_curl GET /agents/v1/store

# Then add the product (substitute literal UUIDs)
ah_curl POST /agents/v1/store/<store_uuid>/products -d '{"product_uuids": ["<product_uuid>"]}'
```

---

## Phase 7 — Sync to fulfillment AND sales channels

Sync targets are different depending on what you're syncing to.

### Fulfillment (Printful/Printify) — REQUIRED FIRST

```bash
ah_curl POST /agents/v1/store/<store_uuid>/products/<product_uuid>/sync?target=merchandise
```

This creates the product on the fulfillment provider's side. MUST succeed before ecommerce sync — Shopify/Etsy/etc. need the fulfillment SKU to attach.

### Ecommerce (Shopify, Etsy, WooCommerce, Wix)

```bash
ah_curl POST /agents/v1/store/<store_uuid>/products/<product_uuid>/sync?target=ecommerce&integration_uuid=<integration_uuid>
```

Sync to multiple channels by calling this once per integration UUID.

### Default to DRAFT, not live

For channels that support a draft state (Etsy, Shopify), prefer pushing as a draft first. Tell the merchant:
> "I've synced as drafts so you can review on your storefront before going live. To publish, flip the listing in your channel admin or re-run sync with `?listing_state=active`."

Only push as `active` if the user EXPLICITLY says "make it live" or "publish it." The cost of a too-eager publish (typo'd description in front of real customers) is much higher than the cost of one extra step.

Done — the product is now synced to the user's storefront in draft form.
