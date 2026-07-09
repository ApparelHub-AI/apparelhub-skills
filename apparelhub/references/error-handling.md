# Error Handling

How to interpret API errors and the most common silent-failure modes.

---

## 1. HTTP status codes

| Status | What it means | What to do |
|---|---|---|
| 401 | API key missing or invalid | Verify the user's `APPARELHUB_API_KEY` env var. Have them generate a new one at `https://apparelhub.ai/developer/api-keys` if it's expired. |
| 402 | Account suspended — the owner's trial ended with no card on file; the account is read-only | `error=account_suspended`. The agent can't pay; tell the account OWNER to add a payment method at the `billing_url` in the body. Reads still work; only writes/quota/sync are blocked. Don't retry. See §2c. |
| 403 | User's tier doesn't include API access OR endpoint is admin-only OR JWT auth attempted from non-browser | If `code=tier_missing_api_access`, link the user to `https://apparelhub.ai/pricing` (Professional / Enterprise required). If the user tried JWT auth from curl, switch to the Agent API + API key. |
| 404 | Endpoint path wrong OR resource doesn't exist | Verify the path against `https://api.apparelhub.ai/agents/v1/openapi.json`. If the resource UUID is wrong, list to confirm. |
| 409 | Conflict — usually integration locked, sales channel uniqueness violation, or duplicate product | Read the error body. See "Common 409 codes" below. |
| 422 | Validation error — field-level issue with the request body | Read the error body. Field name mismatches are the most common cause (Phase 3 vs Phase 5 names — see `references/product-creation-pipeline.md`). |
| 429 | Rate limited | Backoff exponentially. Default tier is 10 req/sec, 10K/mo. Professional is 50 req/sec, 50K/mo. Enterprise is 200 req/sec, 500K/mo. |
| 500 | Server error | Retry ONCE with a 2-3s backoff. If it persists, capture the response body and tell the user there's a platform issue. Don't hammer it. |
| 502 / 503 / 504 | Upstream gateway or timeout | Backoff and retry up to 3 times with exponential delays. After that, it's a platform issue. |

---

## 2. Common 409 codes

### `integration_locked`

Sales channel integration is locked (admin lock OR per-merchant lock). Mutating operations (sync, order auto-submit, fulfillment notify) are blocked.

**What to tell the user:**
> "Your [Shopify/WC/Wix/Etsy] integration is locked. Unlock it in the store dashboard at `https://apparelhub.ai/stores/<store_uuid>` to allow sync."

If they don't know why it's locked, the audit log has the answer:
```bash
curl -sS "https://api.apparelhub.ai/agents/v1/store/<store_uuid>/audit-log?action=integration_locked" -H "x-api-key: $APPARELHUB_API_KEY"
```

### `sales_channel_uniqueness_violation`

The shop URL is already connected to a DIFFERENT user's account in the same environment. Each storefront (`your-store.myshopify.com`, `shop.example.com`, etc.) can be connected to exactly one ApparelHub user.

**What to tell the user:**
> "Your [Shopify/WC/Wix] store is already connected to another ApparelHub account. If that's also you, disconnect it from the other account first. If not, you'll need to use a different storefront."

### `order_linked_to_sales_channel`

Returned by `link-stripe-payment` when called on an order whose `ecommerce_external_id` is set. The storefront already processed the payment; we can't double-attribute by recording a Stripe charge.

**What to tell the user:**
> "This order was paid through [Shopify/WC/Wix/Etsy]'s payment gateway, not through ApparelHub's Stripe Connect. Payment is already recorded — no additional action needed."

(This is Absolute Rule 10 in action — see `references/orders-and-fulfillment.md` for the full payment-authority discussion.)

### `duplicate_product`

A product with this exact name + provider already exists for this user. Either rename the new product or update the existing one instead of creating.

---

## 2b. Workspace scoping errors (enterprise / agency accounts)

On Enterprise accounts each request acts within an active workspace, and the `?workspace=<uuid>` selector is validated. Most accounts have one Default workspace and never see these.

### `workspace_not_found` (404)

The `?workspace=` uuid doesn't resolve to any workspace.

**Fix**: correct the uuid, or omit the param (calls default to the account's Default workspace). There's no agent endpoint that lists workspaces — get the uuid from an asset's `workspaces` field or the web UI (Account → Team & Workspaces).

### `workspace_forbidden` (403)

The workspace exists but this key/user may not act in it. Either the user isn't assigned to it, or a **workspace-scoped key** was pointed at a workspace outside the one(s) it's scoped to.

**Fix**: target a workspace the caller can access. Don't retry with the same `?workspace=`.

### `forbidden` with a `capability` field (403)

A workspace-scoped key's role doesn't permit this action (e.g. `{"error":"forbidden","capability":"design.generate"}` on `POST /images/generate`). The account owner controls the key's role.

**Fix**: surface it; don't retry. Use an account-wide key or a key whose role holds the capability.

**A bad `?workspace=` fails the whole request** — there's no partial result. And a scoped list returning a SUBSET is not an error: see `references/workspaces.md` ("don't misread a scoped list as missing data").

---

## 2c. Account suspended (402) — trial ended, no card

When the account owner's invite-only trial expires with no payment method on
file, the account enters a **read-only freeze**. Any write / create /
quota-consuming / channel-push call returns **HTTP 402**:

```json
{
  "error": "account_suspended",
  "reason": "trial_expired",
  "tier": "Enterprise",
  "message": "This account's Enterprise trial has ended. The account owner must add a payment method in Billing to continue.",
  "billing_url": "https://apparelhub.ai/billing/subscription"
}
```

**Reads still work.** GET calls succeed — you can list/inspect stores, products,
designs, and orders. Only mutations are gated.

**Blocked (402):** image generation, product/store create + update, integration
connect/initiate, merchandise + ecommerce sync, order submit/confirm — every
write route, on both the web and agent APIs.

**What the agent should do:** you can't add a card on the owner's behalf. Stop
the write (don't retry — a 402 won't clear until a card is added) and tell the
human/owner:

> "This account's `<tier>` trial has ended, so it's read-only right now. The
> account owner needs to add a payment method at `<billing_url>` to continue.
> Everything you've built is safe, and full access resumes automatically once a
> card is added."

**Inbound orders are NOT dropped.** Storefront orders that arrive while suspended
are held and auto-release to fulfillment the moment the owner adds a card, so a
real customer who paid on the merchant's live store is never stranded.

---

## 2d. Mockup preview store selection errors

`POST /agents/v1/merchandise/product/preview` accepts an optional `store_uuid`
that pins mockup generation to a specific store's fulfillment-provider
connection. Two failure modes, both fail-loud by design (previously these
silently fell through to the platform's shared credentials):

### `provider_store_mismatch` (400)

The `store_uuid` you passed names a real, accessible store — but that store is
not connected to the merchandise provider in the request. Example: passing a
store that's only connected to one provider while creating a preview for a
different provider's catalog item.

**Recovery:** list the user's stores (`GET /agents/v1/store`), filter for one
whose `providers[]` contains an entry with the requested provider's uuid AND a
non-null `external_id`, and retry with that store — or omit `store_uuid`
entirely to use the account's first connected store for that provider.

### `store_not_found` (404)

The `store_uuid` doesn't exist or isn't accessible to the caller (wrong
workspace scoping is a common cause — see section 2b).

### The `connection` block — which credentials actually ran

The preview create response AND the job poll response carry an additive
`connection` object telling you which fulfillment connection was used:

```json
{
  "connection": {
    "store_uuid": "<store_uuid>",
    "store_name": "Acme Apparel",
    "shared": false
  }
}
```

- `shared: false` — the preview runs through the named store's own provider
  connection (either the `store_uuid` you passed, or the account's first
  connected store when you omitted it).
- `shared: true` (`store_uuid`/`store_name` null) — the account has no store
  connected to that provider, so the platform's shared credentials ran.
  Shared mode is subject to shared rate limits (the 429 with
  `action_required: "connect_store"`) — check `connection.shared` before
  assuming a merchant connection was used.

---

## 3. Sync failures — the silent class

The most common "I thought I synced this but customers don't see it" issues:

### `product not associated with store` (channel sync fails)

Symptom: `sync_to_channel` (or `?target=ecommerce`) fails with **"product not associated with store"** and the product is left created-but-unsynced. Classic in automated flows that jump `create_product` → `sync_to_channel`.

**Cause**: the product was never mapped to the store. `create_product` makes a STANDALONE product; a sales-channel listing requires the product to first be associated with the store AND synced to fulfillment.

**Fix**: run the "map to store" step first — `sync_to_fulfillment(product_uuid, store_uuid)` (MCP; it associates + fulfillment-syncs), or Phase 6 `POST /store/<s>/products` then Phase 7 `?target=merchandise` (REST) — then retry the channel sync. Better: use `ship_product`, which runs the whole ordered pipeline in one call. (MCP `sync_to_channel` v0.3.1+ auto-heals this and returns a `warnings[]` note, but the clean order is map-to-store first — and only sync to a channel at all if the user asked to list on a storefront.)

### Variants not yet created (Phase 5 skipped)

Phase 7 sync to `target=merchandise` returns `400 No valid variants found to sync`. The product has no rows in the variants table.

**Fix**: go back and run Phase 5 (one variant at a time, no batch endpoint). Verify with `GET /agents/v1/product/<uuid>/variants` before retrying sync.

### 0 variants added — the requested colors/sizes don't exist on the garment

Symptom: you called `add_variants` but the product ends with 0 (or fewer than expected) variants. On MCP v0.3.1+ `add_variants` throws `bad_request` listing the garment's real colors/sizes; older behavior returned `variants_added: 0` silently and shipped an unsellable product (this is what left a World-Cup Cap with 0 variants).

**Cause**: sizes are matched EXACTLY and you assumed apparel sizes (S/M/L/XL/2XL) for a garment that's one-size or uses different labels — caps, beanies, phone cases, bottles, bags, etc.

**Fix**: fetch the garment's real matrix (`GET /agents/v1/merchandise/<provider_uuid>/product/<product_ref_id>`, or the `get_garment_details` MCP tool) and build the variant list from the colors/sizes it actually offers. See `references/product-creation-pipeline.md` Phase 5.

### Fulfillment sync wasn't run before ecommerce sync (Phase 7 ordering)

Ecommerce sync (Shopify/Etsy/etc.) needs the fulfillment SKU to attach. If you try `target=ecommerce` before `target=merchandise`, the ecommerce sync may succeed cosmetically but the product won't have a manufacturing path.

**Fix**: ALWAYS run `?target=merchandise` first. Wait for it to return success. Then run `?target=ecommerce`.

### Integration credentials revoked

User disconnected the channel from apparelhub.ai, OR Shopify Token Exchange returned an unauthorized response, OR WooCommerce keys were rotated upstream without reconnecting.

**Diagnostic**: `GET /agents/v1/store/<store_uuid>/integrations` — check `is_connected` and `last_health_check_status`.

**Fix**: have the user reconnect the integration in the store dashboard.

### Display image is the raw design URL, not a mockup

Symptom: the product card thumbnail shows the flat design on a green background (or transparent checkerboard), not a real mockup.

**Cause**: no mockup was ever generated, so `display_image` fell back to `print_data[0].image_url` (the raw design). Common causes: you skipped Phase 3 entirely, OR (MCP split flow) you called `create_product` with `generate_mockup: true` but pre-0.3.1 that was a silent no-op unless `mockup_variant_ids` was ALSO passed — so no preview job was created. (Every product in the World-Cup automated run shipped this way.)

**Fix**: generate a mockup and attach it. Easiest: use `ship_product` (mockup is built in), or `create_product` with `generate_mockup: true` on MCP v0.3.1+ (it now auto-derives representative variants). To repair an existing product, `PATCH /agents/v1/product/<uuid>` with `display_image` set to a real mockup URL from the preview job's preview rows. See `references/product-creation-pipeline.md` Phase 3 + 4.0.

### Wrong field names in Phase 4 (product create)

Symptom: product was created, `uuid` returned, but `manufacturing_metadata` is NULL when you fetch it, and sync silently fails.

**Cause**: used `merchandise_provider_uuid` instead of `provider_uuid`, OR `provider_product_ref_id` instead of `product_ref_id`, OR `retail_price` instead of `price`. The Phase 3 preview endpoint uses the FIRST names; Phase 4 create endpoint uses the SECOND.

**Fix**: delete the broken product (`DELETE /agents/v1/product/<uuid>`) and re-create with the correct field names. See `references/product-creation-pipeline.md` Phase 4 for the gotcha table.

### Mockup `preview_url` is still NULL when you call create

Symptom: product created, but `display_image` auto-resolution picked the raw design URL instead of a mockup.

**Cause**: the preview job's status was `completed` but the S3 ingestion hadn't finished yet. There's a two-phase race — job complete is one thing, S3 mirror populated is another. Gap can be 20+ minutes.

**Fix**: poll the preview-job/previews endpoint until at least one row has a non-null `preview_url` BEFORE calling product create. Or PATCH the product's `display_image` after the fact.

---

## 4. Embroidery-specific failures

### `thread_colors_chest_left option is missing or incorrect`

The `options` block is at the wrong level in your sync payload (probably on the file inside `files[]` instead of at `sync_variants[i].options`).

**Fix**: see `references/embroidery.md` section 5 for the canonical shape. Move options out of the file and put them at the variant level.

### `Allowed values: #FFFFFF, #000000, ...` followed by the 15-color palette

You sent a color that's not in Printful's 15-thread palette.

**Fix**: re-pick thread colors from the design using the 15-color palette only. See `references/embroidery.md` section 1 for the palette + section 8 for the empirical color picker.

---

## 5. Diagnostic discipline

When a workflow fails:

1. **Read the actual response body**. ApparelHub returns structured error JSON; don't just look at the status code.
2. **Check the audit log** for the affected resource. `GET /agents/v1/store/<uuid>/audit-log?...` reveals every state transition with structured details.
3. **Verify the failing field via the OpenAPI spec**: `https://api.apparelhub.ai/agents/v1/openapi.json` (authed with the user's key). Field names drift; check the canonical source.
4. **Reproduce in isolation**. Don't retry an entire pipeline — pinpoint the failing phase and re-run just that one.
5. **Surface the truth to the user**. Don't paper over a real failure with a generic "sync had issues" message. Tell them what specifically failed and what the next step is.

---

## 6. When to give up and escalate

Tell the user to contact ApparelHub support at `support@apparelhub.ai` when:

- 500-class errors persist for >5 minutes across retries
- The OpenAPI spec disagrees with observed API behavior (suggests a deploy in progress OR a real bug)
- An order is stuck in `submitted` for >24 hours with no `ORDER_CONFIRMED` audit row and no error in the log
- An integration that was healthy yesterday returns 401 today with no merchant-side change (suggests credential rotation upstream)
- A sync succeeded according to the API but the product genuinely doesn't appear on the storefront after >15 minutes (verify on the channel admin, not just the public storefront)

Don't escalate for things you can fix: wrong field names, missing variants, draft/live state, locked integrations the merchant can unlock themselves.
