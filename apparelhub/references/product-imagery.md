# Product imagery — what the shopper sees, and in what order

Every product carries two completely different kinds of image, and the platform
stores them in different places for a reason:

- The **print file** is the artwork that gets PRINTED onto the garment. It lives in
  `print_data[].image_url` and is a manufacturing instruction.
- **Listing images** are the photographs a shopper sees on the storefront. They live
  in the gallery, and `display_image` is the cover.

They are not interchangeable, and treating them as if they were is the expensive
mistake this file exists to prevent. Everything below is about listing images.

`references/product-creation-pipeline.md` Phase 4.0 covers choosing them at
CREATION time from a fresh mockup job. This file covers everything after that:
attaching a photo to a product that already exists, reordering, changing the
cover, and declaring where an image came from.

---

## 1. A print file is not a listing image

The print file is flat artwork on a transparent (or full-bleed) canvas. It is what
the fulfillment provider prints. A shopper should never see it.

⛔ **Never push a print file to a sales channel as listing photography.** It is a
known quality failure on at least one major channel: the listing gets graded down
or refused because the "product photo" is a floating graphic on a blank field
rather than a product.

The platform models this explicitly. An image carrying `source: "print_file"` is
**excluded from channel sync** — unless it is the only image the product has, in
which case something is better than an empty listing and it goes anyway. That
fallback is a safety net, not a plan. If you see a product whose gallery is one
`print_file` entry, that product needs a real mockup, not a re-sync.

**How a product ends up in that state:** it was created before its mockup job
finished, so there was no mockup URL to use as a cover and the artwork was the only
image available. It looks completely normal in the API response. The tell is
`source`, not anything about the URL.

```
Check before syncing:
  images[].source == "print_file"  and nothing else in the array  ->  fix first
```

The fix is to generate the mockup (pipeline Phase 3), then attach it as below.

---

## 2. Reading the current state

```bash
curl -sS "https://api.apparelhub.ai/agents/v1/product/<product_uuid>" \
  -H "x-api-key: $APPARELHUB_API_KEY"
```

The imagery-relevant part of the response:

```json
{
  "display_image": "https://cdn.apparelhub.ai/.../black-front.png",
  "images": [
    {
      "url": "https://cdn.apparelhub.ai/.../black-front.png",
      "source": "mockup",
      "ai_generated": false,
      "preview_uuid": "<preview_uuid>",
      "image_uuid": null,
      "thumbnail_url": "https://cdn.apparelhub.ai/.../black-front-thumb.png",
      "added_at": "2026-08-20T14:02:11Z",
      "alt": "Black tee, front"
    }
  ],
  "images_version": 7,
  "gallery_images": ["https://cdn.apparelhub.ai/.../black-front.png"]
}
```

| Field | What it is |
|---|---|
| `images` | The real gallery. Array of objects, **in listing order**. Read this one. |
| `images_version` | Integer that increments on every gallery write. Your concurrency token — see §7. |
| `display_image` | The cover. Also appears in `images` (the platform keeps them consistent). |
| `gallery_images` | **Deprecated.** A flat array of URL strings, same order, kept so older callers do not break. It carries no `source` and no `ai_generated`, so you cannot tell a mockup from a print file by reading it. Do not build new logic on it. |

Per-entry fields:

| Field | Meaning |
|---|---|
| `url` | The image. Max 512 characters. |
| `source` | Where it came from — see §5. |
| `ai_generated` | Tri-state declaration — see §6. `null` means unknown, **not** no. |
| `preview_uuid` | Set when the image came from a mockup preview row. |
| `image_uuid` | Set when the image is a design/upload in the image library. |
| `thumbnail_url` | Platform-generated; may be null until it is built. |
| `added_at` | When it joined the gallery. |
| `alt` | Alt text, when set. |

---

## 3. Writing the gallery

```bash
curl -sS -X PATCH "https://api.apparelhub.ai/agents/v1/product/<product_uuid>" \
  -H "x-api-key: $APPARELHUB_API_KEY" -H "Content-Type: application/json" -d '{
  "gallery_images": [
    "https://cdn.apparelhub.ai/.../black-front.png",
    "https://cdn.apparelhub.ai/.../navy-front.png"
  ],
  "display_image": "https://cdn.apparelhub.ai/.../black-front.png",
  "expected_images_version": 7
}'
```

⛔ **`gallery_images` REPLACES the gallery. It is not a merge.** Whatever you send
becomes the entire gallery, in exactly the order you sent it. To add one photo to a
product that already has four, send all five — read the current `images` first,
append, and write the whole list back. Sending only the new URL silently deletes the
other four.

You may send bare URL strings, or objects when you want to declare provenance:

```json
{
  "gallery_images": [
    "https://cdn.apparelhub.ai/.../black-front.png",
    { "url": "https://cdn.apparelhub.ai/.../studio-shot.jpg",
      "source": "upload",
      "ai_generated": false }
  ]
}
```

The two forms mix freely in one array. A bare string is accepted, but it declares
nothing — prefer the object form for anything you are attaching yourself, so the
provenance in §5 and §6 is actually recorded.

**Sending `"gallery_images": null` resets the gallery to the product's mockups.**
That is the recovery path when a gallery has been curated into a mess and you want
to start from the rendered mockups again. It is destructive to any uploaded or
generated imagery in the gallery, so confirm with the merchant first.

### The cover

`display_image` is set independently of order. The first gallery image and the
cover are **not** the same thing, and either can change without the other.

Two behaviours worth knowing:

- Setting `display_image` to a URL that is not in the gallery **auto-inserts it**.
  You do not have to add it twice.
- If you replace the gallery and omit the current cover, **the cover follows to the
  new first image**. It is not left dangling and it does not error. So a reorder
  that drops the old cover silently changes the cover too — if you meant to keep it,
  pass `display_image` explicitly in the same call.

### Limits

| Limit | Value | On breach |
|---|---|---|
| Images per product | 20 | Request refused |
| URL length | 512 characters | Request refused |
| Duplicate URLs | Deduplicated by URL | Silently collapsed, not an error |

Dedup by URL means the same image cannot appear twice in one gallery. If you build
a list by concatenating fronts and backs and the same URL lands in both, you get one
entry and a shorter gallery than you counted on. Count the result, not the input.

---

## 4. Ordering is functional, not cosmetic

**Channels cap listing images at different counts, and they truncate in gallery
order.** Position decides what actually ships.

| Channel | Listing image cap |
|---|---|
| TikTok Shop | 9 |
| Wix | 15 |
| Shopify | no cap |
| WooCommerce | no cap |

So a 14-image gallery is a full listing on Wix and a 9-image listing on TikTok Shop
made of whichever nine you happened to put first. An agent that treats order as
presentation and appends new images to the end has just decided, without meaning to,
that the new images do not exist on the capped channel.

**Put the images that must survive truncation first.** In practice:

1. The cover shot (usually the darkest colorway front — highest contrast on the design)
2. One front per remaining colorway
3. Back views
4. Detail / lifestyle / merchant photography

That is the same ordering `ah_classify_previews --recommend` produces, which is why
its output is a reasonable default rather than an arbitrary one.

When a product is synced to a capped channel and the gallery exceeds the cap, say so
in your report. "Nine of your fourteen images will appear on TikTok Shop; the first
nine are …" is useful. Silently syncing is how a merchant finds out from a shopper.

---

## 5. Provenance: `source`

Every entry declares where it came from. Five values:

| `source` | Means | Syncs to channels |
|---|---|---|
| `mockup` | A rendered preview from a mockup job — the normal case | Yes |
| `upload` | A photo the merchant supplied | Yes |
| `ai_mockup` | An AI edit of the product's real mockup (§6b) | Yes |
| `print_file` | The flat artwork that gets printed (§1) | **No**, unless it is the only image |
| `unknown` | Provenance was not declared | Yes |

`unknown` is what a bare URL string becomes. It is legal and it syncs, but it means
nobody can later tell whether that image is a photograph or artwork — including you,
next session. Declare `source` when you know it, which is any time you are the one
attaching the image.

---

## 6. Attaching new imagery

### 6a. A photo the merchant supplied

No new upload primitive — this is the existing upload path from
`references/byo-artwork.md`. Get the bytes hosted, then PATCH the returned URL into
the gallery.

```bash
# 1. Upload via any of the three routes in byo-artwork.md. Presigned is cheapest:
curl -sS -X POST "https://api.apparelhub.ai/agents/v1/images/upload/initiate" \
  -H "x-api-key: $APPARELHUB_API_KEY" -H "Content-Type: application/json" \
  -d '{"filename":"studio-shot.jpg","content_type":"image/jpeg","file_size":184203}'
# → { "upload_url": "...", "image_uuid": "<image_uuid>" }

curl -X PUT -H "Content-Type: image/jpeg" --upload-file studio-shot.jpg "<upload_url>"

curl -sS -X POST "https://api.apparelhub.ai/agents/v1/images/upload/<image_uuid>/complete" \
  -H "x-api-key: $APPARELHUB_API_KEY"

curl -sS "https://api.apparelhub.ai/agents/v1/images/upload/<image_uuid>/status" \
  -H "x-api-key: $APPARELHUB_API_KEY"
# → { "processing_status": "completed", "url": "https://cdn.apparelhub.ai/..." }
```

Then read the current gallery, append, and write the whole list back (§3), with
`{"source": "upload"}` on the new entry.

With the MCP connector this is `upload_design` — same three routes, one tool.

⚠️ **The merchant's photo may itself be AI-generated and the platform cannot tell.**
If they made it in an image tool, `ai_generated` is `true` even though `source` is
`upload`. Ask, or leave it `null`. See §6c.

### 6b. Generated imagery — edit the real mockup, never generate a product photo

The platform constrains generated listing imagery to **editing the product's actual
mockup**. You take the rendered mockup — the real garment, the real colorway, the
real design in its real position — and edit it: change the background, put it in a
scene, adjust the lighting.

**Why the constraint exists, plainly:** a from-scratch generation invents a product
that does not exist. The garment will be a slightly different cut, the color a
slightly different shade, the design placed somewhere it is not actually printed.
The shopper receives something that does not match what they were shown. That is not
a quality problem — it is a listing takedown and a chargeback, and it is made in the
merchant's name.

Editing the real mockup keeps the product true and changes only its presentation.

The mechanism is the existing img2img path in `references/design-rules.md` §5b:
`POST /images/generate` with `source_image_uuid` set to the mockup, or the
`iterate_design` MCP tool. Only Nano Banana and OpenAI support edit mode.

Entries land as:

```json
{ "url": "https://cdn.apparelhub.ai/.../lifestyle.png",
  "source": "ai_mockup",
  "ai_generated": true }
```

⛔ Both fields together. `ai_mockup` says what it is; `ai_generated: true` is the
disclosure. Do not set one without the other.

⚠️ **A generated lifestyle shot is still a claim about a physical product.** Verify
it before it goes on the listing: the garment color must still be the color you are
selling, the design must still be where it is actually printed, and the edit must not
have added a feature the blank does not have (a pocket, a zipper, a different collar).
This is the same visual-verification gate as the mockup itself — see SKILL.md §4b.

### 6c. `ai_generated` is a declaration, and it is tri-state

| Value | Means |
|---|---|
| `true` | This image was AI-generated or AI-edited |
| `false` | This image is a photograph or a real render, not AI |
| `null` | **Unknown.** Nobody has declared it. |

`null` is not `false`. An undeclared image is undeclared; do not write `false` to
tidy the field.

It is **independent of `source`**. An `upload` can be `true` (the merchant made it
with an image tool). A `mockup` is `false` (it is a real render of a real blank).

**Set it truthfully. The platform cannot detect it, so your declaration is the only
record there is.** Some channels have synthetic-media disclosure rules, and the
declaration is what a merchant would rely on to answer them. A wrong `false` is a
false statement made under the merchant's name — the same class of thing as a
compliance attestation (`references/listing-attributes.md` §4). If you do not know,
leave it `null` and say so.

---

## 7. Concurrent writes

`images_version` increments on every gallery write. Pass the value you read as
`expected_images_version` and the platform refuses the write if anything changed
underneath you:

```json
409 {
  "error_code": "images_version_conflict",
  "current_version": 9,
  "expected_version": 7
}
```

**On 409: re-read the product, reapply your intent to the CURRENT gallery, and write
again.** Do not retry the same body — it will fail identically, and if it somehow
succeeded it would clobber whatever the other writer did.

"Reapply your intent" is the important part. If you were adding one photo, append it
to the gallery you just re-read. If you were reordering, reorder what is there now.
Replaying a stale list is exactly the overwrite the version token exists to stop.

`expected_images_version` is optional. Omitting it is last-write-wins, which is fine
for a one-shot edit in an interactive session and wrong for anything unattended or
multi-step. **Send it whenever the gallery you are writing was derived from a gallery
you read.**

---

## 8. Common tasks

**Reorder (no new images).** Read `images`, reorder the URLs, PATCH the full list.
Pass `display_image` too if the cover should stay put — dropping it from first
position moves it (§3).

**Change the cover only.** PATCH `display_image` alone. The gallery is untouched; if
the URL is not in it, it is auto-inserted.

**Add one photo.** Read `images` → append → PATCH the whole list with
`expected_images_version`.

**Remove one photo.** Read `images` → drop the entry → PATCH the remainder. There is
no per-image delete; the gallery is written whole.

**Trim for a capped channel.** Reorder so the keepers are first (§4). Do not delete
the rest — Shopify and WooCommerce will show them.

**Recover a broken gallery.** PATCH `"gallery_images": null` to reset to the
product's mockups, then re-curate. Destroys uploaded and generated entries — confirm
first.

---

## 9. What this does NOT do

- **It does not push anything to a channel.** Like listing attributes, gallery
  changes are stored against the product and reach the storefront on the next sync.
  Re-sync after editing imagery, or the merchant is looking at the old listing.
- **It does not change what gets printed.** `print_data[].image_url` is untouched by
  everything in this file. Editing the gallery cannot break manufacturing, and
  editing the gallery cannot fix a wrong print file.
- **It does not validate that an image depicts this product.** Nothing checks that
  the photo you attached is the right garment. That judgment is yours.
