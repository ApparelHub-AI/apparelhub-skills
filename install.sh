#!/usr/bin/env bash
# install.sh — one-line installer for the ApparelHub Claude Code skill.
#
# Usage (recommended):
#   curl -fsSL https://apparelhub.ai/install-skill.sh | bash
#
# Or with the key already set so the script doesn't prompt:
#   APPARELHUB_API_KEY=ah_... bash -c "$(curl -fsSL https://apparelhub.ai/install-skill.sh)"
#
# What this does (all idempotent — safe to re-run):
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
    warn "claude CLI not found on PATH."
    warn "The skill will install correctly but you'll need Claude Code"
    warn "(https://docs.claude.com/en/docs/claude-code) to use it."
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
    if [ ! -r /dev/tty ]; then
        fail "no API key supplied and no terminal available to prompt.
       Re-run with the key in env:
         APPARELHUB_API_KEY=ah_... bash -c \"\$(curl -fsSL https://apparelhub.ai/install-skill.sh)\"
       Or generate a key at https://apparelhub.ai/developer/api-keys"
    fi
    printf "\n   Generate a key at %shttps://apparelhub.ai/developer/api-keys%s\n" "$C_DIM" "$C_RESET"
    printf "   Paste your ApparelHub API key (input hidden): "
    IFS= read -rs API_KEY </dev/tty || true
    printf '\n'
    [ -n "$API_KEY" ] || fail "no key entered"
fi

# Write the .env (bash-compatible). Fish gets a parallel .env.fish below.
umask 077
printf 'export APPARELHUB_API_KEY=%s\n' "$API_KEY" > "$ENV_FILE"
chmod 600 "$ENV_FILE"
ok "key saved to $ENV_FILE (chmod 600)"

if [ "$SHELL_NAME" = "fish" ]; then
    ENV_FISH="$REPO_DIR/.env.fish"
    printf 'set -gx APPARELHUB_API_KEY %s\n' "$API_KEY" > "$ENV_FISH"
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

# Make the key live in THIS shell so ah_check below works.
export APPARELHUB_API_KEY="$API_KEY"

# ---- verify with ah_check ---------------------------------------------------

step "Verifying the key against the platform"

if "$SKILL_SRC/scripts/ah_check"; then
    ok "ah_check passed"
else
    fail "ah_check rejected the key. Verify it at https://apparelhub.ai/developer/api-keys"
fi

# ---- done -------------------------------------------------------------------

cat <<EOF

${C_GREEN}Done.${C_RESET} The ApparelHub skill is installed.

Next steps:
  - Open a new terminal (or run: source ${RC_FILE:-your shell rc file})
    so the next shell has PATH + APPARELHUB_API_KEY set
  - Open Claude Code; ask it to design a tee or list your products
  - Recommended permission allowlist for fewer prompts:
      ${REPO_DIR}/settings.recommended.json
  - Full setup docs: https://apparelhub.ai/agents
  - API reference:   https://apparelhub.ai/developer/api-docs

EOF
