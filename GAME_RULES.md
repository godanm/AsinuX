# AsinuX — Complete Game Rules

---

# KAZHUTHA

## What Kind of Game Is This?

Kazhutha is a **trick-taking card game** for 4 players. The goal is simple: **empty your hand before everyone else**. The last player still holding cards at the end of a round is the **Donkey** — they get eliminated. The game runs as a tournament across multiple rounds until only one player is left standing.

---

## The Setup

- Standard 52-card deck (♠ ♥ ♦ ♣, ranks 2 through Ace)
- Exactly 4 players, each dealt **13 cards**
- Cards are sorted in your hand by suit for visibility
- **The player holding the Ace of Spades always goes first** in round 1

---

## How a Round Works

A round is made up of a series of **tricks**. Each trick, every player plays one card. Once the trick is resolved, someone leads the next one. This repeats until all players except one have emptied their hands.

### Starting a Trick — The Leader

- The **leader** plays any card they choose. That card's suit becomes the **lead suit** for this trick
- The leader can be any player — it rotates based on who wins or loses each trick (explained below)

### Following — What Everyone Else Does

Every other player, going in turn order, must follow these rules:

- **If you have a card of the lead suit** → you MUST play one of those cards. No choice.
- **If you have NO card of the lead suit** → you can play any card from any suit. This is called a **cut** (vettu)

### Two Ways a Trick Can End

**Case 1 — Nobody cuts (all follow suit)**
- All played cards are compared. The player who played the **highest card of the lead suit** wins the trick
- That winner **leads the next trick**
- All played cards are discarded (nobody picks them up)

**Case 2 — Someone cuts (plays a different suit)**
- As soon as a cut happens, the trick **ends immediately** — players still to go don't play
- The player holding the **highest card of the lead suit** on the table must **pick up all the cards** — their own card plus everyone else's played cards go into their hand
- That pickup player **leads the next trick** (they're effectively punished and go again)
- A cut is a weapon: it forces the strongest lead-suit player to absorb the pile

### Card Hierarchy (within a suit)

2 is the lowest, Ace is the highest:

**2 < 3 < 4 < 5 < 6 < 7 < 8 < 9 < 10 < Jack < Queen < King < Ace**

Only cards of the **lead suit** matter when determining the winner or pickup player. Cut cards (different suit) do not compete — they just trigger the cut rule.

---

## Escaping the Round

When a player plays their last card and their hand becomes empty, they **escape**. They are safe for this round. They still sit at the table and watch, but they no longer play cards.

The **first player to escape** in a round earns a score point.

Players escape one by one. As the round narrows, fewer and fewer players remain active.

---

## The Donkey

When only one player is left with cards in their hand, the round ends. That player is the **Donkey** — they are **permanently eliminated** from the tournament. They don't play in future rounds.

There is no redemption: being the Donkey once means you're out.

---

## The Tournament

The game is not just one round — it's a tournament:

- Rounds are played with the remaining (non-eliminated) players
- After each round, the Donkey is eliminated
- The player pool shrinks: 4 → 3 → 2 → 1
- The **last player not eliminated** wins the tournament

When a new round starts, cards are re-dealt evenly among active players, and whoever holds the Ace of Spades leads again.

---

## Turn Order

- Players are seated in a fixed rotation (the order they joined the room)
- Within a trick, play goes clockwise through the rotation
- **Who leads** the next trick is determined by the trick outcome:
  - No cut → the winner (highest lead-suit card) leads
  - Cut → the pickup player (highest lead-suit card) leads
  - If the winner/leader escaped (emptied their hand), the next active player in rotation leads

---

## Bot Behaviour

When you play against bots, they use one of two difficulty levels (randomly assigned):

### Medium Bots
- **Early game** (many cards left): dump high-value cards (Aces, Kings) to get them out of the hand early — but only in suits where nobody is known to be void
- **Mid/late game**: play the lowest safe card to avoid picking up
- **Following suit**: try to stay under the current highest card on the table
- **Cutting**: dump the highest card they have — a free chance to remove a dangerous card

### Hard Bots
Hard bots have **memory** — they track every card played and remember which players have run out of (are "void in") specific suits. With this information they:
- **Target the weakest player**: intentionally lead suits where that player has cards but someone else will cut — forcing the weak player to pick up
- **Drain suits**: if holding 3+ cards of a safe suit early on, they keep leading it to exhaust opponents
- **Dump strategically**: prioritise getting rid of "top cards" (cards that would win the trick if led, guaranteeing a pickup if nobody follows)
- **Never lead into certain death**: they won't lead a suit where every opponent is known void (they'd just pick up their own card)
- **Think time**: medium bots take 1–4 seconds per turn; hard bots take 0.5–2 seconds (react faster)

---

## Strategy Tips

**As a player:**

1. **Suit management**: Track which suits you have few cards in. Leading those suits is risky — if opponents are void, they'll cut and you pick up
2. **Avoid being the highest**: when following suit, try to play a card *below* the current highest on the table. You don't want to win every trick
3. **Use cuts wisely**: cutting forces the strongest card holder to pick up. Time it when you want to hurt a specific opponent — or use it to dump a dangerous high card from your hand
4. **Who leads matters**: if you pick up, you lead next. This can cascade — picking up means more cards, which means more tricks to play, which means more exposure to future cuts
5. **Track escapes**: when someone escapes, they're no longer a threat. Focus on who's close to escaping next and try to block them by cutting their tricks

**Hierarchy reminder**: In any trick, only the suit that was led matters. Playing a high card of the wrong suit never wins or causes a pickup — it just means you successfully cut.

---

## Scoring

- **1st to escape** a round: +1 score point
- **Donkey**: 0 points, eliminated from the tournament
- The in-game leaderboard shows cumulative score across rounds

---

## Quick Reference

| Situation | What happens |
|---|---|
| Everyone follows suit | Highest card wins. Winner leads next |
| Someone cuts | Highest lead-suit player picks up all cards. They lead next |
| You can't follow suit | You MUST cut (play any other card) |
| Your hand is empty | You've escaped — safe for this round |
| Last one with cards | You're the Donkey — eliminated |
| New round | Cards re-dealt, Ace of Spades leads first |

---
---

# RUMMY (13-Card Indian Rummy)

## What Kind of Game Is This?

Rummy is a **draw-and-discard card game** for 2, 4, or 6 players. The goal is to **arrange all 13 cards in your hand into valid melds** (sequences and sets) and declare before anyone else. Players take turns drawing a card and discarding one, building toward a valid declaration.

---

## The Setup

- **Two standard 52-card decks** (104 cards) plus **2 printed Jokers** = 106 cards total
- 2, 4, or 6 players, each dealt **13 cards**
- One card is turned face-up from the remaining deck — its **rank** becomes the **Wild Joker rank** for this game (e.g. if a 7 is turned, all 7s of any suit act as wild jokers)
- Remaining cards form the **closed deck** (face-down draw pile)
- The turned-up wild joker card goes to the **open deck** (face-up discard pile)

---

## The Two Joker Types

### Printed Joker
The card with the Joker face (★). There are 2 in the deck. Worth **0 points** always.

### Wild Joker
Any card whose rank matches the randomly chosen wild joker rank. There are 4 per deck (8 total in the 2-deck game). Worth **0 points** when used as a joker.

Both joker types can **substitute for any card** in a meld.

---

## How a Turn Works

Play moves clockwise. On your turn you must:

1. **Draw** — pick one card from either:
   - The **closed deck** (face-down; you get a mystery card)
   - The **open deck** (face-up; you can see what you're taking)

2. **Discard** — tap any one card from your hand (now 14 cards) to send it to the top of the open deck

Your hand returns to 13 cards. The next player's turn begins.

**Exception — Declare**: instead of discarding at step 2, you may declare if your hand is fully melded (see Declaration below).

---

## Melds — What You're Building

A meld is a group of 3 or more cards that form either a **sequence** or a **set**.

### Sequence (Run)
Three or more cards of the **same suit** in **consecutive rank order**.

Valid: `5♥ 6♥ 7♥` or `Q♠ K♠ A♠` or `3♦ 4♦ 5♦ 6♦`

Jokers can fill gaps:
- `5♥ [JKR] 7♥` — joker substitutes for 6♥ ✓
- `[JKR] 9♣ 10♣` — joker substitutes for 8♣ ✓

**Pure Sequence**: a sequence with **no jokers at all**. You need at least one. Examples: `4♠ 5♠ 6♠` ✓

**Impure Sequence**: a sequence where one or more jokers substitute for missing cards.

### Set (Group)
Three or four cards of the **same rank** from **different suits**.

Valid: `7♠ 7♥ 7♦` or `K♠ K♥ K♦ K♣`

- Duplicate suits are **not allowed**: `7♠ 7♠ 7♥` is invalid
- Sets can contain jokers: `J♠ J♥ [JKR]` — joker substitutes for J♣ or J♦ ✓

---

## Declaration

To win the round you must declare. You can declare **instead of discarding** on your turn (you must have drawn first, so you'll have 14 cards).

Arrange all 14 cards into groups (melds + 1 discard). A valid declaration requires:

1. **Exactly 13 cards** across all melds (14th card goes to discard as normal)
2. **All melds are valid** — every group must be a valid sequence or set
3. **At least 1 pure sequence** (a sequence with no jokers)
4. **At least 2 sequences total** (pure + impure, or 2 pure)

If all four conditions are met → you win the round with **0 penalty points**.

### Invalid Declaration
If you declare but your melds don't meet all four conditions, you receive an **80-point penalty** and the game continues without you.

---

## Dropping

At any point on your turn, you may choose to **drop** instead of playing:

| When you drop | Penalty |
|---|---|
| **First drop** — before you draw (draw phase) | 20 points |
| **Middle drop** — after you draw, before you discard (discard phase) | 40 points |

After dropping you leave the game immediately. If all remaining players drop, the last one standing wins.

---

## Scoring

The **winner** scores **0 points**.

All other players score **penalty points** equal to their **deadwood** — the total point value of cards in their hand that are NOT part of any valid meld. Penalty is capped at **80 points**.

### Card Point Values

| Card | Points |
|---|---|
| Ace | 10 |
| King, Queen, Jack | 10 each |
| 2 – 10 | Face value (2 = 2 pts, 9 = 9 pts, etc.) |
| Printed Joker | 0 |
| Wild Joker (used as joker) | 0 |

---

## Bot Behaviour

Bots fill any empty seats so the table is always full. They play automatically with human-like timing (1.8–2.4 second delays).

### Draw decision
- Always takes from the open deck if the top card:
  - Is any joker (printed or wild)
  - Shares a rank with a card in hand (set potential)
  - Shares a suit and is within 2 ranks of a card in hand (sequence potential)
- Otherwise draws from the closed deck

### Discard decision
Each card is scored by how connected it is to the rest of the hand:
- **+3** per adjacent same-suit card (rank ±1) — direct sequence neighbour
- **+1** per near same-suit card (rank ±2) — joker-bridgeable gap
- **+2** per same-rank different-suit card — set partner

The card with the **lowest connection score** is discarded. Among ties, the **highest-point** card goes first. Jokers are never discarded.

---

## Strategy Tips

1. **Build a pure sequence first** — it's the hardest requirement to meet and you can't declare without one. Prioritise forming it early, even before setting up sets
2. **Watch the open deck** — taking from it reveals your hand to opponents. Only pick up if the card meaningfully improves a partial meld
3. **Don't hold high cards** — unmelded Aces, Kings, Queens and Jacks each cost 10 points. Drop them early if they're not fitting into sequences
4. **Jokers are gold** — never discard a joker. They unlock impure sequences and plug gaps in sets, directly reducing your deadwood
5. **Track discards** — the open deck shows what opponents are throwing away. If someone discards 7♥ and you're building a 7s set, don't count on getting the 7♦ next
6. **Know when to drop** — if your hand is a mess early, a 20-point first drop beats the 80-point cap from a failed declaration later

---

## Quick Reference

| Term | Meaning |
|---|---|
| Closed deck | Face-down draw pile |
| Open deck | Face-up discard pile |
| Wild joker | Cards matching the randomly chosen rank — act as any card |
| Printed joker | The ★ joker cards — act as any card |
| Pure sequence | Run of 3+ same-suit consecutive cards, no jokers |
| Impure sequence | Run of 3+ same-suit consecutive cards, with joker(s) |
| Set | 3–4 same-rank cards from different suits |
| Deadwood | Unmelded cards in hand — their points are your penalty |
| First drop | Leave before drawing — 20 point penalty |
| Middle drop | Leave after drawing — 40 point penalty |
| Invalid declare | Failed declaration — 80 point penalty |
