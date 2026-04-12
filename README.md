# Kazhutha — Donkey Card Game

A fast-paced multiplayer card game built with Flutter. Play online with real players or bots, dodge the Donkey, and climb the leaderboard.

## Live App

- **Web**: [kazhutha.app](https://kazhutha.app) · [asinux-89da0.web.app](https://asinux-89da0.web.app)
- **Android**: Google Play Store (pending approval)

---

## Features

- **Multiplayer** — real-time matchmaking via Firebase Realtime Database
- **Bot opponents** — Easy / Medium / Hard AI with phase-aware strategy (early/mid/late game, vettu awareness)
- **Animated gameplay** — trick fly-out animations, card slide-ins, haptic feedback
- **AdMob** — rewarded interstitial video ads after each round (Android); AdSense placeholder on web
- **Stats & leaderboard** — per-player win/loss/point tracking
- **Feedback** — in-app report button sends mail to support
- **Privacy policy** at [kazhutha.app/privacy](https://kazhutha.app/privacy)

---

## Tech Stack

| Layer | Technology |
|---|---|
| UI | Flutter (Dart) |
| Backend | Firebase Realtime Database |
| Auth | Firebase Anonymous Auth |
| Hosting | Firebase Hosting |
| Ads (mobile) | Google AdMob — Rewarded Interstitial |
| Ads (web) | Google AdSense (pending) |
| Email feedback | `url_launcher` → `mailto:` |

---

## Project Structure

```
lib/
  main.dart                  # App entry, Firebase init, AdMob init
  models/
    card_model.dart          # PlayingCard, Suit enums
    game_state.dart          # GameState, GamePhase, PlayerOrder
    player_model.dart        # Player model
  screens/
    home_screen.dart         # Home, difficulty picker, shimmer loading
    matchmaking_screen.dart  # Fake join animation, bot name generation
    game_screen.dartf        # Main game table, trick fly-out, haptic
    results_screen.dart      # Round end / game over
    stats_screen.dart        # Player stats
  services/
    admob_service.dart       # Platform conditional export
    admob_service_mobile.dart# Real AdMob (rewarded interstitial)
    admob_service_stub.dart  # Web no-op stub
    auth_service.dart        # Firebase anonymous auth
    bot_service.dart         # Bot AI (Easy/Medium/Hard, phase-aware)
    firebase_service.dart    # Room CRUD, game state sync
    sound_service.dart       # Card play / cut sounds
    stats_service.dart       # Win/loss/points tracking
  utils/
    game_logic.dart          # Trick resolution, cut detection
  widgets/
    ad_banner_widget.dart    # AdMob banner (mobile) / placeholder (web)
    card_widget.dart         # Playing card renderer
    feedback_sheet.dart      # Feedback / bug report bottom sheet
    how_to_play_overlay.dart # Game rules overlay
    player_avatar.dart       # Coloured avatar widget
web/
  privacy.html               # Privacy policy page
store_assets/
  play_store_listing.md      # Play Store copy & data safety answers
  adsense_setup.md           # AdSense setup checklist
  gen_feature_graphic.py     # Generates 1024×500 Play Store banner
  feature_graphic_1024x500.png
```

---

## Running Locally

```bash
# Web
flutter run -d chrome

# Android (connected device or emulator)
flutter run -d android
```

### Environment

- Flutter 3.x / Dart 3.x
- Java 17 required for Android Gradle builds
  ```bash
  export JAVA_HOME=$(/usr/libexec/java_home -v 17)
  ```

---

## Deploy

```bash
# Web → Firebase Hosting
flutter build web --pwa-strategy=none
firebase deploy --only hosting

# Android → Play Store (.aab)
flutter build appbundle --release
# Upload build/app/outputs/bundle/release/app-release.aab to Play Console
```

---

## AdMob Unit IDs

| Placement | Platform | ID |
|---|---|---|
| Banner | Android | `ca-app-pub-9287774769346149/5092029867` |
| Banner | iOS | `ca-app-pub-9287774769346149/2135665202` |
| Rewarded Interstitial | Android | `ca-app-pub-9287774769346149/6714019132` |
| Rewarded Interstitial | iOS | `ca-app-pub-9287774769346149/5400937468` |
| Interstitial (fallback) | Android | `ca-app-pub-9287774769346149/2330135158` |
| Interstitial (fallback) | iOS | `ca-app-pub-9287774769346149/2985712449` |

Debug builds automatically use Google's official test IDs.

---

## Feedback / Support

In-app flag icon → opens mail to **godansudha@gmail.com**  
Privacy contact: **privacy@kazhutha.app**
