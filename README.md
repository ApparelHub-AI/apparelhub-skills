# ApparelHub Skills

Claude Code skills for [ApparelHub.ai](https://apparelhub.ai) — the print-on-demand design and orchestration platform. Drop these into your Claude Code skills directory to let Claude design AI-generated apparel, generate product mockups, create products, and sync them to your sales channels via the ApparelHub Agent API.

---

## Skills in this repo

| Skill | Path | What it does |
|-------|------|--------------|
| `apparelhub` | [`apparelhub/SKILL.md`](apparelhub/SKILL.md) | End-to-end POD design workflow: prompt → AI image → local transparency processing → mockup → product create → store sync. Covers Printful + Printify fulfillment, Shopify / WooCommerce / Wix / Etsy sales channels. |

---

## Install

Claude Code looks for skills under `~/.claude/skills/<name>/SKILL.md`. Clone or copy each skill directory in there:

```bash
# Clone the whole repo somewhere
git clone https://github.com/ApparelHub-AI/apparelhub-skills.git ~/code/apparelhub-skills

# Symlink (or copy) each skill into your Claude Code skills dir
mkdir -p ~/.claude/skills
ln -s ~/code/apparelhub-skills/apparelhub ~/.claude/skills/apparelhub
```

Restart Claude Code; the skill is available the next session.

---

## Prerequisites

The `apparelhub` skill needs an ApparelHub API key (Professional or Enterprise tier). Generate one at <https://apparelhub.ai/developer/api-keys>, then:

```bash
export APPARELHUB_API_KEY=ah_...
```

The skill checks for `APPARELHUB_API_KEY` before any API call and prompts you if it's missing.

---

## API surface

The skill talks to ApparelHub's Agent API:

- Production: `https://api.apparelhub.ai/agents/v1/`
- OpenAPI docs: <https://apparelhub.ai/developer/api-docs>

---

## Versioning

Skills are versioned via this repo's git history. The current `apparelhub` skill is at v1.1 (test-driven fixes from the 2026-05-22 validation cycle).

---

## Repo

<https://github.com/ApparelHub-AI/apparelhub-skills>
