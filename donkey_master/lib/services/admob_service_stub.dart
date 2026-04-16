// Web interstitial implementation — pure Flutter overlay dialog.
//
// Ad unit slots to fill in once created in AdSense console:
//   _interstitialSlotId   → "AsinuX - Interstitial"
//   _rewardedSlotId       → "AsinuX - Rewarded Interstitial"

import 'dart:async';

import 'package:flutter/material.dart';

// TODO: paste AdSense ad-unit slot IDs here once created in AdSense console
const _interstitialSlotId = '';
const _rewardedSlotId = '';

// Active slot: prefer rewarded slot if set, otherwise interstitial
const _adSlotId =
    _rewardedSlotId.length > 0 ? _rewardedSlotId : _interstitialSlotId;

class AdMobService {
  static final AdMobService _instance = AdMobService._();
  static AdMobService get instance => _instance;
  AdMobService._();

  Future<void> initialize() async {}

  void showInterstitial([BuildContext? context]) => showRoundEndAd(context);

  /// Shows a full-screen interstitial overlay.
  /// On web: Flutter dialog (auto-closes after 5 s or on skip tap).
  Future<void> showRoundEndAd([BuildContext? context]) async {
    if (context == null || !context.mounted) return;
    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      builder: (_) => const _WebInterstitialDialog(),
    );
  }

  Future<void> showInterstitialAsync([BuildContext? context]) =>
      showRoundEndAd(context);

  Future<void> showRewardedAsync([BuildContext? context]) =>
      showRoundEndAd(context);

  dynamic createBannerAd() => null;
}

// ── Web interstitial dialog ───────────────────────────────────────────────────

class _WebInterstitialDialog extends StatefulWidget {
  const _WebInterstitialDialog();

  @override
  State<_WebInterstitialDialog> createState() => _WebInterstitialDialogState();
}

class _WebInterstitialDialogState extends State<_WebInterstitialDialog> {
  int _countdown = 5;
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_countdown <= 1) {
        t.cancel();
        Navigator.of(context).pop();
      } else {
        setState(() => _countdown--);
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return Center(
      child: SizedBox(
        width: width > 380 ? 340.0 : width * 0.92,
        child: Material(
          color: const Color(0xFF1a000e),
          borderRadius: BorderRadius.circular(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Header ──────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                child: Row(
                  children: [
                    Text(
                      'Advertisement',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.35),
                        fontSize: 11,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white12,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _countdown > 0 ? 'Skip in $_countdown' : 'Close',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.55),
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Colors.white10),

              // ── Ad area ──────────────────────────────────────────
              // Pure Flutter placeholder shown until AdSense slot IDs are
              // configured. When _adSlotId is set, replace this with the
              // live AdSense unit (inject via dart:js_interop).
              Container(
                width: 300,
                height: 250,
                color: const Color(0xFF0d0007),
                child: _adSlotId.isNotEmpty
                    ? const SizedBox.shrink() // live ad injected via JS
                    : Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.campaign_outlined,
                                size: 40,
                                color: Colors.white.withValues(alpha: 0.15)),
                            const SizedBox(height: 8),
                            Text(
                              'Advertisement',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.15),
                                fontSize: 13,
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
