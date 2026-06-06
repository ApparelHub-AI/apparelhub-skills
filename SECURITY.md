# Security

The ApparelHub skill is a knowledge package used by AI agents that hold
your production API key. This document is the durable description of what
the skill does with that key, what it never does, and what to do if you
find a problem.

The claims in this file are verified in CI on every commit (see
`.github/workflows/forbidden-patterns.yml`). If any of them stop being
true, the build fails.

---

## 1. Trust model

- **Your `APPARELHUB_API_KEY` is a production credential.** Treat it like
  any other production secret: store it in your host's secret manager
  (macOS Keychain, 1Password CLI, Doppler, direnv, AWS Secrets Manager,
  Kubernetes secret, etc.) rather than committing it to git or pasting
  it into chats.
- **The skill is open source.** Review what you install before you
  install it. The install script's source is at
  `https://github.com/ApparelHub-AI/apparelhub-skills/blob/main/install.sh`
  and you can read it with `curl -fsSL https://apparelhub.ai/install-skill.sh | less`
  before piping to `bash`.
- **The canonical API host is hard-pinned.** Every helper script that
  makes a network call has `https://api.apparelhub.ai` compiled in. The
  destination cannot be changed by an environment variable, a command-line
  argument, or a config file. If a future commit tries to reintroduce a
  runtime override, the CI grep job fails.

---

## 2. Non-goals (explicit)

The following are things this skill **deliberately does not do**. If you
see anything in the repo that violates these, please open a security
issue.

### 2a. We do not bypass any host platform's permission prompt

If your AI agent's runtime — Claude Code, Cursor, ChatGPT, Gemini, a
custom harness — prompts you the first time it reads `APPARELHUB_API_KEY`
or makes a network call to a new host, **that is your platform's safety
control working correctly**. The skill's job is to make that prompt as
informative as possible (you know what the call is for, what the
destination is, and what the call will return), not to make it go away.

The v1.x skill bundled wrapper scripts whose *stated purpose* was to keep
shell-expansion patterns off the agent's visible command line so a
specific host's "expansion check" wouldn't fire. v2.0 removes that. The
helper scripts that survive (`ah_check`, `ah_poll_mockup`,
`ah_classify_previews`, etc.) earn their place by encoding genuinely
useful logic — state machines, math, image processing — not by
suppressing review prompts.

### 2b. We do not persist your API key to disk by default

`install.sh` no longer writes `~/.apparelhub-skills/.env` and no longer
appends a sourcing line to your shell rc. The recommended pattern is:

- Put `export APPARELHUB_API_KEY=...` wherever you normally manage
  development secrets (your shell rc, your direnv `.envrc`, your host's
  secret manager).
- The installer reads the key once to verify it works, then exits without
  leaving it anywhere.

If you genuinely want the v1.x behavior (persistent `.env` written to
disk, sourced from every shell), invoke the installer with `--persist`.
You will see an explicit warning that explains the trade-off before the
write happens.

### 2c. We do not accept a runtime-overridable base URL

The `APPARELHUB_API_BASE` environment variable that v1.x scripts honored
has been removed. The destination `https://api.apparelhub.ai` is compiled
into every script that makes a network call.

This closes an attack class: a poisoned reference doc, a prompt-injected
`export` instruction, or a malformed `.env` cannot redirect your API key
to an attacker-controlled host.

Internal contributors testing against the dev environment should fork the
repo and edit the constant at the top of the relevant helper script, not
rely on a runtime knob.

### 2d. We do not forward your key to arbitrary URLs

`ah_curl` accepted a full `https://...` URL as its first argument and
used it verbatim, attaching `x-api-key: $APPARELHUB_API_KEY` to whatever
host the agent passed. This is the canonical credential-exfiltration
surface and the most concrete reason v2.0 deletes `ah_curl`.

The surviving helpers (`ah_check`, `ah_poll_mockup`) accept *paths only*
and prepend the hard-pinned host. Any value that contains a host or
scheme is rejected.

---

## 3. Threat model and mitigations

| Threat | Mitigation |
|---|---|
| Prompt injection that tries to redirect the key to an attacker URL | Canonical-host pin in every helper; `ah_curl` deleted |
| Poisoned reference doc with `export APPARELHUB_API_BASE=...` instruction | `APPARELHUB_API_BASE` removed from the codebase entirely |
| Malformed `.env` file overriding the host | `.env` no longer read by any helper for destination configuration |
| Local credential exfiltration via dotfile read | Key not persisted to disk by default |
| Allowlist abuse on a runtime that allows wildcard `curl` patterns | Skill no longer recommends "use our wrapper to dodge prompts" framing; users are encouraged to use their host's review controls in context |
| Shoulder-surfed `cat ~/.apparelhub-skills/.env` | File no longer created by default |
| Rotating a leaked key | `https://apparelhub.ai/developer/api-keys` revokes + reissues; key revocation propagates within minutes |

---

## 4. Reporting a vulnerability

Please email `security@apparelhub.ai` for embargoed security reports.
Public issues are fine for low-impact concerns; anything that could
leak a customer's API key or production data should go through the
private channel first.

Include:

- A description of the issue
- Reproduction steps
- Affected versions
- Suggested mitigation if you have one

We aim to acknowledge within 2 business days and ship a fix within 14
days for high-severity issues.

---

## 5. What changed in v2.0

Summary of the security-relevant changes vs v1.x:

- `ah_curl` deleted (forwarded keys to arbitrary URLs)
- `APPARELHUB_API_BASE` removed from helpers and installer
- API key no longer persisted to `~/.apparelhub-skills/.env` by default
- Installer no longer edits your shell rc by default
- All "exists to bypass the permission prompt" framing removed from
  scripts and docs
- CI grep enforces the above on every commit

See `CHANGELOG.md` or the v2.0 GitHub release for the full migration
guide for existing v1.x users.
