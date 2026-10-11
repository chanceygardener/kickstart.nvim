#!/usr/bin/env bash
# Link the show-me-nvim skill into each agent's skills directory, and the CLI
# onto PATH. Safe to re-run; works with BSD (macOS) and GNU ln.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)

for dir in "$HOME/.claude/skills" "$HOME/.codex/skills" "$HOME/.cursor/skills"; do
  mkdir -p "$dir"
  ln -sfn "$here" "$dir/show-me-nvim"
  echo "linked $dir/show-me-nvim"
done

mkdir -p "$HOME/.local/bin"
ln -sf "$here/scripts/show-me" "$HOME/.local/bin/show-me"
echo "linked ~/.local/bin/show-me (ensure ~/.local/bin is on PATH)"
