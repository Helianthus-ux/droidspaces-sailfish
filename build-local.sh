#!/bin/bash
# Convenience wrapper: verify the script/config files are self-consistent,
# then invoke the real build. Run from anywhere.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "Verifying build files..."
test -f "$ROOT/config/droidspaces.config" || { echo "missing config fragment"; exit 1; }
test -f "$ROOT/scripts/verify_config.py" || { echo "missing verify script"; exit 1; }
python3 -m py_compile "$ROOT/scripts/verify_config.py"
bash -n "$ROOT/scripts/build.sh"
echo "Sanity checks passed. Starting build..."
exec bash "$ROOT/scripts/build.sh" "$@"
