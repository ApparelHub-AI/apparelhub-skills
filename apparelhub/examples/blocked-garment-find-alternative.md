# Example: a garment can't take the design → find one that can

The situation this walks through is the one that goes wrong most often,
and it goes wrong quietly: you are building a merch capsule from a
photographic design, you get to the hat, and the hats you can see are
embroidery-only.

The wrong ending is "no hat is possible". This is the right one.

Assumes `$APPARELHUB_API_KEY` is set. See `references/api-contract.md`.

---

## Phase 1 — You hit the constraint

You have a photoreal design (say a moody noir portrait) and you are
adding a cap. You look at the first provider's headwear:

```bash
curl -sS -G "https://api.apparelhub.ai/agents/v1/merchandise/<provider_uuid>/products" \
  -H "x-api-key: $APPARELHUB_API_KEY" \
  --data-urlencode "category=hats"
```

Every garment comes back like this:

```json
{ "provider_ref_id": "<ref>", "name": "Dad Hat",
  "decoration_method": ["embroidery"],
  "decoration_confidence": "high",
  "accepts_photoreal": false }
```

`accepts_photoreal: false` at `high` confidence. That is real: this
garment is stitched, and a photograph will not stitch.

**Stop here and notice what you actually know.** You know *this
provider's* hats are embroidered. You do not know anything yet about
hats in general. Do not write the sentence "hats can't take this design".

---

## Phase 2 — Ask the whole account, not one provider

```bash
curl -sS -G "https://api.apparelhub.ai/agents/v1/merchandise/find-garments" \
  -H "x-api-key: $APPARELHUB_API_KEY" \
  --data-urlencode "category=hat" \
  --data-urlencode "accepts_photoreal=true"
```

Note there is no `providers` parameter. Leaving it off is the point —
the search covers every provider on the account by default.

```json
{
  "results": [
    { "provider": "<provider B>",
      "product_ref_id": "<ref>",
      "name": "Printed Trucker Cap",
      "decoration_method": ["dtf"],
      "decoration_confidence": "high",
      "accepts_photoreal": true }
  ],
  "total_matched": 2,
  "providers_searched": ["<provider A>", "<provider B>", "<provider C>"],
  "providers_unavailable": [],
  "warnings": []
}
```

A DTF-printed cap. DTF is a transfer print, so it reproduces a
photograph the same way a DTG tee does.

**Read `providers_searched` before you say anything to the user.** It is
the only part of the response that tells you what was covered. If a
provider had been down it would be in `providers_unavailable`, and its
absence from `results` would mean nothing at all.

---

## Phase 3 — Confirm the specific garment

`find_garments` returns a compact projection. Before building, pull the
full record for the one you picked:

```bash
curl -sS "https://api.apparelhub.ai/agents/v1/merchandise/<provider_B_uuid>/product/<ref>" \
  -H "x-api-key: $APPARELHUB_API_KEY"
```

Check three things:

1. `accepts_photoreal` is still `true` and `decoration_confidence` is
   `high`.
2. The print template you intend to use is a print placement, not an
   embroidery one — a garment can offer both.
3. There are variants in the colors you want.

---

## Phase 4 — Build it, and tell the user what happened

Build normally from here (`references/product-creation-pipeline.md`), on
the provider that carries the printable cap.

Then say what you did, and be precise about scope:

> The hats on <provider A> are embroidery-only, and this design is
> photographic, so it would not stitch cleanly. <provider B> carries a
> printed trucker cap that takes it as-is, so I built it there — the
> rest of the capsule is unchanged.

Notice: the constraint is attributed to a **provider**, not to hats. The
user learns something true and keeps a working hat.

---

## The variation where nothing turns up

Sometimes the search genuinely finds nothing:

```json
{ "results": [], "total_matched": 0,
  "providers_searched": ["<provider A>", "<provider B>"],
  "warnings": ["No garments matched ... That is a result for these filters on
                these providers, not proof the item is impossible ..."] }
```

Report the search, not a verdict:

> I checked <provider A> and <provider B> for a printable hat and did not
> find one. Connecting another fulfillment provider would likely get you
> one. Want me to put this design on something else in the meantime?

The difference between that and "no hat is possible" is that one of them
is a fact and leaves the user somewhere to go.

---

## The variation where the garment is unclassified

You may see this:

```json
{ "name": "Knitted Beanie", "decoration_method": [],
  "decoration_confidence": "unknown", "accepts_photoreal": null }
```

`null` is **not** `false`. It means the provider publishes no decoration
signal for this garment — nobody checked, so nothing is ruled out.
Generate a mockup and look at it, or ask the user, but do not silently
drop it. Dropping unknowns is the same mistake as dropping the hat: an
answer shrunk by an absence of evidence.
