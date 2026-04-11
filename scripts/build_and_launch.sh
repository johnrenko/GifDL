#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/MemeDrop.xcodeproj"
SCHEME="MemeDrop"
SIMULATOR_NAME="${SIMULATOR_NAME:-iPhone 17 Pro}"
OS_VERSION="${IOS_RUNTIME_VERSION:-26.4}"
DESTINATION="platform=iOS Simulator,name=${SIMULATOR_NAME},OS=${OS_VERSION}"

cd "$ROOT_DIR"

if [[ ! -d "$PROJECT_PATH" ]]; then
  echo "Generating Xcode project with xcodegen"
  xcodegen generate
fi

echo "Building $SCHEME for $SIMULATOR_NAME (iOS $OS_VERSION)"
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  CODE_SIGNING_ALLOWED=NO \
  build

if [[ "${1:-}" == "--launch" ]]; then
  APP_BUNDLE_PATH="$(find "$HOME/Library/Developer/Xcode/DerivedData" -path "*Build/Products/Debug-iphonesimulator/MemeDrop.app" -print -quit)"
  if [[ -z "$APP_BUNDLE_PATH" ]]; then
    echo "Unable to locate MemeDrop.app in DerivedData"
    exit 1
  fi

  xcrun simctl boot "$SIMULATOR_NAME" >/dev/null 2>&1 || true
  xcrun simctl install booted "$APP_BUNDLE_PATH"
  xcrun simctl launch booted dev.jd.MemeDrop
fi
