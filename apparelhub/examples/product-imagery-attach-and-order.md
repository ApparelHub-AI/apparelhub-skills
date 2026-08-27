# Worked example — attach a photo to a live listing, then order the gallery for a capped channel

Goal: a product already exists and is synced. The merchant sends a studio photo and
says "add this and make it the main image." The product also sells on TikTok Shop,
which shows only 9 listing images, so ordering is part of the job — not a polish step.

Full contract in `references/product-imagery.md`.

---

## 0. Read the current state before you touch anything

```bash
curl -sS "https://api.apparelhub.ai/agents/v1/product/<product_uuid>" \
  -H "x-api-key: $APPARELHUB_API_KEY"
```

```json
{
  "display_image": "https://cdn.apparelhub.ai/.../black-front.png",
  "images": [
    { "url": "https://cdn.apparelhub.ai/.../black-front.png", "source": "mockup", "ai_generated": false },
    { "url": "https://cdn.apparelhub.ai/.../navy-front.png",  "source": "mockup", "ai_generated": false },
    { "url": "https://cdn.apparelhub.ai/.../white-front.png", "source": "mockup", "ai_generated": false },
    { "url": "https://cdn.apparelhub.ai/.../black-back.png",  "source": "mockup", "ai_generated": false }
  ],
  "images_version": 7
}
```

Two things to take from this response:

- **The four existing URLs.** `gallery_images` is a REPLACE, so you will be sending
  all five in step 3, not just the new one.
- **`images_version: 7`.** That is your concurrency token for step 3.

⚠️ Glance at `source` while you are here. If the only entry is `print_file`, stop —
this product never got a mockup and needs pipeline Phase 3 first, not a photo. See
`references/product-imagery.md` §1.

---

## 1. Get the merchant's photo hosted

The existing upload path — nothing new here. Presigned route (see
`references/byo-artwork.md` for all three):

```bash
curl -sS -X POST "https://api.apparelhub.ai/agents/v1/images/upload/initiate" \
  -H "x-api-key: $APPARELHUB_API_KEY" -H "Content-Type: application/json" \
  -d '{"filename":"studio-front.jpg","content_type":"image/jpeg","file_size":184203}'
# → { "upload_url": "...", "image_uuid": "<image_uuid>", "expires_in": 900 }

# Send NO API key on this PUT — the presigned URL carries its own signature.
curl -X PUT -H "Content-Type: image/jpeg" \
  --upload-file studio-front.jpg "<upload_url>"

curl -sS -X POST "https://api.apparelhub.ai/agents/v1/images/upload/<image_uuid>/complete" \
  -H "x-api-key: $APPARELHUB_API_KEY"

curl -sS "https://api.apparelhub.ai/agents/v1/images/upload/<image_uuid>/status" \
  -H "x-api-key: $APPARELHUB_API_KEY"
# → { "processing_status": "completed", "url": "https://cdn.apparelhub.ai/.../studio-front.jpg" }
```

With the MCP connector: `upload_design({ filename, content_type })`, PUT, then
`upload_design({ image_uuid })`.

**Ask the merchant one question before continuing:** was this photo made with an AI
image tool? You cannot tell and neither can the platform. Their answer is
`ai_generated` in the next step. If they do not answer, leave it `null` — do not
write `false` to fill the gap.

---

## 2. Decide the order before you write it

The merchant wants the studio shot as the cover. It also sells on TikTok Shop (cap:
9). With five images nothing truncates today, but the order is what governs if the
gallery grows later, so set it deliberately now:

1. `studio-front.jpg` — the new cover
2. `black-front.png` — darkest colorway front
3. `navy-front.png`
4. `white-front.png`
5. `black-back.png` — back views last

Cover first, one front per colorway, backs after. See
`references/product-imagery.md` §4.

---

## 3. Write the whole gallery in one PATCH

```bash
curl -sS -X PATCH "https://api.apparelhub.ai/agents/v1/product/<product_uuid>" \
  -H "x-api-key: $APPARELHUB_API_KEY" -H "Content-Type: application/json" -d '{
  "gallery_images": [
    { "url": "https://cdn.apparelhub.ai/.../studio-front.jpg",
      "source": "upload",
      "ai_generated": false },
    "https://cdn.apparelhub.ai/.../black-front.png",
    "https://cdn.apparelhub.ai/.../navy-front.png",
    "https://cdn.apparelhub.ai/.../white-front.png",
    "https://cdn.apparelhub.ai/.../black-back.png"
  ],
  "display_image": "https://cdn.apparelhub.ai/.../studio-front.jpg",
  "expected_images_version": 7
}'
```

Points worth noticing in that body:

- **All five URLs are present.** Sending only the new one would have deleted the four
  mockups.
- **The new entry is an object**, so `source` and `ai_generated` are recorded. The
  four existing ones are bare strings — they keep their stored provenance; a bare
  string only means "unknown" for an entry the platform has never seen before.
- **`display_image` is passed explicitly.** It happens to match position 1 here, but
  the cover is independent of order, so state it rather than relying on the coincidence.
- **`expected_images_version: 7`** is the value read in step 0.

Response carries the new `images_version` (8) and the updated `images` array.

---

## 4. If you get a 409

```json
409 { "error_code": "images_version_conflict", "current_version": 9, "expected_version": 7 }
```

Someone else changed the gallery between step 0 and step 3 — another session, or the
merchant in the web UI.

⛔ Do not retry the same body. Go back to step 0, re-read `images`, and rebuild the
list from what is there NOW — keeping your intent (studio shot first, cover set), not
your stale array. Then PATCH again with the new `expected_images_version`.

---

## 5. Sync, or the merchant is looking at the old listing

The gallery is stored against the product. It does not reach the storefront until a
sync.

```bash
curl -sS -X POST "https://api.apparelhub.ai/agents/v1/store/<store_uuid>/products/<product_uuid>/sync?target=ecommerce&integration_uuid=<integration_uuid>" \
  -H "x-api-key: $APPARELHUB_API_KEY"
```

Repeat per connected channel. Skipping this is the most common way to conclude the
edit did not work when it did.

---

## 6. Report back

> "Added the studio photo and made it the main image on **Desert Sunset Tee**.
>
> Gallery order is now: studio shot, black front, navy front, white front, black back.
> All five appear on Shopify. TikTok Shop shows a maximum of 9, so nothing is cut today,
> but that order is what would be kept if you add more.
>
> Re-synced to both channels. I recorded the studio photo as a merchant upload, not
> AI-generated, per your answer."

Say the cap out loud even when nothing truncated. It is the fact that makes the next
addition predictable rather than a surprise.

---

## Variant — starting from `ah_classify_previews` instead of a merchant photo

When you have just run a mockup job and want its recommendation on an existing
product (rather than at create time), the script's output is already the right shape:

```bash
ah_classify_previews /tmp/preview_job.json --recommend /tmp/picks.json
```

```json
{
  "display_image": "https://cdn.apparelhub.ai/.../black-front.png",
  "gallery_images": ["https://cdn.apparelhub.ai/.../black-front.png", "..."],
  "rationale": "Picked black front for dark-color contrast; 3 front + 3 back in gallery, darkest first."
}
```

`display_image` and `gallery_images` are exactly the PATCH field names, and the
ordering it produces (cover first, one front per colorway darkest-first, then backs)
is already the §4 ordering. So the recommendation goes straight into the request body:

```bash
curl -sS -X PATCH "https://api.apparelhub.ai/agents/v1/product/<product_uuid>" \
  -H "x-api-key: $APPARELHUB_API_KEY" -H "Content-Type: application/json" -d '{
  "gallery_images": ["<paste gallery_images from /tmp/picks.json>"],
  "display_image": "<paste display_image from /tmp/picks.json>",
  "expected_images_version": <the value you just read>
}'
```

Two caveats:

- This **replaces** the gallery, so any merchant upload already on the product is
  discarded. If the product has uploads you want to keep, merge them into the list
  yourself rather than pasting the recommendation whole.
- The recommendation caps at 10 entries and knows nothing about your channels. Check
  it against the caps in `references/product-imagery.md` §4 before writing.
