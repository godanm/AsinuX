import 'package:flutter/material.dart';
import '../services/auth_service.dart';

// ── Palette & icon catalogue ─────────────────────────────────────────────────

const avatarColors = [
  Color(0xFFE63946), // crimson
  Color(0xFFFF6B6B), // coral
  Color(0xFFFF9800), // orange
  Color(0xFFFFD700), // gold
  Color(0xFF4CAF50), // green
  Color(0xFF00BCD4), // cyan
  Color(0xFF2196F3), // blue
  Color(0xFF3F51B5), // indigo
  Color(0xFF9C27B0), // purple
  Color(0xFFE91E63), // pink
  Color(0xFF795548), // brown
  Color(0xFF607D8B), // slate
];

const avatarIcons = [
  Icons.person_rounded,
  Icons.face_rounded,
  Icons.mood_rounded,
  Icons.sentiment_very_satisfied_rounded,
  Icons.star_rounded,
  Icons.favorite_rounded,
  Icons.bolt_rounded,
  Icons.local_fire_department_rounded,
  Icons.psychology_rounded,
  Icons.sports_esports_rounded,
  Icons.casino_rounded,
  Icons.auto_awesome_rounded,
];

// ── Helpers ──────────────────────────────────────────────────────────────────

/// Returns the avatar color for a player. Uses their custom preset if set,
/// otherwise falls back to a deterministic hash of their ID.
Color avatarColorFor(String playerId, {AvatarPreset? preset}) {
  if (preset != null && preset.colorIndex >= 0 && preset.colorIndex < avatarColors.length) {
    return avatarColors[preset.colorIndex];
  }
  // deterministic fallback
  final idx = playerId.codeUnits.fold(0, (a, b) => a + b) % avatarColors.length;
  return avatarColors[idx];
}

// ── Widget ───────────────────────────────────────────────────────────────────

/// Renders the local player's avatar, loading the preset from AuthService.
class LocalPlayerAvatar extends StatefulWidget {
  final double radius;
  final String playerId;
  final String playerName;

  const LocalPlayerAvatar({
    super.key,
    required this.radius,
    required this.playerId,
    required this.playerName,
  });

  @override
  State<LocalPlayerAvatar> createState() => _LocalPlayerAvatarState();
}

class _LocalPlayerAvatarState extends State<LocalPlayerAvatar> {
  AvatarPreset _preset = const AvatarPreset(colorIndex: -1, iconIndex: -1);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await AuthService.instance.loadAvatar();
    if (mounted) setState(() => _preset = p);
  }

  @override
  Widget build(BuildContext context) {
    return PlayerAvatarWidget(
      radius: widget.radius,
      playerId: widget.playerId,
      playerName: widget.playerName,
      preset: _preset,
    );
  }
}

/// Stateless avatar widget — pass preset explicitly (for opponents use null).
class PlayerAvatarWidget extends StatelessWidget {
  final double radius;
  final String playerId;
  final String playerName;
  final AvatarPreset? preset;
  final Color? overrideColor; // e.g. green when escaped

  const PlayerAvatarWidget({
    super.key,
    required this.radius,
    required this.playerId,
    required this.playerName,
    this.preset,
    this.overrideColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = overrideColor ?? avatarColorFor(playerId, preset: preset);
    final iconIndex = preset?.iconIndex ?? -1;
    final hasIcon = iconIndex >= 0 && iconIndex < avatarIcons.length;
    final initial = playerName.isNotEmpty ? playerName[0].toUpperCase() : '?';

    return CircleAvatar(
      radius: radius,
      backgroundColor: color,
      child: hasIcon
          ? Icon(avatarIcons[iconIndex], color: Colors.white, size: radius * 1.1)
          : Text(
              initial,
              style: TextStyle(
                fontSize: radius * 0.85,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
    );
  }
}
