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

/// Port of DeteilrecapPage (details of one point of sale, opened from PV).
///
///   1. POST /hotel/detiel_art?caiss_param&p_startDate&p_endDate&session_id_
///   2. POST /hotel/getlistcaisseid/{sid}  -> articles table + top 3 chart
class DeteilRecapScreen extends StatefulWidget {
  final String caisseId;
  final String label;
  final double total; // CA of the point of sale (for the % column)
  final DateTime start;
  final DateTime end;

  const DeteilRecapScreen({
    super.key,
    required this.caisseId,
    required this.label,
    required this.total,
    required this.start,
    required this.end,
  });

  @override
  State<DeteilRecapScreen> createState() => _DeteilRecapScreenState();
}

class _DeteilRecapScreenState extends State<DeteilRecapScreen> with SecLoader {
  final Sec _sec = Sec(); // own spinner / progress bar / retry (like CA)
  String _error = ''; // configuration problem only

  List<Map<String, dynamic>> _rows = [];

  // totals + top 3 are computed from the rows (also after a cache restore)
  double _sum(String k) =>
      _rows.fold<double>(0, (a, m) => a + (m[k] as double));
  double get _tQte => _sum('v_qte');
  double get _tCa => _sum('v_ca');
  double get _tPrix => _sum('v_prix');
  double get _tPct => widget.total > 0 ? _tCa / widget.total * 100 : 0;
  List<Map<String, dynamic>> get _top3 {
    final top = [..._rows]
      ..sort((a, b) => (b['v_ca'] as double).compareTo(a['v_ca'] as double));
    return top.take(3).toList();
  }

  List<String> get _topLabels => _top3
      .map((e) =>
          '${(e['labelle'] ?? '').toString().isEmpty ? 'Inconnu' : e['labelle']}')
      .toList();
  List<double> get _topValues => _top3.map((e) => e['v_ca'] as double).toList();

  bool get _fr => AppLang.lang.value == 'fr';
  String _t(String fr, String en) => _fr ? fr : en;

  /// Cache key: this point of sale, this period, this total.
  String get _page =>
      'detail:${widget.caisseId}:${Fmt.dmy(widget.start)}:${Fmt.dmy(widget.end)}:${widget.total.round()}';

  @override
  void initState() {
    super.initState();
    AppLang.lang.addListener(_onLang);
    final r = PageCache.get<List<Map<String, dynamic>>>(_page, 'rows');
    if (r != null) _rows = r;
    // fresh data (< 3 min) is shown as is, otherwise the cached numbers stay
    // visible while the page refreshes by itself
    if (!PageCache.fresh(_page)) _load();
  }

  void _onLang() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _sec.gen++; // drop a running answer
    AppLang.lang.removeListener(_onLang);
    super.dispose();
  }

  Future<void> _load() async {
    final base = AppConfig.baseUrlOrDefault;
    final body = AppConfig.pointageBody();
    if ((body['url'] as String).isEmpty) {
      setState(() => _error =
          'URL de base de données manquante. Vérifiez la configuration.');
      return;
    }
    if (_error.isNotEmpty && mounted) setState(() => _error = '');
    await runSec(_sec, (gen) async {
      await _run(gen, base, body).timeout(const Duration(seconds: 120));
    });
    if (mounted && _sec.error.isEmpty) PageCache.stamp(_page);
  }

  Future<void> _run(int gen, String base, Map<String, dynamic> body) async {
    if (AppConfig.sessionId.isEmpty) {
      try {
        await Session.load();
      } catch (_) {}
    }
    final sid = AppConfig.sessionId;
    if (sid.isEmpty) throw Exception('session');

    // 1) procedure: must succeed before reading the result table
    await Api.post('$base/hotel/detiel_art', body,
        query: {
          'caiss_param': widget.caisseId,
          'p_startDate': Fmt.dmy(widget.start),
          'p_endDate': Fmt.dmy(widget.end),
          'session_id_': sid,
        },
        retries: 0,
        timeout: const Duration(seconds: 90));
    if (!ok(_sec, gen)) return;

    // 2) result table
    final data =
        Api.asList(await Api.post('$base/hotel/getlistcaisseid/$sid', body));
    if (!ok(_sec, gen)) return;

    final to = widget.total;
    final rows = data.map((m) {
      final ca = Fmt.toDouble(m['ca']).floorToDouble();
      return {
        ...m,
        'v_qte': Fmt.toDouble(m['qte']),
        'v_prix': Fmt.toDouble(m['prix']),
        'v_ca': ca,
        'v_pct': to > 0 ? ca / to * 100 : 0.0,
      };
    }).toList();

    setState(() => _rows = rows);
    PageCache.put(_page, 'rows', rows);
  }

  @override
  Widget build(BuildContext context) {
    Widget b(String s) =>
        Text(s, style: const TextStyle(fontWeight: FontWeight.w800));
    final noData = _t('Aucune donnée', 'No data');

    final table = FluidTable(
      headers: [
        _t('Libellé', 'Label'),
        _t('Qté', 'Qty'),
        _t('Prix Unit. (DT)', 'Unit Price (DT)'),
        _t('C.A (DT)', 'Turnover (DT)'),
        _t('CA(%)', 'CA(%)'),
      ],
      flex: const [2.6, 1, 1.4, 1.3, 1.1],
      rightCols: const {1, 2, 3, 4},
      rows: [
        for (final m in _rows)
          [
            Text('${m['labelle'] ?? ''}'),
            Text(Fmt.n(m['v_qte'])),
            Text(Fmt.n(m['v_prix'])),
            Text(Fmt.thousands(m['v_ca'])),
            Text((m['v_pct'] as double).toStringAsFixed(2)),
          ],
        if (_rows.isNotEmpty)
          [
            b(_t('Total', 'Total')),
            b(Fmt.n(_tQte)),
            b(_tPrix.toStringAsFixed(2)),
            b(Fmt.thousands(_tCa)),
            b(_tPct.toStringAsFixed(2)),
          ],
      ],
    );

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: _t('Retour', 'Back'),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          hotelTitle('${_t('Point de Vente :', 'Sales Point:')} ${widget.label}'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontSize: R.fluid(context, 0.875, 3, 1.2),
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1976D2)),
        ),
        actions: [
          Center(
            child: Text(DateFormat('dd/MM/yyyy').format(DateTime.now()),
                style: TextStyle(
                    fontSize: R.fluid(context, 0.65, 2, 0.9),
                    color: Colors.black54)),
          ),
          IconButton(
            icon: _sec.loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
            onPressed: _sec.loading ? null : _load,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
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
            Center(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  '${Fmt.dmy(widget.start)}  →  ${Fmt.dmy(widget.end)}',
                  style: const TextStyle(color: Colors.black54),
                ),
              ),
            ),
            SecCard(
              sec: _sec,
              hasData: _rows.isNotEmpty,
              onRetry: _load,
              child: _rows.isEmpty
                  ? EmptyChart(noData, height: 80)
                  : table,
            ),
            const SizedBox(height: 16),
            SecTitle(_t('Meilleur Article Vendu', 'Top Selling Item'),
                sec: _sec, onRefresh: _load),
            SecCard(
              sec: _sec,
              hasData: _rows.isNotEmpty,
              onRetry: _load,
              minHeight: 200,
              child: BarSeriesChart(
                emptyText: noData,
                labels: _topLabels,
                values: _topValues,
                colors: const [
                  Color(0x99369EEB), Color(0x99FF6384), Color(0x994BC0C0)
                ],
                legend: _t('C.A (DT)', 'Turnover (DT)'),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
