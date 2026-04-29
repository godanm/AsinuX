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

class _SplashScreenState extends State<SplashScreen> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    FirebaseAnalytics.instance;
    if (kIsWeb) {
      await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
    }
    if (!kIsWeb) await AdMobService.instance.initialize();
    await SoundService.instance.initialize();
    await Future.delayed(const Duration(milliseconds: 2000));
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
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1a0008),
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.2),
            radius: 1.2,
            colors: [Color(0xFF3d0018), Color(0xFF0d0006)],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // App icon
              Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(32),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFE63946).withValues(alpha: 0.35),
                      blurRadius: 40,
                      spreadRadius: 4,
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(32),
                  child: Image.asset(
                    'assets/images/tricksy_icon.jpg',
                    fit: BoxFit.cover,
                  ),
                ),
              )
                  .animate()
                  .fadeIn(duration: 600.ms)
                  .scale(begin: const Offset(0.8, 0.8), end: const Offset(1, 1), duration: 600.ms, curve: Curves.easeOutBack),

              const SizedBox(height: 32),

              // Title
              ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [Color(0xFFFFD250), Color(0xFFFFA040)],
                ).createShader(bounds),
                child: const Text(
                  'Tricksy',
                  style: TextStyle(
                    fontSize: 52,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 4,
                    color: Colors.white,
                  ),
                ),
              ).animate().fadeIn(delay: 300.ms, duration: 500.ms).slideY(begin: 0.15, end: 0),

              const SizedBox(height: 8),

              Text(
                'Outsmart the table.',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withValues(alpha: 0.45),
                  fontStyle: FontStyle.italic,
                  letterSpacing: 1,
                ),
              ).animate().fadeIn(delay: 600.ms, duration: 500.ms),

              const SizedBox(height: 56),

              // Loading dots
              AnimatedOpacity(
                opacity: _ready ? 0 : 1,
                duration: const Duration(milliseconds: 300),
                child: _LoadingDots(),
              ),
            ],
          ),
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
                ? const Color(0xFFFFD250)
                : Colors.white.withValues(alpha: 0.2),
          ),
        );
      }),
    );
  }
}
