#!/bin/zsh
# Build the App Store archive and export the .ipa. With --upload it sends the
# build to App Store Connect, which is not a submission: that stays a button.
# Fails if the DeepSeek key is anywhere in the build, or if the relay that
# replaces it isn't set, which would ship a host that can only use its script.
set -euo pipefail
cd "$(dirname "$0")/../App"
OUT=../.build/release
DEST=export
[[ ${1:-} == --upload ]] && DEST=upload
ARCHIVE=$OUT/SkeeSkeeSkee.xcarchive
rm -rf "$OUT"; mkdir -p "$OUT"

xcodegen generate >/dev/null
xcodebuild -project SkeeSkeeSkee.xcodeproj -scheme SkeeSkeeSkee -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" -derivedDataPath ../.build/archive \
  -allowProvisioningUpdates archive 2>&1 | grep -E 'error:|ARCHIVE (SUCCEEDED|FAILED)' | cut -c1-200

APP=$ARCHIVE/Products/Applications/SkeeSkeeSkee.app
[[ -d $APP ]] || { echo "no app in the archive"; exit 1; }

value=$(/usr/libexec/PlistBuddy -c 'Print :DeepSeekAPIKey' "$APP/Info.plist" 2>/dev/null || true)
[[ -z $value ]] || { echo "FAIL: Info.plist carries a key"; exit 1; }
if [[ -f ../.env ]]; then
  key=$(sed -n 's/^DEEPSEEK_API_KEY=//p' ../.env | tr -d "\"' ")
  if [[ -n $key ]] && grep -rqF -- "$key" "$APP"; then echo "FAIL: the key is in the app bundle"; exit 1; fi
fi
relay=$(/usr/libexec/PlistBuddy -c 'Print :HostRelayURL' "$APP/Info.plist" 2>/dev/null || true)
[[ $relay == https://* ]] || { echo "FAIL: no relay URL in Info.plist: '$relay'"; exit 1; }
echo "key check passed: none in the bundle. Relay: $relay"

cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>$DEST</string>
  <key>signingStyle</key><string>automatic</string>
  <key>teamID</key><string>NY422J2AAW</string>
</dict></plist>
PLIST
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$OUT/export" \
  -exportOptionsPlist "$OUT/ExportOptions.plist" -allowProvisioningUpdates 2>&1 | grep -E 'error:|EXPORT (SUCCEEDED|FAILED)|Upload succeeded|Uploaded' | cut -c1-200
ls -la "$OUT/export" 2>/dev/null || true
