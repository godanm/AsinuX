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

  // Standard interstitial — fallback when rewarded isn't loaded
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

  // Rewarded interstitial — higher eCPM video ad shown after each round
  static String get rewardedInterstitialAdUnitId {
    if (kDebugMode) {
      return Platform.isAndroid
          ? 'ca-app-pub-3940256099942544/5354046379'  // test rewarded interstitial Android
          : 'ca-app-pub-3940256099942544/6978759866'; // test rewarded interstitial iOS
    }
    return Platform.isAndroid
        ? 'ca-app-pub-9287774769346149/6714019132'
        : 'ca-app-pub-9287774769346149/5400937468';
  }

  InterstitialAd? _interstitialAd;
  bool _isInterstitialReady = false;

  RewardedInterstitialAd? _rewardedAd;
  bool _isRewardedReady = false;

  Future<void> initialize() async {
    await MobileAds.instance.initialize();
    _loadInterstitial();
    _loadRewarded();
  }

  // ── Standard interstitial ────────────────────────────────────

  void _loadInterstitial() {
    InterstitialAd.load(
      adUnitId: interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _isInterstitialReady = true;
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              _interstitialAd = null;
              _isInterstitialReady = false;
              _loadInterstitial();
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              ad.dispose();
              _interstitialAd = null;
              _isInterstitialReady = false;
              _loadInterstitial();
            },
          );
        },
        onAdFailedToLoad: (_) {
          _isInterstitialReady = false;
          Future.delayed(const Duration(minutes: 1), _loadInterstitial);
        },
      ),
    );
  }

  void showInterstitial([BuildContext? context]) {
    if (_isInterstitialReady && _interstitialAd != null) {
      _interstitialAd!.show();
    }
  }

  // ── Rewarded interstitial (video — higher payout) ────────────

  void _loadRewarded() {
    RewardedInterstitialAd.load(
      adUnitId: rewardedInterstitialAdUnitId,
      request: const AdRequest(),
      rewardedInterstitialAdLoadCallback: RewardedInterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedAd = ad;
          _isRewardedReady = true;
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              _rewardedAd = null;
              _isRewardedReady = false;
              _loadRewarded();
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              ad.dispose();
              _rewardedAd = null;
              _isRewardedReady = false;
              _loadRewarded();
              // Fallback to standard interstitial
              showInterstitial();
            },
          );
        },
        onAdFailedToLoad: (_) {
          _isRewardedReady = false;
          Future.delayed(const Duration(minutes: 2), _loadRewarded);
        },
      ),
    );
  }

  /// Show a rewarded interstitial video ad after a round.
  /// Falls back to standard interstitial if video isn't ready.
  /// [context] is accepted for API compatibility with the web stub but ignored.
  void showRoundEndAd([BuildContext? context]) {
    if (_isRewardedReady && _rewardedAd != null) {
      _rewardedAd!.show(
        onUserEarnedReward: (_, __) {
          // No in-app reward needed — ad impression is the goal
        },
      );
    } else {
      showInterstitial();
    }
  }

  BannerAd createBannerAd() => BannerAd(
        adUnitId: bannerAdUnitId,
        size: AdSize.banner,
        request: const AdRequest(),
        listener: const BannerAdListener(),
      );
}
