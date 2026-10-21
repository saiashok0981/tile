#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
swift run Tile --smoke-test
swift run Tile --layout-test
swift run Tile --focus-test
