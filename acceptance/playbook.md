# Acceptance Playbook

Manual verification that the skill still meets the platform-neutral +
security acceptance criteria from the v2.0 epic.

Run this before every release tag, and at least quarterly between
releases as a regression check.

---

## 1. The criteria (reproduced for the operator)

- [ ] A fresh agent on a platform we've never special-cased can run the
  full design → product → sync flow from the docs alone.
- [ ] Nothing in the repo's recommended path is justified by, or
  functions to, suppress a host's permission/review prompt.
- [ ] The API key is never written to disk and never sent to any host
  but the pinned canonical one, **by construction** (not just by
  convention).
- [ ] Every state-changing/sync step still requires explicit user
  approval, and sales-channel sync still defaults to DRAFT.

---

## 2. Platform A — bare HTTP

Goal: prove the skill is consumable by an agent with only HTTP
capability.

Setup:

- A throwaway test user on prod with a valid API key.
- A scratch UI (curl, Postman, Insomnia, or a Python REPL with
  `requests`) standing in for "an agent that only has HTTP."
- Open `porting-guides/bare-http.md` in another window.

Steps:

1. Follow `porting-guides/bare-http.md` end-to-end, simulating an agent
   that has no access to the helper scripts in `apparelhub/scripts/`.
2. Generate one design, do transparency processing yourself (Pillow in a
   notebook), upload via transform.
3. Generate a mockup, poll the two-phase wait manually, classify the
   previews by inspecting the JSON.
4. Create the product, add 5 variants (Black S–2XL is enough for the
   test), add to a throwaway store.
5. STOP before sync. Confirm the product is on the store but not synced
   anywhere.
6. Time-box: 60 minutes wall-clock. If you can't complete within 60
   minutes, the docs need work.

Pass criteria:

- [ ] Completed steps 1–5 without referring to anything outside
  `porting-guides/bare-http.md` and `apparelhub/references/`.
- [ ] No need to read script source code.
- [ ] Mockup verification step worked.

Cleanup: delete the test product and remove from the store.

---

## 3. Platform B — Claude Code

Goal: prove the optional Claude Code helpers still encode the right
value and that the install flow is clean.

Setup:

- A fresh container or VM with no prior install of the skill.
- An `APPARELHUB_API_KEY` available as an env var or to paste at the
  installer prompt.

Steps:

1. `curl -fsSL https://apparelhub.ai/install-skill.sh | bash` (or the
   equivalent local path during pre-release testing).
2. Confirm `ls ~/.apparelhub-skills/.env` returns no such file (key not
   persisted by default).
3. Confirm `grep "apparelhub-skills API key" ~/.zshrc` (or your shell's
   rc) returns no hits (rc not edited by default).
4. `ah_check` returns 0 with masked-key confirmation.
5. Open a Claude Code session, drive the same saguaro-tee flow as
   Platform A using the bundled helpers (`ah_poll_mockup`,
   `ah_classify_previews`, etc.).
6. Verify Claude Code prompts on the first `curl https://api.apparelhub.ai/...`
   that expands `$APPARELHUB_API_KEY` and that approving in context
   works correctly.
7. STOP before sync, same as Platform A.

Pass criteria:

- [ ] Installer does not persist `.env` or edit rc by default.
- [ ] `ah_check` passes.
- [ ] `ah_poll_mockup` handles the two-phase wait, including a synthetic
  transient HTTP 504 (kill TCP mid-poll to simulate).
- [ ] Approval prompts fire at the expected points and approving them
  in context allows the flow to proceed.
- [ ] Optionally: install with `--persist`, confirm the warning shows and
  the `.env` does get written.

Cleanup: delete the test product, clean the install (`rm -rf ~/.apparelhub-skills ~/.claude/skills/apparelhub`, remove the PATH line from rc).

---

## 4. Platform C — ChatGPT / Gemini system prompt

Goal: prove the knowledge is portable to a tool-calling agent.

Setup:

- A ChatGPT Custom GPT (or Gemini Gem, or claude.ai Project) with a
  blank slate.
- The contents of `apparelhub/SKILL.md` ready to paste.
- A function-call implementation of `apparelhub_request` per
  `porting-guides/chatgpt-gemini.md` §B.

Steps:

1. Paste `SKILL.md` into the system prompt.
2. Add `references/api-contract.md` as a knowledge file (or paste
   inline).
3. Register the `apparelhub_request` function with the agent.
4. Ask the agent: *"Design a saguaro sunset tee and add it to my
   Acme Apparel store. Black, navy, and white in S–2XL. Don't sync
   to Shopify."*
5. Let the agent drive the flow via function calls.

Pass criteria:

- [ ] The agent issues calls to the correct endpoints in the correct
  order.
- [ ] The agent never tries to send the API key in plaintext (it's
  hidden inside the function-call implementation).
- [ ] The agent stops before sync and asks the user.
- [ ] If the agent tries to pass a full URL or a different host as
  `path`, the implementation rejects with the path-prefix validation
  error.

Cleanup: delete the test product.

---

## 5. Security smoke tests

Automated where possible; manual otherwise.

### 5a. ah_curl deleted

```bash
test ! -e ~/apparelhub-skills/apparelhub/scripts/ah_curl
```

Pass: ah_curl is gone.

### 5b. No `APPARELHUB_API_BASE` reads

```bash
grep -rE 'APPARELHUB_API_BASE' ~/apparelhub-skills/apparelhub ~/apparelhub-skills/claude-code ~/apparelhub-skills/install.sh
```

Pass: no hits, OR every hit is inside a comment that explicitly says
"removed in v2.0 — kept for migration docs only."

### 5c. ah_check rejects an injected host

```bash
APPARELHUB_API_KEY=bogus ah_check
```

Pass: exits non-zero and prints a message that points at
`https://apparelhub.ai/developer/api-keys`. Importantly: the URL in
the output is the canonical one, NOT something derived from an
environment variable.

### 5d. Helper script canonical-host pin

For each helper that makes a network call:

```bash
grep -E 'api\.apparelhub\.ai' ~/apparelhub-skills/apparelhub/scripts/ah_check
grep -E 'api\.apparelhub\.ai' ~/apparelhub-skills/apparelhub/scripts/ah_poll_mockup
```

Pass: the canonical host appears as a literal in each network-making
script. No env-var lookup for the base URL.

### 5e. install.sh does not write .env by default

```bash
( HOME=$(mktemp -d) APPARELHUB_API_KEY=bogus bash ~/apparelhub-skills/install.sh </dev/null; \
  test ! -e "$HOME/.apparelhub-skills/.env" && echo OK )
```

Pass: prints `OK`. (Installer should not write `.env` without `--persist`.)

---

## 6. Forbidden-pattern grep

Same patterns the CI workflow enforces, run locally before tagging:

```bash
cd ~/apparelhub-skills
grep -rnEi 'simple_expansion|expansion-free|allowlist-clean' \
  --include='*.md' --include='*.sh' --include='ah_*' --include='*.py' \
  apparelhub claude-code porting-guides install.sh README.md SECURITY.md
```

Pass: no hits. If any hit, fix before tagging.

```bash
grep -rnE "Claude Code's permission|expansion check.*fire" \
  --include='*.md' --include='*.sh' --include='ah_*' --include='*.py' \
  apparelhub claude-code porting-guides install.sh README.md SECURITY.md
```

Pass: no hits.

---

## 7. After-test ritual

Every full playbook run gets a one-line entry in this file's bottom log:

```
| Date | Tag | Operator | Platforms run | Result | Notes |
|------|-----|----------|---------------|--------|-------|
| 2026-06-06 | pre-v2.0 | Claude+maintainer | A, B, C | PASS | initial v2.0 acceptance |
```

If anything fails, file an issue, fix, re-run the affected platform,
and add a second log row.
