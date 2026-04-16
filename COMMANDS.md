# AsinuX — Operational Commands Reference

All commands are run from the `donkey_master/` directory unless noted otherwise.

---

## 1. Flutter — Build & Run

```bash
# Run on Chrome (web dev)
flutter run -d chrome

# Run on connected Android device
flutter run -d android

# Hot reload (while app is running in terminal)
r

# Hot restart (while app is running in terminal)
R

# Analyze code for errors/warnings
flutter analyze
```

---

## 2. Android — Release Build

> Before building, bump the version code in `pubspec.yaml`:
> `version: 1.0.0+7`  →  increment the number after `+`

```bash
# Generate release AAB (for Play Store upload)
flutter build appbundle --release

# Output path:
# build/app/outputs/bundle/release/app-release.aab
```

---

## 3. Web — Release Build & Firebase Deploy

```bash
# Build web release (reads version from pubspec.yaml automatically)
flutter build web --release --dart-define=APP_VERSION=$(grep '^version:' pubspec.yaml | awk '{print $2}')

# Deploy to Firebase Hosting (asinux-89da0.web.app)
# Run from donkey_master/ directory
firebase deploy --only hosting

# Build + deploy in one line
flutter build web --release --dart-define=APP_VERSION=$(grep '^version:' pubspec.yaml | awk '{print $2}') && firebase deploy --only hosting
```

---

## 4. Version Bump (before every Play Store release)

Edit `donkey_master/pubspec.yaml`:
```
version: 1.0.0+4   ← increment +4 → +5 → +6 ...
```
The number after `+` is the **versionCode** (must be unique and increasing on Play Store).
The `1.0.0` part is the human-readable **versionName** (update when features change).

---

## 5. Git — Push Changes

```bash
# From repo root (/Users/godansudha/Projects/AsinuX)

# Stage all changes
git add -A

# Commit
git commit -m "your message here"

# Push to GitHub
git push origin main
```

---

## 6. Firebase — Other Useful Commands

```bash
# List Firebase projects
firebase projects:list

# Check which project is active (run from donkey_master/)
firebase use

# Switch project
firebase use asinux-89da0

# View Hosting deploy history
firebase hosting:channel:list
```

---

## 7. Flutter — Dependency Management

```bash
# Install/update packages after editing pubspec.yaml
flutter pub get

# Check for outdated packages
flutter pub outdated

# Upgrade all packages to latest compatible versions
flutter pub upgrade
```

---

## 8. Clean Build (when builds behave unexpectedly)

```bash
flutter clean && flutter pub get
```
Then re-run your build command. Use this when you see stale cache errors or
unexpected Gradle failures.

---

## 9. AdSense Web Slot IDs (when ready)

Edit `donkey_master/lib/services/admob_service_stub.dart`:
```dart
const _interstitialSlotId = '';      // paste slot ID here
const _rewardedSlotId = '';          // paste slot ID here
```
Then run: `flutter build web --release --dart-define=APP_VERSION=$(grep '^version:' pubspec.yaml | awk '{print $2}') && firebase deploy --only hosting`

---

## 10. Play Store Upload

1. Bump version code in `pubspec.yaml`
2. Run `flutter build appbundle --release`
3. Upload `build/app/outputs/bundle/release/app-release.aab` to:
   Google Play Console → AsinuX → Production → Create new release

---

## Quick Reference

| Task | Command |
|------|---------|
| Build AAB | `flutter build appbundle --release` |
| Deploy web | `flutter build web --release --dart-define=APP_VERSION=$(grep '^version:' pubspec.yaml \| awk '{print $2}') && firebase deploy --only hosting` |
| Run on Chrome | `flutter run -d chrome` |
| Run on Android | `flutter run -d android` |
| Clean build | `flutter clean && flutter pub get` |
| Push to GitHub | `git add -A && git commit -m "msg" && git push origin main` |
