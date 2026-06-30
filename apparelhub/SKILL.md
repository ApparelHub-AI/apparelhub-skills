---
name: apparelhub
description: Manage the full custom-merchandise pipeline via the ApparelHub multi-channel ecommerce platform: design with AI, build products, list, sell, and fulfill across your sales channels. Use whenever the user wants to create AI-generated designs, generate mockups, build products, sync listings to Shopify/Etsy/WooCommerce/Wix, manage orders, or check fulfillment status.
tools: Bash, WebFetch, Read, Write
---

<!--
This YAML frontmatter is for Claude Code's skill-discovery layer. Other
agents (ChatGPT, Gemini, bare-HTTP) can ignore it — the rest of this
document is host-neutral.
-->

# ApparelHub Skill

ApparelHub is a multi-channel ecommerce platform for custom merchandise. Use
this skill when the user wants to:

- Design AI-generated apparel (tees, hoodies, embroidered apparel,
  water bottles, pillows, doormats, luggage tags)
- Generate product mockups on physical garments
- Create products and sync them to sales channels
  (Shopify, Etsy, WooCommerce, Wix)
- Manage orders and fulfillment via Printful / Printify
- Browse the catalog of garments available for printing

You talk to ApparelHub via its Agent API at
`https://api.apparelhub.ai/agents/v1/`. That's the only host this skill
ever sends an API key to.

This document is host-agnostic — any AI agent capable of making HTTP
requests can drive the platform from this skill alone. If you're a
specific kind of agent (Claude Code, a ChatGPT Custom GPT, a Gemini
tool-calling agent, or a bare-HTTP runtime), there's a porting guide
tailored to you under `porting-guides/` in the same repo.

This SKILL.md is the router. Detailed playbooks live in `references/`
and end-to-end walkthroughs in `examples/`. Load them on demand. Don't
try to memorize the entire skill upfront.

---

## 1. Authentication

Every API call needs the header:

```
x-api-key: <your API key>
```

How the agent sources that key depends on the runtime:

- **The recommended pattern** is that the agent reads
  `APPARELHUB_API_KEY` from its runtime environment (`os.environ`,
  `process.env`, etc.) at call time. The skill does NOT ask you to
  persist the key to disk and does NOT read it from any config file.
- **For tool-calling agents** (ChatGPT Custom GPT with Actions, Gemini
  function calling): hide the key inside the function-call
  implementation so the agent never sees it. See
  `../porting-guides/chatgpt-gemini.md` for the pattern.
- **For Claude Code** (and similar shell-based agents): use whatever
  mechanism you normally use for development secrets — direnv, shell
  rc, macOS Keychain, etc.

**If your runtime prompts the first time it reads this environment
variable or makes a network call, that is correct behavior.** Approve
the prompt in context if the call is one you intended. The skill no
longer ships wrappers whose purpose is to dodge those prompts (see
`../SECURITY.md`).

### Sanity-check the key before a multi-step workflow

`scripts/ah_check` (optional, Claude Code convenience) verifies that
`APPARELHUB_API_KEY` is set AND accepted by the platform, then prints a
masked confirmation:

```
ah_check
```

Exit codes: `0` valid, `2` not set, `3` rejected by the platform or
network failure. Equivalent plain HTTP probe:

```
curl -sS -o /dev/null -w "%{http_code}\n" \
  https://api.apparelhub.ai/agents/v1/store \
  -H "x-api-key: $APPARELHUB_API_KEY"
```

`200` means the key works. Anything else, fix the key before continuing.

**Local key hygiene on shared machines:** `-H "x-api-key: ..."` puts the
key value in the process argv, where `ps` (and other local users) can read
it for the request's duration. On a multi-user box, pass the header via a
curl config on stdin instead, so the key never reaches argv:

```
curl -sS https://api.apparelhub.ai/agents/v1/store --config - <<CFG
header = "x-api-key: $APPARELHUB_API_KEY"
CFG
```

The plain `-H` form is fine on a single-user machine. `scripts/ah_check`
already uses the stdin-config form.

### The canonical OpenAPI spec

```
GET https://api.apparelhub.ai/agents/v1/openapi.json
```

Authoritative reference for every endpoint and field. When you're
unsure about a field name or response shape, fetch the spec.

---

## 2. The product-creation pipeline at a glance

Going from "user wants a saguaro tee" to "product is live on their
Shopify store" takes 7 phases. Execute IN ORDER:

1. **Generate the design image.** `POST /images/generate` with a prompt (slow models, including the Nano Banana default, return **202 + `image_uuid`** and must be polled with `ah_poll_generation`; fast models return 200 + `url`)
2. **LOCAL transparency processing** (your compute, NOT an API call). For
   standard apparel only; SKIP for all-over print
3. **Generate the mockup.** `POST /merchandise/product/preview`
4. **Pick `display_image` + build `gallery_images` from preview rows**
5. **Create the product.** `POST /product/create`
6. **Add variants** (one at a time, no batch endpoint)
7. **Associate with store + sync to fulfillment + sync to sales
   channels.** Default to DRAFT, not live

**Full pipeline detail (every call, every field, every gotcha) lives in
`references/product-creation-pipeline.md`.** Read it before executing
any phase you haven't done in this session.

**The four field-name gotchas that silently break products** are
documented there and worth memorizing:

- Phase 3 preview endpoint uses `merchandise_provider_uuid` +
  `provider_product_ref_id`
- Phase 5 create endpoint uses `provider_uuid` + `product_ref_id`
- Same data, FLIPPED names. Don't copy field names between phases.
- Use `price`, not `retail_price`.

---

## 3. Decision tree: which reference file to load

Before executing a workflow, scan this tree. Loading the right
reference up front saves you from shipping a broken product.

| If the task involves… | Read FIRST |
|---|---|
| Talking to the Agent API at all | `references/api-contract.md` covers the HTTP contract — base URL, auth header, every endpoint, every status code |
| Generating ANY design image | `references/design-rules.md` covers AI prompt anti-patterns, transparency, vision-verification of text |
| **Editing / iterating on an existing design** (user says "make the cat smug", "redo this in landscape", "use this as a starting point") | `references/design-rules.md` section 5b explains how `POST /images/generate` doubles as the img2img endpoint via `source_image_uuid` or multipart `images=@...`. Only Nano Banana and OpenAI support edit; Replicate-backed sources 422. |
| Standard apparel (tees, hoodies, tanks, sweatshirts) | `references/product-creation-pipeline.md` |
| **Embroidered apparel** (Champion Anorak, polos, embroidered hats, jackets) | `references/embroidery.md` covers the 15-color thread palette + the `thread_colors_<placement>` option-placement trap. Skipping this guarantees a 400 from Printful. |
| All-over print (pillows, doormats, area rugs, luggage tags, AOP tees, phone cases, mugs) | `references/all-over-print.md` covers edge-to-edge background rules, product-specific gotchas, the "don't name the product in the AI prompt" trap |
| Variant IDs, pricing, color limit, BC 3001 vs Comfort Colors trade-off | `references/garment-catalog.md` |
| Listing/inspecting orders, payment status, fulfillment status | `references/orders-and-fulfillment.md` includes the payment-authority rule (sales channel wins for storefront orders) |
| **Managing orders** — approving/confirming/holding, the per-store fulfillment workflow (auto / confirm / review), smart guardrails, the agent approval queue, the opt-in signed callback | `references/orders-and-fulfillment.md` sections 8–10. Note the TWO distinct holds (ApparelHub approval vs Printful design hold). |
| A 4xx / 5xx response, sync that didn't take, "Failed to fetch" UX | `references/error-handling.md` |
| **Enterprise / agency account** (multiple workspaces; a list looks like it's "missing" stores/products/designs, or you need to target a specific client workspace) | `references/workspaces.md` covers the `GET /agents/v1/workspaces` discovery route, the `?workspace=` param, the `workspaces` visibility field, 403/404 handling, and workspace-scoped keys |

When the user asks for an end-to-end flow ("build me a saguaro tee and
sync it"), the `examples/` directory has working walkthroughs you can
adapt:

| If the user wants… | Read |
|---|---|
| A front-print tee end-to-end | `examples/front-print-tee.md` |
| An all-over-print pillow / doormat / luggage tag | `examples/all-over-pillow.md` |
| An embroidered chest crest on a jacket / polo | `examples/embroidered-anorak.md` |
| Reviewing + approving a held order as an agent (workflow config → poll the queue → approve/hold) | `examples/order-management.md` |

---

## 4. Top-level safety rails

These apply across every workflow. Don't override without explicit user
instruction.

### 4a. Default to DRAFT, never live

When syncing to a sales channel that supports a draft state (Etsy,
Shopify), push as DRAFT first. The user reviews the listing on the
channel's admin before customers see it. Only push as `active` when
the user EXPLICITLY says "make it live" or "publish it." The cost of a
too-eager publish (typo'd title in front of real customers) is much
higher than the cost of one extra click.

Tell the merchant:

> "I've synced as drafts so you can review on your storefront before
> going live. To publish, flip the listing in your channel admin or
> re-run sync with `?listing_state=active`."

### 4b. Verify the design before creating the product

**Always** visually inspect the design after Phase 1 AND the mockup
after Phase 3. Never ship a broken design or mockup downstream because
manufacturing follows the mockup.

Specifically: if the design contains TEXT, verify spelling with vision
tools BEFORE generating the mockup. AI image models routinely misspell.

### 4c. Respect pricing floors

The merchant loses money on negative-margin products. Never go below
the recommended retail prices in `references/garment-catalog.md`
without the user explicitly accepting the math.

### 4d. Color discipline: max 4 colors per design

More than 4 color variants creates SKU sprawl that hurts conversion.
Pick the 4 best colors for the design and stop.

### 4e. Embroidery is stitched, not printed

For embroidered products, design colors must come from Printful's
15-color thread palette. Designs with gradients, photorealism, or fine
detail will NOT translate. See `references/embroidery.md`.

### 4f. Ask the user before syncing anywhere

Create the product, add variants, add to the store. STOP. Tell the
user what's ready and ask whether to sync to fulfillment and/or to
which sales channels. Sync is a state-changing operation that costs the
merchant time to undo if you got it wrong.

---

## 5. Working with the user's existing data

```
GET https://api.apparelhub.ai/agents/v1/store
GET https://api.apparelhub.ai/agents/v1/store/<store_uuid>/products?fields=uuid,name,price,status,thumbnail_url,fulfillment_status,ecommerce_statuses
GET https://api.apparelhub.ai/agents/v1/images/generated?limit=20&sort=newest
GET https://api.apparelhub.ai/agents/v1/orders?limit=10
GET https://api.apparelhub.ai/agents/v1/orders/<uuid>
```

For order data interpretation (payment status, fulfillment status, who
actually charged the card), see `references/orders-and-fulfillment.md`.

On an **Enterprise (agency) account**, every list/get above is scoped to one
**active workspace** (the Default workspace unless you pass `?workspace=<uuid>`).
If a list looks like it's missing stores/products/designs, you're probably
scoped to a different workspace, not missing data. See section 6.

---

## 6. Workspaces (enterprise accounts)

Most accounts have a single workspace and can ignore this. On **Enterprise
(agency) accounts** the account is split into isolated client / brand
**workspaces**, and every Agent API call acts within ONE of them.

- **Discover them.** `GET /agents/v1/workspaces` lists the workspaces this key
  can act in (`uuid` + `name` + `is_default`), the active workspace, and whether
  the key is pinned. Use it to turn a workspace name the user mentions into the
  `uuid` you scope with — do this first whenever the user names a workspace.
- **Default scope.** With no `?workspace=` param, calls act in the account's
  **Default** workspace.
- **Target a workspace.** Add `?workspace=<workspace_uuid>` to any list / get /
  create call (combines with `?limit=`, `?fields=`, etc.).
- **A bad workspace fails the whole call** (no silent fallback): an unknown
  uuid returns `404 workspace_not_found`; a real-but-inaccessible workspace
  returns `403 workspace_forbidden`.
- **Don't misread a subset as missing data.** A scoped list shows that
  workspace's assets, not the whole account. Products and generated images
  carry a `workspaces` array (every workspace they belong to); stores carry
  `workspace_uuid` / `workspace_name`. Check those before reporting "nothing
  there," then re-issue with the right `?workspace=`.
- **Workspace-scoped keys.** An API key can be pinned to one workspace + role
  in the web UI. It rejects a different `?workspace=` with `403
  workspace_forbidden`, and a role lacking design-generation gets `403
  forbidden` (`capability: design.generate`) on `POST /images/generate`.

Full contract (param, error bodies, Model A visibility, scoped keys, worked
curls) is in **`references/workspaces.md`**. Single-workspace and
non-Enterprise accounts are unaffected.

---

## 7. When NOT to use this skill

- **The user wants to BUY a finished product.** ApparelHub is for
  merchants designing + selling, not end-shoppers. Direct them to the
  merchant's storefront.
- **Generic image generation unrelated to apparel.** Use OpenAI /
  Stability directly; ApparelHub charges against the user's image quota.
- **Platform admin operations** (register your Etsy webhook URLs,
  rotate your Shopify secret). These are done in the apparelhub.ai web
  UI, not via the agent API.
- **Bulk operations beyond ~50 products at once.** The agent API
  enforces rate limits; for true bulk migrations (1000+ products), the
  user should contact ApparelHub support.

---

## 8. Reporting back to the user

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

---

## Security and trust model

See `../SECURITY.md` for the trust model, non-goals (we don't bypass
your platform's permission prompts; we don't persist your API key to
disk; we never send the key anywhere but `https://api.apparelhub.ai`),
and the threat model.
