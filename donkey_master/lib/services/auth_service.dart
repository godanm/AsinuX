import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static final AuthService _instance = AuthService._();
  static AuthService get instance => _instance;
  AuthService._();

  final _auth = FirebaseAuth.instance;

  User? get currentUser => _auth.currentUser;
  String? get uid => _auth.currentUser?.uid;

  Future<User> signInAnonymously() async {
    final user = _auth.currentUser;
    if (user != null) {
      // Save UID so we can cross-reference stats if session ever resets
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('uid', user.uid);
      return user;
    }
    final cred = await _auth.signInAnonymously();
    final newUser = cred.user!;
    final prefs = await SharedPreferences.getInstance();
    // If we have a previously stored UID (different from new one), migrate the name
    final storedUid = prefs.getString('uid');
    if (storedUid != null && storedUid != newUser.uid) {
      // Restore name from Firebase using old UID so stats link is maintained
      final oldName = await FirebaseDatabase.instance
          .ref('stats/$storedUid/displayName')
          .get();
      if (oldName.exists) {
        final name = oldName.value as String;
        await prefs.setString('playerName', name);
        await FirebaseDatabase.instance
            .ref('stats/${newUser.uid}/displayName')
            .set(name);
      }
    }
    await prefs.setString('uid', newUser.uid);
    return newUser;
  }

  Future<String> getOrCreateDisplayName() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString('playerName');
    if (stored != null && stored.isNotEmpty) return stored.replaceAll('_', ' ');
    final adjectives = ['Swift', 'Clever', 'Lucky', 'Bold', 'Sly', 'Witty'];
    final nouns = ['Donkey', 'Fox', 'Bear', 'Wolf', 'Eagle', 'Lion'];
    final name =
        '${adjectives[DateTime.now().millisecond % adjectives.length]} '
        '${nouns[DateTime.now().second % nouns.length]}';
    await prefs.setString('playerName', name);
    return name;
  }

  Future<void> saveDisplayName(String name) async {
    final clean = name.replaceAll('_', ' ').trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('playerName', clean);
    // Also persist to Firebase so leaderboard can show real display names
    final user = _auth.currentUser;
    if (user != null) {
      await FirebaseDatabase.instance.ref('stats/${user.uid}/displayName').set(clean);
    }
  }

  Future<String?> loadDisplayName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('playerName');
  }

  // ── Avatar ────────────────────────────────────────────────────
  // Stored as two ints: colorIndex (0–11) and iconIndex (0–11).

  Future<AvatarPreset> loadAvatar() async {
    final prefs = await SharedPreferences.getInstance();
    return AvatarPreset(
      colorIndex: prefs.getInt('avatarColor') ?? -1, // -1 = use name-hash default
      iconIndex: prefs.getInt('avatarIcon') ?? -1,   // -1 = use letter initial
    );
  }

  Future<void> saveAvatar(AvatarPreset preset) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('avatarColor', preset.colorIndex);
    await prefs.setInt('avatarIcon', preset.iconIndex);
    final user = _auth.currentUser;
    if (user != null) {
      await FirebaseDatabase.instance.ref('stats/${user.uid}').update({
        'avatarColor': preset.colorIndex,
        'avatarIcon': preset.iconIndex,
      });
    }
  }
}

class AvatarPreset {
  final int colorIndex; // -1 = default (name-hash)
  final int iconIndex;  // -1 = letter initial

  const AvatarPreset({required this.colorIndex, required this.iconIndex});

  bool get isDefault => colorIndex == -1 && iconIndex == -1;
}
