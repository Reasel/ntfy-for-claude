#!/usr/bin/env bash
# install.sh — Install ntfy-notify as a Claude Code user skill.
#
# Usage:
#   ./install.sh              # Install to ~/.claude/skills/ntfy-notify
#   ./install.sh /custom/path # Install to a custom location
#
set -euo pipefail

SKILL_NAME="ntfy-notify"
DEFAULT_DEST="${HOME}/.claude/skills/${SKILL_NAME}"
DEST="${1:-$DEFAULT_DEST}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
echo "🔍 Checking dependencies..."

MISSING=()
for cmd in curl jq base64; do
    if ! command -v "$cmd" &>/dev/null; then
        MISSING+=("$cmd")
    fi
done

if [[ ${#MISSING[@]} -gt 0 ]]; then
    echo "⚠️  Missing dependencies: ${MISSING[*]}"
    echo "   Install them before using the skill."
else
    echo "   ✅ All dependencies found (curl, jq, base64)"
fi

# ---------------------------------------------------------------------------
# Install
# ---------------------------------------------------------------------------
echo ""
echo "📦 Installing ${SKILL_NAME} to ${DEST} ..."

mkdir -p "$(dirname "$DEST")"

if [[ -d "$DEST" ]]; then
    echo "   ⚠️  Existing installation found. Replacing..."
    rm -rf "$DEST"
fi

# Copy skill files (exclude repo-only files)
mkdir -p "$DEST/scripts"
cp "$SCRIPT_DIR/SKILL.md" "$DEST/SKILL.md"
cp "$SCRIPT_DIR/scripts/ntfy_ask.sh" "$DEST/scripts/ntfy_ask.sh"
chmod +x "$DEST/scripts/ntfy_ask.sh"

echo "   ✅ Skill installed to ${DEST}"

# ---------------------------------------------------------------------------
# Check environment
# ---------------------------------------------------------------------------
echo ""
echo "🔧 Checking environment..."

if [[ -z "${CLAUDE_NTFY_TOPIC:-}" ]]; then
    AUTO_TOPIC="claude-$(echo -n "$(hostname)-$(whoami)" | sha256sum | cut -c1-12)"
    echo "   ℹ️  CLAUDE_NTFY_TOPIC is not set. Will auto-generate: ${AUTO_TOPIC}"
    echo "      Subscribe to this topic in your ntfy app."
    echo ""
    echo "   To set a custom topic, add to your shell profile (~/.bashrc, ~/.zshrc, etc.):"
    echo ""
    echo "     export CLAUDE_NTFY_TOPIC=\"your-custom-topic\""
    echo ""
    echo "   For self-hosted servers, also set:"
    echo "     export CLAUDE_NTFY_SERVER=\"https://ntfy.yourdomain.com\""
    echo "     export CLAUDE_NTFY_TOKEN=\"tk_your_token_here\""
    echo ""
else
    echo "   ✅ CLAUDE_NTFY_TOPIC is set: ${CLAUDE_NTFY_TOPIC}"
    if [[ -n "${CLAUDE_NTFY_SERVER:-}" ]]; then
        echo "   ✅ CLAUDE_NTFY_SERVER: ${CLAUDE_NTFY_SERVER}"
    else
        echo "   ℹ️  CLAUDE_NTFY_SERVER not set (will use https://ntfy.sh)"
    fi
    if [[ -n "${CLAUDE_NTFY_TOKEN:-}" ]]; then
        echo "   ✅ CLAUDE_NTFY_TOKEN is set"
    elif [[ -n "${CLAUDE_NTFY_USER:-}" ]]; then
        echo "   ✅ CLAUDE_NTFY_USER is set (basic auth)"
    else
        echo "   ℹ️  No auth configured (public topic mode)"
    fi
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Installation complete!"
echo ""
echo "Next steps:"
echo "  1. Optionally set CLAUDE_NTFY_TOPIC, CLAUDE_NTFY_SERVER, CLAUDE_NTFY_TOKEN in your shell profile"
echo "  2. Subscribe to your topic in the ntfy phone app"
echo "  3. Test it:"
echo "     bash ${DEST}/scripts/ntfy_ask.sh --notify \"🤖 Hello from Claude Code!\""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
