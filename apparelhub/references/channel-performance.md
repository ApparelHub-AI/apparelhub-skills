# Channel performance — what people SAW, not just what sold

The analytics endpoints in `references/analytics.md` are built from **orders**.
They tell you what sold. They cannot tell you what was *looked at and not
bought*, and that gap is where most of the fixable money is.

These endpoints close it. They serve what the **sales channel itself** reports
about each of your listings — impressions, clicks, click-through rate,
add-to-carts — alongside a state saying what to do about it.

> A listing with 5,000 impressions and 0 sales, and a listing nobody has ever
> seen, look **identical** in order-based analytics: both are "0 sold". They
> need opposite actions. Telling them apart is the entire point of this file.

---

## 1. The three endpoints

| Endpoint | Returns |
|---|---|
| `GET /agents/v1/analytics/channel/listings` | Per-listing metrics + derived state for a date range |
| `GET /agents/v1/analytics/channel/summary` | State counts, top opportunities, and the safe-to-archive set |
| `GET /agents/v1/analytics/channel/coverage` | Which channels report which metrics |

All read-only. All gated on `advanced_analytics` (Professional+), same as the
rest of analytics — a lower tier gets `403 feature_unavailable`, and you should
say so rather than retry.

Params: `start` / `end` (YYYY-MM-DD, default the last 28 days ending yesterday),
`state` (listings only), `workspace`.

If you have MCP tools available, prefer `channel_performance`,
`channel_opportunities` and `channel_coverage` over raw HTTP.

---

## 2. ⛔ A missing metric is NOT a zero

Coverage is genuinely sparse and will stay that way:

| Channel | Reports performance? |
|---|---|
| TikTok Shop | Yes — impressions, clicks, CTR, add-to-cart, units, GMV |
| WooCommerce | **No.** WooCommerce core records no view data at all |
| Shopify | Not yet (needs plan-gated ShopifyQL) |
| Wix, Fourthwall | No per-listing feed |

So an absent `impressions` can mean *three* different things: this channel never
reports it, ingestion has not run yet, or the shop needs reconnecting. **None of
them mean "nobody saw it."**

Every response carries a `coverage` block for exactly this reason. Read it
before you interpret an absence:

```json
{ "provider": "WooCommerce", "supported": false,
  "unreported_metrics": ["impressions", "clicks"], "status": "not_reported" }
```

`status: "reconnect_required"` means the merchant must reconnect that shop
before performance data can flow. Tell them; do not retry, and do not report the
shop as having no traffic.

**If you take one rule from this file:** never conclude "no demand" from a
missing number. Say "this channel does not report views" instead.

---

## 3. The six states, and what each one means you should do

`listings[].state` is the decision. It is computed against **this store's own
distribution**, not fixed thresholds, so it means the same thing whether the
shop does 200 impressions a day or 200,000.

| State | What it means | Do this |
|---|---|---|
| `winner` | Well seen, and converting | Scale it — more variants/colourways, consider a price test |
| `conversion_blocked` | Plenty of impressions, few clicks | Fix the **listing card**: title, main image, price shown in the feed |
| `pdp_blocked` | They click, then do not buy | Fix the **product page**: images, description, price, variants |
| `starved` | Too few people have seen it to judge | **Discovery** — content, affiliate, ads. NOT a listing rewrite |
| `dead` | No meaningful activity at all | The only state where archiving is appropriate |
| `insufficient_data` | Not enough signal, or unreported | Nothing. Wait for data |

Two of these are easy to get wrong:

**`starved` is not a listing problem.** Rewriting the title of a listing nobody
has seen accomplishes nothing and looks like flailing to the merchant. Low
exposure is a traffic problem. Send it to discovery.

**`dead` is the only archivable state.** In particular `conversion_blocked` is
the *opposite* of dead: the demand is already proven and only the listing is in
the way. Archiving it destroys the best opportunity in the catalogue.

---

## 4. The workflow that uses this properly

```bash
# 1. What can this account even see?
GET /agents/v1/analytics/channel/coverage

# 2. Where is demand being wasted right now?
GET /agents/v1/analytics/channel/summary
#    -> summary.top_opportunities: proven demand, broken conversion,
#       ranked by how many people saw it and did not buy
#    -> summary.archivable: ONLY the genuinely inert listings

# 3. Fix the top opportunity, using the state to pick WHICH fix
#    conversion_blocked -> the card. On TikTok, the listing-quality tools
#    (references/tiktok-listing-quality.md) fix titles and search terms.
#    pdp_blocked        -> the product page: images, description, price

# 4. Come back in a week and re-read the same listing's state.
#    That is how you find out whether the fix actually worked.
```

Step 4 is the half that never existed before. You could always change a listing;
you could not tell whether it helped. Now you can — but give it time: the data
is daily and the channel finalises it a couple of days in arrears.

---

## 5. Dates are the channel's own, and recent days move

Two things that will otherwise look like bugs:

**Different clock.** These dates are the sales channel's local dates (TikTok
reports in the shop's registered timezone). The order-based analytics endpoints
bucket on a different basis. Every response says which via `date_basis`. Do not
compare the two without accounting for it, and do not present them to a merchant
as the same series.

**Recent days are provisional.** Channels restate. A listing's numbers for
yesterday will usually change. Rows carry `is_final`, and the platform
re-fetches provisional days until the channel settles them. So:

- do not treat a day's figures as final until they are;
- expect small movements in the last couple of days;
- if a merchant compares against their Seller Center and sees a small
  difference on a recent day, that is why — say so plainly rather than
  guessing.

---

## 6. Unmapped listings

`mapped_to_apparelhub: false` means the listing exists on the channel but was
not created through the platform — usually a merchant's pre-existing catalogue.
Those rows are still real signal about the shop and are deliberately kept rather
than hidden. You just cannot act on them through the product endpoints until the
listing is adopted, so do not try to edit them.
