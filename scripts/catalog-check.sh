#!/usr/bin/env bash
# Validate every catalog entry: schema, unique ids, and the file at the pinned revision on Hugging Face. See docs/catalog.md.
set -euo pipefail
exec python3 -I "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/catalog.py" check "$@"
