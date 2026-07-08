# Analytics & reporting (`/agents/v1/analytics/*`)

Six **read-only** endpoints let an agent pull order & merchandise metrics
programmatically — headline KPIs, trend series, dimensional breakdowns, ops
health, CSV exports, and (for agencies) a cross-client portfolio. They read
precomputed daily rollups plus a live overlay for the current partial day, so
they're cheap to call.

**Every route is tier-gated on the `advanced_analytics` feature** — Professional
and Enterprise only. On a lower tier every call returns `403 feature_unavailable`
(section 6). If the user is on Free/Basic, don't loop-retry: tell them analytics
needs a Professional+ plan.

All six are `GET`, all take the same date-range + currency + store params, and
all are workspace-scoped like every other agent endpoint (section 7). Full field
schemas live in the served OpenAPI spec (`GET /agents/v1/openapi.json`, **Analytics**
tag) — this file teaches the shapes + the three semantics that trip agents up
(tier gate, currency segmentation, margin coverage).

---

## 1. The six endpoints

| Endpoint | Returns |
|---|---|
| `GET /agents/v1/analytics/summary` | Headline KPIs for the range + prior-period deltas |
| `GET /agents/v1/analytics/timeseries` | KPI series bucketed by `interval` (day / week / month), zero-filled |
| `GET /agents/v1/analytics/breakdown` | Aggregates grouped by a `dimension` (top sellers, channel mix, etc.) |
| `GET /agents/v1/analytics/ops` | Ops health: fulfillment velocity + hold / cancel / refund rates |
| `GET /agents/v1/analytics/export` | CSV download of any `report` (or a raw orders detail) |
| `GET /agents/v1/analytics/portfolio` | Per-client (per-workspace) roll-up — **agency (Enterprise) accounts only** |

### Shared query params

| Param | Applies to | Default | Notes |
|---|---|---|---|
| `start`, `end` | all | **last 30 days** ending today (UTC) | ISO dates, `YYYY-MM-DD`. Bad/inverted range → `400 invalid_range`. |
| `store` | all except portfolio | all accessible stores | A store `uuid` to narrow to one store. Outside your scope → `404 store_not_found`. |
| `currency` | all | the busiest currency in range | Pick which currency to report in (e.g. `USD`). See section 3 — currencies are **never summed**. |
| `workspace` | all | active (Default) workspace | Scope to a workspace, same as every other endpoint (section 7). |
| `interval` | timeseries, export(timeseries) | `day` | `day` \| `week` \| `month`. |
| `dimension` | breakdown (required), export(breakdown) | — | See section 4. |
| `limit` | breakdown | `50` (max `500`) | Top-N rows; the remainder folds into one `(everything else)` row. |
| `report` | export (required) | — | `summary` \| `timeseries` \| `breakdown` \| `ops` \| `orders`. |

```bash
# Headline KPIs for a specific month, in USD
curl -sS "https://api.apparelhub.ai/agents/v1/analytics/summary?start=2026-06-01&end=2026-06-30&currency=USD" \
  -H "x-api-key: $APPARELHUB_API_KEY"
```

---

## 2. `summary` — KPIs + prior-period deltas

```json
{
  "start": "2026-06-01", "end": "2026-06-30",
  "currency": "USD",
  "currencies_present": ["USD", "EUR"],
  "kpis": { "gross_revenue": 4210.50, "order_count": 96, "aov": 43.86, "...": "…" },
  "prior_period": { "start": "2026-05-02", "end": "2026-05-31", "kpis": { "...": "…" } },
  "deltas": { "gross_revenue": 0.18, "order_count": 0.09, "...": "…" },
  "store_count": 3
}
```

- `deltas` are fractional change vs the immediately-preceding equal-length period
  (`0.18` = +18%). Report them as trends, not raw diffs.
- `store_count` is how many stores fed this number (respects `store=` and scope).

### The KPI dict (also `timeseries` buckets, `portfolio` client/`totals`)

| Field | Meaning |
|---|---|
| `gross_revenue` | Revenue over **paid** orders in the currency. A refund flips the order out on recompute. |
| `order_count` | Paid orders. |
| `units` | Items sold. |
| `aov` | Average order value (`null` when `order_count` is 0). |
| `subtotal`, `shipping_collected`, `tax_collected` | Revenue components. |
| `cogs` | Cost of goods (over cost-known orders — see section 3). |
| `gross_profit` | `revenue − cogs` over the cost-known subset. |
| `avg_margin_pct` | Profit ÷ revenue, cost-known subset only. |
| `avg_markup_pct` | Profit ÷ cost, cost-known subset only. |
| `margin_known_order_count`, `margin_known_revenue` | The cost-known subset the margin figures cover. |
| `margin_coverage` | Share of revenue with a known cost (`0.0`–`1.0`) — **read this before trusting a margin** (section 3). |
| `all_order_count` | All orders incl. unpaid/cancelled (denominator for the rates below). |
| `cancelled_count`, `refunded_count`, `held_count` | Counts. |
| `cancellation_rate`, `refund_rate`, `hold_rate` | Fractions of `all_order_count`. |
| `velocity` | `{payment_to_submit_avg_seconds, submit_to_ship_avg_seconds, ship_to_deliver_avg_seconds}` (+ their sample counts). Convert seconds → hours/days for the user. |

---

## 3. Two semantics that will burn you if you skip them

**Currencies are segmented, never summed.** A store selling in USD and EUR has
two independent tallies; the platform will not add €10 to $10. Each response is
computed in ONE `currency` and lists `currencies_present`. If the user sells in
several currencies, either report per-currency (call once per entry in
`currencies_present`, passing `?currency=`) or state which one you're showing.
Never present a single blended total across currencies.

**Margin only covers cost-known orders — check `margin_coverage`.** Some
fulfillment data doesn't expose a per-item cost (e.g. Printify can return a null
cost), so margin/profit are computed ONLY over the orders where cost is known,
and `margin_coverage` reports that share. The platform never fabricates a cost.
So `avg_margin_pct: 0.42` with `margin_coverage: 0.35` means "42% margin, but
only across 35% of revenue" — surface the coverage, don't imply the margin
covers the whole book. High coverage → trust it; low coverage → caveat it.

---

## 4. `breakdown` — group by a dimension

`dimension` is **required**. Valid values:

| `dimension` | Groups revenue/units/margin by… |
|---|---|
| `product_type` | Merch category (tee, hoodie, mug, …) |
| `sales_channel` | Where the order came from (Shopify / WooCommerce / Wix / direct) |
| `fulfillment_provider` | Printful / Printify |
| `product` | Individual product |
| `variant` | Individual variant |
| `hold_reason` | Why orders were held |

```json
{
  "start": "…", "end": "…", "dimension": "sales_channel",
  "currency": "USD", "currencies_present": ["USD"],
  "rows": [
    {"value": "Shopify", "order_count": 41, "units": 63, "revenue": 1980.0,
     "cogs": 720.5, "gross_profit": 1259.5, "margin_pct": 0.63,
     "margin_coverage": 1.0, "count": 41}
  ]
}
```

Rows are ranked; anything past `limit` collapses into a single row with
`value: "(everything else)"` so totals still reconcile. `margin_pct` /
`margin_coverage` per row follow the same cost-known rule as section 3.

---

## 5. `ops` — fulfillment health

```json
{
  "start": "…", "end": "…", "currency": "USD",
  "velocity": {"payment_to_submit_avg_seconds": 57600, "submit_to_ship_avg_seconds": 486000, "ship_to_deliver_avg_seconds": 259200},
  "all_order_count": 110, "cancelled_count": 3, "refunded_count": 2, "held_count": 5,
  "cancellation_rate": 0.027, "refund_rate": 0.018, "hold_rate": 0.045,
  "hold_reasons": [{"value": "design_approval", "count": 4, "...": "…"}]
}
```

Velocity is in **seconds** — convert for humans (`486000 s ≈ 5.6 days`
submit→ship). `hold_reasons` is a `hold_reason` breakdown so you can tell the
merchant *why* orders are stuck.

---

## 6. `export` — CSV

Returns `text/csv` (not JSON) with a `Content-Disposition: attachment`
filename, for the report named by `report` (`summary` | `timeseries` |
`breakdown` | `ops` | `orders`). `breakdown` also honors `dimension`;
`timeseries` also honors `interval`. `orders` is a raw per-order detail export.
Cost/profit columns are left **blank** (not zero) when cost is unknown.

```bash
curl -sS "https://api.apparelhub.ai/agents/v1/analytics/export?report=breakdown&dimension=product&start=2026-06-01&end=2026-06-30" \
  -H "x-api-key: $APPARELHUB_API_KEY" -o top-products-june.csv
```

Save the bytes to a file (or hand the user the CSV); don't try to render it as
JSON.

---

## 7. `portfolio` — the agency cross-client view (Enterprise only)

Rolls every client **workspace** you can see analytics for into one comparison,
ranked by revenue. This is the only endpoint that spans workspaces (the others
scope to one).

```json
{
  "start": "…", "end": "…", "currency": "USD", "currencies_present": ["USD"],
  "clients": [
    {"workspace_uuid": "…", "name": "Acme Co", "is_default": false,
     "account_name": "Acme Co", "store_count": 2, "kpis": { "gross_revenue": 5200.0, "...": "…" }}
  ],
  "totals": { "gross_revenue": 12400.0, "...": "…" },
  "client_count": 4
}
```

- **Agency (Enterprise) accounts only.** A non-agency account gets
  `403 feature_unavailable` with `feature: "client_portfolio"` (distinct from the
  `advanced_analytics` gate).
- A **workspace-scoped** key only sees the workspace(s) it's scoped to — its
  portfolio spans just those, not the whole book.
- `totals` obeys the currency rule (section 3): it sums clients **within one
  currency**, never across.

---

## 8. Scope, tier gates, and errors

**Workspace scoping** matches the rest of the API: no `?workspace=` → the Default
workspace; `?workspace=<uuid>` targets one (see `references/workspaces.md`).
Viewing analytics needs the Director-level `analytics.view` capability —
account owners/admins have it; an invited member needs it granted. Entitlement is
**account-level**: an invited teammate working in a paying account inherits that
account's `advanced_analytics`.

| Status | `error` | When | What to do |
|---|---|---|---|
| 403 | `feature_unavailable` (`feature: advanced_analytics`) | Account tier is below Professional | Don't retry. Tell the user analytics needs Professional+; point to `/pricing`. |
| 403 | `feature_unavailable` (`feature: client_portfolio`) | `portfolio` on a non-agency account | The account isn't an agency (Enterprise) plan; only `portfolio` needs this — the other five still work. |
| 400 | `invalid_range` | Bad or inverted `start`/`end` | Fix the dates (ISO `YYYY-MM-DD`, `start ≤ end`). |
| 400 | `invalid_dimension` | `breakdown`/export dimension not in the list | Use one from section 4. |
| 400 | `invalid_report` | `export` `report` not in the list | Use `summary`/`timeseries`/`breakdown`/`ops`/`orders`. |
| 404 | `store_not_found` | `store=<uuid>` outside your scope | Drop the param (all stores) or use a store you can access. |

Example 403 body:

```json
{"error": "feature_unavailable", "feature": "advanced_analytics",
 "message": "This feature requires an upgraded membership.", "upgrade_url": "/pricing"}
```

---

## 9. Reporting back to the user

- Lead with the outcome (revenue, top channel, margin health), not the JSON.
- Always name the **currency** you're reporting in; if `currencies_present` has
  more than one, say so.
- When you quote a margin, quote `margin_coverage` alongside it (or only quote
  margin when coverage is high).
- Convert `velocity` seconds into hours/days.
- For a CSV export, hand over the file, not a wall of rows.
