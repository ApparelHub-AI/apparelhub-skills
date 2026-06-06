# Porting Guide — Claude Code

Audience: a Claude Code user running locally on macOS or Linux, with
shell access and the `~/.claude/skills/` discovery directory.

This is the most ergonomic path because the skill ships a small set of
optional helper scripts that save typing for the polling state machine,
the preview classification, and the dimension math.

---

## Install

One-liner (Claude Code installer):

```bash
curl -fsSL https://apparelhub.ai/install-skill.sh | bash
```

The installer:

1. Clones the public repo to `~/.apparelhub-skills/`
2. Symlinks `~/.apparelhub-skills/apparelhub` into `~/.claude/skills/apparelhub`
3. Adds the skill's `scripts/` directory to your `PATH` via your shell rc
4. Prompts for your `APPARELHUB_API_KEY` and verifies it against the
   platform with `ah_check`
5. **Does not** persist the key to disk by default. The successful
   verification message tells you to put `export APPARELHUB_API_KEY=...`
   wherever you manage development secrets (shell rc, direnv, etc.).
   Add `--persist` to the installer if you want the v1.x persistent
   `.env` behavior; you'll see a warning about the trade-off.

Before piping curl to bash, you can read the script:

```bash
curl -fsSL https://apparelhub.ai/install-skill.sh | less
```

Source on GitHub:
`https://github.com/ApparelHub-AI/apparelhub-skills/blob/main/install.sh`

### Optional — recommended permission allowlist

The repo ships `claude-code/settings.recommended.json` with allowlist
patterns for the helpers + the canonical `https://api.apparelhub.ai`
prefix. Merge it into your `~/.claude/settings.json` to drop a few
prompts on routine calls. Reading the patterns first is worth a minute
of your time.

---

## Permission prompts are working correctly

Claude Code prompts the first time a command reads your API key from
the environment or makes a network call to a host it doesn't recognize.

**That is correct behavior.** Approve the prompt in context if the call
is one you intended.

The v1.x skill bundled wrapper scripts whose stated purpose was to keep
shell expansion off the visible command line so the prompt wouldn't
fire. v2.0 removes that framing. The optional helpers that ship now
(`ah_check`, `ah_poll_mockup`, `ah_classify_previews`,
`ah_pick_dimensions`, `make_transparent.py`, `ah_pick_provider_url`)
earn their place by encoding genuinely useful logic — state machines,
math, image processing — not by suppressing prompts.

---

## Walkthrough — saguaro sunset tee on BC 3001

The flow is the same as `porting-guides/bare-http.md`. The Claude Code
deltas are where helper scripts save typing.

### 1. Verify the API key is live

```bash
ah_check
```

Exits 0 on success with a masked-key confirmation. Exit 2 if the env
var is missing; exit 3 if the platform rejected the key.

### 2. Generate the design

```bash
curl -sS -X POST https://api.apparelhub.ai/agents/v1/images/generate \
  -H "x-api-key: $APPARELHUB_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"prompt":"vector flat illustration saguaro cactus silhouette desert sunset, on pure RGB #00FF00 background","source":"Nano Banana","size":"1024x1024"}'
```

Claude Code may prompt the first time it expands `$APPARELHUB_API_KEY`.
Approve in context.

### 3. Transparency processing

Use the bundled image script (canonical-host pin doesn't matter here —
it's a pure local image operation, no network call):

```bash
curl -sS "https://apparelhub-production-user-generated-public-objects.s3.amazonaws.com/<image-path>.png" \
  -o /tmp/design_green.png

python3 ~/.claude/skills/apparelhub/scripts/make_transparent.py \
  /tmp/design_green.png /tmp/design_transparent.png \
  --preview /tmp/design_preview.jpg
```

Then look at `/tmp/design_preview.jpg` — that's your no-halo, no-leftover-green
gate. See `apparelhub/references/product-creation-pipeline.md` §2 for
the failure-mode handling.

Upload via the transform endpoint:

```bash
curl -sS -X POST https://api.apparelhub.ai/agents/v1/images/generated/<image_uuid>/transform \
  -H "x-api-key: $APPARELHUB_API_KEY" \
  -F image=@/tmp/design_transparent.png
```

### 4. Pick dimensions

```bash
ah_pick_dimensions /tmp/design_transparent.png 1800 2400 --style chest_fill
```

Prints `(width, height, left, top)` and writes a JSON file the agent
can read for the mockup body. See script `--help` for the placement
styles (`chest_fill`, `chest_emblem`, `back_center`, `all_over`).

### 5. Mockup generation

```bash
curl -sS -X POST https://api.apparelhub.ai/agents/v1/merchandise/product/preview \
  -H "x-api-key: $APPARELHUB_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"merchandise_provider_uuid":"<printful uuid>","generated_image_uuid":"<new uuid>","provider_product_ref_id":"71","templates":[...],"variant_ids":[4016,4017,4018,4019,4020]}'
```

### 6. Poll the mockup — two-phase wait, handled by the script

```bash
ah_poll_mockup <printful uuid> <job uuid>
```

Polls every 8s, blocks until `status=completed` AND at least one
`preview_url` is populated, writes `/tmp/preview_job.json` for you. Has
built-in transient-error tolerance (502/503/504/429 + network failures
counted separately from the wall-clock budget). Exits 0 on success.

### 7. Classify previews

```bash
ah_classify_previews /tmp/preview_job.json --recommend /tmp/picks.json
```

Writes `{display_image, gallery_images, rationale}` into `/tmp/picks.json`.
The agent reads the JSON and pastes the URLs into the create body.

### 8. Create the product, add variants, add to store

Same `curl` shape as the bare-HTTP guide. The polling/classification
scripts are the only Claude-Code-specific conveniences; the
state-changing endpoints are plain HTTP, presented for the agent to
issue with full review-prompt context.

### 9. Sync gates the same way

`POST /sync?target=merchandise` for Printful, `POST /sync?target=ecommerce&integration_uuid=...&listing_state=draft`
for sales channels — only after the user explicitly asks.

---

## What ships in `scripts/`

| Script | Value-add | Network call? |
|---|---|---|
| `ah_check` | Validates the key against the platform before a multi-step workflow. Distinguishes missing (exit 2), rejected (exit 3), valid (exit 0). | Yes — pinned `https://api.apparelhub.ai`. |
| `ah_poll_mockup` | Two-phase polling state machine + transient retry logic. | Yes — pinned `https://api.apparelhub.ai`. |
| `ah_classify_previews` | Local parsing of preview-job JSON; recommends display/gallery picks. | No (reads a local file). |
| `ah_pick_provider_url` | Extracts a single preview URL by color+angle from a preview-job JSON. | No (reads a local file). |
| `ah_pick_dimensions` | Computes `(width, height, left, top)` from design aspect + print area + style preset. | No (reads a local image). |
| `make_transparent.py` | Flood-fill chroma key + pre-multiply + auto-crop for transparency processing. | No (local image op). |

All four network-touching scripts (`ah_check`, `ah_poll_mockup`, plus
the local-only scripts that read API responses) are pinned to
`https://api.apparelhub.ai`. There is no runtime override; if you need
to talk to dev, edit the constant at the top of the script in a local
fork.

### What got deleted from v1.x

- `ah_curl` — accepted arbitrary URLs and forwarded the API key. Deleted
  in v2.0. Replace with plain `curl https://api.apparelhub.ai/agents/v1/...`
  invocations.
- `install_path.sh` — moved to `claude-code/install_path.sh`. Used only
  inside the installer.

---

## Migrating from v1.x

If you have a v1.x install:

1. Remove the rc-file sourcing line (`[ -f ~/.apparelhub-skills/.env ] && . ~/.apparelhub-skills/.env`) from your shell rc.
2. `rm -f ~/.apparelhub-skills/.env ~/.apparelhub-skills/.env.fish` (the key is no longer persisted).
3. Add `export APPARELHUB_API_KEY=...` to wherever you manage development secrets.
4. Re-run the installer: `curl -fsSL https://apparelhub.ai/install-skill.sh | bash`.
5. Update any of your own scripts that called `ah_curl` to use plain `curl https://api.apparelhub.ai/agents/v1/...` invocations.
6. If you'd previously merged the old `settings.recommended.json` into your `~/.claude/settings.json`, swap the `Bash(ah_curl …)` patterns for plain `curl` patterns or remove them entirely. See `claude-code/settings.recommended.json` for the v2.0 baseline.
