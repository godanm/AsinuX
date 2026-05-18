import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/app_version_service.dart';

const _kPlayStoreUrl = 'https://play.google.com/store/apps/details?id=com.asinux.app';

class UpdatePromptDialog extends StatelessWidget {
  final UpdatePromptInfo info;

  const UpdatePromptDialog({super.key, required this.info});

  bool get _isForced => info.type == UpdatePromptType.forced;

  Future<void> _openPlayStore() async {
    final uri = Uri.parse(_kPlayStoreUrl);
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isForced,
      child: AlertDialog(
        backgroundColor: const Color(0xFF1a000e),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                color: const Color(0xFF2a0010),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFE63946).withValues(alpha: 0.4), width: 1.5),
              ),
              child: const Icon(Icons.system_update_rounded, color: Color(0xFFE63946), size: 28),
            ),
            const SizedBox(height: 16),
            Text(
              _isForced ? 'Update Required' : 'Update Available',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              _isForced
                  ? 'This version is no longer supported. Please update Tricksy to continue playing.'
                  : 'A new version of Tricksy is available${info.latestVersion.isNotEmpty ? ' (${info.latestVersion})' : ''}. Update to get the latest features and fixes.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 13,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        actions: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ElevatedButton(
                onPressed: _openPlayStore,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE63946),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  elevation: 0,
                ),
                child: const Text(
                  'Update Now',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),
              ),
              if (!_isForced) ...[
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    'Maybe Later',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
