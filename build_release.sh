#!/bin/bash
set -e

PUBSPEC="pubspec.yaml"

# Read current version line, e.g. "version: 1.2.0+5"
CURRENT=$(grep '^version:' "$PUBSPEC" | sed 's/version: //')
VERSION_NAME=$(echo "$CURRENT" | cut -d'+' -f1)
BUILD_NUM=$(echo "$CURRENT"   | cut -d'+' -f2)

MAJOR=$(echo "$VERSION_NAME" | cut -d'.' -f1)
MINOR=$(echo "$VERSION_NAME" | cut -d'.' -f2)
PATCH=$(echo "$VERSION_NAME" | cut -d'.' -f3)

PATCH=$((PATCH + 1))
BUILD_NUM=$((BUILD_NUM + 1))

NEW_VERSION="${MAJOR}.${MINOR}.${PATCH}+${BUILD_NUM}"

sed -i '' "s/^version:.*/version: ${NEW_VERSION}/" "$PUBSPEC"
echo "▶ Building MyBudga ${MAJOR}.${MINOR}.${PATCH} (build ${BUILD_NUM})"

flutter build apk --release

APK_NAME="MyBudga-${MAJOR}.${MINOR}.${PATCH}.apk"
cp build/app/outputs/flutter-apk/app-release.apk "build/app/outputs/flutter-apk/${APK_NAME}"
echo "✓ APK: build/app/outputs/flutter-apk/${APK_NAME}"

flutter build macos --release

APP_SRC="build/macos/Build/Products/Release/mybudga.app"
APP_DST="build/macos/Build/Products/Release/MyBudga-${MAJOR}.${MINOR}.${PATCH}.app"
cp -R "$APP_SRC" "$APP_DST"
echo "✓ macOS: $APP_DST"

# Remove previous versioned releases now that the new build succeeded
find build/app/outputs/flutter-apk -name 'MyBudga-*.apk' ! -name "${APK_NAME}" -delete
find build/macos/Build/Products/Release -maxdepth 1 -name 'MyBudga-*.app' ! -name "MyBudga-${MAJOR}.${MINOR}.${PATCH}.app" -exec rm -rf {} +
echo "✓ Old releases cleaned up"
