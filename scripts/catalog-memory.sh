#!/usr/bin/env bash
# Fill the memory profile (KV-cache bytes per token) of every entry from the model's own metadata. See docs/catalog.md.
set -euo pipefail
exec python3 -I "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/catalog.py" memory "$@"
