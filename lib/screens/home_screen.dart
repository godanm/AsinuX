import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/auth_service.dart';
import '../widgets/ad_banner_widget.dart';
import '../widgets/how_to_play_overlay.dart';
import '../widgets/player_avatar.dart';
import '../services/bot_service.dart';
import 'matchmaking_screen.dart';
import 'stats_screen.dart';
// import 'leaderboard_screen.dart'; // TODO: re-enable with leaderboard

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _playerName = '';
  bool _nameLoaded = false;
  AvatarPreset _avatar = const AvatarPreset(colorIndex: -1, iconIndex: -1);

  @override
  void initState() {
    super.initState();
    _loadName();
    _loadAvatar();
  }

  Future<void> _loadName() async {
    final name = await AuthService.instance.getOrCreateDisplayName();
    if (mounted) setState(() { _playerName = name; _nameLoaded = true; });
  }

  Future<void> _loadAvatar() async {
    final preset = await AuthService.instance.loadAvatar();
    if (mounted) setState(() => _avatar = preset);
  }

  void _startMatch() {
    if (_playerName.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MatchmakingScreen(
          playerName: _playerName,
          difficulty: BotDifficulty.medium,
        ),
      ),
    );
  }

  void _openSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1a000e),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _SettingsSheet(
        initialName: _playerName,
        initialAvatar: _avatar,
        onSaved: (name, avatar) {
          setState(() {
            _playerName = name;
            _avatar = avatar;
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0d0007),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Column(
                children: [
                  // ── Top bar ──────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    child: Row(
                      children: [
                        // Avatar + name
                        GestureDetector(
                          onTap: _openSettings,
                          child: Row(
                            children: [
                              PlayerAvatarWidget(
                                radius: 22,
                                playerId: _playerName,
                                playerName: _playerName,
                                preset: _avatar,
                              ),
                              const SizedBox(width: 10),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _nameLoaded ? _playerName : '...',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                  Text(
                                    'Tap to edit',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.55),
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        const Spacer(),

                        // TODO: re-enable leaderboard when ready
                        // IconButton(
                        //   icon: const Icon(Icons.emoji_events_rounded, color: Colors.white54, size: 26),
                        //   tooltip: 'Leaderboard',
                        //   onPressed: () async {
                        //     final user = await AuthService.instance.signInAnonymously();
                        //     if (!mounted) return;
                        //     Navigator.push(context, MaterialPageRoute(
                        //       builder: (_) => LeaderboardScreen(currentUid: user.uid),
                        //     ));
                        //   },
                        // ),

                        // Stats
                        IconButton(
                          icon: const Icon(Icons.bar_chart_rounded, color: Colors.white54, size: 26),
                          tooltip: 'Stats',
                          onPressed: () async {
                            final user = await AuthService.instance.signInAnonymously();
                            if (!mounted) return;
                            Navigator.push(context, MaterialPageRoute(
                              builder: (_) => StatsScreen(uid: user.uid, playerName: _playerName),
                            ));
                          },
                        ),

                        // Help
                        IconButton(
                          icon: const Icon(Icons.help_outline_rounded, color: Colors.white54, size: 26),
                          tooltip: 'How to play',
                          onPressed: () => showHowToPlay(context),
                        ),

                        // Settings
                        IconButton(
                          icon: const Icon(Icons.settings_outlined, color: Colors.white54, size: 26),
                          tooltip: 'Settings',
                          onPressed: _openSettings,
                        ),
                      ],
                    ),
                  ),

                  // ── Title ────────────────────────────────────────
                  const SizedBox(height: 12),
                  Text(
                    'AsinuX',
                    style: TextStyle(
                      fontSize: 56,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 4,
                      foreground: Paint()
                        ..shader = const LinearGradient(
                          colors: [Color(0xFFE63946), Color(0xFFFF6B6B)],
                        ).createShader(const Rect.fromLTWH(0, 0, 300, 60)),
                    ),
                  ).animate().fadeIn(duration: 600.ms).slideY(begin: -0.2),
                  Text(
                    'CARD GAME',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w300,
                      letterSpacing: 10,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ).animate().fadeIn(delay: 200.ms),

                  const Spacer(),

                  // ── Play card ────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: GestureDetector(
                      onTap: _nameLoaded ? _startMatch : null,
                      child: Container(
                        width: double.infinity,
                        height: 160,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFF3d0020), Color(0xFF1a000e)],
                          ),
                          border: Border.all(
                            color: const Color(0xFFE63946).withValues(alpha: 0.4),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFE63946).withValues(alpha: 0.2),
                              blurRadius: 24,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Stack(
                          children: [
                            // Card suit decoration left
                            Positioned(
                              left: 20,
                              top: 0,
                              bottom: 0,
                              child: Center(
                                child: Icon(Icons.style_rounded, size: 56, color: Colors.white.withValues(alpha: 0.55)),
                              ),
                            ),
                            // Card suit decoration right
                            Positioned(
                              right: 20,
                              top: 0,
                              bottom: 0,
                              child: Center(
                                child: Icon(Icons.casino_rounded, size: 56, color: Colors.white.withValues(alpha: 0.55)),
                              ),
                            ),
                            // Center content
                            Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFE63946),
                                      borderRadius: BorderRadius.circular(50),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xFFE63946).withValues(alpha: 0.5),
                                          blurRadius: 16,
                                        ),
                                      ],
                                    ),
                                    child: const Text(
                                      'FIND MATCH',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 16,
                                        letterSpacing: 2,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    'Play against others online',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.4),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ).animate().fadeIn(delay: 400.ms, duration: 600.ms).slideY(begin: 0.15),
                    ),
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
            const AdBannerWidget(),
          ],
        ),
      ),
    );
  }
}

// ── Difficulty picker (kept for future use) ───────────────────────────────────

class _DifficultyPicker extends StatelessWidget {
  final BotDifficulty selected;
  const _DifficultyPicker({required this.selected});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Choose Difficulty',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1)),
          const SizedBox(height: 20),
          ...BotDifficulty.values.map((d) {
            final isSelected = d == selected;
            final color = switch (d) {
              BotDifficulty.easy   => Colors.green.shade600,
              BotDifficulty.medium => Colors.orange.shade600,
              BotDifficulty.hard   => Colors.red.shade600,
            };
            return GestureDetector(
              onTap: () => Navigator.pop(context, d),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(
                  color: isSelected ? color.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: isSelected ? color : Colors.white12, width: isSelected ? 2 : 1),
                ),
                child: Row(
                  children: [
                    Icon(
                      switch (d) {
                        BotDifficulty.easy   => Icons.sentiment_satisfied,
                        BotDifficulty.medium => Icons.sentiment_neutral,
                        BotDifficulty.hard   => Icons.sentiment_very_dissatisfied,
                      },
                      color: color, size: 22,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(d.label, style: TextStyle(color: isSelected ? color : Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                          const SizedBox(height: 2),
                          Text(d.description, style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12)),
                        ],
                      ),
                    ),
                    if (isSelected) Icon(Icons.check_circle, color: color, size: 20),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ── Settings sheet ────────────────────────────────────────────────────────────

class _SettingsSheet extends StatefulWidget {
  final String initialName;
  final AvatarPreset initialAvatar;
  final void Function(String name, AvatarPreset avatar) onSaved;

  const _SettingsSheet({
    required this.initialName,
    required this.initialAvatar,
    required this.onSaved,
  });

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  late final TextEditingController _nameCtrl;
  late int _colorIndex;
  late int _iconIndex;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialName);
    _colorIndex = widget.initialAvatar.colorIndex;
    _iconIndex = widget.initialAvatar.iconIndex;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isNotEmpty) await AuthService.instance.saveDisplayName(name);
    final preset = AvatarPreset(colorIndex: _colorIndex, iconIndex: _iconIndex);
    await AuthService.instance.saveAvatar(preset);
    widget.onSaved(name.isNotEmpty ? name : widget.initialName, preset);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: 24, right: 24, top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Live preview
          Center(
            child: PlayerAvatarWidget(
              radius: 36,
              playerId: _nameCtrl.text.isNotEmpty ? _nameCtrl.text : 'p',
              playerName: _nameCtrl.text.isNotEmpty ? _nameCtrl.text : 'P',
              preset: AvatarPreset(colorIndex: _colorIndex, iconIndex: _iconIndex),
            ),
          ),
          const SizedBox(height: 20),

          // Name field
          const Text('YOUR NAME',
              style: TextStyle(color: Colors.white70, fontSize: 11, letterSpacing: 2)),
          const SizedBox(height: 8),
          TextField(
            controller: _nameCtrl,
            textCapitalization: TextCapitalization.words,
            style: const TextStyle(color: Colors.white),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Enter display name',
              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
              prefixIcon: const Icon(Icons.person_rounded, color: Colors.white54),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.07),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE63946), width: 1.5),
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Color picker
          const Text('AVATAR COLOR',
              style: TextStyle(color: Colors.white70, fontSize: 11, letterSpacing: 2)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: List.generate(avatarColors.length, (i) {
              final selected = _colorIndex == i;
              return GestureDetector(
                onTap: () => setState(() => _colorIndex = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: avatarColors[i],
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected ? Colors.white : Colors.transparent,
                      width: 2.5,
                    ),
                    boxShadow: selected
                        ? [BoxShadow(color: avatarColors[i].withValues(alpha: 0.6), blurRadius: 8)]
                        : null,
                  ),
                  child: selected ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
                ),
              );
            }),
          ),

          const SizedBox(height: 20),

          // Icon picker
          Row(
            children: [
              const Text('AVATAR ICON',
                  style: TextStyle(color: Colors.white70, fontSize: 11, letterSpacing: 2)),
              const SizedBox(width: 8),
              Text('(tap again to use initial)',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 10)),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: List.generate(avatarIcons.length, (i) {
              final selected = _iconIndex == i;
              final bg = _colorIndex >= 0 ? avatarColors[_colorIndex] : const Color(0xFFE63946);
              return GestureDetector(
                onTap: () => setState(() => _iconIndex = selected ? -1 : i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: selected ? bg : Colors.white.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selected ? bg : Colors.white12,
                      width: selected ? 2 : 1,
                    ),
                    boxShadow: selected
                        ? [BoxShadow(color: bg.withValues(alpha: 0.5), blurRadius: 8)]
                        : null,
                  ),
                  child: Icon(avatarIcons[i],
                      color: selected ? Colors.white : Colors.white54, size: 22),
                ),
              );
            }),
          ),

          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE63946),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('SAVE',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 2)),
            ),
          ),
        ],
      ),
    );
  }
}

