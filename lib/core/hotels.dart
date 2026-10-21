import 'api_client.dart';
import 'app_config.dart';
import 'prefs.dart';

/// The technical "App Mobile" entry of getConfigHotel* is the configuration
/// database, not a real hotel: it is only shown in the Config page.
class Hotels {
  static String _norm(Object? v) =>
      (v ?? '').toString().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  static bool isAppMobile(Map<String, dynamic> h) {
    for (final k in ['namehotel', 'name']) {
      if (_norm(h[k]) == 'appmobile') return true;
    }
    return false;
  }

  /// Hotels the user may pick (login, change hotel).
  static List<Map<String, dynamic>> visible(List<Map<String, dynamic>> l) =>
      l.where((h) => !isAppMobile(h)).toList();

  static String _key(Object? v) => (v ?? '').toString().trim().toLowerCase();

  /// ONLY the hotels assigned to the logged-in user.
  ///  1. user id (saved at login, or found again from the login identifier)
  ///  2. POST /hotel/getConfigHotelbyemail/{userId} -> names assigned to him
  ///  3. keep, in [all] (getConfigHotel1: url / port / password), only those
  ///     names. Never falls back to "all hotels": throws instead.
  static Future<List<Map<String, dynamic>>> forCurrentUser(
      String base, List<Map<String, dynamic>> all,
      {Map<String, dynamic>? body}) async {
    final b = body ?? AppConfig.initialBody();
    var uid = Prefs.getString('userDbId');
    if (uid.isEmpty) {
      final id = Prefs.getString('loginId').trim();
      if (id.isNotEmpty) {
        final users = Api.asList(await Api.post('$base/hotel/getlistuser', b));
        for (final u in users) {
          if ('${u['email']}' == id || '${u['telephone']}' == id) {
            uid = '${u['id']}';
            await Prefs.setString('userDbId', uid);
            break;
          }
        }
      }
    }
    if (uid.isEmpty) throw ApiException('user not found');

    final assigned = Api.asList(
        await Api.post('$base/hotel/getConfigHotelbyemail/$uid', b));
    final names = {
      for (final h in assigned) _key(h['namehotel'] ?? h['name']),
    }..remove('');
    return visible(all)
        .where((h) => names.contains(_key(h['name'] ?? h['namehotel'])))
        .toList();
  }
}
