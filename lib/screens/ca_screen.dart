import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/app_config.dart';
import '../core/charts.dart';
import '../core/fmt.dart';
import '../core/lang.dart';
import '../core/loader.dart';
import '../core/responsive.dart';
import '../core/section.dart';
import '../core/session.dart';
import '../core/stat_totals.dart';

/// Port of FeedbackPage ("CA" / Chiffre d'Affaire, route /menu/feedback).
///
/// Flow (same as the Ionic page):
///   1. POST /hotel/GetDataproce
///   2. procedures: generer_prev_agence_mobile  (forecast, today -> +1 month)
///                  then, for the realized table:
///                  /generer -> /init_jour_prev -> generer_prev_agence_mobile1
///                  (1st of month -> yesterday)
///   3. tables (parallel, retried while empty):
///        getlistmoiss/{sid}  -> realized turnover by agency
///        getlistmois/{sid}   -> forecasted turnover by agency
///   4. charts (parallel): getchhotel (line)
///                         pies month / year: SAME procedure + APIs as the
///                         "Stat & Revenus" page (GENERER_TOUT_STAT, then the
///                         totals Logement / Nourriture / Boissons / Divers:
///                         column Mois = month pie, column Année = year pie)
class CaScreen extends StatefulWidget {
  final VoidCallback? onMenu;
  const CaScreen({super.key, this.onMenu});

  @override
  State<CaScreen> createState() => _CaScreenState();
}

/// Everything the sections share for one load: session id, dates and the two
/// server procedures. Procedures start lazily (only when a section needs them)
/// and run ONCE per load, whichever sections wait for them.
class _CaCtx {
  final String base, sid, cod, dd, six, hierPass, setHier;
  final Map<String, dynamic> body;
  _CaCtx(this.base, this.body, this.sid, this.cod, this.dd, this.six,
      this.hierPass, this.setHier);

  Future<bool> _proc(String path, String a, String b) => Loader.procedure(
        '$base/hotel/$path',
        body,
        {
          'cod_agence_': '', 'offre_': 'N', 'typ_eb': '-1', 'eb_': '',
          'd1': a, 'd2': b, 'session_': sid, 'cod_hotel_': cod,
        },
      );

  // dd..six = today -> today + 1 month (forecast) ; hierPass..setHier = 1st of month -> yesterday (realized)
  late final Future<bool> fwd = _proc('generer_prev_agence_mobile', dd, six);
  // Realized table: GENERER -> INIT_JOUR_PREV -> generer_prev_agence_mobile1.
  // It starts only AFTER the forecast procedure: INIT_JOUR_PREV rewrites the
  // shared JOUR_PREV table that generer_prev_agence_mobile reads, so running
  // both at the same time would corrupt the forecast. A failure of GENERER or
  // INIT_JOUR_PREV never blocks the realized procedure.
  late final Future<bool> past = () async {
    await fwd;
    await Loader.procedure('$base/hotel/generer', body,
        {'cod_agence_': '', 'cod_user_': '0', 'cod_hotel_': cod});
    await Loader.procedure('$base/hotel/init_jour_prev', body,
        {'d1': hierPass, 'd2': setHier, 'session_': sid});
    return _proc('generer_prev_agence_mobile1', hierPass, setHier);
  }();
  List<Future<bool>> get all => [fwd, past];
}

class _CaScreenState extends State<CaScreen>
    with WidgetsBindingObserver, SecLoader<CaScreen> {
  static const _page = 'ca';
  static const _teal = Color(0xFF4BC0C0);
  static const _pieColors = [
    Color(0xFFBB20A0), Color(0xFFFFA500), Color(0xFF4169E1),
    Color(0xFFF4D03F), Color(0xFFFF6347),
  ];

  // one loading state per table / chart
  final Sec _sLine = Sec(), _sReal = Sec(), _sFore = Sec();
  final Sec _sPieM = Sec(), _sPieY = Sec();
  List<Sec> get _secs => [_sLine, _sReal, _sFore, _sPieM, _sPieY];
  bool get _anyLoading => _secs.any((s) => s.loading);

  String _error = '';

  // dates (same rules as initializeDates())
  bool _realCustom = false; // user picked another period for the realized table
  bool _foreCustom = false; // user picked another period for the forecast table
  late DateTime _today;
  late DateTime _hotelToday; // hotel business date (limit of both calendars)
  late DateTime _prevStart, _prevEnd, _nextStart, _nextEnd;

  List<Map<String, dynamic>> _realized = []; // getlistmoiss
  List<Map<String, dynamic>> _forecast = []; // getlistmois

  List<String> _lineLabels = [];
  List<double> _lineValues = []; // valeur ajoutée
  List<double> _lineTtc = [];
  // category id -> [cumul du mois, cumul de l'année] (from Stat & Revenus)
  Map<String, List<double>> _totals = {};
  int _pieGen = 0; // bumped on every pies load -> older answers are ignored

  List<PieEntry> _pieOf(int slot) {
    final out = <PieEntry>[];
    for (final c in StatTotals.cats) {
      final v = (_totals[c.id] ?? const [0.0, 0.0])[slot];
      if (v <= 0) continue; // a pie only shows positive amounts
      final name = _t(c.fr, c.en);
      out.add(PieEntry(name, '$name: ${v.truncate()}', v,
          _pieColors[out.length % _pieColors.length]));
    }
    return out;
  }

  List<PieEntry> get _pieMonth => _pieOf(0);
  List<PieEntry> get _pieYear => _pieOf(1);

  // sorting: [column, ascending] per table (null = server order)
  int? _rSortCol;
  bool _rAsc = true;
  int? _fSortCol;
  bool _fAsc = true;

  // pagination: 10 agencies per page in each table
  static const int _perPage = 10;
  int _rPage = 1;
  int _fPage = 1;

  bool get _fr => isFr;
  String _t(String fr, String en) => tr(fr, en);

  @override
  void initState() {
    super.initState();
    AppLang.lang.addListener(_onLang);
    WidgetsBinding.instance.addObserver(this);
    _initDates();
    _restore();
    // Fresh data (< 3 min) is shown as is; otherwise the cached numbers stay
    // visible while every section refreshes by itself.
    if (!PageCache.fresh(_page)) _loadAll();
  }

  void _onLang() {
    if (mounted) setState(() {});
  }

  /// Back to the app (phone woke up / network changed): reload by itself.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        mounted &&
        !_anyLoading &&
        !PageCache.fresh(_page)) {
      _loadAll();
    }
  }

  @override
  void dispose() {
    _pieGen++;
    for (final s in _secs) {
      s.gen++; // drop every running answer
    }
    WidgetsBinding.instance.removeObserver(this);
    AppLang.lang.removeListener(_onLang);
    super.dispose();
  }

  // Realized table: 1st day of the month -> yesterday.
  // Forecast table: current day -> same day next month.
  void _initDates() {
    _today = DateTime.now();
    _hotelToday = DateTime(_today.year, _today.month, _today.day);
    if (!_realCustom) _setRealizedPeriod(_today);
    if (!_foreCustom) _setForecastPeriod(_today);
  }

  /// Realized period = 1st day of the month of YESTERDAY -> yesterday.
  /// (On the 1st of a month this is the whole previous month, so the period
  /// is never empty / reversed.)
  void _setRealizedPeriod(DateTime today) {
    final yesterday = DateTime(today.year, today.month, today.day - 1);
    _prevEnd = yesterday;
    _prevStart = DateTime(yesterday.year, yesterday.month, 1);
  }

  void _setForecastPeriod(DateTime today) {
    _nextStart = DateTime(today.year, today.month, today.day);
    _nextEnd = _plusOneMonth(today);
  }

  /// Same day next month (31 Jan -> 28/29 Feb: clamped to the month's end).
  static DateTime _plusOneMonth(DateTime d) {
    final lastDay = DateTime(d.year, d.month + 2, 0).day;
    return DateTime(d.year, d.month + 1, d.day > lastDay ? lastDay : d.day);
  }

  /// "dd/MM/yyyy" (server format) -> DateTime, null if not parsable.
  DateTime? _parseDmy(String v) {
    final m = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(v.trim());
    if (m == null) return null;
    return DateTime(int.parse(m[3]!), int.parse(m[2]!), int.parse(m[1]!));
  }

  void _restore() {
    final r = PageCache.get<List<Map<String, dynamic>>>(_page, 'real');
    if (r != null) {
      _realized = r;
      _sReal.loaded = true;
    }
    final f = PageCache.get<List<Map<String, dynamic>>>(_page, 'fore');
    if (f != null) {
      _forecast = f;
      _sFore.loaded = true;
    }
    final lab = PageCache.get<List<String>>(_page, 'lineLabels');
    final val = PageCache.get<List<double>>(_page, 'lineValues');
    if (lab != null && val != null) {
      _lineLabels = lab;
      _lineValues = val;
      _lineTtc = PageCache.get<List<double>>(_page, 'lineTtc') ?? [];
      _sLine.loaded = true;
    }
    final tot = PageCache.get<Map<String, List<double>>>(_page, 'statTotals');
    if (tot != null) {
      _totals = tot;
      _sPieM.loaded = true;
      _sPieY.loaded = true;
    }
  }

  // ------------------------------------------------------------- data
  /// Whole page: every section starts at the same time and shows its data AS
  /// SOON AS IT ARRIVES (no more waiting for the slowest one).
  Future<void> _loadAll() async {
    if ((AppConfig.pointageBody()['url'] as String).isEmpty) {
      setState(() => _error =
          'URL de base de données manquante. Vérifiez la configuration.');
      return;
    }
    setState(() {
      _error = '';
      _realCustom = false; // full refresh: back to 1st of month -> yesterday
      _foreCustom = false; // forecast: back to today -> +1 month
      _initDates();
    });
    final ctx = _newCtx(startAll: true);
    await Future.wait([
      _loadLine(),
      _loadPies(),
      _loadReal(ctx),
      _loadFore(ctx),
    ]);
    if (mounted && _secs.every((s) => s.error.isEmpty)) PageCache.stamp(_page);
  }

  /// Session + dates, then the procedures start (all at once when [startAll]).
  Future<_CaCtx> _newCtx({bool startAll = false}) async {
    final base = AppConfig.baseUrlOrDefault;
    final body = AppConfig.pointageBody();
    final shared = await Session.load();
    final sid = Session.sidOf(shared);
    if (sid.isEmpty) throw Exception('session not found');

    final hotelToday =
        _parseDmy((shared['dd'] ?? '').toString()) ?? _today;
    final yesterday =
        DateTime(hotelToday.year, hotelToday.month, hotelToday.day - 1);
    // realized period: default (1st of month -> yesterday) unless the user
    // picked his own dates with the two calendars
    final realFrom =
        _realCustom ? _prevStart : DateTime(yesterday.year, yesterday.month, 1);
    final realTo = _realCustom ? _prevEnd : yesterday;

    // forecast period: default (today -> +1 month) unless the user picked
    // his own dates with the two calendars
    final foreFrom = _foreCustom ? _nextStart : hotelToday;
    final foreTo = _foreCustom ? _nextEnd : _plusOneMonth(hotelToday);

    final c = _CaCtx(
      base,
      body,
      sid,
      (shared['codhotelnew'] ?? '').toString(),
      Fmt.dmy(foreFrom), // forecast table: start date ...
      Fmt.dmy(foreTo), // ... -> end date
      Fmt.dmy(realFrom), // realized table: start date ...
      Fmt.dmy(realTo), // ... -> end date
    );
    if (mounted) {
      setState(() {
        _hotelToday = hotelToday;
        _nextStart = foreFrom;
        _nextEnd = foreTo;
        _prevStart = realFrom;
        _prevEnd = realTo;
      });
    }
    if (startAll) {
      c.all; // touch -> both procedures start now, in parallel
    }
    return c;
  }

  /// Reads a session table once its procedure is done. The server answers []
  /// while a procedure is still writing, so empty answers are re-read; if it
  /// stays empty we wait for the OTHER procedure too and read again.
  Future<List<Map<String, dynamic>>> _readTable(
      _CaCtx c, String path, Future<bool> dep, Sec sec, int gen) async {
    bool dead() => !ok(sec, gen);
    await dep;
    if (dead()) return [];
    final url = '${c.base}/hotel/$path/${c.sid}';
    var l = await Loader.listRetry(url, c.body,
        emptyRetries: 3, cancelled: dead);
    if (l.isEmpty && !dead()) {
      await Future.wait(c.all);
      if (dead()) return [];
      l = await Loader.listRetry(url, c.body, emptyRetries: 4, cancelled: dead);
    }
    return l;
  }

  Future<void> _loadReal([Future<_CaCtx>? ctx]) => runSec(_sReal, (gen) async {
        final c = await (ctx ?? _newCtx());
        final rows = await _readTable(c, 'getlistmoiss', c.past, _sReal, gen);
        if (!ok(_sReal, gen)) return;
        setState(() {
          if (rows.isNotEmpty) {
            _realized = rows;
            _rSortCol = null;
            _rPage = 1;
            if (!_realCustom) PageCache.put(_page, 'real', rows);
          }
        });
      });

  Future<void> _loadFore([Future<_CaCtx>? ctx]) => runSec(_sFore, (gen) async {
        final c = await (ctx ?? _newCtx());
        final rows = await _readTable(c, 'getlistmois', c.fwd, _sFore, gen);
        if (!ok(_sFore, gen)) return;
        setState(() {
          if (rows.isNotEmpty) {
            _forecast = rows;
            _fSortCol = null;
            _fPage = 1;
            if (!_foreCustom) PageCache.put(_page, 'fore', rows);
          }
        });
      });

  /// Charts do not depend on the procedures: they start immediately.
  Future<List<Map<String, dynamic>>> _chart(
      String path, Sec sec, int gen) async {
    final base = AppConfig.baseUrlOrDefault;
    return Loader.listRetry('$base/hotel/$path', AppConfig.pointageBody(),
        query: path == 'getchhotel' ? null : {'today': Fmt.dmy(_today)},
        emptyRetries: 1,
        cancelled: () => !ok(sec, gen));
  }

  Future<void> _loadLine() => runSec(_sLine, (gen) async {
        final l = await _chart('getchhotel', _sLine, gen);
        if (!ok(_sLine, gen)) return;
        setState(() {
          if (l.isNotEmpty) {
            final vaKey = _keyOf(l.first, const ['valeur', 'ajout'],
                    exclude: const ['ttc']) ??
                'chiffre';
            final ttcKey = _keyOf(l.first, const ['ttc']);
            debugPrint('CA chart keys: ${l.first.keys.toList()} '
                '-> VA=$vaKey TTC=$ttcKey');
            _lineLabels = l.map((e) => Fmt.dmyAny(e['dat_rev'])).toList();
            _lineValues = l.map((e) => Fmt.toDouble(e[vaKey])).toList();
            _lineTtc = ttcKey == null
                ? []
                : l.map((e) => Fmt.toDouble(e[ttcKey])).toList();
            PageCache.put(_page, 'lineLabels', _lineLabels);
            PageCache.put(_page, 'lineValues', _lineValues);
            PageCache.put(_page, 'lineTtc', _lineTtc);
          }
        });
      });

  /// First key of [row] whose name contains one of [words] (case-insensitive).
  String? _keyOf(Map<String, dynamic> row, List<String> words,
      {List<String> exclude = const []}) {
    for (final k in row.keys) {
      final low = k.toLowerCase();
      if (exclude.any(low.contains)) continue;
      if (words.any(low.contains)) return k;
    }
    return null;
  }

  /// Both pies come from ONE run of the Stat & Revenus procedure + APIs
  /// (month pie = column Mois, year pie = column Année of Total logement /
  /// nourritures / boissons / divers). The procedure can take a while: each
  /// pie shows its own spinner meanwhile.
  Future<void> _loadPies() {
    final g = ++_pieGen;
    final run = StatTotals.fetch(cancelled: () => !mounted || g != _pieGen);
    return Future.wait([
      _fillPie(_sPieM, run, g),
      _fillPie(_sPieY, run, g),
    ]);
  }

  Future<void> _fillPie(
          Sec sec, Future<Map<String, List<double>>> run, int g) =>
      runSec(sec, (gen) async {
        final t = await run;
        if (!ok(sec, gen) || g != _pieGen) return;
        setState(() {
          if (t.isNotEmpty) {
            _totals = t;
            PageCache.put(_page, 'statTotals', t);
          }
        });
      });

  // ------------------------------------------- realized period (calendars)
  DateTime get _yesterday =>
      DateTime(_hotelToday.year, _hotelToday.month, _hotelToday.day - 1);

  DateTime _clamp(DateTime d, DateTime lo, DateTime hi) =>
      d.isBefore(lo) ? lo : (d.isAfter(hi) ? hi : d);

  /// Realized calendar: only days up to YESTERDAY (today and later are
  /// not selectable, there is no realized turnover yet).
  Future<void> _pickReal(bool isStart) async {
    final last = _yesterday;
    final res = await showDatePicker(
      context: context,
      initialDate: _clamp(isStart ? _prevStart : _prevEnd, DateTime(2000), last),
      firstDate: DateTime(2000),
      lastDate: last,
    );
    if (res == null || !mounted) return;
    final d = _clamp(DateTime(res.year, res.month, res.day), DateTime(2000), last);
    setState(() {
      if (isStart) {
        _prevStart = d;
        if (_prevEnd.isBefore(_prevStart)) _prevEnd = _prevStart;
      } else {
        _prevEnd = d;
        if (_prevStart.isAfter(_prevEnd)) _prevStart = _prevEnd;
      }
      _realCustom = true;
      _realized = []; // never show another period's numbers
      _rSortCol = null;
      _rPage = 1;
    });
    _loadReal(); // only the realized table: new dates -> procedure -> table
  }

  /// Forecast calendar: only TODAY and the days after (yesterday and older
  /// are not selectable).
  Future<void> _pickFore(bool isStart) async {
    final first = DateTime(_hotelToday.year, _hotelToday.month, _hotelToday.day);
    final last = DateTime(2100);
    final res = await showDatePicker(
      context: context,
      initialDate: _clamp(isStart ? _nextStart : _nextEnd, first, last),
      firstDate: first,
      lastDate: last,
    );
    if (res == null || !mounted) return;
    final d = _clamp(DateTime(res.year, res.month, res.day), first, last);
    setState(() {
      if (isStart) {
        _nextStart = d;
        if (_nextEnd.isBefore(_nextStart)) _nextEnd = _nextStart;
      } else {
        _nextEnd = d;
        if (_nextStart.isAfter(_nextEnd)) _nextStart = _nextEnd;
      }
      _foreCustom = true;
      _forecast = []; // never show another period's numbers
      _fSortCol = null;
      _fPage = 1;
    });
    _loadFore(); // only the forecast table
  }

  Widget _dateBox(bool isStart, DateTime value, void Function(bool) pick) =>
      Expanded(
        child: OutlinedButton.icon(
          onPressed: () => pick(isStart),
          icon: const Icon(Icons.calendar_month, size: 18),
          label: Text(Fmt.dmy(value)),
        ),
      );

  // ---------------------------------------------------------- sorting
  // col: 0 = agency (A-Z), 1 = C.A, 2 = %CA. Tapping again reverses.
  List<Map<String, dynamic>> _sorted(
      List<Map<String, dynamic>> src, int? col, bool asc) {
    if (col == null) return src;
    final l = [...src];
    int cmp(Map<String, dynamic> a, Map<String, dynamic> b) {
      switch (col) {
        case 0:
          return '${a['lib_agence'] ?? ''}'
              .toLowerCase()
              .compareTo('${b['lib_agence'] ?? ''}'.toLowerCase());
        case 1:
          return Fmt.toDouble(a['prix']).compareTo(Fmt.toDouble(b['prix']));
        default:
          return Fmt.toDouble(a['prix']).compareTo(Fmt.toDouble(b['prix']));
      }
    }

    l.sort((a, b) => asc ? cmp(a, b) : cmp(b, a));
    return l;
  }

  /// Percentages of [values] over their sum, rounded to 2 decimals, whose
  /// total is exactly 100.00 (the missing/extra hundredths go to the largest
  /// remainders). Example: 6554 / 145222 -> 4.51.
  static List<double> _percents(List<double> values) {
    final total = values.fold<double>(0, (a, v) => a + v);
    if (values.isEmpty || total == 0) return List.filled(values.length, 0);
    final raw = [for (final v in values) v / total * 10000]; // hundredths
    final units = [for (final r in raw) r.floor()];
    var left = 10000 - units.fold<int>(0, (a, u) => a + u);
    final order = List<int>.generate(values.length, (i) => i)
      ..sort((a, b) => (raw[b] - units[b]).compareTo(raw[a] - units[a]));
    for (var k = 0; left > 0; k++, left--) {
      units[order[k % order.length]]++;
    }
    return [for (final u in units) u / 100];
  }

  // --------------------------------------------------------------- UI
  Widget _agencyTable({
    required String title,
    required DateTime from,
    required DateTime to,
    required List<Map<String, dynamic>> rows,
    required Sec sec,
    required VoidCallback onRefresh,
    required int? sortCol,
    required bool asc,
    required ValueChanged<int> onSort,
    required int page,
    required ValueChanged<int> onPage,
    Widget? picker,
  }) {
    final shown = _sorted(rows, sortCol, asc)
        .where((m) => '${m['lib_agence']}' != '0')
        .toList();
    // %CA = C.A of the agency / total C.A, 2 decimals, and the column adds up
    // to EXACTLY 100.00 (largest-remainder rounding).
    final total = shown.fold<double>(0, (a, m) => a + Fmt.toDouble(m['prix']));
    final pct = _percents([for (final m in shown) Fmt.toDouble(m['prix'])]);
    Widget b(String s) =>
        Text(s, style: const TextStyle(fontWeight: FontWeight.w800));
    final totalPages = max(1, (shown.length / _perPage).ceil());
    final cur = page > totalPages ? totalPages : page;
    final start = (cur - 1) * _perPage;
    final end = min(start + _perPage, shown.length);

    return Column(children: [
      SecTitle(title, sec: sec, onRefresh: onRefresh),
      Center(
        child: Text.rich(
          TextSpan(children: [
            TextSpan(text: '${_t('Période du', 'Period from')}: '),
            TextSpan(
                text: Fmt.dmy(from),
                style: const TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(text: ' ${_t('au', 'to')} '),
            TextSpan(
                text: Fmt.dmy(to),
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ]),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: R.fluid(context, 0.75, 2, 0.95)),
        ),
      ),
      if (picker != null) ...[const SizedBox(height: 8), picker],
      const SizedBox(height: 10),
      SecCard(
        sec: sec,
        hasData: rows.isNotEmpty,
        onRetry: onRefresh,
        child: rows.isEmpty
            ? EmptyChart(_t('Aucune donnée', 'No data'), height: 80)
            : Column(children: [
                FluidTable(
                headers: [
                  _t('Agence', 'Agency'),
                  _t('C.A', 'Turnover'),
                  _t('%CA', '% Turnover'),
                ],
                flex: const [2.2, 1.4, 1],
                rightCols: const {1, 2},
                onHeaderTap: onSort,
                sortColumn: sortCol,
                sortAscending: asc,
                rows: [
                  for (var i = start; i < end; i++)
                    [
                      Text('${shown[i]['lib_agence'] ?? ''}'),
                      Text(Fmt.thousands(shown[i]['prix'])),
                      Text('${pct[i].toStringAsFixed(2)}%'),
                    ],
                  [
                    b(_t('Total', 'Total')),
                    b(Fmt.thousands(total)),
                    b(total == 0 ? '0.00%' : '100.00%'),
                  ],
                ],
              ),
                if (totalPages > 1) ...[
                  const SizedBox(height: 10),
                  PageBar(page: cur, total: totalPages, onPage: onPage),
                ],
              ]),
      ),
    ]);
  }

  Widget _pieCard(String title, List<PieEntry> entries, Sec sec,
          VoidCallback onRefresh) =>
      Column(children: [
        SecTitle(title, sec: sec, onRefresh: onRefresh),
        SecCard(
          sec: sec,
          hasData: entries.isNotEmpty,
          onRetry: onRefresh,
          child: PieLegendChart(
            entries: entries,
            emptyText: _t('Aucune donnée', 'No data'),
          ),
        ),
      ]);

  @override
  Widget build(BuildContext context) {
    final wide = R.width(context) >= 768;
    final pieM = _pieCard(
        _t("Chiffre d'Affaire Global - Cumul du Mois",
            'Global Turnover - Monthly Cumulative'),
        _pieMonth,
        _sPieM,
        _loadPies);
    final pieY = _pieCard(
        _t("Chiffre d'Affaire Global - Cumul de l'Année",
            'Global Turnover - Yearly Cumulative'),
        _pieYear,
        _sPieY,
        _loadPies);

    return Scaffold(
      appBar: xliaAppBar(
        context,
        title: _t("Chiffre d'Affaire", 'Turnover'),
        date: DateFormat('dd/MM/yyyy').format(DateTime.now()),
        loading: _anyLoading,
        onRefresh: _loadAll,
        onMenu: widget.onMenu,
      ),
      body: RefreshIndicator(
        onRefresh: _loadAll,
        child: ResponsivePage(
          children: [
            if (_error.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(_error, style: const TextStyle(color: Colors.red)),
              ),

            // ---- realized turnover (line)
            SecTitle(_t("Chiffre d'Affaire Réalisé", 'Realized Turnover'),
                sec: _sLine, onRefresh: _loadLine),
            SecCard(
              sec: _sLine,
              hasData: _lineValues.isNotEmpty,
              onRetry: _loadLine,
              minHeight: 280,
              child: LineSeriesChart(
                height: 280,
                filled: true,
                emptyText: _t('Aucune donnée', 'No data'),
                labels: _lineLabels,
                series: [
                  ChartSeries(_t('Valeur ajoutée', 'Added value'), _lineValues,
                      _teal),
                  if (_lineTtc.isNotEmpty)
                    ChartSeries('TTC', _lineTtc, const Color(0xFFFF9F40)),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ---- realized by agency (previous month)
            _agencyTable(
              title: _t("Chiffre d'Affaire Réalisé par Agence",
                  'Realized Turnover by Agency'),
              from: _prevStart,
              to: _prevEnd,
              rows: _realized,
              sec: _sReal,
              onRefresh: _loadReal,
              picker: Row(children: [
                _dateBox(true, _prevStart, _pickReal),
                const SizedBox(width: 10),
                _dateBox(false, _prevEnd, _pickReal),
              ]),
              sortCol: _rSortCol,
              asc: _rAsc,
              page: _rPage,
              onPage: (p) => setState(() => _rPage = p),
              onSort: (c) => setState(() {
                _rAsc = _rSortCol == c ? !_rAsc : true;
                _rSortCol = c;
                _rPage = 1;
              }),
            ),
            const SizedBox(height: 20),

            // ---- pies
            if (wide)
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: pieM),
                const SizedBox(width: 12),
                Expanded(child: pieY),
              ])
            else ...[
              pieM,
              const SizedBox(height: 20),
              pieY,
            ],
            const SizedBox(height: 20),

            // ---- forecast by agency (next month)
            _agencyTable(
              title: _t("Chiffre d'Affaire Prévisionnel par Agence",
                  'Forecasted Turnover by Agency'),
              from: _nextStart,
              to: _nextEnd,
              rows: _forecast,
              sec: _sFore,
              onRefresh: _loadFore,
              picker: Row(children: [
                _dateBox(true, _nextStart, _pickFore),
                const SizedBox(width: 10),
                _dateBox(false, _nextEnd, _pickFore),
              ]),
              sortCol: _fSortCol,
              asc: _fAsc,
              page: _fPage,
              onPage: (p) => setState(() => _fPage = p),
              onSort: (c) => setState(() {
                _fAsc = _fSortCol == c ? !_fAsc : true;
                _fSortCol = c;
                _fPage = 1;
              }),
            ),
            const SizedBox(height: 20),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
