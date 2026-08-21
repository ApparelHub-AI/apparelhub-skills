# Design Rules

Universal rules that apply to ANY design you generate via ApparelHub. Read this before Phase 1 of any new product.

---

## 1. NEVER generate apparel-as-image

The image IS the design that goes ON the product. The garment is the medium, not the subject.

| ❌ Wrong | ✅ Right |
|---|---|
| "A t-shirt with a saguaro cactus on it" | "A saguaro cactus silhouette illustration" |
| "Mockup of a hoodie with mountains" | "Stylized mountain range illustration" |
| "A coffee mug with a cat design" | "Sleeping cat illustration in vintage line-art" |

If the user prompts you with "make me a t-shirt with X", REPHRASE silently before sending to the image API. Generate the design, then put it on the product in Phase 3.

---

## 2. The "don't name the product in the prompt" trap

AI image generators interpret product names too literally. Saying "luggage tag" in the prompt produces a *picture of a luggage tag* — chamfered corners, faux strap hole, ornamental edges — which then prints on a real luggage tag and produces image-on-top-of-image artifacts.

This generalizes. NEVER include the product's literal name in the prompt:

| Product | ❌ Avoid in prompt | ✅ Use instead |
|---|---|---|
| Luggage tag | "luggage tag design" | "flat luxury monogram emblem on burgundy" |
| Pillow | "pillow design" | "flat all-over pattern, edge-to-edge color" |
| Doormat | "doormat design" | "flat landscape graphic, horizontal text, edge-to-edge" |
| T-shirt | "t-shirt design" | "isolated chest-print graphic" (plus the transparency phrasing below) |
| Phone case | "phone case design" | "flat back-print graphic with [color] fill edge-to-edge" |
| Mug | "mug design" / "coffee cup design" | "wraparound graphic strip" or "centered illustration on solid [color]" |

**Diagnostic shape**: if the AI output looks like a shrunken version of the FINAL PRODUCT (has the product's outline, hardware like straps/holes/buttons, decorative edges that match the product's physical edges), the prompt was too literal. Rewrite to describe what's PRINTED ON the product, not the product itself, and regenerate.

---

## 3. Transparent backgrounds — ALWAYS prompt for solid bright green

AI image models cannot produce true transparency. They either render white pixels or bake a fake checkerboard pattern into the RGB pixels. When you later try to remove the background, the result is messy.

**Always prompt for a solid contrasting background — bright green `#00FF00`** — and strip it locally in Phase 2:

```
...on solid bright green background #00FF00
```

Why green specifically:
- Distinct from any natural design content (almost no apparel design legitimately includes pure `#00FF00`)
- High contrast against anti-aliased design edges
- Flood-fills cleanly with no ambiguity between background and design pixels

**Pick a background that CONTRASTS with your subject.** The background is removed by matching that colour, so any part of the artwork sharing it is removed too. A green dragon on a green screen keys the dragon away. Use one of three: `#00FF00` (default), `#FF00FF` when the subject plausibly contains green, `#0000FF` when it contains magenta or pink as well. Pass your choice as `background_color` on `/images/generate`, and make sure the prompt names the same colour — the generator only ever sees the prompt.

The actual keying is done in Phase 2 by the bundled `scripts/make_transparent.py` — see `references/product-creation-pipeline.md`. Note the AI rarely returns *exactly* `#00FF00` (corners often come back muted, e.g. `#52C06E`); the script auto-detects the real corner color, so don't assume pure green.

### The platform now prepares placed designs automatically

Text-to-image generations intended for a placed print are keyed to transparency **server side, at generation time**. The design you get back is the prepared one, and its `print_ready` block on the generate response (and on the async status poll) says what was done:

| `print_ready` | Meaning | What you do |
|---|---|---|
| `applied: true` | Background removed. | Nothing. Do NOT key it again — `process_transparency` will refuse with `already_transparent`. |
| `reason: all_over_intent` | Left opaque on purpose. | Nothing. This is correct for full-bleed. |
| `reason: subject_consumed` | The artwork shared its background colour. | Generate again with a different `background_color`. |
| `reason: no_background_found` / `chroma_not_green` | Could not key it. | Check the mockup before creating the product; `process_transparency` with an explicit `--chroma`, or regenerate. |

**This does not make `process_transparency` obsolete.** It still applies to designs you UPLOADED (never auto-prepared), designs generated before this shipped, and any design where auto-prepare refused. Read `print_ready.applied` rather than assuming either way.

For all-over-print products (pillows, doormats, AOP tees, luggage tags): SKIP this rule. Those need the design to cover edge-to-edge including the background. See `references/all-over-print.md`.

For embroidery: same rule applies — transparent backgrounds work (the bare garment fabric shows through where the design is transparent). See `references/embroidery.md`.

---

## 3b. An opaque background prints as a rectangle — check `design_check`

**Any** design with an opaque background, placed on a garment, prints as a solid coloured rectangle. Not just an un-keyed green screen: an uploaded JPEG, a photo, a design on a grey card. This is the single most common way a product ships visibly broken.

The mockup poll (`GET /merchandise/product/preview/{provider}/job/{job}`) and the preview-jobs listing return a **`design_check`** block when the design behind that mockup will do this. It is absent when there is nothing to say, so its presence IS the finding:

```json
"design_check": {
  "code": "opaque_background",
  "severity": "warning",
  "background_state": "opaque_box",
  "message": "This design has a solid background, so it will print as a coloured rectangle...",
  "next": { "action": "remove_background", "image_uuid": "..." }
}
```

`ship_product` and `create_product` carry it through as a warning, so an unattended run sees it **before** the product is created. Fix it with `process_transparency` (or `POST /images/generated/{uuid}/remove-background`, which costs no generation quota), then **render the mockup again** — the previews you are holding were rendered from the old design.

**It is gated to PLACED prints only.** A full-bleed / all-over design is supposed to be opaque edge to edge, so it is never flagged, and you must not "fix" one. Check `print_style` before acting on anything you infer yourself.

Designs are reported as one of four `background_state` values: `transparent` (ready), `opaque_box` (will print as a rectangle), `opaque_varied` (opaque but a photograph, with no flat border to remove, so removing a background is the WRONG move), and `unknown` (not inspected; say nothing).

---

## 4. Verify text in designs with vision tools BEFORE Phase 3

AI image models routinely misspell. If the user asked for "STAY WILD" and the image renders "STAY WLID", that error propagates through the mockup into the product into the customer's hands.

**Always run a vision check** on Phase 1 output if the design contains text. If anything is misspelled, regenerate before generating the mockup.

Provider ranking for text accuracy:
1. **Nano Banana** (best)
2. Seedream 4.0
3. Seedream 4.5
4. Flux 1.1 Pro
5. OpenAI (worst — avoid for text)

If multiple regenerations fail to produce correct text, switch sources before increasing prompt verbosity. Some models just can't do text reliably.

> **The same instinct applies when a model REFUSES a prompt on content grounds** (`error_code: content_blocked`): change the model, not the wording. Content guards are provider-specific, so a prompt one provider refuses another routinely renders. Reword at most twice, then cycle models; only `content_blocked_all_models` means it is genuinely time to give up on that design. Full protocol: `error-handling.md` §2e.6.

---

## 5. AI source selection — which model for which job

Pass the source as the human-readable NAME string, not a UUID.

| Type of design | Recommended source |
|---|---|
| Photorealistic, exact prompt matching | `Nano Banana` or `Seedream 4.5` |
| Design with text (slogans, brand names, monograms) | `Nano Banana` (best) → `Seedream 4.0` (second) |
| Abstract / geometric / shapes / colors | `OpenAI` |
| Lifestyle / nature / animals | `Nano Banana`, `Seedream 4.5`, `Google Imagen 4` |
| Cinematic / mood-heavy / atmospheric | `Flux 1.1 Pro` |
| Vector flat illustration (silhouettes, line art) | `Nano Banana` or `Seedream 4.5` |

When in doubt, default to `Nano Banana` — it's the most consistent across categories.

---

## 5b. Generating vs editing — `POST /images/generate` is BOTH endpoints

`POST /agents/v1/images/generate` is overloaded. Same endpoint, same auth, but the **request shape** determines whether you're doing text-to-image OR img2img editing.

**Async for slow models (202 + poll), applies to every mode below.** `generate` returns **200 with the image url** only for the one fast synchronous model (`Grok Imagine`), but **202 with an `image_uuid` and `processing_status: pending` (no url yet)** for every slow model (the **Nano Banana** default, plus `OpenAI`, `Seedream 4.0/4.5`, `Flux 1.1 Pro`, `Flux 2 Pro`, `Google Imagen 4`, `Wan 2.7`, `GPT Image 2`): the backend routes those through an async pipeline to dodge the ~29s gateway timeout. On a 202, poll `GET /agents/v1/images/upload/<image_uuid>/status` until `processing_status` is `completed` (read `url`) or `failed` (read `error`), or just run the packaged `ah_poll_generation <image_uuid>` helper. Nano Banana is the default, so most generations take the 202 path. **This applies to img2img EDITS too**: a slow-model edit also returns **202 + `image_uuid`** to poll (only `Grok Imagine` edits synchronously). Full poll contract: `product-creation-pipeline.md` Phase 1.

### Three modes

| Mode | Use when… | Request shape |
|---|---|---|
| **Text-to-image** | Generating a new design from scratch | JSON: `{"prompt": "...", "source": "...", "size": "..."}` |
| **Img2img via gallery** | User says "edit this existing design", "make the cat smug", "use this as a starting point". The source image already lives in the user's apparelhub gallery. | JSON: `{"prompt": "...", "source_image_uuid": "<uuid>", "additional_image_uuids": ["<uuid2>", ...]}` |
| **Img2img via upload** | User uploads a fresh image from their machine OR a Phase 2 transparent-keyed file. | multipart: `prompt=...`, `source=...`, `size=...`, `images=@/tmp/x.png` (or `image=@...` for single) |

The same `source` and `size` parameters apply to all three modes. `additional_image_uuids` (gallery) and additional `images=@...` fields (multipart) enable multi-image reference — combine up to ~5 source images in one edit.

### Field name gotchas

- **`source_image_uuid`** — NOT `image_uuid`, NOT `source_uuid`, NOT `reference_uuid`. The endpoint silently treats the wrong field as missing and falls back to text-to-image mode, OR throws a generic "unexpected system error" depending on what else was passed. If your agent gets a 500 with no useful body, double-check this field name first.
- **`additional_image_uuids`** — array of UUIDs. Plural. NOT `reference_image_uuids` or `extra_image_uuids`.
- **`images=@...`** (multipart) — plural. The endpoint also accepts `image=@...` (singular) for backward compat with single-image uploads, but `images=@...` is the canonical form.
- All UUIDs must be designs the user owns (filtered by `author_id`). Cross-user references fail with `Source image not found or access denied`.

### Source compatibility — img2img edit works on every source EXCEPT Imagen 4

Most models support img2img edit now. The OpenAI-backed sources (`OpenAI` = gpt-image, `GPT Image 2` = gpt-image-2) and the Replicate models `Seedream 4.0/4.5`, `Flux 2 Pro`, `Grok Imagine`, `Wan 2.7` all do. Multi-reference (several source images in one edit) works on the array-input models: `Nano Banana`, `OpenAI`, `GPT Image 2`, `Seedream 4.0/4.5`, `Flux 2 Pro`, `Wan 2.7`. The single-image editor is `Grok Imagine` (plus the OpenAI-backed sources with one image). **Two sources do NOT edit:** `Google Imagen 4` (text-to-image only) and `Flux 1.1 Pro` (its img2img is Flux Redux — a composition/style *variation*, not an instruction-editor, so it is not offered for editing). An edit request on a non-editor returns a clean **400**, not a 500. **Slow-model edits are ASYNC (202 + poll), same as generation** — see §5b; only `Grok Imagine` edits synchronously.

| Source | Text-to-image | Img2img edit | Multi-image |
|---|---|---|---|
| Nano Banana | ✅ | ✅ | ✅ (best at character consistency) |
| OpenAI | ✅ | ✅ | ✅ |
| GPT Image 2 | ✅ | ✅ | ✅ |
| Seedream 4.0 | ✅ | ✅ | ✅ (up to 10 refs) |
| Seedream 4.5 | ✅ | ✅ | ✅ (up to 14 refs) |
| Flux 1.1 Pro | ✅ | ❌ (Redux, not editing) | ❌ |
| Flux 2 Pro | ✅ | ✅ | ✅ (up to 8 refs) |
| Grok Imagine | ✅ | ✅ | ❌ (single reference) |
| Wan 2.7 | ✅ | ✅ | ✅ (up to 9 refs) |
| Google Imagen 4 | ✅ | ❌ 400 | ❌ (text-to-image only) |

If the user wants edit and you'd normally reach for Seedream for the text accuracy, switch to **Nano Banana** for the edit step. Nano Banana is also the best at character/style consistency across a multi-image edit sequence — perfect when iterating on a series.

### Worked example — "edit this Victorian etching to make the cat smug"

```bash
# Find the source image UUID in the user's gallery first.
curl -sS "https://api.apparelhub.ai/agents/v1/images/generated?limit=20&sort=newest" -H "x-api-key: $APPARELHUB_API_KEY"
# Pick the UUID of the design you want to edit. Substitute it literally below.

curl -sS -X POST "https://api.apparelhub.ai/agents/v1/images/generate" -H "x-api-key: $APPARELHUB_API_KEY" -H "Content-Type: application/json" -d '{
  "prompt": "Same Victorian etching of a cat, but with a deeply smug, self-satisfied expression. Whiskers held high. Faintly amused eyes. Keep all other composition elements identical (the moth, the gilt frame, the ornate background).",
  "source": "Nano Banana",
  "source_image_uuid": "abc-123-def-456",
  "size": "1024x1024"
}'
```

Response shape is identical to text-to-image: `{"generated_image": {"uuid": "...", "url": "..."}}`. The new image is a fresh row in the gallery, linked to the source via `source_image_id` so it shows up under the `?edited=true` filter on the listing endpoint.

### Multi-image edit (combine reference images)

```bash
# "Put the character from image A wearing the outfit from image B"
curl -sS -X POST "https://api.apparelhub.ai/agents/v1/images/generate" -H "x-api-key: $APPARELHUB_API_KEY" -H "Content-Type: application/json" -d '{
  "prompt": "The character from the first image, wearing the outfit from the second image, full body, clean white background.",
  "source": "Nano Banana",
  "source_image_uuid": "<character-uuid>",
  "additional_image_uuids": ["<outfit-uuid>"],
  "size": "1024x1024"
}'
```

Nano Banana handles this best (up to 9 reference images on the wider Replicate-routed equivalent, but the agent API caps at the platform-supported set). OpenAI also works for 2-3 image combinations.

### When the user says "iterate on this"

Default to img2img-via-gallery mode (mode 2 in the table above). It's the cheapest in tokens (no upload), preserves the lineage in the gallery, and lets the user re-target their next edit at either the original OR the latest iteration. Confirm with the user which design they want to iterate on if there are multiple recent candidates.

---

## 5c. Aspect ratios — matching the print area

A design should match the SHAPE of the product's print area. A square design centered on a tall phone case or poster leaves the top and bottom of the print area empty (or, on full-bleed goods, shows bare substrate at the margins). Two ways to get the right shape:

### Generate at the aspect that matches the product

`POST /agents/v1/images/generate` accepts a `size` that sets the output aspect ratio:

| `size` | Aspect | Shape | Reach for it when… |
|---|---|---|---|
| `1024x1024` | 1:1 | Square | Chest prints, front-print tees/hoodies, most standard placements |
| `1024x1792` | 9:16 | Tall / portrait | Phone cases, posters, tall banners, portrait wall art |
| `1792x1024` | 16:9 | Wide / landscape | Landscape banners, mugs (wraparound strip), doormats, wide wall art |

Match the size to the product up front so the design is born the right shape — cheaper and cleaner than fixing it afterward. **Full-bleed / all-over goods** (phone cases, AOP tees, posters) want a design that FILLS the print area edge to edge, so generate at the print area's aspect (usually tall for a phone case) rather than square. When you already know the target product, pick its `size` in Phase 1. See `references/all-over-print.md` §12 for the per-product mapping.

Generating at a larger size is also how you keep resolution up for large-format goods (prefer 1792 on the long side over 1024) — see `references/all-over-print.md` §11.

### Fit an EXISTING design to an aspect — `POST /images/generated/<uuid>/fit-aspect` (quota-free)

When the design already exists (in the gallery, or the user liked a square one) but the shape is wrong for the product, reshape it WITHOUT burning an image generation:

```
POST /agents/v1/images/generated/<uuid>/fit-aspect
{ "aspect": "9:16", "mode": "pad", "background": "#000000" }
```

- **`aspect`** (required): target ratio as `"W:H"` numbers — `"1:1"`, `"9:16"`, `"16:9"`, `"4:5"`, `"3:4"`, `"4:3"`, etc. (any ratio up to 20:1).
- **`mode`**:
  - **`pad`** (default) — letterboxes the whole design onto a larger canvas at the target ratio. **Keeps the entire design** (nothing cropped away); the added margin is filled with `background`.
  - **`crop`** — center-crops the design to the target ratio. **Trims** whatever falls outside the ratio (edges of the design are lost). Use only when losing the outer edges is acceptable.
- **`background`** (optional, `pad` only): pad fill as `#RRGGBB` hex. Defaults to **transparent** — leave it transparent for a standard front-print design (garment color shows through the letterbox), or set a solid color for an all-over / full-bleed good so the margin matches the design's own background.

It returns a **NEW gallery image** (the source is untouched), so you can use the fit result downstream and still keep the original.

**Quota-free vs regenerating.** `fit-aspect` is metered as `storage`, NOT as an image generation — it does a local pad/crop, so it does not consume the user's image-generation quota. Regenerating the design at a different `size` (or an AI border-extension via `/images/generate`) DOES consume a generation. So when the pixels are already right and only the shape is wrong, prefer `fit-aspect`; only regenerate when you actually need new/extended content, not just a reshape.

```bash
# Reshape an existing square design to tall 9:16 for a phone case, letterboxed on black.
curl -sS -X POST "https://api.apparelhub.ai/agents/v1/images/generated/<uuid>/fit-aspect" \
  -H "x-api-key: $APPARELHUB_API_KEY" -H "Content-Type: application/json" -d '{
  "aspect": "9:16",
  "mode": "pad",
  "background": "#000000"
}'
# -> 200 { "image": { "uuid": "...", "url": "..." }, "source_image_uuid": "<uuid>",
#          "aspect": "9:16", "mode": "pad",
#          "dimensions": { "original": {...}, "result": {...} } }
```

**`fit-aspect` reshapes; it does not extend content.** `pad` adds blank margin (it doesn't paint new artwork into it) and `crop` throws pixels away. If the user wants the design's scene to actually EXTEND into a new aspect (outpainting — more sky above, more field to the sides), that's an AI job: regenerate via `/images/generate` (which consumes a generation), not `fit-aspect`.

---

## 5d. Retiring a design — archive, delete, and finding orphans

**Designs CAN be archived and deleted.** If you conclude otherwise you have misread the surface, and an agent that concludes it will silently skip gallery cleanup. Both primitives live on the same `/images/generated/<uuid>` resource you already use.

### Archive (reversible, the default choice)

Archiving is a PATCH, not a dedicated endpoint. That's the part that's easy to miss.

```bash
# Archive
curl -sS -X PATCH "https://api.apparelhub.ai/agents/v1/images/generated/<uuid>" \
  -H "x-api-key: $APPARELHUB_API_KEY" -H "Content-Type: application/json" \
  -d '{"archived": true}'
# Restore
curl -sS -X PATCH "https://api.apparelhub.ai/agents/v1/images/generated/<uuid>" \
  -H "x-api-key: $APPARELHUB_API_KEY" -H "Content-Type: application/json" \
  -d '{"archived": false}'
```

The PATCH accepts exactly two fields: **`title`** and **`archived`**. Anything else in the body is ignored and you get a `200` with nothing changed, which looks like success. Don't send `prompt` or `tags` and assume they took.

Archiving hides the design from the default gallery listing and **never touches products already using it**. It is reversible. This is the right way to retire an unwanted or superseded design.

### Delete (irreversible, guarded)

```bash
curl -sS -X DELETE "https://api.apparelhub.ai/agents/v1/images/generated/<uuid>" \
  -H "x-api-key: $APPARELHUB_API_KEY"
# -> 200 { "message": "Image deleted successfully", "freed_bytes": 1048576 }
```

Permanently removes the design and its stored files. If any **live (non-archived) product** uses the design, the platform refuses:

```
409 { "message": "This image is in use by one or more products and cannot be deleted...",
      "code": "image_in_use",
      "products": [ { "uuid": "...", "name": "..." } ] }
```

Nothing is deleted on a `409`. **Archive it instead**, or remove it from the listed products first. Never treat `image_in_use` as a hard failure to report and abandon; archiving is the answer almost every time.

### Finding orphan designs

There is a purpose-built filter for "designs nothing is using", so don't hand-roll it by cross-referencing products:

```bash
# Orphans: designs NOT used by any live product
curl -sS "https://api.apparelhub.ai/agents/v1/images/generated?on_products=false" -H "x-api-key: $APPARELHUB_API_KEY"
# In use only
curl -sS "https://api.apparelhub.ai/agents/v1/images/generated?on_products=true" -H "x-api-key: $APPARELHUB_API_KEY"
# Already-archived designs
curl -sS "https://api.apparelhub.ai/agents/v1/images/generated?archived=true" -H "x-api-key: $APPARELHUB_API_KEY"
```

The listing returns **active designs only** unless you pass `archived=true`, so an archived design "disappearing" from the default list is expected, not data loss. When `on_products` is set, each row also carries `usage_count`.

Other supported filters on the same listing: `search`, `edited`, `source`, `source_uuid`, `size`, `sort` (`newest` | `oldest` | `most_used`), `limit` (max 500), `offset`.

**Filtering by model:** pass `source` with the AI source NAME — the same form
`POST /images/generate` takes, e.g. `?source=Nano Banana` (comma-separated for
several, case-insensitive). You do not need to look up a UUID first; `source_uuid`
still works if you have one. An unrecognised name returns **400** with the list of
valid sources, so a result set that comes back is genuinely filtered. Before this
was fixed the parameter was accepted and silently ignored, which meant a
filtered-looking `200` could be the full unfiltered list — if you are running
against an older platform build, verify rather than assume.

**The gallery-cleanup pass, end to end:** list with `on_products=false` → confirm with the user which orphans to retire → PATCH each with `archived: true`. Reach for DELETE only when the user explicitly wants the design erased permanently.

---

## 6. Color discipline — max 4 colors per design

More than 4 color variants per design creates SKU sprawl that hurts conversion. Pick the 4 best colors for the design and stop.

For dark designs (heavy black/dark linework): Black + 2 dark colors + White
For light designs (line art on light fields): White + 2 light/neutral colors + Black (for contrast)
For colored designs: pick colors that complement the dominant design color, not compete with it.

---

## 7. Mockup verification gate

After Phase 3 (mockup generation), ALWAYS visually inspect the result before proceeding to Phase 4 (product create).

Check for:
- Design renders correctly (not cut off, not distorted)
- **Design is UPRIGHT** — text reads normally on the worn/used product. Some templates render the print file rotated 180° (Printful sock leg FRONTS: file-top = toe), so an upright-composed file prints upside down. See `references/all-over-print.md` §9.
- **Design lands on the visible face** — not straddling a fold/hem/seam (drawstring-bag areas are front+back in one file folded at the bottom) and not wrapped out of view at a silhouette edge (sock strips wrap the leg tube). See `references/all-over-print.md` §9.
- **Every printable surface is covered** on fill/all-over goods — a placement with no file ships as raw white fabric (socks have 4 leg strips; the AOP backpack has front/top/bottom/pocket). See `references/all-over-print.md` §10.
- **No blank or half-covered faces on multi-face / multi-piece merch** — wallets print on the front AND back exterior (a centered design splits at the spine), headphone ear cups both get the design, duffles have no bare far side. Check every face/piece in the mockup. See `references/all-over-print.md` §9.
- **No lettering clipped by an edge** (unless the designer explicitly wants a bleed) — text must sit fully inside the printable face with margin. This bites on oval/irregular faces (headphone ear cups clipped the "S" in SPAIN at the oval edge) and on wrap faces where the safe area is smaller than the print rectangle. Inset the art so no glyph touches an edge; verify at the edges of every face in the mockup. (Physical hardware crossing a face — a duffle strap, a zipper — is not an "edge clip"; that's the product.)
- **A seam across a face must not split a subject** — a backpack pocket seam, tote gusset, or jacket zipper cuts a full-face design in half. When the design has lettering or a subject (a face, a player's body, a logo), favor the seam-free region so it stays intact (the SPAIN backpack split the goalkeeper and "La Roja" across the pocket seam → now the design sits in the upper-body window above it). Abstract patterns can span the seam. See `references/all-over-print.md` §9.
- **Cylindrical drinkware clips at the wrap edges** — a water bottle / tumbler / mug / glass print area wraps around the tube (top → shoulder, bottom → base, sides → around), so a design filling the area is cut top, bottom, and sides (the MOROCCO water bottle clipped the star and "MOROCCO"). Inset the design into the flat frontal band. See `references/all-over-print.md` §9.
- **Resolution is sufficient** — a soft/pixelated print or a platform "low resolution" block means the design shrank too small after keying/cropping. Regenerate at higher resolution (or upscale to the print area). See `references/all-over-print.md` §11.
- **Vertical position matches the product**: collar breathing room (design top-anchored ~13% down) is an APPAREL concept. On phone cases, mugs, and other non-apparel placed goods the design belongs CENTERED on the face — top-anchored placement reads "too far up" (the MOROCCO clear-case incident). MCP v0.3.6+ centers non-apparel placed goods automatically.
- Text legible and spelled correctly
- No white halos around transparent edges
- No checkerboard artifacts where transparency should be
- **No chroma-green background anywhere** on the render — green reaching the mockup means the keying background is in the print file
- Color contrast is acceptable on the chosen garment
- Design isn't tiny (chest emblem when you wanted chest-filling) or oversized (overflowing the print area)

If anything looks wrong, FIX the design and re-mockup before continuing. Manufacturing follows the mockup.

**Inspect at full resolution, never thumbnail scale** — downscaled previews hide clipped edges, seam straddling, and orientation errors. Crop the print region 1:1 if the mockup is large.

---

## 7b. Mockups must cover every color variant you import — decide colors FIRST

**Think ahead: choose the color variants you'll offer BEFORE generating the mockup, then make sure the mockup covers each of those colors.** Mockups are rendered per variant, and same-color variants share one print image — so if you import Black + White but only mockup Black (or "the first N variants", which are all one color), the White variants ship with NO mockup and the product gallery is wrong. The set of colors in the mockups must equal the set of colors in the variants.

- **`ship_product` does this automatically** (v0.3.3+): it resolves your variants first, then renders **one mockup per distinct imported color**. Prefer it for any product with more than one color — it's the whole point of "think ahead."
- **Split primitives:** `create_product` generates the mockup BEFORE `add_variants`, so it cannot know your exact colors — its auto-derived mockup only samples catalog colors and may miss one you intend to sell. For a specific color set, either pass `mockup_variant_ids` covering exactly the colors you'll import, or (better) use `ship_product`.
- **Raw REST (Phase 3):** pass a `variant_ids` list with one representative variant per color you plan to offer, not five sizes of a single color.
- **Rule of thumb:** one garment mockup per color you sell; never leave an offered color with no mockup.

---

## 8. Pricing discipline — never price below cost + margin

The merchant loses money on negative-margin products. See `references/garment-catalog.md` for current pricing floors per garment.

Margin math:
```
Profit = (Retail Price + Customer Shipping)
       - Fulfillment Cost (Printful/Printify)
       - Fulfillment Shipping (~$5.90)
       - Sales Channel Fee (~3.9% of total)
       - Creator Commission (if applicable, 40% standard)
```

Standard shipping: $8.00 to customer, free over $70.

---

## 9. Default to DRAFT when syncing to sales channels

For channels that support draft state (Etsy, Shopify), push as draft first. The merchant reviews on the channel's admin before customers see it. Only push as `active` when the user EXPLICITLY says "make it live."

The cost of a too-eager publish (typo'd description in front of real customers) is much higher than one extra step.
