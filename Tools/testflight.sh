#!/bin/zsh
# testflight.sh [--dry-run]
#
# Archives a Release build and uploads it to App Store Connect, where it
# shows up under TestFlight once processed (about 10–30 minutes). Signing
# and the upload use the Apple ID signed into Xcode (Settings → Accounts).
# The build number is the git commit count, so commit before uploading:
# App Store Connect refuses a build number it has seen before.
#   --dry-run   archive and export an .ipa locally, upload nothing
set -eu
cd "${0:A:h}/.."
WORK=${TMPDIR:-/tmp}/collagestudio-testflight
rm -rf "$WORK"; mkdir -p "$WORK"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Uncommitted changes — commit first (the build number comes from the commit count)." >&2
  exit 1
fi
echo "Version $(grep -m1 'MARKETING_VERSION' CollageStudio.xcodeproj/project.pbxproj | sed 's/[^0-9.]//g') build $(git rev-list --count HEAD) ($(git rev-parse --short HEAD))"

xcodebuild archive -scheme CollageStudio -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$WORK/CollageStudio.xcarchive" \
  -allowProvisioningUpdates -quiet

DEST=upload; [[ ${1:-} == --dry-run ]] && DEST=export
cat > "$WORK/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>$DEST</string>
  <key>signingStyle</key><string>automatic</string>
  <key>teamID</key><string>Q74V8KTHTD</string>
  <key>uploadSymbols</key><true/>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
EOF

xcodebuild -exportArchive -archivePath "$WORK/CollageStudio.xcarchive" \
  -exportOptionsPlist "$WORK/ExportOptions.plist" -exportPath "$WORK/export" \
  -allowProvisioningUpdates
[[ $DEST == upload ]] && echo "Uploaded — App Store Connect emails when it has finished processing." \
                      || echo "Dry run: $WORK/export"
