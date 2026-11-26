#!/usr/bin/env bash
# Counts custom-UI patterns per Swift file and fails if any file has more than
# scripts/native-baseline.txt allows. The baseline only goes down: convert a file
# to stock SwiftUI components, then run `scripts/native-ratchet.sh --update`.
# See AGENTS.md § "Design rule: native first".
set -euo pipefail
cd "$(dirname "$0")/.."
BASELINE=scripts/native-baseline.txt
PATTERN='ARColor\.|\.font\(\.ar|RoundedRectangle\(cornerRadius|Capsule\(\)|\.onTapGesture|\.shadow\(|ARIconButton|ARSearchField|ARChip|ARSectionTitle'

current=$(grep -rcE "$PATTERN" App Features Design --include='*.swift' | grep -v ':0$' | sort || true)

if [[ "${1:-}" == "--update" ]]; then
  printf '%s\n' "$current" > "$BASELINE"
  echo "baseline updated: $(awk -F: '{s+=$2} END {print s+0}' "$BASELINE") hits"
  exit 0
fi

fail=0
while IFS=: read -r file count; do
  [[ -z "$file" ]] && continue
  allowed=$(grep -F "$file:" "$BASELINE" | head -1 | cut -d: -f2 || true)
  allowed=${allowed:-0}
  if (( count > allowed )); then
    echo "::error file=$file::$count custom-UI hits, baseline allows $allowed. Use stock SwiftUI components (AGENTS.md, native first)."
    fail=1
  fi
done <<< "$current"
total=$(printf '%s\n' "$current" | awk -F: '{s+=$2} END {print s+0}')
base=$(awk -F: '{s+=$2} END {print s+0}' "$BASELINE")
echo "custom-UI hits: $total (baseline $base)"
if (( total < base )); then echo "::notice::fewer hits than the baseline. Run scripts/native-ratchet.sh --update and commit it."; fi
exit $fail
