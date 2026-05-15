import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../services/admob_service.dart';

class AdBannerWidget extends StatefulWidget {
  const AdBannerWidget({super.key});

  @override
  State<AdBannerWidget> createState() => _AdBannerWidgetState();
}

class _AdBannerWidgetState extends State<AdBannerWidget> {
  dynamic _ad;
  AdSize? _adSize;
  bool _loaded = false;
  bool _loadStarted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!kIsWeb && !_loadStarted) {
      _loadStarted = true;
      _loadAd();
    }
  }

  Future<void> _loadAd() async {
    try {
      final width = MediaQuery.of(context).size.width.truncate();
      final adSize = await AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(width);
      if (adSize == null || !mounted) return;
      final ad = AdMobService.instance.createBannerAd(adSize);
      await ad.load();
      if (mounted) setState(() { _ad = ad; _adSize = adSize; _loaded = true; });
    } catch (_) {}
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ── Web: no banner (AdSense runs only on static HTML pages) ──
    if (kIsWeb) return const SizedBox.shrink();

    // ── Android/iOS: AdMob adaptive banner ───────────────────────
    if (!_loaded || _ad == null || _adSize == null) return const SizedBox.shrink();
    return SizedBox(
      width: _adSize!.width.toDouble(),
      height: _adSize!.height.toDouble(),
      child: AdWidget(ad: _ad),
    );
  }
}

