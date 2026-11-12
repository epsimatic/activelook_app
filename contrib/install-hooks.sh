#!/bin/bash
# Install git pre-commit hooks for the activelook_app project.
#
# Usage: contrib/install-hooks.sh
#   or:  bash contrib/install-hooks.sh   # from anywhere in the repo

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
HOOKS_DIR="$PROJECT_DIR/.git/hooks"
SOURCE_HOOK="$PROJECT_DIR/contrib/pre-commit"
TARGET_HOOK="$HOOKS_DIR/pre-commit"

if [ ! -f "$SOURCE_HOOK" ]; then
  echo "Error: Source hook not found at $SOURCE_HOOK"
  exit 1
fi

if [ ! -d "$HOOKS_DIR" ]; then
  echo "Error: .git/hooks directory not found. Is this a git repository?"
  exit 1
fi

cp "$SOURCE_HOOK" "$TARGET_HOOK"
chmod +x "$TARGET_HOOK"

echo "Pre-commit hook installed to $TARGET_HOOK"
echo "Run 'git commit' to verify it works."
echo "Use 'git commit --no-verify' to skip checks."
