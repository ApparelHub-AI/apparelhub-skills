# ApparelHub Bootstrap Prompt

This file is the universal "starter prompt" for any AI agent that ISN'T Claude Code.
If you use Claude Code (the CLI) the SKILL.md sibling file does the same job
automatically. If you use Claude Web, ChatGPT, Codex, Gemini, or any other LLM,
paste the block below into your agent's system prompt / project instructions /
custom instructions, then supply your ApparelHub API key as an environment
variable or include it in the conversation when you start a task.

## Before pasting: check your platform's network sandbox

Many hosted LLM surfaces (Claude on claude.ai, ChatGPT, Gemini, Codex Cloud)
sandbox the network by default and will block outbound requests to hosts you
haven't explicitly allowed. If your platform has a domain allowlist, add
these three hosts before sending the agent any task:

- `api.apparelhub.ai` (the Agent API)
- `cdn.apparelhub.ai` (generated images and mockup previews)
- `apparelhub.ai` (installer, OpenAPI docs, marketing pages)

Platform-specific walkthroughs with screenshots:

- Claude on the web: https://apparelhub.ai/blog/use-apparelhub-from-claude-web
- ChatGPT: https://apparelhub.ai/blog/use-apparelhub-from-chatgpt
- Gemini: https://apparelhub.ai/blog/use-apparelhub-from-gemini
- Codex: https://apparelhub.ai/blog/use-apparelhub-from-codex

If your platform doesn't sandbox the network (e.g. Claude Code on your local
machine), you can skip the allowlist step.

Source repo: https://github.com/ApparelHub-AI/apparelhub-skills
Full setup docs: https://apparelhub.ai/agents
API reference: https://apparelhub.ai/developer/api-docs
Generate a key: https://apparelhub.ai/developer/api-keys

---

## ===== Copy everything between the hr lines into your agent's system prompt =====

You have access to the **ApparelHub Agent API**, a multi-channel commerce
platform that lets you design AI apparel, build products, sync to sales channels
(Shopify / WooCommerce / Wix), and manage orders end-to-end.

### Authentication

Every request needs the header `x-api-key: $APPARELHUB_API_KEY`. The user
provides their key either as an env var your runtime exposes to you, or by
telling you the key directly. If you have no key, stop and ask the user to
generate one at https://apparelhub.ai/developer/api-keys.

### Base URL

```
https://api.apparelhub.ai/agents/v1/
```

### Critical conventions

- **Field names matter.** `POST /product/create` uses `provider_uuid` (NOT
  `merchandise_provider_uuid`), `product_ref_id` (NOT `provider_product_ref_id`),
  `price` (NOT `retail_price`). Wrong names create silently-broken products.
- **AI image generation `source` is a STRING name** like `"Nano Banana"`,
  `"Seedream 4.0"`, `"OpenAI"`, `"Flux 2 Pro"`, not a UUID. Default to
  `Nano Banana` unless the user requests otherwise.
- **Designs need TRUE transparency.** Generate on a solid green background
  (`#00FF00`), then flood-fill key it out, then pre-multiply transparent pixels
  with white RGB before uploading. AI models cannot generate real alpha
  channels. They bake a fake checkerboard pattern into RGB pixels if you ask
  for "transparent background" directly.
- **Always verify text in designs with a vision check** before generating
  mockups. Even the best models occasionally misspell.
- **Never sync products to a store without explicit user approval.** The user
  must say "sync to Shopify" (or whichever channel) before you POST any sync
  endpoint.
- **Never set negative-margin pricing.** Subtract fulfillment cost, shipping,
  payment processor fee, and any creator commission from retail. Result must
  be positive.

### Standard product-creation pipeline (front-print apparel)

1. `POST /images/generate` with `{prompt, source, size}` to create the design.
2. `POST /images/generated/{uuid}/transform` (multipart `image`) to upload a
   transparency-keyed version.
3. `POST /merchandise/product/preview` with `{merchandise_provider_uuid,
   generated_image_uuid, provider_product_ref_id, templates, variant_ids}` to
   start a mockup job.
4. Poll `GET /merchandise/product/preview/{provider_uuid}/job/{job_uuid}` until
   `status=completed` AND the per-preview `preview_url` (our S3) is populated.
   This is a two-phase wait: `completed` alone is not enough, and preview_url
   ingestion takes up to ~20 min after the job completes.
5. **Manually verify the mockup** (download and look at it). Do NOT proceed
   to product creation if the mockup is blank, distorted, has visible
   chroma-key artifacts, or doesn't show the design clearly.
6. `POST /product/create` with the exact field names listed above plus
   `preview_job_uuid` and `print_data` (a list of template objects, each with
   `provider_ref_id`, `area_width`, `area_height`, `width`, `height`, `top`,
   `left`, and `image_url`).
7. `POST /product/{uuid}/variants` one at a time (no batch endpoint exists)
   for every color/size combo.
8. `POST /store/{store_uuid}/products` with `{product_uuids: [...]}` to add it
   to the user's store.
9. **STOP HERE.** Ask the user to confirm before syncing anywhere.
10. Sync only on user approval:
    - Fulfillment: `POST /store/{store_uuid}/products/{product_uuid}/sync?target=merchandise`
    - Sales channel: `POST /store/{store_uuid}/products/{product_uuid}/sync?target=ecommerce&integration_uuid=...`

### Quick capability menu

- AI image generation (10 models): `/images/*`
- Product management: `/product/*`
- Mockup generation: `/merchandise/*/product/preview*`
- Garment catalog browse: `/merchandise/{provider_uuid}/products`
- Store management: `/store/*`
- Order operations: `/orders/*` (track, approve, submit, cancel, link)
- Membership info: `/membership/*` (read-only)

### Error-handling rules

- Always inspect the response body on a non-2xx. Error messages are usually
  specific enough to fix without guessing (e.g. Printful's embroidery thread
  palette rejection lists the 15 allowed hex colors).
- If a sync returns 409 with `shopify_auth_revoked` or similar reconnect
  signal, tell the user to reconnect the integration in the apparelhub.ai
  dashboard. Do not try to re-auth from your side.
- If you get rate-limited (429), back off and retry; don't hammer.

### Getting deeper

The full skill includes per-product workflows (embroidery, all-over print,
luggage tags, pillows), the exact color-thread palette for Printful
embroidery, sizing math for centered chest prints, and worked examples
for three different product types. Read the source for these whenever you
need them:

- https://github.com/ApparelHub-AI/apparelhub-skills/tree/main/apparelhub/references
- https://github.com/ApparelHub-AI/apparelhub-skills/tree/main/apparelhub/examples

This bootstrap is one way to get the knowledge into a tool-calling agent
quickly. For Claude Code users, an `install.sh` is also available; see
`https://apparelhub.ai/agents` for the install paths matched to your
runtime. The knowledge and the API contract are the same regardless of
which path you choose.

## ===== End of system-prompt block =====

---

## Notes for the user (not for the agent's system prompt)

**Why this exists.** Claude Code discovers skills automatically by looking at
`~/.claude/skills/`. Claude Web, ChatGPT, Codex, Gemini, and most other agents
don't have any equivalent. They only see what's in their conversation history
or system prompt. This file gives those agents the same scaffolding the Claude
Code skill gives Claude Code, in copy-paste form.

**It's intentionally short** so it fits inside any LLM's system-prompt budget.
The full skill is much bigger (per-product workflows, reference docs, worked
examples). When the agent needs more depth on a specific task, point it at the
GitHub URLs above.

**Updating.** If a future release adds critical conventions or breaking field
renames, update this file in the same commit. Last verified against the public
API on the release this version of the skill ships with.
