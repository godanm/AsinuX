import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class AdMobService {
  static final AdMobService _instance = AdMobService._();
  static AdMobService get instance => _instance;
  AdMobService._();

  // ── Ad Unit IDs ──────────────────────────────────────────────
  // In debug mode, always use Google's official test IDs so ads render.
  // Real IDs only serve once the app is live and AdMob-approved.
  static String get bannerAdUnitId {
    if (kDebugMode) {
      return Platform.isAndroid
          ? 'ca-app-pub-3940256099942544/6300978111'  // test banner Android
          : 'ca-app-pub-3940256099942544/2934735716'; // test banner iOS
    }
    return Platform.isAndroid
        ? 'ca-app-pub-9287774769346149/5092029867'
        : 'ca-app-pub-9287774769346149/2135665202';
  }

  static String get interstitialAdUnitId {
    if (kDebugMode) {
      return Platform.isAndroid
          ? 'ca-app-pub-3940256099942544/1033173712'  // test interstitial Android
          : 'ca-app-pub-3940256099942544/4411468910'; // test interstitial iOS
    }
    return Platform.isAndroid
        ? 'ca-app-pub-9287774769346149/2330135158'
        : 'ca-app-pub-9287774769346149/2985712449';
  }

  InterstitialAd? _interstitialAd;
  bool _isInterstitialReady = false;

  Future<void> initialize() async {
    await MobileAds.instance.initialize();
    await _loadInterstitial();
  }

  Future<void> _loadInterstitial() async {
    await InterstitialAd.load(
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

  void showInterstitial() {
    if (_isInterstitialReady && _interstitialAd != null) {
      _interstitialAd!.show();
    }
  }

  BannerAd createBannerAd() => BannerAd(
        adUnitId: bannerAdUnitId,
        size: AdSize.banner,
        request: const AdRequest(),
        listener: const BannerAdListener(),
      );
}
