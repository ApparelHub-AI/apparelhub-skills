#!/usr/bin/env bash
# install.sh — Claude Code installer for the ApparelHub skill.
#
# Usage (recommended):
#   curl -fsSL https://apparelhub.ai/install-skill.sh | bash
#
# With the key already set so the installer doesn't prompt:
#   APPARELHUB_API_KEY=<your-key> bash -c "$(curl -fsSL https://apparelhub.ai/install-skill.sh)"
#
# Persist the key to ~/.apparelhub-skills/.env (v1.x default — NOT recommended;
# manage the key via your host's secret manager instead):
#   curl -fsSL https://apparelhub.ai/install-skill.sh | bash -s -- --persist
#
# What this does (all idempotent, safe to re-run):
#   1. Verifies prerequisites (git, curl, supported shell)
#   2. Clones (or pulls) the skill repo to ~/.apparelhub-skills
#   3. Symlinks ~/.apparelhub-skills/apparelhub into ~/.claude/skills/apparelhub
#   4. Adds the skill scripts dir to your shell PATH (via claude-code/install_path.sh)
#   5. Prompts for your ApparelHub API key (or reads it from env)
#   6. Runs ah_check to verify the key works against https://api.apparelhub.ai
#   7. EXITS without persisting the key, unless --persist was passed
#
# Source: https://github.com/ApparelHub-AI/apparelhub-skills/blob/main/install.sh
# Trust model: https://github.com/ApparelHub-AI/apparelhub-skills/blob/main/SECURITY.md
# Read this script before piping to bash: curl -fsSL https://apparelhub.ai/install-skill.sh | less

set -euo pipefail

# ---- canonical host (hard-pinned; see SECURITY.md §2c) ----------------------

API_BASE="https://api.apparelhub.ai"
HUB_HOST="apparelhub.ai"

# ---- args -------------------------------------------------------------------

PERSIST=0
for arg in "$@"; do
    case "$arg" in
        --persist) PERSIST=1 ;;
        --help|-h)
            sed -n '2,30p' "$0"
            exit 0
            ;;
        *) ;;
    esac
done

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

# ---- trust-model preamble ---------------------------------------------------

cat <<EOF

${C_DIM}ApparelHub skill installer (v2.0)
- This installs into ~/.apparelhub-skills/ and symlinks into
  ~/.claude/skills/apparelhub/. It edits your shell rc to add the
  skill's scripts/ dir to PATH.
- The API key you supply is sent ONLY to ${API_BASE} for a one-time
  verification (no other host). The key is NOT written to disk unless
  you pass --persist.
- Full trust model: https://github.com/ApparelHub-AI/apparelhub-skills/blob/main/SECURITY.md${C_RESET}
EOF

# ---- OS + prerequisites -----------------------------------------------------

step "Checking your system"

case "$(uname -s)" in
    Darwin|Linux) ok "$(uname -s)" ;;
    *)
        fail "this installer supports macOS and Linux only.
       On Windows or other platforms, see the porting guides:
       https://github.com/ApparelHub-AI/apparelhub-skills/tree/main/porting-guides"
        ;;
esac

for cmd in git curl; do
    command -v "$cmd" >/dev/null 2>&1 \
        || fail "$cmd is not installed. Install $cmd and re-run."
done
ok "git + curl available"

if ! command -v claude >/dev/null 2>&1; then
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

# ---- detect shell rc file (used by PATH setup + optional --persist) ---------

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

# In v2.0, install_path.sh lives under the claude-code/ overlay.
bash "$REPO_DIR/claude-code/install_path.sh" >/dev/null
ok "install_path.sh ran (rc file: ${RC_FILE:-unknown shell, see manual instructions above})"

# ---- API key resolution -----------------------------------------------------

step "Resolving your ApparelHub API key"

API_KEY="${APPARELHUB_API_KEY:-}"

# Order of precedence:
#   1. APPARELHUB_API_KEY already in the environment
#   2. Existing ~/.apparelhub-skills/.env from a prior --persist install (reuse)
#   3. Prompt the user via /dev/tty (works under `curl ... | bash`)
ENV_FILE="$REPO_DIR/.env"
if [ -z "$API_KEY" ] && [ -f "$ENV_FILE" ]; then
    # shellcheck disable=SC1090
    . "$ENV_FILE" 2>/dev/null || true
    API_KEY="${APPARELHUB_API_KEY:-}"
    if [ -n "$API_KEY" ]; then
        ok "reusing key from previous --persist install at $ENV_FILE"
    fi
fi

if [ -z "$API_KEY" ]; then
    if ! ( exec 3</dev/tty ) 2>/dev/null; then
        fail "no API key supplied and no interactive terminal is attached
       to this install. Re-run with the key supplied as an environment
       variable:
         APPARELHUB_API_KEY=<your-key> bash -c \"\$(curl -fsSL https://${HUB_HOST}/install-skill.sh)\"

       If your Claude agent is doing the install for you, send it a
       SELF-CONTAINED chat message that includes the full command.

       Generate a key at https://${HUB_HOST}/developer/api-keys"
    fi
    printf "\n   Generate a key at %shttps://%s/developer/api-keys%s\n" "$C_DIM" "$HUB_HOST" "$C_RESET"
    printf "   Paste your ApparelHub API key (input hidden): "
    IFS= read -rs API_KEY </dev/tty || true
    printf '\n'
    if [ -z "$API_KEY" ]; then
        fail "no key entered. If you intended to install non-interactively,
       supply the key as an env var:
         APPARELHUB_API_KEY=<your-key> bash -c \"\$(curl -fsSL https://${HUB_HOST}/install-skill.sh)\""
    fi
fi

# ---- optional persistence (--persist only) ----------------------------------

if [ $PERSIST -eq 1 ]; then
    printf "\n${C_RED}--persist requested.${C_RESET}\n"
    printf "Writing your API key to %s (chmod 600) and sourcing it\n" "$ENV_FILE"
    printf "from %s on every shell login.\n" "${RC_FILE:-your shell rc file}"
    printf "Anyone with read access to those files (synced dotfiles, backups,\n"
    printf "borrowed laptops, etc.) can read the key. See SECURITY.md §2b.\n\n"

    umask 077
    printf 'export APPARELHUB_API_KEY=%s\n' "$API_KEY" > "$ENV_FILE"
    chmod 600 "$ENV_FILE"
    ok "key saved to $ENV_FILE"

    if [ "$SHELL_NAME" = "fish" ]; then
        ENV_FISH="$REPO_DIR/.env.fish"
        printf 'set -gx APPARELHUB_API_KEY %s\n' "$API_KEY" > "$ENV_FISH"
        chmod 600 "$ENV_FISH"
        ok "fish-compatible env written to $ENV_FISH"
    fi

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
fi

# Make the key live in THIS shell so the ah_check call below works. The
# verification request goes only to $API_BASE (the canonical host).
export APPARELHUB_API_KEY="$API_KEY"

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

Next:

  ${C_BLUE}If you're using Claude Code (CLI):${C_RESET}
    Open a new terminal so the next shell has the PATH update, then
    run \`claude\`. Make sure APPARELHUB_API_KEY is set in that shell
    (via your shell rc, direnv, or a host secret manager).
EOF

if [ $PERSIST -eq 0 ]; then
    cat <<EOF

  ${C_BLUE}Setting APPARELHUB_API_KEY persistently:${C_RESET}
    The v2.0 installer does NOT persist your key. Pick one:
      - shell rc: add \`export APPARELHUB_API_KEY=...\` to ~/.zshrc / ~/.bashrc
      - direnv:   add \`export APPARELHUB_API_KEY=...\` to a project .envrc
      - macOS Keychain / 1Password CLI / etc.
    Or re-run with --persist if you want the v1.x \`.env\` behavior.
EOF
fi

cat <<EOF

  ${C_BLUE}If you're using ChatGPT, Gemini, or another tool-calling agent:${C_RESET}
    See ${REPO_DIR}/porting-guides/chatgpt-gemini.md.

  ${C_BLUE}If you're using a bare-HTTP agent:${C_RESET}
    See ${REPO_DIR}/porting-guides/bare-http.md.

Useful files:
  - Trust model:               ${REPO_DIR}/SECURITY.md
  - Recommended allowlist:     ${REPO_DIR}/claude-code/settings.recommended.json
  - Per-platform porting docs: ${REPO_DIR}/porting-guides/
  - Full setup walkthrough:    https://${HUB_HOST}/agents
  - API reference:             https://${HUB_HOST}/developer/api-docs

EOF
