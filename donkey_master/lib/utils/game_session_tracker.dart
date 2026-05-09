import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class GameSessionTracker {
  static const _key = 'recent_game_rooms';
  static const _max = 10;

  static Future<void> record(String game, String roomId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      final list = raw != null
          ? List<Map<String, dynamic>>.from(
              (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e as Map)))
          : <Map<String, dynamic>>[];
      // Avoid duplicate consecutive entries for the same room
      if (list.isNotEmpty && list.first['roomId'] == roomId) return;
      list.insert(0, {
        'game': game,
        'roomId': roomId,
        'ts': DateTime.now().millisecondsSinceEpoch,
      });
      if (list.length > _max) list.length = _max;
      await prefs.setString(_key, jsonEncode(list));
    } catch (_) {}
  }

  static Future<List<Map<String, dynamic>>> recent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return [];
      return List<Map<String, dynamic>>.from(
          (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e as Map)));
    } catch (_) {
      return [];
    }
  }
}
