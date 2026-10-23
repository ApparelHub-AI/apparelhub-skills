# Orders & Fulfillment — Reading Order Data Correctly

How to interpret order data, payment status, and fulfillment state without giving the merchant misleading answers.

---

## 1. List orders

```bash
curl -sS "https://api.apparelhub.ai/agents/v1/orders?limit=10" -H "x-api-key: $APPARELHUB_API_KEY"
```

Useful filters:
- `?status=pending|in_production|shipped|delivered|cancelled`
- `?store_uuid=<uuid>` to scope to one store
- `?since=<iso8601>` for orders since a date

## 2. Order detail

```bash
curl -sS "https://api.apparelhub.ai/agents/v1/orders/<uuid>" -H "x-api-key: $APPARELHUB_API_KEY"
```

Key fields:
- `payment_status` — `paid` / `pending` / `refunded` / `partial`
- `payment_method` — `sales_channel` / `stripe` / `manual`
- `fulfillment_status` — `pending` / `submitted` / `in_production` / `shipped` / `delivered` / `cancelled`
- `shipments[]` — multiple shipments possible (a multi-item order may ship in batches). Each has `carrier`, `tracking_number`, `tracking_url`, `shipped_at`, `delivered_at`.
- `items[]` — line items. Each has `thumbnail_url` (the product mockup), `variant`, `quantity`, `price`.

---

## 3. ⚠️ Payment authority — sales channel wins for storefront orders

This is the rule that prevents you from giving merchants wrong answers about who charged the customer's card.

### The rule

**The sales channel is the AUTHORITATIVE source of payment status for any order that originated from a storefront** (Shopify, WooCommerce, Wix, TikTok Shop, future channels). ApparelHub MIRRORS the storefront's payment state — it does NOT independently process card charges for these orders.

| Order origin | `payment_method` | Who charged the card | What does `payment_status` mean? |
|---|---|---|---|
| Storefront order (Shopify, WC, Wix, TikTok Shop) | `sales_channel` | The storefront's own payment gateway | Mirror of the storefront's payment state. We didn't touch the money. |
| Manual ApparelHub order with "Pay with credit card" via Stripe Connect | `stripe` | ApparelHub via Stripe Connect | We actually processed the charge. `stripe_payment_intent_id` and `stripe_charge_id` are populated. |
| Manual order, no payment | `manual` | Nobody (yet) | Awaiting payment. May be linked later via `link-stripe-payment` (off-platform sale) OR via `link-ecommerce-order` (if it gets matched to a storefront order). |

### Why this matters

If a merchant asks "did I receive payment for order #155733798?", and that order's `payment_method=sales_channel`, the answer is "yes, the customer paid via [Shopify/WC/Wix/TikTok Shop]'s payment gateway. The funds settle in your sales-channel account on their normal schedule."

DO NOT say "ApparelHub received the payment" — we didn't. DO NOT look for a Stripe charge ID on a `sales_channel` order — there isn't one.

If a merchant wants to attach a Stripe charge to a storefront-linked order via `link-stripe-payment`, that endpoint REFUSES with `400 order_linked_to_sales_channel`. That's by design — the storefront's payment gateway charged the card, not us, and recording a Stripe charge would double-attribute the payment.

---

## 4. Fulfillment status interpretation

| Status | Meaning |
|---|---|
| `pending` | Order received, not yet submitted to fulfillment provider |
| `submitted` | Draft created on Printful/Printify, awaiting confirmation OR awaiting payment |
| `in_production` | Production has started on the fulfillment provider's side |
| `shipped` | At least one shipment has left the warehouse — see `shipments[]` for tracking |
| `delivered` | Carrier reports delivered |
| `cancelled` | Order cancelled. See `cancellation_reason` if present. |

### Multi-shipment orders

A single order can split into multiple shipments — for example, a 5-item order where 2 items are produced at one Printful facility and 3 at another, OR an order where 1 item ships earlier than the rest.

Always iterate `shipments[]` to give the merchant the complete tracking picture, not just `response_data.tracking_number` (which is the FIRST shipment only).

Example summary:
> "Order #155733798 has 3 shipments: 2 already in transit (UPS tracking 1Z..., 1Z...), 1 still in production at the Printful Charlotte facility."

---

## 5. Order cancellation

Orders can be cancelled from either side:
- Merchant clicks "Cancel" in apparelhub.ai → we call the fulfillment provider's cancel endpoint
- Storefront cancellation (Shopify/WC/Wix order moves to `cancelled` state) → webhook arrives, we cascade-cancel the local order AND attempt to cancel on the fulfillment provider

The audit log records exactly what happened:
- `details.provider_cancel.status = "success"` — fulfillment provider confirmed cancel
- `details.provider_cancel.status = "not_found"` — order didn't exist on the provider's side (already cleaned up OR never submitted)
- `details.provider_cancel.status = "failed"` — provider returned an error; check `details.provider_cancel.error`
- `details.provider_cancel.status = "not_attempted"` — we didn't call the provider (typically because the order never reached the submitted state)

If a customer asks "did my order get cancelled," check the local order status AND the audit trail for the `provider_cancel.status`. Local cancelled + provider success = clean cancel. Local cancelled + provider failed = the merchant may still get charged by the provider; flag this.

---

## 6. Reading fulfillment provider data on the order

The order object includes provider-side metadata in `manufacturing_metadata`:
- `provider_order_id` — external ID on Printful/Printify
- `provider_status` — provider's view of order state (may lag our `fulfillment_status` by a few minutes due to webhook delivery)
- `estimated_ship_date` — provider's promise

When these conflict with our `fulfillment_status`, our status is the source of truth (we update it from webhooks AND from order-detail polling). If they disagree by more than a few hours, surface to support — it suggests a webhook miss.

---

## 7. Common questions and how to answer

### "Did the customer pay for this order?"

Check `payment_status`. If `paid`, AND `payment_method=sales_channel`, the storefront processed the charge — say so explicitly. If `payment_method=stripe`, ApparelHub processed via Stripe Connect — say so. If `pending`, the customer hasn't paid yet.

### "Where is my order?"

Iterate `shipments[]`. Give the merchant tracking numbers + carrier + URLs for each shipment. If `fulfillment_status` is `in_production`, tell them no shipments have left yet — production is in progress.

### ⚠️ `needs_attention`: the order will NOT complete on its own

Every order returned by `GET /orders` and `GET /orders/<uuid>` carries `needs_attention`. It's `null` when nothing needs the merchant. Otherwise it's `{kind, severity, title, message}` and **you must tell the user**, quoting `message`:

| `kind` | What happened | What to suggest |
|---|---|---|
| `provider_failed` | The fulfillment provider rejected the order (billing, address, print files). It shows as cancelled, but it's fixable. | Fix the cause the message names (for example, add a payment method in the provider account), then resubmit. |
| `provider_cancelled` | The provider cancelled the order. The buyer paid and nothing will ship. | Find out why with the provider; refund or recreate the order. |
| `cancel_not_stopped` | The buyer cancelled on the sales channel, but production had already started, so it will still ship. | Contact the provider to try to stop it, and handle the refund on the channel. |
| `not_submitted` | Paid, but never sent to the provider (often the channel hasn't released the shipping address yet). Retried hourly. If the channel's ship-by deadline is close or passed, the message says so and `severity` is `error`. | Wait, or push it with `submit-fulfillment` once the address exists. If the deadline is close, treat it as urgent. |
| `ship_by_at_risk` | The sales channel's ship-by deadline (`ship_by_at`) is within a day and the order hasn't shipped. | Check what's holding it (provider status, holds) and get it moving now. |
| `ship_by_missed` | The ship-by deadline passed and the order hasn't shipped. Late shipping updates can count against the merchant's shop. | Get it shipped as soon as possible, and suggest messaging the buyer that it's on the way. |
| `channel_tracking_failed` | The order shipped, but the sales channel refused the tracking update, so the buyer can't see tracking there. Retried automatically. | Quote the channel's reason. The merchant can add the tracking number on the channel directly. |

**`ship_by_at`** is the sales channel's ship-by deadline in UTC (set for TikTok Shop orders, `null` when the channel has none). When the merchant asks "is anything urgent?", sort open orders by it.

An ordinary `cancelled` with `needs_attention: null` is a cancellation the merchant or buyer made and that was honoured. Nothing to do. ApparelHub also alerts the merchant in-app and by email for each of these, so you can say "you should also have an email about this." MCP: `list_my_orders` and `get_order_details` return the same field.

### Orders fulfilled by the merchant's store (`fulfilled_by: "merchant"`)

After a merchant imports their channel catalog (`catalog-import.md`), an order for one of their
own products, the ones not made in ApparelHub, is recorded with `fulfilled_by: "merchant"`. An
ApparelHub-fulfilled order has `fulfilled_by: null`.

- **Their store fulfils it.** ApparelHub never sends it to a fulfillment provider, so it has no
  `fulfillment_provider_name` and never shows `needs_attention`.
- **Don't try to act on it.** Approve, submit, confirm, cancel, hold, record payment and item
  edits all return `409 {"error": "fulfilled_by_merchant"}`. That's expected, not a failure: tell
  the merchant to ship, cancel or refund it in their store.
- **Its status follows the channel.** `POST /orders/{uuid}/reconcile` pulls the store's own status
  (shipped, delivered, cancelled) onto it.
- **Filter:** `GET /orders?fulfilled_by=merchant` lists only these; `?fulfilled_by=apparelhub`
  lists only the orders ApparelHub fulfils.
- **Revenue is reported apart.** The orders dashboard summary carries a separate
  `merchant_fulfilled` block, and analytics label them `merchant:<channel>` on the fulfillment
  dimension. Their cost is outside ApparelHub, so they never count toward margin.
- **Notifications are opt-in.** The store setting `notify_on_tracked_orders` (off by default)
  decides whether the merchant is notified about them. They're recorded either way.

MCP: `list_my_orders` and `get_order_details` return `fulfilled_by`, and `list_my_orders` takes
the same filter.

### "Why hasn't this order shipped?"

Check `fulfillment_status` and the order's audit trail. Common causes:
- `payment_status` still `pending` — fulfillment doesn't submit until payment confirms (auto-submit gates on paid)
- `requires_approval=true` (held by `hold_orders_above_amount`) — merchant has to approve manually
- Provider has a SKU mapping issue (look in audit log for `auto_submit_sku_unmapped`)
- Provider rejected the submission (look in audit log for `provider_submit_failed`)
- **The order is paid and approved but was never sent to the provider** (`fulfillment_status` is `pending`/`approved`, no provider order id). Usually the sales channel had not released the buyer's shipping address yet: TikTok Shop withholds it for a while after an order is placed. Look on the timeline for `awaiting_recipient_address` or `submit_failure_alerted` (`kind: address_pending`). ApparelHub retries these automatically every hour and alerts the merchant in-app and by email; to push one through now, `POST /orders/<uuid>/submit-fulfillment` (an empty body is fine). See "Approve can succeed while the submit fails" below.

### "Was this order successfully submitted to Printful?"

Look for `ORDER_CREATED` and `ORDER_CONFIRMED` rows in the order's audit log:
- `ORDER_CREATED` means draft submitted to provider
- `ORDER_CONFIRMED` means draft flipped to production
- BOTH should exist for an order in `in_production` or beyond

If `ORDER_CREATED` exists but `ORDER_CONFIRMED` doesn't, the order is stuck in draft on the provider's side — usually because `auto_fulfill_on_payment` was off OR the merchant cancelled before confirmation.

### "My storefront shows the order as paid/cancelled/shipped but ApparelHub doesn't (or vice-versa)"

The two drifted — usually a missed webhook. Run a reconcile (section 11): it pulls the latest payment/cancellation from the channel and pushes the latest fulfillment/tracking to it, then tells you exactly what it changed.

### "An order was placed on my Shopify store but ApparelHub never got it at all"

Reconcile needs an order to reconcile. When the order is missing entirely, run a
sync, which asks the connected Shopify shop for recent orders and imports the
ones ApparelHub should have received:

```bash
curl -sS -X POST "https://api.apparelhub.ai/agents/v1/orders/sync" \
  -H "x-api-key: $APPARELHUB_API_KEY" -H 'Content-Type: application/json' \
  -d '{"store_uuid": "<store_uuid>"}'      # omit the body to sync every store
```

What it imports is deliberately narrow, because an imported paid order is sent
to the fulfillment provider exactly as a live one would be: only orders placed
**after the shop was connected**, not cancelled, not already fulfilled on
Shopify, and not placed in the last few minutes (that webhook is still on its
way). It also refreshes the store's fulfillment-provider order statuses, and
today's analytics for any store that gained orders.

Read the response, don't just report the count:

- `shopify[].processed` — imported by this call; `skipped_already_present` — were
  already here (the webhook did arrive).
- `shopify[].not_eligible_reasons` — e.g. `{"fulfilled_upstream": 2}`. These are
  decisions, not failures: tell the merchant why an order was left alone.
- `shopify[].truncated: true` — more orders exist than one call reads; run it again.
- `shopify[].outcome: "auth_revoked"` with `reconnect_url` — the shop's access
  was revoked; the merchant must open that link to re-authorize before any
  order can arrive.
- `errors[]` — anything that failed, per order. Surface it.

---

## 8. The configurable fulfillment workflow (read + set it)

Each store has a **fulfillment workflow** that decides what happens to a paid
order before it reaches the manufacturer. As an agent you can read it and set it.

```bash
# Read the store's workflow + notification settings
curl -sS "https://api.apparelhub.ai/agents/v1/store/<store_uuid>/settings" \
  -H "x-api-key: $APPARELHUB_API_KEY"

# Set it
curl -sS -X PATCH "https://api.apparelhub.ai/agents/v1/store/<store_uuid>/settings" \
  -H "x-api-key: $APPARELHUB_API_KEY" -H "Content-Type: application/json" \
  -d '{"fulfillment_mode":"review","approval_authority":"agent"}'
```

### `fulfillment_mode` — how much to automate

| Mode | What happens on a paid order |
|---|---|
| `auto` | Draft created on the provider, then auto-confirmed → production. Hands off. |
| `confirm` | Draft created automatically; waits for ONE confirm before production. |
| `review` | Held BEFORE submission; requires approval, then drafts + proceeds. Safest. |

### `approval_authority` — who handles an order that needs review

| Authority | Meaning for you (the agent) |
|---|---|
| `human` | Held orders wait in the merchant's dashboard. You are NOT expected to act. |
| `agent` | Held orders are YOURS to decide — poll the queue (section 9) and act via the API. |
| `rules` | Orders flow through automatically; only guardrail trips stop, then routed to you. |

### Smart guardrails (escalate an otherwise-auto order to review)

- `hold_orders_above_amount` (number or null) — hold when order total exceeds this.
- `hold_below_margin_pct` (number or null) — hold when profit margin % is below this.
- `hold_on_negative_margin` (bool) — always hold an order that would lose money.
- `hold_first_time_customer` (bool) — hold the first order from a new customer.
- `hold_channel_risk_review` (bool, **ON by default**) — hold an order the SALES
  CHANNEL has flagged as under its own risk review.

When a guardrail trips, the order is held with `hold_reason` set to one of
`high_value` / `low_margin` / `negative_margin` / `first_time_customer` /
`channel_risk_review`; review-mode holds use `review_mode`.

### `channel_risk_review` behaves differently from the others — know this before you act

The other guardrails only apply once the store's `fulfillment_mode` has already
let an order through. This one **overrides the mode, including `auto`**, because
the signal is not our judgement about the order — it is the channel saying it may
still void the sale. Sending it to fulfillment would mean paying to print a
garment for an order that can disappear.

What that means for you:

- **Do not "fix" it by flipping the store to `auto`.** It will still hold. If a
  merchant genuinely wants these orders to flow, the setting to change is
  `hold_channel_risk_review: false`, and that is their call, not yours.
- **The next step is usually to WAIT, not to decide.** A `channel_risk_review`
  hold typically clears on its own when the channel finishes reviewing, unlike
  `high_value` or `low_margin`, which wait on a human. Reconciling the order
  (section 12) pulls the channel's current state on demand.
- The order is fully visible and real — `payment_status` is `paid`, because the
  buyer WAS charged. Only fulfillment is held.

---

## 9. Acting on orders that need a decision (the agent approval loop)

### The queue (poll-first — the guaranteed path)

```bash
curl -sS "https://api.apparelhub.ai/agents/v1/orders?requires_approval=true&store_uuid=<store_uuid>" \
  -H "x-api-key: $APPARELHUB_API_KEY"
```

Each held order already carries everything you need to decide — no extra
round-trip: `hold_reason`, `total_price`, `cost_total`, `profit_margin`,
`fulfillment_status` (`on_hold`), and `items[]`.

### The actions

```bash
# Release the hold and send the order onward (the ApparelHub-side approval)
curl -sS -X POST ".../agents/v1/orders/<uuid>/approve" -H "x-api-key: $APPARELHUB_API_KEY"

# ⚠️ Approve can succeed while the submit fails. For a sales-channel order the
# approve ALSO submits to the provider, and it returns 200 either way. Always
# read the result:
#   "auto_submitted": false  -> approved, but NOT in production
#   "submit_error": "..."     -> why
#   "submit_error_kind": "address_pending" -> the channel has not released the
#        shipping address yet; ApparelHub retries hourly and alerts the merchant.
#        Tell the user, then re-check later (or submit-fulfillment, below).
#   "submit_error_kind": "other" -> needs a fix first. Tell the user the reason.
# Never report "approved, it's on its way" without checking auto_submitted.

# Push a paid order that never reached its provider (empty body = use the
# stored/channel shipping address)
curl -sS -X POST ".../agents/v1/orders/<uuid>/submit-fulfillment" -H "x-api-key: $APPARELHUB_API_KEY" \
  -H 'Content-Type: application/json' -d '{}'

# Flip an existing draft to production (when the order is already a draft)
curl -sS -X POST ".../agents/v1/orders/<uuid>/confirm" -H "x-api-key: $APPARELHUB_API_KEY"

# Keep it held with a reason / cancel it
curl -sS -X POST ".../agents/v1/orders/<uuid>/hold"   -H "x-api-key: $APPARELHUB_API_KEY" -d '{"reason":"manual review"}'
curl -sS -X POST ".../agents/v1/orders/<uuid>/cancel" -H "x-api-key: $APPARELHUB_API_KEY"
```

### ⚠️ There are TWO different "holds" — don't confuse them

| | ApparelHub approval hold | Printful design-approval hold |
|---|---|---|
| What | The store's workflow held the order BEFORE it was sent to the manufacturer (review mode / a guardrail trip) | The manufacturer (Printful) paused an order it already accepted (design/address review) |
| Signal | `fulfillment_status` = `on_hold`, `requires_approval` = true, `hold_reason` set | `fulfillment_substatus` set (e.g. `design_approval_pending`); an entry in `GET /orders/<uuid>/holds` |
| How to act | `POST /orders/<uuid>/approve` (or `hold` / `cancel`) | `GET /orders/<uuid>/holds` then `POST /orders/<uuid>/holds/<hold_uuid>/approve` or `.../request-changes` |

The approval hold is yours to clear via the workflow. The Printful design hold
often returns a deep link to resolve on Printful's side — relay it to the
merchant rather than guessing.

---

## 10. Opt-in callback (so you don't have to poll constantly)

Set an `agent_callback_url` (https) in the store settings and you get a signing
secret back **once** (`agent_callback_secret` in the PATCH response — store it;
it is never shown again). After that, when an order is held for an
`agent`/`rules` store we POST an `order.awaiting_approval` event to your URL:

- Header `X-ApparelHub-Event: order.awaiting_approval`
- Header `X-ApparelHub-Signature: sha256=<hex>` where `<hex>` is
  `HMAC-SHA256(secret, raw_request_body)`.

Verify before trusting it:

```python
import hmac, hashlib
expected = 'sha256=' + hmac.new(secret.encode(), raw_body, hashlib.sha256).hexdigest()
assert hmac.compare_digest(expected, request.headers['X-ApparelHub-Signature'])
```

The body carries the order summary + `actions` (relative approve/confirm/hold/
cancel paths). Delivery is best-effort: **polling the queue in section 9 is the
guaranteed path**, so a missed callback is just a missed nudge, never lost work.

---

## 11. Reconcile a sales-channel order with its channel

When a **sales-channel order** (Shopify / WooCommerce / Wix / TikTok Shop) drifts
out of sync with the channel it came from — a missed webhook, a status that
changed on only one side — reconcile it:

```bash
ah_curl POST /orders/<order_uuid>/reconcile
```

This applies only to orders that **originated from a connected store** (the order
has an `ecommerce_provider_name`). Native ApparelHub orders (built in the app /
manual) have no channel to reconcile against — the call returns
`reconcilable: false` and changes nothing, and you should not offer it for them.

It uses a **field-aware direction model** (the channel owns money, ApparelHub +
the fulfillment provider own production):

| Concern | Direction |
|---|---|
| Payment paid / refunded | **Pull** from the channel (it's authoritative) |
| Order cancellation | **Pull** from the channel |
| Fulfillment status + shipment tracking | **Push** to the channel |

It pulls **fresh** data from the channel on every call (no stale cache). The
response is a structured summary — it never throws for the normal skip cases:

```json
{
  "reconcilable": true,
  "provider": "Shopify",
  "applied_count": 1,
  "changes": [
    {"field": "payment_status", "direction": "pull", "from": "pending", "to": "paid", "applied": true}
  ],
  "errors": []
}
```

- `reason` (when `applied_count` is 0 and nothing ran): `not_a_sales_channel_order`,
  `integration_inactive`, or `integration_locked`.
- `errors[]` surfaces real conflicts — e.g. the channel cancelled an order
  ApparelHub already **shipped** (`phase: "apply_cancel"`). Reconcile never fakes
  a cancel on a shipped order; it reports the conflict so a human can decide.
- Every run writes a committed `order_reconciled` audit row, and any applied
  change adds a "Synced with <channel>" entry to the order timeline.

**Automatic reconcile:** a store owner can turn on `auto_reconcile_orders` (Store
Settings → Order sync, or `PATCH /store/<uuid>/settings`). When on, a background
worker reconciles the store's open sales-channel orders on a schedule. The manual
call above always works regardless of that setting.

## 12. Edit a draft order's items (add another variant before confirm)

You can add or remove items on an order **while it is still a DRAFT** (before it
is confirmed to production) — e.g. add another color/size of the same product.
This is the ONLY window for editing items; once the order is confirmed / in
production it is locked.

```
# Add an item (e.g. another variant of the same product)
POST /agents/v1/orders/<order_uuid>/items      {"variant_uuid": "...", "quantity": 1, "custom_price": 24.99, "shipping_cost": 5.00}

# Remove a line item (order must keep at least one)
DELETE /agents/v1/orders/<order_uuid>/items/<order_item_id>

# Replace the whole item set (bulk / quantity edits)
PUT /agents/v1/orders/<order_uuid>/items       {"items": [{"variant_uuid": "...", "quantity": 2, "custom_price": 24.99}], "shipping_cost": 5.00}
```

**Pricing on an edit (optional):**
- **`custom_price`** — per **item**, the per-unit retail price. Omit it and the
  item uses the variant's own price. (This is the retail price the customer pays;
  for Printful/Gelato it also flows to the provider draft as the retail price.)
- **`shipping_cost`** / **`tax`** — per **order** (top-level, not per item), the
  order-level retail shipping and tax. These are what the customer pays, NOT the
  provider's own shipping cost (the provider computes that itself). Omit them and
  the order's existing shipping/tax are preserved. The order total is always
  re-priced as `subtotal + shipping_cost + tax`. Negative values are rejected.

MCP tools: `add_order_item` (accepts `custom_price` + `shipping_cost`),
`remove_order_item`.

**How each provider applies the edit (automatic — you don't choose):**

| Provider | Under the hood |
|----------|----------------|
| Printful, Gelato | Edits the existing provider draft **in place** (same order id). |
| Printify | No edit API, so it **cancels + re-creates** the order (a NEW order id). Nothing is charged on a draft, so this is safe. |

The order detail carries **`supports_in_place_order_edit`** (true = in place;
false = will cancel + re-create) so you can tell the user in advance. The edit
result's **`edit_method`** is `in_place`, `recreated` (with a new
`fulfillment_external_id`), or `local` (no provider draft yet).

**Errors:** `409 order_not_editable` (already confirmed — not editable),
`409 variant_not_synced` (sync the product first), `403 variant_not_in_store`,
`400 items_empty` (can't remove the last item — cancel the order instead),
`502 provider_edit_failed` (retry-eligible). Editing never touches the
create/submit/confirm flow — it only changes the draft's items and re-prices.
