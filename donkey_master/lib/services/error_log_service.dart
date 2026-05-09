import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

/// Mixin for service classes. Wrap any async game-action method with
/// [guarded] to get automatic error logging + rethrow.
///
/// Usage:
///   class MyService with GameGuard {
///     @override String get gameName => 'my_game';
///
///     Future<void> doAction(String roomId) =>
///         guarded('doAction', () async { ... });
///   }
mixin GameGuard {
  String get gameName;

  Future<T> guarded<T>(String op, Future<T> Function() fn) async {
    try {
      return await fn();
    } catch (e, st) {
      debugPrint('[$gameName] $op ERROR: $e');
      ErrorLogService.instance.logAuto(
        game: gameName,
        error: '$op: $e',
        stack: st,
      );
      rethrow;
    }
  }
}

class ErrorLogService {
  static final ErrorLogService _instance = ErrorLogService._();
  static ErrorLogService get instance => _instance;
  ErrorLogService._();

  final _db = FirebaseDatabase.instance;

  /// Log a game-specific error with an explicit uid.
  Future<void> log({
    required String uid,
    required String game,
    required String error,
    Map<String, dynamic>? context,
  }) async {
    try {
      await _db.ref('error_logs/$uid').push().set({
        'game': game,
        'error': error,
        'ts': ServerValue.timestamp,
        'platform': kIsWeb ? 'web' : 'android',
        'context': context,
      });
      debugPrint('[ErrorLog] $game/$error uid=$uid');
    } catch (e) {
      debugPrint('[ErrorLog] failed to write: $e');
    }
  }

  /// Log using the currently signed-in user's uid.
  /// Safe to call even before Firebase is fully initialised — it silently
  /// drops the log entry if no user is authenticated yet.
  Future<void> logAuto({
    required String game,
    required String error,
    StackTrace? stack,
    Map<String, dynamic>? context,
  }) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final ctx = <String, dynamic>{
        if (context != null) ...context,
        if (stack != null) 'stack': _trim(stack.toString()),
      };
      await log(uid: uid, game: game, error: error, context: ctx.isEmpty ? null : ctx);
    } catch (_) {
      // Firebase not ready or auth not available — skip silently
    }
  }

  static String _trim(String s) =>
      s.length > 800 ? '${s.substring(0, 800)}…' : s;
}
