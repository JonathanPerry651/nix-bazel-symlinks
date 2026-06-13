#!/bin/bash
set -euo pipefail

# Resolve the directory of this script (workspace root)
WORKSPACE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${WORKSPACE_DIR}"

# Run the Go updater script natively on the host
exec go run nix_update.go "$@"
