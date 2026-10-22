#!/bin/zsh
# Runs the UI tests (CollageStudioUITests) on the simulator, or on a device.
#   zsh Tools/uitest.sh                     all tests, iPhone 17 Pro simulator
#   zsh Tools/uitest.sh -only SmokeTests/testExportOpensShareSheet
#   zsh Tools/uitest.sh -device <udid>      on a phone (it gets the Debug
#                                           build; reinstall Release after)
# Results (with screenshots of failures): /tmp/CollageUITests/<time>.xcresult
set -e
cd "$(dirname "$0")/.."
DEST="id=9616B792-D7D9-41DF-81BD-2D6EFCAF03E7"   # iPhone 17 Pro simulator
ONLY=()
while [[ $# -gt 0 ]]; do
  case $1 in
    -device) DEST="id=$2"; shift 2 ;;
    -only) ONLY+=("-only-testing:CollageStudioUITests/$2"); shift 2 ;;
    *) echo "unknown option $1"; exit 2 ;;
  esac
done
OUT=/tmp/CollageUITests
mkdir -p $OUT
RESULT=$OUT/$(date +%Y%m%d-%H%M%S).xcresult
set +e
xcodebuild test -project CollageStudio.xcodeproj -scheme CollageStudio -configuration Debug \
  -destination "$DEST" -derivedDataPath $OUT/dd -resultBundlePath $RESULT \
  -allowProvisioningUpdates "${ONLY[@]}" 2>&1 \
  | grep -E "Test Case .*(passed|failed)|error:|XCTAssert|failed:|\*\* TEST" 
STATUS=${pipestatus[1]}
echo "Results: $RESULT"
exit $STATUS
