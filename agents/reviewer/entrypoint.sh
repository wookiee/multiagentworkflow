#!/bin/bash
set -e

# Reviewer Agent Entrypoint
# This script is called by n8n to run the Reviewer agent

# Required environment variables:
# - GITHUB_TOKEN: GitHub personal access token for the reviewer bot
# - ANTHROPIC_API_KEY: Anthropic API key for Claude
# - REPO_URL: Repository clone URL
# - PR_NUMBER: Pull request number to review
# - PR_TITLE: PR title
# - PR_BODY: PR body/description
# - PR_BRANCH: PR branch name

# Optional environment variables:
# - ITERATION_COUNT: Current review iteration (for context)
# - MAX_ITERATIONS: Maximum allowed iterations before escalation

echo "=== Reviewer Agent Starting ==="
echo "Repository: $REPO_URL"
echo "PR: #$PR_NUMBER - $PR_TITLE"
echo "Iteration: ${ITERATION_COUNT:-1} / ${MAX_ITERATIONS:-5}"

# Configure GitHub CLI
echo "$GITHUB_TOKEN" | gh auth login --with-token

# Clone repository to get full context
REPO_DIR="/workspace/repo"
if [ -d "$REPO_DIR/.git" ]; then
    echo "Updating existing repository..."
    cd "$REPO_DIR"
    git fetch origin
else
    echo "Cloning repository..."
    git clone "$REPO_URL" "$REPO_DIR"
    cd "$REPO_DIR"
fi

# Checkout the PR branch
git checkout "$PR_BRANCH" 2>/dev/null || git checkout -b "$PR_BRANCH" "origin/$PR_BRANCH"
git pull origin "$PR_BRANCH" || true

# Get PR details
echo "=== Fetching PR Details ==="
gh pr view "$PR_NUMBER" --json title,body,files,reviews,comments > /tmp/pr-details.json

# Check CI status
echo "=== Checking CI Status ==="
CI_STATUS=$(gh pr checks "$PR_NUMBER" --json name,state,conclusion 2>/dev/null || echo "[]")
echo "$CI_STATUS" > /tmp/ci-status.json

# Copy agent instructions
cp /agent/CLAUDE.md "$REPO_DIR/CLAUDE.md.agent"

# Create the review prompt
PROMPT="You are reviewing Pull Request #${PR_NUMBER}.

PR Title: ${PR_TITLE}

PR Description:
${PR_BODY}

This is review iteration ${ITERATION_COUNT:-1} of maximum ${MAX_ITERATIONS:-5}.

First, check the CI status:
\`\`\`
$(cat /tmp/ci-status.json)
\`\`\`

If CI is failing, request changes asking the author to fix CI before you review the code.

If CI is passing, perform a thorough code review:

1. View the PR diff:
   \`gh pr diff $PR_NUMBER\`

2. Check files changed:
   \`gh pr view $PR_NUMBER --json files\`

3. Review the code for:
   - Correctness and logic
   - Test coverage
   - Security considerations
   - Performance implications
   - Code style consistency

4. Submit your review using:
   - \`gh pr review $PR_NUMBER --approve --body \"...\"\` if the code is good
   - \`gh pr review $PR_NUMBER --request-changes --body \"...\"\` if changes are needed

Be constructive and specific in your feedback. Focus on issues that matter."

echo "=== Running Claude Code ==="

# Run Claude Code in headless mode
claude -p "$PROMPT" \
    --allowedTools "Read,Bash,Glob,Grep" \
    --max-turns 30 \
    2>&1 | tee /tmp/claude-output.log

EXIT_CODE=$?

# Clean up agent instructions
rm -f "$REPO_DIR/CLAUDE.md.agent"

# Determine review outcome
echo "=== Determining Review Outcome ==="
REVIEW_STATE=$(gh pr view "$PR_NUMBER" --json reviews --jq '.reviews[-1].state' 2>/dev/null || echo "UNKNOWN")

echo "Latest review state: $REVIEW_STATE"

# Output result for n8n to capture
if [ $EXIT_CODE -eq 0 ]; then
    echo "{\"status\": \"success\", \"review_state\": \"$REVIEW_STATE\", \"pr_number\": $PR_NUMBER}"
else
    echo "{\"status\": \"failed\", \"error\": \"Claude Code exited with code $EXIT_CODE\"}"
fi

echo "=== Reviewer Agent Complete ==="
exit $EXIT_CODE
