// Web/unsupported platform stub — all methods are no-ops.
class AdMobService {
  static final AdMobService _instance = AdMobService._();
  static AdMobService get instance => _instance;
  AdMobService._();

  Future<void> initialize() async {}
  void showInterstitial() {}
  void showRoundEndAd() {}
  dynamic createBannerAd() => null;
}
