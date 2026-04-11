import 'package:flutter/material.dart';
import '../models/card_model.dart';

class CardWidget extends StatelessWidget {
  final PlayingCard card;
  final bool isSelected;
  final VoidCallback? onTap;
  final double width;
  final double height;

  const CardWidget({
    super.key,
    required this.card,
    this.isSelected = false,
    this.onTap,
    this.width = 70,
    this.height = 100,
  });

  @override
  Widget build(BuildContext context) {
    final color = card.isRed ? const Color(0xFFD32F2F) : const Color(0xFF1A1A1A);
    final symbol = card.suitSymbol;
    final rank = card.rankLabel;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width == double.infinity ? null : width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? const Color(0xFFE63946) : const Color(0xFFDDDDDD),
            width: isSelected ? 2.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 4,
              offset: const Offset(1, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: Stack(
            children: [
              // Top-left rank — large and bold so it's readable when peeking
              Positioned(
                top: 4,
                left: 5,
                child: _RankSuit(rank: rank, symbol: symbol, color: color, rankSize: 18),
              ),
              // Center suit symbol — only shows when card is fully visible (bottom card)
              Align(
                alignment: const Alignment(0, 0.2),
                child: Text(
                  symbol,
                  style: TextStyle(
                    fontSize: height * 0.42,
                    color: color.withValues(alpha: 0.85),
                    height: 1,
                  ),
                ),
              ),
              // Bottom-right mirrored rank
              Positioned(
                bottom: 4,
                right: 5,
                child: Transform.rotate(
                  angle: 3.14159,
                  child: _RankSuit(rank: rank, symbol: symbol, color: color, rankSize: 18),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RankSuit extends StatelessWidget {
  final String rank;
  final String symbol;
  final Color color;
  final double rankSize;

  const _RankSuit({
    required this.rank,
    required this.symbol,
    required this.color,
    required this.rankSize,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          rank,
          style: TextStyle(
            fontSize: rankSize,
            fontWeight: FontWeight.w900,
            color: color,
            height: 1.0,
          ),
        ),
        Text(
          symbol,
          style: TextStyle(
            fontSize: rankSize * 0.7,
            color: color,
            height: 1.0,
          ),
        ),
      ],
    );
  }
}

class CardBackWidget extends StatelessWidget {
  final double width;
  final double height;

  const CardBackWidget({super.key, this.width = 70, this.height = 100});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF283593), Color(0xFF1A237E)],
        ),
        border: Border.all(color: Colors.white24),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(1, 2)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: Colors.white30, width: 1.5),
          ),
          child: Center(
            child: Icon(
              Icons.style,
              color: Colors.white.withValues(alpha: 0.25),
              size: width * 0.45,
            ),
          ),
        ),
      ),
    );
  }
}
