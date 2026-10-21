import 'package:shared_preferences/shared_preferences.dart';

/// Thin synchronous wrapper around SharedPreferences
/// (replacement for localStorage + Ionic Storage in the Angular app).
class Prefs {
  static late SharedPreferences _p;

  static Future<void> init() async {
    _p = await SharedPreferences.getInstance();
  }

  static String getString(String key, [String def = '']) =>
      _p.getString(key) ?? def;

  static Future<void> setString(String key, String value) async {
    await _p.setString(key, value);
  }

  static bool getBool(String key, [bool def = false]) =>
      _p.getBool(key) ?? def;

  static Future<void> setBool(String key, bool value) async {
    await _p.setBool(key, value);
  }

  static Future<void> remove(String key) async {
    await _p.remove(key);
  }
}
