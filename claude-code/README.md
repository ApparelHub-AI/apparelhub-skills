# Claude Code overlay

Files in this directory are specific to Claude Code users — manifest
frontmatter, the `Bash(...)` permission allowlist, the PATH helper, etc.
They are not required for any other consumer of the skill (ChatGPT,
Gemini, bare-HTTP agents).

The host-neutral knowledge lives one directory up, in `apparelhub/`.

## What's here

| File | Purpose |
|---|---|
| `settings.recommended.json` | Drop-in patterns for `~/.claude/settings.json` to allowlist the helpers + canonical-host `curl` calls. Optional; without it, Claude Code will prompt the first time it expands `$APPARELHUB_API_KEY` or hits the canonical host. That prompt is the safety control working correctly — see `../SECURITY.md` §2a. |
| `install_path.sh` | Idempotent PATH-edit utility. Adds `~/.claude/skills/apparelhub/scripts` to your shell rc. Invoked by `../install.sh`; you don't typically run it directly. |

## Permission prompts are working correctly

The v1.x skill bundled a wrapper script (`ah_curl`) whose stated purpose
was to keep shell-expansion patterns off the visible command line so
Claude Code's `simple_expansion` check wouldn't fire. v2.0 removed that.
The helpers that remain — `ah_check`, `ah_poll_mockup`, etc. — earn
their place by encoding genuinely useful logic (state machines, math,
image processing), not by suppressing review prompts.

If Claude Code prompts you when the agent first reads your API key or
calls the API: that's the prompt working. Approve in context. If you
want fewer prompts on routine calls, merge `settings.recommended.json`
into your `~/.claude/settings.json`.

## Where to start

Most Claude Code users want `../porting-guides/claude-code.md`.
