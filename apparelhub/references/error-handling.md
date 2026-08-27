# Error Handling

How to interpret API errors and the most common silent-failure modes.

---

## 1. HTTP status codes

| Status | What it means | What to do |
|---|---|---|
| 401 | API key missing or invalid | Verify the user's `APPARELHUB_API_KEY` env var. Have them generate a new one at `https://apparelhub.ai/developer/api-keys` if it's expired. |
| 402 | Account suspended — the owner's trial ended with no card on file; the account is read-only | `error=account_suspended`. The agent can't pay; tell the account OWNER to add a payment method at the `billing_url` in the body. Reads still work; only writes/quota/sync are blocked. Don't retry. See §2c. |
| 403 | User's tier doesn't include API access OR endpoint is admin-only OR JWT auth attempted from non-browser | If `code=tier_missing_api_access`, the user needs Professional or Enterprise. Read `GET /agents/v1/membership/billing-route` before naming a destination: Stripe accounts go to `https://apparelhub.ai/pricing`, Shopify-billed accounts upgrade in their Shopify admin (see api-contract.md). If the user tried JWT auth from curl, switch to the Agent API + API key. |
| 404 | Endpoint path wrong OR resource doesn't exist | Verify the path against `https://api.apparelhub.ai/agents/v1/openapi.json`. If the resource UUID is wrong, list to confirm. |
| 409 | Conflict — usually integration locked, sales channel uniqueness violation, or duplicate product | Read the error body. See "Common 409 codes" below. |
| 422 | Validation error — field-level issue with the request body | Read the error body. Field name mismatches are the most common cause (Phase 3 vs Phase 5 names — see `references/product-creation-pipeline.md`). |
| 429 | Rate limited — **read the body before deciding what to back off** | Two different things. No `error` field (or `platform_rate_limited`): YOUR key hit the platform throttle — back off exponentially. Default tier is 10 req/sec, 10K/mo. Professional is 50 req/sec, 50K/mo. Enterprise is 200 req/sec, 500K/mo. `error: provider_rate_limited`: the FULFILLMENT PROVIDER is throttling us and your key is fine — wait `retry_after` and retry the SAME request. See §2f. |
| 500 | Server error | Retry ONCE with a 2-3s backoff. If it persists, capture the response body and tell the user there's a platform issue. Don't hammer it. |
| 502 / 503 / 504 | Upstream gateway or timeout | Backoff and retry up to 3 times with exponential delays. After that, it's a platform issue. |

---

## 2. Common 409 codes

### `integration_locked`

Sales channel integration is locked (admin lock OR per-merchant lock). Mutating operations (sync, order auto-submit, fulfillment notify) are blocked.

**What to tell the user:**
> "Your [Shopify/WC/Wix/Etsy] integration is locked. Unlock it in the store dashboard at `https://apparelhub.ai/stores/<store_uuid>` to allow sync."

If they don't know why it's locked, the audit log has the answer:
```bash
curl -sS "https://api.apparelhub.ai/agents/v1/store/<store_uuid>/audit-log?action=integration_locked" -H "x-api-key: $APPARELHUB_API_KEY"
```

### `sales_channel_uniqueness_violation`

The shop URL is already connected to a DIFFERENT user's account in the same environment. Each storefront (`your-store.myshopify.com`, `shop.example.com`, etc.) can be connected to exactly one ApparelHub user.

**What to tell the user:**
> "Your [Shopify/WC/Wix] store is already connected to another ApparelHub account. If that's also you, disconnect it from the other account first. If not, you'll need to use a different storefront."

### `order_linked_to_sales_channel`

Returned by `link-stripe-payment` when called on an order whose `ecommerce_external_id` is set. The storefront already processed the payment; we can't double-attribute by recording a Stripe charge.

**What to tell the user:**
> "This order was paid through [Shopify/WC/Wix/Etsy]'s payment gateway, not through ApparelHub's Stripe Connect. Payment is already recorded — no additional action needed."

(This is Absolute Rule 10 in action — see `references/orders-and-fulfillment.md` for the full payment-authority discussion.)

### `duplicate_product`

A product with this exact name + provider already exists for this user. Either rename the new product or update the existing one instead of creating.

### `image_in_use`

From `DELETE /images/generated/{uuid}`. A live (non-archived) product still uses this design, so **nothing was deleted**. The body carries the blocking `products[]` (`uuid` + `name`).

This is a guard, not a dead end. **Archive the design instead** (`PATCH /images/generated/{uuid}` with `{"archived": true}`), which is reversible and leaves those products untouched. Only if the user explicitly wants the design erased permanently should you archive or delete the blocking products first and retry. Do not report "designs cannot be deleted" and abandon the task. See `references/design-rules.md` section 5d.

### `images_version_conflict`

From `PATCH /product/{uuid}` when you passed `expected_images_version` and the product's gallery changed underneath you (another session, or the merchant editing in the web UI). **Nothing was written.** The body carries `current_version` and `expected_version`.

```json
409 { "error_code": "images_version_conflict", "current_version": 9, "expected_version": 7 }
```

⛔ **Do not retry the same body.** It will fail identically, and if it somehow succeeded it would overwrite whatever the other writer did. Re-read the product, reapply your INTENT to the gallery as it is NOW (append your photo to the current list; reorder what is actually there), then PATCH again with the fresh `expected_images_version`. Replaying a stale array is precisely the overwrite the token exists to prevent. See `references/product-imagery.md` §7.

---

## 2a-bis. "I have a file and no way to use it" — uploading client artwork

Not an error code, but the same class of dead end as the one above, and the more
expensive one to get wrong.

If you are handed a file the merchant already owns — a logo, a brand mark, a
cleared cover — and you cannot find a way to put it on a product, **do not
conclude it is impossible and do not generate a lookalike.** Uploading is
supported: `references/byo-artwork.md`. Three routes (public `source_url`, a
presigned URL you PUT to yourself, or inline base64), all of which return a uuid
that works anywhere a generated design uuid works.

Codes you may see on that path:

### `unsupported_format`

The bytes are not SVG, PNG, JPEG or WEBP. **AI and EPS** need exporting first:
save as SVG to keep it vector (rendered at print resolution, best quality) or
export a PNG at print size. Exporting is not redrawing — it is the same artwork in
another container — so it does not breach a "do not alter our mark" instruction.

### `svg_text_not_outlined`

The SVG contains live `<text>` rather than outlines. Rendering runs with no fonts
on purpose, so that text would come out as nothing — a wordmark would upload blank,
or a logo would upload with its mark intact and its wordmark quietly gone.

Fix it at the source and re-upload: Illustrator *Type > Create Outlines*, Figma
*Flatten*, Inkscape *Path > Object to Path*. **Do not retype or recreate the
lettering yourself.** If you cannot get an outlined export, ask for a PNG.

### `svg_external_reference`

The SVG links to an image by URL. That is never fetched (deliberately — it is what
stops a hostile SVG reaching anything), so it would render as a hole in the
artwork. Re-export with the image embedded, or flatten the whole thing to PNG.
Inline `data:` URIs are fine.

### `svg_rendered_blank` / `svg_invalid` / `svg_too_large`

The document drew nothing, could not be parsed, or is over the 8MB source ceiling.
Flatten and re-export, or supply a PNG.

### `invalid_source_url`

The URL is not https, does not resolve publicly, or resolves to a private
address. The most common real cause is a **share link that requires sign-in** —
the server fetches it anonymously, so it sees a login page, not the file. Either
make the link publicly readable, or use the presigned route and upload the bytes
yourself.

### `file_too_large`

Over 50MB outright, or over the much lower inline-base64 cap. Base64 is capped
deliberately: it costs roughly 350k tokens per megabyte of file. Switch to
`source_url` or the presigned route, both of which cost nothing in context.

### `storage_limit_reached` (403)

The account's storage allowance is full. This is a **storage** limit, not an AI
generation limit — uploads never consume image generations. Archive or delete
unused designs (`GET /images/generated?on_products=false` finds orphans), or the
account needs a larger plan.

---

## 2b. Workspace scoping errors (enterprise / agency accounts)

On Enterprise accounts each request acts within an active workspace, and the `?workspace=<uuid>` selector is validated. Most accounts have one Default workspace and never see these.

### `workspace_not_found` (404)

The `?workspace=` uuid doesn't resolve to any workspace.

**Fix**: correct the uuid, or omit the param (calls default to the account's Default workspace). List them with `GET /agents/v1/workspaces` — see `references/workspaces.md` §2.

### `workspace_forbidden` (403)

The workspace exists but this key/user may not act in it. Either the user isn't assigned to it, or a **workspace-scoped key** was pointed at a workspace outside the one(s) it's scoped to.

**Fix**: target a workspace the caller can access. Don't retry with the same `?workspace=`.

### `wrong_workspace` (409) — the store is real and yours, you're just scoped elsewhere

The store exists and you may access it, but the request was scoped to a **different** workspace, so it was refused before anything else ran. You get this from the connect calls (`.../connect-api-key`, `.../initiate`) when the store lives outside the account's Default workspace and no `?workspace=` was sent.

Worth recognising on sight, because this used to surface as `Store not found or access denied.` — wrong on both counts, and it reads as a credential problem. **The store is resolved BEFORE any provider call**, so a correct credential and a typo'd one fail *identically*, and the same credential works in the web dashboard (which always scopes to the workspace being viewed). That has cost real debugging time re-checking keys that were never read.

The response names its own fix:

```json
{"error":"wrong_workspace",
 "workspace_uuid":"<uuid>","workspace_name":"Acme Co",
 "retry_with":{"workspace":"<uuid>"}}
```

**Fix**: retry the identical call with `?workspace=<workspace_uuid>`. Do not touch the credentials.

**Prevention**: on a multi-workspace account, send `?workspace=` on every store-scoped call — connect, initiate, and the readiness/status polls too. A poll scoped to the wrong workspace reports "not connected" forever, so a connection that really did land never reaches the user.

### `forbidden` with a `capability` field (403)

A workspace-scoped key's role doesn't permit this action (e.g. `{"error":"forbidden","capability":"design.generate"}` on `POST /images/generate`). The account owner controls the key's role.

**Fix**: surface it; don't retry. Use an account-wide key or a key whose role holds the capability.

**A bad `?workspace=` fails the whole request** — there's no partial result. And a scoped list returning a SUBSET is not an error: see `references/workspaces.md` ("don't misread a scoped list as missing data").

---

## 2c. Account suspended (402) — trial ended, no card

When the account owner's invite-only trial expires with no payment method on
file, the account enters a **read-only freeze**. Any write / create /
quota-consuming / channel-push call returns **HTTP 402**:

```json
{
  "error": "account_suspended",
  "reason": "trial_expired",
  "tier": "Enterprise",
  "message": "This account's Enterprise trial has ended. The account owner must add a payment method in Billing to continue.",
  "billing_provider": "stripe",
  "billing_url": "https://apparelhub.ai/billing/subscription"
}
```

**Read `billing_provider` before you tell anyone what to do.** On a
`"shopify"` account the fix is in their Shopify admin, not on apparelhub.ai, and
`billing_url` points there instead (or is `null` if we could not resolve their
plan page, in which case say "your Shopify admin" and stop). Telling a Shopify
merchant to add a card in Billing sends them somewhere they can do nothing.
Quote the `message` and `billing_url` from the response rather than composing
your own, and it stays correct on both.

**Reads still work.** GET calls succeed — you can list/inspect stores, products,
designs, and orders. Only mutations are gated.

**Blocked (402):** image generation, product/store create + update, integration
connect/initiate, merchandise + ecommerce sync, order submit/confirm — every
write route, on both the web and agent APIs.

**What the agent should do:** you can't add a card on the owner's behalf. Stop
the write (don't retry — a 402 won't clear until a card is added) and tell the
human/owner:

> "This account's `<tier>` trial has ended, so it's read-only right now. The
> account owner needs to add a payment method at `<billing_url>` to continue.
> Everything you've built is safe, and full access resumes automatically once a
> card is added."

**Inbound orders are NOT dropped.** Storefront orders that arrive while suspended
are held and auto-release to fulfillment the moment the owner adds a card, so a
real customer who paid on the merchant's live store is never stranded.

---

## 2d. Mockup preview store selection errors

`POST /agents/v1/merchandise/product/preview` accepts an optional `store_uuid`
that pins mockup generation to a specific store's fulfillment-provider
connection. Two failure modes, both fail-loud by design (previously these
silently fell through to the platform's shared credentials):

### `provider_store_mismatch` (400)

The `store_uuid` you passed names a real, accessible store — but that store is
not connected to the merchandise provider in the request. Example: passing a
store that's only connected to one provider while creating a preview for a
different provider's catalog item.

**Recovery:** list the user's stores (`GET /agents/v1/store`), filter for one
whose `providers[]` contains an entry with the requested provider's uuid AND a
non-null `external_id`, and retry with that store — or omit `store_uuid`
entirely to use the account's first connected store for that provider.

### `store_not_found` (404)

The `store_uuid` doesn't exist or isn't accessible to the caller (wrong
workspace scoping is a common cause — see section 2b).

### The `connection` block — which credentials actually ran

The preview create response AND the job poll response carry an additive
`connection` object telling you which fulfillment connection was used:

```json
{
  "connection": {
    "store_uuid": "<store_uuid>",
    "store_name": "Acme Apparel",
    "shared": false
  }
}
```

- `shared: false` — the preview runs through the named store's own provider
  connection (either the `store_uuid` you passed, or the account's first
  connected store when you omitted it).
- `shared: true` (`store_uuid`/`store_name` null) — the account has no store
  connected to that provider, so the platform's shared credentials ran.
  Shared mode is subject to shared rate limits (the 429 with
  `action_required: "connect_store"`) — check `connection.shared` before
  assuming a merchant connection was used.

---

## 2e. Preview and generation dead-ends that used to be unrecoverable

Four failures that previously gave an agent nothing to act on. All four now
return something you can branch on and retry from. **Read the code, not the
prose** — the prose is for the human, the code is for you.

### `empty_variant_selection` (400) — you sent `variant_ids: []`

An empty array is an easy accident: it is what a filter or list comprehension
produces when nothing matched (e.g. selecting "Black / M" on a garment where
that combination is out of stock).

It is **rejected**, not treated as "all variants". Previously the empty array
fell through the filter, the garment's entire variant list survived (589 on
Bella+Canvas 3001), got capped to 30, and fanned out to a 30-variant provider
render that failed with a bare 500. That is expensive — Printful renders are
rate-limited at roughly 2 per minute on a shared account — and it inverts what
you actually asked for.

**Recovery:** the response carries `available_colors`, `available_sizes` and a
slimmed `available_variants[]`. Pick from those and retry. If your selection
logic produced the empty list, that is the real bug — do not resend the same
request.

**Send 2 to 3 specific `variant_ids`.** Omitting the key entirely is legal but
means "every variant", which is almost never what you want.

### `placement_constraint` (400) — the provider refuses this placement set

Providers cap how many print placements one submission may carry, and forbid
certain placements appearing together. A fill / all-over design that covers
every panel can exceed either limit.

The platform now reduces the set for you where it can (see `warnings[]` below).
This error means it could not. The body carries `requested_placements`,
`attempted_placements` and, when the provider disclosed it, `max_placements`, so
you can construct a valid request from the error alone.

**Recovery:** retry with fewer placements, front first. Do not resend the same
set; it will fail identically.

### `warnings[]` on a successful preview — placements were dropped

A preview that succeeded with a reduced placement set returns `warnings[]`
naming each placement that was left off and why:

```json
{
  "status": "pending",
  "warnings": [
    "Printful allows 3 placements on this garment and could not include sleeve_right in this preview, so it was left off."
  ]
}
```

**This is a success, not a failure.** Log it and carry on. Worth surfacing to
the merchant, because it explains why a panel came out blank.

### `knit_options_unavailable` (400) — the garment is knitted, not printed

A **knitted** garment has no ink. Every part of it, including your design, is
reproduced in **yarn**, so the provider needs to know which yarns to use.

Normally you never see this: yarn colours are matched to your design
automatically and the preview **succeeds**, carrying a `warnings[]` note saying
the garment is knitted and naming the yarns chosen. This error only appears when
no usable colour can be read from the design (e.g. it is fully transparent, or
has no solid areas).

The body carries the provider's fixed yarn palette as `available_colors`
(`[{hex, name}, ...]`) and the per-design colour cap as `max_colors`.

**Recovery:** use a design with clear, solid areas of colour, or pick a printed
garment instead. Do not retry the same design unchanged.

**Design rule for knitted garments** — this is the part that bites:

> A knit render **quantises your artwork to the yarn colours**, exactly the way
> embroidery quantises to thread colours. Gradients, photographs and fine
> detail do not survive. Keep the design to a few **flat, solid** colours with
> strong contrast against the base, and stay within `max_colors` (the base
> counts as one of them).

A design with one dominant colour will come back as a **flat block** — the call
succeeds and the mockup is real, but the artwork is gone. If a knit mockup looks
like a solid rectangle, that is this, not a platform failure.

### `error_code` on a failed image generation

`GET /agents/v1/images/upload/{uuid}/status` returns `error_code` alongside the
human-readable `error` when `processing_status` is `failed`. Branch on the code;
do not string-match the prose. The three codes mean **three different remedies**,
and treating them alike wastes generations:

| `error_code` | What happened | What to do |
|---|---|---|
| `content_blocked` | **One** model refused on content-policy grounds (copyrighted character, prohibited content). | **Do not abandon the design, and do not just reword.** The identical prompt fails identically on that model, but a DIFFERENT model very often renders it. Full protocol in §2e.6. |
| `content_blocked_all_models` | **Every** model refused. The full sweep is exhausted. | This is the only legitimate signal to give up on that design. See §2e.6 step 4. |
| `no_image_returned` | The model finished without producing an image, for a reason unrelated to policy. | **Retry once**, or switch model. Nothing is wrong with the prompt. |
| `text_response_instead_of_image` | The model answered conversationally instead of drawing. Often an ask it cannot satisfy (3D, video, vector). | **Rephrase**, or switch model. |

`error_code` is absent on failures recorded before this shipped, and on failure
kinds with no specific code — treat a missing code as "unknown, retry once".

⛔ **Do not tell a merchant their prompt may contain copyrighted content unless
the code is `content_blocked`.** Sending someone off to fix a prompt that was
never the problem is worse than saying nothing.

### 2e.6 Content blocks: reword twice, then cycle every model, then abandon

**On a content block, changing the MODEL beats changing the WORDS.** That inverts
the natural instinct, which is why it is written down here.

**What a content block actually is.** A provider refusing to emit an image it
judges to reproduce protected material, or to breach its own usage policy. It is
a normal, expected outcome for some subject matter, not a platform fault and not
a sign anything is broken. Nothing needs escalating.

**Why rewording is the weak lever.** These guards react to *subject matter* far
more than to phrasing. If the guard objects to the motif, ten rewordings of the
same idea are ten refusals. That is not hypothetical: in one real session an
agent hit a block, reworded the same prompt six times, was refused every time,
and abandoned the design — while other models sat untried.

**Why changing model is the strong lever.** Content guards are
**provider-specific**. They are not a shared standard, and providers differ in
both the *kind* of guard they run and how trigger-happy it is. Some run a
recitation/copyright guard; others only screen for unsafe content. So a prompt
one provider refuses on copyright grounds is routinely rendered by another with
no objection at all.

#### The protocol

1. **Recognise the condition.** Branch on `error_code` — never on the message
   prose. A content block is not a validation error, not a rate limit, and not a
   transient failure, and none of those remedies apply to it.

2. **Reword at most twice.** Vary the **motif and palette away from the
   recognisable signature** — that is the thing a guard is reacting to. Do not
   simply rephrase the same sentence with different adjectives; that is the
   six-attempt failure above. Two attempts, then stop; further rewording of the
   same idea has no expected value.

3. **Then let the model sweep run.** The server cycles the remaining models for
   you on a content block, jumping to a different provider first. **This is the
   step agents miss, and it is the one most likely to actually produce the
   design.** It costs little: a refusal comes back *faster* than a success,
   because the model never generates anything. If you are calling the API
   directly rather than through the MCP server, do this yourself — retry the same
   prompt against a different `source`, preferring a different provider over a
   sibling model on the same one.

4. **Only abandon when the sweep is exhausted.** `content_blocked_all_models`
   means every model refused, and it is the **only** legitimate signal to give up
   on that design. ⛔ **A single `content_blocked` is never sufficient grounds to
   abandon.** If you do abandon at that point, say plainly that every model
   refused and what the subject was — do not report it as a generic failure, and
   do not tell the merchant to keep rewording.

#### One thing to do with a rescued design

If a design only rendered *after* a content block was routed around, that is
worth a deliberate look before it goes onto a product — it is, by definition, art
that at least one provider's guard objected to. The result's `fallback_trail`
records the block, so you can tell. Where a compliance-checking capability is
available to you (the MCP server exposes `check_design_compliance`), this is
exactly the design to run it on. This is cheap and it keeps the merchant, whose
name is on the product, out of an argument they did not choose.

---

## 2f. Connecting a fulfillment provider — the credential is not always the problem

Connecting a provider that authenticates with a merchant-supplied credential
(Printify uses a Personal Access Token, Gelato an API key) can fail for five
different reasons, and only two of them are the credential's fault. The platform
used to report all five as one sentence telling the merchant to check their
token, which is how a real merchant ended up replacing a working credential and
giving up. **Branch on `credential_at_fault`, not on the HTTP status.**

Endpoints: `POST /agents/v1/store/{store}/merchandise_provider/{provider}/validate-pat`
(dry run, persists nothing) and `.../connect-pat` (persists).

| `reason` | HTTP | `credential_at_fault` | What to do |
|---|---|---|---|
| `invalid_token` | 400 | true | Ask the user for a new credential. It expired, was revoked, or got truncated on paste. |
| `insufficient_scope` | 400 | true | The credential works but lacks a permission. Ask them to re-create it **with shop read access** — do not just ask for "a new token", they will make the same one again. |
| `rate_limited` | 429 | false | The provider is throttling us. Wait `retry_after`, retry the SAME credential. Body carries `error: provider_rate_limited`. |
| `provider_unavailable` | 502 | false | The provider is down. Wait and retry. |
| `transport_error` | 502 | false | We could not reach the provider. Wait and retry. |

⛔ **Never ask the user for a new credential when `credential_at_fault` is
false.** That is the exact failure this contract exists to prevent: it sends
someone to replace the one thing that was working, and it is how you lose a
merchant mid-setup.

The response also carries `message`, a merchant-facing sentence that is safe to
show verbatim, and `provider`.

### `error: missing_token` (400)

Different, and worth separating: the request body carried no usable token, so
**nothing was sent to the provider at all**. Do not report this as a rejected
credential. Fix the body — the wire field is `pat` — and retry the same token.

### Connection health is a tri-state

`GET /agents/v1/store/{store}/merchandise_provider/{provider}/connection/health`
returns `healthy` as `true`, `false`, **or `null`**.

- `true` — the stored credential works.
- `false` — genuinely broken. `reason` is `token_revoked`, `insufficient_scope`,
  `reconnect_required`, `not_connected`, or `no_token`. The merchant has to act.
- `null` — **unknown**. `reason` is `provider_unreachable` (they were throttling
  us or were down) or `health_check_unsupported` (we have no way to probe that
  provider). Neither says anything about the credential.

Do not prompt anyone to reconnect on `null`. This endpoint used to report any
failure as `token_revoked`, so a provider blip told merchants their working
integration had been revoked.

**`reconnect_required` is the one reason retrying can never fix.** It arrives
with `remedy: "reauthorize"` and means an OAuth provider's refresh token is gone
or was refused. Send the merchant back through that provider's connect flow. Do
not retry, and do not ask them to paste a token — OAuth providers do not use one.

### How the check works, and its one side effect

The probe differs by how the provider authenticates, because the two models
answer different questions:

- **PAT / API key** (Printify, Gelato) — the credential is static, so the check
  spends it against the provider.
- **OAuth** (Printful) — the access token expires roughly hourly and is
  refreshed on every store-scoped call, so its expiry proves nothing. The check
  exercises the **refresh** token instead.

⚠️ Because of that, checking health on an OAuth connection whose access token is
near expiry **will refresh and persist a new one**. That is intended, and it is
the same thing any other store-scoped call would have done, but it does mean
this endpoint is not strictly read-only. Do not poll it in a loop.

---

## 3. Sync failures — the silent class

The most common "I thought I synced this but customers don't see it" issues:

### `product not associated with store` (channel sync fails)

Symptom: `sync_to_channel` (or `?target=ecommerce`) fails with **"product not associated with store"** and the product is left created-but-unsynced. Classic in automated flows that jump `create_product` → `sync_to_channel`.

**Cause**: the product was never mapped to the store. `create_product` makes a STANDALONE product; a sales-channel listing requires the product to first be associated with the store AND synced to fulfillment.

**Fix**: run the "map to store" step first — `sync_to_fulfillment(product_uuid, store_uuid)` (MCP; it associates + fulfillment-syncs), or Phase 6 `POST /store/<s>/products` then Phase 7 `?target=merchandise` (REST) — then retry the channel sync. Better: use `ship_product`, which runs the whole ordered pipeline in one call. (MCP `sync_to_channel` v0.3.1+ auto-heals this and returns a `warnings[]` note, but the clean order is map-to-store first — and only sync to a channel at all if the user asked to list on a storefront.)

### Variants not yet created (Phase 5 skipped)

Phase 7 sync to `target=merchandise` returns `400 No valid variants found to sync`. The product has no rows in the variants table.

**Fix**: go back and run Phase 5 (one variant at a time, no batch endpoint). Verify with `GET /agents/v1/product/<uuid>/variants` before retrying sync.

### Variants added LATER show `provider_external_id: null` — re-sync to fulfillment

Symptom: you added variants to a product that was ALREADY synced, every call returned success, but reading the product back shows the new variants with `provider_external_id` (a.k.a. `external_id`) **`null`** while the original variants have it. Orders for the new variants may not reach the provider.

**Cause**: `provider_external_id` is the variant's FULFILLMENT-provider link, stamped during the fulfillment sync — not by `add_variants`. Until it is stamped, the webhook that ingests a paid order **skips that line** (and manual order / estimate creation rejects the variant). The listing looks fine; the order silently under-fulfills.

**Fix**: re-run the fulfillment sync — `sync_to_fulfillment(product_uuid, store_uuid)` (MCP), or Phase 7 `?target=merchandise` (REST) — then re-read the product and confirm every variant now has a non-null `provider_external_id`. If the product is also listed on a channel, re-run the channel sync too. See `product-creation-pipeline.md` → "Updating a product that's ALREADY synced."

**A name collision to know (not a bug)**: the variant-level `provider_external_id` / `external_id` is the FULFILLMENT link; the channel-level `external_id` under `ecommerce_statuses[]` is the storefront LISTING id. A null variant link says nothing about the channel — do not read it as "the channel lost the product."

### 0 variants added — the requested colors/sizes don't exist on the garment

Symptom: you called `add_variants` but the product ends with 0 (or fewer than expected) variants. On MCP v0.3.1+ `add_variants` throws `bad_request` listing the garment's real colors/sizes; older behavior returned `variants_added: 0` silently and shipped an unsellable product (this is what left a World-Cup Cap with 0 variants).

**Cause**: sizes are matched EXACTLY and you assumed apparel sizes (S/M/L/XL/2XL) for a garment that's one-size or uses different labels — caps, beanies, phone cases, bottles, bags, etc.

**Fix**: fetch the garment's real matrix (`GET /agents/v1/merchandise/<provider_uuid>/product/<product_ref_id>`, or the `get_garment_details` MCP tool) and build the variant list from the colors/sizes it actually offers. See `references/product-creation-pipeline.md` Phase 5.

### `verify_design_quality` returns a "block" / low-resolution — do NOT skip the item

Symptom: a design fails a pre-flight QC gate with a resolution "block" (e.g. `847x596`), and an
unattended/scheduled build skips the item — which then never gets built.

**Cause**: keying + tight-crop shrinks a design (a 1024×1024 design can crop to `847x396`). Older
QC treated a min side < 600px as a hard BLOCK.

**Fix (MCP v0.3.9+, automatic)**: low resolution is now a WARN, never a block — `process_transparency`
upscales its keyed output to a resolution floor, and `ship_product`'s placed path upscales to the
print area, so the design builds. **Do not treat low resolution as a reason to skip.** The warn
means "regenerate the source at 1024px+ for genuinely sharp large-format detail," not "abort."

**Rule for any automated/scheduled build loop**: only a HARD block (an item explicitly marked
un-buildable, or a genuine unrecoverable error) should defer an item — and even then, DEFER +
RETRY-NEXT-RUN, never permanently skip in a way that stalls the whole run. See "Scheduled /
reconciler builds" in `product-creation-pipeline.md`.

### `verify_design_quality` blocks on a green halo or a black box — these ARE hard blocks

Symptom: a design fails QC with `Chroma-key green survives on N% of the visible design` or
`A solid black rectangle covers N% of the visible design`.

**Unlike the resolution warn above, treat both as genuine blocks.** The pipeline upscales a
low-resolution design, so that warn is recoverable — but nothing downstream removes a halo or a
slab. They print exactly as they look: a green outline around the artwork, or a filled black
rectangle on the garment.

**Fix**: re-run `process_transparency` for a halo; regenerate for a black box (and if it recurs,
iterate with a prompt that names the artifact so the model removes it).

These checks are new (MCP v0.5.16). Before that, `verify_design_quality` measured only alpha,
resolution and premultiply — so it could and did return **100/100 on a design with both defects**.
If you are running an older MCP build, a perfect score does not mean the design is visually clean;
look at it.

### `text_verified.has_text` is `null` — that means UNKNOWN, not "no text"

`verify_design_text` reads text with local OCR (tesseract). When tesseract is not available it
cannot look at all, so it returns `has_text: null`.

**Do not treat `null` as falsy.** `false` means OCR ran and found no text; `null` means the question
was never answered. If you skip the spelling check on a `null`, you can ship a design covered in
misspelled text believing it had none — which is exactly what happened before MCP v0.5.16, when this
case returned `false`.

**Fix**: on `null`, read the design image yourself and verify any spelling visually, or install
tesseract in the environment running the MCP server.

### "No variants could be resolved" on a garment with ONE dimension (clear phone cases etc.)

Symptom: `ship_product` / `add_variants` fails with `bad_request: No variants could be resolved` even though your size names are correct.

**Cause**: many non-apparel goods have a SINGLE variant dimension. A clear phone case's catalog has device sizes ("iPhone 15", "iPhone 16 Pro Max"...) but **no color at all**; some one-size goods have colors but no size. Requiring a color+size match against a catalog that lacks one dimension matches nothing (the WC26 MOROCCO clear-case failure).

**Fix**: on MCP v0.3.6+ this is automatic — the resolver matches by the dimension the catalog HAS and keeps your requested name as the variant label (a warning explains the match), and the error lists the catalog's real color/size names when nothing resolves. On older versions or the raw API: pass explicit `provider_variant_ids`, or send the catalog's own values verbatim (e.g. color `""`).

### Fulfillment sync wasn't run before ecommerce sync (Phase 7 ordering)

Ecommerce sync (Shopify/Etsy/etc.) needs the fulfillment SKU to attach. If you try `target=ecommerce` before `target=merchandise`, the ecommerce sync may succeed cosmetically but the product won't have a manufacturing path.

**Fix**: ALWAYS run `?target=merchandise` first. Wait for it to return success. Then run `?target=ecommerce`.

### Integration credentials revoked

User disconnected the channel from apparelhub.ai, OR Shopify Token Exchange returned an unauthorized response, OR WooCommerce keys were rotated upstream without reconnecting.

**Diagnostic**: `GET /agents/v1/store/<store_uuid>/integrations` — check `is_connected` and `last_health_check_status`.

**Fix**: have the user reconnect the integration in the store dashboard.

### Display image is the raw design URL, not a mockup

Symptom: the product card thumbnail shows the flat design on a green background (or transparent checkerboard), not a real mockup.

**Cause**: no mockup was ever generated, so `display_image` fell back to `print_data[0].image_url` (the raw design). Common causes: you skipped Phase 3 entirely, OR (MCP split flow) you called `create_product` with `generate_mockup: true` but pre-0.3.1 that was a silent no-op unless `mockup_variant_ids` was ALSO passed — so no preview job was created. (Every product in the World-Cup automated run shipped this way.)

**Fix**: generate a mockup and attach it. Easiest: use `ship_product` (mockup is built in), or `create_product` with `generate_mockup: true` on MCP v0.3.1+ (it now auto-derives representative variants). To repair an existing product, `PATCH /agents/v1/product/<uuid>` with `display_image` set to a real mockup URL from the preview job's preview rows. See `references/product-creation-pipeline.md` Phase 3 + 4.0.

### Wrong field names in Phase 4 (product create)

Symptom: product was created, `uuid` returned, but `manufacturing_metadata` is NULL when you fetch it, and sync silently fails.

**Cause**: used `merchandise_provider_uuid` instead of `provider_uuid`, OR `provider_product_ref_id` instead of `product_ref_id`, OR `retail_price` instead of `price`. The Phase 3 preview endpoint uses the FIRST names; Phase 4 create endpoint uses the SECOND.

**Fix**: delete the broken product (`DELETE /agents/v1/product/<uuid>`) and re-create with the correct field names. See `references/product-creation-pipeline.md` Phase 4 for the gotcha table.

### Mockup `preview_url` is still NULL when you call create

Symptom: product created, but `display_image` auto-resolution picked the raw design URL instead of a mockup.

**Cause**: the preview job's status was `completed` but the S3 ingestion hadn't finished yet. There's a two-phase race — job complete is one thing, S3 mirror populated is another. Gap can be 20+ minutes.

**Fix**: poll the preview-job/previews endpoint until at least one row has a non-null `preview_url` BEFORE calling product create. Or PATCH the product's `display_image` after the fact.

---

## 4. Embroidery-specific failures

### `thread_colors_chest_left option is missing or incorrect`

The `options` block is at the wrong level in your sync payload (probably on the file inside `files[]` instead of at `sync_variants[i].options`).

**Fix**: see `references/embroidery.md` section 5 for the canonical shape. Move options out of the file and put them at the variant level.

### `Allowed values: #FFFFFF, #000000, ...` followed by the 15-color palette

You sent a color that's not in Printful's 15-thread palette.

**Fix**: re-pick thread colors from the design using the 15-color palette only. See `references/embroidery.md` section 1 for the palette + section 8 for the empirical color picker.

---

## 5. Diagnostic discipline

When a workflow fails:

1. **Read the actual response body**. ApparelHub returns structured error JSON; don't just look at the status code.
2. **Check the audit log** for the affected resource. `GET /agents/v1/store/<uuid>/audit-log?...` reveals every state transition with structured details.
3. **Verify the failing field via the OpenAPI spec**: `https://api.apparelhub.ai/agents/v1/openapi.json` (authed with the user's key). Field names drift; check the canonical source.
4. **Reproduce in isolation**. Don't retry an entire pipeline — pinpoint the failing phase and re-run just that one.
5. **Surface the truth to the user**. Don't paper over a real failure with a generic "sync had issues" message. Tell them what specifically failed and what the next step is.

---

## 6. When to give up and escalate

Tell the user to contact ApparelHub support at `support@apparelhub.ai` when:

- 500-class errors persist for >5 minutes across retries
- The OpenAPI spec disagrees with observed API behavior (suggests a deploy in progress OR a real bug)
- An order is stuck in `submitted` for >24 hours with no `ORDER_CONFIRMED` audit row and no error in the log
- An integration that was healthy yesterday returns 401 today with no merchant-side change (suggests credential rotation upstream)
- A sync succeeded according to the API but the product genuinely doesn't appear on the storefront after >15 minutes (verify on the channel admin, not just the public storefront)

Don't escalate for things you can fix: wrong field names, missing variants, draft/live state, locked integrations the merchant can unlock themselves.
