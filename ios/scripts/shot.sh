#!/bin/zsh
# Build, install and screenshot a screen on a given simulator.
# Usage: scripts/shot.sh <sim-udid> <derived-data-dir> <out.png> <screen> [extra launch args...]
# Example: scripts/shot.sh $SIM /tmp/dd-overview /tmp/overview.png overview -profile jordan
# Set NOBUILD=1 to skip the build step. Set WAIT=<seconds> to change settle time (default 2.5).
set -e
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
SIM=$1; DD=$2; OUT=$3; SCREEN=$4; shift 4
ROOT=${0:A:h:h}
BUNDLE=com.hackumbc.adaptiveretirement

xcrun simctl boot "$SIM" 2>/dev/null || true
if [[ -z "$NOBUILD" ]]; then
  xcodebuild -project "$ROOT/AdaptiveRetirement.xcodeproj" -scheme AdaptiveRetirement \
    -destination "platform=iOS Simulator,id=$SIM" -derivedDataPath "$DD" build 2>&1 \
    | grep -E "error:|BUILD (SUCCEEDED|FAILED)" || true
fi
APP="$DD/Build/Products/Debug-iphonesimulator/AdaptiveRetirement.app"
xcrun simctl install "$SIM" "$APP"
xcrun simctl terminate "$SIM" "$BUNDLE" 2>/dev/null || true
xcrun simctl launch "$SIM" "$BUNDLE" -screen "$SCREEN" "$@" >/dev/null
sleep ${WAIT:-2.5}
xcrun simctl io "$SIM" screenshot "$OUT" >/dev/null 2>&1
echo "saved $OUT"
