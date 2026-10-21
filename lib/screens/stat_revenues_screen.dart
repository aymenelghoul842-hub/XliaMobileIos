import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../core/api_client.dart';
import '../core/app_config.dart';
import '../core/fmt.dart';
import '../core/lang.dart';
import '../core/loader.dart';
import '../core/net.dart';
import '../core/prefs.dart';
import '../core/responsive.dart';
import '../core/section.dart';
import '../core/session.dart';

/// "Stat & Revenus" (route /menu/Revenus) - same layout as the printed
/// report "Rapport statistiques & revenus": ONE table
///      Libellé | Jour (A, A-1) | Mois (A, A-1) | Année (A, A-1)
/// that always fits the screen width (no horizontal scroll).
///
/// Flow:
///   1. POST /hotel/GetDataproce                 -> hotel date, code, session
///   2. POST /hotel/getDateSTAT_REAL/{cod_hotel} -> IN1_date_purge_ (not shown)
///   3. POST /hotel/GENERER_TOUT_STAT            -> fills the server tables
///        IN2 = calendar date (default yesterday)   IN3 = 1 January
///        IN4 = IN2 - 1 year      IN5 = IN3 - 1 year
///        IN6 = session           IN7 = ''           IN8 = hotel code
///   4. every read API (in parallel) -> its rows are placed in report order.
class StatRevenuesScreen extends StatefulWidget {
  final VoidCallback? onMenu;
  const StatRevenuesScreen({super.key, this.onMenu});

  @override
  State<StatRevenuesScreen> createState() => _StatRevenuesScreenState();
}

enum _Kind { rows, total, revenue, section }

/// One read API = one block of the report (in report order).
class _Part {
  final String api;
  final bool session, hotel;
  final _Kind kind;
  final String label; // used when the API row has no libellé
  final bool gapAfter;
  final int? skipIfSameAs; // index of another part with identical rows
  final int? sumOf; // always the sum of another block's rows (no API call)
  final bool raw; // true: show the server text as is (statistics lines)
  final String section; // title band printed before this block's first line
  List<Map<String, dynamic>> rows = [];
  String error = '';
  String sample = ''; // first row as key=value (diagnostic)
  _Part(this.api, this.kind,
      {this.label = '',
      this.session = true,
      this.hotel = true,
      this.gapAfter = false,
      this.skipIfSameAs,
      this.sumOf,
      this.raw = false,
      this.section = ''});

  String path(String sid, String cod) {
    final p = StringBuffer('/hotel/$api');
    if (session) p.write('/$sid');
    if (hotel) p.write('/$cod');
    return p.toString();
  }
}

/// One printed line of the report.
class _Line {
  final String label;
  final List<String> v; // Jour A, A-1 | Mois A, Bud, A-1 | Année A, Bud, A-1 (Bud not displayed)
  final _Kind kind;
  final bool gap;
  const _Line(this.label, this.v, this.kind) : gap = false;
  const _Line.gap()
      : label = '',
        v = const [],
        kind = _Kind.rows,
        gap = true;
  const _Line.section(String title)
      : label = title,
        v = const [],
        kind = _Kind.section,
        gap = false;
}

class _StatRevenuesScreenState extends State<StatRevenuesScreen> {
  /// IN3 / IN5 start: false = 1st day of the MONTH, true = 1st of January.
  static const bool _startFromJanuary = true;

  // order of the printed report
  // SAME ORDER as the printed report "Rapport statistiques & revenus".
  // A block whose API row has no libellé gets the name below as its row label.
  final List<_Part> _parts = [
    // Same blocks, same order as the printed report. A block whose API has
    // no libellé (all the "Total ..." queries) gets the name given here.
    // 1. statistics lines (Nuitées clients ... Chambres offertes): the server
    //    sends them already formatted -> shown as is
    _Part('GetDataSetArrangement', _Kind.rows,
        label: 'Statistiques', raw: true),
    // 2. Total arrangement / Total extra
    _Part('getDataSetTotArrang', _Kind.total,
        label: 'Total arrangement:'),
    _Part('getDataSetTotExt', _Kind.total, label: 'Total extra:'),
    // 3. LOGEMENT lines + Total logement (sum of the lines if the API is empty)
    _Part('getPresta_log', _Kind.rows, label: 'Logement'),
    _Part('getDataSetLog', _Kind.total, label: 'Total logement:', sumOf: 3),
    // 4. Nourriture
    _Part('getDataSetNour', _Kind.rows,
        label: 'Nourriture'),
    _Part('getSetDataNourTot', _Kind.total,
        label: 'Total nourritures:', sumOf: 5),
    // 5. Boissons
    _Part('getSetDataBoiss', _Kind.rows, label: 'Boissons'),
    _Part('getSetBoissTot', _Kind.total, label: 'Total boissons:', sumOf: 7),
    // 6. Divers (typ_work 4)
    _Part('getSetDiversList', _Kind.rows, label: 'Divers'),
    _Part('getSetDiversTot', _Kind.total, label: 'Total divers:', sumOf: 9),
    // 7. Total Revenu (red line)
    _Part('getSetRevenus', _Kind.revenue,
        label: 'Total Revenu:', session: false),
    // 8. Autre (taxe de séjour, ristourne TVA ...) + Total Autre
    _Part('getSetDataAutre', _Kind.rows, label: 'Autre'),
    _Part('getSetDataAutreTot', _Kind.total,
        label: 'Total Autre:', sumOf: 12),
  ];

  final LoadToken _token = LoadToken();
  DateTime _hotelToday = _dateOnly(DateTime.now());
  DateTime? _picked; // user's choice; null = always yesterday
  String _phase = '';
  String _procInfo = ''; // result of GENERER_TOUT_STAT (diagnostic)
  String _ctxInfo = ''; // session / hotel / dates used (diagnostic)
  bool _loading = false;
  // loading state of the report card (same widgets as the Prévisions page)
  final Sec _sRep = Sec();

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
  DateTime get _yesterday =>
      DateTime(_hotelToday.year, _hotelToday.month, _hotelToday.day - 1);
  DateTime get _selected {
    final p = _picked ?? _yesterday;
    return p.isAfter(_yesterday) ? _yesterday : p; // never today / future
  }

  DateTime get _start => _startFromJanuary
      ? DateTime(_selected.year, 1, 1)
      : DateTime(_selected.year, _selected.month, 1);

  static DateTime _minusYear(DateTime d) =>
      DateTime(d.year - 1, d.month, (d.month == 2 && d.day == 29) ? 28 : d.day);

  String _t(String fr, String en) => AppLang.lang.value == 'en' ? en : fr;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _token.cancel();
    super.dispose();
  }

  static DateTime? _parseDmy(String s) {
    final m = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})').firstMatch(s.trim());
    if (m == null) return null;
    return DateTime(int.parse(m[3]!), int.parse(m[2]!), int.parse(m[1]!));
  }

  // ------------------------------------------------------------ loading
  Future<void> _loadAll() async {
    final gen = _token.begin();
    bool cur() => mounted && _token.isCurrent(gen);

    setState(() {
      _loading = true;
      _sRep.loading = true;
      _sRep.error = '';
      _phase = _t('Connexion au serveur…', 'Connecting to the server…');
      for (final p in _parts) {
        p.rows = [];
        p.error = '';
      }
    });

    void stop(String err) {
      if (!cur()) return;
      setState(() {
        _loading = false;
        _sRep.loading = false;
        _sRep.loaded = true;
        _sRep.error = err;
        _phase = '';
      });
    }

    try {
      final base = AppConfig.baseUrlOrDefault;
      final body = AppConfig.pointageBody();

      // 1. session + hotel date + hotel code
      final shared = await Session.load();
      if (!cur()) return;
      final sid = Session.sidOf(shared);
      var cod = (shared['codhotelnew'] ?? '').toString();
      if (cod.isEmpty) cod = Prefs.getString('codhotelnew');
      if (sid.isEmpty || cod.isEmpty) {
        stop(_t('Session ou code hôtel introuvable. Reconnectez-vous.',
            'Session or hotel code not found. Please log in again.'));
        return;
      }
      final hd = _parseDmy((shared['dd'] ?? '').toString());
      if (hd != null) setState(() => _hotelToday = hd);

      // 2. purge date (only launched, never shown)
      setState(() => _phase =
          _t('Préparation des statistiques…', 'Preparing the statistics…'));
      // If this API fails or answers nothing we do NOT stop: the oldest
      // date of the report (start of the month, A-1) is used instead.
      final d2 = _selected;
      final d3 = _start;
      var purge = '';
      try {
        final dateRows = await Loader.listRetry(
            '$base/hotel/getDateSTAT_REAL/$cod', body,
            emptyRetries: 2, reportOffline: false, cancelled: () => !cur());
        purge = _purgeFrom(dateRows);
      } catch (_) {}
      if (!cur()) return;
      if (purge.isEmpty) purge = Fmt.dmy(d3);

      // 3. procedure
      setState(() => _phase =
          _t('Génération des statistiques…', 'Generating the statistics…'));
      final procQuery = {
        'IN1_date_purge_': purge,
        'IN2_ce_jour_': Fmt.dmy(d2),
        'IN3_date_debut_': Fmt.dmy(d3),
        'IN4_ce_jour_a1': Fmt.dmy(_minusYear(d2)),
        'IN5_date_debut_a1': Fmt.dmy(_minusYear(d3)),
        'IN6_session_': sid,
        'IN7_cod_unite_': '',
        'IN8_cod_hotel_': cod,
      };
      _ctxInfo = procQuery.entries.map((e) => '${e.key}=${e.value}').join('\n');
      var procMsg = 'OK';
      // the procedure can be slow: wait up to 10 minutes, ONE call only
      // (a retry would start a second copy while the first is running)
      // and show the elapsed time.
      final sw = Stopwatch()..start();
      final ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!cur()) return;
        final m = sw.elapsed.inMinutes;
        final sec = (sw.elapsed.inSeconds % 60).toString().padLeft(2, '0');
        setState(() => _phase = _t(
            'Génération des statistiques… $m:$sec (peut durer plusieurs minutes)',
            'Generating the statistics… $m:$sec (may take several minutes)'));
      });
      try {
        await Api.post('$base/hotel/GENERER_TOUT_STAT', body,
            query: procQuery,
            retries: 0,
            reportOffline: false,
            timeout: const Duration(minutes: 10));
        procMsg = 'OK (${sw.elapsed.inSeconds}s)';
      } catch (e) {
        procMsg = 'ERREUR (${sw.elapsed.inSeconds}s): $e';
      } finally {
        ticker.cancel();
      }
      if (!cur()) return;
      _procInfo = procMsg;
      // a failed procedure is NOT a reason to stop (the server may have
      // finished anyway) - but it is shown in the status sheet.
      if (!procMsg.startsWith('OK')) debugPrint('GENERER_TOUT_STAT $procMsg');

      // 4. every block of the report
      setState(() =>
          _phase = _t('Chargement du rapport…', 'Loading the report…'));
      await Future.wait([
        for (final p in _parts) _loadPart(p, base, body, sid, cod, cur),
      ]);
      if (!cur()) return;
      // an error is shown ONLY when nothing at all could be loaded
      final any = _parts.any((p) => p.rows.isNotEmpty);
      final firstErr = _parts
          .map((p) => p.error)
          .firstWhere((e) => e.isNotEmpty, orElse: () => '');
      setState(() {
        _loading = false;
        _sRep.loading = false;
        _sRep.loaded = true;
        _sRep.error = any ? '' : firstErr;
        _phase = '';
      });
    } catch (e) {
      stop(Net.message(e));
    }
  }

  Future<void> _loadPart(_Part p, String base, Map<String, dynamic> body,
      String sid, String cod, bool Function() cur) async {
    try {
      final rows = await Loader.listRetry('$base${p.path(sid, cod)}', body,
          emptyRetries: 0, reportOffline: false, cancelled: () => !cur());
      if (cur()) {
        p.rows = rows;
        p.sample = rows.isEmpty
            ? ''
            : rows.first.entries
                .take(16)
                .map((e) => '${e.key}=${e.value}')
                .join('  ');
      }
    } catch (e) {
      // this API failed: skip ONLY this block, the others are not affected
      if (cur()) p.error = Net.message(e);
    }
    debugPrint('STAT ${p.api}: ${p.rows.length} rows ${p.error}');
    // show this block right away (progressive loading, like Prévisions)
    if (cur() && mounted) setState(() {});
  }

  /// First date found in the getDateSTAT_REAL answer (key with "purge" first).
  String _purgeFrom(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return '';
    String fmt(dynamic v) {
      final s = v?.toString().trim() ?? '';
      if (s.isEmpty) return '';
      if (_parseDmy(s) != null) {
        return s.substring(0, s.indexOf(RegExp(r'\d{4}')) + 4);
      }
      final out = Fmt.dmyAny(v);
      return _parseDmy(out) != null ? out : '';
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

  Future<void> _pickDate() async {
    final last = _yesterday; // today and later are not selectable
    final res = await showDatePicker(
      context: context,
      initialDate: _selected,
      firstDate: DateTime(2000),
      lastDate: last,
    );
    if (res == null || !mounted) return;
    final d = _dateOnly(res);
    setState(() => _picked = d.isAfter(last) ? last : d);
    _loadAll();
  }


  // ------------------------------------------------- Total Revenu
  // In the printed report:  Total Revenu = Total logement + Total nourritures
  //                                      + Total boissons + Total divers
  // (also = Total arrangement + Total extra). getSetRevenus calls Oracle
  // functions (pck_edition.CF_R1Formula*) that depend on the DB session, and
  // every request uses a NEW connection -> it can answer 0 / null. So when
  // it does, the figure is rebuilt from the four totals.
  static const _revParts = [4, 6, 8, 10]; // indexes of the four totals

  /// The 8 figures of a total block: its own API row, or (if that API gave
  /// nothing) the sum of its lines. null = nothing available.
  List<double?>? _totalVals(int idx) {
    final p = _parts[idx];
    if (p.rows.isNotEmpty) {
      return [for (final x in _valuesOf(p.rows.first, '')) _toNum(x)];
    }
    final src = idx > 0 ? _parts[idx - 1].rows : <Map<String, dynamic>>[];
    if (src.isEmpty) return null;
    final sums = List<double?>.filled(8, null);
    for (final r in src) {
      final v = _valuesOf(r, '');
      for (var i = 0; i < 8; i++) {
        final d = _toNum(v[i]);
        if (d != null) sums[i] = (sums[i] ?? 0) + d;
      }
    }
    return sums;
  }

  /// Figures of the "Total Revenu" line (null = no data at all).
  List<double?>? _revenueVals() {
    final rev = _parts.firstWhere((p) => p.kind == _Kind.revenue);
    List<double?>? api;
    if (rev.rows.isNotEmpty) {
      api = [for (final x in _valuesOf(rev.rows.first, '')) _toNum(x)];
    }
    // rebuilt only when the four totals are all available
    final tots = [for (final i in _revParts) _totalVals(i)];
    List<double?>? calc;
    if (tots.every((t) => t != null)) {
      calc = List<double?>.filled(8, null);
      for (var i = 0; i < 8; i++) {
        double? s;
        for (final t in tots) {
          final d = t![i];
          if (d != null) s = (s ?? 0) + d;
        }
        calc[i] = s;
      }
    }
    if (api == null) return calc;
    if (calc == null) return api;
    return [
      for (var i = 0; i < 8; i++)
        (api[i] == null || (api[i] == 0 && (calc[i] ?? 0) != 0))
            ? calc[i]
            : api[i]
    ];
  }

  // ------------------------------------------- rows -> report lines
  static final _numRe = RegExp(r'^-?\d+(\.\d+)?$');
  static double? _toNum(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    final s =
        v.toString().replaceAll(RegExp(r'[\s\u00A0]'), '').replaceAll(',', '.');
    return _numRe.hasMatch(s) ? double.tryParse(s) : null;
  }

  static final _skipKey = RegExp(
      r'^(id|cod|code|ordre|order|rang|num|numero|session|sess|saission|sid|idx|index|seq|typ|type)([_a-z0-9]*)$',
      caseSensitive: false);
  // keys that really are a row libellé (strong) / may be one (weak)
  static final _strongKey = RegExp(
      r'(lib|label|design|intitul|rubrique)',
      caseSensitive: false);
  static final _weakKey = RegExp(r'(nom|name|nature|titre)',
      caseSensitive: false);

  /// libellé of a row. A field only counts when it really names the row:
  /// in a block with several rows its value must be different from row to
  /// row (a constant column such as a hotel name is NOT a libellé).
  /// Returns '' when the API has no libellé (the block's own name is used).
  String _labelOf(Map<String, dynamic> r, List<Map<String, dynamic>> all) {
    bool varies(String k) {
      if (all.length < 2) return true;
      return all.map((x) => '${x[k] ?? ''}').toSet().length > 1;
    }

    String text(dynamic v) {
      final s = v?.toString().trim() ?? '';
      return (s.isEmpty || _toNum(v) != null) ? '' : s;
    }

    for (final e in r.entries) {
      if (_strongKey.hasMatch(e.key) && varies(e.key)) {
        final s = text(e.value);
        if (s.isNotEmpty) return s;
      }
    }
    if (all.length > 1) {
      for (final e in r.entries) {
        if (_weakKey.hasMatch(e.key) && varies(e.key)) {
          final s = text(e.value);
          if (s.isNotEmpty) return s;
        }
      }
      for (final e in r.entries) {
        if (varies(e.key)) {
          final s = text(e.value);
          if (s.isNotEmpty) return s;
        }
      }
    }
    return '';
  }

  /// The eight figures of a row, in the order of the printed report:
  /// Jour A, Jour A-1 | Mois A, Mois Bud, Mois A-1 | Année A, Année Bud, Année A-1.
  /// The column is found from the field name (jour / jour1 / jour_1 / sumJourUn,
  /// mois / budg_mois / sumBudMois, annee / annee_1 / sumAnne, TRJ ... TRJUN,
  /// GJour ... ) so the order the server sends the fields in does not matter.
  static const _noValue = {
    'formatnumber', 'session', 'sessionid', 'codwork', 'rangwork', 'typwork',
    'rangstatrev', 'typestatrev', 'libstatrev', 'rang', 'cod',
  };
  static const _trSlots = {
    'trj': 0, 'trjun': 1, 'trm': 2, 'trbm': 3,
    'trmun': 4, 'tra': 5, 'trba': 6, 'traun': 7,
  };

  int? _slotOf(String key) {
    var k = key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (_noValue.contains(k) || k.startsWith('lib')) return null;
    if (_trSlots.containsKey(k)) return _trSlots[k];
    if (k == 'jj14') return 1;
    if (RegExp(r'^ec[ma]\d$').hasMatch(k)) return null; // ecart columns
    if (k.endsWith('x') && RegExp(r'(jour|mois|annee|anne)').hasMatch(k)) {
      k = k.substring(0, k.length - 1); // jour_x, mois_1_x ...
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

  List<dynamic> _valuesOf(Map<String, dynamic> r, String label) {
    final out = List<dynamic>.filled(8, null);
    final named = <int>{};
    var ok = true;
    for (final e in r.entries) {
      final slot = _slotOf(e.key);
      if (slot == null) continue;
      var v = e.value;
      if (v is String) v = v.replaceAll('%', '').trim();
      if (!named.add(slot)) {
        // same figure sent twice (formatted + raw): keep the first one found
        if (out[slot] == null || '${out[slot]}'.isEmpty) out[slot] = v;
        continue;
      }
      out[slot] = v;
    }
    if (ok && named.isNotEmpty) return out;

    // unknown field names (ex. VAL1..VAL6): keep the order of the fields
    final keys = <String>[];
    for (final e in r.entries) {
      final k = e.key.toLowerCase();
      if (e.value != null && _toNum(e.value) == null) {
        if ((e.value.toString().trim()).isNotEmpty) continue; // text column
      }
      if (_skipKey.hasMatch(k)) continue;
      keys.add(e.key);
    }
    final fb = List<dynamic>.filled(8, null);
    for (var i = 0; i < keys.length && i < 8; i++) {
      fb[i] = r[keys[i]];
    }
    return fb;
  }

  // amounts like the printed report: 3 decimals, spaces between thousands
  // (95 653,207 / -96,000 / 0,000). On phones amounts >= 1000 lose their
  // decimals so the nine columns still fit the screen.
  String _amt(double d, bool compact) {
    var dec = 3;
    if (compact && d.abs() >= 1000) dec = 0;
    final fixed = d.abs().toStringAsFixed(dec);
    final parts = fixed.split('.');
    final ip = parts[0];
    final buf = StringBuffer();
    for (var i = 0; i < ip.length; i++) {
      if (i > 0 && (ip.length - i) % 3 == 0) buf.write(' ');
      buf.write(ip[i]);
    }
    final s = parts.length > 1 ? '$buf,${parts[1]}' : buf.toString();
    return (d < 0 && double.parse(fixed) != 0) ? '-$s' : s;
  }

  /// One cell of a line.
  ///  * statistics block : the server text as is (no % sign, like the report)
  ///  * detail lines     : blank when 0 (like the report)
  ///  * total lines      : always printed, even 0,000
  String _cell(dynamic v, _Part p, bool compact) {
    if (v == null) return '';
    if (p.raw) {
      if (v is num) {
        final t = v == v.roundToDouble()
            ? v.toInt().toString()
            : v.toString().replaceAll('.', ',');
        return t;
      }
      return v.toString().replaceAll('%', '').trim();
    }
    final d = _toNum(v);
    if (d == null) return v.toString().trim();
    if (p.kind == _Kind.rows && d == 0) return '';
    return _amt(d, compact);
  }

  List<_Line> _lines(bool compact) {
    final out = <_Line>[];
    // A "Total ..." line is printed only once, at its first place (like the
    // printed report): the server can answer the same total in two APIs.
    final seenTotals = <String>{};
    bool firstTotal(String label) {
      final k = label.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      return seenTotals.add(k);
    }

    for (var pi = 0; pi < _parts.length; pi++) {
      final p = _parts[pi];
      final mark = out.length;
      try {
        _addPart(out, p, pi, compact, firstTotal);
      } catch (_) {
        // unreadable answer from one API: skip that block only
        if (out.length > mark) out.removeRange(mark, out.length);
      }
    }
    return out;
  }

  void _addPart(List<_Line> out, _Part p, int pi, bool compact,
      bool Function(String) firstTotal) {
    if (p.kind == _Kind.revenue) {
      final rv = _revenueVals();
      if (rv != null &&
          !rv.every((d) => (d ?? 0) == 0) &&
          firstTotal(p.label)) {
        out.add(_Line(p.label, [for (final v in rv) _cell(v, p, compact)],
            p.kind));
      }
      return;
    }
    // same rows as another block: the "Total" line is the sum of that block
    final same = p.sumOf ?? p.skipIfSameAs;
    if (same != null &&
        ((p.sumOf != null && p.rows.isEmpty) ||
            (p.sumOf == null &&
                p.rows.isNotEmpty &&
                jsonEncode(p.rows) == jsonEncode(_parts[same].rows)))) {
      if (_parts[same].rows.isEmpty) return;
      final sums = List<double?>.filled(8, null);
      for (final r in _parts[same].rows) {
        final v = _valuesOf(r, '');
        for (var i = 0; i < 8; i++) {
          final d = _toNum(v[i]);
          if (d != null) sums[i] = (sums[i] ?? 0) + d;
        }
      }
      if (sums.every((d) => (d ?? 0) == 0)) return; // no data -> skipped
      if (firstTotal(p.label)) {
        out.add(_Line(
            p.label,
            [for (final d in sums) d == null ? '' : _amt(d, compact)],
            p.kind));
      }
      return;
    }

    final startLen = out.length;
    final isRows = p.kind == _Kind.rows;
    // a line without libellé gets the block's own name (numbered if several)
    final noLib =
        isRows ? p.rows.where((r) => _labelOf(r, p.rows).isEmpty).length : 0;
    var n = 0;
    for (final r in p.rows) {
      // total lines never have a libellé in their SQL -> fixed name
      var label = isRows ? _labelOf(r, p.rows) : p.label;
      final rawVals = _valuesOf(r, label);
      final vals = [for (final v in rawVals) _cell(v, p, compact)];
      final empty = vals.every((e) => e.isEmpty);
      final noValue =
          rawVals.every((v) => v == null || v.toString().trim().isEmpty);
      // figures present but all 0 -> not printed (like the report);
      // no figure received at all -> kept, so a wrong mapping is visible
      if (empty && !noValue && !p.raw) continue;
      // a total made only of zeros = no data today -> skipped
      if (!isRows &&
          !p.raw &&
          rawVals.every((v) => (_toNum(v) ?? 0) == 0)) {
        continue;
      }
      if (label.isEmpty) {
        if (empty) continue;
        n++;
        label = noLib > 1 ? '${p.label} $n' : p.label;
      }
      if (!isRows && !firstTotal(label)) continue;
      out.add(_Line(label, vals, p.kind));
    }
    if (out.length > startLen && p.section.isNotEmpty) {
      out.insert(startLen, _Line.section(p.section));
    }
  }

  // ----------------------------------------------------------------- UI
  static const _days = [
    'lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'
  ];
  static const _daysEn = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
  ];
  static const _blue = Color(0xFF1A3FBF);
  static const _red = Color(0xFFC00000);
  static const _ink = Color(0xFF1B2540);
  static const _muted = Color(0xFF7886A5);
  static const _rule = Color(0xFFE6EAF3);
  // Jour / Mois / Année accent colors
  static const _cDay = Color(0xFF2F6FED);
  static const _cMonth = Color(0xFF0F9D8A);
  static const _cYear = Color(0xFF7A4DE8);
  static const _slotColor = [
    _cDay, _cDay, _cMonth, _cMonth, _cMonth, _cYear, _cYear, _cYear
  ];

  // Table: Libellé | Jour (A, A-1) | Mois (A, A-1) | Année (A, A-1)
  // (the "Bud" columns are not shown). Always fits the screen width.
  static const _shown = [0, 1, 2, 4, 5, 7];
  static const int _fLabel = 30, _fNum = 14;
  static const double _fsLabel = 16, _fsData = 14;
  static const _grid = BorderSide(color: Color(0xFFB8C2D9), width: 0.8);

  Widget _tc(int flex, Widget child,
          {Color? color, Alignment align = Alignment.centerRight}) =>
      Expanded(
        flex: flex,
        child: Container(
          alignment: align,
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 7),
          decoration: BoxDecoration(
            color: color,
            border: const Border(right: _grid, bottom: _grid),
          ),
          child: child,
        ),
      );

  Widget _trow(List<Widget> cells) => IntrinsicHeight(
        child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch, children: cells),
      );

  Widget _data(String s, TextStyle st, {Alignment a = Alignment.centerRight}) =>
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: a,
        child: Text(s, maxLines: 1, style: st),
      );

  Widget _reportHeader(bool fr) {
    Widget group(String t, Color c) => _tc(
        _fNum * 2,
        _data(
            t,
            const TextStyle(
                color: Colors.white,
                fontSize: _fsLabel,
                fontWeight: FontWeight.w800),
            a: Alignment.center),
        color: c,
        align: Alignment.center);
    Widget sub(String t, Color c) => _tc(
        _fNum,
        _data(
            t,
            TextStyle(
                fontSize: _fsData, color: c, fontWeight: FontWeight.w700),
            a: Alignment.center),
        color: const Color(0xFFF1F4FB),
        align: Alignment.center);
    const subs = ['(A)', '(A-1)', '(A)', '(A-1)', '(A)', '(A-1)'];
    const cols = [_cDay, _cDay, _cMonth, _cMonth, _cYear, _cYear];
    return Column(children: [
      _trow([
        _tc(_fLabel, const SizedBox(), color: const Color(0xFFF1F4FB)),
        group(fr ? 'Jour' : 'Day', _cDay),
        group(fr ? 'Mois' : 'Month', _cMonth),
        group(fr ? 'Année' : 'Year', _cYear),
      ]),
      _trow([
        _tc(
            _fLabel,
            Text(fr ? 'Libellé' : 'Label',
                style: const TextStyle(
                    fontSize: _fsLabel,
                    fontWeight: FontWeight.w800,
                    color: _ink)),
            color: const Color(0xFFF1F4FB),
            align: Alignment.centerLeft),
        for (var i = 0; i < 6; i++) sub(subs[i], cols[i]),
      ]),
    ]);
  }

  Widget _sectionBand(String t) => _trow([
        _tc(
            _fLabel + _fNum * 6,
            Text(t.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: _fsLabel,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    color: _ink)),
            color: const Color(0xFFE3E9F6),
            align: Alignment.centerLeft),
      ]);

  Widget _lineRow(_Line l, int idx) {
    if (l.kind == _Kind.section) return _sectionBand(l.label);
    final strong = l.kind != _Kind.rows;
    final isRev = l.kind == _Kind.revenue;
    final base = isRev ? _red : (strong ? _blue : _ink);
    final tint = isRev
        ? const Color(0xFFFFEBEB)
        : strong
            ? const Color(0xFFE8EEFF)
            : (idx.isEven ? Colors.white : const Color(0xFFF8FAFD));
    return _trow([
      _tc(
          _fLabel,
          Text(l.label.trim(),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: _fsLabel,
                  color: base,
                  fontWeight: strong ? FontWeight.w800 : FontWeight.w500)),
          color: tint,
          align: Alignment.centerLeft),
      for (final slot in _shown)
        _tc(
            _fNum,
            _data(
                slot < l.v.length ? l.v[slot] : '',
                TextStyle(
                    fontSize: _fsData,
                    color: (slot < l.v.length && l.v[slot].startsWith('-'))
                        ? _red
                        : (strong ? base : _ink),
                    fontWeight: strong ? FontWeight.w800 : FontWeight.w600)),
            color: tint),
    ]);
  }

  Widget _report(BuildContext context) {
    final compact = R.width(context) < 600;
    final fr = AppLang.lang.value != 'en';
    final lines = _lines(compact);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Align(
          alignment: Alignment.centerRight,
          child: Text(fr ? 'Montants en T.T.C' : 'Amounts incl. tax',
              style: const TextStyle(
                  fontSize: _fsData, color: _muted, fontStyle: FontStyle.italic)),
        ),
      ),
      Container(
        decoration:
            const BoxDecoration(border: Border(left: _grid, top: _grid)),
        child: Column(children: [
          _reportHeader(fr),
          for (var i = 0; i < lines.length; i++) _lineRow(lines[i], i),
        ]),
      ),
    ]);
  }

  // ---- big figures: Total Revenu (day / month / year) with the A-1 gap
  Widget _kpis(BuildContext context) {
    final v = _revenueVals();
    if (v == null) return const SizedBox.shrink();
    final fr = AppLang.lang.value != 'en';

    Widget tile(String title, dynamic a, dynamic a1, Color c) {
      final da = _toNum(a);
      final d1 = _toNum(a1);
      if (da == null) return const Expanded(child: SizedBox());
      final pct = (d1 != null && d1 != 0) ? (da - d1) / d1.abs() * 100 : null;
      final up = (pct ?? 0) >= 0;
      return Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
                colors: [c, c.withOpacity(0.78)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                  color: c.withOpacity(0.25),
                  blurRadius: 8,
                  offset: const Offset(0, 3)),
            ],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(_amt(da, true),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800)),
            ),
            const SizedBox(height: 6),
            if (pct != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.22),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(up ? Icons.arrow_upward : Icons.arrow_downward,
                      size: 11, color: Colors.white),
                  const SizedBox(width: 2),
                  Text('${pct.abs().toStringAsFixed(1)}%',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700)),
                ]),
              ),
          ]),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(left: 6, bottom: 6),
          child: Text(fr ? 'Total Revenu' : 'Total Revenue',
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w800, color: _ink)),
        ),
        Row(children: [
          tile(fr ? 'Jour' : 'Day', v[0], v[1], _cDay),
          tile(fr ? 'Mois' : 'Month', v[2], v[4], _cMonth),
          tile(fr ? 'Année' : 'Year', v[5], v[7], _cYear),
        ]),
      ]),
    );
  }

  // ---- which API answered / which one was skipped
  Widget _statusBar(bool fr) {
    if (_loading || !_sRep.loaded) return const SizedBox.shrink();
    final total = _parts.length;
    final okN = _parts.where((p) => p.rows.isNotEmpty).length;
    final good = okN == total;
    const c = Color(0xFF5B6B8C); // neutral: an API without data is normal
    return Align(
      alignment: Alignment.center,
      child: ActionChip(
        avatar: Icon(good ? Icons.check_circle : Icons.info_outline,
            size: 18, color: c),
        label: Text(
            fr ? '$okN/$total blocs avec données' : '$okN/$total blocks with data',
            style: TextStyle(color: c, fontWeight: FontWeight.w700)),
        backgroundColor: c.withOpacity(0.10),
        side: BorderSide(color: c.withOpacity(0.35)),
        onPressed: () => _showStatus(fr),
      ),
    );
  }

  String _sidForSql() {
    final m = RegExp(r'IN6_session_=(.*)').firstMatch(_ctxInfo);
    return m == null ? '' : m[1]!.trim();
  }

  void _showStatus(bool fr) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(fr ? 'État des API du rapport' : 'Report API status',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _procInfo.startsWith('OK')
                    ? const Color(0xFFE8F5E9)
                    : const Color(0xFFFFEBEE),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                  'GENERER_TOUT_STAT: $_procInfo\n$_ctxInfo\n'
                  'SQL: select typ_work, count(*) from work_stat_rev '
                  "where session_id='${_sidForSql()}' group by typ_work",
                  style: const TextStyle(fontSize: 11)),
            ),
            const SizedBox(height: 6),
            Flexible(
              child: ListView(shrinkWrap: true, children: [
                for (final p in _parts)
                  ListTile(
                    dense: true,
                    leading: Icon(
                      p.error.isNotEmpty
                          ? Icons.error_outline
                          : (p.rows.isNotEmpty
                              ? Icons.check_circle
                              : Icons.remove_circle_outline),
                      color: p.error.isNotEmpty
                          ? Colors.red
                          : (p.rows.isNotEmpty ? Colors.green : Colors.grey),
                    ),
                    title: Text(p.api,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                        p.error.isNotEmpty
                            ? p.error
                            : (p.rows.isNotEmpty
                                ? '${p.rows.length} ${fr ? 'ligne(s)' : 'row(s)'}\n${p.sample}'
                                : (fr
                                    ? 'Aucune ligne reçue'
                                    : 'No rows received')),
                        maxLines: 6,
                        style: const TextStyle(fontSize: 11.5)),
                  ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d2 = _selected;
    final hasRows = _parts.any((p) => p.rows.isNotEmpty);
    final fr = AppLang.lang.value != 'en';
    final dayName = (fr ? _days : _daysEn)[d2.weekday - 1];

    return Scaffold(
      appBar: xliaAppBar(
        context,
        title: 'Stat & Revenus',
        date: Fmt.dmy(d2),
        loading: _loading,
        onRefresh: _loadAll,
        onMenu: widget.onMenu,
      ),
      body: RefreshIndicator(
        onRefresh: _loadAll,
        child: ResponsivePage(
          children: [
            // ---- date
            AppCard(
              child: Column(children: [
                Row(children: [
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(fr ? 'Journée du' : 'Day of',
                              style: const TextStyle(
                                  fontSize: 12, color: _muted)),
                          const SizedBox(height: 2),
                          Text('$dayName, ${Fmt.dmy(d2)}',
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: _ink)),
                        ]),
                  ),
                  OutlinedButton.icon(
                    onPressed: _loading ? null : _pickDate,
                    icon: const Icon(Icons.calendar_month, size: 18),
                    label: Text(fr ? 'Changer' : 'Change'),
                  ),
                ]),
                if (_loading) ...[
                  const SizedBox(height: 10),
                  const ClipRRect(
                    borderRadius: BorderRadius.all(Radius.circular(4)),
                    child: LinearProgressIndicator(minHeight: 3),
                  ),
                  const SizedBox(height: 8),
                  Text(_phase,
                      style: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w600)),
                ],
              ]),
            ),
            const SizedBox(height: 14),

            _kpis(context),

            // ---- the report: every API block, in the order of the printed
            // report, in ONE table. Same loading widgets as Prévisions.
            SecCard(
              sec: _sRep,
              hasData: hasRows,
              onRetry: _loadAll,
              minHeight: 160,
              child: hasRows
                  ? _report(context)
                  : Padding(
                      padding: const EdgeInsets.all(16),
                      child: Center(
                          child: Text(fr ? 'Aucune donnée' : 'No data',
                              style: const TextStyle(color: Colors.black54))),
                    ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
