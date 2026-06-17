# Worked example — review and approve a held order as an agent

Goal: a store runs `fulfillment_mode=review` (or `auto` with guardrails) and
`approval_authority=agent`. You are the agent. An order comes in, gets held, and
you decide what to do with it.

See `references/orders-and-fulfillment.md` sections 8–10 for the full contract.

---

## 0. (One time) Put the store in agent-review mode

```bash
curl -sS -X PATCH "https://api.apparelhub.ai/agents/v1/store/$STORE_UUID/settings" \
  -H "x-api-key: $APPARELHUB_API_KEY" -H "Content-Type: application/json" \
  -d '{
        "fulfillment_mode": "auto",
        "approval_authority": "agent",
        "hold_below_margin_pct": 25,
        "hold_on_negative_margin": true
      }'
```

This says: auto-fulfill paid orders, BUT hold any order whose margin is under
25% (or negative) for the agent to review.

## 1. Find orders waiting on you (poll-first, the guaranteed path)

```bash
curl -sS "https://api.apparelhub.ai/agents/v1/orders?requires_approval=true&store_uuid=$STORE_UUID" \
  -H "x-api-key: $APPARELHUB_API_KEY"
```

Each held order already includes the decision context:

```json
{
  "uuid": "8f1c...",
  "external_display_id": "#1042",
  "fulfillment_status": "on_hold",
  "requires_approval": true,
  "hold_reason": "low_margin",
  "total_price": 27.99,
  "cost_total": 22.40,
  "profit_margin": 5.59
}
```

## 2. Decide

`profit_margin / total_price = 5.59 / 27.99 = 20%`, which is under the 25%
threshold — that is why it was held. Apply your own business logic. For example:

- Margin still positive and above your floor → **approve**.
- Margin too thin / negative → **keep on hold** (or cancel) and flag the merchant.

```bash
# Approve → releases the hold and sends the order onward
curl -sS -X POST "https://api.apparelhub.ai/agents/v1/orders/8f1c.../approve" \
  -H "x-api-key: $APPARELHUB_API_KEY"

# OR keep it held with a note for the merchant
curl -sS -X POST "https://api.apparelhub.ai/agents/v1/orders/8f1c.../hold" \
  -H "x-api-key: $APPARELHUB_API_KEY" -H "Content-Type: application/json" \
  -d '{"reason":"margin below floor; asked merchant to reprice"}'
```

## 3. If the order later shows a manufacturer (Printful) design hold

That is a DIFFERENT hold (`fulfillment_substatus` set). Handle it separately:

```bash
curl -sS "https://api.apparelhub.ai/agents/v1/orders/8f1c.../holds" -H "x-api-key: $APPARELHUB_API_KEY"
# then, per the returned hold uuid:
curl -sS -X POST "https://api.apparelhub.ai/agents/v1/orders/8f1c.../holds/<hold_uuid>/approve" \
  -H "x-api-key: $APPARELHUB_API_KEY"
```

## 4. (Optional) Get pinged instead of polling

Set an `agent_callback_url` in the store settings; you get a one-time signing
secret in the PATCH response. We then POST `order.awaiting_approval` to your URL
with an `X-ApparelHub-Signature: sha256=<hmac>` header you verify against the
raw body. Polling (step 1) keeps working regardless, so treat the callback as a
nudge, not the source of truth.
```
