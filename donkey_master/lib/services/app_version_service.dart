import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;

// Injected at build time via --dart-define=APP_VERSION=x.y.z+n
const _kAppVersion = String.fromEnvironment('APP_VERSION', defaultValue: '');

int get currentBuildNumber {
  if (_kAppVersion.contains('+')) {
    return int.tryParse(_kAppVersion.split('+').last) ?? 0;
  }
  return 0;
}

enum UpdatePromptType { none, optional, forced }

class UpdatePromptInfo {
  final UpdatePromptType type;
  final String latestVersion;

  const UpdatePromptInfo({required this.type, required this.latestVersion});
}

class AppVersionService {
  AppVersionService._();
  static final instance = AppVersionService._();

  Future<UpdatePromptInfo> checkForUpdate() async {
    // Web always serves the latest build — no prompt needed.
    if (kIsWeb) return const UpdatePromptInfo(type: UpdatePromptType.none, latestVersion: '');

    try {
      final snap = await FirebaseDatabase.instance.ref('config/versions').get();
      if (!snap.exists) return const UpdatePromptInfo(type: UpdatePromptType.none, latestVersion: '');

      final data = Map<String, dynamic>.from(snap.value as Map);
      final minBuild = (data['minBuild'] as int?) ?? 0;
      final latestBuild = (data['latestBuild'] as int?) ?? 0;
      final latestVersion = (data['latestVersion'] as String?) ?? '';
      final current = currentBuildNumber;

      debugPrint('[AppVersionService] current=$current min=$minBuild latest=$latestBuild');

      if (current < minBuild) {
        return UpdatePromptInfo(type: UpdatePromptType.forced, latestVersion: latestVersion);
      }
      if (current < latestBuild) {
        return UpdatePromptInfo(type: UpdatePromptType.optional, latestVersion: latestVersion);
      }
      return const UpdatePromptInfo(type: UpdatePromptType.none, latestVersion: '');
    } catch (e) {
      debugPrint('[AppVersionService] check failed: $e');
      return const UpdatePromptInfo(type: UpdatePromptType.none, latestVersion: '');
    }
  }
}
