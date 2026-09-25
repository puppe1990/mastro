#!/bin/bash
# Build a mastro wrapper script for convenience.
#
# This creates a `mastro` script in the current directory that
# delegates to `gleam run -m mastro/cli`.
#
# Usage:
#   ./bin/build-cli.sh
#   ./mastro new my_app
#
set -euo pipefail

gleam build

cat > mastro <<'SCRIPT'
#!/bin/bash
# Mastro CLI wrapper — delegates to gleam run -m mastro/cli
gleam run -m mastro/cli -- "$@"
SCRIPT

chmod +x mastro
echo "Created ./mastro wrapper script"
echo "Run: ./mastro new my_app"
