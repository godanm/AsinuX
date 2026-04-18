import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import '../services/stats_service.dart';
import '../widgets/ad_banner_widget.dart';
import '../widgets/how_to_play_overlay.dart';
import '../widgets/feedback_sheet.dart';
import '../widgets/player_avatar.dart';
import 'matchmaking_screen.dart';
import 'rummy_matchmaking_screen.dart';
import 'game28_matchmaking_screen.dart';
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
  StreamSubscription<PlayerStats>? _statsSubscription;

  @override
  void initState() {
    super.initState();
    _loadName();
    _loadAvatar();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkFirstLaunch());
  }

  @override
  void dispose() {
    _statsSubscription?.cancel();
    super.dispose();
  }

  Future<void> _checkFirstLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getBool('how_to_play_seen') ?? false;
    if (seen || !mounted) return;
    await prefs.setBool('how_to_play_seen', true);
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1a000e),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Do you know how to play AsinuX?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              showHowToPlay(context);
            },
            child: const Text('No, show me!', style: TextStyle(color: Color(0xFFE63946))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Yes, let\'s play', style: TextStyle(color: Colors.white.withValues(alpha: 0.7))),
          ),
        ],
      ),
    );
  }

  Future<void> _loadName() async {
    final name = await AuthService.instance.getOrCreateDisplayName();
    if (mounted) setState(() { _playerName = name; _nameLoaded = true; });
    // Subscribe to stats stream so the header updates in real-time after games.
    final user = await AuthService.instance.signInAnonymously();
    _statsSubscription?.cancel();
    _statsSubscription = StatsService.instance.statsStream(user.uid).listen((stats) {
      if (mounted) setState(() => _stats = stats);
    });
    // Force a fresh fetch after 2s to catch any stats written just before
    // returning to home (recordRound may still be in-flight when the stream
    // first fires).
    Future.delayed(const Duration(seconds: 2), () async {
      if (!mounted) return;
      final fresh = await StatsService.instance.getStats(user.uid);
      if (mounted) setState(() => _stats = fresh);
    });
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
                // ── Top bar (fixed) ───────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Flexible(
                        child: GestureDetector(
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
                        icon: const Icon(Icons.outlined_flag, color: Colors.white54, size: 22),
                        tooltip: 'Feedback / Report issue',
                        onPressed: () => FeedbackSheet.show(context),
                      ),
                      IconButton(
                        icon: const Icon(Icons.settings_outlined, color: Colors.white54, size: 24),
                        tooltip: 'Settings',
                        onPressed: _openSettings,
                      ),
                    ],
                  ),
                ),

                // ── Scrollable content, vertically centred ────────
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) => SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: constraints.maxHeight),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // ── Logo block ────────────────────────────
                            ShaderMask(
                              shaderCallback: (bounds) => const LinearGradient(
                                colors: [Color(0xFFE63946), Color(0xFFFF6B6B), Color(0xFFFFD700)],
                                stops: [0.0, 0.6, 1.0],
                              ).createShader(bounds),
                              child: const Text(
                                'AsinuX',
                                style: TextStyle(
                                  fontSize: 58,
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

                            const SizedBox(height: 20),

                            // ── Row 1: live games ─────────────────────
                            Row(
                              children: [
                                Expanded(
                                  child: _GameCard(
                                    emoji: '🃏',
                                    title: 'KAZHUTHA',
                                    subtitle: 'Trick-taking · 4 players',
                                    accentColor: const Color(0xFFFF1744),
                                    gradientColors: const [Color(0xFF8B0020), Color(0xFF400010)],
                                    suits: const ['♠', '♥', '♣', '♦'],
                                    enabled: _nameLoaded,
                                    comingSoon: false,
                                    onTap: _startMatch,
                                  ).animate().fadeIn(delay: 400.ms, duration: 500.ms).slideY(begin: 0.1),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _GameCard(
                                    emoji: '🀄',
                                    title: 'RUMMY',
                                    subtitle: '13-card · 2–6 players',
                                    accentColor: const Color(0xFF00E5FF),
                                    gradientColors: const [Color(0xFF004D5C), Color(0xFF002030)],
                                    suits: const ['🂡', '🂱', '🃁', '🃑'],
                                    enabled: _nameLoaded,
                                    comingSoon: false,
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (_) => RummyMatchmakingScreen(playerName: _playerName)),
                                    ),
                                  ).animate().fadeIn(delay: 520.ms, duration: 500.ms).slideY(begin: 0.1),
                                ),
                              ],
                            ),

                            const SizedBox(height: 12),

                            // ── Row 2: coming soon ────────────────────
                            Row(
                              children: [
                                Expanded(
                                  child: _GameCard(
                                    emoji: '🎴',
                                    title: '28',
                                    subtitle: 'Trick-taking · Teams · 4 players',
                                    accentColor: const Color(0xFF00C853),
                                    gradientColors: const [Color(0xFF005C26), Color(0xFF002d13)],
                                    suits: const ['♠', '♣', '♥', '♦'],
                                    enabled: _nameLoaded,
                                    comingSoon: false,
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (_) => Game28MatchmakingScreen(playerName: _playerName)),
                                    ),
                                  ).animate().fadeIn(delay: 640.ms, duration: 500.ms).slideY(begin: 0.1),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _GameCard(
                                    emoji: '🌹',
                                    title: 'TEEN PATTI',
                                    subtitle: '3-card poker · 2–6 players',
                                    accentColor: const Color(0xFF2979FF),
                                    gradientColors: const [Color(0xFF0D3D8B), Color(0xFF061a40)],
                                    suits: const ['♠', '♣', '♥', '♦'],
                                    enabled: false,
                                    comingSoon: true,
                                    onTap: () {},
                                  ).animate().fadeIn(delay: 760.ms, duration: 500.ms).slideY(begin: 0.1),
                                ),
                              ],
                            ),

                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
                    ),
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

// Injected at build time via --dart-define=APP_VERSION=x.y.z+n
const _kAppVersion = String.fromEnvironment('APP_VERSION', defaultValue: '');

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

          const SizedBox(height: 16),
          Center(
            child: Text(
              _kAppVersion.isNotEmpty ? 'AsinuX $_kAppVersion' : 'AsinuX',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.2),
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Game card ─────────────────────────────────────────────────────────────────

class _GameCard extends StatelessWidget {
  final String emoji;
  final String title;
  final String subtitle;
  final Color accentColor;
  final List<Color> gradientColors;
  final List<String> suits;
  final bool enabled;
  final bool comingSoon;
  final VoidCallback onTap;

  const _GameCard({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.accentColor,
    required this.gradientColors,
    required this.suits,
    required this.enabled,
    required this.comingSoon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final canTap = enabled && !comingSoon;

    return GestureDetector(
      onTap: canTap ? onTap : null,
      child: Opacity(
        opacity: comingSoon ? 0.6 : 1.0,
        child: Container(
          height: 160,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: gradientColors,
            ),
            border: Border.all(
              color: accentColor.withValues(alpha: comingSoon ? 0.25 : 0.5),
              width: 1.5,
            ),
            boxShadow: comingSoon
                ? null
                : [
                    BoxShadow(
                      color: accentColor.withValues(alpha: 0.25),
                      blurRadius: 24,
                      spreadRadius: 2,
                    ),
                  ],
          ),
          child: Stack(
            children: [
              // Background suit watermarks
              Positioned(
                bottom: -8, right: 4,
                child: Text(
                  suits[0],
                  style: TextStyle(
                    fontSize: 64,
                    color: accentColor.withValues(alpha: 0.08),
                  ),
                ),
              ),
              Positioned(
                top: -4, left: 4,
                child: Text(
                  suits[1],
                  style: TextStyle(
                    fontSize: 40,
                    color: accentColor.withValues(alpha: 0.06),
                  ),
                ),
              ),

              // Content
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(emoji, style: const TextStyle(fontSize: 32)),
                    const Spacer(),
                    Text(
                      title,
                      style: TextStyle(
                        color: comingSoon
                            ? Colors.white.withValues(alpha: 0.5)
                            : Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.35),
                        fontSize: 10,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 10),
                    // CTA row
                    if (comingSoon)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.15)),
                        ),
                        child: Text(
                          'COMING SOON',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.45),
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                          ),
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              accentColor,
                              accentColor.withValues(alpha: 0.75)
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: accentColor.withValues(alpha: 0.45),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.play_arrow_rounded,
                                color: Colors.white, size: 14),
                            SizedBox(width: 4),
                            Text(
                              'PLAY NOW',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
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
      builder: (_, _) => Container(
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

