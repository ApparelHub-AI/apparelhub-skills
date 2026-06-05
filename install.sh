#!/usr/bin/env bash
# install.sh: one-line installer for the ApparelHub Claude Code skill.
#
# Usage (recommended):
#   curl -fsSL https://apparelhub.ai/install-skill.sh | bash
#
# Or with the key already set so the script doesn't prompt:
#   APPARELHUB_API_KEY=ah_... bash -c "$(curl -fsSL https://apparelhub.ai/install-skill.sh)"
#
# What this does (all idempotent, safe to re-run):
#   1. Verifies prerequisites (git, curl, supported shell)
#   2. Clones (or pulls) the skill repo to ~/.apparelhub-skills
#   3. Symlinks ~/.apparelhub-skills/apparelhub into ~/.claude/skills/apparelhub
#   4. Adds the skill scripts dir to your shell PATH (via install_path.sh)
#   5. Stores your ApparelHub API key in ~/.apparelhub-skills/.env (chmod 600)
#      and sources it from your shell rc file
#   6. Runs ah_check to verify the key works against the platform
#
# Source: https://github.com/ApparelHub-AI/apparelhub-skills/blob/main/install.sh
# Read it before piping to bash: curl -fsSL https://apparelhub.ai/install-skill.sh | less

set -euo pipefail

# ---- environment selection -------------------------------------------------
# Honor APPARELHUB_API_BASE for environment selection so the same installer
# works against dev or prod. Default to prod; set
#   APPARELHUB_API_BASE=https://api.dev.apparelhub.ai
# to target the dev stack. The detected host is also used to derive the
# front-end host (apparelhub.ai vs dev.apparelhub.ai) for any URLs we print.
API_BASE="${APPARELHUB_API_BASE:-https://api.apparelhub.ai}"
API_BASE="${API_BASE%/}"
HUB_HOST=$(printf '%s' "$API_BASE" | sed -e 's,^https\?://,,' -e 's,^api\.,,' -e 's,/.*$,,')

# ---- pretty output helpers --------------------------------------------------

if [ -t 1 ]; then
    C_BLUE=$'\033[34m'
    C_GREEN=$'\033[32m'
    C_RED=$'\033[31m'
    C_DIM=$'\033[2m'
    C_RESET=$'\033[0m'
else
    C_BLUE="" C_GREEN="" C_RED="" C_DIM="" C_RESET=""
fi

step()  { printf '\n%s>> %s%s\n' "$C_BLUE" "$1" "$C_RESET"; }
ok()    { printf '%s   ok%s %s\n' "$C_GREEN" "$C_RESET" "$1"; }
warn()  { printf '%s   !! %s%s\n' "$C_RED" "$1" "$C_RESET" >&2; }
fail()  { printf '\n%sinstall failed:%s %s\n' "$C_RED" "$C_RESET" "$1" >&2; exit 1; }

# ---- OS + prerequisites -----------------------------------------------------

step "Checking your system"

case "$(uname -s)" in
    Darwin|Linux) ok "$(uname -s)" ;;
    *)
        fail "this installer supports macOS and Linux only.
       On Windows or other platforms, follow the manual install instructions:
       https://github.com/ApparelHub-AI/apparelhub-skills#install"
        ;;
esac

for cmd in git curl; do
    command -v "$cmd" >/dev/null 2>&1 \
        || fail "$cmd is not installed. Install $cmd and re-run."
done
ok "git + curl available"

if ! command -v claude >/dev/null 2>&1; then
    # Soft note rather than a red warning. Many users invoke Claude through
    # a custom harness (e.g. OpenClaw, Cline, Aider, or a web UI that proxies
    # the chat into a container running Claude) where the `claude` binary is
    # never on the local PATH. The install still works correctly in those
    # setups.
    printf '%s   .. claude CLI not on PATH (fine if you use a custom harness or web UI)%s\n' \
        "$C_DIM" "$C_RESET"
fi

# ---- repo clone / pull ------------------------------------------------------

REPO_URL="https://github.com/ApparelHub-AI/apparelhub-skills.git"
REPO_DIR="$HOME/.apparelhub-skills"

step "Installing the skill at $REPO_DIR"

if [ -d "$REPO_DIR/.git" ]; then
    git -C "$REPO_DIR" pull --ff-only origin main >/dev/null 2>&1 \
        || warn "git pull did not fast-forward; leaving working copy as-is"
    ok "updated existing clone"
elif [ -e "$REPO_DIR" ]; then
    fail "$REPO_DIR exists and is not a git clone. Move or remove it, then re-run."
else
    git clone --depth=1 "$REPO_URL" "$REPO_DIR" >/dev/null 2>&1 \
        || fail "git clone failed"
    ok "cloned $REPO_URL"
fi

# ---- symlink into Claude Code's skills dir ----------------------------------

SKILLS_DIR="$HOME/.claude/skills"
SKILL_LINK="$SKILLS_DIR/apparelhub"
SKILL_SRC="$REPO_DIR/apparelhub"

step "Linking the skill into $SKILLS_DIR"

mkdir -p "$SKILLS_DIR"

if [ -L "$SKILL_LINK" ]; then
    if [ "$(readlink "$SKILL_LINK")" = "$SKILL_SRC" ]; then
        ok "symlink already in place"
    else
        ln -sfn "$SKILL_SRC" "$SKILL_LINK"
        ok "updated symlink to $SKILL_SRC"
    fi
elif [ -e "$SKILL_LINK" ]; then
    fail "$SKILL_LINK exists and is not a symlink. Move or remove it, then re-run."
else
    ln -s "$SKILL_SRC" "$SKILL_LINK"
    ok "created symlink $SKILL_LINK -> $SKILL_SRC"
fi

# ---- detect shell rc file (used by both PATH setup + key sourcing) ----------

SHELL_NAME=$(basename "${SHELL:-/bin/bash}")
case "$SHELL_NAME" in
    zsh)  RC_FILE="$HOME/.zshrc" ;;
    bash)
        if [ -f "$HOME/.bash_profile" ]; then
            RC_FILE="$HOME/.bash_profile"
        else
            RC_FILE="$HOME/.bashrc"
        fi
        ;;
    fish) RC_FILE="$HOME/.config/fish/config.fish" ;;
    *)    RC_FILE="" ;;
esac

# ---- PATH setup -------------------------------------------------------------

step "Adding the skill scripts dir to your PATH"

bash "$SKILL_SRC/scripts/install_path.sh" >/dev/null
ok "install_path.sh ran (rc file: ${RC_FILE:-unknown shell, see manual instructions above})"

# ---- API key resolution -----------------------------------------------------

step "Setting your ApparelHub API key"

ENV_FILE="$REPO_DIR/.env"
API_KEY="${APPARELHUB_API_KEY:-}"

# Order of precedence:
#   1. APPARELHUB_API_KEY already in the environment (re-run / scripted install)
#   2. ~/.apparelhub-skills/.env from a previous install (reuse it silently)
#   3. Prompt the user via /dev/tty (works under `curl ... | bash`)
if [ -z "$API_KEY" ] && [ -f "$ENV_FILE" ]; then
    # shellcheck disable=SC1090
    . "$ENV_FILE"
    API_KEY="${APPARELHUB_API_KEY:-}"
    [ -n "$API_KEY" ] && ok "reusing key from $ENV_FILE"
fi

if [ -z "$API_KEY" ]; then
    # Probe whether we can actually OPEN /dev/tty for read, not just whether
    # the file exists. Many headless contexts (custom harnesses, CI runners,
    # etc.) have the device node present, so `[ -r /dev/tty ]` is misleadingly
    # true, but opening it for read fails because nothing is on the other end.
    # Run the open in a subshell so a failure doesn't take down the install
    # script.
    if ! ( exec 3</dev/tty ) 2>/dev/null; then
        fail "no API key supplied and no interactive terminal is attached
       to this install. This is normal in custom harnesses (e.g.
       OpenClaw, Cline, Aider), CI runners, and other contexts where
       the agent has no controlling terminal.

       Re-run with the key supplied as an environment variable:
         APPARELHUB_API_KEY=<your-key> bash -c \"\$(curl -fsSL https://${HUB_HOST}/install-skill.sh)\"

       If your Claude agent is doing the install for you, send it a
       SELF-CONTAINED chat message. Claude has no prior knowledge of
       ApparelHub, so the prompt must include the exact command. For
       example:
         \"Please run this exact command for me:
          APPARELHUB_API_KEY=<your-key> bash -c \"\$(curl -fsSL https://${HUB_HOST}/install-skill.sh)\"
          This is the ApparelHub installer; source is at
          https://github.com/ApparelHub-AI/apparelhub-skills/blob/main/install.sh.\"

       Or copy a ready-made harness prompt with your key pre-filled from
       https://${HUB_HOST}/developer/api-keys (Custom harness tab).

       Generate a key at https://${HUB_HOST}/developer/api-keys"
    fi
    printf "\n   Generate a key at %shttps://%s/developer/api-keys%s\n" "$C_DIM" "$HUB_HOST" "$C_RESET"
    printf "   Paste your ApparelHub API key (input hidden): "
    IFS= read -rs API_KEY </dev/tty || true
    printf '\n'
    if [ -z "$API_KEY" ]; then
        # Belt + suspenders: if the read failed despite our probe passing
        # (race, slow tty open, etc.), still surface the harness-aware copy
        # instead of the prior generic "no key entered" line.
        fail "no key entered. If you intended to install non-interactively
       (custom harness, CI, etc.), supply the key as an env var:
         APPARELHUB_API_KEY=<your-key> bash -c \"\$(curl -fsSL https://${HUB_HOST}/install-skill.sh)\""
    fi
fi

# Write the .env (bash-compatible). Fish gets a parallel .env.fish below.
# If a non-default APPARELHUB_API_BASE was supplied (e.g. dev install), persist
# that too so subsequent shells + the packaged skill scripts (ah_check,
# ah_curl, ah_poll_mockup) target the same env. The default is implicit; only
# persist when the user explicitly chose a non-default base URL.
umask 077
{
    printf 'export APPARELHUB_API_KEY=%s\n' "$API_KEY"
    if [ "$API_BASE" != "https://api.apparelhub.ai" ]; then
        printf 'export APPARELHUB_API_BASE=%s\n' "$API_BASE"
    fi
} > "$ENV_FILE"
chmod 600 "$ENV_FILE"
ok "key saved to $ENV_FILE (chmod 600, target $API_BASE)"

if [ "$SHELL_NAME" = "fish" ]; then
    ENV_FISH="$REPO_DIR/.env.fish"
    {
        printf 'set -gx APPARELHUB_API_KEY %s\n' "$API_KEY"
        if [ "$API_BASE" != "https://api.apparelhub.ai" ]; then
            printf 'set -gx APPARELHUB_API_BASE %s\n' "$API_BASE"
        fi
    } > "$ENV_FISH"
    chmod 600 "$ENV_FISH"
    ok "fish-compatible env written to $ENV_FISH"
fi

# Add a sourcing line to the rc file so future shells pick up the key.
# Idempotent via marker.
SOURCE_MARKER="# apparelhub-skills API key"
if [ -n "$RC_FILE" ]; then
    if [ -f "$RC_FILE" ] && grep -qF "$SOURCE_MARKER" "$RC_FILE"; then
        ok "$RC_FILE already sources the key"
    else
        mkdir -p "$(dirname "$RC_FILE")"
        case "$SHELL_NAME" in
            fish)
                printf '\n%s\nif test -f %s\n    source %s\nend\n' \
                    "$SOURCE_MARKER" "$REPO_DIR/.env.fish" "$REPO_DIR/.env.fish" >> "$RC_FILE"
                ;;
            *)
                printf '\n%s\n[ -f %s ] && . %s\n' \
                    "$SOURCE_MARKER" "$ENV_FILE" "$ENV_FILE" >> "$RC_FILE"
                ;;
        esac
        ok "added sourcing line to $RC_FILE"
    fi
fi

# Make the key live in THIS shell so ah_check below works. Pass
# APPARELHUB_API_BASE through too so ah_check targets the right environment
# (defaults to prod, but a dev install passes the dev base URL).
export APPARELHUB_API_KEY="$API_KEY"
export APPARELHUB_API_BASE="$API_BASE"

# ---- verify with ah_check ---------------------------------------------------

step "Verifying the key against the platform ($API_BASE)"

if "$SKILL_SRC/scripts/ah_check"; then
    ok "ah_check passed"
else
    fail "ah_check rejected the key. Verify it at https://${HUB_HOST}/developer/api-keys"
fi

# ---- done -------------------------------------------------------------------

cat <<EOF

${C_GREEN}Done.${C_RESET} The ApparelHub skill is installed.

Next step depends on how you talk to Claude:

  ${C_BLUE}- Claude Code (CLI):${C_RESET}
      Open a new terminal (or run: source ${RC_FILE:-your shell rc file})
      so the next shell has PATH + APPARELHUB_API_KEY set, then run
      \`claude\` and ask it to design a tee or list your products.

  ${C_BLUE}- Custom harness or web UI talking to Claude through any${C_RESET}
    ${C_BLUE}  chat interface (e.g. OpenClaw, Cline, Aider):${C_RESET}
      Start a NEW conversation. Claude discovers skills at session start,
      so the running session won't see ApparelHub until you open a fresh
      conversation. No restart of your harness needed.

  ${C_BLUE}- Claude Web or any other AI agent (Codex, ChatGPT, Gemini, ...):${C_RESET}
      The skill files were installed locally, but Claude Web and other
      agents can't read your local filesystem. Use the bootstrap prompt
      instead:
        ${REPO_DIR}/apparelhub/BOOTSTRAP-PROMPT.md
      Paste its contents into your agent's project / system prompt and
      provide your API key as an env var or in the prompt.

Useful files:
  - Recommended permission allowlist (drops permission prompts):
      ${REPO_DIR}/settings.recommended.json
  - Universal bootstrap prompt for any LLM:
      ${REPO_DIR}/apparelhub/BOOTSTRAP-PROMPT.md
  - Full setup docs: https://apparelhub.ai/agents
  - API reference:   https://apparelhub.ai/developer/api-docs

EOF
