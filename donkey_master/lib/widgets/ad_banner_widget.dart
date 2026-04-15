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
    // ── Web: placeholder until real AdSense script is wired ──────
    if (kIsWeb) return const _WebAdPlaceholder();

    // ── Android/iOS: AdMob banner ─────────────────────────────────
    if (!_loaded || _ad == null) return const SizedBox.shrink();
    return SizedBox(height: 50, child: AdWidget(ad: _ad));
  }
}

// Replace this widget body with a real AdSense <ins> tag via HtmlElementView
// once the AdSense publisher ID is received.
class _WebAdPlaceholder extends StatelessWidget {
  const _WebAdPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 60,
      color: const Color(0xFF0d0007),
      child: Center(
        child: Container(
          width: double.infinity,
          height: 50,
          margin: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF1a000e),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.campaign_outlined,
                  size: 14, color: Colors.white.withValues(alpha: 0.2)),
              const SizedBox(width: 6),
              Text(
                'Advertisement',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.2),
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
