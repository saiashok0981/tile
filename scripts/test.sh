#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
swift build --product Tile
tile_binary="$(swift build --show-bin-path)/Tile"
"${tile_binary}" --smoke-test
"${tile_binary}" --layout-test
"${tile_binary}" --focus-test
"${tile_binary}" --keyboard-test
"${tile_binary}" --agent-test
"${tile_binary}" --menu-bar-agent-test
if [[ "${TILE_SKIP_MANAGED_CODEX:-0}" == "1" ]]; then
  print 'Skipping managed Codex protocol test: disabled for token-free CI'
elif command -v codex >/dev/null 2>&1; then
  "${tile_binary}" --managed-codex-test
  if [[ -x /usr/local/bin/codex || -x /opt/homebrew/bin/codex ]]; then
    env PATH=/usr/bin:/bin "${tile_binary}" --managed-codex-test
  fi
else
  print 'Skipping managed Codex protocol test: codex CLI is not installed'
fi
