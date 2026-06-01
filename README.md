# ApparelHub Skills

Claude Code skills for [ApparelHub.ai](https://apparelhub.ai) — the print-on-demand design and orchestration platform. Drop these into your Claude Code skills directory to let Claude design AI-generated apparel, generate product mockups, create products, and sync them to your sales channels via the ApparelHub Agent API.

---

## What's in this repo

The `apparelhub/` skill uses the parent SKILL + lazy-loaded references pattern. The entry-point `SKILL.md` is a lean router (~150 lines) that loads detailed playbooks from `references/` and `examples/` on demand:

```
apparelhub-skills/
├── settings.recommended.json                 # Permission allowlist to merge into ~/.claude/settings.json
└── apparelhub/
    ├── SKILL.md                              # Router — loaded on every invocation
    ├── scripts/
    │   ├── ah_curl                           # Agent API wrapper — hides $APPARELHUB_API_KEY from command line
    │   └── make_transparent.py               # Phase 2 keying tool (auto-chroma, enclosed sweep, despill)
    ├── references/
    │   ├── product-creation-pipeline.md      # 7-phase workflow detail
    │   ├── design-rules.md                   # AI prompts, transparency, vision verify
    │   ├── embroidery.md                     # Thread palette + sync payload shape
    │   ├── all-over-print.md                 # Pillows, doormats, luggage tags
    │   ├── garment-catalog.md                # Variant IDs, pricing floors
    │   ├── orders-and-fulfillment.md         # Order data + payment authority
    │   └── error-handling.md                 # 4xx/5xx semantics + silent failures
    └── examples/
        ├── front-print-tee.md                # Bella+Canvas 3001 end-to-end
        ├── all-over-pillow.md                # 18×18 pillow end-to-end
        └── embroidered-anorak.md             # Champion Anorak chest crest end-to-end
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

# Optional but recommended: add the scripts dir to your PATH so the agent
# can invoke `ah_curl` and `make_transparent.py` by bare name. This is the
# cleanest match for the allowlist patterns in settings.recommended.json.
echo 'export PATH="$HOME/.claude/skills/apparelhub/scripts:$PATH"' >> ~/.zshrc  # or .bashrc
```

Restart Claude Code; the skill is available next session.

---

## Reducing permission prompts (recommended)

By default Claude Code asks for confirmation before every `curl`, `python3`, and `jq` invocation the skill makes — which adds up fast across the 7-phase product-creation pipeline. Crucially, **Claude Code also prompts on any command containing shell expansion (`$VAR`, `${VAR}`, `$(...)`) regardless of how broad your allowlist is.** v1.4 of this skill ships an `ah_curl` wrapper that hides `$APPARELHUB_API_KEY` INSIDE the script so the agent's command line stays expansion-free. The recommended settings allowlist BOTH the wrapper invocation and a few fallback raw-curl patterns:

```json
{
  "permissions": {
    "allow": [
      "Bash(ah_curl GET *)",
      "Bash(ah_curl POST *)",
      "Bash(ah_curl PATCH *)",
      "Bash(ah_curl PUT *)",
      "Bash(ah_curl DELETE *)",
      "Bash(*apparelhub/scripts/ah_curl GET *)",
      "Bash(*apparelhub/scripts/ah_curl POST *)",
      "Bash(*apparelhub/scripts/ah_curl PATCH *)",
      "Bash(*apparelhub/scripts/ah_curl PUT *)",
      "Bash(*apparelhub/scripts/ah_curl DELETE *)",
      "Bash(curl -sS https://api.apparelhub.ai/agents/v1/*)",
      "Bash(curl -sS -X POST https://api.apparelhub.ai/agents/v1/*)",
      "Bash(curl -sS -X PATCH https://api.apparelhub.ai/agents/v1/*)",
      "Bash(curl -sS -X PUT https://api.apparelhub.ai/agents/v1/*)",
      "Bash(curl -sS -X DELETE https://api.apparelhub.ai/agents/v1/*)",
      "Bash(curl -sS https://apparelhub-production-user-generated-public-objects.s3.amazonaws.com/*)",
      "Bash(curl -sS -o /tmp/* https://apparelhub-production-user-generated-public-objects.s3.amazonaws.com/*)",
      "Bash(jq:*)",
      "Bash(python3 *apparelhub/scripts/make_transparent.py *)",
      "Bash(python3 /tmp/*)",
      "Bash(getent hosts *)"
    ]
  }
}
```

The first two pattern groups match `ah_curl` invocations either bare (if you added the scripts dir to PATH per the Install section) or via a full path ending in `apparelhub/scripts/ah_curl`. The raw `curl` patterns are kept as a fallback for cases where the agent decides to fetch the OpenAPI spec or hit an endpoint directly with literal values.

**Merge it into your `~/.claude/settings.json`:**

- If the file doesn't exist yet: `cp ~/code/apparelhub-skills/settings.recommended.json ~/.claude/settings.json`
- If it does exist: copy the entries above into your existing `permissions.allow` array. Each entry is a Claude Code Bash glob pattern — anything matching is auto-approved; anything not matching still prompts.

What the scope intentionally does NOT include:
- Bare `Bash(curl:*)` — would allow exfiltration to arbitrary URLs
- Bare `Bash(python3:*)` — only allows running the packaged `make_transparent.py` by path OR scripts under `/tmp/`
- Any `rm`, `mv`, or write outside `/tmp/` — destructive ops still require explicit approval

Restart Claude Code after editing settings; the changes apply on the next session.

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

- Prompt-free Agent API access via the packaged `scripts/ah_curl` wrapper (hides `$APPARELHUB_API_KEY` so Claude Code's expansion check doesn't fire)
- AI-generated apparel design (Nano Banana, Seedream 4.0/4.5, Flux 1.1 Pro, OpenAI, Google Imagen 4)
- Local transparency processing via the packaged `scripts/make_transparent.py` (auto chroma detect, enclosed-region sweep for letter holes, optional `--despill` and `--dominance` modes, pre-multiplied white)
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
| 1.4 | 2026-06-01 | Packaged `scripts/ah_curl` Agent API wrapper — hides `$APPARELHUB_API_KEY` from the command line so Claude Code's `simple_expansion` check stops prompting on every call. Rewrites SKILL.md auth section + all 7 references + all 3 examples to invoke `ah_curl METHOD PATH` with literal-value substitution (no shell variables for captured UUIDs). `settings.recommended.json` extended with `ah_curl` patterns. New PATH setup step in Install. |
| 1.3 | 2026-06-01 | Packaged `scripts/make_transparent.py` keying tool (replaces inline Pillow snippets). `settings.recommended.json` for permission-prompt reduction. Phase 2 reference + design rules updated to invoke the script by path. Auto chroma detection for AI-generated greens that aren't exactly `#00FF00`. |
| 1.2 | 2026-06-01 | Restructured to parent + references pattern. Added embroidery, all-over print, payment authority, error handling, AI prompt anti-patterns. Three full end-to-end examples. Fixed OpenAPI spec URL. |
| 1.1 | 2026-05-29 | Test-driven fixes from the 2026-05-22 validation cycle (six bugs caught in Test 2 of the multi-step product creation flow). |
| 1.0 | 2026-05-21 | Initial publish. |

---

## Repo

<https://github.com/ApparelHub-AI/apparelhub-skills>
