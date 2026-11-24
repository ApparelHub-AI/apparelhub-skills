# Bring your own artwork — uploading files the merchant already owns

Everything else in this skill starts from "generate a design." This file covers
the other half: the merchant already **owns** the artwork, and you need to get it
onto a product without changing it.

That covers a lot of real work — an established brand's logo, a client's wordmark,
a cleared album cover, a photograph they hold the rights to, a mark a designer
delivered as a file. Agencies and existing brands arrive with a catalog in hand,
so this is usually the *first* thing they need, not an edge case.

---

## 0. The rule that matters most

**Never regenerate, redraw or approximate a mark you were given as a file.**

If a client supplies a logo and you cannot upload it, the answer is not "generate
something that looks similar." A lookalike breaches an explicit instruction, and
for anything with fine structure — a pixel-grid seal, a wordmark with specific
letterforms, a registered mark — it produces something visibly wrong that a
client will reject on sight.

The correct move when you genuinely cannot proceed is to **stop and say what you
need**, naming the file and where it should go. An unbuilt product is recoverable.
A fabricated trademark is not.

Uploading is supported. Use it.

---

## 1. Which route to use

Three ways to get bytes in. They all end in the same place — a design uuid you
pass to product creation exactly like a generated one. Pick by what your
environment can do, cheapest first.

| Route | Use when | Cost to you |
|---|---|---|
| **`source_url`** | The file is reachable at an https URL that does not require sign-in | One call. Nothing enters your context. |
| **`image_base64`** | You can read the file's bytes and it is small (4MB or less) | **Roughly 350k tokens per megabyte of file.** Small files only. |
| **Presigned** (`presigned: true`) | You can make an HTTP PUT yourself (`curl`, `fetch`, `requests`) **and** call back to finish | Two calls. Nothing enters your context. Full resolution. |

**Presigned is only for callers that can do both steps.** If you have a shell or
an HTTP client it is the best route: free in context and unlimited in file size.
Starting it reserves a design in the merchant's gallery straight away, though.
If the PUT or the finishing call never happens, the merchant sees a failed
upload. So never start one you cannot finish. Over MCP, presigned mode is opt-in
(`presigned: true`). Calling `upload_design` with no file and no opt-in reserves
nothing and returns `file_required`.

`image_base64` is not a convenience: a 3MB logo inlined as base64 will consume
most of a context window.

### A file the user attached in the chat

An image someone drops into a chat conversation is usually something you can
*see*, not a file you can PUT or base64-encode. Seeing it is not enough to
upload it, and you must never redraw or regenerate it instead. Ask the merchant
for a public link to it (then use `source_url`), or ask them to upload it
themselves at **apparelhub.ai/images/gallery** and tell you when it's done. Then
use that design from the gallery (`list_my_designs`).

### With the MCP server

One tool, `upload_design`, does all three:

```
upload_design({ source_url: "https://…/client-logo.png" })
→ { status: "completed", design_uuid: "…", url: "…" }

upload_design({ filename: "client-logo.png", content_type: "image/png", presigned: true })
→ { mode: "presigned", upload_url: "…", image_uuid: "…", next_step: "…", important: "…" }
   … you PUT the bytes …
upload_design({ image_uuid: "…" })
→ { status: "completed", design_uuid: "…" }

upload_design({ image_base64: "<base64>", filename: "seal.png" })
→ { status: "completed", design_uuid: "…" }

upload_design({ filename: "client-logo.png" })   // no file, no opt-in
→ error { code: "file_required", suggestion: "…" }   // nothing was reserved

upload_design({ source_url: "https://…/mark.svg" })
→ { status: "completed", design_uuid: "…",
    warnings: ["The SVG was rendered to a 4096x2048 raster at print resolution…"] }
```

Then feed `design_uuid` to `ship_product` / `create_product` as normal.

### Over the raw API

Three steps. This is what the tool does for you.

```bash
# 1. Reserve a slot and get a presigned URL (valid 15 minutes).
curl -sS -X POST "https://api.apparelhub.ai/agents/v1/images/upload/initiate" \
  -H "x-api-key: $APPARELHUB_API_KEY" -H "Content-Type: application/json" -d '{
  "filename": "client-logo.png",
  "content_type": "image/png",
  "file_size": 24831
}'
# → { "upload_url": "...", "image_uuid": "...", "expires_in": 900 }

# 2. PUT the bytes straight to storage.
#    This is NOT an ApparelHub endpoint. Send NO API key — the presigned URL
#    already carries its own signature, and forwarding your key to a
#    third-party host is exactly the mistake SECURITY.md §2d exists to prevent.
#    The Content-Type MUST match what you declared in step 1 or the PUT fails
#    with an opaque signature error.
curl -X PUT -H "Content-Type: image/png" --upload-file client-logo.png "<upload_url>"

# 3. Kick off processing, then poll until it lands.
curl -sS -X POST "https://api.apparelhub.ai/agents/v1/images/upload/<image_uuid>/complete" \
  -H "x-api-key: $APPARELHUB_API_KEY"
curl -sS "https://api.apparelhub.ai/agents/v1/images/upload/<image_uuid>/status" \
  -H "x-api-key: $APPARELHUB_API_KEY"
# → { "processing_status": "completed", "url": "https://cdn…" }
```

`image_uuid` **is** the design uuid. Once `processing_status` is `completed` it
appears in `GET /images/generated` alongside generated designs and works
everywhere a design uuid works.

Send `file_size` when you know it: it lets the storage quota refuse an
over-limit upload *before* the presigned URL is minted, instead of after you have
moved the bytes.

---

## 2. Formats

**Accepted: SVG, PNG, JPEG, WEBP.**

**Prefer SVG when the client has one.** Vector has no fixed resolution, so it is
rendered server-side at print resolution (4096px on the long side) and stays crisp
at any print size — better than any raster of the same mark, which can only be
enlarged and lose edges. Upload the `.svg` directly; you get back an ordinary
design uuid.

Two things have to be true of the SVG, and both are refused with instructions
rather than silently mangled:

- **Text must be converted to outlines.** Rendering runs with no fonts on purpose,
  because substituting a font in a brand wordmark is corruption, not a fallback.
  Live `<text>` would render as nothing — so a wordmark would come out blank, or a
  logo would come out with its mark intact and its wordmark quietly gone. Fix it at
  the source: Illustrator *Type > Create Outlines*, Figma *Flatten*, Inkscape
  *Path > Object to Path*. Never retype the lettering yourself.
- **Linked images must be embedded.** An `<image href="https://…">` is never
  fetched (that is deliberate — it is what stops a hostile SVG reaching anything),
  so it would render as a hole. Re-export with the image embedded, or flatten the
  whole thing to PNG. Inline `data:` URIs are fine.

**The document size can be in any unit.** An SVG sized in pixels, inches,
millimetres, centimetres or points uploads as it is. So does one with no size, a
percentage size, or a zero or negative size on its root element: the size is then
taken from the `viewBox`, or from the artwork itself. Do not ask a client to
re-export only to change units.

**A refused SVG says why.** The status poll comes back `failed` with a stable
`error_code`: `svg_no_size`, `svg_text_not_outlined`, `svg_external_reference`,
`svg_rendered_blank`, `svg_too_large` or `svg_invalid`. Branch on the code, not
the prose. What each one means and what to tell the user:
`references/error-handling.md` section 2a-bis.

**PNG is the right raster default** — the only common raster format that carries
transparency, which a logo sitting on a coloured garment needs.

**AI and EPS are not accepted.** Export to SVG (keeps it vector, best quality) or
PNG at print size. Exporting is not redrawing — it is the same artwork in another
container, so it does not breach a "do not alter the mark" instruction. Generating
a lookalike would.

Ceiling is 50MB per file (8MB for an SVG source). Anything above the print maximum
is scaled down on ingest; anything below the 512px minimum is enlarged — which is
where the next section matters. An SVG never needs enlarging: it is rendered at
print size to begin with.

---

## 3. Small artwork, and the trap in enlarging it

Files below 512px on either side are enlarged automatically to reach the print
minimum. **How they are enlarged decides whether the mark survives.**

- **Photographic or painterly artwork** wants smooth interpolation. Edges are
  meant to be soft; smoothing looks natural.
- **Pixel art, flat logos, hard-edge marks** want nearest-neighbour. Smoothing
  invents in-between colours across every edge, so an 11x11 pixel-grid seal comes
  back as a blurred smear rather than crisp squares. That is exactly the "visibly
  fails when approximated" outcome a client will reject.

Pass `upscale` to control it:

| Value | Effect |
|---|---|
| `auto` (default) | Detects pixel-art-scale sources and uses nearest for them, smooth otherwise |
| `pixel` | Forces nearest-neighbour. **Use this for any hard-edge mark you were told not to approximate.** |
| `smooth` | Forces smooth interpolation |

Auto-detection is deliberately conservative — it only fires on genuinely tiny,
low-colour sources. A 300px flat logo does **not** trip it, so if you are handed
a small logo with hard edges, say `pixel` explicitly rather than hoping.

**Read the result.** When a file was enlarged, the response says so and names the
filter that ran. If it says the artwork was smoothed and the mark is hard-edged,
re-upload with `upscale: "pixel"` — or ask for a higher-resolution original,
which is always the better answer when one exists.

Enlarging never adds detail. If the source is genuinely too small and the client
has a bigger file, ask for it.

---

## 4. After the upload

### Read `upload_assessment` first

Once an upload reaches `completed`, the status poll
(`GET /agents/v1/images/upload/<image_uuid>/status`) and the design detail
(`GET /agents/v1/images/generated/<image_uuid>`) carry an `upload_assessment`
block that says what kind of image it is:

```json
"upload_assessment": {
  "has_transparency": false,
  "opaque_uniform_background": true,
  "looks_like_photo": false
}
```

At most one flag is true. It is a hint and never blocks anything.

| Flag that is true | What it means | What to do |
|---|---|---|
| `has_transparency` | The file has real transparency. | Ready to place on a product as it stands. Go to the mockup. |
| `opaque_uniform_background` | Opaque, with one flat colour all the way round the edge (a logo on white, for example). Placed on a garment it prints as a rectangle. | The background can very likely be removed: `POST /agents/v1/images/generated/<image_uuid>/remove-background` (no generation is spent). Tell the user you are doing it, read the result's `background_state`, then render the mockup. If the client forbade any change to the mark, ask for a transparent version instead. |
| `looks_like_photo` | Opaque, no flat edge colour, many colours. Probably a photograph of a product or a scene, not artwork to print. | Background removal will not help. Ask whether they have the artwork file itself. If the photo IS the design (a full-bleed print), carry on and say it will print with its background. |
| none | Opaque, but neither of the two patterns above. | Look at it, and check `design_check` on the mockup (`references/design-rules.md` section 3b). |

The block is absent on generated designs and on uploads processed before it
existed. Absent means "not assessed", never "fine".

**MCP callers:** `upload_design` returns `upload_assessment` and adds a warning in
words for the flat-background and photograph cases; a refused SVG comes back as
an error whose code is the SVG code. MCP server 0.20.1 or later.

### Then the normal pipeline

From here it is the normal pipeline — see
`references/product-creation-pipeline.md`. Two things worth knowing:

- **Transparency keying does not apply.** The chroma-key step exists because AI
  generators cannot produce real transparency, so we ask for a green background
  and key it out. A client's PNG either already has an alpha channel or it does
  not. Do not run it through the keyer hoping to improve it. If the background
  is opaque and needs to be transparent, let `upload_assessment` (above) decide:
  a flat uniform background can be removed with `remove-background`, and anything
  else is a question for the client ("do you have this with a transparent
  background?"), not something to guess at.
- **Quality checks still apply.** Run the mockup gate as usual and inspect the
  render at full size. A client file can still be too low-resolution, wrongly
  proportioned for the print area, or wrong for the garment colour.

Uploads are **storage-metered only** — they do not consume an AI image
generation. Uploading forty client assets costs zero generations. They do count
against the account's storage allowance.

---

## 5. When you are stuck

If you cannot upload (no shell, no link, file only attached in chat, too large to
inline), say so plainly and name what you need. Pointing the merchant at
apparelhub.ai/images/gallery is usually the fastest fix:

> I need `client-logo.png` uploaded to the *Acme Co* workspace before I can build
> the paw-only tee. It is the client's own mark and they have asked that it not be
> redrawn, so I have not generated a substitute.

That is a complete, actionable request. Do not:

- generate a lookalike "just for the mockup" — a mockup gets shown to someone, and
  then it exists;
- build the rest of the range and quietly skip the blocked item without saying
  which one and why;
- describe the mark in a prompt and treat the result as the client's asset.
