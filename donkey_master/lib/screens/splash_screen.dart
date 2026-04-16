import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';
import '../firebase_options.dart';
import '../services/admob_service.dart';
import '../services/sound_service.dart';
import 'home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _donkeyController;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _donkeyController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _init();
  }

  Future<void> _init() async {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    FirebaseAnalytics.instance; // activate analytics collection on all platforms
    // On web, persist auth across browser restarts so returning users keep their profile
    if (kIsWeb) {
      await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
    }
    if (!kIsWeb) await AdMobService.instance.initialize();
    await SoundService.instance.initialize();
    // Minimum splash time so animation is visible
    await Future.delayed(const Duration(milliseconds: 1800));
    if (mounted) setState(() => _ready = true);
    await Future.delayed(const Duration(milliseconds: 400));
    if (mounted) {
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondary) => const HomeScreen(),
          transitionsBuilder: (context, anim, secondary, child) =>
              FadeTransition(opacity: anim, child: child),
          transitionDuration: const Duration(milliseconds: 400),
        ),
      );
    }
  }

  @override
  void dispose() {
    _donkeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0d0007),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Donkey emoji with bounce
            AnimatedBuilder(
              animation: _donkeyController,
              builder: (context, child) => Transform.translate(
                offset: Offset(0, -12 * _donkeyController.value),
                child: const Text('🫏', style: TextStyle(fontSize: 96)),
              ),
            ),
            const SizedBox(height: 24),

            // Title
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [Color(0xFFE63946), Color(0xFFFF6B6B)],
              ).createShader(bounds),
              child: const Text(
                'AsinuX',
                style: TextStyle(
                  fontSize: 52,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 4,
                  color: Colors.white,
                ),
              ),
            ).animate().fadeIn(delay: 300.ms, duration: 500.ms).slideY(begin: 0.2),

            const SizedBox(height: 8),

            Text(
              "Don't be the AsinuX!",
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withValues(alpha: 0.4),
                fontStyle: FontStyle.italic,
                letterSpacing: 1,
              ),
            ).animate().fadeIn(delay: 600.ms, duration: 500.ms),

            const SizedBox(height: 48),

            // Loading dots
            AnimatedOpacity(
              opacity: _ready ? 0 : 1,
              duration: const Duration(milliseconds: 300),
              child: _LoadingDots(),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingDots extends StatefulWidget {
  @override
  State<_LoadingDots> createState() => _LoadingDotsState();
}

class _LoadingDotsState extends State<_LoadingDots> {
  int _step = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (mounted) setState(() => _step = (_step + 1) % 4);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        final active = i < _step;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 10 : 7,
          height: active ? 10 : 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active
                ? const Color(0xFFE63946)
                : Colors.white.withValues(alpha: 0.2),
          ),
        );
      }),
    );
  }
}
