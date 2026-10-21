import 'api_client.dart';
import 'app_config.dart';
import 'prefs.dart';
import 'section.dart';

/// Shared "GetDataproce" call (Ionic: getDataForSecondUrl / executeProcedure*).
/// Returns the server map (dates, hotel code...) and persists the session id,
/// exactly like the Home screen does, so any page can be opened first.
///
/// Reliability notes (why Prévisions / CA sometimes needed a manual refresh):
///  * Several screens used to call GetDataproce at the same time (drawer +
///    previous page still finishing + new page). Each answer overwrote the
///    stored session id, so a page could run its procedures with session A and
///    then read the result tables with session B -> empty tables.
///    => concurrent calls now share ONE in-flight request.
///  * Pages now take the session id from the returned map ([sidKey]) instead of
///    re-reading shared preferences after every await.
///  * If GetDataproce is unreachable the last known session id / hotel code are
///    returned so the page can still try to load.
class Session {
  /// Key added to the returned map: the session id to use for this load.
  static const sidKey = '__sid';

  static Future<Map<String, dynamic>>? _inflight;

  /// Forget any running/old request (call when the hotel changes).
  static void reset() {
    _inflight = null;
    PageCache.clear(); // never show the previous hotel's numbers
  }

  static Future<Map<String, dynamic>> load() {
    final running = _inflight;
    if (running != null) return running;
    final f = _load();
    _inflight = f;
    f.whenComplete(() {
      if (identical(_inflight, f)) _inflight = null;
    }).ignore();
    return f;
  }

  /// Session id of a map returned by [load] (falls back to the stored one).
  static String sidOf(Map<String, dynamic> m) {
    final v = (m[sidKey] ?? '').toString();
    return v.isNotEmpty ? v : AppConfig.sessionId;
  }

  static Future<Map<String, dynamic>> _load() async {
    Map<String, dynamic> map = {};
    Object? failure;
    try {
      final data = await Api.post(
        '${AppConfig.baseUrlOrDefault}/hotel/GetDataproce',
        AppConfig.pointageBody(),
        retries: 3,
      );
      if (data is Map) map = Map<String, dynamic>.from(data);
    } catch (e) {
      failure = e;
    }

    Future<void> save(String k, dynamic v) async {
      if (v != null && v.toString().isNotEmpty) {
        await Prefs.setString(k, v.toString());
      }
    }

    final saves = <Future<void>>[
      save('hotelName', map['nomhotel']),
      save('getsiglehotel', map['getsiglehotel']),
    ];
    final sid = (map['saissionid'] ??
            map['sessionid'] ??
            map['sessionId'] ??
            map['session_id'] ??
            '')
        .toString();
    if (sid.isNotEmpty) {
      // sid first: pages read it right after this call returns
      await Prefs.setString('sessionId', sid);
      await Prefs.setString('saissionid', sid);
    }
    for (final k in [
      'codhotelnew', 'd1', 'six', 'firstday', 'lastday', 'anncom', 'dd',
      'tom', 'tomm', 'hierPass', 'setHier',
    ]) {
      saves.add(save(k, map[k]));
    }
    await Future.wait(saves);

    // Fallbacks so a page can still load if GetDataproce answered badly.
    for (final k in ['codhotelnew', 'anncom']) {
      if ((map[k] ?? '').toString().isEmpty) {
        final p = Prefs.getString(k);
        if (p.isNotEmpty) map[k] = p;
      }
    }
    map[sidKey] = sid.isNotEmpty ? sid : AppConfig.sessionId;

    if (failure != null && (map[sidKey] as String).isEmpty) {
      // nothing usable at all -> let the caller report the real error
      throw failure is ApiException ? failure : ApiException('$failure');
    }
    return map;
  }
}
