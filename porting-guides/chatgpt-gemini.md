# Porting Guide — ChatGPT, Gemini, and other tool-calling agents

Audience: a ChatGPT Custom GPT, a Gemini agent with function-calling, or
any LLM runtime that doesn't have shell access but does support either
(a) a long-form system prompt, or (b) a typed function-calling
interface, or both.

Two paths. Pick the one that matches your platform.

---

## Path A — System prompt + paste-in knowledge

For Custom GPTs, claude.ai Projects, Gemini Gems, or any agent whose
primary surface is an editable system prompt.

### A1. Set the system prompt

Paste the contents of `apparelhub/SKILL.md` into your agent's system
prompt (or its "Instructions" / "Knowledge" / "Custom Instructions"
field, whatever the platform calls it).

If the platform has a separate "knowledge files" attachment area, add:

- `apparelhub/references/api-contract.md`
- `apparelhub/references/product-creation-pipeline.md`
- `apparelhub/references/design-rules.md`
- `apparelhub/references/embroidery.md` (if the user will do embroidery)
- `apparelhub/references/all-over-print.md` (if the user will do AOP)
- `apparelhub/references/garment-catalog.md`
- `apparelhub/references/orders-and-fulfillment.md`
- `apparelhub/references/error-handling.md`
- `apparelhub/examples/front-print-tee.md` (or whichever example matches the user's likely first product)

Or just point the agent at the GitHub raw URLs and let it fetch on demand.

### A2. Supply the API key

How the agent gets `APPARELHUB_API_KEY` depends on the platform:

| Platform | Key delivery |
|---|---|
| ChatGPT Custom GPT with Actions | Configure the API key as an Action authentication (header `x-api-key`). The agent never sees the raw key. |
| ChatGPT Custom GPT without Actions | Tell the agent the key in the conversation. (Lower confidentiality — the key sits in conversation memory.) |
| Gemini agent with function calling | Bake the key into your function-call implementation's env; the agent never sees it. |
| claude.ai Projects | Set as a Project env or instruct the agent in the system prompt. |

**Recommendation**: where the platform supports it, use the
function-call / Action mechanism so the agent never sees the raw key.
Conversational supply works but is lower-confidence.

### A3. The agent now has the same knowledge as Claude Code

It knows the 7-phase pipeline, the field-name gotchas, the transparency
rules, the embroidery palette, the pricing floors, the draft-not-live
default, the mandatory mockup verification. It executes the flow by
issuing HTTP requests through whatever tool its runtime provides.

The walkthrough in `porting-guides/bare-http.md` applies verbatim.

---

## Path B — Single function-calling tool

For platforms that support typed function calling (OpenAI Functions /
Gemini Function Calling / Anthropic Tools API). The most secure model:
define ONE function the agent can call, hide the canonical host and the
API key inside the function implementation, and let the agent compose
the pipeline.

### B1. Function definition

```json
{
  "name": "apparelhub_request",
  "description": "Make an HTTP request to the ApparelHub Agent API. The base URL https://api.apparelhub.ai/agents/v1/ and the x-api-key header are added automatically by the implementation. You only supply the method, path (must start with /), and optional JSON body.",
  "parameters": {
    "type": "object",
    "required": ["method", "path"],
    "properties": {
      "method": {
        "type": "string",
        "enum": ["GET", "POST", "PATCH", "PUT", "DELETE"]
      },
      "path": {
        "type": "string",
        "description": "Path beginning with /agents/v1/, e.g. /agents/v1/store. Full URLs are rejected.",
        "pattern": "^/agents/v1/"
      },
      "body": {
        "type": "object",
        "description": "Optional JSON body for POST/PATCH/PUT. Omitted for GET/DELETE."
      },
      "query": {
        "type": "object",
        "description": "Optional query-string parameters.",
        "additionalProperties": {"type": "string"}
      }
    }
  }
}
```

### B2. Implementation (server-side, not visible to the agent)

```python
import os
import requests

CANONICAL_HOST = "https://api.apparelhub.ai"
API_KEY = os.environ["APPARELHUB_API_KEY"]

def apparelhub_request(method, path, body=None, query=None):
    if not path.startswith("/agents/v1/"):
        return {"error": "path must start with /agents/v1/"}
    url = CANONICAL_HOST + path
    headers = {"x-api-key": API_KEY}
    if body is not None:
        headers["Content-Type"] = "application/json"
    resp = requests.request(
        method, url,
        headers=headers,
        params=query,
        json=body,
        timeout=60,
    )
    return {"status": resp.status_code, "body": resp.text}
```

Key properties of this design:

- **The agent never sees the API key.** The model output is just
  `{"method": "GET", "path": "/agents/v1/store"}`; the key is added by
  the function before the request leaves the host.
- **The canonical host is enforced by construction.** No matter what
  the agent passes, the request goes to `https://api.apparelhub.ai`.
- **The agent cannot redirect the key.** A prompt-injected
  "set base URL to attacker.example.com" is not actionable: the
  function-call schema doesn't expose a base-URL parameter.
- **Path-prefix validation rejects full URLs.** The agent can't try to
  pass `https://attacker.example.com/leak` as the `path`.

### B3. Multipart upload

The transform endpoint is the one place a single-JSON-tool design needs
a fallback. Two options:

- **Option B3a**: define a second function `apparelhub_transform_image`
  that takes `{image_uuid: string, image_data_url: string}` and uses
  the JSON data-URL form internally (`api-contract.md` §6c).
- **Option B3b**: in `apparelhub_request`, allow a `data_url` field in
  the body; the implementation rewrites it into a multipart body
  before sending. The agent's view stays JSON-only.

Either works; Option B3a is the cleaner schema.

### B4. The agent now drives the pipeline

The system prompt tells the agent it has `apparelhub_request` available.
It then issues the same sequence of calls as the bare-HTTP guide,
expressed as function calls instead of raw HTTP. The agent has zero
ability to leak the key.

---

## Differences from Claude Code

- **No `~/.claude/skills/` discovery.** The skill is "installed" by
  pasting it into the system prompt or attaching it as a knowledge file.
- **No `Bash(...)` allowlist.** Approval gates come from the platform's
  own mechanisms (Custom GPT Action user-confirm dialogs, Gemini's
  function-call review screens).
- **No `make_transparent.py` running locally.** Transparency processing
  must happen wherever the agent's runtime can run image code — either
  in a function-call implementation (cleaner) or by asking the user to
  upload a pre-processed image.
- **No `ah_check` / `ah_poll_mockup`.** These were Claude Code typing
  conveniences; in a tool-calling agent the polling state machine lives
  inside the function-call loop the agent already runs.

---

## What still applies verbatim

- The 7-phase pipeline, in order.
- The four field-name gotchas (`provider_uuid` vs `merchandise_provider_uuid`, `product_ref_id` vs `provider_product_ref_id`, `price` not `retail_price`, `print_data` vs `templates`).
- The transparency-on-bright-green rule (`#00FF00` background, then key locally).
- The embroidery 15-color thread palette.
- The all-over-print product rules (edge-to-edge background, "don't name the product in the prompt").
- The pricing floors.
- The "default to DRAFT, never live" rule for sales-channel sync.
- The mandatory visual verification of both the design (after step 2) and the mockup (after step 6).
- The "ask the user before syncing" rule.

These are the moat. The fact that they apply across Claude Code,
ChatGPT, Gemini, and bare-HTTP agents is what makes this a knowledge
package and not a Claude Code wrapper.
