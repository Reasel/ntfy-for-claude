# 📱 ntfy-notify — Phone Notifications for Claude Code

Send push notifications with tappable response buttons to your phone from [Claude Code](https://docs.anthropic.com/en/docs/claude-code) sessions. Reply to decisions, approvals, and questions without leaving the couch.

![ntfy](https://img.shields.io/badge/ntfy-push%20notifications-blue)
![Shell](https://img.shields.io/badge/shell-bash-green)
![License](https://img.shields.io/badge/license-MIT-orange)

## How It Works

```
┌──────────────┐     POST question     ┌──────────────┐     push      ┌──────────┐
│  Claude Code │ ──────────────────────▶│  ntfy server │ ────────────▶ │  📱 Phone │
│  (terminal)  │                        │  (self-host  │               │  (ntfy   │
│              │◀─────────────────────  │   or ntfy.sh)│ ◀──────────── │   app)   │
└──────────────┘     poll for reply     └──────────────┘   tap button  └──────────┘
```

1. Claude Code hits a decision point and sends a notification with numbered options
2. Your phone buzzes with **tappable buttons** (up to 3) — e.g., `1) Fix tests`, `2) Revert`, `3) Skip`
3. You tap a button (or type a number) and the reply goes back to the same ntfy topic
4. The script picks up your response and Claude Code continues working

No typing needed — just tap a button on the notification and you're done.

## Quick Start

### 1. Install the skill

```bash
# Clone the repo
git clone https://github.com/YOUR_USERNAME/ntfy-notify.git

# Copy to Claude Code's user skills directory
mkdir -p ~/.claude/skills
cp -r ntfy-notify ~/.claude/skills/ntfy-notify
```

### 2. Install the ntfy app on your phone

- **Android**: [Google Play](https://play.google.com/store/apps/details?id=io.heckel.ntfy)
- **iOS**: [App Store](https://apps.apple.com/app/ntfy/id1625396347)

### 3. Choose your setup

<details>
<summary><strong>Option A: Public ntfy.sh (quick & easy)</strong></summary>

No server setup needed. Just pick a unique topic name (it acts as a shared secret):

```bash
# Add to your shell profile (~/.bashrc, ~/.zshrc, etc.)
export NTFY_TOPIC="claude-code-$(openssl rand -hex 6)"

# Print it so you can subscribe in the phone app
echo "Subscribe to this topic in ntfy app: $NTFY_TOPIC"
```

In the ntfy phone app, tap **+** and subscribe to that exact topic name.

> ⚠️ Topics on ntfy.sh are public — anyone who guesses the name can read/write.
> Use a long random string and don't send sensitive data in messages.

</details>

<details>
<summary><strong>Option B: Self-hosted ntfy with auth (recommended)</strong></summary>

This is the secure option. You control the server and topics are locked down with access control.

**On your ntfy server:**

```bash
# Create a user for Claude Code
ntfy user add claude-bot

# Create a topic with read-write access
ntfy access claude-bot claude-code rw

# Generate an access token
ntfy token add claude-bot
# → Output: tk_... (save this!)
```

**On your machine:**

```bash
# Add to your shell profile (~/.bashrc, ~/.zshrc, etc.)
export NTFY_SERVER="https://ntfy.yourdomain.com"
export NTFY_TOPIC="claude-code"
export NTFY_TOKEN="tk_your_token_here"
```

**In the phone app**, add a subscription:
- Server: `https://ntfy.yourdomain.com`
- Topic: `claude-code`
- Log in with your user credentials or a separate read-access token

</details>

### 4. Test it

```bash
# Send a test notification (no reply expected)
bash ~/.claude/skills/ntfy-notify/scripts/ntfy_ask.sh --notify "🤖 ntfy-notify is working!"

# Send a question with tappable buttons
bash ~/.claude/skills/ntfy-notify/scripts/ntfy_ask.sh \
    "🤖 Test question — pick an option:" \
    --options "Option A" "Option B" "Option C"
```

If everything is configured correctly, you'll get a push notification on your phone. Tap a button and you should see the response printed in your terminal.

## Usage

### Ask with tappable buttons (up to 3)

```bash
ntfy_ask.sh "🤖 Which database?" --options "PostgreSQL" "SQLite" "MongoDB"
```

The user sees buttons they can tap — the response is just the number (`1`, `2`, or `3`).

### Ask with more than 3 options

```bash
ntfy_ask.sh "🤖 Pick a framework:" --options "React" "Vue" "Svelte" "Angular"
```

The first 3 options get tappable buttons. The 4th appears in the message text and the user types `4`.

### Free-text question (no buttons)

```bash
ntfy_ask.sh "🤖 What should I name the new module?"
```

Shows a Reply button — the user types their answer.

### Notification only (no reply expected)

```bash
ntfy_ask.sh --notify "✅ Deployment complete. All 47 tests passing."
```

Sends the notification and exits immediately.

### Handling the response

```bash
RESPONSE=$(bash ~/.claude/skills/ntfy-notify/scripts/ntfy_ask.sh \
    "🤖 3 tests failing. What should I do?" \
    --options "Fix them" "Skip" "Abort")

case "$RESPONSE" in
    1) echo "Fixing tests..." ;;
    2) echo "Skipping..." ;;
    3) echo "Aborting..." ;;
    *) echo "Unexpected response: $RESPONSE" ;;
esac
```

### Exit codes

| Code | Meaning |
|------|---------|
| `0`  | Reply received (printed to stdout) |
| `1`  | Timeout — no reply within `NTFY_TIMEOUT` seconds (prints `TIMEOUT` to stdout) |
| `2`  | Missing dependency (`curl`, `jq`, or `base64`) |
| `3`  | Failed to send notification (network error or auth failure) |

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `NTFY_TOPIC` | ✅ | — | Topic name to publish/subscribe to |
| `NTFY_SERVER` | | `https://ntfy.sh` | Server URL (set for self-hosted) |
| `NTFY_TOKEN` | | — | Access token auth (preferred) |
| `NTFY_USER` | | — | Username for basic auth |
| `NTFY_PASSWORD` | | — | Password for basic auth (requires `NTFY_USER`) |
| `NTFY_TIMEOUT` | | `300` | Seconds to wait for a reply |

If both `NTFY_TOKEN` and `NTFY_USER`/`NTFY_PASSWORD` are set, token auth takes priority.

## How Claude Code Uses This

Once the skill is installed, Claude Code can use it whenever it needs your input during an autonomous session. The `SKILL.md` file tells Claude when and how to call the script.

**Example — Claude Code is refactoring your codebase and hits a problem:**

```
🤖 Refactoring auth module. Found circular dependency between
   auth.ts and session.ts.

1) Break cycle by extracting shared types
2) Merge into single module
3) Pause and show me the dependency graph

Tap a button or reply with a number (1-3):
```

You tap `1` on your phone, Claude Code reads the response and continues working.

**Example — Claude Code wants confirmation before something destructive:**

```
⚠️ About to drop and recreate the migrations table.
   This will lose migration history.

1) Yes, proceed
2) No, abort

Tap a button or reply with a number (1-2):
```

## Security

- **Always use HTTPS.** Auth credentials travel in HTTP headers. The script warns if you're using plain HTTP with auth.
- **Prefer token auth.** Tokens can be revoked individually without changing account passwords. Create one per integration.
- **Minimal permissions.** Give the Claude Code user `rw` access only to its specific topic — never use an admin account.
- **No secrets in messages.** Use ntfy for decisions and status updates only. Don't send passwords, API keys, or PII.
- **Self-host for maximum security.** Set `auth-default-access: deny-all` in your ntfy `server.yml` so topics are private by default.
- **Rotate tokens periodically.** Regenerate with `ntfy token add` and update the env var.

## Requirements

- **bash** (4.0+)
- **curl**
- **jq**
- **base64** (part of coreutils)

All of these are pre-installed on macOS and most Linux distributions.

## Platform Notes

| Platform | Button Experience |
|----------|-------------------|
| **Android** | Buttons appear directly on the notification. One tap, done. No need to open the app. |
| **iOS** | Tapping the notification opens the ntfy app, where you tap the button. Slightly more steps but still fast. |

## Troubleshooting

**"ERROR: Set NTFY_TOPIC environment variable"**
→ Export `NTFY_TOPIC` in your shell profile and restart your terminal.

**Notification sent but no buttons appear**
→ Make sure you're using the ntfy app (not just browser notifications). Action buttons require the native app.

**Button taps don't register / get 403**
→ Your topic likely has access control. Set `NTFY_TOKEN` or `NTFY_USER`/`NTFY_PASSWORD` so the button callbacks can authenticate. The script injects auth into the action headers automatically.

**Timeout even though you replied**
→ Check that you're replying to the correct topic. If using auth, ensure the phone app is also authenticated to the same topic.

**"WARNING: Sending credentials over non-HTTPS connection"**
→ Switch `NTFY_SERVER` to an `https://` URL. Credentials in headers are visible over plain HTTP.

## License

MIT — see [LICENSE](LICENSE).
