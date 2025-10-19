#!/usr/bin/env bash
set -Eeuo pipefail
PATH="/usr/local/bin:/usr/bin:/bin"
REPO_DIR="/config"
cd "$REPO_DIR"

# must be a git repo
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Not a git repo at $REPO_DIR"
  exit 0
fi

# ensure git identity
git config user.name  >/dev/null 2>&1 || git config user.name  "HA Nightly Backup"
git config user.email >/dev/null 2>&1 || git config user.email "ha-backup@local"

# stay in sync if an upstream exists
if git rev-parse --abbrev-ref --symbolic-full-name @{u} >/dev/null 2>&1; then
  git pull --rebase --autostash || true
fi

# stage changes
git add -A

# commit only when there are changes
if [ -n "$(git status --porcelain)" ]; then
  DATE="$(date '+%Y-%m-%d %H:%M:%S')"
  MESSAGE="🕒 Nightly backup: $DATE"
  git commit -m "$MESSAGE"
else
  echo "No changes to commit."
fi

# detect current branch, fallback to main
BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)"

# push, setting upstream on first run
if git rev-parse --abbrev-ref --symbolic-full-name @{u} >/dev/null 2>&1; then
  git push
else
  git push --set-upstream origin "$BRANCH"
fi
