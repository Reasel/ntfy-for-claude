---
name: ntfy-notify
description: Send numbered-choice notifications to the user's phone via ntfy and wait for their response. Use this skill whenever Claude Code needs user input, confirmation, a decision between options, or approval during an autonomous/background session — especially when the user may be away from their terminal. Trigger this for any "ask the user" moment, permission checks, ambiguous decisions, error recovery choices, or when you want to keep the user in the loop on progress. Also use when the user explicitly mentions ntfy, phone notifications, or remote responses.
---

# ntfy Notify — Phone-Based Input for Claude Code

Send questions with numbered options to the user's phone via [ntfy](https://ntfy.sh) and wait for their reply. This lets you keep working autonomously while the user responds from anywhere.

## Prerequisites

- `curl`, `jq`, and `base64` must be available (standard on most systems)
- The user should have the ntfy app installed on their phone ([Android](https://play.google.com/store/apps/details?id=io.heckel.ntfy) / [iOS](https://apps.apple.com/app/ntfy/id1625396347)) and be subscribed to their topic.

### Required Environment Variable

| Variable | Description |
|----------|-------------|
| `NTFY_TOPIC` | Your unique ntfy topic name |

### Optional Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `NTFY_SERVER` | `https://ntfy.sh` | Server URL. Set for self-hosted instances |
| `NTFY_TIMEOUT` | `300` | Seconds to wait for a reply |

### Authentication (choose one method or skip for public topics)

| Variable | Description |
|----------|-------------|
| `NTFY_TOKEN` | **Preferred.** An ntfy access token (e.g., `tk_AgQdq7mVBoFD37zQVN29RhuMzNIz2`). Created via `ntfy token add <username>` on self-hosted servers, or in Account > Access Tokens on the web UI. |
| `NTFY_USER` + `NTFY_PASSWORD` | Basic auth fallback. If both `NTFY_TOKEN` and user/password are set, token wins. |

Auth is applied to **both** outgoing notifications **and** action button callbacks, so replies work correctly on access-controlled topics.

### Self-Hosted Server Setup

For a private self-hosted ntfy server with access control:

1. **Create a dedicated user** for Claude Code:
   ```bash
   ntfy user add claude-bot
   ```

2. **Grant read-write access** to your topic:
   ```bash
   ntfy access claude-bot claude-code-topic rw
   ```

3. **Generate an access token** (avoids storing passwords):
   ```bash
   ntfy token add claude-bot
   # Output: tk_... (save this)
   ```

4. **Set your env vars**:
   ```bash
   export NTFY_SERVER="https://ntfy.yourdomain.com"
   export NTFY_TOPIC="claude-code-topic"
   export NTFY_TOKEN="tk_..."
   ```

5. **In the phone app**, add the subscription using the same server URL and topic, logging in with the user credentials or a separate read-access token.

## When to Use

- You need the user to **choose between options** (e.g., which approach to take, which file to modify)
- You need **confirmation or approval** before a destructive/irreversible action
- You hit an **ambiguous situation** and want guidance
- You want to **report progress** and optionally get feedback
- The user is likely **away from the terminal** (long-running task, background session)

## How to Use

### Step 1: Decide your question and options

Keep the message short — the user reads it on a phone. The `--options` flag handles numbering and button creation for you, so just provide a clear question and short option labels.

Good examples:
- `"🤖 Found 3 failing tests after refactor."` with `--options "Fix tests" "Revert" "Skip"`
- `"⚠️ Delete the staging database?"` with `--options "Yes, delete" "No, abort"`
- `"🤖 Which auth library?"` with `--options "Passport.js" "Auth0 SDK" "Roll our own"`

### Step 2: Run the script with options

Pass `--options` followed by the label for each choice. These become **tappable buttons** on the notification — the user just taps instead of typing.

```bash
bash /path/to/ntfy-notify/scripts/ntfy_ask.sh \
    "🤖 Found 3 failing tests after refactor." \
    --options "Fix tests" "Revert" "Skip"
```

This sends a notification that looks like:

```
🤖 Found 3 failing tests after refactor.

1) Fix tests
2) Revert
3) Skip

Tap a button or reply with a number (1-3):
```

...with three tappable buttons at the bottom: `1) Fix tests`, `2) Revert`, `3) Skip`.

**ntfy supports up to 3 action buttons.** If you pass more than 3 options, the first 3 get buttons and the rest appear in the message text only (the user types the number for those).

You can also call it **without `--options`** for free-text input:

```bash
bash /path/to/ntfy-notify/scripts/ntfy_ask.sh "🤖 What branch name should I use?"
```

The script will:
1. Send the message as a push notification with tappable buttons (if options provided)
2. Wait for a reply on the same topic (polling every 3 seconds)
3. Print the user's response to stdout and exit 0
4. Print `TIMEOUT` and exit 1 if no response within the timeout

### Step 3: Parse the response

When the user taps a button, the response is just the number (e.g., `1`). When they type manually, it could be `1`, `1)`, or even a word. Handle gracefully:
- Trim whitespace
- Accept `1`, `1)`, `1.` style answers
- If the response doesn't match any option, send a follow-up asking them to try again
- If `TIMEOUT` is returned, either proceed with a safe default or retry

### Notification-Only Mode (no response needed)

For status updates where you don't need a reply, use the `--notify` flag:

```bash
bash /path/to/ntfy-notify/scripts/ntfy_ask.sh --notify "✅ Build complete. All 47 tests passing."
```

This sends the notification and exits immediately without waiting.

## How the Reply Works

The notification includes an **inline Reply action button** (via ntfy's `Actions` header). The flow is:

1. The script sends your question to the ntfy topic with an attached HTTP reply action
2. The user's phone shows a push notification with a **"Reply"** button
3. The user taps Reply, types their number (e.g., `2`), and hits Send
4. ntfy POSTs their response back to the same topic as a new message
5. The script (polling every 3s) picks up the new message and prints it to stdout
6. Claude Code reads the response and continues

On **Android**, the Reply button appears directly on the notification — you can respond without even opening the app. On **iOS**, tapping the notification opens the ntfy app where you can reply from there.

If the user doesn't reply within the timeout (default 5 minutes), the script prints `TIMEOUT` and exits with code 1. Claude Code should then either use a safe default or send a follow-up.

## Tips

- **Keep messages short**: Phone screens are small. Lead with the key question.
- **Use emoji**: They help scanability on notifications. 🤖 for Claude, ⚠️ for warnings, ✅ for success, ❌ for errors.
- **Number every option**: Even yes/no should be `1) Yes  2) No` — it's faster to type a digit.
- **Batch decisions**: If you have multiple small questions, group them into one notification when possible.
- **Set a safe default**: For non-critical choices, mention the default: "Reply 1-3 (default: 1 in 5min)"

## Security

- **Use HTTPS always.** The script warns if you're sending auth over plain HTTP, but you should ensure your server is behind TLS. Credentials and tokens travel in HTTP headers.
- **Prefer token auth over passwords.** Tokens can be revoked individually without changing the account password. Create one token per integration so you can rotate them independently.
- **Use minimal permissions.** Create a dedicated ntfy user for Claude Code with `rw` access only to the specific topic it needs — not a broad admin account.
- **Don't send secrets in message bodies.** Use ntfy for decisions and status updates only. Passwords, API keys, and PII should never go through notification bodies.
- **For public ntfy.sh**: If you don't self-host, your topic name is effectively a shared secret. Use a long random string (e.g., `claude-a8f3c9b2e1d7`). Anyone who guesses the topic name can read and write to it.
- **For self-hosted servers**: Enable access control (`auth-default-access: deny-all` in server.yml) so topics are private by default. This is the most secure option.
- **Rotate tokens periodically.** You can regenerate tokens with `ntfy token add` and update the env var.
