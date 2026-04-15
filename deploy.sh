#!/bin/bash
# AsinuX deploy script — builds and pushes to Firebase Hosting
set -e
cd "$(dirname "$0")/donkey_master"
echo "Building..."
flutter build web --release --pwa-strategy=none
echo "Deploying..."
firebase deploy --only hosting --project asinux-89da0
echo "Done → https://asinux-89da0.web.app"
