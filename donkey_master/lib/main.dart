import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/splash_screen.dart';
import 'services/admob_service.dart';
import 'services/error_log_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Catch widget/framework errors on both web and Android.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    ErrorLogService.instance.logAuto(
      game: 'flutter_error',
      error: details.exceptionAsString(),
      stack: details.stack,
      context: {'library': details.library ?? ''},
    );
  };

  // Catch uncaught async/Dart errors that escape the Flutter zone.
  PlatformDispatcher.instance.onError = (error, stack) {
    ErrorLogService.instance.logAuto(
      game: 'uncaught_error',
      error: error.toString(),
      stack: stack,
    );
    return true;
  };

  runApp(const DonkeyMasterApp());
}

class DonkeyMasterApp extends StatefulWidget {
  const DonkeyMasterApp({super.key});

  @override
  State<DonkeyMasterApp> createState() => _DonkeyMasterAppState();
}

class _DonkeyMasterAppState extends State<DonkeyMasterApp>
    with WidgetsBindingObserver {

  static final navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (kIsWeb) HardwareKeyboard.instance.addHandler(_handleKey);
  }

  @override
  void dispose() {
    if (kIsWeb) HardwareKeyboard.instance.removeHandler(_handleKey);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  bool _handleKey(KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      navigatorKey.currentState?.maybePop();
      return true;
    }
    return false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!kIsWeb && state == AppLifecycleState.resumed) {
      AdMobService.instance.showAppOpenAd();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tricksy',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFFD700),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const SplashScreen(),
    );
  }
}
