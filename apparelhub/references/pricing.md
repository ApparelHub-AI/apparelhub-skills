# Costs, margins & pricing

Setting a product's retail price to hit a target margin is one of the
most common merchant tasks — and the cost data you need is NOT where
you'd first look. Read this before pricing anything by margin.

---

## 1. Where per-variant cost lives (the read path)

The authoritative per-variant production cost is on
`variants[].cost`, returned by the **store products list**:

```
GET https://api.apparelhub.ai/agents/v1/store/<store_uuid>/products
```

Each product in that list carries a `variants` array, and each variant
has `cost` (the provider's production cost) alongside `price` (the
retail price you set), `uuid`, `color`, `size`, `sku`,
`provider_variant_id`. Example variant:

```json
{ "uuid": "…", "color": "White", "size": "2XL",
  "cost": 21.68, "price": 25.51, "provider_variant_id": "104651" }
```

**Cost is populated by the fulfillment sync.** A freshly-created product
has no cost until you sync it to its fulfillment provider
(`POST /store/<store>/products/<product>/sync?target=merchandise`) — that
sync is when the provider returns real production cost per variant. So
the order is always: create → add variants → associate with store →
**sync to fulfillment (populates cost)** → read costs → set prices.

### Two traps that make cost look "unavailable"

- **The product-detail endpoint omits it.**
  `GET /agents/v1/product/<uuid>` does NOT include the `variants` array
  at all, so it shows no cost. Use the **store products list** above.
- **Catalog cost can be `null`.** The catalog/browse cost
  (`GET /agents/v1/merchandise/<provider>/product/<ref>` variants, and
  the product's `provider-options`) is the *supplier catalog* cost, and
  some providers (notably **Printify**) return it as `null` there. Do
  NOT conclude "this product has no cost" from a null catalog price —
  the real per-variant cost appears on the *product's* variants after
  the fulfillment sync.

---

## 2. Cost varies by size

Provider costs tier up by size — larger sizes (2XL, 3XL) cost more than
S–XL, often by several dollars. So a single flat retail price gives a
**different margin on every size** (and can be negative on the largest).
Read each variant's own `cost` and price each variant individually
(§3) rather than assuming one cost for the product.

---

## 3. Recipe: price a product to a target margin

"Margin" here is profit as a share of the selling price:
`margin = (price − cost) / price`. To hit a target margin `m`, the
price for a variant is:

```
price = cost / (1 - m)
```

(e.g. a 15% margin on a $16.81 cost → 16.81 / 0.85 = **$19.78**.
Verify: (19.78 − 16.81) / 19.78 = 15.0%.)

Steps:

1. **Sync to fulfillment first** so costs exist (§1).
2. **Read costs** from `GET /store/<store>/products` → each variant's
   `uuid` + `cost`.
3. **Compute** `price = round(cost / (1 - m), 2)` per variant.
4. **Apply per variant** with:
   ```
   PUT /agents/v1/product/<product_uuid>/variants/<variant_uuid>
   { "name": "<Color> / <Size>", "color": "…", "size": "…", "price": <price> }
   ```
   Loop over the variants (one PUT each).
5. **Re-sync the sales channel** so the storefront picks up the new
   prices: `POST /store/<store>/products/<product>/sync?target=ecommerce&integration_uuid=<uuid>`.

> **Note:** a bulk variant-price endpoint
> (`PATCH /product/<uuid>/variants/bulk`) exists but is unreliable
> today — use the per-variant `PUT` loop above.

---

## 4. Pricing floors (never price below these)

Negative margin = the merchant loses money. Minimum retail prices that
produce positive margin on the standard fee structure:

| Garment | Approx fulfillment cost | Recommended retail |
|---|---|---|
| BC 3001 Standard Tee | ~$11.69 | **$27.99** |
| BC 3001 Influencer Tee | ~$11.69 | **$29.99** |
| Comfort Colors Tee | ~$14.69 | **$34.99** |
| BC 6400 Women's Relaxed | ~$13.69 | **$34.99** |
| BC 3719 Pullover Hoodie | ~$25.50 | **$54.99** |
| BC 4719 Heavyweight Hoodie | ~$36.50 | **$64.99** |
| AOP Athletic Tee | ~$22.00 | **$44.99** |
| Piqué Polo (DTG left-chest) | ~$17–22 (size-tiered) | **$39.99+** |
| Youth Tees | ~$10.50 | **$24.99** |
| Champion Packable Anorak (embroidered) | ~$42.57 | **$89.99** |
| Acrylic Luggage Tag | ~$13.20 | **$24.99** |

These floors assume a healthy retail margin. If the merchant explicitly
wants a low margin (e.g. a near-cost family/friends store), read the
actual per-variant `cost` (§1) and price to their target (§3) instead —
but never silently go below cost.

### Full margin math

```
Profit = (Retail Price + Customer Shipping)
       - Fulfillment Cost (Printful/Printify/Gelato)
       - Fulfillment Shipping (~$5.90)
       - Sales Channel Fee (~3.9% of total)
       - Creator Commission (if applicable, 40% standard)
```

- Customer shipping: $8.00 to customer, free over $70.
- The analytics endpoints report margin only over cost-known orders —
  see `references/analytics.md` (`margin_coverage`) before trusting an
  aggregate margin figure.

---

## 5. Draft-order retail pricing

Setting the price a *customer* pays on a manual/draft order (not the
product's own price) is separate — per-item `custom_price` and
order-level `shipping_cost`/`tax` on the draft-order item endpoints.
See `references/orders-and-fulfillment.md` section 12.
