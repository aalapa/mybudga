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

echo "✓ APK: build/app/outputs/flutter-apk/MyBudga-${MAJOR}.${MINOR}.${PATCH}.apk"
