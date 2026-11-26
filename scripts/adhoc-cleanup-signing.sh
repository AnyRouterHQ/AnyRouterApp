#!/usr/bin/env bash
# Remove the temporary keychain and profile (CI only, runs always).
set -uo pipefail
[ -n "${KEYCHAIN_PATH:-}" ] && security delete-keychain "$KEYCHAIN_PATH" || true
[ -n "${PROFILE_UUID:-}" ] && rm -f "$HOME/Library/MobileDevice/Provisioning Profiles/$PROFILE_UUID.mobileprovision" || true
rm -f "${RUNNER_TEMP:-/nonexistent}/adhoc.mobileprovision"
exit 0
