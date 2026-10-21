import 'prefs.dart';

/// Single source of truth for server URL + DB config bodies
/// (port of AppConfigService + the per-page buildRequestBody helpers).
class AppConfig {
  static const defaultServer = '197.13.4.11';
  static const defaultPort = '8107';
  static const defaultUrlpub =
      'jdbc:oracle:thin:@//10.0.26.2:1521/DBHOTEL_SOPALA';
  static const defaultUsername = 'APP_MOBILE';
  static const defaultPassword = 'ArabSoft2026';
  static const defaultHotel = 'SOPORT';

  /// Admin access to the config screen (login: sup / arabsoft123).
  static const adminUser = 'sup';
  static const adminPassword = 'arabsoft123';

  static bool get hasServerConfig =>
      Prefs.getString('jarAddress').isNotEmpty &&
      Prefs.getString('jarPort').isNotEmpty;

  /// http://address:port  (empty string if not configured)
  static String get baseUrl {
    final a = Prefs.getString('jarAddress');
    final p = Prefs.getString('jarPort');
    if (a.isEmpty || p.isEmpty) return '';
    return _build(a, p);
  }

  /// Same as [baseUrl] but falls back to the defaults (used by drawer/home).
  static String get baseUrlOrDefault {
    final a = Prefs.getString('jarAddress');
    final p = Prefs.getString('jarPort');
    return _build(a.isEmpty ? defaultServer : a, p.isEmpty ? defaultPort : p);
  }

  static String _build(String address, String port) {
    final clean = address
        .replaceAll(RegExp(r'^https?://'), '')
        .replaceAll(RegExp(r'/+$'), '');
    return 'http://$clean:$port';
  }

  /// Main hotel DB config body: { url, username, password }
  static Map<String, dynamic> initialBody([Map<String, dynamic>? extra]) {
    final user = Prefs.getString('username');
    final pass = Prefs.getString('password');
    return {
      'url': Prefs.getString('urlpub'),
      'username': user.isEmpty ? defaultUsername : user,
      'password': pass.isEmpty ? defaultPassword : pass,
      ...?extra,
    };
  }

  /// Pointage (selected hotel) DB config body, falls back to the main one.
  static Map<String, dynamic> pointageBody([Map<String, dynamic>? extra]) {
    String pick(String a, String b, String def) {
      final x = Prefs.getString(a);
      if (x.isNotEmpty) return x;
      final y = Prefs.getString(b);
      return y.isNotEmpty ? y : def;
    }

    return {
      'url': pick('pointage_url', 'urlpub', ''),
      'username': pick('pointage_username', 'username', defaultUsername),
      'password': pick('pointage_password', 'password', defaultPassword),
      ...?extra,
    };
  }

  static String get sessionId {
    for (final k in ['sessionId', 'saissionid', 'session_id', 'sessionID']) {
      final v = Prefs.getString(k);
      if (v.isNotEmpty) return v;
    }
    return '';
  }
}
