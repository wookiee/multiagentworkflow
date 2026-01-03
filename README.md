# Multi-Agent Claude Code Workflow

A system where multiple Claude Code agents collaborate on GitHub issues through an automated PR-based workflow.

## How It Works

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  GitHub Issue   │────▶│   Coder Agent   │────▶│   Pull Request  │
│   Assigned      │     │  Implements PR  │     │    Created      │
└─────────────────┘     └─────────────────┘     └─────────────────┘
                                                        │
                                                        ▼
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│    PR Merged    │◀────│  Your Approval  │◀────│ Reviewer Agent  │
│                 │     │   (Required)    │     │  Reviews Code   │
└─────────────────┘     └─────────────────┘     └─────────────────┘
                                                        │
                                                        ▼
                                                ┌─────────────────┐
                                                │ Changes Needed? │
                                                │   Loop Back     │
                                                └─────────────────┘
```

**Workflow:**
1. Assign a GitHub issue to `@coder-bot`
2. Coder agent implements the solution and creates a PR
3. CI runs tests on the PR
4. Reviewer agent reviews the code
5. If changes needed: Coder addresses feedback, loop continues
6. If approved: You provide final approval, PR is merged

**Safeguards:**
- Maximum 5 review iterations before human escalation
- 24-hour timeout before human escalation
- Tests must pass before Reviewer will review

---

## Prerequisites

- A cloud VPS (Ubuntu 22.04+ recommended) with Docker installed
- Two GitHub accounts for the bots (or one, if you want a single bot)
- An Anthropic API key
- A domain name (optional, but recommended for HTTPS webhooks)

---

## Setup Instructions

### Step 1: Create GitHub Bot Accounts

You need two GitHub accounts to act as your agents:

1. **Create the Coder bot account**
   - Go to https://github.com/join
   - Create account (e.g., `your-org-coder-bot`)
   - Verify email
   - Go to Settings → Developer settings → Personal access tokens → Tokens (classic)
   - Generate new token with `repo` scope
   - Save the token securely

2. **Create the Reviewer bot account**
   - Repeat the above for a second account (e.g., `your-org-reviewer-bot`)
   - Generate and save its token

3. **Add bots as repository collaborators**
   - Go to your target repository → Settings → Collaborators
   - Add both bot accounts with "Write" access

### Step 2: Get an Anthropic API Key

1. Go to https://console.anthropic.com
2. Sign up or log in
3. Navigate to API Keys
4. Create a new API key
5. Save it securely

**Cost Note:** Each agent interaction uses API tokens. Estimated costs:
- Simple bug fix: $0.50-2.00
- Medium feature: $2-10
- Complex feature with multiple review cycles: $10-50+

### Step 3: Set Up Your VPS

#### 3.1 Provision a Server

Recommended specs:
- Ubuntu 22.04 LTS
- 4GB RAM minimum
- 20GB disk
- Providers: DigitalOcean, Linode, AWS EC2, etc.

#### 3.2 Install Docker

```bash
# Connect to your server
ssh root@your-server-ip

# Update system
apt update && apt upgrade -y

# Install Docker
curl -fsSL https://get.docker.com | sh

# Install Docker Compose
apt install docker-compose-plugin -y

# Verify installation
docker --version
docker compose version
```

#### 3.3 Clone This Repository

```bash
# Create directory for the project
mkdir -p /opt/multiagent
cd /opt/multiagent

# Clone the repository
git clone https://github.com/YOUR_USERNAME/multiagentworkflow.git .
```

#### 3.4 Configure Environment Variables

```bash
# Copy the example environment file
cp .env.example .env

# Edit with your values
nano .env
```

Fill in your `.env` file:

```bash
# Anthropic API Key
ANTHROPIC_API_KEY=sk-ant-api03-your-key-here

# GitHub Tokens (from Step 1)
CODER_GITHUB_TOKEN=ghp_your-coder-token
REVIEWER_GITHUB_TOKEN=ghp_your-reviewer-token

# Git identity for commits
CODER_GIT_NAME=Coder Bot
CODER_GIT_EMAIL=coder-bot@yourdomain.com
REVIEWER_GIT_NAME=Reviewer Bot
REVIEWER_GIT_EMAIL=reviewer-bot@yourdomain.com

# n8n configuration
N8N_HOST=your-domain.com  # or server IP
N8N_PROTOCOL=https        # use 'http' if no SSL
WEBHOOK_URL=https://your-domain.com:5678

# n8n authentication (CHANGE THESE!)
N8N_USER=admin
N8N_PASSWORD=your-secure-password

# Workflow limits
MAX_ITERATIONS=5
TIMEOUT_HOURS=24
```

### Step 4: Set Up SSL (Recommended)

For production, you should use HTTPS. Here's a simple setup with Caddy:

```bash
# Install Caddy
apt install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
apt update
apt install caddy -y

# Configure Caddy
cat > /etc/caddy/Caddyfile << 'EOF'
your-domain.com {
    reverse_proxy localhost:5678
}
EOF

# Restart Caddy
systemctl restart caddy
```

Update your `.env`:
```bash
N8N_HOST=your-domain.com
N8N_PROTOCOL=https
WEBHOOK_URL=https://your-domain.com
```

### Step 5: Build and Start Services

```bash
cd /opt/multiagent

# Build the agent Docker images
docker compose build

# Start n8n
docker compose up -d n8n

# Verify n8n is running
docker compose logs n8n
```

Access n8n at `https://your-domain.com` (or `http://your-server-ip:5678`).

### Step 6: Configure n8n Workflows

#### 6.1 Set Up Database

n8n needs a database to track workflow state. The workflow templates use PostgreSQL, but you can use SQLite for simplicity:

**Option A: Use SQLite (simpler)**

Edit `docker-compose.yml` to add SQLite config to n8n:
```yaml
n8n:
  environment:
    - DB_TYPE=sqlite
    - DB_SQLITE_DATABASE=/home/node/.n8n/database.sqlite
```

Then modify the n8n workflow JSON files to use n8n's built-in storage instead of Postgres nodes.

**Option B: Add PostgreSQL (production)**

Add to `docker-compose.yml`:
```yaml
services:
  postgres:
    image: postgres:15
    environment:
      - POSTGRES_USER=n8n
      - POSTGRES_PASSWORD=your-db-password
      - POSTGRES_DB=n8n
    volumes:
      - postgres_data:/var/lib/postgresql/data
    networks:
      - agent-network

volumes:
  postgres_data:
```

Create the workflow state table:
```sql
CREATE TABLE workflow_state (
    id SERIAL PRIMARY KEY,
    issue_number INTEGER,
    pr_number INTEGER,
    issue_title TEXT,
    repository TEXT,
    status TEXT DEFAULT 'pending',
    iteration_count INTEGER DEFAULT 0,
    started_at TIMESTAMP,
    timeout_at TIMESTAMP,
    coder_completed_at TIMESTAMP,
    last_review_at TIMESTAMP,
    escalated_at TIMESTAMP,
    timed_out_at TIMESTAMP
);
```

#### 6.2 Import Workflows

1. Open n8n in your browser
2. Log in with credentials from `.env`
3. Go to Workflows → Import from File
4. Import each file from `n8n/workflows/`:
   - `issue-assigned.json`
   - `pr-review.json`
   - `escalation.json`

#### 6.3 Configure Workflow Credentials

For each imported workflow:

1. Open the workflow
2. Click on nodes that need credentials:
   - **Database nodes**: Configure your Postgres/SQLite connection
   - **Slack nodes**: Add Slack webhook (or replace with email)
3. Update the Execute Command nodes with your environment variables
4. Save and activate each workflow

#### 6.4 Configure Notifications

The workflows include Slack notifications for escalations. To configure:

1. Create a Slack webhook at https://api.slack.com/apps
2. Add the webhook URL to n8n credentials
3. Update the Slack nodes in the workflows

**Alternative**: Replace Slack nodes with:
- Email (SMTP node)
- Discord webhook
- Telegram bot
- Any other n8n-supported service

### Step 7: Configure Your GitHub Repository

#### 7.1 Update GitHub Actions Workflow Files

In your target repository, update the bot usernames in the workflow files.

Edit `.github/workflows/issue-assigned.yml`:
```yaml
if: github.event.assignee.login == 'your-actual-coder-bot-username'
```

Edit `.github/workflows/pr-opened.yml`:
```yaml
if: github.event.pull_request.user.login == 'your-actual-coder-bot-username'
```

Edit `.github/workflows/pr-comment.yml`:
```yaml
if: github.event.review.user.login == 'your-actual-reviewer-bot-username'
```

#### 7.2 Add Repository Secrets

Go to your repository → Settings → Secrets and variables → Actions:

1. Add `N8N_WEBHOOK_URL`: Your n8n webhook URL (e.g., `https://your-domain.com`)

#### 7.3 Configure Branch Protection

Go to Settings → Branches → Add rule for `main`:

- [x] Require a pull request before merging
- [x] Require approvals: 2
- [x] Require status checks to pass: select your CI job
- [x] Include administrators (optional)

### Step 8: Test the System

#### 8.1 Verify Webhooks

1. Create a test issue in your repository
2. Check n8n executions to see if the webhook was received
3. If not, check:
   - GitHub Actions logs
   - n8n is accessible from the internet
   - Firewall allows port 5678 (or your reverse proxy port)

#### 8.2 End-to-End Test

1. Create a simple issue:
   ```
   Title: Add hello world function
   Body: Create a function that returns "Hello, World!"
   ```

2. Assign the issue to `@your-coder-bot`

3. Watch the magic:
   - Check GitHub Actions for the trigger
   - Check n8n executions
   - Check Docker logs: `docker compose logs -f`

4. Monitor the PR creation and review cycle

#### 8.3 Troubleshooting

**Webhook not received:**
```bash
# Check n8n logs
docker compose logs n8n

# Test webhook manually
curl -X POST https://your-domain.com/webhook/issue-assigned \
  -H "Content-Type: application/json" \
  -d '{"test": true}'
```

**Agent container fails:**
```bash
# Run agent manually to see errors
docker compose run --rm coder-agent

# Check if Claude Code is installed
docker compose run --rm coder-agent claude --version
```

**GitHub authentication fails:**
```bash
# Test GitHub token
curl -H "Authorization: token YOUR_TOKEN" https://api.github.com/user
```

---

## Customization

### Adjusting Agent Behavior

Edit the `CLAUDE.md` files in `agents/coder/` and `agents/reviewer/` to customize:
- Review strictness
- Code style preferences
- Testing requirements
- Communication style

### Changing Iteration Limits

Update in `.env`:
```bash
MAX_ITERATIONS=10  # More review cycles allowed
TIMEOUT_HOURS=48   # Longer timeout
```

### Adding More Agents

You can extend this system with additional agents:
- **Tester Agent**: Runs and analyzes test results
- **Documenter Agent**: Updates documentation
- **Security Agent**: Performs security review

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         GitHub                                   │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐              │
│  │   Issues    │  │Pull Requests│  │  Actions    │              │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘              │
└─────────┼────────────────┼────────────────┼─────────────────────┘
          │                │                │
          │    Webhooks    │                │
          ▼                ▼                ▼
┌─────────────────────────────────────────────────────────────────┐
│                        Your VPS                                  │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                         n8n                              │    │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐      │    │
│  │  │Issue Assign │  │  PR Review  │  │ Escalation  │      │    │
│  │  │  Workflow   │  │  Workflow   │  │  Workflow   │      │    │
│  │  └──────┬──────┘  └──────┬──────┘  └─────────────┘      │    │
│  └─────────┼────────────────┼──────────────────────────────┘    │
│            │                │                                    │
│            ▼                ▼                                    │
│  ┌─────────────────┐  ┌─────────────────┐                       │
│  │  Coder Agent    │  │ Reviewer Agent  │                       │
│  │  (Docker)       │  │  (Docker)       │                       │
│  │                 │  │                 │                       │
│  │  - Claude Code  │  │  - Claude Code  │                       │
│  │  - GitHub CLI   │  │  - GitHub CLI   │                       │
│  │  - Git          │  │  - Git          │                       │
│  └─────────────────┘  └─────────────────┘                       │
└─────────────────────────────────────────────────────────────────┘
```

---

## Cost Estimation

| Component | Cost |
|-----------|------|
| VPS (4GB) | ~$20-40/month |
| Anthropic API | Pay per token (see below) |
| GitHub | Free (public repos) or $4/user/month |
| Domain | ~$10-15/year |

**Anthropic API Costs** (Claude Sonnet 3.5):
- Input: $3 / million tokens
- Output: $15 / million tokens

Typical issue implementation: 10k-50k tokens = $0.50-$5.00

---

## Security Considerations

1. **API Keys**: Never commit `.env` to git
2. **GitHub Tokens**: Use fine-grained tokens with minimal permissions
3. **n8n Access**: Use strong passwords, consider IP whitelisting
4. **Agent Isolation**: Agents run in containers with limited permissions
5. **Audit Logging**: n8n keeps execution logs for review

---

## License

MIT
