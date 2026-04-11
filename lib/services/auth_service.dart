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
    if (user != null) return user;
    final cred = await _auth.signInAnonymously();
    return cred.user!;
  }

  Future<String> getOrCreateDisplayName() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString('playerName');
    if (stored != null && stored.isNotEmpty) return stored;
    final adjectives = ['Swift', 'Clever', 'Lucky', 'Bold', 'Sly', 'Witty'];
    final nouns = ['Donkey', 'Fox', 'Bear', 'Wolf', 'Eagle', 'Lion'];
    final name =
        '${adjectives[DateTime.now().millisecond % adjectives.length]} '
        '${nouns[DateTime.now().second % nouns.length]}';
    await prefs.setString('playerName', name);
    return name;
  }

  Future<void> saveDisplayName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('playerName', name);
    // Also persist to Firebase so leaderboard can show real display names
    final user = _auth.currentUser;
    if (user != null) {
      await FirebaseDatabase.instance.ref('stats/${user.uid}/displayName').set(name);
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
