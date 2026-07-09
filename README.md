# ApparelHub Skill

A **portable knowledge package** for AI agents that drive
[ApparelHub.ai](https://apparelhub.ai), the multi-channel ecommerce platform
for custom merchandise (design with AI, then list, sell, and fulfill across
every channel). Use it with Claude Code, Claude Web, ChatGPT,
Gemini, or any agent that can make HTTP requests.

The knowledge core (the 7-phase product pipeline, the field-name
gotchas, the transparency rules, the embroidery thread palette, the
all-over-print rules, the pricing floors, the draft-not-live default,
the mandatory mockup verification) is host-neutral. Optional Claude
Code conveniences live under `claude-code/`.

**This is v2.0, a security-first re-architecture of v1.x.** See
[`SECURITY.md`](./SECURITY.md) for the trust model. v1.x users:
migration notes are at the bottom of this README and in the v2.0
GitHub release notes.

**Who this is for**

- Anyone with an ApparelHub account on the Professional or Enterprise
  tier who wants to drive the platform from an AI agent.
- Claude Code users — see [`porting-guides/claude-code.md`](./porting-guides/claude-code.md).
- ChatGPT Custom GPT / Gemini / claude.ai Projects users — see [`porting-guides/chatgpt-gemini.md`](./porting-guides/chatgpt-gemini.md).
- Agents with only HTTP capability — see [`porting-guides/bare-http.md`](./porting-guides/bare-http.md).

**Quick links**

- Setup walkthrough: <https://apparelhub.ai/agents>
- Browser API docs: <https://apparelhub.ai/developer/api-docs>
- Generate an API key: <https://apparelhub.ai/developer/api-keys>
- Security and trust model: [`SECURITY.md`](./SECURITY.md)

---

## What's in this repo

```
apparelhub-skills/
├── SECURITY.md                          # Trust model + non-goals + threat model
├── apparelhub/                          # Host-neutral knowledge package
│   ├── SKILL.md                         # Router, host-neutral
│   ├── BOOTSTRAP-PROMPT.md              # Paste-into-system-prompt scaffold
│   ├── references/
│   │   ├── api-contract.md              # Canonical HTTP contract
│   │   ├── product-creation-pipeline.md # 7-phase workflow detail
│   │   ├── design-rules.md              # AI prompts, transparency, vision verify
│   │   ├── embroidery.md                # Thread palette + sync payload shape
│   │   ├── all-over-print.md            # Pillows, doormats, luggage tags
│   │   ├── garment-catalog.md           # Variant IDs, pricing floors
│   │   ├── orders-and-fulfillment.md    # Order data + payment authority
│   │   └── error-handling.md            # 4xx/5xx semantics + silent failures
│   ├── examples/
│   │   ├── front-print-tee.md           # Bella+Canvas 3001 end-to-end
│   │   ├── all-over-pillow.md           # 18×18 pillow end-to-end
│   │   └── embroidered-anorak.md        # Champion Anorak chest crest end-to-end
│   └── scripts/                         # Optional Claude Code conveniences
│       ├── ah_check                     # Auth precondition: verify key works
│       ├── ah_poll_mockup               # Two-phase mockup wait state machine
│       ├── ah_classify_previews         # Local preview-row parser
│       ├── ah_pick_provider_url         # Extract one preview URL by color+angle
│       ├── ah_pick_dimensions           # Compute print dimensions from design
│       └── make_transparent.py          # Chroma key + auto-crop
├── porting-guides/                      # Per-platform install/usage walkthroughs
│   ├── bare-http.md
│   ├── claude-code.md
│   └── chatgpt-gemini.md
├── claude-code/                         # Claude-Code-specific overlay
│   ├── README.md
│   ├── settings.recommended.json        # Optional permission allowlist
│   └── install_path.sh                  # PATH editor used by install.sh
├── acceptance/
│   └── playbook.md                      # Pre-release verification
├── .github/workflows/
│   └── forbidden-patterns.yml           # CI guard for v1.x antipatterns
└── install.sh                           # Claude Code installer
```

The knowledge in `apparelhub/` is what any agent reads. Everything
else is platform-specific scaffolding.

---

## Install

Pick the path that matches your agent.

### Hosted connector for Claude.ai, Perplexity, ChatGPT (no install)

The lowest-friction path, with nothing to install. In Claude.ai or Perplexity (or ChatGPT on Business or Enterprise), add a **custom connector** pointing at:

```
https://mcp.apparelhub.ai
```

Sign in to ApparelHub once and the connector links to your account. Your agent gets the full ApparelHub tool surface (design, build, sync, orders) as typed tools, run on our compute. No key to paste, no shell. Walkthrough: [Use ApparelHub from Claude on the web](https://apparelhub.ai/blog/use-apparelhub-from-claude-web).

The rest of this section covers running the skill or tools inside your own agent runtime.

### Claude Code (CLI on macOS/Linux)

```bash
curl -fsSL https://apparelhub.ai/install-skill.sh | bash
```

The installer:

1. Clones the repo to `~/.apparelhub-skills/`.
2. Symlinks `~/.apparelhub-skills/apparelhub/` into `~/.claude/skills/apparelhub/`.
3. Adds the skill's `scripts/` directory to your shell PATH (bash, zsh, fish).
4. Prompts for your `APPARELHUB_API_KEY` (or reads it from env), verifies it against the platform with `ah_check`, then exits.
5. **Does not persist the key to disk by default** — that changed in v2.0 (see [`SECURITY.md`](./SECURITY.md)). Put `export APPARELHUB_API_KEY=...` wherever you manage development secrets: shell rc, direnv, macOS Keychain, 1Password CLI, etc.

If you want the v1.x persistent-`.env` behavior, pass `--persist`:

```bash
curl -fsSL https://apparelhub.ai/install-skill.sh | bash -s -- --persist
```

You'll see a warning explaining the trade-off before the write happens.

Inspect the script before piping to bash:

```bash
curl -fsSL https://apparelhub.ai/install-skill.sh | less
```

Source on GitHub: <https://github.com/ApparelHub-AI/apparelhub-skills/blob/main/install.sh>

Then follow [`porting-guides/claude-code.md`](./porting-guides/claude-code.md).

### ChatGPT Custom GPT / Gemini / claude.ai Projects

Two paths in [`porting-guides/chatgpt-gemini.md`](./porting-guides/chatgpt-gemini.md):

- **Path A** — paste [`apparelhub/SKILL.md`](./apparelhub/SKILL.md) (or [`apparelhub/BOOTSTRAP-PROMPT.md`](./apparelhub/BOOTSTRAP-PROMPT.md) for a short version) into the agent's system prompt, attach the `references/` files as knowledge files.
- **Path B** — register a single `apparelhub_request(method, path, body)` function that hides the canonical host and the API key inside the implementation. The agent can compose the pipeline without ever seeing the raw key. Highest-confidence path for production use.

### Bare-HTTP agent

Read [`porting-guides/bare-http.md`](./porting-guides/bare-http.md).
Same flow, no shell, no scripts, no filesystem. Multipart-from-disk
or JSON data-URL — your choice. The HTTP contract is in
[`apparelhub/references/api-contract.md`](./apparelhub/references/api-contract.md).

---

## Optional — Claude Code permission allowlist

The repo ships [`claude-code/settings.recommended.json`](./claude-code/settings.recommended.json)
with patterns that allowlist the helper scripts plus the canonical
`https://api.apparelhub.ai` curl prefix. Merge it into your
`~/.claude/settings.json` to drop a few prompts on routine calls.

**Note.** Claude Code will still prompt the first time the agent
expands `$APPARELHUB_API_KEY` even with the allowlist in place. That's
the safety control working correctly. Approve in context if the call is
one you intended. The skill no longer ships wrappers whose purpose is
to dodge those prompts; see [`SECURITY.md`](./SECURITY.md) §2a.

---

## What changed in v2.0

The full migration guide is in the v2.0 GitHub release notes. The
short version:

- `ah_curl` is deleted. It forwarded the API key to arbitrary URLs.
  Replace any of your own scripts that called `ah_curl GET /...` with
  plain `curl https://api.apparelhub.ai/agents/v1/...` invocations.
- `APPARELHUB_API_BASE` is no longer read by helpers or the installer.
  The canonical host `https://api.apparelhub.ai` is hard-pinned.
  Internal contributors targeting dev should fork and edit the constant
  at the top of the script.
- The installer no longer writes `~/.apparelhub-skills/.env` by default
  and no longer edits your shell rc. Manage `APPARELHUB_API_KEY` via
  your host's secret manager.
- The Claude Code-specific bits (`settings.recommended.json`, the PATH
  helper) moved into a `claude-code/` overlay.

**Migration for v1.x users:**

1. Remove the v1.x rc-file sourcing line `[ -f ~/.apparelhub-skills/.env ] && . ~/.apparelhub-skills/.env` (or `source ~/.apparelhub-skills/.env.fish`).
2. `rm -f ~/.apparelhub-skills/.env ~/.apparelhub-skills/.env.fish`.
3. Put `export APPARELHUB_API_KEY=...` in wherever you manage dev secrets.
4. If you suspect the v1.x `.env` was ever exposed, rotate the key at <https://apparelhub.ai/developer/api-keys>.
5. Re-run the installer: `curl -fsSL https://apparelhub.ai/install-skill.sh | bash`.
6. Update your `~/.claude/settings.json` to use the v2.0 patterns in [`claude-code/settings.recommended.json`](./claude-code/settings.recommended.json) (drop the `Bash(ah_curl ...)` entries).
7. Replace any `ah_curl` invocations in your own scripts with plain `curl https://api.apparelhub.ai/agents/v1/...` calls.

---

## Versioning

| Version | Date | Summary |
|---|---|---|
| 2.14 | 2026-07-09 | **Wrap goods: the print area is not always the visible face (all-over-print §9-§10, design-rules §7, error-handling).** Grid-calibrated facts from the WC26 QC incidents: sublimation sock leg FRONT strips render the print file rotated 180° (file-top = toe) while the BACK strips render upright, the strip wraps the leg so only the central ~64% stays frontal, and ALL FOUR strips need files (unprinted = raw white fabric); drawstring-bag "front" areas are front+back in ONE file folded at the bottom (visible front = top ~50%, art centered on the area straddles the fold); AOP-backpack sibling placements (top/bottom/pocket) need solid background files. Extreme-aspect fill areas (≤1:2 / ≥2.2:1) are suspect wraps — preview before building. Mockup gate (§7) gains upright-orientation, fold/silhouette-clipping, all-placements-covered, no-chroma-green, and full-resolution-inspection checks, plus: collar breathing room is an APPAREL concept — non-apparel placed goods (phone cases, mugs) center the design. Error-handling gains the single-dimension variant case (clear phone cases have NO color dimension — match by size or pass provider_variant_ids). Pairs with `apparelhub-mcp` v0.3.6 (does all of this automatically). Docs only — no script, settings, or installer changes. |
| 2.13 | 2026-07-09 | **Mockups must cover every color variant you import (design-rules §7b).** New rule: decide your color variants BEFORE generating the mockup, then make sure the mockup covers each color. Mockups render per variant and same-color variants share one print image, so "the first N variants" is all ONE color — leaving the other imported colors (e.g. White when you offer Black + White) with no mockup and a wrong-looking gallery. `ship_product` now renders **one mockup per distinct imported color** automatically (`apparelhub-mcp` v0.3.3); `create_product`'s auto-mockup samples one-per-color from the catalog (best-effort — it runs before variants exist, so for color-accurate mockups use `ship_product` or pass `mockup_variant_ids`); raw Phase 3 should pass one `variant_id` per color. Docs only — no script, settings, or installer changes. |
| 2.12 | 2026-07-08 | **Product pipeline: "map to store" is NOT "publish to a sales channel", + mockup/variant automation guardrails.** Reframes the creation pipeline so it ENDS at Phase 7 (product created, mapped to the store, fulfillment-synced = sellable); pushing a storefront listing is a new OPT-IN Phase 8, done ONLY when the user explicitly asks to list/publish (a scheduled task had wrongly turned "map it to the store" into a WooCommerce sync). `SKILL.md` §2 + `references/product-creation-pipeline.md` gain a prominent "map ≠ publish" callout. Phase 5 now says read the garment's REAL colors/sizes from `get_garment_details` — never hard-code `S/M/L/XL/2XL` (one-size caps/beanies/accessories otherwise resolve to 0 variants). Phase 3 stresses a finished product must show a garment mockup, not the raw design. Recommends `ship_product` for automated/scheduled runs (one call, correct order) and adds the MCP-tool→phase mapping (`sync_to_fulfillment` = map-to-store; `sync_to_channel` = opt-in Phase 8). `references/error-handling.md` gains `product not associated with store`, `0 variants added (wrong sizes)`, and a `generate_mockup` no-op note. Pairs with `apparelhub-mcp` v0.3.1. Docs only — no script, settings, or installer changes. |
| 2.11 | 2026-07-08 | **Post-sale fulfillment issues (apparelhub-ai epic #510).** New `references/fulfillment-issues.md` documents the issue-reporting loop: report a defect on an order (`POST /agents/v1/orders/{uuid}/issues` with category/items/resolution), attach evidence (direct multipart up to 4MB or the presigned initiate/complete flow; 5 files max, one video, mirroring provider limits), get the provider-ready problem-report summary + dashboard deep-link (`GET .../provider-report`), mark it filed with the claim reference (`POST .../submit-upstream`), track and resolve (`POST .../resolve`), and create a zero-charge replacement order (`POST .../replacement-order` with structured `recipient_unavailable`/`variant_unlinked` failures). Teaches the three facts agents must relay: providers accept problem reports ONLY in their own dashboards, the window is 30 days FROM DELIVERY (`eligibility.days_remaining`), and change-of-mind (size/color preference) is not claim-eligible. Printful refunds auto-resolve filed issues; Printify resolves manually. `SKILL.md` (§3 decision tree) references it. Docs only — no script, settings, or installer changes. |
| 2.10 | 2026-07-08 | **Analytics endpoints (apparelhub-ai epic #387).** New `references/analytics.md` documents the six read-only `/agents/v1/analytics/*` endpoints so an agent can pull metrics programmatically: `summary` (KPIs + prior-period deltas), `timeseries` (day/week/month), `breakdown` (`dimension` = product_type/sales_channel/fulfillment_provider/product/variant/hold_reason), `ops` (velocity + hold/cancel/refund rates), `export` (CSV, `report` = summary/timeseries/breakdown/ops/orders), and `portfolio` (per-client/per-workspace roll-up, agency-Enterprise only). Teaches the three semantics agents miss: the `advanced_analytics` tier gate (`403 feature_unavailable`, Professional+; `portfolio` additionally `403`s `client_portfolio` for non-agency accounts), currencies segmented never summed (read `currency` + `currencies_present`), and margins only over cost-known orders (`margin_coverage`). Shared params `start`/`end`/`store`/`currency`/`?workspace=`. `SKILL.md` (§3 decision tree) and `references/api-contract.md` (§4 catalog) reference it. Full schemas in the served OpenAPI spec (Analytics tag). Docs only — no script, settings, or installer changes. |
| 2.9 | 2026-06-30 | **Multi-workspace key scope (apparelhub-ai#447).** An Agent API key can now be scoped to one OR MORE workspaces (each with a role), so the `GET /agents/v1/workspaces` `key_scope` field changed shape: it is now `{pinned, workspaces:[{workspace_uuid, role}]}` (was `{pinned, workspace_uuid, role}`). For a scoped key, `key_scope.workspaces` lists exactly the workspaces it can act in, each with the key's role; `?workspace=` works for any of them and rejects the rest with `403 workspace_forbidden`. Account-wide keys are unchanged (`pinned:false`, empty `workspaces`). `references/workspaces.md` (§2 + §5), `SKILL.md` (§6), `references/api-contract.md` (§4b), and `references/error-handling.md` updated. Docs only — no script, settings, or installer changes. |
| 2.8 | 2026-06-30 | **Workspace discovery route (epic apparelhub-ai#416) + example scrub.** Documents the new `GET /agents/v1/workspaces` route — the piece v2.6 was missing. v2.6 told the agent "there's no agent endpoint that lists an account's workspaces," so an agent asked to scope to a workspace by name had no way to resolve the name to a `uuid` and choked. Now `GET /agents/v1/workspaces` returns `{workspaces:[{uuid,name,is_default}], active_workspace, key_scope}`; the agent matches the user's name to a `uuid`, then scopes with `?workspace=<uuid>`. A workspace-pinned key lists only its own workspace. `references/workspaces.md` (§2) now leads with the discovery route, and `SKILL.md` (§6) + `references/api-contract.md` (§4b) reference it. Also scrubbed every example and doc of real account-specific values (provider UUIDs, store URLs, workspace/client names) in favor of generic placeholders. Docs only — no script, settings, or installer changes. |
| 2.7 | 2026-06-30 | **Agent 402 account-suspended contract (epic apparelhub-ai#425).** `references/error-handling.md` documents the read-only-suspension 402: a new status-table row + a dedicated "Account suspended (402)" section. When an account's invite-only trial expires with no card on file, the account goes read-only — reads still succeed but writes / quota / sync return `402 {error:"account_suspended", reason:"trial_expired", tier, message, billing_url}`. The agent can't pay; it should stop the write (don't retry), tell the account OWNER to add a payment method at the `billing_url`, and note that everything is safe and held storefront orders auto-release on conversion. Docs only — no script, settings, or installer changes. |
| 2.6 | 2026-06-30 | **Workspace scoping docs (enterprise accounts).** New `references/workspaces.md` plus a `SKILL.md` "Workspaces" section, for issue #25: on Enterprise / agency accounts every Agent API call acts within one **active workspace**. With no param it's the **Default** workspace; `?workspace=<uuid>` targets a specific one (unknown uuid → `404 workspace_not_found`, real-but-inaccessible → `403 workspace_forbidden`). Products and generated images carry a `workspaces` array, stores carry `workspace_uuid` / `workspace_name` (Model A visibility), and workspace-scoped API keys pin a workspace + role (a role lacking `design.generate` gets `403 forbidden` on image gen). The point: an agent on an enterprise account knows how to target a workspace and won't misread a workspace-scoped list as "missing data." `api-contract.md` (§4b + status table) and `error-handling.md` (§2b) gain the `?workspace=` param and the two error codes. Docs only — no script, settings, or installer changes. Refs apparelhub-ai#410, #377. |
| 2.5 | 2026-06-23 | **Async image-gen polling + security nits.** New `ah_poll_generation` script + docs (issue #20): `POST /images/generate` returns **202 + `image_uuid`** for slow models (the Nano Banana default, Seedream 4.0/4.5, Flux 2 Pro, Google Imagen 4, Wan 2.7, GPT Image 2), so the agent must poll `GET /images/upload/<uuid>/status` until `processing_status` is completed (read `url`) or failed (read `error`). Fast models (OpenAI, Grok Imagine, Flux 1.1 Pro) still return 200 + url. Security hardening (issue #17): `ah_check` now feeds the API key through a curl stdin config instead of `-H`, so the key stays out of process argv (SKILL.md documents the same pattern for shared machines); removed the broad `Bash(python3 /tmp/*)` grant from `settings.recommended.json` (`make_transparent.py` keeps its own scoped grant); raw object-storage hostnames swapped to `https://cdn.apparelhub.ai` in the porting guide and the curl allowlist. **Migration:** if you previously merged `settings.recommended.json`, remove the `Bash(python3 /tmp/*)` line, add the two `ah_poll_generation` grants, and replace the `*.s3.amazonaws.com` curl patterns with the `cdn.apparelhub.ai` ones. |
| 2.4 | 2026-06-23 | **Multi-channel repositioning + reconcile docs.** The descriptor and identity lines (README, `SKILL.md` frontmatter + intro, `BOOTSTRAP-PROMPT.md`) now describe ApparelHub as a multi-channel ecommerce platform for custom merchandise instead of a print-on-demand platform. Channel lists (Shopify/Etsy/WooCommerce/Wix) and the Printful/Printify fulfillment copy are unchanged. Plus `references/orders-and-fulfillment.md` gains section 11: how an agent reconciles a sales-channel order's payment, refund, cancellation, and fulfillment status with the channel (epic apparelhub-ai#309 Phase 5). |
| 2.3 | 2026-06-18 | **Printify embroidery.** `references/embroidery.md` gains a full PRINTIFY EMBROIDERY section (P1-P8). The 15-thread palette is identical hex to Printful (Madeira codes added), but Printify auto-digitizes so you send NO thread colors (unlike Printful's `thread_colors_*` options); 6-color cap; up to 36h post-order digitization; embroidery area sizes; the negative-space-fill and outline-for-solid-backgrounds rules; pre-digitized Embroidery Ready Fonts. Plus the dual-decoration mockup limitation: on a blueprint whose provider does embroidery and DTF, Printify generates ONLY the embroidery mockup scene, so a DTF crest prints correctly but cannot be previewed (verified, and reproduced in Printify's own designer). |
| 2.2 | 2026-06-17 | **Agent order management.** `references/orders-and-fulfillment.md` gains sections 8-10 plus a new `examples/order-management.md`: the per-store fulfillment workflow (auto / confirm / review), approval authority (you / your AI agent / smart rules), smart guardrails (high-value, low-margin, negative-margin), the agent approval queue (`GET /agents/v1/orders?requires_approval=true`), the two distinct holds (ApparelHub approval vs Printful design), and the opt-in HMAC-signed `order.awaiting_approval` callback. |
| 2.1 | 2026-06-11 | Docs reference the branded `cdn.apparelhub.ai` host instead of the raw object-storage URL, matching the platform cutover. Worked-example response shapes and verification `curl`s now show CDN URLs (both forms serve the same bytes). |
| 2.0 | 2026-06-06 | **Platform-neutral, security-first re-architecture.** `ah_curl` deleted (forwarded keys to arbitrary URLs). `APPARELHUB_API_BASE` removed from user path; canonical host hard-pinned in every helper. Installer no longer persists the API key to disk or edits shell rc by default (opt in with `--persist`). New top-level `SECURITY.md` documents trust model + non-goals + threat model, enforced by CI grep. New `apparelhub/references/api-contract.md` makes the HTTP contract consumable by bare-HTTP agents. New `porting-guides/` directory ships per-platform walkthroughs for bare-HTTP, Claude Code, and ChatGPT/Gemini tool-calling. Claude-Code-specific bits moved to a `claude-code/` overlay. All "exists to suppress the permission prompt" framing removed from scripts and docs; see SECURITY.md §2a. |
| 1.16 | 2026-06-05 | Rebrand bridge → harness, drop Docker mentions, strip em-dashes from all public-facing surfaces. |
| 1.15 | 2026-06-05 | End-to-end environment selection via `APPARELHUB_API_BASE` (removed in v2.0). |
| 1.14 | 2026-06-05 | Bridge install prompt rewritten to be self-contained. |
| 1.13 | 2026-06-05 | Multi-harness install support; universal bootstrap prompt for non-Claude-Code agents. |
| 1.12 | 2026-06-04 | Initial public skill funnel release (epic-agent-onboarding). |
| 1.11 and earlier | — | See GitHub Releases page for full history. |

---

## Contributing

Bug reports and PRs welcome at <https://github.com/ApparelHub-AI/apparelhub-skills/issues>.
Security issues go to `security@apparelhub.ai` per [`SECURITY.md`](./SECURITY.md) §4.

The acceptance playbook in [`acceptance/playbook.md`](./acceptance/playbook.md)
is run before every release tag. The CI workflow in
[`.github/workflows/forbidden-patterns.yml`](./.github/workflows/forbidden-patterns.yml)
guards against v1.x antipatterns reappearing.

---

## License

This project is licensed under the [MIT License](./LICENSE).
