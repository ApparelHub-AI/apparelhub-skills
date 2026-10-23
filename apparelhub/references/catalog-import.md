# Catalog import — bring in what the merchant already sells

Most established sellers arrive with a catalog already live on a sales channel,
built long before ApparelHub. Everything else in this skill only sees products
ApparelHub made. Catalog import closes that gap: it reads the merchant's
existing listings off a connected channel and keeps them as **tracked
listings**, so you can see and reason about their whole catalog.

> **Say this to the merchant BEFORE you start an import, every time:**
> it changes nothing on their store, and those products keep being fulfilled
> exactly as they are today. ApparelHub only reads.

---

## 1. What a tracked listing is, and is not

| It IS | It is NOT |
|---|---|
| A read-only mirror of a listing on the channel: title, description, price, currency, status, SKUs, variants, the channel's own image URL | An ApparelHub product. You cannot sync it, price-cascade it, edit it, or put it on a fulfillment provider |
| Refreshed every time you import again | Written back to the channel. Nothing is ever pushed to the merchant's store from this path |
| Linked to its product when ApparelHub created it (`made_in_apparelhub: true`, `product_uuid`) | Duplicated. A listing ApparelHub made is recognised and linked, not imported a second time |
| Kept when it leaves the channel, stamped `removed_at` | Deleted. Removed listings are hidden by default, never thrown away |

Images are the channel's own URLs, referenced rather than copied.

**Fulfilment is untouched.** Orders for the merchant's own products keep going
wherever they go today. ApparelHub never fulfils a tracked listing. Once the
catalog is imported, those orders are *recorded* in ApparelHub with
`fulfilled_by: "merchant"`, so you can read every order from one place; see
"Orders fulfilled by the merchant's store" in `orders-and-fulfillment.md`.

---

## 2. Which channels

Catalog import works where the channel reports **`catalog_read: true`**:
**Shopify, WooCommerce, Wix and TikTok Shop**. Any other channel is refused with
`409 catalog_read_unsupported`; tell the merchant it is not available for that
channel yet rather than retrying.

Two places report it:

- `GET /agents/v1/store/{store_uuid}`: each entry in `active_integrations`
  carries `capabilities.catalog_read` (and the integration `uuid` you need).
- `GET /agents/v1/store/{store_uuid}/catalog`: its `channels` list carries
  `catalog_read` and `last_run` for every connected channel, even before any
  import has run.

---

## 3. The workflow

Use it when an established seller wants to see or manage what they already
sell ("what's in my shop?", "bring my existing products in", "which of my
listings did you make?").

1. **Find the integration.** `GET /store/{store_uuid}`, pick the channel in
   `active_integrations`, check `capabilities.catalog_read` is `true`, keep its
   `uuid`.
2. **Tell the merchant** it changes nothing on their store and their products
   stay fulfilled as today.
3. **Start the import.**
   `POST /store/{store_uuid}/ecommerce/integration/{integration_uuid}/catalog/import`
   → `202 {"run": {"uuid": "...", "status": "queued", ...}, "message": "..."}`.
   No body is needed.
4. **Poll the run** every few seconds until `status` is `completed` or
   `failed`: `GET /store/{store_uuid}/catalog/runs/{run_uuid}`.
5. **Read the result** with `scope=external` to see the merchant's own
   products (the ones ApparelHub did not create):
   `GET /store/{store_uuid}/catalog?scope=external`.

```bash
curl -s -X POST "https://api.apparelhub.ai/agents/v1/store/<store_uuid>/ecommerce/integration/<integration_uuid>/catalog/import" \
  -H "x-api-key: $APPARELHUB_API_KEY"

curl -s "https://api.apparelhub.ai/agents/v1/store/<store_uuid>/catalog/runs/<run_uuid>" \
  -H "x-api-key: $APPARELHUB_API_KEY"

curl -s "https://api.apparelhub.ai/agents/v1/store/<store_uuid>/catalog?scope=external&limit=100" \
  -H "x-api-key: $APPARELHUB_API_KEY"
```

**Multi-workspace (agency) accounts:** every call above is scoped to the
request's active workspace, which is the Default one unless you pass
`?workspace=<workspace_uuid>`. Add it to all three calls when the store lives
in another workspace. If you forget, you get `409 wrong_workspace` with
`retry_with.workspace`; retry the same call with that value (see
`references/workspaces.md`).

**Re-running is safe.** A second import updates what is there and never
duplicates. Listings that have left the channel since the last import get
`removed_at` set.

---

## 4. The run

`GET /store/{store_uuid}/catalog/runs/{run_uuid}` →

```json
{"run": {
  "uuid": "...", "integration_uuid": "...",
  "status": "running",
  "pages": 3, "seen": 150, "created": 140, "updated": 0,
  "ours": 10, "removed": 0, "images_fetched": 40,
  "error": null,
  "started_at": "2026-10-22T12:00:00", "finished_at": null
}}
```

| Field | Meaning |
|---|---|
| `status` | `queued` → `running` → `completed` or `failed` |
| `seen` | Listings read from the channel so far |
| `created` / `updated` | New tracked listings / ones refreshed from an earlier import |
| `ours` | Listings ApparelHub created, linked to their product |
| `removed` | Listings that left the channel since the last import |
| `images_fetched` | Listings whose image had to be looked up separately (capped per run; a later import fills in more) |
| `error` | Why a `failed` run stopped. `null` otherwise |

**A failed run is stated, never silent.** What was read before it stopped is
kept, and **nothing is marked removed on a partial pass**, so a failure can
never make listings look like they vanished. Report the `error`, fix the cause
(most often: reconnect the channel), and import again.

---

## 5. Reading the catalog

`GET /store/{store_uuid}/catalog`

| Param | Values |
|---|---|
| `integration` | One channel's integration uuid (optional) |
| `scope` | `all` (default), `external` (only listings ApparelHub did not create), `ours` (only ones it did) |
| `include_removed` | `true` to include listings that have left the channel |
| `workspace` | Workspace uuid, on agency accounts when the store is not in the Default workspace (applies to all three endpoints) |
| `limit` / `offset` | `limit` 1 to 500 (default 100), `offset` 0 or more |

Response:

```json
{
  "listings": [{
    "uuid": "...", "integration_uuid": "...", "channel": "WooCommerce",
    "external_id": "...", "title": "...", "description": "...",
    "image_url": "https://shop.example.com/...",
    "price": 24.99, "currency": "USD",
    "channel_status": "live",
    "product_sku": "...",
    "variants": [{"external_variant_id": "...", "sku": "...", "title": "...", "price": 24.99}],
    "made_in_apparelhub": false, "product_uuid": null,
    "first_seen_at": "...", "last_seen_at": "...", "removed_at": null
  }],
  "total": 1, "limit": 100, "offset": 0,
  "channels": [{"integration_uuid": "...", "channel": "WooCommerce", "catalog_read": true, "last_run": {"...": "..."}}]
}
```

`channel_status` is `live`, `draft`, `archived` or `unknown`. Page with
`offset` until you have `total`.

---

## 6. Refusals

| Status | `error` | What to do |
|---|---|---|
| `404` | `store_not_found` / `integration_not_found` | Wrong store, or that channel is not connected to this store. Re-read `GET /store/{store_uuid}` |
| `404` | `run_not_found` | The run uuid is not on this store |
| `409` | `wrong_workspace` | The store is in another workspace. Retry the same call with `?workspace=` set to `retry_with.workspace` |
| `409` | `import_in_progress` | An import for this channel is already running. The body includes that `run`: **poll it, do not start another** |
| `409` | `integration_inactive` | The channel is disconnected. Ask the merchant to reconnect it, then import |
| `409` | `catalog_read_unsupported` | This channel cannot be imported yet. Do not retry |
| `400` | `invalid_paging` / `invalid_scope` | Fix `limit`/`offset` or `scope` |

---

## 7. MCP

On the ApparelHub MCP server (0.17.0+) the same flow is three tools:
`import_channel_catalog` (start; on `import_in_progress` it returns the run
already going, with `already_running: true`), `get_catalog_import_run` (poll),
and `list_tracked_listings` (read, including each channel's `catalog_read`).
