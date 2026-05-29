import 'package:shared_preferences/shared_preferences.dart';

class ProfileSharedPreferences implements SharedPreferences {
  final SharedPreferences _prefs;
  final String _prefix;

  ProfileSharedPreferences(this._prefs, String profile)
      : _prefix = profile.isNotEmpty ? '${profile}_' : '';

  String _pKey(String key) => '$_prefix$key';

  @override
  Set<String> getKeys() {
    if (_prefix.isEmpty) return _prefs.getKeys();
    return _prefs.getKeys()
        .where((key) => key.startsWith(_prefix))
        .map((key) => key.substring(_prefix.length))
        .toSet();
  }

  @override
  Object? get(String key) => _prefs.get(_pKey(key));

  @override
  bool? getBool(String key) => _prefs.getBool(_pKey(key));

  @override
  int? getInt(String key) => _prefs.getInt(_pKey(key));

  @override
  double? getDouble(String key) => _prefs.getDouble(_pKey(key));

  @override
  String? getString(String key) => _prefs.getString(_pKey(key));

  @override
  List<String>? getStringList(String key) => _prefs.getStringList(_pKey(key));

  @override
  bool containsKey(String key) => _prefs.containsKey(_pKey(key));

  @override
  Future<bool> setBool(String key, bool value) => _prefs.setBool(_pKey(key), value);

  @override
  Future<bool> setInt(String key, int value) => _prefs.setInt(_pKey(key), value);

  @override
  Future<bool> setDouble(String key, double value) => _prefs.setDouble(_pKey(key), value);

  @override
  Future<bool> setString(String key, String value) => _prefs.setString(_pKey(key), value);

  @override
  Future<bool> setStringList(String key, List<String> value) => _prefs.setStringList(_pKey(key), value);

  @override
  Future<bool> remove(String key) => _prefs.remove(_pKey(key));

  @override
  Future<bool> clear() async {
    if (_prefix.isEmpty) return _prefs.clear();
    final keysToRemove = _prefs.getKeys().where((key) => key.startsWith(_prefix)).toList();
    bool success = true;
    for (final key in keysToRemove) {
      final res = await _prefs.remove(key);
      if (!res) success = false;
    }
    return success;
  }

  @override
  Future<void> reload() => _prefs.reload();

  @override
  Future<bool> commit() async => true;
}
