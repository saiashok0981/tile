#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
print 'Running smoke test'
swift run Tile --smoke-test
print 'Running four-pane layout test'
swift run Tile --layout-test
print 'Running input focus test'
swift run Tile --focus-test
print 'Running keyboard workflow test'
swift run Tile --keyboard-test
print 'Running agent workflow test'
swift run Tile --agent-test
print 'Running menu bar agent test'
swift run Tile --menu-bar-agent-test
if [[ "${TILE_SKIP_MANAGED_CODEX:-0}" == "1" ]]; then
  print 'Skipping managed Codex protocol test: disabled for token-free CI'
elif command -v codex >/dev/null 2>&1; then
  swift run Tile --managed-codex-test
  if [[ -x /usr/local/bin/codex || -x /opt/homebrew/bin/codex ]]; then
    env PATH=/usr/bin:/bin swift run Tile --managed-codex-test
  fi
else
  print 'Skipping managed Codex protocol test: codex CLI is not installed'
fi
