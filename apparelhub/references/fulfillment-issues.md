# Post-sale fulfillment issues — report defects, bridge them to the provider, track to resolution

When a fulfilled item arrives wrong (print doesn't match the mockup, damaged in
transit, wrong item, missing item, bad print quality), ApparelHub is the system
of record for the problem AND the assisted bridge upstream to the fulfillment
provider (Printful / Printify). This reference covers the full loop:
report → evidence → provider handoff → claim tracking → resolution → optional
replacement order.

## 1. The one fact that shapes everything

**Fulfillment providers accept problem reports ONLY in their own dashboards.**
There is no provider API to file a claim (verified against Printful v1 +
v2-beta and Printify docs). Both providers:

- accept reports for **30 days from delivery** (hard window),
- require **photo evidence**,
- resolve approved claims as a **free reprint** or a **wallet/balance refund**.

So the ApparelHub flow is ASSISTED, not automatic: you structure the report the
way the provider's form wants it, ApparelHub gives you a copy-paste-ready
summary + a dashboard deep-link, the merchant files it there, and you record
the provider's claim reference back on the issue. Printful refunds and returns
are then detected automatically (issues you marked as filed auto-resolve when
Printful refunds); Printify claims are resolved manually.

## 2. Report an issue

```
POST /agents/v1/orders/{order_uuid}/issues
{
  "category": "mockup_mismatch",
  "title": "Logo printed oversized",
  "description": "The logo wraps around the product instead of printing on a single face. Does not match the approved mockup.",
  "resolution_requested": "reprint",
  "items": [{"order_item_id": 123, "quantity_affected": 1}]
}
```

Categories: `mockup_mismatch`, `print_quality`, `damaged_in_transit`,
`wrong_item`, `wrong_size_or_color`, `missing_item`, `blank_or_mislabeled`,
`late_delivery`, `lost_in_transit`, `other`.

`resolution_requested`: `reprint` (default) | `refund_wallet` |
`refund_customer` | `replacement_order` | `other` | `none`.

The 201 response includes `issue.warnings` — READ THEM AND RELAY THEM. They
are deterministic eligibility hints from the providers' published policies:

- `wrong_size_or_color` when the customer simply prefers a different size or
  color is "change of mind" and is NOT eligible for a free reprint. Only a
  product that differs from what was actually ordered qualifies. Size
  deviations under about an inch are also ineligible.
- `print_quality` caused by a low-resolution design file is not covered.
- The 30-day window: `issue.eligibility.days_remaining` tells you how long is
  left; a warning fires at 7 days or less, and another when the window has
  already passed (still file it, but the provider may reject).

## 3. Attach evidence (required by providers)

Small photos (up to 4MB each) go direct:

```
POST /agents/v1/orders/issues/{issue_uuid}/attachments
(multipart, field "files", JPEG/PNG)
```

Bigger files (large photos, one MP4/MOV video) use the two-step flow:

```
POST /agents/v1/orders/issues/{issue_uuid}/attachments/initiate
{"filename": "defect.mp4", "content_type": "video/mp4", "size": 12345678}
-> {"attachment_id": "...", "upload_url": "...", "content_type": "video/mp4"}

PUT the raw file bytes to upload_url with that exact Content-Type header, then:

POST /agents/v1/orders/issues/{issue_uuid}/attachments/{attachment_id}/complete
```

Caps (they mirror the providers' own limits): **5 files per issue**, images
15MB or less, at most **one** video, 250MB or less.

⚠️ Providers do NOT accept links — when the merchant files the report on the
provider form, they must download the evidence from the issue (each attachment
carries a short-lived `url`) and upload it to the provider form directly.

## 4. The provider handoff (the important part)

Preview the provider-ready report at any time:

```
GET /agents/v1/orders/issues/{issue_uuid}/provider-report
```

Returns `{provider_report: {provider, provider_order_id, dashboard_url,
summary_text, evidence_count, warnings}}`. `summary_text` is a copy-paste-ready
problem report structured the way the provider's form wants it (items,
quantities, reason, details, requested resolution). `dashboard_url` deep-links
to the provider page where the report is filed.

When the merchant files it (or you walk them through it), mark the issue:

```
POST /agents/v1/orders/issues/{issue_uuid}/submit-upstream
{"provider_claim_ref": "CASE-12345"}      # optional but valuable
```

That transitions the issue `open -> submitted_upstream`, records the claim
reference, and returns the provider report in the same response.

## 5. Track + resolve

- `GET /agents/v1/orders/issues` — workspace inbox. Filters: `?status=open`,
  `?status=open_any` (open + filed), `?store=<uuid>`, `limit`/`offset`. Add
  `?workspace=<uuid>` for non-default workspaces (same rule as order reads).
- `GET /agents/v1/orders/{order_uuid}/issues` — one order's issues +
  the current report-window eligibility.
- `GET /agents/v1/orders/issues/{issue_uuid}?include_report=true` — full detail.

**Printful:** when Printful refunds the merchant, ApparelHub detects it and an
issue already marked `submitted_upstream` auto-resolves as `resolved_refund`
(the merchant is also notified). A returned package is stamped onto open
issues as claim context.

**Printify:** no automatic detection exists — when the provider approves the
claim, record it:

```
POST /agents/v1/orders/issues/{issue_uuid}/resolve
{"resolution_type": "reprint", "notes": "Provider approved a free reprint, new order in production."}
```

`resolution_type`: `reprint` | `refund_wallet` | `refund_customer` |
`replacement_order` | `other` | `none` (= close without resolution).

Statuses you'll see: `open`, `submitted_upstream`, `resolved_reprint`,
`resolved_refund`, `resolved_replacement`, `resolved_other`, `rejected`,
`closed`.

## 6. Replacement (reship) orders

When the merchant wants to reship at their own cost (or alongside a provider
claim):

```
POST /agents/v1/orders/issues/{issue_uuid}/replacement-order
```

Creates a NEW zero-charge draft order (payment recorded as `no_payment` — the
customer is never charged for a replacement) containing the affected line
items, with the recipient address pulled live from the fulfillment provider
(ApparelHub never stores recipient addresses). The draft respects the store's
fulfillment workflow: on a confirm/review store it waits in the approval queue
like any other draft.

Structured failures to handle honestly (all 4xx with `{error, message}`):

- `recipient_unavailable` — the provider order had no complete address; create
  the order manually with the recipient details.
- `variant_unlinked` — a line item isn't linked to a product variant (common
  on manual orders); create the replacement manually.
- `replacement_exists` — this issue already has one (`replacement_order_uuid`).

## 7. Gotchas

- **Don't report before checking the mockup-vs-product claim yourself** when
  the user shares photos: if the product matches the approved mockup and the
  customer just dislikes it, that's change-of-mind — not claim-eligible.
- **The window is from DELIVERY, not order date.** An order that hasn't been
  delivered yet has no deadline (`eligibility.basis = "not_delivered"`).
- **File within the window.** ApparelHub reminds the merchant automatically
  when an unfiled issue is 7 days from its deadline, but don't rely on it —
  if `days_remaining` is low, say so and push the handoff in the same breath.
- **Workspace scoping applies** exactly like order reads: a paramless request
  sees the Default workspace. Pass `?workspace=<uuid>` when the store lives
  elsewhere, and don't conclude an issue is missing on a 404 until you've
  tried the right workspace.
- Evidence uploads are the only asset-writing surface here and they're capped
  by design; issue reporting is NOT metered against any generation quota.
