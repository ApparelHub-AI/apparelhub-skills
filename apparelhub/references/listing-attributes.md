# Listing attributes — the fields the CHANNEL defines, not us

Every sales channel puts extra fields on a listing beyond name, price and images.
TikTok Shop calls them **product attributes**, eBay calls them **item specifics**,
Shopify calls them **category metafields**, WooCommerce calls them **product
attributes**. Same shape every time: a set of fields defined by the channel, some
required, most with an enumerated set of allowed values.

They matter because channels grade listings on completeness, and an incomplete
listing gets less reach. They are also where product-compliance answers live, and
some of those are legal statements.

> **You cannot guess these.** The field names and their allowed values are defined
> by the channel, per taxonomy category. A value that does not match is refused. The
> whole point of `describe_listing_attributes` is that you never have to guess.

---

## 1. The loop

```
describe_listing_attributes   ->  learn the fields and allowed values
set_listing_attributes        ->  store the values (per product)
set_channel_settings          ->  store the shop-wide ones (compliance, brand, templates)
sync_to_channel               ->  push the listing, which is what makes it real
```

**Setting a value does not change the live listing on its own.** Values are stored
against the listing and applied on the next sync. Either pass `sync: true` on
`set_listing_attributes`, or run `sync_to_channel` afterwards. Skipping the sync is
the most common way to conclude "it did not work" when it did.

Always call `describe_listing_attributes` first, even if you think you know the
field names. They differ per channel and per category.

---

## 2. Reading the schema

Each field carries three properties that are deliberately **separate**:

| property | means |
|---|---|
| `value_type` | `string` / `number` / `bool` / `date` / `object` |
| `cardinality` | `single` or `multi` — pass an array for `multi` |
| `free_text` | whether a value OUTSIDE `allowed_values` is accepted |

They are separate because most real fields are **enumerated AND free-text-able** at
the same time: there is a list of suggested values, and the channel will also take
your own wording. Neither flag alone tells you what is legal, which is why there is
no single "type" to switch on.

Other fields worth reading:

- **`requirement`** — `required`, `conditional`, `recommended`, `optional`.
  `conditional` means it only becomes required once `required_when` holds, i.e.
  after some other field is answered a particular way.
- **`allowed_values`** — omitted for very large lists (one real field carries 647
  values); `allowed_values_count` is always there. Pass `include_values` with `all`
  or a comma-separated list of keys to expand.
- **`allows_custom_fields`** on the schema — some channels let a product define its
  own attribute inline. Where it is true, a key that is not in `fields` is still
  legitimate. Where it is false, an unknown key is refused.
- **`supported: false`** with an empty `fields` — this channel defines no listing
  attributes. That is a real answer, not an error. Report it and move on.

### `values` is what is LIVE, not what you last wrote

`values` reflects the listing **on the channel**, which is not the same as what was
last set from here. Channel-side auto-fills and edits the merchant made directly in
the channel's own admin appear there too. That drift is usually the most useful
thing in the response — it is how you notice a field you set was replaced, or one
you never set is populated.

### Check how the category was resolved

When `resolved_for` is present it says which taxonomy node the schema came from and
how:

- **`explicit_override`** — the merchant chose this category. Trust it.
- **`keyword_match`** — it was GUESSED from the product name. Treat it as
  unverified and say so.

This matters more than it sounds. If the guess is wrong, the fields you are being
offered belong to a different kind of product entirely, and setting attributes
against them is **worse than setting none** — you would be writing confident,
validated, wrong metadata. On a `keyword_match`, sanity-check that the category
actually describes the product before setting anything, and tell the merchant if it
does not.

---

## 3. Setting values

A **partial write succeeds**. Send four values with one bad and the three good ones
are stored while the bad one comes back in `rejected`. You do not have to get them
all right at once, and you should not discard the good ones to retry.

`rejected[]` always carries a machine-readable `reason`:

| reason | what to do |
|---|---|
| `value_not_allowed` | the allowed values are echoed back — pick one, or ask the merchant |
| `unknown_field` | the channel does not define that field; re-read the schema |
| `not_multi` | you sent a list to a single-valued field |
| `invalid_format` | fails the channel's format for that field |
| `too_long` | exceeds the field's max length |
| `empty_value` | omit the field instead of sending an empty string |
| `unsupported` | this channel has no listing attributes at all |

Rejections are **returned, never dropped**. If a field is missing from `accepted`,
look for it in `rejected` — it will be there with a reason.

`unset_required[]` lists fields that are required and empty. These are **not** filled
in for you. Left unset, the channel picks its own default or grades the listing
down, so they are worth resolving with the merchant.

---

## 4. ⛔ Never invent a compliance answer

`set_channel_settings` writes shop-wide settings, and some of them are **legal
attestations** — product-compliance questions such as California Proposition 65.
They are statements the MERCHANT makes about their goods and they carry legal
weight.

**Relay what the merchant told you. Never choose a value yourself.**

Specifically, do not:

- infer the answer from the product type;
- reason that printed apparel must be exempt (Proposition 65 covers clothing, and
  some inks and finishes do contain listed chemicals);
- default to the common answer because it is usually the common answer;
- copy an answer from another shop;
- pick the nearest allowed value because it looks close.

If the merchant has not given you an answer, **leave it unset and tell them it is
outstanding.** An unset attestation is honest. An invented one is not, and it is
made in their name.

Answering one of these questions can make a follow-up field **conditionally
required** — typically naming the specific substances, from a list of hundreds. It
will appear in `unset_required`. Surface it to the merchant; never fill it in.

The same rule applies with less at stake to ordinary attributes: relay, do not
invent. A value you made up is silently wrong metadata on a live listing.

---

## 5. Scope: per product vs per shop

| scope | set with | examples |
|---|---|---|
| `product` | `set_listing_attributes` | material, style, fit, care instructions |
| `integration` | `set_channel_settings` | compliance answers, brand, shipping template, size-chart template |

A field's `scope` tells you which. Shop-wide settings apply to **every** listing on
that channel, so they are answered once rather than per product — and existing
listings pick them up on their next sync.

Some shop-wide settings are ids (brand, shipping template). Where the channel can
list the options, they arrive in `allowed_values` so you never have to send the
merchant hunting for an id. An empty list with a `help` note means the shop
genuinely has none available — for example a shop with no brand authorisation,
which is a normal state, not a fault.

---

## 6. Quick reference

```
describe_listing_attributes   store_uuid, product_uuid?, integration_uuid?, include_values?
set_listing_attributes        store_uuid, product_uuid, values{}, remove[]?, sync?
set_channel_settings          store_uuid, integration_uuid, values{}, remove[]?
```

- Omit `product_uuid` on describe to get the shop-wide fields; `integration_uuid` is
  required in that case.
- `integration_uuid` is otherwise only needed when the store has more than one
  channel connected. Ambiguity is refused with the candidates listed, never guessed.
- A locked integration refuses writes.
