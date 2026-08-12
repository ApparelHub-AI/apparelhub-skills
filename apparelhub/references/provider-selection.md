# Provider selection: choosing where a garment gets made

Read this when a garment cannot take a design, when you are about to
tell a user something is not possible, or when you want the cheapest or
best-quality source for an item.

The single rule this document exists for:

> **A capability limit is a fact about one provider, not about the
> category of garment.** Check the others before you conclude anything.

---

## 1. Why this matters more than it sounds

An account usually has several fulfillment providers connected. They do
not carry the same catalog and they do not decorate the same way.

The concrete failure this prevents: an agent was asked for a merch
capsule with a hat. The first provider it looked at carried only
*embroidered* headwear, and embroidery cannot reproduce a photographic
design. The agent reported:

> "No hat. Embroidery uses a fixed 15-thread palette — a photographic
> image cannot be stitched."

Every word of that is true about that provider. It was still the wrong
answer, because the same account had another provider carrying
DTF-**printed** caps that take photoreal artwork as-is. The item was
dropped and the user was told it was impossible.

Note the shape of the mistake. The agent was not blocked, and it did not
give up. It **concluded** — confidently, from one provider's constraint —
that no path existed. A wrong answer delivered with certainty is worse
than an error, because nobody goes looking for it.

---

## 2. Decoration methods, and which accept a photograph

Every garment reports `decoration_method` (an array) and
`accepts_photoreal`.

| Method | Reproduces photos / gradients? | Notes |
|---|---|---|
| `dtg` | ✅ | Direct-to-garment. The default for tees and hoodies. |
| `dtf` | ✅ | Direct-to-film transfer. How printed caps are made. |
| `sublimation` | ✅ | Hard goods and polyester. |
| `aop` | ✅ | All-over print / cut-and-sew. |
| `print` | ✅ | A print process the provider does not name more precisely. |
| `embroidery` | ❌ | Stitched. Fixed 15-color thread palette, no gradients, no fine detail. |
| `patch` | ❌ | Leather or woven patch. |
| `screen` | ❌ | Spot colors only. |
| `vinyl` | ❌ | Cut vinyl, spot colors only. |

A garment can support **several** methods. A tee offering both `dtg` and
`embroidery` accepts a photograph — on its DTG placement.
`accepts_photoreal` is already true for that case, so trust the field
rather than reading the array yourself.

### `decoration_confidence` — and why `null` is not `false`

| Value | Means | What to do |
|---|---|---|
| `high` | The provider declared the technique, or the placement name encodes it (`embroidery_front`, `front_left_dtf`). | Trust it. |
| `low` | Inferred from the product name. Likely, not certain. | Fine for choosing what to try; confirm before promising. |
| `unknown` | The provider publishes nothing for this garment. `accepts_photoreal` is `null`. | **Verify — do not drop.** |

`accepts_photoreal: null` means *nobody could tell*. It does **not** mean
the garment cannot take the design. Some genuinely unclassifiable
garments exist (a knitted beanie whose provider declares no technique at
all), and treating those as "unsuitable" throws away real options for no
reason. Confirm with `get_garment_details`, a test mockup, or by asking.

---

## 3. Finding a garment across every provider

`find_garments` searches **all** providers on the account by default.
That default is deliberate — you should have to opt *out* of checking.

```bash
curl -sS -G "https://api.apparelhub.ai/agents/v1/merchandise/find-garments" \
  -H "x-api-key: $APPARELHUB_API_KEY" \
  --data-urlencode "category=hat" \
  --data-urlencode "accepts_photoreal=true"
```

Response:

```json
{
  "results": [
    { "provider": "<provider B>", "product_ref_id": "<ref>",
      "name": "Printed Trucker Cap",
      "decoration_method": ["dtf"],
      "decoration_confidence": "high",
      "accepts_photoreal": true }
  ],
  "total_matched": 3,
  "providers_searched": ["<provider A>", "<provider B>", "<provider C>"],
  "providers_unavailable": [],
  "warnings": []
}
```

Useful filters:

| Param | Use |
|---|---|
| `category` | `hat`, `t-shirt`, `mug`… Matched against product names on every provider, including the words providers actually use — `hat` also finds cap, beanie, snapback, trucker. |
| `accepts_photoreal` | `true` for photographic art; `false` to find something you can embroider. |
| `decoration_method` | Comma-separated, e.g. `dtf,dtg`. Any match qualifies. |
| `providers` | Comma-separated names. **Omit it** unless you have a reason to narrow. |
| `include_unknown` | Defaults to `true`. Leave it — unclassified is not unsuitable. |
| `limit` | Default 20, max 50. |

### Always read `providers_searched` and `warnings`

`results` cannot tell you what was *not* looked at. `providers_searched`
can, and `providers_unavailable` lists any provider that errored — a
provider missing from the results because it was down is not a provider
that carries nothing.

An empty `results` means *nothing matched these filters on these
providers*. It is not proof the garment does not exist. Say the first
thing, never the second.

---

## 4. When a design is refused

If a sync or a pre-flight check refuses a design as incompatible with a
garment's decoration method, the refusal already carries the answer:

```json
{
  "error_code": "embroidery_design_not_producible",
  "concerns": [ ... ],
  "constraint_scope": "provider",
  "alternatives": [
    { "provider": "<provider B>", "product_ref_id": "<ref>",
      "name": "Printed Trucker Cap", "decoration_method": ["dtf"] }
  ],
  "checked": true,
  "providers_searched": ["<provider B>", "<provider C>"]
}
```

- `constraint_scope: "provider"` is telling you how to phrase it. Say
  "this provider's version is embroidery-only", not "hats are
  embroidery-only".
- `alternatives` are print-capable equivalents on the account's **other**
  providers. Offer one.
- `checked` distinguishes *searched and found none* (`true`) from *did
  not search* (`false`). Only the first is evidence of anything.

---

## 5. Choosing between providers when several work

Once more than one provider can make the item:

1. **Cost.** Compare with `get_garment_details` on the shortlisted
   garments, and **read `cost_source` before comparing anything**:

   - `live` — the provider publishes cost in its catalog (Printful,
     Gelato). Directly comparable.
   - `cached` — a snapshot from the last time that blank was built here
     (Printify, which publishes no catalog cost). Usable, but check
     `cost_captured_at`; an old one may have moved.
   - `unavailable` — no cost known. **This is the one that matters.**

   When a shortlisted garment comes back `unavailable` you have two
   honest options, and no third one:

   - Build that candidate. Generating a mockup is what makes Printify
     report its cost, so the number exists afterwards.
   - Compare on what you do know, and **say which provider's cost you
     could not get.**

   Never present a cost comparison with a provider silently missing from
   it. A table with a quiet gap reads as complete and gets acted on as
   though it were.

   Two limits to state whenever you give a cost comparison:

   - This is **base production cost**. It excludes shipping and tax, and
     shipping is often what actually decides between two providers on
     bulky or heavy items.
   - `estimate_order_costs` covers production plus shipping plus tax, but
     only for **Printful and Gelato**. There is no landed-cost estimate
     for Printify, so a true landed comparison across all three is not
     something you can produce today. Do not imply otherwise.

   See `references/pricing.md` for how cost gets onto a variant.
2. **Decoration quality.** A printed cap and an embroidered cap are
   different products, not two ways of making one. If the user asked for
   an embroidered look, `accepts_photoreal: false` is what you want.
3. **Keep a capsule consistent.** If the rest of a collection is on one
   provider, staying there simplifies fulfillment and shipping. Say so
   and let the user choose — do not silently split a capsule.
4. **Mockups.** Some providers render some garments poorly. Always look
   at the mockup before shipping (safety rail 4b).

---

## 6. What to say to the user

Bad, and the reason this document exists:

> "No hat is possible — embroidery cannot reproduce a photographic
> design."

Good:

> "The hats on <provider A> are embroidery-only, and this design is
> photographic, so it will not stitch well. <provider B> carries a
> printed trucker cap that takes it as-is — want me to build it there?"

Also good, when nothing turned up:

> "I searched <provider A>, <provider B> and <provider C> for a printable
> hat and did not find one. Connecting another fulfillment provider would
> be the way to get one — want me to look at what else this design could
> go on in the meantime?"

The difference is that both good versions name what was checked, and
leave the user somewhere to go.
