import 'dart:async';
import 'dart:convert';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/api_client.dart';
import '../core/app_config.dart';
import '../core/charts.dart';
import '../core/fmt.dart';
import '../core/lang.dart';
import '../core/loader.dart';
import '../core/prefs.dart';
import '../core/responsive.dart';
import '../core/section.dart';
import '../core/session.dart';

/// Port of HelpPage ("Prévisions", route /menu/help).
///
/// Flow (same as the Ionic page):
///   1. POST /hotel/GetDataproce                       -> session + dates
///   2. procedures (parallel): getInfo_planning_apk, generer_prevision_comparee,
///      prevision_mensuelle, generer_prev_categ_Mobile
///   3. data (parallel): getOccupationPaxDetailsPrev/{sid},
///      getOccupationDetailsPrev/{sid}, getCompare/{sid}, getCompare1/{sid}
///   4. pie: getchambredispo1 ; tap a slice -> getprevcateg (details bar chart)
class PrevisionsScreen extends StatefulWidget {
  final VoidCallback? onMenu;
  const PrevisionsScreen({super.key, this.onMenu});

  @override
  State<PrevisionsScreen> createState() => _PrevisionsScreenState();
}

/// Everything the sections share for one load: session id, dates and the
/// heavy Oracle procedures. Each procedure starts lazily and runs ONCE per
/// load, whichever sections wait for it.
class _PrevCtx {
  final String base, sid, cod, dd, tom, six, tomm, anComp;
  final Map<String, dynamic> body;
  _PrevCtx(this.base, this.body, this.sid, this.cod, this.dd, this.tom,
      this.six, this.tomm, this.anComp);

  Future<bool> _p(String path, Map<String, String> q) =>
      Loader.procedure('$base/hotel/$path', body, q);

  // fills the table read by getchambredispo1 (categories pie)
  late final Future<bool> cat =
      _p('categ_dispo_mobile', {'codhotel': cod, 'session_id_': sid});
  // weekly rooms / pax tables
  late final Future<bool> plan = _p('getInfo_planning_apk',
      {'cod_hotel_New': cod, 'd1': dd, 'session_id_': sid});
  // compared forecast (+ A-1 columns)
  late final Future<bool> comp = _p('generer_prevision_comparee', {
    'd1': tom, 'd2': six, 'AnComp_': anComp,
    'offre_': '', 'session_': sid, 'cod_hotel_': cod,
  });
  late final Future<bool> mens = _p('prevision_mensuelle',
      {'AnComp_': anComp, 'offre_': '', 'session_': sid, 'cod_hotel_': cod});
  // category details (tap on a pie slice)
  late final Future<bool> det = _p('generer_prev_categ_Mobile', {
    'd1': tom, 'd2': tomm, 'offre_': '', 'cod_agence_': '',
    'session_': sid, 'cod_hotel_': cod,
  });
  List<Future<bool>> get all => [cat, plan, comp, mens, det];
}

class _PrevisionsScreenState extends State<PrevisionsScreen>
    with WidgetsBindingObserver, SecLoader<PrevisionsScreen> {
  static const _orange = Color(0xFFFFA500);
  static const _blue = Color(0xFF2F88C2);
  static const _defaultColors = [
    Color(0xFFFF6384), Color(0xFF36A2EB), Color(0xFFFFCE56), Color(0xFF4BC0C0),
    Color(0xFF9966FF), Color(0xFFFF9F40), Color(0xFFFF8A80), Color(0xFF80D8FF),
    Color(0xFFA5D6A7), Color(0xFFFFD54F),
  ];

  static const _page = 'prev';

  // one loading state per table / chart
  final Sec _sCats = Sec(), _sRooms = Sec(), _sPax = Sec();
  final Sec _sCmp = Sec(), _sCmp1 = Sec();
  List<Sec> get _secs => [_sCats, _sRooms, _sPax, _sCmp, _sCmp1];
  bool get _anyLoading => _secs.any((x) => x.loading);

  String _error = '';
  Timer? _timer;
  Future<_PrevCtx>? _ctxF; // procedures of the current load (details wait on it)

  // tables
  List<Map<String, dynamic>> _rooms = []; // getOccupationDetailsPrev
  List<Map<String, dynamic>> _pax = []; // getOccupationPaxDetailsPrev
  List<Map<String, dynamic>> _cmp = []; // getCompare   (A-1 lookup by day)
  List<Map<String, dynamic>> _cmp1 = []; // getCompare1  (compared forecast)
  Map<String, Map<String, dynamic>> _cmpByDay = {};

  // totals of the compared table
  double _tPax = 0, _tPax1 = 0, _tEPax = 0, _tChb = 0, _tChb1 = 0, _tEChb = 0;

  // category pie + details
  List<PieEntry> _cats = [];
  String? _detailCode;
  Color _detailColor = _orange;
  List<String> _detailLabels = [];
  List<double> _detailValues = [];
  bool _detailLoading = false;

  bool get _fr => isFr;
  String _t(String fr, String en) => tr(fr, en);

  @override
  void initState() {
    super.initState();
    AppLang.lang.addListener(_onLang);
    WidgetsBinding.instance.addObserver(this);
    _restore();
    // Fresh data (< 3 min) is shown as is; otherwise the cached numbers stay
    // visible while every section refreshes by itself.
    if (!PageCache.fresh(_page)) _loadAll();
    // background refresh every 10 minutes (like the Ionic interval)
    _timer = Timer.periodic(const Duration(minutes: 10), (_) {
      if (mounted && !_anyLoading) _loadAll();
    });
  }

  void _onLang() {
    if (mounted) setState(() {});
  }

  /// Coming back to the app (after the phone slept / network changed):
  /// reload automatically, no manual refresh needed.
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
    for (final x in _secs) {
      x.gen++; // drop every running answer
    }
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    AppLang.lang.removeListener(_onLang);
    super.dispose();
  }

  // ------------------------------------------------------------ cache
  void _applyRooms(List<Map<String, dynamic>> l) => _rooms = l;
  void _applyPax(List<Map<String, dynamic>> l) => _pax = l;
  void _applyCmp(List<Map<String, dynamic>> l) {
    _cmp = l;
    _cmpByDay = {for (final m in l) '${m['jour']}': m};
  }

  double _sum(List<Map<String, dynamic>> l, String k) =>
      l.fold<double>(0, (a, e) => a + Fmt.toDouble(e[k]));

  void _applyCmp1(List<Map<String, dynamic>> l) {
    _cmp1 = l;
    _tPax = _sum(l, 'pax');
    _tPax1 = _sum(l, 'pax1');
    _tEPax = _sum(l, 'epax');
    _tChb = _sum(l, 'chb');
    _tChb1 = _sum(l, 'chb1');
    _tEChb = _sum(l, 'echb');
  }

  void _restore() {
    final r = PageCache.get<List<Map<String, dynamic>>>(_page, 'rooms');
    if (r != null) {
      _applyRooms(r);
      _sRooms.loaded = true;
    }
    final p = PageCache.get<List<Map<String, dynamic>>>(_page, 'pax');
    if (p != null) {
      _applyPax(p);
      _sPax.loaded = true;
    }
    final c = PageCache.get<List<Map<String, dynamic>>>(_page, 'cmp');
    if (c != null) {
      _applyCmp(c);
      _sCmp.loaded = true;
    }
    final c1 = PageCache.get<List<Map<String, dynamic>>>(_page, 'cmp1');
    if (c1 != null) {
      _applyCmp1(c1);
      _sCmp1.loaded = true;
    }
    final k = PageCache.get<List<PieEntry>>(_page, 'cats');
    if (k != null) {
      _cats = k;
      _sCats.loaded = true;
    }
  }

  // ------------------------------------------------------------- data
  /// Whole page: every section starts at the same time and shows its data AS
  /// SOON AS IT ARRIVES (each one waits only for ITS OWN procedure).
  Future<void> _loadAll() async {
    if ((AppConfig.pointageBody()['url'] as String).isEmpty) {
      setState(() => _error =
          'URL de base de données manquante. Vérifiez la configuration.');
      return;
    }
    setState(() => _error = '');
    final ctx = _newCtx(startAll: true);
    _ctxF = ctx;
    await Future.wait([
      _loadCats(ctx),
      _loadRooms(ctx),
      _loadPax(ctx),
      _loadCmp(ctx),
      _loadCmp1(ctx),
    ]);
    if (mounted && _secs.every((x) => x.error.isEmpty)) PageCache.stamp(_page);
  }

  /// Session + dates, then the heavy procedures start (all at once when
  /// [startAll]; otherwise only the ones a refreshed section asks for).
  Future<_PrevCtx> _newCtx({bool startAll = false}) async {
    final base = AppConfig.baseUrlOrDefault;
    final body = AppConfig.pointageBody();
    final shared = await Session.load();
    final sid = Session.sidOf(shared);
    if (sid.isEmpty) throw Exception('session not found');

    final now = DateTime.now();
    String pick(String key, DateTime fallback) {
      final v = shared[key];
      return (v != null && v.toString().isNotEmpty)
          ? v.toString()
          : Fmt.apiDate(fallback);
    }

    final c = _PrevCtx(
      base,
      body,
      sid,
      (shared['codhotelnew'] ??
              shared['cod_hotel'] ??
              Prefs.getString('cod_hotel', '02'))
          .toString(),
      pick('dd', now),
      pick('tom', now.add(const Duration(days: 1))),
      pick('six', now.add(const Duration(days: 6))),
      pick('tomm', now.add(const Duration(days: 6))),
      (shared['anncom'] ?? shared['AnComp_'] ?? (now.year - 1)).toString(),
    );
    if (startAll) {
      c.all; // touch -> every procedure starts now, in parallel
    }
    return c;
  }

  /// Reads a session table once ITS procedures are done. The server answers []
  /// while a procedure is still writing, so empty answers are re-read; if it
  /// stays empty we wait for ALL procedures and read again.
  Future<List<Map<String, dynamic>>> _readTable(_PrevCtx c, String path,
      List<Future<bool>> deps, Sec sec, int gen) async {
    bool dead() => !ok(sec, gen);
    await Future.wait(deps);
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

  Map<String, dynamic> _withDay(Map<String, dynamic> m) =>
      {...m, 'jour': Fmt.dmyAny(m['jour'])};

  Future<void> _loadRooms([Future<_PrevCtx>? ctx]) =>
      runSec(_sRooms, (gen) async {
        final c = await (ctx ?? _newCtx());
        final l = await _readTable(
            c, 'getOccupationDetailsPrev', [c.plan], _sRooms, gen);
        if (!ok(_sRooms, gen)) return;
        setState(() {
          if (l.isNotEmpty) {
            _applyRooms(l
                .map((m) => {
                      ..._withDay(m),
                      'taux_chb': Fmt.toDouble(m['taux_chb']).toStringAsFixed(2),
                    })
                .toList());
            PageCache.put(_page, 'rooms', _rooms);
          }
        });
      });

  Future<void> _loadPax([Future<_PrevCtx>? ctx]) => runSec(_sPax, (gen) async {
        final c = await (ctx ?? _newCtx());
        final l = await _readTable(
            c, 'getOccupationPaxDetailsPrev', [c.plan], _sPax, gen);
        if (!ok(_sPax, gen)) return;
        setState(() {
          if (l.isNotEmpty) {
            _applyPax(l
                .map((m) => {
                      ..._withDay(m),
                      'taux_pax': Fmt.toDouble(m['taux_pax']).toStringAsFixed(2),
                    })
                .toList());
            PageCache.put(_page, 'pax', _pax);
          }
        });
      });

  Future<void> _loadCmp([Future<_PrevCtx>? ctx]) => runSec(_sCmp, (gen) async {
        final c = await (ctx ?? _newCtx());
        final l = await _readTable(
            c, 'getCompare', [c.comp, c.mens], _sCmp, gen);
        if (!ok(_sCmp, gen)) return;
        setState(() {
          if (l.isNotEmpty) {
            _applyCmp(l.map(_withDay).toList());
            PageCache.put(_page, 'cmp', _cmp);
          }
        });
      });

  Future<void> _loadCmp1([Future<_PrevCtx>? ctx]) =>
      runSec(_sCmp1, (gen) async {
        final c = await (ctx ?? _newCtx());
        final l = await _readTable(
            c, 'getCompare1', [c.comp, c.mens], _sCmp1, gen);
        if (!ok(_sCmp1, gen)) return;
        setState(() {
          if (l.isNotEmpty) {
            _applyCmp1(l.map(_withDay).toList());
            PageCache.put(_page, 'cmp1', _cmp1);
          }
        });
      });

  Future<void> _loadCats([Future<_PrevCtx>? ctx]) =>
      runSec(_sCats, (gen) async {
        final c = await (ctx ?? _newCtx());
        bool dead() => !ok(_sCats, gen);
        // colors are fetched while the procedure is still running
        final colorsF = _loadColors(c.base, c.body);
        await c.cat;
        if (dead()) return;
        final colors = await colorsF;
        if (dead()) return;
        var data = await _readCats(c, dead);
        if (data.isEmpty && !dead()) {
          await Future.wait(c.all);
          if (dead()) return;
          data = await _readCats(c, dead);
        }
        if (dead()) return;
        final total = data.fold<double>(0, (a, e) => a + Fmt.toDouble(e['nbr']));
        final entries = <PieEntry>[];
        for (var i = 0; i < data.length; i++) {
          final code = (data[i]['cod_categ'] ?? '').toString();
          final nbr = Fmt.toDouble(data[i]['nbr']);
          final pct = total > 0 ? nbr / total * 100 : 0.0;
          final fallback = _defaultColors[i % _defaultColors.length];
          final color = (colors[code] ?? '').isNotEmpty
              ? Fmt.hex(colors[code], fallback: fallback)
              : fallback;
          entries.add(PieEntry(code, '$code (${pct.toStringAsFixed(2)}%)', nbr, color));
        }
        setState(() {
          if (entries.isNotEmpty) {
            _cats = entries;
            PageCache.put(_page, 'cats', entries);
          }
        });
      });

  /// getchambredispo1 is bound to the session id (the Ionic page forgot it).
  /// The plain call is kept as a last resort.
  Future<List<Map<String, dynamic>>> _readCats(
      _PrevCtx c, bool Function() dead) async {
    var data = await Loader.listRetry('${c.base}/hotel/getchambredispo1', c.body,
        query: {'session_id_': c.sid}, emptyRetries: 3, cancelled: dead);
    if (data.isEmpty && !dead()) {
      data = await Loader.listRetry('${c.base}/hotel/getchambredispo1', c.body,
          emptyRetries: 1, cancelled: dead);
    }
    return data;
  }

  /// Category colors: saved by Etat Hotel, fetched here if Prévisions is opened first.
  Future<Map<String, String>> _loadColors(
      String base, Map<String, dynamic> body) async {
    Map<String, String> colors = {};
    try {
      final raw = Prefs.getString('colorMap');
      if (raw.isNotEmpty) {
        colors = (jsonDecode(raw) as Map)
            .map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''));
      }
    } catch (_) {}
    if (colors.isEmpty) {
      try {
        final res = await Api.post('$base/hotel/getcolor', body);
        for (final item in Api.asList(res)) {
          dynamic c = item['color'];
          try {
            final p = jsonDecode(c.toString());
            c = p is Map ? p['color'] : p;
          } catch (_) {}
          colors[(item['cod_categ'] ?? '').toString()] = (c ?? '').toString();
        }
        await Prefs.setString('colorMap', jsonEncode(colors));
      } catch (_) {}
    }
    return colors;
  }

  DateTime _parseApiDate(String s) {
    try {
      final part = s.split(RegExp(r'[ T]')).first.split('-');
      return DateTime(int.parse(part[0]), int.parse(part[1]), int.parse(part[2]));
    } catch (_) {
      return DateTime.tryParse(s) ?? DateTime.now();
    }
  }

  /// Tap on a category -> getprevcateg -> bar chart of the remaining rooms.
  Future<void> _openDetails(int index) async {
    if (index < 0 || index >= _cats.length || _detailLoading) return;
    final entry = _cats[index];
    setState(() => _detailLoading = true);
    try {
      // the details table is filled by generer_prev_categ_Mobile
      final cf = _ctxF;
      if (cf != null) {
        try {
          await (await cf).det;
        } catch (_) {}
      }
      final data = Api.asList(await Api.post(
          '${AppConfig.baseUrlOrDefault}/hotel/getprevcateg',
          AppConfig.pointageBody()));
      bool same(Map<String, dynamic> m) =>
          '${m['cod_CATEG'] ?? m['cod_categ'] ?? ''}'.trim() == entry.code;
      final rows = data.where(same).toList();
      if (rows.isEmpty) {
        if (mounted) {
          setState(() {
            _detailCode = null;
            _detailLoading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(_t('Aucun détail pour ${entry.code}',
                  'No details for ${entry.code}'))));
        }
        return;
      }
      final dates = <String, DateTime>{};
      for (final m in rows) {
        if (m['jour'] != null) {
          final d = _parseApiDate(m['jour'].toString());
          dates['${d.year}-${d.month}-${d.day}'] = d;
        }
      }
      var uniq = dates.values.toList()..sort();
      if (uniq.length > 6) uniq = uniq.sublist(0, 6);
      final labels = uniq.map((d) => DateFormat('dd/MM').format(d)).toList();
      final values = uniq.map((d) {
        final m = rows.firstWhere(
            (x) => x['jour'] != null && _parseApiDate(x['jour'].toString()) == d,
            orElse: () => const {});
        return Fmt.toDouble(m['rest']);
      }).toList();
      if (!mounted) return;
      setState(() {
        _detailCode = entry.code;
        _detailColor = entry.color;
        _detailLabels = labels;
        _detailValues = values;
        _detailLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _detailLoading = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_t('Erreur de chargement', 'Loading error'))));
      }
    }
  }

  // --------------------------------------------------------------- UI
  Widget _bold(dynamic v) =>
      Text(Fmt.n(v), style: const TextStyle(fontWeight: FontWeight.w700));

  Widget _a1(dynamic v) => Text(Fmt.n(v),
      style: const TextStyle(color: _blue, fontWeight: FontWeight.w600));

  Widget _occupationTable({
    required List<Map<String, dynamic>> rows,
    required String valueHeader,
    required String dep,
    required String arr,
    required String value,
    required String rate,
    required String a1Key,
  }) {
    return FluidTable(
      headers: [
        _t('Journée', 'Day'),
        _t('Départ', 'Departure'),
        _t('Arrivée', 'Arrival'),
        valueHeader,
        _t('% T.O', '% Occupancy'),
        _t('A-1', 'Prev. Year'),
      ],
      flex: const [1.5, 1, 1, 1, 1, 1],
      rows: [
        for (final r in rows)
          [
            Text('${r['jour']}'),
            Text(Fmt.n(r[dep])),
            Text(Fmt.n(r[arr])),
            _bold(r[value]),
            Text('${Fmt.n(double.tryParse('${r[rate]}') ?? 0)}%'),
            _sCmp.loading && _cmpByDay.isEmpty
                ? const Text('…', style: TextStyle(color: _blue))
                : _a1(_cmpByDay['${r['jour']}']?[a1Key]),
          ],
      ],
    );
  }

  Widget _comparedTable() {
    Widget b(dynamic v) =>
        Text(Fmt.n(v), style: const TextStyle(fontWeight: FontWeight.w800));
    Widget bp(dynamic v) => Text('${Fmt.n(v)}%',
        style: const TextStyle(fontWeight: FontWeight.w800));
    return FluidTable(
      headers: [
        _t('Journée', 'Day'),
        _t('Pax', 'Pax'),
        _t('A-1', 'Prev. Year'),
        _t('Écart %', 'Gap %'),
        _t('Chambre', 'Rooms'),
        _t('A-1', 'Prev. Year'),
        _t('Écart %', 'Gap %'),
      ],
      flex: const [1.5, 1, 1, 1, 1, 1, 1],
      rows: [
        for (final r in _cmp1)
          [
            Text('${r['jour']}'),
            _bold(r['pax']),
            _a1(r['pax1']),
            Text('${Fmt.n(r['epax'])}%'),
            _bold(r['chb']),
            _a1(r['chb1']),
            Text('${Fmt.n(r['echb'])}%'),
          ],
        if (_cmp1.isNotEmpty)
          [
            b(_t('Total', 'Total')),
            b(_tPax),
            b(_tPax1),
            bp(_tEPax),
            b(_tChb),
            b(_tChb1),
            bp(_tEChb),
          ],
      ],
    );
  }

  Widget _detailsCard() {
    final fs = R.fluid(context, 0.6, 1.8, 0.8);
    var maxY = _detailValues.fold<double>(0, (a, v) => v > a ? v : a);
    maxY = maxY <= 0 ? 10 : (maxY * 1.2).ceilToDouble();
    return AppCard(
      child: Column(children: [
        Row(children: [
          Expanded(
            child: Text(
              '${_t('Détails par Catégorie', 'Details by Category')} — $_detailCode',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close),
            onPressed: () => setState(() => _detailCode = null),
          ),
        ]),
        SizedBox(
          height: 220,
          child: BarChart(BarChartData(
            maxY: maxY,
            alignment: BarChartAlignment.spaceAround,
            borderData: FlBorderData(show: false),
            gridData: const FlGridData(show: true, drawVerticalLine: false),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                getTitlesWidget: (v, m) =>
                    Text(v.toInt().toString(), style: TextStyle(fontSize: fs)),
              )),
              bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 26,
                getTitlesWidget: (v, m) {
                  final i = v.toInt();
                  if (i < 0 || i >= _detailLabels.length) return const SizedBox();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(_detailLabels[i], style: TextStyle(fontSize: fs)),
                  );
                },
              )),
            ),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipItem: (group, gi, rod, ri) => BarTooltipItem(
                    '${rod.toY.toInt()} Rest',
                    const TextStyle(color: Colors.white, fontSize: 12)),
              ),
            ),
            barGroups: [
              for (var i = 0; i < _detailValues.length; i++)
                BarChartGroupData(x: i, barRods: [
                  BarChartRodData(
                    toY: _detailValues[i],
                    width: 22,
                    color: _detailColor,
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(4)),
                  ),
                ]),
            ],
          )),
        ),
        const SizedBox(height: 6),
        LegendDot(_detailColor, '$_detailCode - ${_t('Prévisions', 'Forecast')}'),
      ]),
    );
  }

  /// Table + chart of the SAME source: each one is its own card with its own
  /// loading bar, and both refresh together.
  Widget _tableCard(Sec sec, bool hasData, VoidCallback retry, Widget table,
          Widget chart) =>
      Column(children: [
        SecCard(sec: sec, hasData: hasData, onRetry: retry, child: table),
        const SizedBox(height: 12),
        SecCard(
            sec: sec,
            hasData: hasData,
            onRetry: retry,
            minHeight: 220,
            child: chart),
      ]);

  @override
  Widget build(BuildContext context) {
    final noData = _t('Aucune donnée', 'No data');
    final paxLabels = _pax.map((e) => '${e['jour']}').toList();
    final roomLabels = _rooms.map((e) => '${e['jour']}').toList();
    final cmpLabels = _cmp1.map((e) => '${e['jour']}').toList();
    final a1 = _t('A-1', 'Prev. Year');

    final paxChart = LineSeriesChart(
      emptyText: noData,
      filled: true,
      labels: paxLabels,
      series: [
        ChartSeries('Pax', _pax.map((e) => Fmt.toDouble(e['pax'])).toList(), _orange),
        if (_cmpByDay.isNotEmpty)
          ChartSeries('$a1 Pax',
              _pax.map((e) => Fmt.toDouble(_cmpByDay['${e['jour']}']?['pax1'])).toList(), _blue),
      ],
    );
    final roomChart = LineSeriesChart(
      emptyText: noData,
      filled: true,
      labels: roomLabels,
      series: [
        ChartSeries(_t('Chambre', 'Rooms'),
            _rooms.map((e) => Fmt.toDouble(e['chb'])).toList(), _orange),
        if (_cmpByDay.isNotEmpty)
          ChartSeries('$a1 ${_t('Chambre', 'Rooms')}',
              _rooms.map((e) => Fmt.toDouble(_cmpByDay['${e['jour']}']?['chb1'])).toList(), _blue),
      ],
    );
    final cmpPaxChart = SecCard(
      sec: _sCmp1,
      hasData: _cmp1.isNotEmpty,
      onRetry: _loadCmp1,
      minHeight: 220,
      child: Column(children: [
        Text(_t('Prévision Comparée par Pax', 'Compared Pax Forecast'),
            style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        LineSeriesChart(
          emptyText: noData,
          curved: false,
          labels: cmpLabels,
          series: [
            ChartSeries('Pax', _cmp1.map((e) => Fmt.toDouble(e['pax'])).toList(), _orange),
            ChartSeries(a1, _cmp1.map((e) => Fmt.toDouble(e['pax1'])).toList(), _blue),
          ],
        ),
      ]),
    );
    final cmpRoomChart = SecCard(
      sec: _sCmp1,
      hasData: _cmp1.isNotEmpty,
      onRetry: _loadCmp1,
      minHeight: 220,
      child: Column(children: [
        Text(_t('Prévision Comparée par Chambre', 'Compared Room Forecast'),
            style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        LineSeriesChart(
          emptyText: noData,
          curved: false,
          labels: cmpLabels,
          series: [
            ChartSeries(_t('Chambre', 'Rooms'),
                _cmp1.map((e) => Fmt.toDouble(e['chb'])).toList(), _orange),
            ChartSeries(a1, _cmp1.map((e) => Fmt.toDouble(e['chb1'])).toList(), _blue),
          ],
        ),
      ]),
    );

    return Scaffold(
      appBar: xliaAppBar(
        context,
        title: _t('Prévisions', 'Forecasts'),
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

            // ---- categories
            SecTitle(_t('Catégories Disponibles', 'Available Categories'),
                sec: _sCats, onRefresh: _loadCats),
            SecCard(
              sec: _sCats,
              hasData: _cats.isNotEmpty,
              onRetry: _loadCats,
              child: PieLegendChart(
                entries: _cats,
                emptyText: noData,
                onTap: _openDetails,
              ),
            ),
            if (_detailLoading)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (_detailCode != null) ...[
              const SizedBox(height: 12),
              _detailsCard(),
            ],

            // ---- weekly rooms
            SecTitle(_t("Prévisions d'une semaine par Chambre",
                'Weekly Room Forecast'),
                sec: _sRooms, onRefresh: _loadRooms),
            _tableCard(
              _sRooms,
              _rooms.isNotEmpty,
              _loadRooms,
              _occupationTable(
                rows: _rooms,
                valueHeader: _t('Chambre', 'Rooms'),
                dep: 'dep_chb',
                arr: 'arr_chb',
                value: 'chb',
                rate: 'taux_chb',
                a1Key: 'chb1',
              ),
              roomChart,
            ),

            // ---- weekly pax
            SecTitle(_t("Prévisions d'une semaine par Pax", 'Weekly Pax Forecast'),
                sec: _sPax, onRefresh: _loadPax),
            _tableCard(
              _sPax,
              _pax.isNotEmpty,
              _loadPax,
              _occupationTable(
                rows: _pax,
                valueHeader: 'Pax',
                dep: 'dep_pax',
                arr: 'arr_pax',
                value: 'pax',
                rate: 'taux_pax',
                a1Key: 'pax1',
              ),
              paxChart,
            ),

            // ---- compared forecast
            SecTitle(_t('Prévision Comparée', 'Compared Forecast'),
                sec: _sCmp1, onRefresh: _loadCmp1),
            SecCard(
              sec: _sCmp1,
              hasData: _cmp1.isNotEmpty,
              onRetry: _loadCmp1,
              child: _comparedTable(),
            ),
            const SizedBox(height: 12),
            if (R.width(context) >= 768)
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: cmpPaxChart),
                const SizedBox(width: 12),
                Expanded(child: cmpRoomChart),
              ])
            else ...[
              cmpPaxChart,
              const SizedBox(height: 12),
              cmpRoomChart,
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
