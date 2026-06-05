# ApparelHub Skills

Make [ApparelHub.ai](https://apparelhub.ai) agent-controllable from [Claude Code](https://docs.claude.com/en/docs/claude-code). This repo packages a Claude Code skill that lets your agent design AI-generated apparel, generate product mockups, create products, manage variants, sync to sales channels, and track orders, all via the ApparelHub Agent API.

**Who this is for**

- Claude Code users who want to run a print-on-demand business from their terminal
- Users on a custom Claude harness (e.g. OpenClaw, Cline, Aider) who want first-class access to ApparelHub's product, mockup, store, and order endpoints
- Users of Claude Web, ChatGPT, Codex, Gemini, or any other AI agent. See [`apparelhub/BOOTSTRAP-PROMPT.md`](./apparelhub/BOOTSTRAP-PROMPT.md) for the universal copy-paste system prompt
- Anyone with an ApparelHub account on the Professional or Enterprise tier

**Quick links**

- Full setup walkthrough: <https://apparelhub.ai/agents>
- Browser API reference: <https://apparelhub.ai/developer/api-docs>
- Generate an API key: <https://apparelhub.ai/developer/api-keys>

---

## What's in this repo

The `apparelhub/` skill uses the parent SKILL + lazy-loaded references pattern. The entry-point `SKILL.md` is a lean router (~150 lines) that loads detailed playbooks from `references/` and `examples/` on demand:

```
apparelhub-skills/
├── settings.recommended.json                 # Permission allowlist to merge into ~/.claude/settings.json
└── apparelhub/
    ├── SKILL.md                              # Router, loaded on every invocation
    ├── scripts/
    │   ├── ah_check                          # Auth precondition: verify key is set + valid (run first each session)
    │   ├── ah_curl                           # Agent API wrapper: hides $APPARELHUB_API_KEY from command line
    │   ├── ah_poll_mockup                    # Phase 3 wait: polls job + S3 ingestion in one call (no for-loop expansion)
    │   ├── ah_classify_previews              # Phase 4.0: parses preview rows by color/angle, writes display+gallery picks
    │   ├── ah_pick_provider_url              # Extract one URL by color+angle from a preview JSON (no jq filter needed)
    │   ├── ah_pick_dimensions                # Phase 3 sizing: compute (width,height,left,top) from design aspect + area
    │   ├── install_path.sh                   # One-time PATH setup (detects bash/zsh/fish, idempotent)
    │   └── make_transparent.py               # Phase 2 keying tool (auto-chroma, enclosed sweep, despill, auto-crop, chroma sanity check)
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

### One-line installer (recommended)

```bash
curl -fsSL https://apparelhub.ai/install-skill.sh | bash
```

The installer:

1. Clones this repo to `~/.apparelhub-skills`
2. Symlinks it into `~/.claude/skills/apparelhub`
3. Adds the scripts dir to your shell PATH (bash, zsh, fish)
4. Prompts for your ApparelHub API key and stores it in `~/.apparelhub-skills/.env` (chmod 600), then sources it from your shell rc file
5. Runs `ah_check` to verify the key works against the platform

It's idempotent. Re-run it any time to pull the latest skill version and re-verify your key. Inspect it before piping to bash if you'd like:

```bash
curl -fsSL https://apparelhub.ai/install-skill.sh | less
```

If your key is already in env, the script won't prompt:

```bash
APPARELHUB_API_KEY=<your-key> bash -c "$(curl -fsSL https://apparelhub.ai/install-skill.sh)"
```

Open a new terminal (or `source` your rc file) and Claude Code can use the skill on its next session.

### Targeting a non-prod environment

By default `install.sh` and every packaged script (`ah_check`, `ah_curl`, `ah_poll_mockup`) talks to the production Agent API at `https://api.apparelhub.ai`. To install against a different environment (e.g. internal testing on the dev stack), set `APPARELHUB_API_BASE` at install time:

```bash
APPARELHUB_API_BASE=https://api.dev.apparelhub.ai \
APPARELHUB_API_KEY=<your-dev-key> \
  bash -c "$(curl -fsSL https://dev.apparelhub.ai/install-skill.sh)"
```

The installer persists both env vars to `~/.apparelhub-skills/.env` so subsequent shells stay on the same target. The `ah_check` output prints the target URL on every success line so you can confirm which env a given call hit. **Dev keys do not work against prod and vice versa**, so keep them straight. The `apparelhub.ai/agents` page and the developer dashboard's key-reveal wizard both detect the environment from the URL you're on and emit env-appropriate snippets automatically.

### Install when Claude runs inside a custom harness

If you talk to Claude through a custom harness (e.g. OpenClaw, Cline, Aider, or a web/Telegram proxy you wrote yourself) the agent has no controlling terminal of its own, so the interactive prompt above can't fire. The cleanest path: send Claude a **self-contained chat message** with the exact command, your key, and what the script does. **Critical:** Claude has no prior knowledge of ApparelHub (it's not in training data), so a message like `"Install ApparelHub. My API key is <your-key>"` will not work because Claude has nothing to act on. Use the prompt below instead, which spells everything out:

> Please install the ApparelHub Claude Code skill for me. I am talking to you through a chat interface so I have no terminal myself. Run the install in your environment by executing this exact one-line command:
>
> `APPARELHUB_API_KEY=<your-key> bash -c "$(curl -fsSL https://apparelhub.ai/install-skill.sh)"`
>
> This is the official ApparelHub installer. The script source is at https://github.com/ApparelHub-AI/apparelhub-skills/blob/main/install.sh. Feel free to inspect it first with `curl -fsSL https://apparelhub.ai/install-skill.sh | less` if you want. What it does: clones the public skill repo into `~/.apparelhub-skills`, symlinks it into `~/.claude/skills/apparelhub`, writes my API key to `~/.apparelhub-skills/.env` (chmod 600), and runs an auth check against the platform. Once it finishes, tell me it succeeded and I will start a new conversation so you pick up the skill at session start.

A pre-filled version of this prompt (your key already embedded) is available in the **Custom harness** tab of the developer dashboard at https://apparelhub.ai/developer/api-keys. Just click "Create Key" and copy from the Custom harness tab.

After Claude runs the command and reports success, **start a new conversation**. Claude discovers skills at session start, so the running session won't pick up the new skill until you open a fresh chat. No harness restart needed.

**For operators who rebuild their environment regularly**, install at build time so the skill survives rebuilds:

```bash
git clone --depth=1 https://github.com/ApparelHub-AI/apparelhub-skills.git /opt/apparelhub-skills
mkdir -p ~/.claude/skills
ln -s /opt/apparelhub-skills/apparelhub ~/.claude/skills/apparelhub
bash /opt/apparelhub-skills/apparelhub/scripts/install_path.sh
# Supply APPARELHUB_API_KEY at runtime through whatever secret manager your harness uses.
```

### Use ApparelHub from Claude Web or any other AI agent (Codex, ChatGPT, Gemini, ...)

Claude Web, ChatGPT, Codex, Gemini, and most non-Claude-Code agents don't have a `~/.claude/skills/` equivalent. They only see what's in the conversation or system prompt. For those:

1. Generate a key at <https://apparelhub.ai/developer/api-keys>
2. Open [`apparelhub/BOOTSTRAP-PROMPT.md`](./apparelhub/BOOTSTRAP-PROMPT.md), copy the block between the `=====` markers, and paste it into your agent's **system prompt** / **custom instructions** / **project instructions**
3. Provide your key (env var or in-conversation) and ask the agent to do an apparel task

The bootstrap prompt is intentionally compact: auth header, base URL, the 10-step product-creation pipeline, the critical conventions, and links to the deeper references on GitHub. Enough to drive the platform without the packaged helper scripts.

### Manual install

If you'd rather wire it up by hand:

```bash
# 1. Clone the repo
git clone https://github.com/ApparelHub-AI/apparelhub-skills.git ~/.apparelhub-skills

# 2. Symlink the skill into Claude Code's skills dir
mkdir -p ~/.claude/skills
ln -s ~/.apparelhub-skills/apparelhub ~/.claude/skills/apparelhub

# 3. Put the scripts dir on PATH (idempotent; detects bash / zsh / fish)
bash ~/.claude/skills/apparelhub/scripts/install_path.sh

# 4. Set + persist your API key
export APPARELHUB_API_KEY=ah_...   # generate at apparelhub.ai/developer/api-keys
echo "export APPARELHUB_API_KEY=$APPARELHUB_API_KEY" >> ~/.bashrc   # or ~/.zshrc

# 5. Verify
~/.claude/skills/apparelhub/scripts/ah_check
```

Restart Claude Code; the skill is available next session.

---

## Reducing permission prompts (recommended)

By default Claude Code asks for confirmation before every `curl`, `python3`, and `jq` invocation the skill makes, which adds up fast across the 7-phase product-creation pipeline. Crucially, **Claude Code also prompts on any command containing shell expansion (`$VAR`, `${VAR}`, `$(...)`) regardless of how broad your allowlist is.** v1.4 of this skill ships an `ah_curl` wrapper that hides `$APPARELHUB_API_KEY` INSIDE the script so the agent's command line stays expansion-free. The recommended settings allowlist BOTH the wrapper invocation and a few fallback raw-curl patterns:

```json
{
  "permissions": {
    "allow": [
      "Bash(ah_check)",
      "Bash(*apparelhub/scripts/ah_check)",
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
      "Bash(ah_poll_mockup *)",
      "Bash(*apparelhub/scripts/ah_poll_mockup *)",
      "Bash(ah_classify_previews *)",
      "Bash(*apparelhub/scripts/ah_classify_previews *)",
      "Bash(ah_pick_provider_url *)",
      "Bash(*apparelhub/scripts/ah_pick_provider_url *)",
      "Bash(ah_pick_dimensions *)",
      "Bash(*apparelhub/scripts/ah_pick_dimensions *)",
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
- If it does exist: copy the entries above into your existing `permissions.allow` array. Each entry is a Claude Code Bash glob pattern: anything matching is auto-approved, anything not matching still prompts.

What the scope intentionally does NOT include:
- Bare `Bash(curl:*)`, which would allow exfiltration to arbitrary URLs
- Bare `Bash(python3:*)`. The allowlist only allows running the packaged `make_transparent.py` by path OR scripts under `/tmp/`
- Any `rm`, `mv`, or write outside `/tmp/`. Destructive ops still require explicit approval

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

- Prompt-free Agent API access via `scripts/ah_check` (start-of-session auth probe) + `scripts/ah_curl` (per-call wrapper). Both hide `$APPARELHUB_API_KEY` so Claude Code's expansion check doesn't fire
- One-time PATH setup via `scripts/install_path.sh` (detects bash / zsh / fish, idempotent)
- AI-generated apparel design (Nano Banana, Seedream 4.0/4.5, Flux 1.1 Pro, OpenAI, Google Imagen 4)
- Local transparency processing via the packaged `scripts/make_transparent.py` (auto chroma detect, enclosed-region sweep for letter holes, optional `--despill` and `--dominance` modes, pre-multiplied white)
- Mockup generation via Printful + Printify
- Product creation, variant management, store association
- Sales channel sync (Shopify, Etsy, WooCommerce, Wix)
- Order lookups + payment status + fulfillment tracking
- Embroidered apparel (Champion Anorak, polos, embroidered hats), including the 15-color thread palette and the `thread_colors_<placement>` sync payload trap
- All-over print products (pillows, doormats, area rugs, luggage tags)
- Pricing floors per garment

---

## Versioning

| Version | Date | Highlights |
|---|---|---|
| 1.16 | 2026-06-05 | Public-content hygiene pass. The "harness" framing on `apparelhub.ai/agents`, in the developer-key wizard, and across the install scripts was previously named after `claude-bridge` (an internal-only project) and tied to a specific container runtime. Both are off-message: the compute layer running the agent has no bearing on the install, and the named example was not a public product. The tab and all related copy are now **Custom harness**, with concrete examples drawn from public harnesses: OpenClaw, Cline, Aider. The container-specific operator snippet was replaced with a generic shell snippet that works for any build pipeline. Stripped em-dashes from `install.sh`, README, SKILL.md, BOOTSTRAP-PROMPT.md, the packaged scripts, and the entire `/agents` page + key wizard to comply with the marketing rule against em-dash overuse in public copy. Variable rename: `bridgeChatMessage` → `harnessChatMessage` in the wizard for consistency. No behavior change in any packaged script; this is pure documentation, prompt copy, and tab labels. |
| 1.15 | 2026-06-05 | **End-to-end environment selection via `APPARELHUB_API_BASE`**. v1.14 and prior hard-coded `https://api.apparelhub.ai` in every packaged script. A user installing against the dev stack would correctly get a dev key, point the install snippet at dev, then have `ah_check` (and every subsequent `ah_curl` / `ah_poll_mockup`) hit prod and 401. v1.15 makes every script honor `APPARELHUB_API_BASE` (default `https://api.apparelhub.ai`). `install.sh` reads it, persists both `APPARELHUB_API_KEY` AND `APPARELHUB_API_BASE` to `~/.apparelhub-skills/.env`, exports both before the trailing `ah_check`, and uses the derived front-end host (apparelhub.ai vs dev.apparelhub.ai) in every printed URL. `ah_check` output now includes the target URL on the success line and the 401/403 branch tells the user to verify the key was generated for THIS environment. `ah_curl`'s `PATH_OR_URL` resolver prefixes with `$APPARELHUB_API_BASE` instead of a hardcoded value. `ah_poll_mockup` does the same in its Python. No external API change, no UI change in this repo (UI changes ship in the matching apparelhub-ui commit). Pairs with: documentation updates in SKILL.md ("Environment targeting" section) + README ("Targeting a non-prod environment" section). Also: replaced stale `ah_xxx` placeholders with neutral `<your-key>` since AWS API Gateway-generated keys don't have an `ah_` prefix, the placeholder shouldn't suggest they do. |
| 1.14 | 2026-06-05 | Bridge install prompt rewritten to be **self-contained**. v1.13's bridge tab on `apparelhub.ai/agents` and the matching tab on the developer dashboard told users to send Claude `"Install ApparelHub. My API key is ah_..."` and let Claude figure out the rest. That doesn't work, Claude has no prior knowledge of ApparelHub (it's not in training data), so the message has nothing for Claude to act on. The fix: the prompt is now a complete instruction in plain English, names the official installer URL (https://apparelhub.ai/install-skill.sh), spells out the one-line command for Claude to execute (`APPARELHUB_API_KEY=ah_xxx bash -c "$(curl -fsSL ...)"`), points at the GitHub source for inspection, describes what the script does (clone, symlink, write `.env` chmod 600, ah_check), and tells Claude what to report when done. Also fixes a stale `\\\"`/`\\\$(...)` shell-escape bug in `install.sh`'s no-TTY fail message that printed literal backslashes instead of plain quotes/dollar signs in the example. Pure documentation + prompt-engineering change; no behavior change in any packaged script. |
| 1.13 | 2026-06-05 | Multi-harness install support and a universal bootstrap prompt for non-Claude-Code agents. `install.sh` now (a) treats a missing `claude` CLI as a soft note instead of a red warning (it's normal for any non-CLI setup where the agent talks to Claude through a different transport), (b) expands the no-TTY failure message to call out headless harness scenarios explicitly with a suggested chat-message form the user can send to their Claude, and (c) rewrites the "Done" message into three paths: Claude Code CLI users get the "open a new terminal" instruction; custom harness users get "start a new conversation, no harness restart needed"; Claude Web / Codex / Gemini users get pointed at the new bootstrap file. New `apparelhub/BOOTSTRAP-PROMPT.md` is a copy-paste system-prompt block for any LLM that ISN'T Claude Code, gives the agent enough scaffolding (auth header, base URL, the 10-step product pipeline, the critical-conventions list, links to the GitHub references for deeper workflows) to drive the Agent API without needing the packaged helper scripts. Pairs with the redesigned `apparelhub.ai/agents` page that now has three install paths (CLI / custom harness / web+other), each capped at 3 steps. |
| 1.12 | 2026-06-04 | New top-level `install.sh` plus a rewritten README lead and Install section. Was: "find the GitHub repo, figure out where to clone, set up the symlink manually, find install_path.sh, set the env var, find ah_check, run it". Five-plus manual steps. Now: `curl -fsSL https://apparelhub.ai/install-skill.sh \| bash`. The installer clones to `~/.apparelhub-skills`, symlinks into `~/.claude/skills/apparelhub`, adds the scripts dir to PATH via the existing `install_path.sh`, prompts for the API key against `/dev/tty` (so it works under `curl ... \| bash` where stdin is the script body), stores the key in `~/.apparelhub-skills/.env` with `chmod 600`, sources it from the right rc file (bash / zsh / fish), and runs `ah_check` as the success gate. Idempotent end-to-end: re-running pulls the latest skill version, leaves existing rc entries alone, and re-verifies the key. README lead now leads with "what is this and who is it for" + links to apparelhub.ai/agents + apparelhub.ai/developer/api-keys + apparelhub.ai/developer/api-docs before any install instructions. Manual install path preserved below the one-liner for users who prefer it. |
| 1.11 | 2026-06-02 | A real Test 2 session caught `ah_poll_mockup` exiting on the first transient HTTP 504 from the job-status endpoint. 504s on that endpoint are EXPECTED during polling, they happen when our Lambda is mid-S3-ingestion (downloading mockups from Printful → uploading to our S3) or when Printful's upstream is slow, and API Gateway times out at 30s. The job is still progressing on the platform side; the agent should just retry. v1.11 treats 502 / 503 / 504 / 429 / `URLError` as transient and continues polling. New `--max-transient-errors` flag (default 5) caps consecutive failures before bailing; the counter resets on any successful poll. Each retry prints `poll N (Ts): transient HTTP 504 (retry M/5, sleeping 8s)` so the agent can see what's happening. Wall-clock `--timeout` still applies during retry loops so a permanently-broken endpoint can't hang forever. Non-transient HTTP errors (400, 401, 403, 404, 500, etc.) still fail fast. |
| 1.10 | 2026-06-02 | Tune the v1.9 collar padding default from 10% (~0.6") to 13% (~0.8") of area_height. After looking at the v1.9 mockup, Tony confirmed that ~0.8" is the right standard chest-print breathing room, what you'd expect on a retail t-shirt. On BC 3001 front (728×376 at 60.7 px/inch), 13% of area_height = 48px = ~0.79". Worked example in docs updated from `width=427, height=339, top=37` to `width=413, height=328, top=48`. The previous default 0.10 is still documented as the "tighter than default" tuning value; new entries 0.05 (~0.3"), 0.10 (~0.6"), 0.13 (default ~0.8"), 0.15 (~0.9"), 0.20 (~1.2") give the merchant a complete reference table. Behavior change: every Phase 3 chest_fill invocation now produces slightly shifted-down + slightly smaller dimensions vs v1.9. |
| 1.9 | 2026-06-02 | One quality polish on top of v1.8: a real Test 2 session showed that v1.8's `chest_fill` style with `top: 0` pushed the design flush against the collar seam (zero breathing room between the printed design and the t-shirt collar). `ah_pick_dimensions` now reserves 10% of `area_height` at the top as collar breathing room by default, tunable with the new `--collar-padding-pct` flag (range `[0, 1.0)`). On BC 3001 front (728×376) this gives ~37px / ~0.6" of space between the collar and the design. The height-constrained branch correctly shrinks the design to fit within `area_height - collar_padding` so nothing overshoots. `back_center` is unaffected (already vertically centered). Worked example in the docs updated from `width=473, height=376, top=0` to `width=427, height=339, top=37`. Two reference tuning values documented: `--collar-padding-pct 0.05` (~0.3" tight) and `0.15` (~0.9" generous). Pass `0.0` to restore v1.8 behavior. |
| 1.8 | 2026-06-02 | Quality regressions surfaced in the second Test 2 cycle: the keying step destroyed the design (yellow sun consumed because the AI used a yellow-green background instead of pure #00FF00) AND the agent picked dimensions that produced too-small chest prints (68.7% of area_width vs the skill's 80-90% guidance). Three fixes: (1) `make_transparent.py` adds a chroma sanity check that REJECTS non-#00FF00 backgrounds (exit code 4 with regen recommendation; bypass with `--force-chroma`), tightens default tolerance from 90 to 45 (yellow design colors no longer fall inside the match window), and auto-crops to the design's tight bounding box (so Phase 3 sizing reflects the actual design extent, not the AI canvas + transparent margin). (2) New `ah_pick_dimensions <design_path> <area_w> <area_h>` script that computes correct `(width, height, left, top)` from the design's actual aspect ratio + the print area + a placement style preset (`chest_fill` default, `chest_emblem`, `back_center`, `all_over`). Codifies the math AND the constraint (never overshoot area_height by default, which would cause Printful to crop at print time). Replaces the soft "80-90% of area_width" guidance that the agent kept undershooting. (3) Phase 1 prompt example strengthened with explicit "NOT yellow-green or olive" guidance. SKILL.md helpers table + product-creation-pipeline.md Phase 2 / Phase 3c / Phase 3d / Phase 4 print_data + front-print-tee.md all updated. |
| 1.7 | 2026-06-01 | Three new packaged scripts kill the remaining inline-bash expansion prompts surfaced during Test 2 validation: `ah_poll_mockup` (collapses Phase 3 job-status poll + Phase 3.5 S3-ingestion poll into one call against the job-status endpoint), `ah_classify_previews` (parses preview rows by color + angle from the provider CDN filename slug; `--recommend` writes a JSON with `display_image` + curated `gallery_images` ready to paste literally into product create), `ah_pick_provider_url` (extracts one URL by color+angle, no jq filter needed). Content fix: removed all references to `GET /merchandise/product/preview-job/<job>/previews`, that listing endpoint returned 0 rows in the field even after preview_url was populated; the job-status endpoint carries the preview rows directly. `settings.recommended.json` extended with the three new patterns. SKILL.md "Other packaged helpers" section added with a one-line rule of thumb: if you're writing more than one shell line for a workflow step, there's probably a packaged script for it. |
| 1.6 | 2026-06-01 | Documents the img2img edit modes on `POST /images/generate`. The endpoint is overloaded, same path for text-to-image AND editing, mode determined by whether `source_image_uuid` (JSON) / `images=@...` (multipart) is present. New section 5b in `references/design-rules.md` covers the request shape, the `source_image_uuid` field-name gotcha (NOT `image_uuid`), `additional_image_uuids` for multi-image reference, and the source-compatibility matrix (only Nano Banana + OpenAI support edit; Replicate-backed sources 422). SKILL.md decision tree + Phase 1 reference pointer updated. |
| 1.5 | 2026-06-01 | New `scripts/ah_check`, start-of-session auth probe (verifies key is set AND valid, prints masked confirmation, distinguishes missing vs revoked). Replaces the `echo "${APPARELHUB_API_KEY:?...}"` pattern that still tripped expansion prompts in v1.4. New `scripts/install_path.sh`, one-time PATH setup that detects bash / zsh / fish, idempotent, replaces the manual `echo ... >> ~/.bashrc` instruction. SKILL.md auth section + Install section updated. |
| 1.4 | 2026-06-01 | Packaged `scripts/ah_curl` Agent API wrapper, hides `$APPARELHUB_API_KEY` from the command line so Claude Code's `simple_expansion` check stops prompting on every call. Rewrites SKILL.md auth section + all 7 references + all 3 examples to invoke `ah_curl METHOD PATH` with literal-value substitution (no shell variables for captured UUIDs). `settings.recommended.json` extended with `ah_curl` patterns. New PATH setup step in Install. |
| 1.3 | 2026-06-01 | Packaged `scripts/make_transparent.py` keying tool (replaces inline Pillow snippets). `settings.recommended.json` for permission-prompt reduction. Phase 2 reference + design rules updated to invoke the script by path. Auto chroma detection for AI-generated greens that aren't exactly `#00FF00`. |
| 1.2 | 2026-06-01 | Restructured to parent + references pattern. Added embroidery, all-over print, payment authority, error handling, AI prompt anti-patterns. Three full end-to-end examples. Fixed OpenAPI spec URL. |
| 1.1 | 2026-05-29 | Test-driven fixes from the 2026-05-22 validation cycle (six bugs caught in Test 2 of the multi-step product creation flow). |
| 1.0 | 2026-05-21 | Initial publish. |

---

## Repo

<https://github.com/ApparelHub-AI/apparelhub-skills>
