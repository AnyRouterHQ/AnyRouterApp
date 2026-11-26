#!/usr/bin/env bash
# Import the signing cert and ad-hoc profile into a temporary keychain (CI only).
# Env: IOS_CERT_P12_BASE64, IOS_CERT_PASSWORD, IOS_ADHOC_PROFILE_BASE64, RUNNER_TEMP, GITHUB_ENV
set -euo pipefail

KEYCHAIN="$RUNNER_TEMP/adhoc-signing.keychain-db"
KEYCHAIN_PASSWORD="$(uuidgen)"
echo "::add-mask::$KEYCHAIN_PASSWORD"

printf '%s' "$IOS_CERT_P12_BASE64" | base64 --decode > "$RUNNER_TEMP/cert.p12"
printf '%s' "$IOS_ADHOC_PROFILE_BASE64" | base64 --decode > "$RUNNER_TEMP/adhoc.mobileprovision"

security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security import "$RUNNER_TEMP/cert.p12" -P "$IOS_CERT_PASSWORD" -A -t cert -f pkcs12 -k "$KEYCHAIN"
security set-key-partition-list -S apple-tool:,apple: -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
security list-keychains -d user -s "$KEYCHAIN" $(security list-keychains -d user | tr -d '"')

# Decode the profile to read its UUID and name.
security cms -D -i "$RUNNER_TEMP/adhoc.mobileprovision" > "$RUNNER_TEMP/profile.plist"
UUID=$(/usr/libexec/PlistBuddy -c 'Print :UUID' "$RUNNER_TEMP/profile.plist")
NAME=$(/usr/libexec/PlistBuddy -c 'Print :Name' "$RUNNER_TEMP/profile.plist")

# The profile must carry the increased-memory-limit entitlement the app asks for.
if ! /usr/libexec/PlistBuddy -c 'Print :Entitlements' "$RUNNER_TEMP/profile.plist" | grep -q 'increased-memory-limit'; then
  echo "::error::Profile lacks com.apple.developer.kernel.increased-memory-limit. Enable the Increased Memory Limit capability on the App ID and regenerate the profile (see docs/install.md)."
  exit 1
fi

PROFILES="$HOME/Library/MobileDevice/Provisioning Profiles"
mkdir -p "$PROFILES"
cp "$RUNNER_TEMP/adhoc.mobileprovision" "$PROFILES/$UUID.mobileprovision"

{
  echo "KEYCHAIN_PATH=$KEYCHAIN"
  echo "PROFILE_UUID=$UUID"
  echo "PROFILE_NAME=$NAME"
} >> "$GITHUB_ENV"
rm -f "$RUNNER_TEMP/cert.p12" "$RUNNER_TEMP/profile.plist"
echo "Installed profile (name hidden in logs)."
