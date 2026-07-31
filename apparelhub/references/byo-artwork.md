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
| **Presigned** (no source) | You can make an HTTP request yourself (`curl`, `fetch`, `requests`) | Two calls. Nothing enters your context. Full resolution. |
| **`image_base64`** | Neither of the above is possible | **Roughly 350k tokens per megabyte of file.** Small files only. |

**Default to the presigned route** if you have a shell or any HTTP client. It is
the only one that is both free in context and unlimited in file size.

`image_base64` exists so that a caller with no shell and no hosting is not stuck.
It is not a convenience — a 3MB logo inlined as base64 will consume most of a
context window. Reach for it last.

### With the MCP server

One tool, `upload_design`, does all three:

```
upload_design({ source_url: "https://…/client-logo.png" })
→ { status: "completed", design_uuid: "…", url: "…" }

upload_design({ filename: "client-logo.png", content_type: "image/png" })
→ { mode: "presigned", upload_url: "…", image_uuid: "…", next_step: "…" }
   … you PUT the bytes …
upload_design({ image_uuid: "…" })
→ { status: "completed", design_uuid: "…" }

upload_design({ image_base64: "<base64>", filename: "seal.png" })
→ { status: "completed", design_uuid: "…" }
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

**Accepted: PNG, JPEG, WEBP.** PNG is the right default — it is the only one of
the three that carries transparency, and a logo that will sit on a coloured
garment needs a transparent background.

**Vector (SVG, AI, EPS) is not accepted.** Rasterize first:

- Render at the size you intend to print. 2000px on the long side is a safe
  default for apparel; match the print area for all-over print.
- Keep the background transparent if the mark should sit on the garment colour.
- Export PNG.

Rasterizing is not redrawing — it is the same artwork at a fixed resolution, so
it does not breach a "do not alter the mark" instruction. Generating a lookalike
would.

Ceiling is 50MB per file. Anything above the print maximum is scaled down on
ingest; anything below the 512px minimum is enlarged — which is where the next
section matters.

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

From here it is the normal pipeline — see
`references/product-creation-pipeline.md`. Two things worth knowing:

- **Transparency keying does not apply.** The chroma-key step exists because AI
  generators cannot produce real transparency, so we ask for a green background
  and key it out. A client's PNG either already has an alpha channel or it does
  not. Do not run it through the keyer hoping to improve it — if the background
  is opaque white and needs to be transparent, that is a question for the client
  ("do you have this with a transparent background?"), not something to guess at.
- **Quality checks still apply.** Run the mockup gate as usual and inspect the
  render at full size. A client file can still be too low-resolution, wrongly
  proportioned for the print area, or wrong for the garment colour.

Uploads are **storage-metered only** — they do not consume an AI image
generation. Uploading forty client assets costs zero generations. They do count
against the account's storage allowance.

---

## 5. When you are stuck

If you cannot upload — no shell, no hosting, file too large to inline — say so
plainly and name what you need:

> I need `client-logo.png` uploaded to the *Acme Co* workspace before I can build
> the paw-only tee. It is the client's own mark and they have asked that it not be
> redrawn, so I have not generated a substitute.

That is a complete, actionable request. Do not:

- generate a lookalike "just for the mockup" — a mockup gets shown to someone, and
  then it exists;
- build the rest of the range and quietly skip the blocked item without saying
  which one and why;
- describe the mark in a prompt and treat the result as the client's asset.
