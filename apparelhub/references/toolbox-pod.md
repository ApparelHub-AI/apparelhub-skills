# Toolbox POD: a US print shop with low base costs and flat per-order shipping

Read this before you connect Toolbox POD, build a product on it, pick it
over another provider, or act on an order that one of its products is in.

Toolbox POD is a print on demand shop in Utah that prints and ships its own
orders. Find it by comparing provider names with case, spaces and
punctuation ignored (`toolboxpod`), never by an exact string: its display
name may read `Toolbox POD` or `ToolboxPOD`. Call it "Toolbox POD" when you
talk to the merchant.

Like every provider in ApparelHub, it is **bring your own account**: the
merchant connects their own Toolbox POD account and Toolbox POD bills the
merchant's card directly. ApparelHub never takes a cut of the print cost.

---

## 1. When to choose it, and when not to

| Choose Toolbox POD when | Choose another provider when |
|---|---|
| The buyers are in the **US**. | Any meaningful share of buyers is **outside the US**. Toolbox POD ships to US addresses only (section 5). |
| The product is one of its garments (section 3). | The product is anything else: mugs, hats, all-over print, embroidery, sleeve prints. |
| You want the lowest delivered cost, especially on **multi-item orders**: shipping is one flat fee per order, not per item. | You need a print method or placement it does not offer (it prints front, back, or both). |

Before recommending it on cost, compare the live numbers (section 3), not
the figures in this file, and read `references/provider-selection.md`
section 5 for how to present a cost comparison honestly.

A merchant who sells to the US and abroad can keep **the same design on two
providers**: a Toolbox POD product in the store that serves US orders and a
Printful, Printify or Gelato product for everyone else. That is also what
makes a held order movable (section 6).

---

## 2. Connecting it: sign in, never a key

Toolbox POD connects by **signing in to Toolbox POD** (OAuth). There is no
key or token to paste, and the `validate-pat` / `connect-pat` routes do not
apply to it. Never ask the merchant for a Toolbox POD key.

1. List the account's stores (`GET /agents/v1/store`) and connect INTO the
   store the merchant means (see `references/error-handling.md` section
   2e-bis). A store's orders are fulfilled through one provider today, so
   if the store already fulfills through another provider (for example the
   one serving international buyers), ask whether Toolbox POD should go in a
   separate store connected to the same storefront.
2. Find the provider uuid: `GET /agents/v1/merchandise/providers`, the row
   whose `name`, lowercased with spaces and punctuation removed, is
   `toolboxpod`.
3. Start the connect:

   ```bash
   curl -sS -X POST "https://api.apparelhub.ai/agents/v1/store/create/merchandise_provider/<toolboxpod_provider_uuid>" \
     -H "x-api-key: $APPARELHUB_API_KEY" -H "Content-Type: application/json" \
     -d '{"store_uuid": "<store_uuid>"}'
   ```

   The response carries `auth_url`. **Hand it to the merchant to open in
   their browser.** You cannot complete the sign-in for them. On the Toolbox
   POD side they sign in (or create an account), choose which of their
   Toolbox POD stores to connect, and approve.
4. **Ask them to set a spending limit on that consent screen.** The limit
   caps what orders placed through ApparelHub can charge to their card.
   Until purchasing is on with a limit, orders are created but wait for the
   merchant to pay (section 4).
5. Poll `GET /agents/v1/onboarding/readiness` (or the store) until the
   connection shows as connected, then run the health check in section 7.

MCP callers: `list_connectable_providers`, then `connect_fulfillment_provider`
with the store's uuid.

---

## 3. Garments, placement and costs

Three garments at launch, each printed on the **front, the back, or both**,
sizes **S to 3XL**:

| Garment | `product_ref_id` | One side | Both sides |
|---|---|---|---|
| Gildan 64000 Softstyle tee | `GD64` | $8.59 | $13.59 |
| Comfort Colors 1717 garment-dyed tee | `CC17` | $11.59 | $16.59 |
| Lane Seven LS14001 premium pullover hoodie | `LS14` | $22.50 | $28.50 |

Size upcharges: tees **+$2 for 2XL and +$4 for 3XL**; the hoodie **+$1 and
+$2**. Shipping is **one flat $5.95 per order** to a US address, however many
items are in it.

⛔ **These prices are a snapshot and can change. Never hardcode them.** Read
the live numbers before quoting or pricing:

- `GET /agents/v1/merchandise/<provider_uuid>/product/<product_ref_id>`
  returns each variant's one side cost (`price`) and `cost_both_sides`, plus
  `shipping: {"model": "flat_per_order", "amount", "currency"}` and
  `ships_to`.
- Product codes come from the catalog itself
  (`GET /agents/v1/merchandise/<provider_uuid>/products` or `find_garments`).
  Treat the codes above as examples, not a contract.
- A design printed on both sides costs the **both sides** price for that
  variant, not two one side prices. Price the product from the cost that
  matches what you built.
- `estimate_order_costs` supports Toolbox POD and applies the shipping fee
  once per order.

**Placement.** Send the usual `print_data` box for each side, exactly as for
any provider (`references/product-creation-pipeline.md`); `provider_ref_id`
is `front` or `back`. ApparelHub sends that exact box to Toolbox POD, so the
print matches the mockup you approved. If your box is one of Toolbox POD's
standard placements you can say so with `"preset"` on the print file
(`full-front`, `left-chest`, `full-back`, `low-hem`); otherwise leave it out.
Artwork must hold at least 150 DPI at the printed size, so give it a large,
crisp file.

**Mockups.** Toolbox POD's own product photos with your design on them, in
each color you pick. Generate and look at them exactly as for any provider
(safety rail 4b). A product's artwork or placement cannot be edited in place
on Toolbox POD's side; changing it makes a new design there, which ApparelHub
handles for you. Just know that a change is a rebuild, not a tweak.

---

## 4. Paying for orders, and why a paid order is final

ApparelHub creates the Toolbox POD order when it is submitted, and
**confirming the order is what pays for it** on the merchant's card, inside
their spending limit.

If Toolbox POD cannot take payment, the order is held with a `hold_details`
whose `action` is `confirm_again_after_fix`. The `code` tells you the fix and
`message` is merchant-ready:

| `code` | What the merchant does in Toolbox POD |
|---|---|
| `purchasing_not_enabled` | Let ApparelHub pay for orders. |
| `spending_limit_exceeded` | Raise the spending limit. |
| `owner_confirmation_required` | The account owner approves the payment. |
| `no_payment_method` / `no_customer` | Add a card. |
| `payment_held` | Update the card (it was declined). |

Relay the message, wait for the merchant to say it is fixed, then confirm
the order again. Confirming twice never charges twice.

⛔ **Treat a paid Toolbox POD order as final.** Toolbox POD sends a paid
order straight to production, so a cancel after payment is normally refused
with a message saying so. Before you confirm, make sure the order is right
(address, items, sizes). If something is wrong after payment, the merchant
contacts Toolbox POD support; report the problem as a fulfillment issue
(`references/fulfillment-issues.md`) so it is on record.

---

## 5. US addresses only: `ships_to`

Toolbox POD ships to the 50 US states, DC and PO boxes. The platform says
so in data, on every surface, without naming a provider:

- `ships_to` on the provider (`GET /agents/v1/merchandise/providers`), on
  catalog garment detail, and on every merchant product (`GET
  /agents/v1/product/<uuid>` and lists).
- It is a list of country codes (`["US"]`). **`null`, absent, or an empty
  list all mean worldwide.** Never read an empty list as "ships nowhere".

Use it before you build: if the merchant's storefront sells abroad, say up
front that a Toolbox POD product only serves the US orders, and offer a
second provider for the rest.

**Store warning.** `GET /agents/v1/store/<uuid>` can carry
`shipping_warnings[]`, one entry per (provider, sales channel) pair:

| `code` | `severity` | Means |
|---|---|---|
| `channel_ships_beyond_provider` | `warning` | The storefront sells to countries the provider cannot ship to (`channel_ships_to_count`, `channel_ships_to_sample`). |
| `channel_destinations_unknown` | `info` | We could not read where the storefront ships. That is unknown, not fine. |

Show `message` as written when it is present. Absent or `[]` means no
warning.

---

## 6. An order that cannot ship: `destination_unsupported`

An order for a Toolbox POD product going to a non-US address is **held and
never sent to Toolbox POD**, so nothing is charged. The order shows
`requires_approval: true`, a plain `hold_reason`, and:

```json
"hold_details": {
  "code": "destination_unsupported",
  "country": "CA",
  "provider_name": "Toolbox POD",
  "ships_to": ["US"],
  "product_variant_ids": [123],
  "items": [{"name": "Sunset Tee", "quantity": 1, "product_variant_id": 123}],
  "order_item_uuids": [],
  "message": "<merchant-ready explanation>",
  "suggested_reroute": null
}
```

Match lines on `product_variant_id` (`order_item_uuids` is always empty).
What to do depends on `suggested_reroute`:

- **`suggested_reroute` is set:** the same design exists as a product on a
  provider that ships there, in a store connected to the **same storefront**
  the order came from. Offer to move it, and with the merchant's agreement:

  ```bash
  curl -sS -X POST "https://api.apparelhub.ai/agents/v1/orders/<order_uuid>/reroute" \
    -H "x-api-key: $APPARELHUB_API_KEY" -H "Content-Type: application/json" \
    -d '{"product_uuid": "<suggested_reroute.product_uuid>"}'
  ```

  The order is recreated in that store, the held one is closed, and the
  storefront link (and so tracking) moves with it. Then handle the new order
  as usual (confirm it if the store needs confirmation).
- **`suggested_reroute` is `null`:** there is nothing to move it to. For a
  storefront order, the merchant **cancels the order and refunds the
  customer on their storefront**. For a manual order, cancel it, or build the
  design on a provider that ships there and create the order again.

Reroute refusals (`409`, each with a merchant-readable `message`):
`not_destination_held`, `destination_unsupported`,
`product_not_in_connected_store`, `reroute_variants_missing`,
`recipient_unavailable`, `reroute_channel_mismatch` (the target store is not
connected to the order's storefront; tell the merchant to cancel and refund
there instead). Do not retry a 409 with the same product.

⛔ Never edit the shipping address to a US one to get the order through, and
never reroute to a product the merchant did not agree to.

MCP callers: `get_order_details` returns `hold_details`; `reroute_order`
moves the order.

---

## 7. Connection health: what the merchant still has to switch on

`GET /agents/v1/store/<store>/merchandise_provider/<provider>/connection/health`
returns, for Toolbox POD, an itemised report:

```json
{
  "healthy": false,
  "reason": "action_required",
  "mode": "live",
  "checks": {
    "token":      {"ok": true},
    "scopes":     {"ok": true, "missing": []},
    "mode":       {"ok": true, "mode": "live"},
    "purchasing": {"ok": false, "limits": []},
    "webhook":    {"ok": true}
  },
  "fixes": ["Turn on purchasing for ApparelHub in Toolbox POD and set a spending limit ..."]
}
```

- Each `checks.*.ok` is `true`, `false` or `null` (could not tell). Only
  `false` is a problem.
- `fixes[]` are merchant-ready sentences. Relay them as written.
- `reason` is `ok`, `action_required`, `not_connected`,
  `reconnect_required` (send them through the connect flow again; never ask
  for a key), `provider_unreachable` or `provider_rate_limited` (both
  unknown: wait, do not ask anyone to reconnect).
- `mode: "test"` is a sandbox connection: it never charges, prints or ships,
  and needs no spending limit.

Run it once after connecting and whenever confirmations start coming back
held. Do not poll it in a loop (see `references/error-handling.md` 2f).

MCP callers: `check_fulfillment_connection`.

---

## 8. What to tell the merchant

Good:

> "Toolbox POD's Gildan tee is $8.59 for a front print right now, plus one
> $5.95 shipping charge per order, which makes it the cheapest delivered tee
> on your account for US orders. It only ships inside the US, so I'd keep
> your Printful version for international buyers. Want me to build it?"

Bad:

> "Toolbox POD is always the cheapest." (Prices change and it depends on the
> product and destination; quote the live number.)

> "I'll cancel it if anything's wrong." (A paid order usually can't be
> cancelled; check before confirming.)
