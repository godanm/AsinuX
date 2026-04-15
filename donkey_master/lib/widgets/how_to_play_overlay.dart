import 'package:flutter/material.dart';

void showHowToPlay(BuildContext context) {
  Navigator.of(context).push(PageRouteBuilder(
    opaque: false,
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.85),
    pageBuilder: (_, _, _) => const _HowToPlayOverlay(),
    transitionsBuilder: (_, animation, _, child) => FadeTransition(
      opacity: animation,
      child: ScaleTransition(
        scale: Tween(begin: 0.95, end: 1.0).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOut),
        ),
        child: child,
      ),
    ),
  ));
}

class _HowToPlayOverlay extends StatelessWidget {
  const _HowToPlayOverlay();

  static const _steps = [
    ('🃏', 'Each player gets 13 cards. The player with Ace of Spades leads first.'),
    ('🔄', 'On your turn, play a card. Others must follow the same suit.'),
    ('✂️', 'If you can\'t follow suit, cut with any card — the lead-suit player picks up all cards.'),
    ('🏃', 'Empty your hand first to escape the round safely.'),
    ('🫏', 'The last player holding cards is the Donkey — eliminated!'),
    ('🏆', 'Last player standing wins. Points: 1st=100, 2nd=60, 3rd=30, Donkey=0.'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 480),
            decoration: BoxDecoration(
              color: const Color(0xFF1a000e),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFE63946).withValues(alpha: 0.3), width: 1.5),
              boxShadow: [
                BoxShadow(color: const Color(0xFFE63946).withValues(alpha: 0.15), blurRadius: 40, spreadRadius: 4),
                BoxShadow(color: Colors.black.withValues(alpha: 0.6), blurRadius: 20),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 20, 16, 20),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.07))),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.help_outline_rounded, color: Color(0xFFE63946), size: 22),
                      const SizedBox(width: 10),
                      const Text(
                        'HOW TO PLAY',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: Icon(Icons.close_rounded, color: Colors.white.withValues(alpha: 0.5), size: 22),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),

                // Steps
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
                  child: Column(
                    children: _steps.map((e) => Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 40, height: 40,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Center(
                              child: Text(e.$1, style: const TextStyle(fontSize: 20)),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: Text(
                                e.$2,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.8),
                                  fontSize: 13.5,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    )).toList(),
                  ),
                ),

                // Got it button
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE63946),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      child: const Text(
                        'GOT IT, LET\'S PLAY',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
