# Next Android Release — Pending Changes

## Bug Fixes

### Rummy
- **Bot stuck in discard/draw phase** (`rummy_game_screen.dart`)
  The `_lastBotActionKey` guard prevented any retry after a silent failure (web timer
  throttle, network hiccup, out-of-bounds index). Fixed: key is cleared after each bot
  action completes; if the state hasn't advanced, a self-retry fires after 3 seconds.
  *(Web already fixed and deployed — Android needs this build.)*

## New Features

- **In-app share button** — one-tap WhatsApp/share message with game invite link
  (currently players have to copy-paste the room code manually)

## Notes
- Current production version: `1.0.0+35`
- Next version should be: `1.0.0+36` (bump pubspec.yaml before building AAB)
