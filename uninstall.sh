#!/usr/bin/env bash
# uninstall.sh — Remove ntfy-notify from Claude Code user skills.
set -euo pipefail

SKILL_NAME="ntfy-notify"
DEFAULT_DEST="${HOME}/.claude/skills/${SKILL_NAME}"
DEST="${1:-$DEFAULT_DEST}"

if [[ -d "$DEST" ]]; then
    rm -rf "$DEST"
    echo "✅ Removed ${SKILL_NAME} from ${DEST}"
    echo ""
    echo "Note: Your environment variables (NTFY_TOPIC, NTFY_TOKEN, etc.)"
    echo "are still in your shell profile. Remove them manually if no longer needed."
else
    echo "ℹ️  ${SKILL_NAME} not found at ${DEST}. Nothing to remove."
fi
