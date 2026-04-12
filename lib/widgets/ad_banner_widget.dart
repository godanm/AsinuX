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
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) _loadAd();
  }

  void _loadAd() async {
    try {
      final ad = AdMobService.instance.createBannerAd();
      await ad.load();
      if (mounted) setState(() { _ad = ad; _loaded = true; });
    } catch (_) {}
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || !_loaded || _ad == null) return const SizedBox.shrink();
    return SizedBox(height: 50, child: AdWidget(ad: _ad));
  }
}
