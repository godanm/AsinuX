# AsinuX (Kazhutha) — Complete Game Logic

## What Kind of Game Is This?

AsinuX is a **trick-taking card game** for 4 players. The goal is simple: **empty your hand before everyone else**. The last player still holding cards at the end of a round is the **Donkey** — they get eliminated. The game runs as a tournament across multiple rounds until only one player is left standing.

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
