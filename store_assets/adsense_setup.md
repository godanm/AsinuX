# Tricksy web publishing review

## What changed

The root serves visible educational HTML. The lobby is at `/play`, and the eight existing game routes still load Flutter. The loader starts Flutter only on those nine paths. The learning centers share a stylesheet and a small practice script. Questions and explanations are readable as static text.

## Source audit

| Game | Reachable table and actions | Round or match result | Implementation |
| --- | --- | --- | --- |
| Kazhutha | Four seats, one player and three bots. Follow suit or cut when void. Standard ranks within a suit. | A cut awards the pile to the highest lead-suit card. First escape earns a round point. Last holding cards is eliminated. Last surviving seat wins. | `game_logic.dart`, `firebase_service.dart` |
| Game 28 | Four seats in opposite partnerships, three bots. Bid 14–28, pass after an opening bid, choose and reveal trump, follow suit. | J, 9, A, 10 score 3, 2, 1, 1. Bid met determines the scoring team. Standard/high/sweep awards are 1/2/3 game points. Failed declared Thani awards 3 to defenders. | `game28_state.dart`, `game28_service.dart` |
| Rummy | Public tables of 2, 4, or 6 with bot fill. Draw, discard, drop or declare 13 cards in valid groups with two sequences including a pure one. | Winner scores zero. Remaining hand values are capped at 80. Invalid declaration is 80. Session scores accumulate. | `rummy_service.dart`, `functions/src/index.ts` |
| Teen Patti | Four seats, one player and three bots. Blind/Seen, Pack, Chaal, Sideshow and Show use virtual chips. | Trail, pure sequence, sequence, color, pair, high card. Show compares remaining hands and awards the virtual pot. | `teen_patti_state.dart`, `teen_patti_service.dart` |
| Blackjack | One player versus computer. Deal, Hit, Stand, Double Down on eligible two-card hands. | Dealer draws below 17. Equal totals push. Natural pays rounded 1.5 times the stake unless both have naturals. | `blackjack_game_screen.dart` |
| Bluff | One player and three bots. Face-down plays follow an Ace-to-King cycle; challenge the latest claim in its window. | A false claim makes the claimant pick up the pile, a truthful claim makes the challenger pick it up. A final play must survive the challenge. | `bluff_game_screen.dart` |
| Wild Card | Public tables of 2, 4, or 6 with bot fill. Match color, number or action, choose color on Wild, or draw and pass. | Skip/Reverse and immediate draw effects change play. The first empty hand wins. | `wildcard_models.dart`, `wildcard_service.dart` |
| Tambola | Public tables of 2, 4, or 6 with bot fill. Mark called numbers on a 15-number ticket. | Claims validate Early Five, three rows and Full House against called numbers. The first valid claim for a prize wins it. Full House ends the game. | `tambola_models.dart`, `tambola_service.dart` |

The app share action links to the site root. There is no reachable private room-code form or invite URL parser. Kazhutha has dormant lobby code, and public matchmaking stores room IDs in in-app state.

## Hosting release checklist

1. Review and approve the PR. From `donkey_master`, run `flutter pub get` and `flutter build web --release --pwa-strategy=none --dart-define=APP_VERSION=<pubspec version>`.
2. Preview the release directory with `firebase emulators:start --only hosting --project demo-tricksy`. Check the static root and lessons with JavaScript disabled, then exercise all practice controls with JavaScript enabled. Check `/play`, game links, legacy redirects, unknown paths, `robots.txt`, `sitemap.xml`, and `ads.txt`.
3. After explicit release approval, deploy **Hosting only** to the intended Firebase project. Check both connected domains, the preferred host and canonical URLs. Submit the canonical sitemap in Search Console after the release.

## AdSense resubmission checklist

- Confirm account activation and ownership of the intended domain in AdSense. If offered, use the existing ads.txt entry for verification. Verify the live file returns HTTP 200 and matches the account publisher ID.
- This branch pauses AdSense script loading across the website. Check account-level Auto ads and exclusions before any future re-enable. Keep game/loading screens, errors, menus, alerts, and bare navigation pages outside advertising inventory. Review eligible editorial placements individually and keep them clear of interaction controls.
- Confirm current privacy and consent disclosures. Review CMP and regional consent requirements in the account and test the actual consent behavior before enabling serving.
- Review the published site manually against the rejection and only then request review in AdSense. Site approval and any consent configuration are external to this PR.

[Publisher-content policy](https://support.google.com/publisherpolicies/answer/11112688) · [AdSense site readiness](https://support.google.com/adsense/answer/7299563) · [Ads.txt setup](https://support.google.com/adsense/answer/12171612) · [Google consent requirements](https://support.google.com/adsense/answer/13554116)
