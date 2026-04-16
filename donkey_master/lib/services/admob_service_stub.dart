// Web interstitial implementation — uses a Flutter dialog overlay with an
// embedded AdSense 300×250 unit via HtmlElementView.
//
// Ad unit slots to fill in once created in AdSense console:
//   _interstitialSlotId   → equivalent of "AsinuX - Interstitial"
//   _rewardedSlotId       → equivalent of "AsinuX - Rewarded Interstitial"
// Both use a 300×250 display unit on web (AdSense has no rewarded format).

import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

const _publisherId = 'ca-pub-9287774769346149';

// TODO: paste AdSense ad-unit slot IDs here once created in AdSense console
const _interstitialSlotId = '';      // "AsinuX - Interstitial" equivalent
const _rewardedSlotId = '';          // "AsinuX - Rewarded Interstitial" equivalent

// Active slot: prefer rewarded slot if set, otherwise interstitial
const _adSlotId =
    _rewardedSlotId.length > 0 ? _rewardedSlotId : _interstitialSlotId;

bool _viewFactoryRegistered = false;

void _ensureViewFactory() {
  if (_viewFactoryRegistered) return;
  _viewFactoryRegistered = true;
  ui_web.platformViewRegistry.registerViewFactory(
    'adsense-interstitial',
    (int viewId) {
      final div = web.document.createElement('div');
      div.setAttribute(
        'style',
        'width:300px;height:250px;background:#0d0007;'
        'display:flex;align-items:center;justify-content:center;',
      );

      if (_adSlotId.isNotEmpty) {
        // Real AdSense unit
        final ins = web.document.createElement('ins');
        ins.setAttribute('class', 'adsbygoogle');
        ins.setAttribute('style', 'display:block;width:300px;height:250px');
        ins.setAttribute('data-ad-client', _publisherId);
        ins.setAttribute('data-ad-slot', _adSlotId);
        div.appendChild(ins);

        final script = web.document.createElement('script');
        script.textContent =
            '(adsbygoogle = window.adsbygoogle || []).push({});';
        div.appendChild(script);
      } else {
        // Placeholder until slot ID is configured
        div.innerHTML =
            ('<div style="color:rgba(255,255,255,0.15);font-family:sans-serif;'
            'font-size:13px;letter-spacing:1px;text-align:center;">'
            '<div style="font-size:28px;margin-bottom:8px">📢</div>'
            'Advertisement</div>').toJS;
      }
      return div;
    },
  );
}

class AdMobService {
  static final AdMobService _instance = AdMobService._();
  static AdMobService get instance => _instance;
  AdMobService._();

  Future<void> initialize() async {
    _ensureViewFactory();
  }

  void showInterstitial([BuildContext? context]) => showRoundEndAd(context);

  /// Shows a full-screen interstitial overlay.
  /// On web: Flutter dialog with embedded AdSense unit (auto-closes in 5 s).
  Future<void> showRoundEndAd([BuildContext? context]) async {
    if (context == null || !context.mounted) return;
    _ensureViewFactory();
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      builder: (_) => const _WebInterstitialDialog(),
    );
  }

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

              // ── Ad area (300×250 AdSense unit) ───────────────────
              const SizedBox(
                width: 300,
                height: 250,
                child: HtmlElementView(viewType: 'adsense-interstitial'),
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
