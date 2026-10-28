#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
swift run Tile --smoke-test
swift run Tile --layout-test
swift run Tile --focus-test
swift run Tile --keyboard-test
swift run Tile --agent-test
if [[ "${TILE_SKIP_MANAGED_CODEX:-0}" == "1" ]]; then
  print 'Skipping managed Codex protocol test: disabled for token-free CI'
elif command -v codex >/dev/null 2>&1; then
  swift run Tile --managed-codex-test
else
  print 'Skipping managed Codex protocol test: codex CLI is not installed'
fi
