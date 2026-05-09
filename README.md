# Tricksy — AsinuX Card Games

Eight multiplayer card games in one Flutter app. Play online with real players or bots across Kazhutha, Rummy, Game 28, Teen Patti, Blackjack, Bluff, Tambola, and Wild Card.

## Live App

- **Web**: [tricksy.app](https://tricksy.app) · [kazhutha.app](https://kazhutha.app)
- **Android**: Google Play Store (pending production approval)

---

## Games

| Game | Type | Players |
|---|---|---|
| Kazhutha | Trick-taking — avoid being the Donkey | 4 |
| Rummy | 13-card Indian Rummy — declare to win | 2–6 |
| Game 28 | Bidding + trick-taking (teams) | 4 |
| Teen Patti | 3-card Indian poker | 2–6 |
| Blackjack | Beat the dealer to 21 | 1 vs bot |
| Bluff | Deception — empty your hand first | 2–6 |
| Tambola | 90-number Housie / Bingo | 2–6 |
| Wild Card | UNO-style colour matching | 2–6 |

---

## Web Routes

### Flutter app (catch-all → `index.html`)

| Route | Behaviour |
|---|---|
| `/` | Home screen — all 8 game cards |
| `/kazhutha` | Opens app → auto-navigates to Kazhutha matchmaking |
| `/rummy` | Opens app → auto-navigates to Rummy matchmaking |
| `/game-28` | Opens app → auto-navigates to Game 28 matchmaking |
| `/teen-patti` | Opens app → auto-navigates to Teen Patti matchmaking |
| `/blackjack` | Opens app → auto-navigates to Blackjack game |
| `/bluff` | Opens app → auto-navigates to Bluff game |
| `/tambola` | Opens app → auto-navigates to Tambola matchmaking |
| `/wildcard` | Opens app → auto-navigates to Wild Card matchmaking |

Deep-link routing is handled in `HomeScreen._handleWebDeepLink()` — reads `Uri.base.path` after auth completes and pushes the target screen. The first-launch dialog is suppressed on deep-link arrivals via `_kDeepLinkPaths`.

### Static HTML pages (explicit Firebase Hosting rewrites)

| Route | File | Description |
|---|---|---|
| `/games/kazhutha` | `web/games/kazhutha.html` | Kazhutha rules + SEO |
| `/games/rummy` | `web/games/rummy.html` | Rummy rules + SEO |
| `/games/28` | `web/games/28.html` | Game 28 rules + SEO |
| `/games/teen-patti` | `web/games/teen-patti.html` | Teen Patti rules + SEO |
| `/games/blackjack` | `web/games/blackjack.html` | Blackjack rules + SEO |
| `/games/bluff` | `web/games/bluff.html` | Bluff rules + SEO |
| `/games/tambola` | `web/games/tambola.html` | Tambola rules + SEO |
| `/games/wildcard` | `web/games/wildcard.html` | Wild Card rules + SEO |
| `/how-to-play` | `web/how-to-play.html` | All-games rules hub |
| `/about` | `web/about.html` | About page |
| `/privacy` | `web/privacy.html` | Privacy policy |

---

## Features

- **8 card games** — Kazhutha, Rummy, Game 28, Teen Patti, Blackjack, Bluff, Tambola, Wild Card
- **Multiplayer** — real-time matchmaking via Firebase Realtime Database
- **Bot opponents** — phase-aware AI for every game; bots fill empty seats after a short wait
- **Error logging** — three-layer system: `GameGuard` mixin (service-level) → `FlutterError.onError` → `PlatformDispatcher.onError`; all errors written to `error_logs/$uid` in RTDB
- **Feedback diagnostics** — in-app feedback sheet attaches the user's recent error log entries and game session history automatically
- **Atomic prize claims** — Tambola prize claims use Firebase transactions to prevent race conditions in concurrent multiplayer
- **Rewarded ads** — user-initiated "Watch ad → earn bonus pts"; reward always delivered even if ad unit unavailable
- **Interstitial ads** — shown at natural pause points (game exit, between rounds); never mid-play
- **Stats** — per-player win/loss/points tracking across all games (floor: 500 pts)
- **Web deep links** — `/kazhutha`, `/tambola`, `/wildcard`, etc. open the app directly on that game's screen, first-launch dialog suppressed
- **Privacy policy** at [tricksy.app/privacy](https://tricksy.app/privacy)

---

## Tech Stack

| Layer | Technology |
|---|---|
| UI | Flutter (Dart) — Web + Android |
| Backend | Firebase Realtime Database |
| Auth | Firebase Anonymous Auth |
| Functions | Firebase Cloud Functions (Node.js / TypeScript) |
| Hosting | Firebase Hosting (tricksy.app + kazhutha.app) |
| Ads (mobile) | Google AdMob — Rewarded Interstitial + Interstitial |
| Ads (web) | Google AdSense |
| Analytics | Google Analytics (GA4) |

---

## Project Structure

```
lib/
  main.dart                              # App entry; global FlutterError + PlatformDispatcher handlers
  screens/
    splash_screen.dart                   # Firebase init, auth persistence, 1.8s splash
    home_screen.dart                     # 8 game cards, web deep-link routing
    matchmaking_screen.dart              # Kazhutha matchmaking
    game_screen.dart                     # Kazhutha game table
    rummy_matchmaking_screen.dart
    rummy_game_screen.dart
    game28_matchmaking_screen.dart
    game28_game_screen.dart
    teen_patti_matchmaking_screen.dart
    teen_patti_game_screen.dart
    blackjack_game_screen.dart           # Blackjack (vs bot, no matchmaking)
    bluff_game_screen.dart               # Bluff (vs bots, no matchmaking)
    tambola_matchmaking_screen.dart
    tambola_lobby_screen.dart            # Host lobby + bot fill before game starts
    tambola_game_screen.dart
    wildcard_matchmaking_screen.dart
    wildcard_game_screen.dart
    leaderboard_screen.dart
    stats_screen.dart
  services/
    admob_service.dart                   # Platform conditional export
    admob_service_mobile.dart            # AdMob: interstitial + rewarded + app open
    admob_service_stub.dart              # Web stub (simulates reward immediately)
    auth_service.dart                    # Firebase anonymous auth + display name
    error_log_service.dart               # RTDB error logging + GameGuard mixin
    firebase_service.dart                # Kazhutha game logic
    game28_service.dart
    game_logger.dart                     # Per-room event log (gamelogs/ node)
    rummy_service.dart
    rummy_bot_service.dart
    stats_service.dart
    sound_service.dart
    tambola_service.dart
    teen_patti_service.dart
    wildcard_service.dart
  models/
    game28_state.dart
    rummy_models.dart
    tambola_models.dart
    wildcard_models.dart
  utils/
    game_session_tracker.dart            # SharedPreferences log of recent rooms (for feedback)
  widgets/
    ad_banner_widget.dart
    card_widget.dart
    feedback_sheet.dart                  # Attaches error logs + recent rooms on submit
    how_to_play_overlay.dart
    player_avatar.dart
functions/
  src/index.ts                           # dealRummyGame, declareRummyGame, dailyCleanup
web/
  games/
    kazhutha.html  rummy.html  28.html   # Per-game SEO pages
    teen-patti.html  blackjack.html
    bluff.html  tambola.html  wildcard.html
  blog/                                  # Blog posts for AdSense content review
  how-to-play.html
  about.html  privacy.html  terms.html
purge.sh                                 # Manual full-wipe of all transactional RTDB data
database.rules.json                      # Firebase RTDB security rules
store_assets/
  play_store_listing.md
  adsense_setup.md
  gen_feature_graphic.py
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

- Flutter SDK ^3.10 / Dart SDK ^3.10
- Java 17 required for Android Gradle builds
  ```bash
  export JAVA_HOME=$(/usr/libexec/java_home -v 17)
  ```

---

## Deploy

```bash
# Web → Firebase Hosting
flutter build web --release --dart-define=APP_VERSION=1.0.0+33
firebase deploy --only hosting

# Android → Play Store (.aab)
# 1. Bump version code in pubspec.yaml
# 2. Build
flutter build appbundle --release
# 3. Upload build/app/outputs/bundle/release/app-release.aab to Play Console

# Firebase Functions (after editing functions/src/index.ts)
cd functions && npm run build && cd ..
firebase deploy --only functions

# RTDB rules (after editing database.rules.json)
firebase deploy --only database
```

### Maintenance

```bash
# Manual purge of all transactional RTDB data (keeps stats)
./purge.sh          # prompts for confirmation
./purge.sh --yes    # non-interactive
```

The `dailyCleanup` Cloud Function runs at 02:00 UTC and automatically purges data older than 7 days across all game nodes, feedback, and error logs.

---

## Error Logging

Errors are written to `error_logs/$uid` in RTDB. Three capture points:

1. **`GameGuard` mixin** — wraps service methods with `guarded('opName', fn)`; logs game + operation context before rethrowing
2. **`FlutterError.onError`** — catches all widget/framework errors
3. **`PlatformDispatcher.instance.onError`** — catches all unhandled async errors

All locally-caught exceptions in screens and services also call `ErrorLogService.instance.logAuto()` before showing user-facing error messages, so swallowed errors are still captured.

---

## Feedback / Support

In-app feedback sheet (flag icon) → writes to `feedback/` node in RTDB with uid, platform, version, recent error log references, and recent game room history.

Privacy contact: **privacy@kazhutha.app**
