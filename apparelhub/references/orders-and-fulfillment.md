# Orders & Fulfillment — Reading Order Data Correctly

How to interpret order data, payment status, and fulfillment state without giving the merchant misleading answers.

---

## 1. List orders

```bash
curl -sS "https://api.apparelhub.ai/agents/v1/orders?limit=10" \
  -H "x-api-key: $APPARELHUB_API_KEY"
```

Useful filters:
- `?status=pending|in_production|shipped|delivered|cancelled`
- `?store_uuid=<uuid>` to scope to one store
- `?since=<iso8601>` for orders since a date

## 2. Order detail

```bash
curl -sS "https://api.apparelhub.ai/agents/v1/orders/<uuid>" \
  -H "x-api-key: $APPARELHUB_API_KEY"
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
