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

  // Standard interstitial — shown when player quits mid-game
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

  // Rewarded interstitial — shown at round end / game win
  static String get rewardedInterstitialAdUnitId {
    if (kDebugMode) {
      return Platform.isAndroid
          ? 'ca-app-pub-3940256099942544/5354046379'
          : 'ca-app-pub-3940256099942544/6978759866';
    }
    return Platform.isAndroid
        ? 'ca-app-pub-9287774769346149/6714019132'
        : 'ca-app-pub-9287774769346149/5400937468';
  }

  InterstitialAd? _interstitialAd;
  bool _isInterstitialReady = false;
  Completer<void>? _interstitialLoadCompleter;

  RewardedInterstitialAd? _rewardedAd;
  bool _isRewardedReady = false;
  Completer<void>? _rewardedLoadCompleter;

  Future<void> initialize() async {
    await MobileAds.instance.initialize();
    _loadInterstitial();
    _loadRewarded();
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
          Future.delayed(const Duration(minutes: 1), _loadInterstitial);
        },
      ),
    );
  }

  void _loadRewarded() {
    _rewardedLoadCompleter = Completer<void>();
    debugPrint('[AdMob] loading rewarded interstitial (${kDebugMode ? "TEST" : "LIVE"}) $rewardedInterstitialAdUnitId');
    RewardedInterstitialAd.load(
      adUnitId: rewardedInterstitialAdUnitId,
      request: const AdRequest(),
      rewardedInterstitialAdLoadCallback: RewardedInterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          debugPrint('[AdMob] rewarded interstitial loaded ✓');
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
          Future.delayed(const Duration(minutes: 2), _loadRewarded);
        },
      ),
    );
  }

  // ── Show methods (awaitable — complete when ad is dismissed) ──

  /// Show standard interstitial.
  /// If the ad is still loading, waits up to [_kAdLoadTimeout] for it to finish
  /// before giving up — prevents silent skips when a game ends right after a
  /// previous ad triggered a reload.
  Future<void> showInterstitialAsync([BuildContext? context]) async {
    debugPrint('[AdMob] showInterstitialAsync — ready=$_isInterstitialReady');
    if (!_isInterstitialReady || _interstitialAd == null) {
      // Wait for an in-flight load rather than silently giving up
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

  /// Show rewarded interstitial. Falls back to standard interstitial if not ready.
  /// Also waits for in-flight loads before giving up.
  Future<void> showRewardedAsync([BuildContext? context]) async {
    debugPrint('[AdMob] showRewardedAsync — rewarded=$_isRewardedReady interstitial=$_isInterstitialReady');

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
          _loadRewarded();
          if (!completer.isCompleted) completer.complete();
        },
        onAdFailedToShowFullScreenContent: (ad, error) {
          debugPrint('[AdMob] rewarded FAILED TO SHOW: ${error.code} ${error.message}');
          ad.dispose();
          _rewardedAd = null;
          _isRewardedReady = false;
          _loadRewarded();
          if (!completer.isCompleted) completer.complete();
        },
      );
      _rewardedAd!.show(onUserEarnedReward: (ad, reward) {});
      await completer.future;
    } else {
      // Rewarded unavailable — fall back to interstitial
      await showInterstitialAsync();
    }
  }

  // ── Legacy fire-and-forget aliases ───────────────────────────

  void showInterstitial([BuildContext? context]) => showInterstitialAsync();
  void showRoundEndAd([BuildContext? context]) => showRewardedAsync();

  BannerAd createBannerAd() => BannerAd(
        adUnitId: bannerAdUnitId,
        size: AdSize.banner,
        request: const AdRequest(),
        listener: const BannerAdListener(),
      );
}
