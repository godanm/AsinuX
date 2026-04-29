import 'package:flutter/material.dart';

// ── Public entry points ───────────────────────────────────────────────────────

/// Opens the game selector. Tap a game to see its rule cards.
void showHowToPlay(BuildContext context, {String? game}) {
  Navigator.of(context).push(PageRouteBuilder(
    opaque: false,
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.88),
    pageBuilder: (_, _, _) => _HowToPlayOverlay(initialGame: game),
    transitionsBuilder: (_, animation, _, child) => FadeTransition(
      opacity: animation,
      child: ScaleTransition(
        scale: Tween(begin: 0.96, end: 1.0).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOut),
        ),
        child: child,
      ),
    ),
  ));
}

// ── Rule card model ───────────────────────────────────────────────────────────

class _Card {
  final String emoji;
  final String title;
  final String body;
  final List<String> bullets;
  const _Card({required this.emoji, required this.title, required this.body, this.bullets = const []});
}

// ── Game definitions ──────────────────────────────────────────────────────────

class _Game {
  final String id;
  final String emoji;
  final String title;
  final String subtitle;
  final Color accent;
  final List<Color> gradientColors;
  final List<_Card> cards;
  const _Game({
    required this.id,
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.gradientColors,
    required this.cards,
  });
}

const _games = <_Game>[
  _Game(
    id: '28',
    emoji: '🃏',
    title: 'GAME 28',
    subtitle: 'Trick-taking · 4 players · 2 teams',
    accent: Color(0xFF00c6ff),
    gradientColors: [Color(0xFF003a4a), Color(0xFF001a26)],
    cards: [
      _Card(
        emoji: '🏆',
        title: 'Objective',
        body: 'Win 6 game points (or the target) before the other team. Teams bid on tricks and must score at least their bid to earn points.',
        bullets: [
          '4 players in 2 teams (A & B)',
          'First team to reach the target wins',
          'A round = one full set of 8 tricks',
        ],
      ),
      _Card(
        emoji: '🃏',
        title: 'Cards & Points',
        body: 'Only 8 ranks are used (J, 9, A, 10, K, Q, 8, 7). Card points are counted when you win a trick.',
        bullets: [
          'Jack = 3 points',
          'Nine = 2 points',
          'Ace = 1 point, Ten = 1 point',
          'K, Q, 8, 7 = 0 points',
          'Total in the deck = 28 points',
        ],
      ),
      _Card(
        emoji: '🎯',
        title: 'Bidding',
        body: 'Each player gets 4 cards to bid on. Bid how many card points your team will win. Highest bidder wins; remaining 4 cards are dealt after.',
        bullets: [
          'Bid from 14 (minimum) up to 28',
          'First bidder must open — cannot pass',
          'Partner rule: must bid 20+ to outbid your own partner',
          'Bid winner secretly chooses a trump suit',
        ],
      ),
      _Card(
        emoji: '🔄',
        title: 'Playing Tricks',
        body: 'Follow the lead suit if you have it. The highest card of the lead suit wins — unless trump is revealed.',
        bullets: [
          'Trump beats any non-trump card',
          'Bid winner cannot voluntarily lead trump',
          'To reveal trump: be void in lead suit, then ask for trump',
          'Once trump is revealed, it applies for the rest of the round',
        ],
      ),
      _Card(
        emoji: '📊',
        title: 'Scoring',
        body: 'After all 8 tricks, compare the bid team\'s card points against their bid to award game points.',
        bullets: [
          'Bid met: +1 game point (bid ≥ 20: +2 pts)',
          'All 28 points (Thani!): +3 game points',
          'Bid failed: defending team gets the game points',
          'First team to the target score wins the game!',
        ],
      ),
    ],
  ),
  _Game(
    id: 'kazhutha',
    emoji: '🃏',
    title: 'DONKEY',
    subtitle: 'Trick-taking · 4 players',
    accent: Color(0xFFE63946),
    gradientColors: [Color(0xFF5c0a1a), Color(0xFF2a0010)],
    cards: [
      _Card(
        emoji: '🏃',
        title: 'Objective',
        body: 'Empty your hand before everyone else. The last player still holding cards is eliminated as the Donkey.',
        bullets: [
          '4 players, 13 cards each',
          'Survive rounds to win the tournament',
          'Last player standing wins',
        ],
      ),
      _Card(
        emoji: '🃏',
        title: 'Setup',
        body: 'Cards are dealt evenly from a standard 52-card deck. The player holding the Ace of Spades leads first.',
        bullets: [
          'Standard deck, no jokers',
          'Ace of Spades always leads round 1',
          'Cards are sorted by suit in your hand',
        ],
      ),
      _Card(
        emoji: '🔄',
        title: 'Playing a Trick',
        body: 'The leader plays any card — that suit is the lead suit. Everyone else must follow the same suit if they can.',
        bullets: [
          'Must follow the lead suit if you have it',
          'Highest lead-suit card wins the trick',
          'Winner leads the next trick',
        ],
      ),
      _Card(
        emoji: '✂️',
        title: 'The Cut',
        body: 'If you have no cards of the lead suit, play any card. This is a cut — the trick ends immediately.',
        bullets: [
          'The player with the highest lead-suit card picks up all played cards',
          'The pickup player leads the next trick',
          'Use cuts to force dangerous high cards onto opponents',
        ],
      ),
      _Card(
        emoji: '🏆',
        title: 'Escaping & Scoring',
        body: 'Play your last card to escape the round. Points are awarded for order of escape.',
        bullets: [
          '1st to escape: +100 pts',
          '2nd to escape: +60 pts',
          '3rd to escape: +30 pts',
          'Donkey (last player): −50 pts, eliminated',
        ],
      ),
    ],
  ),
  _Game(
    id: 'teen_patti',
    emoji: '🌹',
    title: 'TEEN PATTI',
    subtitle: '3-card poker · 2–6 players',
    accent: Color(0xFF2979FF),
    gradientColors: [Color(0xFF0D3D8B), Color(0xFF061a40)],
    cards: [
      _Card(
        emoji: '🏆',
        title: 'Objective',
        body: 'A 3-card betting game. Each player gets three cards and bets chips into the pot. The last player standing — or the strongest hand at showdown — wins the entire pot.',
        bullets: [
          '2–6 players, one pot',
          'Everyone starts Blind (cards face-down)',
          'Fold, call (Chaal), or raise each turn',
          'Winner takes the whole pot',
        ],
      ),
      _Card(
        emoji: '🃏',
        title: 'Hand Rankings',
        body: 'Hands are ranked from strongest to weakest. Suit tie-breaker order: Spades > Hearts > Diamonds > Clubs.',
        bullets: [
          'Trail — three of a kind (best)',
          'Pure Sequence — straight flush (same suit)',
          'Sequence — straight (any suits)',
          'Color — flush (same suit, not consecutive)',
          'Pair — two of a kind',
          'High Card — none of the above (worst)',
        ],
      ),
      _Card(
        emoji: '👁️',
        title: 'Blind vs Seen',
        body: 'You start Blind — your cards are hidden even from you. Tap "See Cards" on your turn to become Seen. Playing Blind costs half as much, but you\'re betting without seeing your hand.',
        bullets: [
          'Blind: Chaal costs 1× stake, Raise costs 2× stake',
          'Seen: Chaal costs 2× stake, Raise costs 4× stake',
          'You can see your cards at any time on your turn',
          'Once Seen, you cannot go back to Blind',
        ],
      ),
      _Card(
        emoji: '🎯',
        title: 'Your Actions',
        body: 'On your turn choose one action. If only 2 players remain you can also call a Show to force a reveal.',
        bullets: [
          'Chaal — match the current stake and stay in',
          'Raise — double the bet and increase the stake',
          'Fold — give up your cards and exit the round',
          'See Cards — reveal your hand (become Seen)',
          'Sideshow — privately compare hands with the previous player (both must be Seen, 3+ active)',
          'Show — compare hands when only 2 players remain',
        ],
      ),
      _Card(
        emoji: '🤝',
        title: 'Sideshow & Showdown',
        body: 'Sideshow lets two Seen players compare hands privately — the weaker hand folds immediately. A tie means the requester folds.',
        bullets: [
          'Sideshow target can accept or reject',
          'Rejection: game continues, no one folds',
          'Show cost: both Seen = full stake; Seen vs Blind = half stake',
          'Tie at Show: the caller loses (non-caller wins)',
          'Pot limit hit → all active hands are revealed, best hand wins and splits ties',
        ],
      ),
    ],
  ),
  _Game(
    id: 'rummy',
    emoji: '🀄',
    title: 'RUMMY',
    subtitle: '13-card · 2–6 players',
    accent: Color(0xFF1565C0),
    gradientColors: [Color(0xFF0a1a4a), Color(0xFF050d26)],
    cards: [
      _Card(
        emoji: '🏆',
        title: 'Objective',
        body: 'Arrange all 13 cards into valid melds — sequences and sets — then declare before anyone else.',
        bullets: [
          '2, 4, or 6 players',
          'First valid declaration wins',
          'Others score penalty points for unmelded cards',
        ],
      ),
      _Card(
        emoji: '🃏',
        title: 'Setup',
        body: 'Two standard decks (104 cards) plus 2 printed Jokers. One card is turned face-up — its rank becomes the Wild Joker for this game.',
        bullets: [
          'Each player gets 13 cards',
          'Wild jokers substitute for any card in a meld',
          'Printed jokers (★) also substitute for any card',
        ],
      ),
      _Card(
        emoji: '🔄',
        title: 'Your Turn',
        body: 'Draw one card then discard one card every turn. Build your hand toward valid melds.',
        bullets: [
          'Draw from the closed deck (face-down) or open deck (face-up)',
          'Taking from the open deck is visible to all opponents',
          'Always discard down to 13 cards',
        ],
      ),
      _Card(
        emoji: '🧩',
        title: 'Melds',
        body: 'A sequence is 3+ same-suit consecutive cards. A set is 3–4 same-rank different-suit cards.',
        bullets: [
          'You need at least 1 pure sequence (no jokers)',
          'You need at least 2 sequences total',
          'Jokers can fill gaps in sequences and sets',
          'Example sequence: 5♥ 6♥ 7♥ or 5♥ [JKR] 7♥',
        ],
      ),
      _Card(
        emoji: '🏳️',
        title: 'Drop & Declare',
        body: 'Drop out early to limit your penalty, or declare when all 13 cards are melded.',
        bullets: [
          'First drop (before drawing): 20 pts penalty',
          'Middle drop (after drawing): 40 pts penalty',
          'Invalid declaration: 80 pts penalty',
          'Winner scores 0 — others score their unmelded card points (capped at 80)',
        ],
      ),
    ],
  ),
  _Game(
    id: 'blackjack',
    emoji: '🃏',
    title: 'BLACKJACK',
    subtitle: 'Beat the dealer · 1 player vs house',
    accent: Color(0xFFFFD700),
    gradientColors: [Color(0xFF3D2800), Color(0xFF1A1000)],
    cards: [
      _Card(
        emoji: '🏆',
        title: 'Objective',
        body: 'Beat the dealer by getting a hand value closer to 21 without going over. You play against the house — not other players.',
        bullets: [
          'Get closer to 21 than the dealer',
          'Go over 21 and you "bust" — instant loss',
          'Dealer busts? You win automatically',
          'Equal totals = push (bet returned)',
        ],
      ),
      _Card(
        emoji: '🃏',
        title: 'Card Values',
        body: 'Number cards are worth their face value. Face cards are worth 10. Aces are flexible.',
        bullets: [
          '2–10 = face value',
          'Jack, Queen, King = 10',
          'Ace = 11 or 1 — whichever keeps you under 21',
          'Ace + any 10-value card = Blackjack (best hand!)',
        ],
      ),
      _Card(
        emoji: '🎯',
        title: 'Your Actions',
        body: 'After the deal you have three moves. Choose wisely based on your total and the dealer\'s visible card.',
        bullets: [
          'Hit — draw another card',
          'Stand — keep your hand and end your turn',
          'Double Down — double your bet, draw exactly one card, then stand (only on first two cards)',
        ],
      ),
      _Card(
        emoji: '🤖',
        title: 'Dealer Rules',
        body: 'The dealer follows fixed rules — no strategy, no choices. One of the dealer\'s two cards is hidden until your turn ends.',
        bullets: [
          'Dealer always hits until reaching 17 or more',
          'Dealer stands on 17 and above',
          'Hidden card is revealed after you stand or bust',
        ],
      ),
      _Card(
        emoji: '💰',
        title: 'Payouts',
        body: 'Your winnings depend on how you won. Blackjack pays a bonus over a regular win.',
        bullets: [
          'Regular win → +1× your bet',
          'Blackjack (Ace + 10-value) → +1.5× your bet',
          'Push (tie) → bet returned, no gain or loss',
          'Bust or lower total → lose your bet',
        ],
      ),
    ],
  ),
  _Game(
    id: 'bluff',
    emoji: '🤫',
    title: 'BLUFF',
    subtitle: 'Deception · 4 players',
    accent: Color(0xFFAB47BC),
    gradientColors: [Color(0xFF2D0040), Color(0xFF130020)],
    cards: [
      _Card(
        emoji: '🏆',
        title: 'Objective',
        body: 'Be the first player to get rid of all your cards. The catch — you can lie about what you play, and everyone else can call you out.',
        bullets: [
          '4 players, full 52-card deck dealt evenly',
          'Cards are played face-down — no one sees what you really put down',
          'First to empty their hand wins',
        ],
      ),
      _Card(
        emoji: '🃏',
        title: 'Playing a Turn',
        body: 'On your turn, place 1 to 4 cards face-down on the pile and declare their rank. The declared rank must be one step higher than the previous player\'s declared rank.',
        bullets: [
          'Declare a rank: e.g. "Two 8s" or "One King"',
          'Rank must follow the sequence (previous + 1)',
          'After King the sequence resets to Ace',
          'You may tell the truth or lie — that\'s the game',
        ],
      ),
      _Card(
        emoji: '😤',
        title: 'Calling Bluff',
        body: 'Any player can shout "Bluff!" after someone plays. The cards just played are flipped over and checked.',
        bullets: [
          'Bluffer caught → bluffer picks up the entire pile',
          'Challenge was wrong → challenger picks up the entire pile',
          'Either way the pile resets and the next turn begins',
        ],
      ),
      _Card(
        emoji: '🎭',
        title: 'When to Bluff',
        body: 'Bluffing is the heart of the game. Lie when you don\'t have the required rank. Tell the truth when you do — or when a lie would be too obvious.',
        bullets: [
          'Watch how many cards others pick up — big hands = desperate plays',
          'Bluff when you\'re running low and need to dump cards fast',
          'Call bluff on unusually large plays (4 of the same rank is rare)',
          'Poker face matters — bots never flinch!',
        ],
      ),
      _Card(
        emoji: '💡',
        title: 'Tips & Strategy',
        body: 'The best Bluff players balance deception with credibility. Getting caught too often means a mountain of cards.',
        bullets: [
          'Don\'t bluff every turn — build trust, then strike',
          'Call bluff early in the game when the pile is small (low risk)',
          'Save your real cards for when the sequence matches',
          'Watch opponents\' hesitation before they play',
        ],
      ),
    ],
  ),
];

// ── Root overlay widget ───────────────────────────────────────────────────────

class _HowToPlayOverlay extends StatefulWidget {
  final String? initialGame;
  const _HowToPlayOverlay({this.initialGame});

  @override
  State<_HowToPlayOverlay> createState() => _HowToPlayOverlayState();
}

class _HowToPlayOverlayState extends State<_HowToPlayOverlay> {
  String? _activeGameId;

  @override
  void initState() {
    super.initState();
    _activeGameId = widget.initialGame;
  }

  _Game? get _activeGame {
    if (_activeGameId == null) return null;
    final match = _games.where((g) => g.id == _activeGameId).toList();
    return match.isEmpty ? null : match.first;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500, maxHeight: 680),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.04, 0),
                    end: Offset.zero,
                  ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
                  child: child,
                ),
              ),
              child: _activeGame == null
                  ? _GameSelector(
                      key: const ValueKey('selector'),
                      onGameSelected: (id) => setState(() => _activeGameId = id),
                      onClose: () => Navigator.pop(context),
                    )
                  : _RuleCards(
                      key: ValueKey(_activeGameId),
                      game: _activeGame!,
                      onBack: () => setState(() => _activeGameId = null),
                      onClose: () => Navigator.pop(context),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Game selector (2×2 grid) ──────────────────────────────────────────────────

class _GameSelector extends StatelessWidget {
  final void Function(String id) onGameSelected;
  final VoidCallback onClose;

  const _GameSelector({super.key, required this.onGameSelected, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0f0015),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          _OverlayHeader(title: 'HOW TO PLAY', onClose: onClose),

          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: Column(
              children: [
                Text(
                  'Select a game to learn the rules',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.35),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 20),

                // 2×2 grid
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.35,
                  children: _games.map((g) => _GameTile(
                        game: g,
                        onTap: () => onGameSelected(g.id),
                      )).toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GameTile extends StatelessWidget {
  final _Game game;
  final VoidCallback onTap;
  const _GameTile({required this.game, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: game.gradientColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: game.accent.withValues(alpha: 0.4)),
          boxShadow: [
            BoxShadow(color: game.accent.withValues(alpha: 0.2), blurRadius: 12),
          ],
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(game.emoji, style: const TextStyle(fontSize: 24)),
            const Spacer(),
            Text(
              game.title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              game.subtitle,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 10,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text(
                  'Learn rules',
                  style: TextStyle(color: game.accent, fontSize: 10, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 3),
                Icon(Icons.arrow_forward_rounded, color: game.accent, size: 11),
              ],
            ),
          ],
        ),
      ),
    );
  }
}


// ── Swipeable rule cards ──────────────────────────────────────────────────────

class _RuleCards extends StatefulWidget {
  final _Game game;
  final VoidCallback onBack;
  final VoidCallback onClose;

  const _RuleCards({super.key, required this.game, required this.onBack, required this.onClose});

  @override
  State<_RuleCards> createState() => _RuleCardsState();
}

class _RuleCardsState extends State<_RuleCards> {
  late final PageController _pageCtrl;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController();
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  void _next() {
    if (_page < widget.game.cards.length - 1) {
      _pageCtrl.nextPage(duration: const Duration(milliseconds: 280), curve: Curves.easeInOut);
    } else {
      widget.onBack();
    }
  }

  void _prev() {
    if (_page > 0) {
      _pageCtrl.previousPage(duration: const Duration(milliseconds: 280), curve: Curves.easeInOut);
    } else {
      widget.onBack();
    }
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final total = game.cards.length;
    final isLast = _page == total - 1;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0f0015),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: game.accent.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(color: game.accent.withValues(alpha: 0.12), blurRadius: 40, spreadRadius: 2),
        ],
      ),
      child: Column(
        children: [
          // Header with back + game title + close
          Container(
            padding: const EdgeInsets.fromLTRB(8, 12, 16, 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.07))),
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: widget.onBack,
                  icon: Icon(Icons.arrow_back_rounded, color: Colors.white.withValues(alpha: 0.6), size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 8),
                Text(game.emoji, style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 6),
                Text(
                  game.title,
                  style: TextStyle(
                    color: game.accent,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                  ),
                ),
                const Spacer(),
                // Page indicator
                Text(
                  '${_page + 1} / $total',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 12),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: widget.onClose,
                  child: Icon(Icons.close_rounded, color: Colors.white.withValues(alpha: 0.4), size: 20),
                ),
              ],
            ),
          ),

          // Swipeable cards
          Expanded(
            child: PageView.builder(
              controller: _pageCtrl,
              itemCount: total,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (_, i) {
                final card = game.cards[i];
                return _RuleCardPage(card: card, accent: game.accent);
              },
            ),
          ),

          // Dot indicators + nav buttons
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              children: [
                // Dots
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(total, (i) => AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _page ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: i == _page
                          ? game.accent
                          : Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  )),
                ),
                const SizedBox(height: 14),
                // Nav row
                Row(
                  children: [
                    if (_page > 0)
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _prev,
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: Text('BACK',
                              style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.5),
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1)),
                        ),
                      )
                    else
                      const Expanded(child: SizedBox()),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: _next,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: game.accent,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          elevation: 0,
                        ),
                        child: Text(
                          isLast ? 'GOT IT!' : 'NEXT',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RuleCardPage extends StatelessWidget {
  final _Card card;
  final Color accent;
  const _RuleCardPage({required this.card, required this.accent});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Big emoji + title
          Row(
            children: [
              Container(
                width: 52, height: 52,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: accent.withValues(alpha: 0.3)),
                ),
                child: Center(child: Text(card.emoji, style: const TextStyle(fontSize: 26))),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  card.title.toUpperCase(),
                  style: TextStyle(
                    color: accent,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Body text
          Text(
            card.body,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75),
              fontSize: 14,
              height: 1.55,
            ),
          ),

          if (card.bullets.isNotEmpty) ...[
            const SizedBox(height: 16),
            ...card.bullets.map((b) => Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    width: 5, height: 5,
                    decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      b,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            )),
          ],
        ],
      ),
    );
  }
}

// ── Shared header ─────────────────────────────────────────────────────────────

class _OverlayHeader extends StatelessWidget {
  final String title;
  final VoidCallback onClose;
  const _OverlayHeader({required this.title, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 18, 16, 18),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.07))),
      ),
      child: Row(
        children: [
          const Icon(Icons.help_outline_rounded, color: Colors.white54, size: 20),
          const SizedBox(width: 10),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 15,
              letterSpacing: 1.5,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: onClose,
            child: Icon(Icons.close_rounded, color: Colors.white.withValues(alpha: 0.45), size: 22),
          ),
        ],
      ),
    );
  }
}
