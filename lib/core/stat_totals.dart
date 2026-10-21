import 'package:flutter/foundation.dart';
import 'api_client.dart';
import 'app_config.dart';
import 'fmt.dart';
import 'loader.dart';
import 'prefs.dart';
import 'session.dart';

/// One revenue category read from the "Stat & Revenus" tables.
class StatCat {
  final String id; // key used in the result map
  final String fr, en; // legend label
  final String totalApi; // "Total ..." API  (one row)
  const StatCat(this.id, this.fr, this.en, this.totalApi);
}

/// Month-to-date and year-to-date totals per category, taken from EXACTLY the
/// same server procedure and APIs as the "Stat & Revenus" page:
///
///   1. POST /hotel/getDateSTAT_REAL/{cod_hotel}   -> IN1_date_purge_
///   2. POST /hotel/GENERER_TOUT_STAT              -> fills WORK_STAT_REV for the session
///        IN2 = yesterday   IN3 = 1 January   IN4/IN5 = same dates - 1 year
///   3. totals (parallel):  getDataSetLog      (Total logement)
///                          getSetDataNourTot  (Total nourritures)
///                          getSetBoissTot     (Total boissons)
///                          getSetDiversTot    (Total divers)
///      values are used tel quel (no rebuilding from the lines).
///
/// Result: category id -> [cumul du mois, cumul de l'année] (Mois A / Année A
/// columns of the report).
class StatTotals {
  static const cats = <StatCat>[
    StatCat('log', 'Logement', 'Accommodation', 'getDataSetLog'),
    StatCat('nour', 'Nourriture', 'Food', 'getSetDataNourTot'),
    StatCat('boiss', 'Boissons', 'Beverages', 'getSetBoissTot'),
    StatCat('div', 'Divers', 'Miscellaneous', 'getSetDiversTot'),
  ];

  /// Index of the month / year columns in the 8 figures of a report line:
  /// Jour A, Jour A-1 | Mois A, Mois Bud, Mois A-1 | Année A, Année Bud, Année A-1.
  static const int monthSlot = 2;
  static const int yearSlot = 5;

  static DateTime? _parseDmy(String s) {
    final m = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})').firstMatch(s.trim());
    if (m == null) return null;
    return DateTime(int.parse(m[3]!), int.parse(m[2]!), int.parse(m[1]!));
  }

  static DateTime _minusYear(DateTime d) =>
      DateTime(d.year - 1, d.month, (d.month == 2 && d.day == 29) ? 28 : d.day);

  /// Runs the procedure then reads the totals. [cancelled] stops the work as
  /// soon as the page is closed / reloaded. Returns {} when nothing was found.
  static Future<Map<String, List<double>>> fetch({
    bool Function()? cancelled,
  }) async {
    bool dead() => cancelled?.call() ?? false;
    final base = AppConfig.baseUrlOrDefault;
    final body = AppConfig.pointageBody();

    // session + hotel code + hotel date (same source as the Stat page)
    final shared = await Session.load();
    final sid = Session.sidOf(shared);
    var cod = (shared['codhotelnew'] ?? '').toString();
    if (cod.isEmpty) cod = Prefs.getString('codhotelnew');
    if (sid.isEmpty || cod.isEmpty) throw Exception('session not found');
    final hotelToday =
        _parseDmy((shared['dd'] ?? '').toString()) ?? DateTime.now();

    final d2 = DateTime(hotelToday.year, hotelToday.month, hotelToday.day - 1);
    final d3 = DateTime(d2.year, 1, 1); // 1 January, like the report

    // purge date (falls back to the oldest date of the report)
    var purge = '';
    try {
      final rows = await Loader.listRetry('$base/hotel/getDateSTAT_REAL/$cod', body,
          emptyRetries: 2, reportOffline: false, cancelled: dead);
      purge = _purgeFrom(rows);
    } catch (_) {}
    if (dead()) return {};
    if (purge.isEmpty) purge = Fmt.dmy(d3);

    // the procedure: ONE call, can be slow (same as the Stat page)
    try {
      await Api.post('$base/hotel/GENERER_TOUT_STAT', body,
          query: {
            'IN1_date_purge_': purge,
            'IN2_ce_jour_': Fmt.dmy(d2),
            'IN3_date_debut_': Fmt.dmy(d3),
            'IN4_ce_jour_a1': Fmt.dmy(_minusYear(d2)),
            'IN5_date_debut_a1': Fmt.dmy(_minusYear(d3)),
            'IN6_session_': sid,
            'IN7_cod_unite_': '',
            'IN8_cod_hotel_': cod,
          },
          retries: 0,
          reportOffline: false,
          timeout: const Duration(minutes: 10));
    } catch (e) {
      // the server may have finished anyway: still try to read the tables
      debugPrint('GENERER_TOUT_STAT (CA) $e');
    }
    if (dead()) return {};

    final out = <String, List<double>>{};
    await Future.wait([
      for (final c in cats)
        () async {
          final v = await _category(c, base, body, sid, cod, dead);
          if (v != null) out[c.id] = v;
        }(),
    ]);
    return out;
  }

  /// [month, year] of one category, exactly as the "Total ..." API sends it
  /// (no rebuilding, no rounding). null = the server sent nothing.
  static Future<List<double>?> _category(StatCat c, String base,
      Map<String, dynamic> body, String sid, String cod, bool Function() dead) async {
    try {
      final rows = await Loader.listRetry(
          '$base/hotel/${c.totalApi}/$sid/$cod', body,
          emptyRetries: 0, reportOffline: false, cancelled: dead);
      if (rows.isEmpty) return null;
      final v = _valuesOf(rows.first);
      return [v[monthSlot] ?? 0, v[yearSlot] ?? 0];
    } catch (_) {
      return null;
    }
  }

  // ------------------------------------------------------------ parsing
  // (same rules as the Stat & Revenus page, so the figures are identical)
  static final _numRe = RegExp(r'^-?\d+(\.\d+)?$');
  static double? _toNum(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    final s =
        v.toString().replaceAll(RegExp(r'[\s\u00A0]'), '').replaceAll(',', '.');
    return _numRe.hasMatch(s) ? double.tryParse(s) : null;
  }

  static const _noValue = {
    'formatnumber', 'session', 'sessionid', 'codwork', 'rangwork', 'typwork',
    'rangstatrev', 'typestatrev', 'libstatrev', 'rang', 'cod',
  };
  static const _trSlots = {
    'trj': 0, 'trjun': 1, 'trm': 2, 'trbm': 3,
    'trmun': 4, 'tra': 5, 'trba': 6, 'traun': 7,
  };

  static int? _slotOf(String key) {
    var k = key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (_noValue.contains(k) || k.startsWith('lib')) return null;
    if (_trSlots.containsKey(k)) return _trSlots[k];
    if (k == 'jj14') return 1;
    if (RegExp(r'^ec[ma]\d$').hasMatch(k)) return null; // ecart columns
    if (k.endsWith('x') && RegExp(r'(jour|mois|annee|anne)').hasMatch(k)) {
      k = k.substring(0, k.length - 1);
    }
    final bud = k.contains('bud');
    final a1 = k.endsWith('un') || RegExp(r'1$').hasMatch(k) || k.contains('a1');
    if (k.contains('jour')) return a1 ? 1 : 0;
    if (k.contains('mois')) return bud ? 3 : (a1 ? 4 : 2);
    if (k.contains('anne') || k.contains('year')) {
      return bud ? 6 : (a1 ? 7 : 5);
    }
    return null;
  }

  /// The 8 numeric figures of a row (null = absent / not a number).
  static List<double?> _valuesOf(Map<String, dynamic> r) {
    final out = List<double?>.filled(8, null);
    for (final e in r.entries) {
      final slot = _slotOf(e.key);
      if (slot == null) continue;
      var v = e.value;
      if (v is String) v = v.replaceAll('%', '').trim();
      final d = _toNum(v);
      // same figure sent twice (formatted + raw): keep the first one found
      if (out[slot] == null && d != null) out[slot] = d;
    }
    return out;
  }

  /// First date found in the getDateSTAT_REAL answer (key with "purge" first).
  static String _purgeFrom(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return '';
    String fmt(dynamic v) {
      final s = v?.toString().trim() ?? '';
      if (s.isEmpty) return '';
      if (_parseDmy(s) != null) {
        return s.substring(0, s.indexOf(RegExp(r'\d{4}')) + 4);
      }
      final o = Fmt.dmyAny(v);
      return _parseDmy(o) != null ? o : '';
    }

    final r = rows.first;
    for (final e in r.entries) {
      if (e.key.toLowerCase().contains('purge')) {
        final f = fmt(e.value);
        if (f.isNotEmpty) return f;
      }
    }
    for (final e in r.entries) {
      final f = fmt(e.value);
      if (f.isNotEmpty) return f;
    }
    return '';
  }
}
