#!/bin/bash
# AsinuX deploy script — builds and pushes to Firebase Hosting
set -e
cd "$(dirname "$0")/donkey_master"
APP_VERSION=$(grep '^version:' pubspec.yaml | awk '{print $2}')
echo "Building v$APP_VERSION..."
flutter build web --release --pwa-strategy=none --dart-define=APP_VERSION="$APP_VERSION"
echo "Deploying..."
firebase deploy --only hosting --project asinux-89da0
echo "Done → https://asinux-89da0.web.app"
