---
name: apparelhub
description: Design custom apparel and sync print-on-demand products to merchant stores via the ApparelHub platform. Use whenever the user wants to create AI-generated apparel designs, generate mockups, build products, sync to Shopify/Etsy/WooCommerce/Wix, manage orders, or check fulfillment status.
tools: Bash, WebFetch, Read, Write
---

# ApparelHub Skill

ApparelHub is a print-on-demand design and orchestration platform. Use this skill when the user wants to:

- Design AI-generated apparel (tees, hoodies, embroidered apparel, water bottles, pillows, doormats, luggage tags)
- Generate product mockups on physical garments
- Create products and sync them to sales channels (Shopify, Etsy, WooCommerce, Wix)
- Manage orders and fulfillment via Printful / Printify
- Browse the catalog of garments available for printing

You talk to ApparelHub via its Agent API at `https://api.apparelhub.ai/agents/v1/`.

This SKILL.md is the router. Detailed playbooks live in `references/` and end-to-end walkthroughs in `examples/`. Load them on demand — don't try to memorize the entire skill upfront.

---

## 1. Authentication — ALWAYS use `ah_curl`

Every API call needs the user's ApparelHub API key in the `x-api-key` header. **Do NOT compose `curl ... -H "x-api-key: $APPARELHUB_API_KEY"` yourself** — Claude Code's permission system prompts on any command containing `$VAR` expansion regardless of how broad your allowlist is. The bundled `scripts/ah_curl` wrapper hides the env-var read INSIDE the script so your command line stays expansion-free.

### How to invoke

The wrapper lives at `~/.claude/skills/apparelhub/scripts/ah_curl` (or the equivalent install path). Invoke by full path:

```bash
~/.claude/skills/apparelhub/scripts/ah_curl GET /agents/v1/store
```

If the user has added `~/.claude/skills/apparelhub/scripts` to their PATH (see the repo README's install section), the bare invocation works too:

```bash
ah_curl GET /agents/v1/store
```

The allowlist patterns in `settings.recommended.json` match BOTH forms.

### Argument shape

```
ah_curl METHOD PATH_OR_URL [extra curl args...]
```

- `METHOD` — `GET`, `POST`, `PATCH`, `PUT`, `DELETE` (uppercase, no `-X` prefix)
- `PATH_OR_URL` — an absolute path (prepended with `https://api.apparelhub.ai`) or a full URL
- Extra args pass through to curl unchanged: `-d '{...}'` for JSON bodies, `-F image=@/tmp/x.png` for multipart, `-o /tmp/out` to save the response

### Examples

```bash
ah_curl GET /agents/v1/store
ah_curl POST /agents/v1/images/generate -d '{"prompt":"...","source":"Nano Banana"}'
ah_curl POST /agents/v1/images/generated/abc-123/transform -F image=@/tmp/design_transparent.png
ah_curl PATCH /agents/v1/product/abc-123 -d '{"display_image":"https://..."}'
ah_curl DELETE /agents/v1/product/abc-123
```

### Start every session with `ah_check`

Run `ah_check` as the FIRST call of any session. It verifies that `APPARELHUB_API_KEY` is set AND valid against the live API, then prints a masked confirmation line.

```bash
ah_check
```

Exit codes:
- **0** — key is set and valid. Output looks like `ah_check: ok (key ah_xxxx...yyyy)`. Proceed.
- **2** — key is not set in the environment. Tell the user:
  > You need an ApparelHub API key. Generate one at https://apparelhub.ai/developer/api-keys (requires Professional or Enterprise tier). Then run: `export APPARELHUB_API_KEY=ah_xxx...`
- **3** — key is set but rejected (401/403). Likely revoked, expired, or from the wrong environment. Tell the user to check `https://apparelhub.ai/developer/api-keys`.

**Do not echo the key yourself.** `echo "${APPARELHUB_API_KEY:?...}"` contains shell expansion (`${...}`) and will prompt on every invocation regardless of allowlist. `ah_check` is the prompt-free equivalent that also validates against the platform.

(`ah_curl` itself also exits 2 on a missing key — so even if you skip `ah_check`, your first real API call surfaces the same error. The advantage of `ah_check` is catching it BEFORE you've started a multi-step workflow.)

### Other packaged helpers (use these instead of inline bash)

The skill ships a small set of additional scripts that exist for the same reason `ah_curl` does — they keep the agent's visible command line expansion-free and single-target so Claude Code's safety checks don't fire on every call. Always invoke them by name or full path, NEVER reproduce their logic inline.

| Script | Replaces | When to invoke |
|---|---|---|
| `ah_poll_mockup` | A `for`/`while` loop polling `/merchandise/product/preview/<provider>/job/<job>` with `status=...; if "$s" = ...` checks | Phase 3 — after `POST /merchandise/product/preview` returns a `job_uuid`. Polls until the job is completed AND at least one preview row has `preview_url` populated, in ONE call. |
| `ah_classify_previews` | A `python3 -c "import json; ..."` heredoc parsing the preview rows by color + angle | Phase 4.0 — after `ah_poll_mockup` succeeds. Classifies all preview rows AND (with `--recommend`) writes a JSON file with the best `display_image` + a curated `gallery_images` list ready to paste into the product create body. |
| `ah_pick_provider_url` | A `jq` filter walking the previews array for a specific color+angle | Anywhere you need ONE specific mockup URL (e.g., "download the black front mockup to verify visually before product creation"). |
| `ah_pick_dimensions` | Inline math + the agent eyeballing the 80-90% rule | Phase 3 — after Phase 2 produces the cropped transparent design. Computes correct `(width, height, left, top)` from the design's actual aspect ratio + the garment's print area + a placement style. Without it the agent routinely produces too-small chest prints. |
| `make_transparent.py` | Inline Pillow `python3 -c "..."` snippets | Phase 2 — local transparency processing (see `references/design-rules.md`). v1.8: rejects non-#00FF00 backgrounds by default (catches AI ignoring the prompt) and auto-crops to the design's bounding box. |

All four (plus `ah_curl` and `ah_check`) live in `scripts/` and are matched by the patterns in `settings.recommended.json`. The pipeline reference (`references/product-creation-pipeline.md`) and the end-to-end examples in `examples/` show concrete invocations.

**General rule:** if you find yourself writing more than ONE shell line for a workflow step — a `for` loop, a `&&`-chained pair of commands, a `python3 -c` heredoc — stop and check whether there's a packaged script for it. Inline multi-line bash WILL trip the simple_expansion or multi-redirect checks regardless of how broad the allowlist is.

### Spec lookup

The canonical OpenAPI spec lives at `https://api.apparelhub.ai/agents/v1/openapi.json` — fetch it the same way as any other GET:

```bash
ah_curl GET /agents/v1/openapi.json
```

When in doubt about field names, fetch the spec.

---

## 1a. Use LITERAL values, never shell variables

The same `simple_expansion` rule that forced `ah_curl` also applies to captured UUIDs, URLs, and anything else you'd typically store in a shell variable. **DON'T** do this:

```bash
PRODUCT_UUID=$(ah_curl POST /agents/v1/product/create -d '...' | jq -r '.product.uuid')
ah_curl POST /agents/v1/product/$PRODUCT_UUID/variants -d '...'   # ← $PRODUCT_UUID triggers prompt
```

**DO** capture the value in your OWN reasoning context (parse the JSON, remember the UUID), then paste it LITERALLY into the next command:

```bash
ah_curl POST /agents/v1/product/create -d '...'
# Response: {"product": {"uuid": "abc-123-def-456", ...}}
# (You read the UUID from the output and substitute it inline below.)
ah_curl POST /agents/v1/product/abc-123-def-456/variants -d '...'
```

The agent IS the orchestrator. Don't delegate state to the shell. This applies to every UUID, URL, integration ID, job ID, etc. that you capture between API calls.

---

## 2. The product-creation pipeline at a glance

Going from "user wants a saguaro tee" to "product is live on their Shopify store" takes 7 phases. Execute IN ORDER:

1. **Generate the design image** — POST `/images/generate` with a prompt
2. **LOCAL transparency processing** (your compute, NOT an API call) — for standard apparel only; SKIP for all-over print
3. **Generate the mockup** — POST `/merchandise/product/preview`
4. **Pick `display_image` + build `gallery_images` from preview rows**
5. **Create the product** — POST `/product/create`
6. **Add variants** (one at a time, no batch endpoint)
7. **Associate with store + sync to fulfillment + sync to sales channels** — default to DRAFT, not live

**Full pipeline detail (every curl, every field, every gotcha) lives in `references/product-creation-pipeline.md`.** Read it before executing any phase you haven't done in this session.

**The four field-name gotchas that silently break products** are documented there and worth memorizing:
- Phase 3 preview endpoint uses `merchandise_provider_uuid` + `provider_product_ref_id`
- Phase 5 create endpoint uses `provider_uuid` + `product_ref_id`
- Same data, FLIPPED names — don't copy field names between phases
- Use `price`, not `retail_price`

---

## 3. Decision tree — which reference file to load

Before executing a workflow, scan this tree. Loading the right reference up front saves you from shipping a broken product.

| If the task involves… | Read FIRST |
|---|---|
| Generating ANY design image | `references/design-rules.md` — AI prompt anti-patterns, transparency, vision-verification of text |
| **Editing / iterating on an existing design** (user says "make the cat smug", "redo this in landscape", "use this as a starting point") | `references/design-rules.md` section 5b — `POST /images/generate` doubles as the img2img endpoint via `source_image_uuid` or multipart `images=@...`. Only Nano Banana and OpenAI support edit; Replicate-backed sources 422. |
| Standard apparel (tees, hoodies, tanks, sweatshirts) | `references/product-creation-pipeline.md` |
| **Embroidered apparel** (Champion Anorak, polos, embroidered hats, jackets) | `references/embroidery.md` — the 15-color thread palette + the `thread_colors_<placement>` option-placement trap. Skipping this guarantees a 400 from Printful. |
| All-over print (pillows, doormats, area rugs, luggage tags, AOP tees, phone cases, mugs) | `references/all-over-print.md` — edge-to-edge background rules, product-specific gotchas, the "don't name the product in the AI prompt" trap |
| Variant IDs, pricing, color limit, BC 3001 vs Comfort Colors trade-off | `references/garment-catalog.md` |
| Listing/inspecting orders, payment status, fulfillment status | `references/orders-and-fulfillment.md` — INCLUDES the payment-authority rule (sales channel wins for storefront orders) |
| A 4xx / 5xx response, sync that didn't take, "Failed to fetch" UX | `references/error-handling.md` |

When the user asks for an end-to-end flow ("build me a saguaro tee and sync it"), the `examples/` directory has working walkthroughs you can adapt:

| If the user wants… | Read |
|---|---|
| A front-print tee end-to-end | `examples/front-print-tee.md` |
| An all-over-print pillow / doormat / luggage tag | `examples/all-over-pillow.md` |
| An embroidered chest crest on a jacket / polo | `examples/embroidered-anorak.md` |

---

## 4. Top-level safety rails

These apply across every workflow. Don't override without explicit user instruction.

### 4a. Default to DRAFT, never live
When syncing to a sales channel that supports a draft state (Etsy, Shopify), push as DRAFT first. The user reviews the listing on the channel's admin before customers see it. Only push as `active` when the user EXPLICITLY says "make it live" or "publish it." The cost of a too-eager publish (typo'd title in front of real customers) is much higher than the cost of one extra click.

Tell the merchant:
> "I've synced as drafts so you can review on your storefront before going live. To publish, flip the listing in your channel admin or re-run sync with `?listing_state=active`."

### 4b. Verify the design before creating the product
**Always** visually inspect the design after Phase 1 AND the mockup after Phase 3. Never ship a broken design or mockup downstream — manufacturing follows the mockup.

Specifically: if the design contains TEXT, verify spelling with vision tools BEFORE generating the mockup. AI image models routinely misspell.

### 4c. Respect pricing floors
The merchant loses money on negative-margin products. Never go below the recommended retail prices in `references/garment-catalog.md` without the user explicitly accepting the math.

### 4d. Color discipline — max 4 colors per design
More than 4 color variants creates SKU sprawl that hurts conversion. Pick the 4 best colors for the design and stop.

### 4e. Embroidery is stitched, not printed
For embroidered products, design colors must come from Printful's 15-color thread palette. Designs with gradients, photorealism, or fine detail will NOT translate. See `references/embroidery.md`.

---

## 5. Working with the user's existing data

```bash
# List the user's stores
ah_curl GET /agents/v1/store

# List products on a specific store (use ?fields= to trim payload)
# Substitute the literal store UUID before invoking.
ah_curl GET /agents/v1/store/<store_uuid>/products?fields=uuid,name,price,status,thumbnail_url,fulfillment_status,ecommerce_statuses

# List the user's AI-generated images
ah_curl GET /agents/v1/images/generated?limit=20&sort=newest

# List orders (then drill into one)
ah_curl GET /agents/v1/orders?limit=10
ah_curl GET /agents/v1/orders/<uuid>
```

For order data interpretation (payment status, fulfillment status, who actually charged the card), see `references/orders-and-fulfillment.md`.

---

## 6. When NOT to use this skill

- **The user wants to BUY a finished product.** ApparelHub is for merchants designing + selling, not end-shoppers. Direct them to the merchant's storefront.
- **Generic image generation unrelated to apparel.** Use OpenAI / Stability directly; ApparelHub charges against the user's image quota.
- **Platform admin operations** (register your Etsy webhook URLs, rotate your Shopify secret). These are done in the apparelhub.ai web UI, not via the agent API.
- **Bulk operations beyond ~50 products at once.** The agent API enforces rate limits; for true bulk migrations (1000+ products), the user should contact ApparelHub support.

---

## 7. Reporting back to the user

After completing a workflow, give a tight summary:

- What you generated (design URL)
- The mockup link (so they can verify visually)
- The product page URL: `https://apparelhub.ai/merchandise/my-products`
- Which channels you synced to + sync status (draft vs live)
- Anything that didn't succeed and why

Don't dump raw JSON. Users want outcomes, not API responses.

---

## Quick links

- Product manager: `https://apparelhub.ai/merchandise/my-products`
- Generated designs: `https://apparelhub.ai/images/gallery`
- Stores: `https://apparelhub.ai/stores`
- Orders: `https://apparelhub.ai/orders`
- API keys: `https://apparelhub.ai/developer/api-keys`
- Live API docs (browser): `https://apparelhub.ai/developer/api-docs`
- Live API spec (JSON, authed): `https://api.apparelhub.ai/agents/v1/openapi.json`
- Pricing tiers: `https://apparelhub.ai/pricing`
