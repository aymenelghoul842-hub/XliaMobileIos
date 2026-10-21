import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/api_client.dart';
import '../core/app_config.dart';
import '../core/charts.dart';
import '../core/fmt.dart';
import '../core/lang.dart';
import '../core/responsive.dart';
import '../core/section.dart';
import '../core/session.dart';
import 'deteilrecap_screen.dart';

/// Port of RecaptilatifPage ("PV" / Points de vente, route /menu/recaptilatif).
///
/// Flow (same as the Ionic page):
///   1. POST /hotel/PV_LIST_AR?p_startDate&p_endDate&session_id_   (procedure)
///   2. POST /hotel/getlistpv/{sid}      -> table + "points de vente" chart
///   3. POST /hotel/getmaxarticle/{sid}  -> top 3 articles chart
/// Tap a row -> [DeteilRecapScreen].
class PvScreen extends StatefulWidget {
  final VoidCallback? onMenu;
  const PvScreen({super.key, this.onMenu});

  @override
  State<PvScreen> createState() => _PvScreenState();
}

class _PvScreenState extends State<PvScreen> with SecLoader {
  final Sec _sRows = Sec(); // points of sale table + sales-point chart
  final Sec _sArt = Sec(); // top articles chart
  List<Sec> get _secs => [_sRows, _sArt];
  bool get _anyLoading => _secs.any((s) => s.loading);

  String _error = ''; // configuration problem only
  bool _procFailed = false;

  late DateTime _start;
  late DateTime _end;

  List<Map<String, dynamic>> _rows = [];
  List<Map<String, dynamic>> _artTop = []; // top 3 articles

  // totals are computed from the rows (also right after a cache restore)
  double _sum(String k) =>
      _rows.fold<double>(0, (a, m) => a + (m[k] as int).toDouble());
  double get _tEspe => _sum('v_espe');
  double get _tCheq => _sum('v_cheq');
  double get _tCart => _sum('v_cart');
  double get _tAut => _sum('v_aut');
  double get _tCa => _sum('v_ca');
  List<String> get _artLabels => _artTop.map((e) => '${e['labelle'] ?? ''}').toList();
  List<double> get _artValues => _artTop.map((e) => Fmt.toDouble(e['qte'])).toList();

  bool get _fr => AppLang.lang.value == 'fr';
  String _t(String fr, String en) => _fr ? fr : en;

  /// Cache is per period: another period never shows these numbers.
  String get _page => 'pv:${Fmt.dmy(_start)}:${Fmt.dmy(_end)}';

  @override
  void initState() {
    super.initState();
    AppLang.lang.addListener(_onLang);
    final n = DateTime.now();
    _start = DateTime(n.year, n.month, n.day);
    _end = _start;
    _restore();
    // fresh data (< 3 min) is shown as is, otherwise the cached numbers stay
    // visible while every section refreshes by itself
    if (!PageCache.fresh(_page)) _loadAll();
  }

  void _restore() {
    final r = PageCache.get<List<Map<String, dynamic>>>(_page, 'rows');
    final a = PageCache.get<List<Map<String, dynamic>>>(_page, 'art');
    if (r != null) _rows = r;
    if (a != null) _artTop = a;
  }

  void _onLang() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final s in _secs) {
      s.gen++; // drop every running answer
    }
    AppLang.lang.removeListener(_onLang);
    super.dispose();
  }

  // ------------------------------------------------------------- data
  /// Whole page: the procedure runs ONCE, then the table and the articles
  /// chart read their data at the same time, each one shows up when ready.
  Future<void> _loadAll() async {
    if ((AppConfig.pointageBody()['url'] as String).isEmpty) {
      setState(() => _error =
          'URL de base de données manquante. Vérifiez la configuration.');
      return;
    }
    if (_error.isNotEmpty) setState(() => _error = '');
    final prep = _prepare();
    await Future.wait([_loadRows(prep), _loadArt(prep)]);
    if (mounted && _secs.every((s) => s.error.isEmpty)) PageCache.stamp(_page);
  }

  /// Session + the PV_LIST_AR procedure. Returns the session id.
  Future<String> _prepare() async {
    final base = AppConfig.baseUrlOrDefault;
    final body = AppConfig.pointageBody();
    _procFailed = false;
    if (AppConfig.sessionId.isEmpty) {
      try {
        await Session.load();
      } catch (_) {}
    }
    final sid = AppConfig.sessionId;
    if (sid.isEmpty) throw Exception('session');
    try {
      await Api.post('$base/hotel/PV_LIST_AR', body,
          query: {
            'p_startDate': Fmt.dmy(_start),
            'p_endDate': Fmt.dmy(_end),
            'session_id_': sid,
          },
          retries: 0,
          timeout: const Duration(seconds: 90));
    } catch (_) {
      _procFailed = true;
    }
    return sid;
  }

  Future<List<Map<String, dynamic>>> _read(String path, String sid) async =>
      Api.asList(await Api.post(
          '${AppConfig.baseUrlOrDefault}/hotel/$path/$sid',
          AppConfig.pointageBody()));

  Future<void> _loadRows([Future<String>? prep]) => runSec(_sRows, (gen) async {
        final sid = await (prep ?? _prepare()).timeout(const Duration(seconds: 150));
        if (!ok(_sRows, gen)) return;
        final data = await _read('getlistpv', sid);
        if (!ok(_sRows, gen)) return;
        if (data.isEmpty && _procFailed) throw Exception('PV_LIST_AR');
        int fl(dynamic v) => Fmt.toDouble(v).floor();
        final rows = data
            .map((m) => {
                  ...m,
                  'v_espe': fl(m['espe']),
                  'v_cheq': fl(m['cheq']),
                  'v_cart': fl(m['cart']),
                  'v_aut': fl(m['aut']),
                  'v_ca': fl(m['ca']),
                })
            .toList();
        setState(() => _rows = rows);
        PageCache.put(_page, 'rows', rows);
      });

  Future<void> _loadArt([Future<String>? prep]) => runSec(_sArt, (gen) async {
        final sid = await (prep ?? _prepare()).timeout(const Duration(seconds: 150));
        if (!ok(_sArt, gen)) return;
        final art = [...await _read('getmaxarticle', sid)];
        if (!ok(_sArt, gen)) return;
        // top 3 articles by quantity (Ionic needs at least 3 rows)
        art.sort((a, b) =>
            Fmt.toDouble(b['qte']).compareTo(Fmt.toDouble(a['qte'])));
        final top =
            art.length >= 3 ? art.take(3).toList() : <Map<String, dynamic>>[];
        setState(() => _artTop = top);
        PageCache.put(_page, 'art', top);
      });

  Future<void> _pick(bool isStart) async {
    final res = await showDatePicker(
      context: context,
      initialDate: isStart ? _start : _end,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (res == null) return;
    setState(() {
      if (isStart) {
        _start = res;
        if (_end.isBefore(_start)) _end = _start;
      } else {
        _end = res;
        if (_start.isAfter(_end)) _start = _end;
      }
      _rows = []; // never show another period's numbers
      _artTop = [];
    });
    _restore(); // this period may already be cached
    if (!PageCache.fresh(_page)) _loadAll();
  }

  void _openDetails(Map<String, dynamic> row) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DeteilRecapScreen(
        caisseId: '${row['caisseid'] ?? ''}',
        label: '${row['labelle'] ?? ''}',
        total: Fmt.toDouble(row['v_ca']),
        start: _start,
        end: _end,
      ),
    ));
  }

  // --------------------------------------------------------------- UI
  Widget _dateBox(bool isStart) {
    final d = isStart ? _start : _end;
    return Expanded(
      child: OutlinedButton.icon(
        onPressed: () => _pick(isStart),
        icon: const Icon(Icons.calendar_month, size: 18),
        label: Text(Fmt.dmy(d)),
      ),
    );
  }

  /// 0 -> blank (like the Ionic table), otherwise "1 234".
  Widget _amount(dynamic v) => Text(v == 0 ? '' : Fmt.thousands(v));

  @override
  Widget build(BuildContext context) {
    Widget b(String s) =>
        Text(s, style: const TextStyle(fontWeight: FontWeight.w800));
    final noData = _t('Aucune donnée', 'No data');

    final table = FluidTable(
      headers: [
        'P.V',
        _t('ESPE', 'CASH'),
        _t('CHEQ', 'CHECK'),
        _t('CART', 'CARD'),
        _t('AUTRE', 'OTHER'),
        _t('CA', 'TURNOVER'),
      ],
      flex: const [2.2, 1.1, 1.1, 1.1, 1.1, 1.3],
      rightCols: const {1, 2, 3, 4, 5},
      onRowTap: (i) => _openDetails(_rows[i]),
      rows: [
        for (final m in _rows)
          [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(child: Text('${m['labelle'] ?? ''}')),
              const SizedBox(width: 3),
              const Icon(Icons.visibility_outlined,
                  size: 14, color: Color(0xFF2196F3)),
            ]),
            _amount(m['v_espe']),
            _amount(m['v_cheq']),
            _amount(m['v_cart']),
            _amount(m['v_aut']),
            _amount(m['v_ca']),
          ],
        if (_rows.isNotEmpty)
          [
            b(_t('Total', 'Total')),
            b(Fmt.thousands(_tEspe)),
            b(Fmt.thousands(_tCheq)),
            b(Fmt.thousands(_tCart)),
            b(Fmt.thousands(_tAut)),
            b(Fmt.thousands(_tCa)),
          ],
      ],
    );

    // top 3 points of sale by turnover
    final topPv = [..._rows]
      ..sort((a, b) => (b['v_ca'] as int).compareTo(a['v_ca'] as int));
    final pv3 = topPv.take(3).toList();

    return Scaffold(
      appBar: xliaAppBar(
        context,
        title: 'PV',
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

            SectionTitle(_t('Sélectionner la période :', 'Select the period:')),
            Row(children: [
              _dateBox(true),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(_t('Au', 'To'),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              _dateBox(false),
            ]),
            const SizedBox(height: 16),

            SecTitle(_t('Points de vente', 'Sales points'),
                sec: _sRows, onRefresh: _loadRows),
            SecCard(
              sec: _sRows,
              hasData: _rows.isNotEmpty,
              onRetry: _loadRows,
              child: _rows.isEmpty
                  ? EmptyChart(noData, height: 80)
                  : table,
            ),
            const SizedBox(height: 16),

            SecCard(
              sec: _sArt,
              hasData: _artTop.isNotEmpty,
              onRetry: _loadArt,
              minHeight: 200,
              child: BarSeriesChart(
                emptyText: noData,
                labels: _artLabels,
                values: _artValues,
                colors: const [
                  Color(0xFFFF4336), Color(0xFF3694FF), Color(0xFFFF36F8)
                ],
                legend: _t('Meilleurs Articles Vendus', 'Top Selling Items'),
              ),
            ),
            const SizedBox(height: 16),

            SecCard(
              sec: _sRows,
              hasData: _rows.isNotEmpty,
              onRetry: _loadRows,
              minHeight: 200,
              child: BarSeriesChart(
                emptyText: noData,
                labels: pv3.map((e) => '${e['labelle'] ?? ''}').toList(),
                values: pv3.map((e) => (e['v_ca'] as int).toDouble()).toList(),
                colors: const [Color(0xFFFA7000)],
                legend: _t('Points de Vente', 'Sales Points'),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
