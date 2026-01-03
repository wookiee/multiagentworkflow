#!/bin/bash
set -e

# Coder Agent Entrypoint
# This script is called by n8n to run the Coder agent

# Required environment variables:
# - GITHUB_TOKEN: GitHub personal access token for the coder bot
# - ANTHROPIC_API_KEY: Anthropic API key for Claude
# - REPO_URL: Repository clone URL
# - ISSUE_NUMBER: GitHub issue number to implement
# - ISSUE_TITLE: Issue title
# - ISSUE_BODY: Issue body/description
# - DEFAULT_BRANCH: Default branch name (usually 'main')

# Optional environment variables:
# - GIT_USER_NAME: Git user name for commits
# - GIT_USER_EMAIL: Git user email for commits
# - REVIEW_COMMENTS: Review comments to address (for revision mode)

echo "=== Coder Agent Starting ==="
echo "Repository: $REPO_URL"
echo "Issue: #$ISSUE_NUMBER - $ISSUE_TITLE"

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
    git checkout "$DEFAULT_BRANCH"
    git pull origin "$DEFAULT_BRANCH"
else
    echo "Cloning repository..."
    git clone "$REPO_URL" "$REPO_DIR"
    cd "$REPO_DIR"
fi

# Determine branch name
BRANCH_NAME="feature/issue-${ISSUE_NUMBER}"

# Check if this is a revision (responding to review comments)
if [ -n "$REVIEW_COMMENTS" ]; then
    echo "=== Revision Mode: Addressing Review Comments ==="

    # Check out existing branch
    git checkout "$BRANCH_NAME"
    git pull origin "$BRANCH_NAME" || true

    # Create prompt for addressing review comments
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

    # Create new branch
    git checkout -b "$BRANCH_NAME" || git checkout "$BRANCH_NAME"

    # Create prompt for initial implementation
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

# Copy agent instructions to workspace
cp /agent/CLAUDE.md "$REPO_DIR/CLAUDE.md.agent"

echo "=== Running Claude Code ==="

# Run Claude Code in headless mode
claude -p "$PROMPT" \
    --allowedTools "Read,Write,Edit,Bash,Glob,Grep,TodoWrite" \
    --max-turns 50 \
    2>&1 | tee /tmp/claude-output.log

EXIT_CODE=$?

# Clean up agent instructions
rm -f "$REPO_DIR/CLAUDE.md.agent"

echo "=== Coder Agent Complete ==="
echo "Exit code: $EXIT_CODE"

# Output result for n8n to capture
if [ $EXIT_CODE -eq 0 ]; then
    echo '{"status": "success", "branch": "'$BRANCH_NAME'"}'
else
    echo '{"status": "failed", "error": "Claude Code exited with code '$EXIT_CODE'"}'
fi

exit $EXIT_CODE
