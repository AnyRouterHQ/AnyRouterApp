#!/usr/bin/env bash
# Add or refresh one catalog entry from Hugging Face. See docs/catalog.md.
set -euo pipefail
exec python3 -I "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/catalog.py" add "$@"
