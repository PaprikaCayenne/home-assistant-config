#!/bin/bash

cd /config

# Set timestamp for commit
DATE=$(date '+%Y-%m-%d %H:%M:%S')
MESSAGE="🕒 Nightly backup: $DATE"

# Add, commit, and push
git --git-dir=/config/.git --work-tree=/config add -A
git --git-dir=/config/.git --work-tree=/config commit -m "$MESSAGE"
git --git-dir=/config/.git --work-tree=/config push origin main
