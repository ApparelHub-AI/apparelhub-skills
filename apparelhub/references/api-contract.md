# ApparelHub Agent API — HTTP Contract

This is the canonical description of the ApparelHub Agent API in pure
HTTP terms. Any AI agent capable of making HTTP requests can drive the
platform from this document alone — no shell, no scripts, no filesystem
required.

The other reference files in this directory describe *what to do*
(transparency processing, design rules, embroidery palette, pricing
floors). This file describes *how to talk to the API*.

---

## 1. Base URL

```
https://api.apparelhub.ai/agents/v1/
```

This is the only host the skill ever sends an API key to. There is no
runtime override; if you see a script or doc telling you to set a
different base URL, that is not from us.

---

## 2. Authentication

Every request needs the header:

```
x-api-key: <your API key>
```

- Generate a key at `https://apparelhub.ai/developer/api-keys`
  (requires Professional or Enterprise tier).
- The key is the only credential. Do not also send a Bearer token; the
  Agent API explicitly rejects JWT auth from non-browser clients.
- The key is environment-scoped. A key generated against prod will
  return 401/403 if used elsewhere, and vice versa.

### How the agent should source the key

The recommended pattern is: the agent reads `APPARELHUB_API_KEY` from
its runtime environment (`os.environ`, `process.env`, etc.) at call
time. The skill does **not** ask you to persist the key to disk and
does **not** read the key from any config file.

If your runtime prompts the first time you read this environment
variable or make a network call, **that is correct behavior**. Approve
the prompt in context if the call is one you intended to make.

---

## 3. Response shapes

- All responses are JSON unless explicitly noted (image downloads, the
  OpenAPI spec download, etc.).
- Errors return a JSON body with at minimum `{"error": "<message>"}` and
  often additional fields. Inspect the body on any non-2xx.
- IDs are UUIDs (strings) throughout.

---

## 4. Endpoint catalog

### Image generation

| Method | Path | Purpose |
|---|---|---|
| `POST` | `/agents/v1/images/generate` | Generate a design image. Text-to-image OR img2img edit. |
| `GET` | `/agents/v1/images/generated` | List previously generated images. Supports `?limit=N&sort=newest`. |
| `POST` | `/agents/v1/images/generated/{uuid}/transform` | Upload a processed (e.g. transparency-keyed) version. Multipart `image=@...` or `image` data URL. Returns a NEW image UUID. |

**`POST /images/generate` request body**:

```json
{
  "prompt": "vector flat illustration saguaro cactus silhouette on solid bright green background #00FF00",
  "source": "Nano Banana",
  "size": "1024x1024"
}
```

- `source` is the model NAME as a string: `"Nano Banana"`, `"Seedream 4.0"`, `"Seedream 4.5"`, `"OpenAI"`, `"Flux 1.1 Pro"`, `"Flux 2 Pro"`, `"Google Imagen 4"`, `"GPT Image 2"`, `"Grok Imagine"`, `"Wan 2.7"`. **Not** a UUID.
- For img2img edit mode, add `source_image_uuid` (an existing image you generated) OR submit multipart with `images=@/path/to/file.png`. Only `Nano Banana` and `OpenAI` support edit; Replicate-backed models return 422 if you try.

**`POST /images/generated/{uuid}/transform` request**:

Multipart `image` upload, e.g.:

```
Content-Type: multipart/form-data; boundary=...
... boundary line ...
Content-Disposition: form-data; name="image"; filename="design.png"
Content-Type: image/png

<binary png bytes>
```

For HTTP-only agents that cannot do filesystem multipart: the endpoint also accepts a JSON body `{"image_data_url": "data:image/png;base64,..."}` containing the same bytes inline.

### Mockup generation

| Method | Path | Purpose |
|---|---|---|
| `POST` | `/agents/v1/merchandise/product/preview` | Start a mockup job. Returns a `job_uuid`. |
| `GET` | `/agents/v1/merchandise/product/preview/{provider_uuid}/job/{job_uuid}` | Poll job status + retrieve preview URLs. |
| `PATCH` | `/agents/v1/merchandise/product/preview/job/{job_uuid}/archive` | Archive an orphaned job (cleanup). |

**Preview request body — the field names matter**:

```json
{
  "merchandise_provider_uuid": "<provider uuid>",
  "generated_image_uuid": "<the transparency-keyed image uuid from /transform>",
  "provider_product_ref_id": "71",
  "templates": [
    {
      "provider_ref_id": "front",
      "area_width": 1800,
      "area_height": 2400,
      "width": 1584,
      "height": 1056,
      "top": 312,
      "left": 108,
      "image_url": "https://...processed-image-url..."
    }
  ],
  "variant_ids": [4016, 4017, 4018, 4019, 4020]
}
```

⚠️ Here the field names are `merchandise_provider_uuid` and
`provider_product_ref_id`. In the **product create** endpoint below, the
same data uses **different names** (`provider_uuid` and `product_ref_id`).
Don't copy field names between phases.

**Polling — two-phase completion**:

A mockup job has TWO completion gates:

1. `status == "completed"` — Printful's mockup generator finished.
2. At least one entry in `previews[]` has a non-null `preview_url`
   (means we've downloaded the mockup from Printful and mirrored it to
   our S3).

The gap between these can be 20+ minutes. Don't stop polling at
`status == "completed"` alone. Keep polling the SAME job endpoint until
at least one `preview_url` is populated.

Reasonable polling parameters: 8-second interval, 30-minute total
budget. The job endpoint occasionally returns transient HTTP 502/503/504/429
(API Gateway timeouts during S3 ingestion or upstream slowness) — these
are normal during long polls; retry up to ~5 consecutive transient errors.

### Product creation

| Method | Path | Purpose |
|---|---|---|
| `POST` | `/agents/v1/product/create` | Create the product shell. |
| `POST` | `/agents/v1/product/{uuid}/variants` | Add ONE variant per call (no batch endpoint). |
| `PATCH` | `/agents/v1/product/{uuid}` | Update fields like `display_image`, `gallery_images`. |
| `DELETE` | `/agents/v1/product/{uuid}` | Hard delete (cascades to variants). |
| `GET` | `/agents/v1/product/{uuid}` | Inspect. |
| `GET` | `/agents/v1/product/{uuid}/provider-options` | List the variant matrix the provider exposes. |

**`POST /product/create` request body** — these field names silently
break products if you use the wrong ones:

```json
{
  "name": "Saguaro Sunset Tee",
  "description": "...",
  "generated_image_uuid": "<the transparency-keyed image uuid>",
  "preview_job_uuid": "<the job uuid from the mockup phase>",
  "provider_uuid": "<provider uuid>",
  "product_ref_id": "71",
  "price": 27.99,
  "print_data": [
    {
      "provider_ref_id": "front",
      "area_width": 1800,
      "area_height": 2400,
      "width": 1584,
      "height": 1056,
      "top": 312,
      "left": 108,
      "image_url": "https://...processed-image-url..."
    }
  ]
}
```

The four field-name gotchas:

| Wrong (mockup endpoint name) | Right (create endpoint name) |
|---|---|
| `merchandise_provider_uuid` | `provider_uuid` |
| `provider_product_ref_id` | `product_ref_id` |
| `retail_price` | `price` |
| (mockup uses `templates`) | (create uses `print_data`) |

`product_ref_id` must be a STRING. Even if the catalog returned it as a
number, pass it as `"71"` not `71`. `provider_product_ref_id` in the
mockup endpoint is also a string.

### Variants

```json
POST /agents/v1/product/{product_uuid}/variants
{
  "name": "Black",
  "price": 27.99,
  "color": "Black",
  "size": "S",
  "provider_variant_id": 4016
}
```

One request per variant. There is no bulk endpoint.

**Without variants, sync to fulfillment fails** with `400 "No valid
variants found to sync"`. Add every color × size combo BEFORE syncing.

### Stores and sync

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/agents/v1/store` | List the user's stores. |
| `GET` | `/agents/v1/store/{uuid}` | Inspect one store (integrations, settings). |
| `GET` | `/agents/v1/store/{uuid}/products` | List products on a store. Supports `?fields=...` for sparse payloads. |
| `POST` | `/agents/v1/store/{uuid}/products` | Add products to a store: body `{"product_uuids": [...]}`. |
| `DELETE` | `/agents/v1/store/{uuid}/products/{product_uuid}` | Remove a product from a store. |
| `POST` | `/agents/v1/store/{uuid}/products/{product_uuid}/sync?target=merchandise` | Sync to fulfillment provider (Printful / Printify). |
| `POST` | `/agents/v1/store/{uuid}/products/{product_uuid}/sync?target=ecommerce&integration_uuid=<integration_uuid>` | Sync to sales channel (Shopify / WooCommerce / Wix). |
| `DELETE` | `/agents/v1/store/{uuid}/products/{product_uuid}/sync?target=merchandise` | Unsync from fulfillment. |
| `DELETE` | `/agents/v1/store/{uuid}/products/{product_uuid}/sync?target=ecommerce&integration_uuid=<integration_uuid>` | Unsync from sales channel. |
| `GET` | `/agents/v1/store/{uuid}/audit-log` | Compliance trail. Supports `?action=...` filtering. |

**Default sales-channel sync to DRAFT** when supported (Etsy, Shopify).
Push as `?listing_state=draft` (or omit — draft is the default). Only
push as `active` when the user explicitly says "make it live."

### Orders and fulfillment

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/agents/v1/orders` | List recent orders. |
| `GET` | `/agents/v1/orders/{uuid}` | Inspect one order. |
| `POST` | `/agents/v1/orders/{uuid}/approve` | Approve a held order. |
| `POST` | `/agents/v1/orders/{uuid}/submit` | Submit an order for fulfillment. |
| `POST` | `/agents/v1/orders/{uuid}/cancel` | Cancel an order. |
| `POST` | `/agents/v1/orders/{uuid}/link-ecommerce-order` | Link a manual ApparelHub order to a storefront order. |

Payment authority rules live in `references/orders-and-fulfillment.md`.

### Garment catalog

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/agents/v1/merchandise/{provider_uuid}/products` | Browse the catalog. Supports `?fields=` to trim payload. |
| `GET` | `/agents/v1/merchandise/{provider_uuid}/product/{product_ref_id}` | Full detail for one garment, including the variant matrix. |

### Merchandise connections (per-user PATs)

| Method | Path | Purpose |
|---|---|---|
| `POST` | `/agents/v1/store/{uuid}/merchandise_provider/{provider_uuid}/connect-pat` | Connect a Printify PAT. |
| `DELETE` | `/agents/v1/store/{uuid}/merchandise_provider/{provider_uuid}/connection` | Disconnect. |
| `GET` | `/agents/v1/store/{uuid}/merchandise_provider/{provider_uuid}/connection/health` | Health-check the connection. |

### Membership (read-only)

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/agents/v1/membership` | Current tier, features, usage quotas. |

### OpenAPI spec

```
GET /agents/v1/openapi.json
```

Authoritative reference for every endpoint, every field. Fetch any time
you're unsure about a field name or response shape. Renderable in any
Swagger viewer.

---

## 4b. Workspace scoping (enterprise accounts)

On Enterprise (agency) accounts the account is divided into isolated
**workspaces**, and every request acts within ONE active workspace. Most
accounts have a single Default workspace and can ignore this.

- **Discover workspaces.** `GET /agents/v1/workspaces` →
  `{workspaces:[{uuid,name,is_default}], active_workspace, key_scope}`. Resolve a
  workspace name → uuid here (the user names a client, e.g. "Acme Co"; you need its uuid),
  then scope with `?workspace=`. A pinned key lists only its own workspace.
- **Active workspace.** No param means the account's **Default** workspace.
  `?workspace=<workspace_uuid>` on any list / get / create call targets a
  specific one (combines with `?limit=`, `?fields=`, etc.).
- **A bad `?workspace=` fails the whole request** (no silent fallback): an
  unknown uuid returns `404 {"error":"workspace_not_found"}`; a
  real-but-inaccessible workspace returns `403 {"error":"workspace_forbidden"}`.
- **Response fields tell you where an asset lives (Model A).** Products and
  generated images carry a `workspaces` array
  (`[{"uuid","name","is_default"}, ...]`) — every workspace the asset belongs to
  (via store association, or its home workspace if storeless). Stores carry
  single `workspace_uuid` / `workspace_name` / `workspace_is_default`.
- **Workspace-scoped keys.** A key can be pinned to one workspace + role; it
  rejects a different `?workspace=` (`403 workspace_forbidden`) and a role
  lacking a capability returns
  `403 {"error":"forbidden","capability":"design.generate"}` on image generation.

```bash
curl -sS "https://api.apparelhub.ai/agents/v1/store?workspace=<workspace_uuid>" \
  -H "x-api-key: $APPARELHUB_API_KEY"
```

Full detail (Model A visibility, scoped keys, worked curls): `references/workspaces.md`.

---

## 5. Status-code semantics

| Code | Meaning | Action |
|---|---|---|
| 200 / 201 / 204 | Success | Parse the body if present. |
| 400 | Malformed request | The body usually names the offending field. Common cause: wrong field name (see §4 gotchas). |
| 401 | Missing or invalid API key | Verify the key, check the environment scoping. Don't retry without fixing. |
| 403 | Key present but lacks scope (e.g., USER key hitting `/admin/*`); `workspace_forbidden` (targeting a workspace this key/user can't act in); `forbidden` + `capability` (a workspace-scoped key's role lacks the op) | Tell the user; do not retry with a different key or workspace. |
| 404 | Resource doesn't exist; `workspace_not_found` (a bad `?workspace=` uuid — see §4b) | Verify the UUID. May indicate a race with a delete from another session. |
| 409 | Conflict (e.g., `shopify_auth_revoked`, `order_linked_to_sales_channel`, `sales_channel_uniqueness`) | The body explains. Do not bulldoze; surface to the user. |
| 422 | Semantic rejection (e.g., Replicate-backed source on the edit endpoint) | The body names the constraint. |
| 429 | Rate limited | Back off (exponential, ≥1s) and retry. |
| 502 / 503 / 504 | Transient gateway issue | Retry up to ~5 times; if persistent, surface to the user. |

---

## 6. Multipart upload conventions

The transform endpoint is the only place the platform expects multipart
input. Three valid ways to deliver the bytes:

### 6a. Multipart from disk (shell-bound agents)

```
curl -sS -X POST https://api.apparelhub.ai/agents/v1/images/generated/<uuid>/transform \
  -H "x-api-key: $APPARELHUB_API_KEY" \
  -F image=@/path/to/transparent.png
```

### 6b. Multipart from in-memory bytes (HTTP-only agents)

Send a `multipart/form-data` body with one part named `image`, content
type `image/png` (or `image/jpeg`), the binary bytes as the body of that
part. Any HTTP library exposes this as `files={"image": bytes_io}` or
equivalent.

### 6c. Data URL fallback (agents that can't do multipart)

```
POST /agents/v1/images/generated/<uuid>/transform
Content-Type: application/json
x-api-key: <key>

{ "image_data_url": "data:image/png;base64,iVBORw0KGgo..." }
```

Useful for tool-calling agents whose function definition only supports
JSON-shaped arguments.

---

## 7. Idempotency notes

- Mockup job creation (`POST /merchandise/product/preview`) is **not**
  idempotent — calling it twice with the same body produces two jobs.
  Capture the `job_uuid` from the first response and reuse it.
- Variant creation is not idempotent — calling it twice with the same
  `provider_variant_id` creates two variants on the same product. Track
  what you've added.
- Sync endpoints are idempotent — re-syncing an already-synced product
  updates the existing listing rather than creating a duplicate.
- Cancel and disconnect endpoints are idempotent — calling on an
  already-cancelled order or already-disconnected integration returns 200
  with a "nothing to do" message.

---

## 8. Versioning

The Agent API path is `/agents/v1/`. Backwards-incompatible changes
introduce `/v2/` rather than breaking `v1/` consumers. The skill's
v2.0 release does NOT correspond to an API version bump; the underlying
Agent API is still `v1`.

---

## 9. Quick links

- API docs (browser, requires auth): `https://apparelhub.ai/developer/api-docs`
- OpenAPI spec (JSON, authed): `https://api.apparelhub.ai/agents/v1/openapi.json`
- API keys: `https://apparelhub.ai/developer/api-keys`
- Product manager: `https://apparelhub.ai/merchandise/my-products`
- Stores: `https://apparelhub.ai/stores`
- Orders: `https://apparelhub.ai/orders`
