# Product Creation Pipeline — Full Detail

The workflow from "user wants a saguaro tee" to a finished, sellable product. Execute the phases IN ORDER. Skipping or reordering a phase produces broken products that look successful but silently fail downstream.

> **Where does the pipeline END?** By default, at **Phase 7 — the product is created, mapped to the user's store, and synced to fulfillment (manufacturable).** Phase 8 (pushing a listing to a Shopify/WooCommerce/Wix storefront) is a SEPARATE, opt-in step. Only do it when the user EXPLICITLY asks to list / publish / sell on a storefront. "Map / add to the store" and "store availability" mean Phase 7 (association + fulfillment) — NOT a sales-channel listing. Don't extend "add it to my store" into a channel sync.

> **Shortcut for the whole build (recommended for automated / scheduled / bounded runs): the `ship_product` MCP tool runs Phases 3–7 in ONE call** — mockup, create, variants, store association, fulfillment sync — with the correct order guaranteed, and only touches a sales channel if you pass `sync_to_channels`. The split primitives (`create_product`, `add_variants`, `sync_to_fulfillment`, `sync_to_channel`) are for interactive/partial flows; if you chain them, follow the exact order in Phases 5→8 below.

**All Agent API calls in this document are shown as plain `curl https://api.apparelhub.ai/agents/v1/...` invocations.** Any HTTP client works equivalently — `requests`, `fetch`, native function-call HTTP, etc. The base URL is the canonical host (`https://api.apparelhub.ai`); see `../../SECURITY.md`. When you see placeholders like `<image_uuid>` or `<job_uuid>`, substitute the value the previous step returned. Your runtime may prompt the first time it expands `$APPARELHUB_API_KEY` — that's the platform's safety control working correctly; approve in context.

---

## Phase 1 — Generate the design image

```bash
curl -sS -X POST "https://api.apparelhub.ai/agents/v1/images/generate" -H "x-api-key: $APPARELHUB_API_KEY" -H "Content-Type: application/json" -d '{
  "prompt": "vector flat illustration saguaro cactus silhouette desert sunset, on pure RGB #00FF00 background, fully saturated bright green, NOT yellow-green or olive, NOT chartreuse",
  "source": "Nano Banana",
  "size": "1024x1024"
}'
```

The extra phrasing on the background is deliberate. AI generators routinely ignore "#00FF00" and produce a yellow-green or olive background instead. When that happens, the keying step in Phase 2 will consume warm design elements (yellow suns, gold details) because they fall inside the tolerance window around the actual background color. The `make_transparent.py` script in Phase 2 has a sanity check that rejects non-#00FF00 backgrounds and tells the agent to regenerate — but it's cheaper to get the right background first.

**Two response shapes (branch on the HTTP status code):**

- **Fast models** (`OpenAI`, `Grok Imagine`, `Flux 1.1 Pro`) return **200** with `{ "generated_image": { "uuid": "...", "url": "..." } }` directly. Save the UUID + url and continue.
- **Slow models** (the **Nano Banana** default, plus `Seedream 4.0/4.5`, `Flux 2 Pro`, `Google Imagen 4`, `Wan 2.7`, `GPT Image 2`) run through an async pipeline and return **202** with `{ "image_uuid": "...", "processing_status": "pending", "generated_image": { ...no url yet... } }`. This avoids the ~29s gateway timeout that used to 504 slow generations. You MUST then poll `GET /agents/v1/images/upload/<image_uuid>/status` until `processing_status` is `completed` (then read `url`) or `failed` (then read `error`).

Nano Banana is the platform default, so **most generations now take the 202 path.** Use the packaged `ah_poll_generation` script. DO NOT hand-roll a `for` loop with `$(...)` command substitution; the expansion check will prompt on every iteration.

```bash
# Fast model: url is already in the 200 response, no polling needed.
# Slow model (202): take image_uuid from the response, then:
ah_poll_generation <image_uuid>
# One status line per poll; on success the LAST line printed is the image url.
# Full status payload saved to /tmp/generation_status.json.
```

Flags: `--timeout SECONDS` (default 600), `--interval SECONDS` (default 5), `--out PATH` (default `/tmp/generation_status.json`), `--max-transient-errors N` (default 5; tolerates 502/503/504/429/network blips while the worker renders). Exit codes: `0` completed (url present), `1` failed/timeout/too-many-transient, `2` no key or bad args.

Save the resulting image UUID (and url) for the rest of the pipeline.

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

Use the bundled helper at `scripts/make_transparent.py` (relative to this skill's base directory). It does border flood-fill + an enclosed-region sweep (so letter holes go transparent), auto-detects the actual chroma color from the corners (AI green is rarely exactly `#00FF00`), writes pre-multiplied white to avoid halos, **auto-crops to the design's tight bounding box** (so downstream sizing reflects the actual design extent, not the AI canvas + transparent margin), and can emit a dark-background preview. It is the single, reviewable entry point for this step — invoke it BY PATH so it stays inside the whitelist (see `settings.recommended.json`); do NOT paste an inline `python3 -c`/heredoc version, which would prompt on every run.

```bash
# Download the generated image (it has a solid green background).
# Substitute the URL the Phase 1 response returned.
curl -sS "https://cdn.apparelhub.ai/<image-path-from-phase-1-response>.png" \
    -o /tmp/design_green.png

# Strip the background -> true RGBA. The skill ships make_transparent.py for
# Claude Code users; if your runtime has its own image library, use that
# instead. Either way the result should be a PNG with true RGBA alpha and
# pre-multiplied-white transparent pixels.
python3 ~/.claude/skills/apparelhub/scripts/make_transparent.py \
    /tmp/design_green.png /tmp/design_transparent.png \
    --preview /tmp/design_preview.jpg
```

The script prints the detected chroma + its euclidean distance from `#00FF00`, the keying stats, the post-crop dimensions, and a `corner alpha [0, 0, 0, 0]` confirmation. Then **look at `/tmp/design_preview.jpg`** before continuing — that's your no-halo, no-leftover-green gate.

### What to do if the chroma sanity check fails (exit code 4)

If the AI ignored the bright-green prompt and produced a yellow-green / olive / muted background, the script REFUSES to key (exit code 4) and prints a regeneration recommendation. Default behavior:

```
chroma SANITY CHECK FAILED
  detected corners: #B5CD57 (distance 207 from #00FF00)
  threshold: --chroma-max-distance 120
```

The right response is to **REGENERATE the design** with a stricter prompt (the failure message includes the suggested phrasing). Do NOT just pass `--force-chroma` — keying against a non-green background with default tolerance will consume any design colors that fall within ±45 of the background, which means yellows, golds, and warm earth tones get eaten.

Pass `--force-chroma` only when:
- You've inspected the design and confirmed it has no warm colors close to the background, OR
- You've also passed `--dominance` (which uses a green-channel-dominates rule instead of a color box and is safer against muted greens), OR
- You're explicitly testing the keying behavior

### Useful flags

- `--dominance` — for muted / desaturated / dark green screens (e.g. corners come back like `#52C06E`, `#95D052`). Uses a "green dominates" test instead of a color box; safer against non-pure-green backgrounds. Bypasses the chroma sanity check.
- `--despill` — neutralize a faint green rim on anti-aliased edges.
- `--chroma 00FF00` — force a specific background color instead of auto-detect. Bypasses the sanity check (you've already told the script what color to key).
- `--tolerance N` — widen/narrow the color-box match (default 45, was 90 in v1.7). Wider tolerance catches more anti-aliased pixels but is more likely to consume design colors.
- `--no-crop` — skip the auto-crop step. NOT recommended — without crop, the design has lots of transparent padding around it, which makes the agent's Phase 3 sizing inaccurate. Use only when you specifically need the original canvas dimensions preserved.
- `--force-chroma` — bypass the non-#00FF00 sanity check.
- `--crop-padding N` — transparent padding kept around the bounding box (default 16). Keeps the corner-alpha-zero check working downstream.

The script also exits non-zero (exit 3) if the corners aren't fully transparent after keying — if that happens, re-run with `--dominance` (and optionally `--despill`).

### Step 2b: Upload the processed bytes via the transform endpoint

(Which is just an upload — NOT a transformation):

```bash
curl -sS -X POST "https://api.apparelhub.ai/agents/v1/images/generated/<original_image_uuid>/transform" -H "x-api-key: $APPARELHUB_API_KEY" \
    -F image=@/tmp/design_transparent.png
```

The `-F image=@...` form sends `multipart/form-data` — curl auto-sets the multipart boundary on `Content-Type`, so don't preset a `Content-Type` header on multipart calls. For HTTP-only agents that can't do multipart from disk, the endpoint also accepts a JSON `{"image_data_url": "data:image/png;base64,..."}` body (see `api-contract.md` §6c).

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
curl -sS "https://api.apparelhub.ai/agents/v1/merchandise/<provider_uuid>/products?fields=provider_ref_id,name,brand" -H "x-api-key: $APPARELHUB_API_KEY"
```

### Step 3b: FETCH the garment's print templates

This gives you `area_width`, `area_height`, and the valid `provider_ref_id` for each print placement. **DO NOT hardcode these dimensions.** They vary per garment.

```bash
curl -sS "https://api.apparelhub.ai/agents/v1/merchandise/<provider_uuid>/product/<product_ref_id>" -H "x-api-key: $APPARELHUB_API_KEY"
```

The response includes `print_templates` (or similar) with each placement's dimensions and `provider_ref_id` (e.g., `"front"`, `"back"`, `"embroidery_chest_left"`, `"default"`).

### Step 3c: CALCULATE design positioning with `ah_pick_dimensions`

Use the packaged `ah_pick_dimensions` script. It opens the Phase-2-cropped design, reads its actual aspect ratio, and computes `(width, height, left, top)` that respects BOTH the area width AND the area height — preventing the design from getting cropped at print time or from rendering as a small chest emblem when you wanted chest-fill.

```bash
ah_pick_dimensions /tmp/design_transparent.png 728 376 --style chest_fill --out /tmp/dimensions.json
```

The script prints JSON to stdout AND writes to `--out`:

```json
{
  "design_path": "/tmp/design_transparent.png",
  "design_size": [664, 527],
  "area_size": [728, 376],
  "style": "chest_fill",
  "width": 413,
  "height": 328,
  "left": 157,
  "top": 48,
  "rationale": "design aspect (1.26) is taller than the available height (area_h=376 minus collar_padding=48), so scaled to fit available_height = 328px; resulting width 413px = 57% of area_width, top=48px (13% of area_height for collar breathing room).",
  "strategy": "height_constrained"
}
```

Read the literal numbers from the output and paste them into the Phase 3 preview API body (and the Phase 4 product create body — they must match).

### Why this beats picking dimensions by hand

The skill used to say "use 80-90% of area_width." That guidance:
1. **Doesn't respect the design's aspect ratio.** A 664×527 design (1.26:1) and a 1024×1024 design (1:1) need different sizing on the same 728×376 (1.94:1) print area, because the design's height overshoots the area's height differently.
2. **Misses that height-overshoot causes Printful to CROP.** v1.7-and-earlier guidance was "OK if height overshoots since it's anchored at top" — that's wrong. Anything outside the print area gets cropped at print time.
3. **Was soft.** Agents routinely picked 60-70% of area_width thinking "that looks fine," producing prints that look like small chest emblems instead of the chest-fill the merchant wanted.
4. **Didn't account for the collar.** v1.8's `chest_fill` set `top=0` (literal top of print area), which on BC 3001 puts the design touching the collar seam. v1.9 reserves 10% of area_height as breathing room by default.

`ah_pick_dimensions` codifies the math AND the constraints (never overshoot area_height, always leave collar breathing room for chest_fill) so the agent can't undershoot on chest-fill OR crowd the collar.

### Style presets

- `chest_fill` (default) — 88% of area_width, scaled to preserve aspect ratio. Reserves 13% of area_height at the top as breathing room between the collar seam and the design (~0.8" on BC 3001 front; tunable with `--collar-padding-pct`). Scales the design DOWN if needed so it fits entirely within the available height (area_h minus collar padding) without crop.
- `chest_emblem` — 35% of area_width, centered both axes. For small badge / logo prints.
- `back_center` — same sizing math as chest_fill but vertically centered. NO collar padding (back placements don't have a collar problem; centering already gives even top/bottom breathing room).
- `all_over` — width=area_width, height=area_height, top=0, left=0. For pillows, doormats, full-bleed designs. See `references/all-over-print.md`.

### Tuning the collar padding

Default 13% of area_height = ~0.8" breathing room on BC 3001 front (728×376 at ~60.7 px/inch). Adjust with `--collar-padding-pct`:

- `0.0` — flush with the print area top edge (v1.8 behavior — designs end up touching the collar, NOT recommended)
- `0.05` — tight (~0.3"), design is more substantial but very close to the collar
- `0.10` — tighter than default (~0.6"), was the v1.9 default
- `0.13` (default) — ~0.8", typical retail chest-print breathing room
- `0.15` — generous (~0.9"), design is smaller but visually anchored well below the collar
- `0.20` — extra generous (~1.2"), design pushed lower toward the mid-chest

For embroidery: tight placement on the chest-left or similar. Use `--style chest_emblem` and a smaller `--fill-ratio` if needed. See `references/embroidery.md` for the 541×541 anorak example.

### Step 3d: Create the preview with the COMPLETE template structure

Paste the LITERAL `width`, `height`, `top`, `left` numbers from `/tmp/dimensions.json` (Step 3c output). Example body using the values from the sample `ah_pick_dimensions` output above (664×527 design on 728×376 print area):

```bash
curl -sS -X POST "https://api.apparelhub.ai/agents/v1/merchandise/product/preview" -H "x-api-key: $APPARELHUB_API_KEY" -H "Content-Type: application/json" -d '{
  "merchandise_provider_uuid": "<provider_uuid>",
  "generated_image_uuid": "<image_uuid>",
  "provider_product_ref_id": "71",
  "templates": [
    {
      "provider_ref_id": "front",
      "image_url": "<image_url>",
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

(Your numbers will differ depending on the design's aspect ratio — always source them from `ah_pick_dimensions`.)

Notes:
- Include ALL variant_ids across ALL colors in ONE preview call (15 IDs for 3 colors × 5 sizes here). The provider returns separate mockups per color in the same job.
- Missing any template field → 404 with `KeyError` or generic Exception from `merchandise.py`. Common cause of "Error building the standard response for product preview." Always pass the full template object.
- The SAME `width`/`height`/`top`/`left` numbers must be used in the Phase 4 product create body's `print_data[0]`. Mismatched dimensions produce inconsistent state between the mockup and the actual print.
- **Fulfillment connection (`store_uuid`, optional):** pass a `store_uuid` to pin
  mockup generation to that store's connection to this provider; omit it to use the
  account's first store connected to the provider. With no connected store at all,
  the platform's shared credentials run (subject to shared rate limits). Passing a
  store that is NOT connected to the requested provider fails with
  `400 provider_store_mismatch` — see `references/error-handling.md` section 2d.
  The response's `connection` block (`{store_uuid, store_name, shared}`, also on the
  job poll) tells you which connection ACTUALLY ran — check `connection.shared`
  before assuming a merchant connection was used.

Returns a `job_uuid`. Mockup generation is **async**. Use the packaged `ah_poll_mockup` script — DO NOT write an inline `for` loop with `$(...)` command substitution; the expansion check will prompt on every iteration.

```bash
ah_poll_mockup <provider_uuid> <job_uuid>
```

The script polls `GET /merchandise/product/preview/<provider_uuid>/job/<job_uuid>` every 8 seconds until the job is `completed` AND at least one preview row has a populated `preview_url` (handles BOTH completion phases — provider render finish AND our S3 ingestion catching up — in one call). It prints a one-line status per poll and saves the final response to `/tmp/preview_job.json`.

Default timeout is 30 minutes. Useful flags:
- `--timeout 600` — shorter cap if you want to fail fast
- `--interval 5` — poll more aggressively
- `--out /tmp/some_other_path.json` — write to a non-default path
- `--min-ready 4` — wait until 4+ previews have `preview_url` (default is 1)

**Note: there is no separate `/preview-job/<job>/previews` listing endpoint to call.** The job-status endpoint above carries the preview rows once they're ingested. Older docs may reference the listing endpoint; it returned 0 rows in the field even after the job endpoint reported preview_url populated. Stick with `ah_poll_mockup` against the job endpoint.

---

## Phase 3.5 — Mockup verification (MANDATORY)

After `ah_poll_mockup` exits 0, **visually inspect at least one mockup** before product creation. Pick a dark-color front URL from `/tmp/preview_job.json` (you can use `ah_pick_provider_url` to extract one), download with curl, and view it.

```bash
# Print the black front URL on stdout (substitute the literal value into the next curl).
ah_pick_provider_url /tmp/preview_job.json black front
# Returns: https://cdn.apparelhub.ai/<uuid>.png

# Download for visual inspection (paste the URL literally — don't capture it in $VAR):
curl -sS -o /tmp/mockup_check.png "https://cdn.apparelhub.ai/<the-uuid-from-above>.png"
```

Check for:
- Design renders correctly (not cut off, not distorted)
- Text is legible and spelled correctly
- No white halos around transparent edges
- No checkerboard artifacts where transparency should be
- Color contrast is acceptable on the chosen garment

If anything looks wrong, FIX the design and re-mockup before continuing. Never ship a broken mockup to product creation — manufacturing follows the mockup.

---

## Phase 4.0 — Pick `display_image` + build `gallery_images` from preview rows

Use the packaged `ah_classify_previews` script with `--recommend` to do this in one call:

```bash
ah_classify_previews /tmp/preview_job.json --recommend /tmp/picks.json
```

This prints a `(COLOR, ANGLE, URL)` table for every preview row AND writes `/tmp/picks.json` with the agent's recommended `display_image` and a curated `gallery_images` list ready to paste literally into the product create body.

`/tmp/picks.json` looks like:

```json
{
  "display_image": "https://.../black-front-best.png",
  "gallery_images": [
    "https://.../black-front....png",
    "https://.../navy-front....png",
    "https://.../white-front....png",
    "https://.../black-back....png",
    "https://.../navy-back....png"
  ],
  "rationale": "Picked black front for dark-color contrast; 3 front + 3 back in gallery, darkest first."
}
```

**Read those URLs from `/tmp/picks.json` and paste them as LITERAL strings into the Phase 4 product create body.** Don't capture them in shell variables — paste the URL text directly.

### What the recommendation algorithm does

- `display_image`: front-view of the darkest available color (black > midnight > navy > charcoal > forest > dark > olive > burgundy > maroon, then non-dark colors). Prefers our S3 mirror (`preview_url`) over the provider CDN.
- `gallery_images`: one front-view per unique color (darkest first, matching `display_image`'s color), then one back-view per unique color in the same order. Capped at 10 entries.

### When to override the recommendation

If the merchant has a specific color preference for the storefront thumbnail ("show the white version as the main image"), use `ah_pick_provider_url /tmp/preview_job.json white front` to extract that URL and pass it as `display_image` instead. The recommendation is a sensible default, not a constraint.

### What if `--recommend` returned `display_image: null`?

Means no preview rows matched the front/back filename pattern. Run `ah_classify_previews /tmp/preview_job.json` without `--recommend` to see the raw rows — provider may be using a non-standard slug. Fall back to picking one manually from the table.

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
curl -sS -X POST "https://api.apparelhub.ai/agents/v1/product/create" -H "x-api-key: $APPARELHUB_API_KEY" -H "Content-Type: application/json" -d '{
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
      "width": 413,
      "height": 328,
      "top": 48,
      "left": 157
    }
  ]
}'
```

**The `width`/`height`/`top`/`left` values MUST match what was sent to the Phase 3 preview call.** Source them from `/tmp/dimensions.json` (output of `ah_pick_dimensions` in Step 3c). Mismatch produces a product whose mockup shows one placement but whose actual print uses a different placement.

### `print_data` vs `display_image` — what each is for

- **`print_data[].image_url` is the RAW DESIGN URL** (the transparent image from Phase 2). This is what Printful uses to actually PRINT. It is NOT a mockup. Never put a mockup URL in `print_data` — that ships shirt-on-a-shirt.

- **`display_image` and `gallery_images` are MOCKUP URLs** (from the preview job). These are what customers see on the product page. Never put the raw design URL here — that shows the design on a green background instead of on a shirt.

If you OMIT `display_image` and `gallery_images`, the platform picks them automatically using the same logic in Phase 4.0. Explicit is preferred when you want a specific dark-color thumbnail.

Returns the new product `uuid`.

---

## Phase 5 — Add variants

Variants are created ONE AT A TIME (no batch endpoint). The product is unsyncable until variants exist.

> ⚠️ **Read the garment's REAL colors/sizes before you build the variant list — do NOT hardcode `S/M/L/XL/2XL`.** Sizes are matched EXACTLY. Tees/tanks/hoodies use `S…2XL`, but caps, beanies, phone cases, water bottles, bags, socks, blankets, glasses, towels etc. are frequently **one-size** or use different labels (`One size`, `OSFA`, `S/M`, `L/XL`, a device model, a volume). Requesting apparel sizes on a one-size garment resolves to **ZERO variants** and — via the split-primitive `add_variants` — used to ship a 0-variant product silently. Always fetch the actual matrix first: `curl -sS "https://api.apparelhub.ai/agents/v1/merchandise/<provider_uuid>/product/<product_ref_id>"` (or the `get_garment_details` MCP tool) and build the variant list from the colors/sizes it returns. If you add variants and get **0 added / an error naming the available options**, that's this — you assumed the wrong size vocabulary.

Issue 15 separate POSTs, one per variant. There is no batch endpoint. If you're driving this from a tool-calling agent, that's 15 separate function calls; from a script, 15 separate `curl` invocations:

```bash
# One curl call per variant. Substitute the real product UUID and the real
# product UUID from Phase 4's response wherever you see <product_uuid>.
curl -sS -X POST "https://api.apparelhub.ai/agents/v1/product/<product_uuid>/variants" -H "x-api-key: $APPARELHUB_API_KEY" -H "Content-Type: application/json" -d '{"name":"Black","price":27.99,"color":"Black","size":"S","provider_variant_id":4016}'
curl -sS -X POST "https://api.apparelhub.ai/agents/v1/product/<product_uuid>/variants" -H "x-api-key: $APPARELHUB_API_KEY" -H "Content-Type: application/json" -d '{"name":"Black","price":27.99,"color":"Black","size":"M","provider_variant_id":4017}'
curl -sS -X POST "https://api.apparelhub.ai/agents/v1/product/<product_uuid>/variants" -H "x-api-key: $APPARELHUB_API_KEY" -H "Content-Type: application/json" -d '{"name":"Black","price":27.99,"color":"Black","size":"L","provider_variant_id":4018}'
curl -sS -X POST "https://api.apparelhub.ai/agents/v1/product/<product_uuid>/variants" -H "x-api-key: $APPARELHUB_API_KEY" -H "Content-Type: application/json" -d '{"name":"Black","price":27.99,"color":"Black","size":"XL","provider_variant_id":4019}'
curl -sS -X POST "https://api.apparelhub.ai/agents/v1/product/<product_uuid>/variants" -H "x-api-key: $APPARELHUB_API_KEY" -H "Content-Type: application/json" -d '{"name":"Black","price":27.99,"color":"Black","size":"2XL","provider_variant_id":4020}'
# ...repeat for Navy (8495-8499) and White (4012-4015, 4011)
```

Look up the right variant IDs via:
```bash
curl -sS "https://api.apparelhub.ai/agents/v1/merchandise/<provider_uuid>/product/71" -H "x-api-key: $APPARELHUB_API_KEY"
```

Or use the quick-reference variant tables in `references/garment-catalog.md`.

---

## Phase 6 — Associate the product with the user's store ("map to store", part 1)

This + Phase 7 together are what a merchant means by **"map / add the product to the store"** or **"store availability."** Phase 6 registers the product under the store; Phase 7 makes it manufacturable. Neither creates a storefront listing.

```bash
# List stores first
curl -sS "https://api.apparelhub.ai/agents/v1/store" -H "x-api-key: $APPARELHUB_API_KEY"

# Then add the product (substitute literal UUIDs)
curl -sS -X POST "https://api.apparelhub.ai/agents/v1/store/<store_uuid>/products" -H "x-api-key: $APPARELHUB_API_KEY" -H "Content-Type: application/json" -d '{"product_uuids": ["<product_uuid>"]}'
```

---

## Phase 7 — Sync to fulfillment ("map to store", part 2) — the normal END of the pipeline

```bash
curl -sS -X POST "https://api.apparelhub.ai/agents/v1/store/<store_uuid>/products/<product_uuid>/sync?target=merchandise" -H "x-api-key: $APPARELHUB_API_KEY"
```

This creates the product on the fulfillment provider's side (Printful/Printify) so it's manufacturable. **Association (Phase 6) MUST happen first** — this sync is addressed under the store's product list. Together, Phases 6+7 are "the product is mapped to the store." **For most requests — including "map it to the Agent Printful store", "add it to my store" — you STOP HERE.** The product is created, on the store, and sellable.

> **MCP-tool mapping (if you're driving the platform via the ApparelHub MCP tools, not raw curl):**
> - **`ship_product`** = Phases 3–7 in one call (mockup → create → variants → associate → fulfillment sync). Preferred, especially for automated runs.
> - **`sync_to_fulfillment(product_uuid, store_uuid)`** = Phase 6 + Phase 7 combined (it associates the product with the store AND syncs to fulfillment). This is the "map to store" step and the REQUIRED precursor to any channel sync.
> - **`sync_to_channel(...)`** = Phase 8 below (sales channel), opt-in only.

---

## Phase 8 — (OPT-IN) Sync to a sales channel — ONLY when the user asks to list/publish on a storefront

**Do NOT do this step unless the user EXPLICITLY asked to list, publish, or sell the product on a storefront (Shopify, WooCommerce, Wix, Etsy).** "Map to the store" / "add to the store" / "store availability" do NOT mean this — they mean Phases 6–7. Pushing to a sales channel when the user only asked to map to the store is over-reach (it happened in an automated task and created unwanted WooCommerce drafts).

If (and only if) they asked to list it on a storefront:

```bash
curl -sS -X POST "https://api.apparelhub.ai/agents/v1/store/<store_uuid>/products/<product_uuid>/sync?target=ecommerce&integration_uuid=<integration_uuid>" -H "x-api-key: $APPARELHUB_API_KEY"
```

Fulfillment (Phase 7) MUST have succeeded first — the storefront listing attaches to the fulfillment SKU. Sync to multiple channels by calling this once per integration UUID.

### Default to DRAFT, not live

For channels that support a draft state (Etsy, Shopify), prefer pushing as a draft first. Tell the merchant:
> "I've synced as drafts so you can review on your storefront before going live. To publish, flip the listing in your channel admin or re-run sync with `?listing_state=active`."

Only push as `active` if the user EXPLICITLY says "make it live" or "publish it." The cost of a too-eager publish (typo'd description in front of real customers) is much higher than the cost of one extra step.

---

## Scheduled / reconciler builds (automated, unattended runs)

When a build loop runs on a schedule (a cron/trigger firing every hour, a batch that rebuilds a
catalog), design it as a **desired-state reconciler**, not a one-shot builder. This is what keeps
an unattended run from leaving gaps or stalling, and lets it auto-recover after you fix a bug.

**Reconcile, don't self-terminate.** Each run: read the ACTUAL products, compare to the desired
plan, and (re)build anything missing or unmapped. When everything is present, report "all present —
idle" and stop for that run, but do NOT delete the trigger. Deleting the trigger is what prevents
recovery — if you later fix the pipeline and delete a bad product to force a rebuild, there has to
be a next run to rebuild it. Stop the loop by deleting the trigger manually (or lowering its cadence)
when the work is truly done, not automatically on first completion.

**Deletion is the rebuild signal.** The "done" check should be presence of the named product mapped
to its store. So the operator's workflow to fix products that came out wrong is: fix + deploy the
MCP/skill → DELETE the wrong products → the next run rebuilds them, correctly, with the fixed
pipeline. No product is left as a gap.

**Never STALL on one un-buildable item.** If an item can't build this run (a genuine error, or a
design that needs regenerating), leave it un-built, report it as "pending: <reason>", and let the
NEXT run retry it — do not let one item block the rest of the run or the loop. Auto-recoverable
conditions (low resolution, a tinted-green key, a wrong-size variant guess) are handled by the tools
and should not defer an item at all (see `error-handling.md`). Only an explicitly un-supported item
(e.g. a garment type you're deliberately skipping) is a permanent "count-as-done" deferral.

**Idempotency.** A present-and-mapped item is skipped; a product that exists but isn't mapped gets
mapped (`sync_to_fulfillment`), never duplicated. Match products by a stable name you control.
