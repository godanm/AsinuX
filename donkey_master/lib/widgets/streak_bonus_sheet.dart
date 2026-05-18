import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/streak_service.dart';

class StreakBonusSheet extends StatefulWidget {
  final StreakStatus status;
  final VoidCallback onClaimed;

  const StreakBonusSheet({
    super.key,
    required this.status,
    required this.onClaimed,
  });

  @override
  State<StreakBonusSheet> createState() => _StreakBonusSheetState();
}

class _StreakBonusSheetState extends State<StreakBonusSheet> {
  bool _claiming = false;
  bool _claimed = false;

  Future<void> _claim() async {
    if (_claiming || _claimed) return;
    setState(() => _claiming = true);
    await Future.delayed(const Duration(milliseconds: 600));
    if (mounted) setState(() { _claiming = false; _claimed = true; });
    await Future.delayed(const Duration(milliseconds: 900));
    if (mounted) {
      widget.onClaimed();
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final day = widget.status.currentDay;
    final reward = widget.status.reward;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF130010),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 36, height: 4,
            decoration: BoxDecoration(
              color: Colors.white12,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),

          // Title
          Text(
            'Day $day Bonus',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ).animate().fadeIn(duration: 300.ms).slideY(begin: -0.2, end: 0),

          const SizedBox(height: 6),
          Text(
            'Log in daily to keep your streak',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 13),
          ),

          const SizedBox(height: 28),

          // Day tiles
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(7, (i) {
              final tileDay = i + 1;
              final isPast = tileDay < day;
              final isCurrent = tileDay == day;
              return _DayTile(
                day: tileDay,
                pts: kStreakRewards[i],
                isPast: isPast,
                isCurrent: isCurrent,
              ).animate(delay: (i * 60).ms).fadeIn(duration: 250.ms).scale(begin: const Offset(0.8, 0.8));
            }),
          ),

          const SizedBox(height: 32),

          // Reward amount
          if (!_claimed)
            Column(
              children: [
                Text(
                  '+$reward',
                  style: const TextStyle(
                    color: Color(0xFFFFD700),
                    fontSize: 42,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ).animate().fadeIn(duration: 400.ms, delay: 300.ms).scale(begin: const Offset(0.7, 0.7)),
                const Text(
                  'points',
                  style: TextStyle(color: Color(0xFFFFD700), fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ],
            )
          else
            const Icon(Icons.check_circle_rounded, color: Color(0xFF00E5FF), size: 52)
                .animate().scale(begin: const Offset(0.3, 0.3), duration: 400.ms, curve: Curves.elasticOut),

          const SizedBox(height: 28),

          // Claim button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _claimed ? null : _claim,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00E5FF),
                disabledBackgroundColor: const Color(0xFF00E5FF).withValues(alpha: 0.4),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: _claiming
                  ? const SizedBox(
                      width: 22, height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.black54),
                    )
                  : Text(
                      _claimed ? 'Claimed!' : 'Claim Bonus',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DayTile extends StatelessWidget {
  final int day;
  final int pts;
  final bool isPast;
  final bool isCurrent;

  const _DayTile({
    required this.day,
    required this.pts,
    required this.isPast,
    required this.isCurrent,
  });

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color border;
    Color textColor;

    if (isPast) {
      bg = const Color(0xFF002a1a);
      border = const Color(0xFF00c850);
      textColor = const Color(0xFF00c850);
    } else if (isCurrent) {
      bg = const Color(0xFF001f2a);
      border = const Color(0xFF00E5FF);
      textColor = const Color(0xFF00E5FF);
    } else {
      bg = const Color(0xFF1a001a);
      border = Colors.white10;
      textColor = Colors.white38;
    }

    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: border, width: isCurrent ? 1.5 : 1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            isPast
                ? Icon(Icons.check_rounded, color: textColor, size: 14)
                : Text(
                    'D$day',
                    style: TextStyle(color: textColor, fontSize: 10, fontWeight: FontWeight.w700),
                  ),
            const SizedBox(height: 3),
            Text(
              '${pts >= 1000 ? '${pts ~/ 1000}k' : pts}',
              style: TextStyle(color: textColor, fontSize: 9, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
