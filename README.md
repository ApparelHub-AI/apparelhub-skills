# ApparelHub Skills

Claude Code skills for [ApparelHub.ai](https://apparelhub.ai) — the print-on-demand design and orchestration platform. Drop these into your Claude Code skills directory to let Claude design AI-generated apparel, generate product mockups, create products, and sync them to your sales channels via the ApparelHub Agent API.

---

## What's in this repo

The `apparelhub/` skill uses the parent SKILL + lazy-loaded references pattern. The entry-point `SKILL.md` is a lean router (~150 lines) that loads detailed playbooks from `references/` and `examples/` on demand:

```
apparelhub/
├── SKILL.md                                  # Router — loaded on every invocation
├── references/
│   ├── product-creation-pipeline.md          # 7-phase workflow detail
│   ├── design-rules.md                       # AI prompts, transparency, vision verify
│   ├── embroidery.md                         # Thread palette + sync payload shape
│   ├── all-over-print.md                     # Pillows, doormats, luggage tags
│   ├── garment-catalog.md                    # Variant IDs, pricing floors
│   ├── orders-and-fulfillment.md             # Order data + payment authority
│   └── error-handling.md                     # 4xx/5xx semantics + silent failures
└── examples/
    ├── front-print-tee.md                    # Bella+Canvas 3001 end-to-end
    ├── all-over-pillow.md                    # 18×18 pillow end-to-end
    └── embroidered-anorak.md                 # Champion Anorak chest crest end-to-end
```

Claude reads `SKILL.md` whenever the user asks about ApparelHub workflows, then opens the relevant `references/` or `examples/` file as needed. Tokens only get spent on the context you actually need.

---

## Install

Claude Code looks for skills under `~/.claude/skills/<name>/SKILL.md`. Clone or copy the skill directory there:

```bash
# Clone the repo somewhere
git clone https://github.com/ApparelHub-AI/apparelhub-skills.git ~/code/apparelhub-skills

# Symlink (or copy) the apparelhub skill into your Claude Code skills dir
mkdir -p ~/.claude/skills
ln -s ~/code/apparelhub-skills/apparelhub ~/.claude/skills/apparelhub
```

Restart Claude Code; the skill is available next session.

---

## Prerequisites

You need an ApparelHub API key (Professional or Enterprise tier). Generate one at <https://apparelhub.ai/developer/api-keys>, then:

```bash
export APPARELHUB_API_KEY=ah_...
```

The skill checks for `APPARELHUB_API_KEY` before any API call and prompts you if it's missing.

---

## API surface

The skill talks to ApparelHub's Agent API:

- Production: `https://api.apparelhub.ai/agents/v1/`
- OpenAPI spec (authed): `https://api.apparelhub.ai/agents/v1/openapi.json`
- Browser docs: <https://apparelhub.ai/developer/api-docs>

---

## What the skill covers

- AI-generated apparel design (Nano Banana, Seedream 4.0/4.5, Flux 1.1 Pro, OpenAI, Google Imagen 4)
- Local transparency processing (Pillow flood-fill + pre-multiply white)
- Mockup generation via Printful + Printify
- Product creation, variant management, store association
- Sales channel sync (Shopify, Etsy, WooCommerce, Wix)
- Order lookups + payment status + fulfillment tracking
- Embroidered apparel (Champion Anorak, polos, embroidered hats) — including the 15-color thread palette and the `thread_colors_<placement>` sync payload trap
- All-over print products (pillows, doormats, area rugs, luggage tags)
- Pricing floors per garment

---

## Versioning

| Version | Date | Highlights |
|---|---|---|
| 1.2 | 2026-06-01 | Restructured to parent + references pattern. Added embroidery, all-over print, payment authority, error handling, AI prompt anti-patterns. Three full end-to-end examples. Fixed OpenAPI spec URL. |
| 1.1 | 2026-05-29 | Test-driven fixes from the 2026-05-22 validation cycle (six bugs caught in Test 2 of the multi-step product creation flow). |
| 1.0 | 2026-05-21 | Initial publish. |

---

## Repo

<https://github.com/ApparelHub-AI/apparelhub-skills>
