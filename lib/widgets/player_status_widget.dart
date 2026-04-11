import 'package:flutter/material.dart';
import '../models/player_model.dart';
import '../widgets/card_widget.dart';

class PlayerStatusWidget extends StatelessWidget {
  final Player player;
  final bool isCurrentUser;
  final bool showCards;
  final bool isCurrentTurn;

  const PlayerStatusWidget({
    super.key,
    required this.player,
    this.isCurrentUser = false,
    this.showCards = false,
    this.isCurrentTurn = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: player.isEliminated
            ? Colors.grey.shade800
            : isCurrentUser
                ? const Color(0xFF220010)
                : Colors.grey.shade900,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCurrentTurn
              ? const Color(0xFFE63946)
              : isCurrentUser
                  ? const Color(0xFFE63946).withValues(alpha: 0.4)
                  : Colors.transparent,
          width: 2,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                player.isEliminated ? Icons.sentiment_dissatisfied : Icons.person,
                color: player.isEliminated ? Colors.grey : Colors.white,
                size: 16,
              ),
              const SizedBox(width: 4),
              Text(
                player.name,
                style: TextStyle(
                  color: player.isEliminated ? Colors.grey : Colors.white,
                  fontWeight: isCurrentUser ? FontWeight.bold : FontWeight.normal,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          if (player.isEliminated) ...[
            const SizedBox(height: 4),
            const Text(
              'OUT',
              style: TextStyle(
                color: Colors.redAccent,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
          ],
          if (showCards && player.hand.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: player.hand
                  .map((c) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 1),
                        child: CardBackWidget(width: 24, height: 34),
                      ))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}
