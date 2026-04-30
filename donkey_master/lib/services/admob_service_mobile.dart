import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class AdMobService {
  static final AdMobService _instance = AdMobService._();
  static AdMobService get instance => _instance;
  AdMobService._();

  // ── Ad Unit IDs ──────────────────────────────────────────────
  // Debug mode uses Google's official test IDs so ads always render locally.
  // Real IDs serve once the app is live and AdMob-approved.

  static String get bannerAdUnitId {
    if (kDebugMode) {
      return Platform.isAndroid
          ? 'ca-app-pub-3940256099942544/6300978111'
          : 'ca-app-pub-3940256099942544/2934735716';
    }
    return Platform.isAndroid
        ? 'ca-app-pub-9287774769346149/5092029867'
        : 'ca-app-pub-9287774769346149/2135665202';
  }

  // Standard interstitial — shown when player quits mid-game (shared across all games)
  static String get interstitialAdUnitId {
    if (kDebugMode) {
      return Platform.isAndroid
          ? 'ca-app-pub-3940256099942544/1033173712'
          : 'ca-app-pub-3940256099942544/4411468910';
    }
    return Platform.isAndroid
        ? 'ca-app-pub-9287774769346149/2330135158'
        : 'ca-app-pub-9287774769346149/2985712449';
  }

  // App Open Ad — shown when app is foregrounded
  static String get appOpenAdUnitId {
    if (kDebugMode) {
      return Platform.isAndroid
          ? 'ca-app-pub-3940256099942544/9257395921'
          : 'ca-app-pub-3940256099942544/9257395921';
    }
    return Platform.isAndroid
        ? 'ca-app-pub-9287774769346149/5755022612'
        : 'ca-app-pub-9287774769346149/REPLACE_IOS_APP_OPEN_ID';
  }

  // Per-game rewarded ad unit IDs.
  // TODO: Create one "Rewarded Interstitial" unit per game in AdMob console, then
  //       paste the IDs below. Until filled in, all placements fall back to the
  //       shared unit so existing behaviour is unchanged.
  static const _androidRewardedIds = <String, String>{
    'kazhutha':  '', // TODO: Kazhutha_Rewarded (Android)
    'rummy':     '', // TODO: Rummy_Rewarded (Android)
    'teenPatti': '', // TODO: TeenPatti_Rewarded (Android)
    'game28':    '', // TODO: 28_Rewarded (Android)
    'blackjack': '', // TODO: Blackjack_Rewarded (Android)
    'bluff':     '', // TODO: Bluff_Rewarded (Android)
  };
  static const _iosRewardedIds = <String, String>{
    'kazhutha':  '', // TODO: Kazhutha_Rewarded (iOS)
    'rummy':     '', // TODO: Rummy_Rewarded (iOS)
    'teenPatti': '', // TODO: TeenPatti_Rewarded (iOS)
    'game28':    '', // TODO: 28_Rewarded (iOS)
    'blackjack': '', // TODO: Blackjack_Rewarded (iOS)
    'bluff':     '', // TODO: Bluff_Rewarded (iOS)
  };
  // Shared fallback used until game-specific IDs are filled in
  static const _androidRewardedShared = 'ca-app-pub-9287774769346149/6714019132';
  static const _iosRewardedShared     = 'ca-app-pub-9287774769346149/5400937468';

  static String _rewardedUnitIdFor(String placement) {
    if (kDebugMode) {
      return Platform.isAndroid
          ? 'ca-app-pub-3940256099942544/5354046379'
          : 'ca-app-pub-3940256099942544/6978759866';
    }
    if (Platform.isAndroid) {
      final id = _androidRewardedIds[placement] ?? '';
      return id.isNotEmpty ? id : _androidRewardedShared;
    }
    final id = _iosRewardedIds[placement] ?? '';
    return id.isNotEmpty ? id : _iosRewardedShared;
  }

  // ── State ────────────────────────────────────────────────────

  InterstitialAd? _interstitialAd;
  bool _isInterstitialReady = false;
  Completer<void>? _interstitialLoadCompleter;

  RewardedInterstitialAd? _rewardedAd;
  bool _isRewardedReady = false;
  Completer<void>? _rewardedLoadCompleter;
  String _rewardedPlacement = ''; // which placement is currently pre-loaded

  AppOpenAd? _appOpenAd;
  bool _isAppOpenReady = false;
  DateTime? _appOpenLoadTime;

  /// Set to true while inside an active game to suppress the App Open ad.
  bool suppressAppOpenAd = false;

  Future<void> initialize() async {
    await MobileAds.instance.initialize();
    _loadInterstitial();
    _loadRewarded();
    _loadAppOpen();
  }

  // ── Loaders ──────────────────────────────────────────────────

  void _loadInterstitial() {
    _interstitialLoadCompleter = Completer<void>();
    debugPrint('[AdMob] loading interstitial (${kDebugMode ? "TEST" : "LIVE"}) $interstitialAdUnitId');
    InterstitialAd.load(
      adUnitId: interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          debugPrint('[AdMob] interstitial loaded ✓');
          _interstitialAd = ad;
          _isInterstitialReady = true;
          _interstitialLoadCompleter?.complete();
          _interstitialLoadCompleter = null;
        },
        onAdFailedToLoad: (error) {
          debugPrint('[AdMob] interstitial FAILED TO LOAD: ${error.code} ${error.message} domain=${error.domain}');
          _isInterstitialReady = false;
          _interstitialLoadCompleter?.complete();
          _interstitialLoadCompleter = null;
          Future.delayed(const Duration(seconds: 30), _loadInterstitial);
        },
      ),
    );
  }

  void _loadRewarded([String placement = '']) {
    _rewardedPlacement = placement;
    final unitId = _rewardedUnitIdFor(placement);
    _rewardedLoadCompleter = Completer<void>();
    debugPrint('[AdMob] loading rewarded (${kDebugMode ? "TEST" : "LIVE"} placement=$placement) $unitId');
    RewardedInterstitialAd.load(
      adUnitId: unitId,
      request: const AdRequest(),
      rewardedInterstitialAdLoadCallback: RewardedInterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          debugPrint('[AdMob] rewarded loaded ✓ placement=$placement');
          _rewardedAd = ad;
          _isRewardedReady = true;
          _rewardedLoadCompleter?.complete();
          _rewardedLoadCompleter = null;
        },
        onAdFailedToLoad: (error) {
          debugPrint('[AdMob] rewarded FAILED TO LOAD: ${error.code} ${error.message} domain=${error.domain}');
          _isRewardedReady = false;
          _rewardedLoadCompleter?.complete();
          _rewardedLoadCompleter = null;
          Future.delayed(const Duration(minutes: 2), () => _loadRewarded(placement));
        },
      ),
    );
  }

  // ── Show methods (awaitable — complete when ad is dismissed) ──

  /// Show standard interstitial (shared exit ad, no placement needed).
  Future<void> showInterstitialAsync([BuildContext? context]) async {
    debugPrint('[AdMob] showInterstitialAsync — ready=$_isInterstitialReady');
    if (!_isInterstitialReady || _interstitialAd == null) {
      final pending = _interstitialLoadCompleter;
      if (pending != null && !pending.isCompleted) {
        debugPrint('[AdMob] interstitial not ready — waiting for load…');
        await pending.future.timeout(
          const Duration(seconds: 5),
          onTimeout: () {},
        );
      }
      if (!_isInterstitialReady || _interstitialAd == null) {
        debugPrint('[AdMob] interstitial still not ready after wait — skipping');
        return;
      }
    }

    final completer = Completer<void>();
    _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        debugPrint('[AdMob] interstitial dismissed');
        ad.dispose();
        _interstitialAd = null;
        _isInterstitialReady = false;
        _loadInterstitial();
        if (!completer.isCompleted) completer.complete();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint('[AdMob] interstitial FAILED TO SHOW: ${error.code} ${error.message}');
        ad.dispose();
        _interstitialAd = null;
        _isInterstitialReady = false;
        _loadInterstitial();
        if (!completer.isCompleted) completer.complete();
      },
    );
    _interstitialAd!.show();
    await completer.future;
  }

  /// Show rewarded interstitial for a specific game [placement].
  /// Falls back to standard interstitial if not ready.
  /// [onRewarded] fires only when the user completes the ad and earns the reward.
  Future<void> showRewardedAsync({
    BuildContext? context,
    VoidCallback? onRewarded,
    String placement = '',
  }) async {
    debugPrint('[AdMob] showRewardedAsync placement=$placement — rewarded=$_isRewardedReady interstitial=$_isInterstitialReady');

    // If cached ad is for a different game, dispose and reload with the right ID.
    if (_isRewardedReady && _rewardedAd != null && _rewardedPlacement != placement) {
      debugPrint('[AdMob] rewarded placement mismatch ($_rewardedPlacement → $placement) — reloading');
      _rewardedAd!.dispose();
      _rewardedAd = null;
      _isRewardedReady = false;
      _loadRewarded(placement);
    }

    // Wait for rewarded to finish loading if it isn't ready yet
    if (!_isRewardedReady || _rewardedAd == null) {
      final pending = _rewardedLoadCompleter;
      if (pending != null && !pending.isCompleted) {
        debugPrint('[AdMob] rewarded not ready — waiting for load…');
        await pending.future.timeout(
          const Duration(seconds: 5),
          onTimeout: () {},
        );
      }
    }

    if (_isRewardedReady && _rewardedAd != null) {
      final completer = Completer<void>();
      _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (ad) {
          debugPrint('[AdMob] rewarded dismissed');
          ad.dispose();
          _rewardedAd = null;
          _isRewardedReady = false;
          _loadRewarded(placement);
          if (!completer.isCompleted) completer.complete();
        },
        onAdFailedToShowFullScreenContent: (ad, error) {
          debugPrint('[AdMob] rewarded FAILED TO SHOW: ${error.code} ${error.message}');
          ad.dispose();
          _rewardedAd = null;
          _isRewardedReady = false;
          _loadRewarded(placement);
          if (!completer.isCompleted) completer.complete();
        },
      );
      _rewardedAd!.show(onUserEarnedReward: (ad, reward) { onRewarded?.call(); });
      await completer.future;
    } else if (onRewarded != null) {
      // User explicitly requested a rewarded ad — deliver the reward even if
      // the rewarded unit is unavailable, so the promised bonus is never lost.
      onRewarded.call();
    } else {
      // System-initiated (round-end) with no reward callback — fall back to interstitial.
      await showInterstitialAsync();
    }
  }

  // ── App Open Ad ──────────────────────────────────────────────

  bool get _isAppOpenValid =>
      _isAppOpenReady &&
      _appOpenAd != null &&
      _appOpenLoadTime != null &&
      DateTime.now().difference(_appOpenLoadTime!) < const Duration(hours: 4);

  void _loadAppOpen() {
    AppOpenAd.load(
      adUnitId: appOpenAdUnitId,
      request: const AdRequest(),
      adLoadCallback: AppOpenAdLoadCallback(
        onAdLoaded: (ad) {
          debugPrint('[AdMob] app open loaded ✓');
          _appOpenAd = ad;
          _isAppOpenReady = true;
          _appOpenLoadTime = DateTime.now();
        },
        onAdFailedToLoad: (error) {
          debugPrint('[AdMob] app open FAILED: ${error.code} ${error.message}');
          _isAppOpenReady = false;
          Future.delayed(const Duration(minutes: 5), _loadAppOpen);
        },
      ),
    );
  }

  Future<void> showAppOpenAd() async {
    if (suppressAppOpenAd) return;
    if (!_isAppOpenValid) {
      _loadAppOpen();
      return;
    }
    final completer = Completer<void>();
    _appOpenAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _appOpenAd = null;
        _isAppOpenReady = false;
        _loadAppOpen();
        if (!completer.isCompleted) completer.complete();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint('[AdMob] app open FAILED TO SHOW: ${error.code}');
        ad.dispose();
        _appOpenAd = null;
        _isAppOpenReady = false;
        _loadAppOpen();
        if (!completer.isCompleted) completer.complete();
      },
    );
    _appOpenAd!.show();
    await completer.future;
  }

  // ── Legacy fire-and-forget aliases ───────────────────────────

  void showInterstitial([BuildContext? context]) => showInterstitialAsync();
  void showRoundEndAd([BuildContext? context]) => showRewardedAsync();

  BannerAd createBannerAd(AdSize size) => BannerAd(
        adUnitId: bannerAdUnitId,
        size: size,
        request: const AdRequest(),
        listener: const BannerAdListener(),
      );
}
