# Kazhutha — AsinuX Card Games

Six multiplayer card games in one Flutter app. Play online with real players or bots across Kazhutha, Rummy, Game 28, Teen Patti, Blackjack, and Bluff.

## Live App

- **Web**: [kazhutha.app](https://kazhutha.app) · [asinux-89da0.web.app](https://asinux-89da0.web.app)
- **Android**: Google Play Store (pending approval)

---

## Games

| Game | Type | Players |
|---|---|---|
| Kazhutha | Trick-taking — avoid being the Donkey | 4 |
| Rummy | 13-card Indian Rummy | 2–6 |
| Game 28 | Bidding + trick-taking (teams) | 4 |
| Teen Patti | 3-card Indian poker | 2–6 |
| Blackjack | Beat the dealer to 21 | 1 vs bot |
| Bluff | Deception — empty your hand first | 2–6 |

---

## Web Routes

### Flutter app (catch-all → `index.html`)

| Route | Behaviour |
|---|---|
| `/` | Home screen — all 6 game cards |
| `/kazhutha` | Opens app → auto-navigates to Kazhutha matchmaking |
| `/rummy` | Opens app → auto-navigates to Rummy matchmaking |
| `/game-28` | Opens app → auto-navigates to Game 28 matchmaking |
| `/teen-patti` | Opens app → auto-navigates to Teen Patti matchmaking |
| `/blackjack` | Opens app → auto-navigates to Blackjack game |
| `/bluff` | Opens app → auto-navigates to Bluff game |

Deep-link routing is handled in `HomeScreen._handleWebDeepLink()` — reads `Uri.base.path` after auth completes and pushes the target screen. The first-launch dialog is suppressed on deep-link arrivals.

### Static HTML pages (explicit Firebase Hosting rewrites)

| Route | File | Description |
|---|---|---|
| `/how-to-play` | `web/how-to-play.html` | 6-tab rules page (one tab per game) |
| `/how-to-play/kazhutha` | `web/how-to-play/kazhutha.html` | Redirects → `/how-to-play#kazhutha` |
| `/how-to-play/rummy` | `web/how-to-play/rummy.html` | Redirects → `/how-to-play#rummy` |
| `/how-to-play/game-28` | `web/how-to-play/game-28.html` | Redirects → `/how-to-play#game28` |
| `/how-to-play/teen-patti` | `web/how-to-play/teen-patti.html` | Redirects → `/how-to-play#teen-patti` |
| `/how-to-play/blackjack` | `web/how-to-play/blackjack.html` | Redirects → `/how-to-play#blackjack` |
| `/how-to-play/bluff` | `web/how-to-play/bluff.html` | Redirects → `/how-to-play#bluff` |
| `/about` | `web/about.html` | About page — 6 game cards, tech stack |
| `/privacy` | `web/privacy.html` | Privacy policy |

---

## Features

- **6 card games** — Kazhutha, Rummy, Game 28, Teen Patti, Blackjack, Bluff
- **Multiplayer** — real-time matchmaking via Firebase Realtime Database
- **Bot opponents** — phase-aware AI for every game (Easy / Medium / Hard where applicable)
- **Rewarded ads** — user-initiated "Watch ad → earn bonus pts" in every game; reward always delivered even if rewarded unit is unavailable
- **Interstitial ads** — shown at natural pause points (game exit, between rounds); never mid-play
- **Stats** — per-player win/loss/points tracking, shared pool across all games (floor: 500 pts)
- **Web deep links** — `/kazhutha`, `/rummy`, etc. open the app directly on that game's screen
- **Privacy policy** at [kazhutha.app/privacy](https://kazhutha.app/privacy)

---

## Tech Stack

| Layer | Technology |
|---|---|
| UI | Flutter (Dart) |
| Backend | Firebase Realtime Database |
| Auth | Firebase Anonymous Auth |
| Hosting | Firebase Hosting |
| Ads (mobile) | Google AdMob — Rewarded Interstitial + Interstitial |
| Ads (web) | Google AdSense |
| Analytics | Google Analytics (GA4) |

---

## Project Structure

```
lib/
  main.dart                        # App entry, lifecycle observer (App Open ad)
  screens/
    splash_screen.dart             # Firebase init, auth persistence, 1.8s splash
    home_screen.dart               # 6 game cards, web deep-link routing
    matchmaking_screen.dart        # Kazhutha matchmaking
    game_screen.dart               # Kazhutha game table
    rummy_matchmaking_screen.dart  # Rummy matchmaking
    rummy_game_screen.dart         # Rummy game table
    game28_matchmaking_screen.dart # Game 28 matchmaking
    game28_game_screen.dart        # Game 28 game table
    teen_patti_matchmaking_screen.dart
    teen_patti_game_screen.dart
    blackjack_game_screen.dart     # Blackjack (vs bot, no matchmaking)
    bluff_game_screen.dart         # Bluff (vs bots, no matchmaking)
    stats_screen.dart              # Per-player stats
  services/
    admob_service.dart             # Platform conditional export
    admob_service_mobile.dart      # AdMob: interstitial + rewarded + app open
    admob_service_stub.dart        # Web stub (simulates reward immediately)
    auth_service.dart              # Firebase anonymous auth + display name
    stats_service.dart             # Points pool (_applyPointsDelta, 500pt floor)
    sound_service.dart             # Card play / cut / win sounds
  widgets/
    ad_banner_widget.dart          # AdMob banner (mobile) / AdSense (web)
    card_widget.dart               # Playing card renderer
    feedback_sheet.dart            # Feedback / bug report bottom sheet
    how_to_play_overlay.dart       # In-app rules overlay
    player_avatar.dart             # Coloured avatar widget
web/
  how-to-play.html                 # 6-tab rules page
  how-to-play/
    kazhutha.html                  # Per-game redirect stubs
    rummy.html
    game-28.html
    teen-patti.html
    blackjack.html
    bluff.html
  about.html                       # About page
  privacy.html                     # Privacy policy
store_assets/
  play_store_listing.md            # Play Store copy & data safety answers
  adsense_setup.md                 # AdSense setup checklist
  gen_feature_graphic.py           # Generates 1024×500 Play Store banner
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
flutter build web --dart-define=APP_VERSION=1.0.0+30 --release
firebase deploy --only hosting

# Android → Play Store (.aab)
# 1. Bump version in pubspec.yaml (version: x.y.z+n)
# 2. Build
flutter build appbundle --release
# 3. Upload build/app/outputs/bundle/release/app-release.aab to Play Console
```

---

## Feedback / Support

In-app flag icon → opens mail to **reachgodan@gmail.com**  
Privacy contact: **privacy@kazhutha.app**
