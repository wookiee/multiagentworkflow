# Multi-Agent Claude Code Workflow

A system where multiple Claude Code agents collaborate on GitHub issues through an automated PR-based workflow.

## How It Works

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  GitHub Issue   │────▶│  Claudius/ette  │────▶│   Pull Request  │
│   Assigned      │     │  Implements PR  │     │    Created      │
└─────────────────┘     └─────────────────┘     └─────────────────┘
                                                       │
                                                       ▼
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│    PR Merged    │◀────│  Your Approval  │◀────│ Claudius/ette   │
│                 │     │   (Required)    │     │  Reviews Code   │
└─────────────────┘     └─────────────────┘     └─────────────────┘
                                                       │
                                                       ▼
                                               ┌─────────────────┐
                                               │ Changes Needed? │
                                               │   Loop Back     │
                                               └─────────────────┘
```

**Agents:**
- **Claudius** (`@claudiusward`) - Software engineer agent
- **Claudette** (`@claudetteward`) - Software engineer agent

Both agents can assume either the **Coder** or **Reviewer** role dynamically. When one agent creates a PR, the other reviews it.

**Workflow:**
1. Assign a GitHub issue to `@claudiusward` or `@claudetteward`
2. The assigned agent implements the solution and creates a PR
3. CI runs tests on the PR
4. The other agent reviews the code
5. If changes needed: Original agent addresses feedback, loop continues
6. If approved: You provide final approval, PR is merged

**Safeguards:**
- Maximum 5 review iterations before human escalation
- 24-hour timeout before human escalation
- Tests must pass before Reviewer will review

---

## Current Deployment

This system is deployed on `bacchubuntu` via Tailscale. See [DEPLOYMENT.md](DEPLOYMENT.md) for access details and credentials.

---

## Quick Start (For New Repositories)

To add the multi-agent workflow to a new repository:

### 1. Add Bot Collaborators
Go to your repo → Settings → Collaborators → Add:
- `claudiusward` (Write access)
- `claudetteward` (Write access)

### 2. Copy GitHub Actions Workflows
Copy the `.github/workflows/` directory from this repo to your target repo.

### 3. Add Repository Secret
Go to Settings → Secrets → Actions → New secret:
- Name: `N8N_WEBHOOK_URL`
- Value: `http://100.95.141.86:5678`

### 4. Configure Branch Protection
Go to Settings → Branches → Add rule for `main`:
- [x] Require pull request before merging
- [x] Require 2 approvals
- [x] Require status checks to pass

### 5. Create an Issue
Create an issue and assign it to `@claudiusward` or `@claudetteward`.

---

## Repository Structure

```
multiagentworkflow/
├── agents/
│   ├── claudius/           # Claudius agent container
│   │   ├── CLAUDE.md       # Agent instructions (coder + reviewer)
│   │   ├── Dockerfile      # Container definition
│   │   └── entrypoint.sh   # Startup script
│   └── claudette/          # Claudette agent container
│       ├── CLAUDE.md       # Agent instructions (coder + reviewer)
│       ├── Dockerfile      # Container definition
│       └── entrypoint.sh   # Startup script
├── .github/workflows/      # GitHub Actions for triggering agents
│   ├── issue-assigned.yml  # Triggers on issue assignment
│   ├── pr-opened.yml       # Triggers reviewer on PR
│   ├── pr-comment.yml      # Handles review responses
│   └── ci.yml              # CI pipeline template
├── n8n/workflows/          # n8n workflow definitions
│   ├── issue-assigned.json # Coder workflow
│   ├── pr-review.json      # Reviewer workflow
│   └── escalation.json     # Timeout/escalation workflow
├── docker-compose.yml      # Service definitions
├── .env.example            # Environment template
├── DEPLOYMENT.md           # Deployment details & credentials
└── README.md               # This file
```

---

## Prerequisites

- A server with Docker installed (Ubuntu 22.04+ recommended)
- Two GitHub accounts for the agents
- An Anthropic API key
- Network access to the server (Tailscale, VPN, or public IP)

---

## Full Setup Instructions

### Step 1: Create GitHub Agent Accounts

1. Create two GitHub accounts (e.g., `claudiusward`, `claudetteward`)
2. For each account:
   - Go to Settings → Developer settings → Personal access tokens → Tokens (classic)
   - Generate token with `repo` scope
   - Save the token securely

### Step 2: Get an Anthropic API Key

1. Go to https://console.anthropic.com
2. Sign up or log in
3. Navigate to API Keys → Create new key
4. Save it securely

**Cost Note:** Claude API is pay-per-token:
- Simple bug fix: $0.50-2.00
- Medium feature: $2-10
- Complex feature with review cycles: $10-50+

### Step 3: Set Up Your Server

```bash
# Install Docker
curl -fsSL https://get.docker.com | sh

# Clone this repository
git clone https://github.com/mikeyward/multiagentworkflow.git
cd multiagentworkflow

# Create environment file
cp .env.example .env
# Edit .env with your values (see .env.example for documentation)

# Build agent containers
docker compose --profile agents build

# Start n8n
docker compose up -d n8n
```

### Step 4: Configure n8n Workflows

1. Access n8n at `http://your-server:5678`
2. Log in with credentials from `.env`
3. Import workflows from `n8n/workflows/`
4. Configure database connections (or simplify to use n8n variables)
5. Activate workflows

### Step 5: Configure Target Repositories

For each repo you want the agents to work on:

1. Add `claudiusward` and `claudetteward` as collaborators
2. Copy `.github/workflows/` to the repo
3. Add `N8N_WEBHOOK_URL` secret
4. Configure branch protection

---

## Customization

### Adjusting Agent Behavior

Edit `agents/claudius/CLAUDE.md` (or `claudette`) to customize:
- Review strictness
- Code style preferences
- Testing requirements
- Communication style

### Changing Limits

Update in `.env`:
```bash
MAX_ITERATIONS=10  # More review cycles allowed
TIMEOUT_HOURS=48   # Longer timeout
```

### Adding Slack Notifications

1. Create Slack webhook at https://api.slack.com/apps
2. Add `SLACK_WEBHOOK_URL` to `.env`
3. Configure Slack node in n8n escalation workflow

---

## Troubleshooting

### Webhook Not Received
```bash
# Check n8n logs
docker compose logs n8n

# Test webhook manually
curl -X POST http://your-server:5678/webhook/issue-assigned \
  -H "Content-Type: application/json" \
  -d '{"test": true}'
```

### Agent Container Fails
```bash
# Run agent manually to see errors
docker compose --profile agents run --rm claudius

# Check Claude Code is installed
docker compose --profile agents run --rm claudius claude --version
```

### GitHub Authentication Fails
```bash
# Test GitHub token
curl -H "Authorization: token YOUR_TOKEN" https://api.github.com/user
```

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
│                    bacchubuntu (Tailscale)                       │
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
│  │    Claudius     │  │    Claudette    │                       │
│  │    (Docker)     │  │    (Docker)     │                       │
│  │                 │  │                 │                       │
│  │  - Claude Code  │  │  - Claude Code  │                       │
│  │  - GitHub CLI   │  │  - GitHub CLI   │                       │
│  │  - Git          │  │  - Git          │                       │
│  └─────────────────┘  └─────────────────┘                       │
└─────────────────────────────────────────────────────────────────┘
```

---

## Security Considerations

1. **API Keys**: Never commit `.env` to git (it's in `.gitignore`)
2. **GitHub Tokens**: Use tokens with minimal `repo` scope only
3. **n8n Access**: Use strong passwords, access via Tailscale only
4. **Agent Isolation**: Agents run in containers with limited permissions
5. **Audit Logging**: n8n keeps execution logs for review

---

## License

MIT
