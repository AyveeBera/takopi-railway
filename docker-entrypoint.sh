#!/bin/bash
set -e

# --- Takopi config ---
CONFIG_DIR="$HOME/.takopi"
CONFIG_FILE="$CONFIG_DIR/takopi.toml"

mkdir -p "$CONFIG_DIR"

# Seed config file - env vars override via pydantic-settings at runtime
cat > "$CONFIG_FILE" << 'EOF'
default_engine = "claude"
transport = "telegram"
watch_config = true

[transports.telegram]
bot_token = "placeholder"
chat_id = 0
session_mode = "chat"
show_resume_line = false

[transports.telegram.files]
enabled = true
auto_put = true

[transports.telegram.topics]
enabled = false
scope = "auto"

[codex]
extra_args = ["-c", "notify=[]", "--dangerously-bypass-approvals-and-sandbox"]

[claude]
model = "opus"
allowed_tools = ["Bash", "Read", "Edit", "Write", "WebSearch", "WebFetch"]
use_api_billing = true
EOF

# --- GitHub CLI auth ---
if [ -n "$GITHUB_TOKEN" ]; then
  GITHUB_TOKEN="${GITHUB_TOKEN//\"/}"
  echo "Attempting GitHub CLI auth (token length: ${#GITHUB_TOKEN})..."
  if gh_output=$(echo "$GITHUB_TOKEN" | gh auth login --with-token 2>&1); then
    echo "✓ GitHub CLI authenticated"
    gh auth setup-git
    echo "✓ Git configured to use GitHub CLI authentication"
  else
    echo "⚠ GitHub CLI auth failed - continuing without GitHub integration"
    echo "  Error: $gh_output"
    echo "  Hint: Ensure GITHUB_TOKEN has 'repo' scope. Generate at: https://github.com/settings/tokens"
  fi
fi

# --- Codex CLI auth (optional) ---
if [ -n "$OPENAI_API_KEY" ]; then
  OPENAI_API_KEY="${OPENAI_API_KEY//\"/}"
  echo "Attempting Codex CLI auth (token length: ${#OPENAI_API_KEY})..."
  if codex_output=$(echo "$OPENAI_API_KEY" | codex login --with-api-key 2>&1); then
    echo "✓ Codex CLI authenticated"
  else
    echo "⚠ Codex CLI auth failed - continuing without Codex"
    echo "  Error: $codex_output"
    echo "  Hint: Ensure OPENAI_API_KEY is valid. Generate at: https://platform.openai.com/api-keys"
  fi
fi

# --- Knowledge vault bootstrap ---
VAULT="${KNOWLEDGE_PATH:-/data/knowledge}"

dirs=(
  00-inbox
  01-todos
  02-projects
  03-resources
  04-claude-code/skills
  05-prompts
  06-meetings
  07-logs/agent
  07-logs/daily
  _templates
  _assets
)

for d in "${dirs[@]}"; do
  mkdir -p "$VAULT/$d"
done

# MEMORY.md
if [ ! -f "$VAULT/MEMORY.md" ]; then
  cat > "$VAULT/MEMORY.md" << 'MEMO'
# Memory

Persistent context for the agent. Updated as significant things are learned.
MEMO
fi

# Todo files
[ -f "$VAULT/01-todos/inbox.md" ]  || echo "# Inbox"   > "$VAULT/01-todos/inbox.md"
[ -f "$VAULT/01-todos/active.md" ] || echo "# Active"  > "$VAULT/01-todos/active.md"
[ -f "$VAULT/01-todos/arxiv.md" ]  || echo "# Archive" > "$VAULT/01-todos/arxiv.md"

# Vault CLAUDE.md (agent memory instructions)
if [ ! -f "$VAULT/CLAUDE.md" ]; then
  cat > "$VAULT/CLAUDE.md" << 'VEOF'
# Knowledge Vault

## Directory Structure

```
/data/
├── github/      # GitHub repos ONLY
└── knowledge/      # Everything else (notes, docs, memory)
```

## Where Things Go

### `/data/github/` — GitHub Repos Only
- Clone all GitHub repos here
- All coding work happens here

### `/data/knowledge/` — Everything Else
- `00-inbox/` — Quick capture, unsorted notes
- `01-todos/` — Task management (inbox.md → active.md → arxiv.md)
- `02-projects/` — Project context and planning docs
- `03-resources/` — Long-term knowledge (Layer 2 memory)
- `04-claude-code/` — Claude configs and skills
- `05-prompts/` — Prompt library
- `06-meetings/` — Meeting notes
- `07-logs/agent/` — Daily agent logs (Layer 1 memory)
- `07-logs/daily/` — Human journal

## Agent Memory

### Layer 1: Daily Agent Logs (`07-logs/agent/YYYY-MM-DD.md`)
Append-only notes. Write here when:
- A decision is made (with rationale)
- User preference discovered
- Important action completed
- Something to follow up on

Format:
```markdown
## HH:MM AM/PM - Topic
Brief factual note. Decision: X. Reason: Y.
```

### Layer 2: Long-term Knowledge (`03-resources/`)
Curated, processed knowledge notes. Significant learnings get promoted here.

### Reading Memory
At session start:
1. Read `07-logs/agent/` for today + yesterday
2. Search `03-resources/` for relevant context
VEOF
fi

echo "✓ Knowledge vault ready at $VAULT"

# --- Symlink Claude skills to persistent volume ---
CLAUDE_DIR="$HOME/.claude"
SKILLS_DIR="$VAULT/04-claude-code/skills"
mkdir -p "$CLAUDE_DIR"
if [ ! -L "$CLAUDE_DIR/skills" ]; then
  ln -sf "$SKILLS_DIR" "$CLAUDE_DIR/skills"
fi

# --- Global CLAUDE.md (agent instructions) ---
if [ ! -f "$CLAUDE_DIR/CLAUDE.md" ]; then
  cat > "$CLAUDE_DIR/CLAUDE.md" << 'GLOBALEOF'
# Global Agent Instructions

## Agent Memory

All sessions write memory to the knowledge vault at `/data/knowledge/`.

### Layer 1: Daily Agent Logs (`/data/knowledge/07-logs/agent/YYYY-MM-DD.md`)
Append-only notes to remember things for future sessions.

IMPORTANT: Proactively and automatically append to daily logs throughout the session without asking. Only ask if unsure whether something qualifies as worth logging.

Write here when:
- A decision is made (with rationale)
- User preference discovered
- Important action completed
- Something to follow up on

Format:
```markdown
## HH:MM AM/PM - Topic
Brief factual note. Decision: X. Reason: Y.
```

### Layer 2: Long-term Knowledge (`/data/knowledge/03-resources/`)
Significant learnings get promoted here as curated notes.

### Reading Memory
At session start (when context matters):
1. Read `/data/knowledge/MEMORY.md` for persistent context
2. Read `/data/knowledge/07-logs/agent/` for today + yesterday
3. Search `/data/knowledge/03-resources/` for relevant context
GLOBALEOF
fi

# --- Install default skills ---
if [ ! -d "$SKILLS_DIR/skill-creator" ]; then
  echo "Installing skill-creator skill..."
  npx --yes skills add https://github.com/anthropics/skills --skill skill-creator --global --yes
fi

# --- Seed cron skill ---
CRON_SKILL="$SKILLS_DIR/cron"
mkdir -p "$CRON_SKILL"
if [ ! -f "$CRON_SKILL/skill.md" ]; then
  cat > "$CRON_SKILL/skill.md" << 'SKILL'
# Cron

Manage scheduled automation for your skills.

## Usage

```
/cron <action>
```

**Actions:**
- `list` — Show all cron jobs
- `add` — Add a new scheduled job
- `remove` — Remove a job
- `sync` — Install crontab.txt to system

## Files

- Source: `04-claude-code/cron/crontab.txt`
- This file is version-controlled and synced to the system crontab

## Process

### /cron list
```bash
crontab -l
```

### /cron add
1. Ask: What skill/command to run?
2. Ask: What schedule? (daily, weekly, custom cron expression)
3. Add entry to `04-claude-code/cron/crontab.txt`
4. Install with `crontab 04-claude-code/cron/crontab.txt`
5. Confirm with `crontab -l`

### /cron remove
1. Show current jobs (numbered)
2. Ask which to remove
3. Edit `04-claude-code/cron/crontab.txt`
4. Reinstall crontab
5. Confirm removal

### /cron sync
```bash
crontab $KNOWLEDGE_PATH/04-claude-code/cron/crontab.txt
```

## Cron Schedule Reference

```
┌───────────── minute (0-59)
│ ┌───────────── hour (0-23)
│ │ ┌───────────── day of month (1-31)
│ │ │ ┌───────────── month (1-12)
│ │ │ │ ┌───────────── day of week (0-6, Sun=0)
│ │ │ │ │
* * * * * command
```

**Common patterns:**
- `0 6 * * *` — Daily at 6am
- `0 8 * * 0` — Weekly on Sunday at 8am
- `0 9 1 * *` — Monthly on 1st at 9am
- `*/15 * * * *` — Every 15 minutes

## Log Output

All cron jobs should append to a log:
```bash
>> $KNOWLEDGE_PATH/07-logs/.cron.log 2>&1
```
SKILL
fi

# Start cron daemon
cron
echo "✓ Cron daemon started"

# --- Clone repos if requested ---
if [ -n "$TAKOPI_REPOS" ]; then
  IFS=',' read -ra REPOS <<< "$TAKOPI_REPOS"
  for repo in "${REPOS[@]}"; do
    name=$(basename "$repo")
    if [ ! -d "/data/github/$name" ]; then
      echo "Cloning $repo..."
      git clone "https://github.com/$repo.git" "/data/github/$name"
    fi
  done
fi

exec "$@"
