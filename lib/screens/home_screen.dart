import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/auth_service.dart';
import '../services/stats_service.dart';
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
  PlayerStats _stats = const PlayerStats();
  BotDifficulty _difficulty = BotDifficulty.easy;

  @override
  void initState() {
    super.initState();
    _loadName();
    _loadAvatar();
  }

  Future<void> _loadName() async {
    final name = await AuthService.instance.getOrCreateDisplayName();
    if (mounted) setState(() { _playerName = name; _nameLoaded = true; });
    // Load stats once name/uid is ready
    final user = await AuthService.instance.signInAnonymously();
    final stats = await StatsService.instance.getStats(user.uid);
    if (mounted) setState(() => _stats = stats);
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
          difficulty: _difficulty,
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
      backgroundColor: const Color(0xFF0a0008),
      body: Stack(
        children: [
          // ── Background suit watermarks ────────────────────────
          Positioned.fill(child: _SuitWatermarks()),

          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      // ── Top bar ────────────────────────────────
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(
                          children: [
                            GestureDetector(
                              onTap: _nameLoaded ? _openSettings : null,
                              child: Row(
                                children: [
                                  Stack(
                                    children: [
                                      _nameLoaded
                                          ? PlayerAvatarWidget(
                                              radius: 22,
                                              playerId: _playerName,
                                              playerName: _playerName,
                                              preset: _avatar,
                                            )
                                          : _Shimmer(width: 44, height: 44, radius: 22),
                                      if (_nameLoaded)
                                        Positioned(
                                          bottom: 0, right: 0,
                                          child: Container(
                                            width: 14, height: 14,
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFE63946),
                                              shape: BoxShape.circle,
                                              border: Border.all(color: const Color(0xFF0a0008), width: 1.5),
                                            ),
                                            child: const Icon(Icons.edit, size: 8, color: Colors.white),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(width: 10),
                                  _nameLoaded
                                      ? Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              _playerName,
                                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                            ),
                                            Text(
                                              '${_stats.totalPoints} pts',
                                              style: TextStyle(color: const Color(0xFFFFD700).withValues(alpha: 0.85), fontSize: 11, fontWeight: FontWeight.w600),
                                            ),
                                          ],
                                        )
                                      : Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            _Shimmer(width: 90, height: 12, radius: 6),
                                            const SizedBox(height: 5),
                                            _Shimmer(width: 55, height: 10, radius: 5),
                                          ],
                                        ),
                                ],
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              icon: const Icon(Icons.bar_chart_rounded, color: Colors.white54, size: 24),
                              tooltip: 'Stats',
                              onPressed: () async {
                                final user = await AuthService.instance.signInAnonymously();
                                if (!mounted) return;
                                Navigator.push(context, MaterialPageRoute(
                                  builder: (_) => StatsScreen(uid: user.uid, playerName: _playerName),
                                ));
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.help_outline_rounded, color: Colors.white54, size: 24),
                              tooltip: 'How to play',
                              onPressed: () => showHowToPlay(context),
                            ),
                            IconButton(
                              icon: const Icon(Icons.settings_outlined, color: Colors.white54, size: 24),
                              tooltip: 'Settings',
                              onPressed: _openSettings,
                            ),
                          ],
                        ),
                      ),

                      // ── Logo block ─────────────────────────────
                      const SizedBox(height: 8),
                      ShaderMask(
                        shaderCallback: (bounds) => const LinearGradient(
                          colors: [Color(0xFFE63946), Color(0xFFFF6B6B), Color(0xFFFFD700)],
                          stops: [0.0, 0.6, 1.0],
                        ).createShader(bounds),
                        child: const Text(
                          'AsinuX',
                          style: TextStyle(
                            fontSize: 64,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 6,
                            color: Colors.white,
                          ),
                        ),
                      ).animate().fadeIn(duration: 600.ms).slideY(begin: -0.15),
                      Text(
                        '— THE CARD GAME —',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w400,
                          letterSpacing: 8,
                          color: Colors.white.withValues(alpha: 0.35),
                        ),
                      ).animate().fadeIn(delay: 300.ms),

                      const Spacer(),

                      // ── Quick stats strip ──────────────────────
                      if (_stats.roundsPlayed > 0)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _QuickStat(label: 'Rounds', value: '${_stats.roundsPlayed}'),
                              _QuickStatDivider(),
                              _QuickStat(label: 'Escaped', value: '${_stats.escapeCount}', color: Colors.greenAccent.shade400),
                              _QuickStatDivider(),
                              _QuickStat(label: 'Donkey', value: '${_stats.donkeyCount}', color: Colors.redAccent),
                            ],
                          ),
                        ).animate().fadeIn(delay: 400.ms),

                      const SizedBox(height: 20),

                      // ── Play button ────────────────────────────
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: GestureDetector(
                          onTap: _nameLoaded ? _startMatch : null,
                          child: Container(
                            width: double.infinity,
                            height: 140,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(28),
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0xFF5c0a1a), Color(0xFF2a0010), Color(0xFF1a000a)],
                                stops: [0.0, 0.5, 1.0],
                              ),
                              border: Border.all(color: const Color(0xFFE63946).withValues(alpha: 0.5), width: 1.5),
                              boxShadow: [
                                BoxShadow(color: const Color(0xFFE63946).withValues(alpha: 0.3), blurRadius: 32, spreadRadius: 4),
                                BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 12),
                              ],
                            ),
                            child: Stack(
                              children: [
                                // Left suit icons
                                Positioned(
                                  left: 16, top: 0, bottom: 0,
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text('♠', style: TextStyle(fontSize: 28, color: Colors.white.withValues(alpha: 0.6))),
                                      Text('♣', style: TextStyle(fontSize: 22, color: Colors.white.withValues(alpha: 0.35))),
                                    ],
                                  ),
                                ),
                                // Right suit icons
                                Positioned(
                                  right: 16, top: 0, bottom: 0,
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text('♥', style: TextStyle(fontSize: 28, color: const Color(0xFFE63946).withValues(alpha: 0.7))),
                                      Text('♦', style: TextStyle(fontSize: 22, color: const Color(0xFFE63946).withValues(alpha: 0.4))),
                                    ],
                                  ),
                                ),
                                // Center
                                Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 12),
                                        decoration: BoxDecoration(
                                          gradient: const LinearGradient(
                                            colors: [Color(0xFFE63946), Color(0xFFc0182a)],
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                          ),
                                          borderRadius: BorderRadius.circular(50),
                                          boxShadow: [
                                            BoxShadow(color: const Color(0xFFE63946).withValues(alpha: 0.6), blurRadius: 20, spreadRadius: 1),
                                          ],
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
                                            SizedBox(width: 6),
                                            Text(
                                              'PLAY NOW',
                                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17, letterSpacing: 2),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Matchmaking with 3 players',
                                        style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 11, letterSpacing: 0.5),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ).animate().fadeIn(delay: 500.ms, duration: 500.ms).slideY(begin: 0.1),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // ── Difficulty selector ────────────────────
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.psychology_rounded,
                                    size: 13,
                                    color: Colors.white.withValues(alpha: 0.35)),
                                const SizedBox(width: 5),
                                Text(
                                  'BOT DIFFICULTY',
                                  style: TextStyle(
                                    fontSize: 10,
                                    letterSpacing: 2,
                                    color: Colors.white.withValues(alpha: 0.35),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: BotDifficulty.values.map((d) {
                                final selected = _difficulty == d;
                                final color = switch (d) {
                                  BotDifficulty.easy   => const Color(0xFF4CAF50),
                                  BotDifficulty.medium => const Color(0xFFFF9800),
                                  BotDifficulty.hard   => const Color(0xFFE63946),
                                };
                                final icon = switch (d) {
                                  BotDifficulty.easy   => Icons.sentiment_satisfied_rounded,
                                  BotDifficulty.medium => Icons.sentiment_neutral_rounded,
                                  BotDifficulty.hard   => Icons.sentiment_very_dissatisfied_rounded,
                                };
                                return Expanded(
                                  child: GestureDetector(
                                    onTap: () => setState(() => _difficulty = d),
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 200),
                                      margin: const EdgeInsets.symmetric(horizontal: 4),
                                      padding: const EdgeInsets.symmetric(vertical: 10),
                                      decoration: BoxDecoration(
                                        color: selected
                                            ? color.withValues(alpha: 0.15)
                                            : Colors.white.withValues(alpha: 0.04),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: selected ? color : Colors.white.withValues(alpha: 0.1),
                                          width: selected ? 1.5 : 1,
                                        ),
                                      ),
                                      child: Column(
                                        children: [
                                          Icon(icon,
                                              color: selected ? color : Colors.white.withValues(alpha: 0.3),
                                              size: 20),
                                          const SizedBox(height: 4),
                                          Text(
                                            d.label.toUpperCase(),
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 1,
                                              color: selected ? color : Colors.white.withValues(alpha: 0.3),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ).animate().fadeIn(delay: 600.ms),

                      const SizedBox(height: 24),
                    ],
                  ),
                ),
                const AdBannerWidget(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Background suit watermarks ────────────────────────────────────────────────

class _SuitWatermarks extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Stack(
      children: [
        // Top-right ♥
        Positioned(
          top: -30, right: -20,
          child: Transform.rotate(
            angle: math.pi / 12,
            child: Text('♥', style: TextStyle(fontSize: 180, color: const Color(0xFFE63946).withValues(alpha: 0.06))),
          ),
        ),
        // Bottom-left ♠
        Positioned(
          bottom: -20, left: -20,
          child: Transform.rotate(
            angle: -math.pi / 10,
            child: Text('♠', style: TextStyle(fontSize: 160, color: Colors.white.withValues(alpha: 0.04))),
          ),
        ),
        // Mid ♦
        Positioned(
          top: size.height * 0.38, right: -10,
          child: Text('♦', style: TextStyle(fontSize: 100, color: const Color(0xFFE63946).withValues(alpha: 0.04))),
        ),
        // Mid-left ♣
        Positioned(
          top: size.height * 0.45, left: -10,
          child: Text('♣', style: TextStyle(fontSize: 90, color: Colors.white.withValues(alpha: 0.03))),
        ),
      ],
    );
  }
}

// ── Quick stat pill ───────────────────────────────────────────────────────────

class _QuickStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _QuickStat({required this.label, required this.value, this.color = Colors.white});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.w900)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 10, letterSpacing: 1)),
      ],
    );
  }
}

class _QuickStatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1, height: 28,
      margin: const EdgeInsets.symmetric(horizontal: 24),
      color: Colors.white.withValues(alpha: 0.1),
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

// ── Shimmer skeleton block ────────────────────────────────────────────────────

class _Shimmer extends StatefulWidget {
  final double width;
  final double height;
  final double radius;

  const _Shimmer({required this.width, required this.height, required this.radius});

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))
      ..repeat(reverse: true);
    _anim = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius),
          color: Color.lerp(
            Colors.white.withValues(alpha: 0.07),
            Colors.white.withValues(alpha: 0.18),
            _anim.value,
          ),
        ),
      ),
    );
  }
}

