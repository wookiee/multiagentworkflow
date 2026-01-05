#!/bin/bash
set -e

# Software Engineer Agent Entrypoint
# This script is called by n8n to run the agent in either coder or reviewer role

# Required environment variables:
# - GITHUB_TOKEN: GitHub personal access token
# - ANTHROPIC_API_KEY: Anthropic API key for Claude
# - ROLE: Either "coder" or "reviewer"
# - REPO_URL: Repository clone URL

# Role-specific environment variables:
# For CODER role:
# - ISSUE_NUMBER: GitHub issue number to implement
# - ISSUE_TITLE: Issue title
# - ISSUE_BODY: Issue body/description
# - DEFAULT_BRANCH: Default branch name (usually 'main')
# - REVIEW_COMMENTS: Review comments to address (for revision mode)

# For REVIEWER role:
# - PR_NUMBER: Pull request number to review
# - PR_TITLE: PR title
# - PR_BODY: PR body/description
# - PR_BRANCH: PR branch name
# - ITERATION_COUNT: Current review iteration
# - MAX_ITERATIONS: Maximum allowed iterations

# Optional environment variables:
# - GIT_USER_NAME: Git user name for commits
# - GIT_USER_EMAIL: Git user email for commits

AGENT_NAME="${AGENT_NAME:-Agent}"
echo "=== ${AGENT_NAME} Starting (Role: ${ROLE}) ==="
echo "Repository: $REPO_URL"

# Configure git
if [ -n "$GIT_USER_NAME" ]; then
    git config --global user.name "$GIT_USER_NAME"
fi
if [ -n "$GIT_USER_EMAIL" ]; then
    git config --global user.email "$GIT_USER_EMAIL"
fi

# Configure GitHub CLI
echo "$GITHUB_TOKEN" | gh auth login --with-token

# Clone or update repository
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

# Copy agent instructions to workspace
cp /agent/CLAUDE.md "$REPO_DIR/CLAUDE.md.agent"

# Dispatch based on role
if [ "$ROLE" = "coder" ]; then
    echo "Issue: #$ISSUE_NUMBER - $ISSUE_TITLE"

    # Checkout appropriate branch
    git checkout "${DEFAULT_BRANCH:-main}"
    git pull origin "${DEFAULT_BRANCH:-main}"

    BRANCH_NAME="feature/issue-${ISSUE_NUMBER}"

    if [ -n "$REVIEW_COMMENTS" ]; then
        echo "=== Revision Mode: Addressing Review Comments ==="
        git checkout "$BRANCH_NAME"
        git pull origin "$BRANCH_NAME" || true

        PROMPT="You are working on issue #${ISSUE_NUMBER}: ${ISSUE_TITLE}

The reviewer has requested changes. Here are their comments:

${REVIEW_COMMENTS}

Please:
1. Address each review comment
2. Make the necessary code changes
3. Run the test suite to ensure everything passes
4. Commit your changes with a clear message
5. If you disagree with any feedback, explain your reasoning

After making changes, push to the branch and respond to the review comments."
    else
        echo "=== Initial Implementation Mode ==="
        git checkout -b "$BRANCH_NAME" || git checkout "$BRANCH_NAME"

        PROMPT="You have been assigned issue #${ISSUE_NUMBER}.

Issue Title: ${ISSUE_TITLE}

Issue Description:
${ISSUE_BODY}

Please implement this issue following these steps:
1. Explore the codebase to understand the architecture
2. Implement the solution
3. Write tests for your changes
4. Run the test suite and ensure all tests pass
5. Commit your changes with clear, descriptive messages

When complete, create a pull request with:
- A clear title
- A description of what was implemented
- Reference to the issue (Closes #${ISSUE_NUMBER})
- Test results summary

Remember: Do NOT create the PR if tests are failing. Fix them first."
    fi

    ALLOWED_TOOLS="Read,Write,Edit,Bash,Glob,Grep,TodoWrite"
    MAX_TURNS=50

elif [ "$ROLE" = "reviewer" ]; then
    echo "PR: #$PR_NUMBER - $PR_TITLE"
    echo "Iteration: ${ITERATION_COUNT:-1} / ${MAX_ITERATIONS:-5}"

    # Checkout the PR branch
    git checkout "$PR_BRANCH" 2>/dev/null || git checkout -b "$PR_BRANCH" "origin/$PR_BRANCH"
    git pull origin "$PR_BRANCH" || true

    # Get CI status
    echo "=== Checking CI Status ==="
    CI_STATUS=$(gh pr checks "$PR_NUMBER" --json name,state,conclusion 2>/dev/null || echo "[]")
    echo "$CI_STATUS" > /tmp/ci-status.json

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

    ALLOWED_TOOLS="Read,Bash,Glob,Grep"
    MAX_TURNS=30

else
    echo "ERROR: Unknown role '$ROLE'. Must be 'coder' or 'reviewer'."
    exit 1
fi

echo "=== Running Claude Code ==="

# Run Claude Code in headless mode
claude -p "$PROMPT" \
    --allowedTools "$ALLOWED_TOOLS" \
    --max-turns "$MAX_TURNS" \
    2>&1 | tee /tmp/claude-output.log

EXIT_CODE=$?

# Clean up agent instructions
rm -f "$REPO_DIR/CLAUDE.md.agent"

echo "=== ${AGENT_NAME} Complete ==="
echo "Exit code: $EXIT_CODE"

# Output result for n8n to capture
if [ $EXIT_CODE -eq 0 ]; then
    if [ "$ROLE" = "coder" ]; then
        echo "{\"status\": \"success\", \"role\": \"coder\", \"branch\": \"$BRANCH_NAME\"}"
    else
        REVIEW_STATE=$(gh pr view "$PR_NUMBER" --json reviews --jq '.reviews[-1].state' 2>/dev/null || echo "UNKNOWN")
        echo "{\"status\": \"success\", \"role\": \"reviewer\", \"review_state\": \"$REVIEW_STATE\", \"pr_number\": $PR_NUMBER}"
    fi
else
    echo "{\"status\": \"failed\", \"role\": \"$ROLE\", \"error\": \"Claude Code exited with code $EXIT_CODE\"}"
fi

exit $EXIT_CODE
