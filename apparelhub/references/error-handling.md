# Error Handling

How to interpret API errors and the most common silent-failure modes.

---

## 1. HTTP status codes

| Status | What it means | What to do |
|---|---|---|
| 401 | API key missing or invalid | Verify the user's `APPARELHUB_API_KEY` env var. Have them generate a new one at `https://apparelhub.ai/developer/api-keys` if it's expired. |
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
ah_curl GET /agents/v1/store/<store_uuid>/audit-log?action=integration_locked
```

### `sales_channel_uniqueness_violation`

The shop URL is already connected to a DIFFERENT user's account in the same environment. Each storefront (`apparelhubai.myshopify.com`, `wp.merctech.io`, etc.) can be connected to exactly one ApparelHub user.

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

## 3. Sync failures — the silent class

The most common "I thought I synced this but customers don't see it" issues:

### Variants not yet created (Phase 5 skipped)

Phase 7 sync to `target=merchandise` returns `400 No valid variants found to sync`. The product has no rows in the variants table.

**Fix**: go back and run Phase 5 (one variant at a time, no batch endpoint). Verify with `GET /agents/v1/product/<uuid>/variants` before retrying sync.

### Fulfillment sync wasn't run before ecommerce sync (Phase 7 ordering)

Ecommerce sync (Shopify/Etsy/etc.) needs the fulfillment SKU to attach. If you try `target=ecommerce` before `target=merchandise`, the ecommerce sync may succeed cosmetically but the product won't have a manufacturing path.

**Fix**: ALWAYS run `?target=merchandise` first. Wait for it to return success. Then run `?target=ecommerce`.

### Integration credentials revoked

User disconnected the channel from apparelhub.ai, OR Shopify Token Exchange returned an unauthorized response, OR WooCommerce keys were rotated upstream without reconnecting.

**Diagnostic**: `GET /agents/v1/store/<store_uuid>/integrations` — check `is_connected` and `last_health_check_status`.

**Fix**: have the user reconnect the integration in the store dashboard.

### Display image is the raw design URL, not a mockup

Symptom: the product card thumbnail shows the flat design on a green background (or transparent checkerboard), not a real mockup.

**Cause**: `display_image` was set to `print_data[0].image_url` (the raw design) instead of a `preview_url` from the preview job.

**Fix**: `PATCH /agents/v1/product/<uuid>` with `display_image` set to a real mockup URL from the preview job's preview rows. See `references/product-creation-pipeline.md` Phase 4.0 for the picker logic.

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
