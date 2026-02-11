# takopi-railway

Railway deployment for [takopi](https://github.com/banteg/takopi) - Telegram bridge for AI coding agents.

## One-Click Deploy

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/F5m5Aw?utm_medium=integration&utm_source=template&utm_campaign=generic)

> **Note:** After deploying, add a volume mounted at `/data` in Railway's dashboard.

## Required Environment Variables

```bash
# Telegram (required)
TAKOPI__TRANSPORTS__TELEGRAM__BOT_TOKEN=your_bot_token
TAKOPI__TRANSPORTS__TELEGRAM__CHAT_ID=your_chat_id

# Engine API keys (at least one required)
ANTHROPIC_API_KEY=your_anthropic_key

# Optional
OPENAI_API_KEY=your_openai_key

# GitHub (optional)
# - PAT (works as-is)
GITHUB_TOKEN=your_github_token
# - OR GitHub App (auto-refreshed installation token)
GITHUB_APP_ID=12345
# Railway-friendly options for the private key (choose one):
# - Base64 (recommended on Railway)
GITHUB_APP_PRIVATE_KEY_B64=LS0tLS1CRUdJTiBQUklWQVRFIEtFWS0tLS0tCk1JS...
# - PEM text (use \\n for newlines; Railway may wrap in quotes and that's OK)
GITHUB_APP_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\\n...\\n-----END PRIVATE KEY-----"
# - File path (if you can provide a file in the container)
GITHUB_APP_PRIVATE_KEY_FILE=/path/to/private-key.pem
GITHUB_APP_INSTALLATION_ID=987654

# Optional GitHub App tuning
# - Wait for token before cloning TAKOPI_REPOS
GITHUB_TOKEN_WAIT_SECONDS=180
# - Refresh a bit before expiry (seconds)
GITHUB_TOKEN_REFRESH_SAFETY_SECONDS=300

# Optional: repos to clone on startup (comma-separated)
TAKOPI_REPOS=owner/repo1,owner/repo2

# ngrok (optional)
# - Authenticates the ngrok CLI on boot and persists config under /data
NGROK_AUTHTOKEN=your_ngrok_authtoken
# Optional: provide token via file path (e.g. Railway secret file)
NGROK_AUTHTOKEN_FILE=/path/to/ngrok_authtoken
# Optional: override config location (default: /data/.config/ngrok/ngrok.yml)
NGROK_CONFIG=/data/.config/ngrok/ngrok.yml
```

### GitHub App Token Notes

When using `GITHUB_APP_*` variables, an installation token is fetched on boot and periodically refreshed inside the container. The current token is written to `/run/github-token`.
For scripts/tools, you can read that file directly or run `github-token` to print the current token (falls back to `GITHUB_TOKEN` in PAT mode).

For private repo cloning / API access, make sure your GitHub App has at least **Repository permissions → Contents: Read** (and is installed on the target repos).

### Creating Your Telegram Bot

Before deploying, you need to create a bot with BotFather:

1. Open Telegram and search for [@BotFather](https://t.me/botfather)
2. Start a chat and send `/newbot`
3. Follow the prompts:
   - Choose a display name (e.g., "My Takopi Bot")
   - Choose a unique username ending in "bot" (e.g., "mytakopi_bot")
4. BotFather will reply with your bot token (looks like `1234567890:ABCdefGHIjklMNOpqrsTUVwxyz`)
5. Copy this token and use it as `TAKOPI__TRANSPORTS__TELEGRAM__BOT_TOKEN`

**Important:** Keep your bot token secret! Anyone with this token can control your bot.

### Getting Your Chat ID

For DMs, your chat ID is the same as your user ID. To get it:

1. Message [@userinfobot](https://t.me/userinfobot) on Telegram
2. It will reply with your user ID
3. Use that number as `TAKOPI__TRANSPORTS__TELEGRAM__CHAT_ID`

## Structure

```
/data/
├── github/         # GitHub repos only
└── knowledge/      # Knowledge vault (notes, todos, memory)
    ├── 00-inbox/
    ├── 01-todos/
    ├── 02-projects/
    ├── 03-resources/   # Layer 2: long-term knowledge
    ├── 04-claude-code/skills/
    ├── 05-prompts/
    ├── 06-meetings/
    ├── 07-logs/agent/  # Layer 1: daily logs
    ├── 07-logs/daily/
    ├── CLAUDE.md
    └── MEMORY.md
```

## Default Skills

- `skill-creator` - Create new skills
- `cron` - Manage scheduled automations

## Engines

Pre-installed:
- Claude Code (`@anthropic-ai/claude-code`)
- Codex (`@openai/codex`)
