#!/usr/bin/env bash
# install_path.sh — one-time: add the apparelhub scripts dir to your shell's
# PATH so `ah_check`, `ah_poll_mockup`, `make_transparent.py`, and the other
# packaged helpers can be invoked by bare name.
#
# Idempotent. Safe to re-run — won't add a duplicate line.
# Detects bash, zsh, and fish. Falls back to printing manual instructions
# for any other shell.
#
# Usage: bash ~/.claude/skills/apparelhub/scripts/install_path.sh

set -euo pipefail

SCRIPTS_DIR="$HOME/.claude/skills/apparelhub/scripts"
EXPORT_LINE='export PATH="$HOME/.claude/skills/apparelhub/scripts:$PATH"'
MARKER="# apparelhub-skills PATH"

# Detect the user's shell
SHELL_NAME=$(basename "${SHELL:-/bin/bash}")
case "$SHELL_NAME" in
    zsh)
        RC_FILE="$HOME/.zshrc"
        ;;
    bash)
        # On macOS, ~/.bash_profile is what bash reads for login shells (the
        # default Terminal.app behavior). On Linux, ~/.bashrc is read by
        # interactive non-login shells. Both are common enough that we prefer
        # whichever already exists; if neither does, create ~/.bashrc.
        if [ -f "$HOME/.bash_profile" ]; then
            RC_FILE="$HOME/.bash_profile"
        else
            RC_FILE="$HOME/.bashrc"
        fi
        ;;
    fish)
        echo "install_path.sh: fish shell detected"
        echo "Run this in a fish shell (it's idempotent):"
        echo "  fish_add_path $SCRIPTS_DIR"
        exit 0
        ;;
    *)
        echo "install_path.sh: unknown shell '$SHELL_NAME'"
        echo "Add this line manually to your shell's rc file:"
        echo "  $EXPORT_LINE"
        exit 0
        ;;
esac

# Verify the scripts dir actually exists before we add it
if [ ! -d "$SCRIPTS_DIR" ]; then
    echo "install_path.sh: scripts dir $SCRIPTS_DIR does not exist" >&2
    echo "         Did you symlink the apparelhub skill into ~/.claude/skills/?" >&2
    echo "         See the README's Install section." >&2
    exit 2
fi

# Idempotency check — look for our marker, not the export line itself (so a
# user could rephrase the export line without us treating it as missing)
if [ -f "$RC_FILE" ] && grep -qF "$MARKER" "$RC_FILE"; then
    echo "install_path.sh: PATH entry already present in $RC_FILE — no-op"
    echo "If ah_check still isn't found, restart your shell or run: source $RC_FILE"
    exit 0
fi

# Append marker + export line
printf '\n%s\n%s\n' "$MARKER" "$EXPORT_LINE" >> "$RC_FILE"

echo "install_path.sh: added to $RC_FILE"
echo ""
echo "To pick up the change in your current shell, run:"
echo "  source $RC_FILE"
echo ""
echo "Or open a new terminal."
