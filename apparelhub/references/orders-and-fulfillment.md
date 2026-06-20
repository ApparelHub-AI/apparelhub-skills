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

**The sales channel is the AUTHORITATIVE source of payment status for any order that originated from a storefront** (Shopify, WooCommerce, Wix, Etsy, future channels). ApparelHub MIRRORS the storefront's payment state — it does NOT independently process card charges for these orders.

| Order origin | `payment_method` | Who charged the card | What does `payment_status` mean? |
|---|---|---|---|
| Storefront order (Shopify, WC, Wix, Etsy) | `sales_channel` | The storefront's own payment gateway | Mirror of the storefront's payment state. We didn't touch the money. |
| Manual ApparelHub order with "Pay with credit card" via Stripe Connect | `stripe` | ApparelHub via Stripe Connect | We actually processed the charge. `stripe_payment_intent_id` and `stripe_charge_id` are populated. |
| Manual order, no payment | `manual` | Nobody (yet) | Awaiting payment. May be linked later via `link-stripe-payment` (off-platform sale) OR via `link-ecommerce-order` (if it gets matched to a storefront order). |

### Why this matters

If a merchant asks "did I receive payment for order #155733798?", and that order's `payment_method=sales_channel`, the answer is "yes, the customer paid via [Shopify/WC/Wix/Etsy]'s payment gateway. The funds settle in your sales-channel account on their normal schedule."

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

### "Why hasn't this order shipped?"

Check `fulfillment_status` and the order's audit trail. Common causes:
- `payment_status` still `pending` — fulfillment doesn't submit until payment confirms (auto-submit gates on paid)
- `requires_approval=true` (held by `hold_orders_above_amount`) — merchant has to approve manually
- Provider has a SKU mapping issue (look in audit log for `auto_submit_sku_unmapped`)
- Provider rejected the submission (look in audit log for `provider_submit_failed`)

### "Was this order successfully submitted to Printful?"

Look for `ORDER_CREATED` and `ORDER_CONFIRMED` rows in the order's audit log:
- `ORDER_CREATED` means draft submitted to provider
- `ORDER_CONFIRMED` means draft flipped to production
- BOTH should exist for an order in `in_production` or beyond

If `ORDER_CREATED` exists but `ORDER_CONFIRMED` doesn't, the order is stuck in draft on the provider's side — usually because `auto_fulfill_on_payment` was off OR the merchant cancelled before confirmation.

### "My storefront shows the order as paid/cancelled/shipped but ApparelHub doesn't (or vice-versa)"

The two drifted — usually a missed webhook. Run a reconcile (section 11): it pulls the latest payment/cancellation from the channel and pushes the latest fulfillment/tracking to it, then tells you exactly what it changed.

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

When a guardrail trips, the order is held with `hold_reason` set to one of
`high_value` / `low_margin` / `negative_margin`; review-mode holds use
`review_mode`.

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
