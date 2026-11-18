# Example: build and list a Toolbox POD tee for a US store

The user says: "Connect Toolbox POD to my store, put this design on a black
Gildan tee, front only, S to 2XL, price it for a 50% margin, and list it on
my Shopify store."

Read `../references/toolbox-pod.md` first. This walkthrough only shows what
is different about Toolbox POD; every other step is the normal pipeline in
`front-print-tee.md`.

Placeholders like `<store_uuid>` stand for the value an earlier step
returned. All calls go to `https://api.apparelhub.ai/agents/v1/` with the
`x-api-key` header.

---

## Step 1: Check where the store sells

```bash
curl -sS "https://api.apparelhub.ai/agents/v1/store" -H "x-api-key: $APPARELHUB_API_KEY"
```

Pick the store the user means. If it already shows a
`shipping_warnings[]` entry, or the user mentions international buyers, say
now: "Toolbox POD ships to US addresses only. Orders from other countries
would be held, so I'd keep a version on another provider for them." Let the
user decide before you go on.

## Step 2: Connect Toolbox POD (the merchant signs in)

```bash
# Find the provider: the row whose name is "ToolboxPOD", and note ships_to: ["US"]
curl -sS "https://api.apparelhub.ai/agents/v1/merchandise/providers" -H "x-api-key: $APPARELHUB_API_KEY"

curl -sS -X POST "https://api.apparelhub.ai/agents/v1/store/create/merchandise_provider/<toolboxpod_provider_uuid>" \
  -H "x-api-key: $APPARELHUB_API_KEY" -H "Content-Type: application/json" \
  -d '{"store_uuid": "<store_uuid>"}'
# -> {"auth_url": "https://..."}
```

Tell the user:

> "Open this link to sign in to Toolbox POD and approve the connection.
> On that screen, please turn on purchasing and set a spending limit;
> Toolbox POD charges your card directly for each order, and orders wait
> until that's on."

Poll `GET /agents/v1/onboarding/readiness` until it shows connected, then:

```bash
curl -sS "https://api.apparelhub.ai/agents/v1/store/<store_uuid>/merchandise_provider/<toolboxpod_provider_uuid>/connection/health" \
  -H "x-api-key: $APPARELHUB_API_KEY"
```

If `checks.purchasing.ok` is `false`, relay the line in `fixes[]` and carry
on building; it only blocks paying for orders.

## Step 3: Read the live garment and cost

```bash
curl -sS "https://api.apparelhub.ai/agents/v1/merchandise/<toolboxpod_provider_uuid>/product/GD64" \
  -H "x-api-key: $APPARELHUB_API_KEY"
```

From the response, keep:

- the black variants for S, M, L, XL, 2XL: each `provider_ref_id` (the
  variant id) and its `price` (one side cost; 2XL costs more);
- the front template's `area_width` / `area_height`;
- `shipping.amount` (one flat fee per order) and `ships_to`.

Do not reuse prices from the reference doc; use these.

## Step 4: Design, mockup, verify

Follow `front-print-tee.md` phases 1 to 3.5 with
`merchandise_provider_uuid` = the Toolbox POD provider uuid and
`provider_product_ref_id` = `"GD64"`. One `print_data` entry with
`provider_ref_id: "front"` and the usual box. The mockup is Toolbox POD's
photo of a black tee with the design on it. Look at it before you continue
(safety rail 4b): placement, transparency on black, no cut off lettering.

## Step 5: Create the product and price it

Create the product and its variants as in `front-print-tee.md` phases 4 and
5. Price each variant from ITS OWN cost: `cost / (1 - 0.50)`, rounded to a
sensible retail price, and never below the floors in
`../references/pricing.md`. Because the design is front only, use the one
side cost; a front and back design would use `cost_both_sides`.

When you report the margin, say shipping is a flat fee per order on top, so
a multi-item order keeps more of each sale.

## Step 6: Sync and list (with approval)

Ask the user before syncing anywhere (safety rail 4f). Then sync to
fulfillment, then to the Shopify integration, as in `front-print-tee.md`
phases 6 and 7. Listings go up as drafts unless the user asked for live.

## Step 7: When an order comes in

- **US order:** it reaches the store's queue like any other. Check the
  address and items, then confirm it: confirming is what pays Toolbox POD.
  A held confirm carries `hold_details.code` (for example
  `spending_limit_exceeded`); relay `message`, wait for the fix, confirm
  again. After payment the order is final.
- **Order to another country:** it is held with
  `hold_details.code = "destination_unsupported"` and was never sent or
  charged. If `suggested_reroute` is set, offer to move it
  (`POST /orders/<order_uuid>/reroute`). If it is `null`, tell the merchant
  to cancel and refund the order on their storefront.

What to report back:

> "Done: 'Sunset Tee' is built on Toolbox POD's black Gildan 64000, front
> print, S to 2XL, priced $17.99 (S to XL) and $21.99 (2XL) for about a
> 50% margin on today's base cost, and it's a draft on Shopify. Shipping is a flat $5.95 per order
> from Toolbox POD. It only ships to US addresses, so international orders
> for it will be held for you to handle."
