#!/usr/bin/env bash
# A model name must be shown with its logo: use ModelLabel (or ModelLogo next to the name).
# Fails when a view shows a model's displayName or shortName as plain Text.
# Allowed places are listed in scripts/model-name-allowlist.txt (one file path per line).
set -euo pipefail
cd "$(dirname "$0")/.."
ALLOW=scripts/model-name-allowlist.txt
hits=$(grep -rnE 'Text\([^)]*(\.displayName|\.shortName)' App Features Design --include='*.swift' || true)
fail=0
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  file=${line%%:*}
  if ! grep -qxF "$file" "$ALLOW"; then
    echo "::error file=$file::model name shown as plain Text; use ModelLabel (logo + name)."
    echo "$line"
    fail=1
  fi
done <<< "$hits"
exit $fail
