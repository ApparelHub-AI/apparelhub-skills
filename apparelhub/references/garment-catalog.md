# Garment Catalog Quick Reference

Variant IDs, pricing floors, color-mix recommendations. Verify against the live catalog endpoint when in doubt:

```bash
curl -sS "https://api.apparelhub.ai/agents/v1/merchandise/<provider_uuid>/product/<product_ref_id>" -H "x-api-key: $APPARELHUB_API_KEY" | python3 -m json.tool
```

---

## Bella+Canvas 3001 — Standard Unisex T-Shirt

`product_ref_id = "71"` on Printful. The workhorse — most common tee body.

### Variant IDs (color × size)

| Color | S | M | L | XL | 2XL |
|---|---|---|---|---|---|
| Black | 4016 | 4017 | 4018 | 4019 | 4020 |
| White | 4012 | 4013 | 4014 | 4015 | 4011 |
| Heather Midnight Navy | 8495 | 8496 | 8497 | 8498 | 8499 |
| Solid White Blend | 24352 | 24353 | 24354 | 24355 | 24356 |

### ⚠️ CRITICAL — variant ID 4021–4025 is AQUA, not Navy

If the user asks for "Navy" on a BC 3001, use Heather Midnight Navy (`8495-8499`). NEVER `4021-4025` — those produce a teal/aqua shirt. Triple-check via the catalog endpoint above when unsure.

---

## Champion Packable Anorak — Printful product 399

First embroidered garment we shipped. Quarter-zip pullover with hood.

| Property | Value |
|---|---|
| Print method | Embroidery (`embroidery_chest_left` placement, 541×541 px) |
| Cost (S–XL) | $42.57 |
| Cost (2XL) | $44.57 |
| Recommended retail | $89.99 |

### Black variant IDs

| Size | ID |
|---|---|
| S | 11008 |
| M | 11009 |
| L | 11010 |
| XL | 11011 |
| 2XL | 11012 |

**Read `references/embroidery.md` before constructing any sync payload for this product** — the 15-color thread palette + `thread_colors_chest_left` option-placement trap are non-negotiable.

---

## All-over-print products

| Product | Printful ID | Print area | Variants of note |
|---|---|---|---|
| Pillow (square + lumbar) | 214 | 2717×2717 (18×18) | 9515 (18×18), 7907 (20×12 lumbar), 11077 (22×22) |
| Doormat / area rug | 924 | Varies by size — 36×24 = 1437×972 | Landscape: 23705/06/07. Portrait: 23702 etc. (decorative ONLY — doormats MUST be landscape) |
| Water bottle | 382 | 700×433 (vertical designs work best) | Template `provider_ref_id: "default"` |
| Acrylic luggage tag | 938 | 1622×2677 | Single variant 23889 |
| AOP Athletic Tee | (varies) | Full body + sleeves | All variant IDs from catalog |

See `references/all-over-print.md` for the rules that apply across these products (background-to-edges, don't-name-the-product-in-the-prompt, pillow uniform-color technique).

---

## Pricing floors (DO NOT price below)

Negative margin = merchant loses money. These are the minimum retail prices that produce positive margin on the standard fee structure.

| Garment | Approx fulfillment cost | Recommended retail |
|---|---|---|
| BC 3001 Standard Tee | ~$11.69 | **$27.99** |
| BC 3001 Influencer Tee | ~$11.69 | **$29.99** |
| Comfort Colors Tee | ~$14.69 | **$34.99** |
| BC 6400 Women's Relaxed | ~$13.69 | **$34.99** |
| BC 3719 Pullover Hoodie | ~$25.50 | **$54.99** |
| BC 4719 Heavyweight Hoodie | ~$36.50 | **$64.99** |
| AOP Athletic Tee | ~$22.00 | **$44.99** |
| Youth Tees | ~$10.50 | **$24.99** |
| Champion Packable Anorak (embroidered) | ~$42.57 | **$89.99** |
| Acrylic Luggage Tag | ~$13.20 | **$24.99** |

### Margin math

```
Profit = (Retail Price + Customer Shipping)
       - Fulfillment Cost (Printful/Printify)
       - Fulfillment Shipping (~$5.90)
       - Sales Channel Fee (~3.9% of total)
       - Creator Commission (if applicable, 40% standard)
```

- Customer shipping: $8.00 to customer, free over $70
- Creator commission: 40% standard; garment-specific tiers exist for high-volume creators

---

## Quality trade-off — BC 3001 vs Comfort Colors

**Comfort Colors tees** are higher quality:
- Heavier weight (~6.1 oz vs BC 3001's ~4.2 oz)
- True pigment-dyed (vintage color depth, fades beautifully)
- Softer hand-feel out of the box
- Cost ~$3 more

**Recommendation framework:**
- Premium-feel brand selling at $35+ price points → **Comfort Colors**
- High-volume / budget-conscious lines → **BC 3001**
- Mixed lifestyle / casual brand → **BC 3001 for volume tees, Comfort Colors for hero / collection pieces**

When the user asks you to pick a tee body and gives no preference, default to BC 3001 unless their existing product mix or stated brand positioning suggests premium.

---

## Color mix — max 4 per design

More than 4 color variants creates SKU sprawl that hurts conversion. Pick the 4 best colors and stop.

### Default color recipes by design type

| Design type | Recipe |
|---|---|
| Dark linework / heavy black design | Black + Heather Midnight Navy + Charcoal + White |
| Light linework / line art on light fields | White + Solid White Blend + Heather Midnight Navy + Black (contrast) |
| Earthy / natural / vintage | Comfort Colors: Sandstone + Khaki + Hunter Green + Black |
| Bright / pop / streetwear | Black + White + Red + one accent (e.g. Bright Yellow) |
| Mother's Day / soft / floral | Pink + Heather Midnight Navy + Cream / Solid White Blend + Black |

These are starting points — adjust to the specific design's dominant colors.

---

## When to verify against the live catalog

ALWAYS verify if:
- The garment is new (added to Printful/Printify catalog in the last 3 months)
- The user asks for a color that's not in the tables above
- A sync fails with "variant not found" or similar
- It's been > 30 days since the catalog data here was last refreshed

The catalog endpoint is canonical — these tables are quick references that can drift.
