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

/// Port of InviteFriendPage ("Etat tiers", route /menu/invitefriend).
///
///   1. POST /hotel/GetDataproce            -> session, dateimputcontrol, device
///   2. POST /hotel/genere_impayer/{sid}    -> procedure (builds the unpaid list)
///   3. POST /hotel/getetatier/{sid}        -> [{nomtier, montant}] sorted desc
class TiersScreen extends StatefulWidget {
  final VoidCallback? onMenu;
  const TiersScreen({super.key, this.onMenu});

  @override
  State<TiersScreen> createState() => _TiersScreenState();
}

class _TiersScreenState extends State<TiersScreen> with SecLoader {
  static const String _pageKey = 'tiers';

  final Sec _sec = Sec(); // own spinner / progress bar / retry (like CA)
  String _error = ''; // configuration problem only

  String _dateImput = '';
  String _device = '';
  List<Map<String, dynamic>> _rows = [];
  double _total = 0;

  // search by name + pagination (50 per page)
  static const int _pageSize = 50;
  final TextEditingController _search = TextEditingController();
  String _query = '';
  int _page = 0;

  /// Rows matching the search (name), already sorted by amount.
  List<Map<String, dynamic>> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _rows;
    return _rows
        .where((m) => '${m['nomtier'] ?? ''}'.toLowerCase().contains(q))
        .toList();
  }

  bool get _fr => AppLang.lang.value == 'fr';
  String _t(String fr, String en) => _fr ? fr : en;

  @override
  void initState() {
    super.initState();
    AppLang.lang.addListener(_onLang);
    _restore();
    // fresh data (< 3 min) is shown as is, otherwise the cached numbers stay
    // visible while the page refreshes by itself
    if (!PageCache.fresh(_pageKey)) _load();
  }

  void _restore() {
    final r = PageCache.get<List<Map<String, dynamic>>>(_pageKey, 'rows');
    if (r == null) return;
    _rows = r;
    _total = r.fold<double>(0, (a, m) => a + (m['v_montant'] as double));
    _dateImput = PageCache.get<String>(_pageKey, 'dateImput') ?? '';
    _device = PageCache.get<String>(_pageKey, 'device') ?? '';
  }

  void _onLang() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _sec.gen++; // drop a running answer
    _search.dispose();
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
    if (mounted && _sec.error.isEmpty) PageCache.stamp(_pageKey);
  }

  Future<void> _run(int gen, String base, Map<String, dynamic> body) async {
    // 1) session + control date + currency
    try {
      final data = await Session.load();
      final d = (data['dateimputcontrol'] ?? '').toString();
      final dev = (data['device'] ?? '').toString();
      if (ok(_sec, gen)) {
        setState(() {
          _dateImput = d.isEmpty ? _t('Date indisponible', 'Date unavailable') : d;
          _device = dev;
        });
        PageCache.put(_pageKey, 'dateImput', _dateImput);
        PageCache.put(_pageKey, 'device', _device);
      }
    } catch (_) {
      if (ok(_sec, gen) && _dateImput.isEmpty) {
        setState(() => _dateImput = _t('Date indisponible', 'Date unavailable'));
      }
    }
    if (!ok(_sec, gen)) return;

    final sid = AppConfig.sessionId;
    if (sid.isEmpty) throw Exception('session');

    // 2) procedure (heavy: long timeout, no retry)
    var procFailed = false;
    try {
      await Api.post('$base/hotel/genere_impayer/$sid', body,
          retries: 0, timeout: const Duration(seconds: 90));
    } catch (_) {
      procFailed = true;
    }
    if (!ok(_sec, gen)) return;

    // 3) data (an error here marks the section: retry button / red message)
    final data = Api.asList(await Api.post('$base/hotel/getetatier/$sid', body));
    if (!ok(_sec, gen)) return;
    if (data.isEmpty && procFailed) throw Exception('genere_impayer');

    final rows = data.map((m) {
      final raw = (m['montant'] ?? '0').toString().replaceAll(',', '').trim();
      return {...m, 'v_montant': double.tryParse(raw) ?? 0.0};
    }).toList()
      ..sort((a, b) =>
          (b['v_montant'] as double).compareTo(a['v_montant'] as double));

    setState(() {
      _rows = rows;
      _total = rows.fold<double>(0, (a, m) => a + (m['v_montant'] as double));
      _page = 0;
    });
    PageCache.put(_pageKey, 'rows', rows);
  }

  @override
  Widget build(BuildContext context) {
    Widget b(String s) =>
        Text(s, style: const TextStyle(fontWeight: FontWeight.w800));

    final filtered = _filtered;
    final pages = filtered.isEmpty ? 1 : (filtered.length / _pageSize).ceil();
    final page = _page.clamp(0, pages - 1);
    final shown = filtered.skip(page * _pageSize).take(_pageSize).toList();
    final filteredTotal =
        filtered.fold<double>(0, (a, m) => a + (m['v_montant'] as double));

    final table = FluidTable(
      headers: [
        _t('Nom Tiers', 'Third party'),
        '${_t('Montant', 'Amount')} $_device'.trim(),
      ],
      flex: const [2.5, 1.3],
      rightCols: const {1},
      rows: [
        for (final m in shown)
          [
            Text('${m['nomtier'] ?? ''}'),
            Text(Fmt.thousands(m['v_montant']),
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        if (filtered.isNotEmpty) [b('TOTAL'), b(Fmt.thousands(filteredTotal))],
      ],
    );

    final searchField = Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: _search,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          isDense: true,
          prefixIcon: const Icon(Icons.search),
          hintText: _t('Rechercher par nom', 'Search by name'),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _search.clear();
                    setState(() {
                      _query = '';
                      _page = 0;
                    });
                  },
                ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
        onChanged: (v) => setState(() {
          _query = v;
          _page = 0;
        }),
      ),
    );

    final pager = Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            tooltip: _t('Précédent', 'Previous'),
            icon: const Icon(Icons.chevron_left),
            onPressed: page > 0 ? () => setState(() => _page = page - 1) : null,
          ),
          Flexible(
            child: Text(
              '${_t('Page', 'Page')} ${page + 1} / $pages  •  '
              '${filtered.length} ${_t('résultat(s)', 'result(s)')}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            tooltip: _t('Suivant', 'Next'),
            icon: const Icon(Icons.chevron_right),
            onPressed: page < pages - 1
                ? () => setState(() => _page = page + 1)
                : null,
          ),
        ],
      ),
    );

    return Scaffold(
      appBar: xliaAppBar(
        context,
        title: _t('Etat Tiers', 'Third Parties'),
        date: DateFormat('dd/MM/yyyy').format(DateTime.now()),
        loading: _sec.loading,
        onRefresh: _load,
        onMenu: widget.onMenu,
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ResponsivePage(
          maxWidth: 800,
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
            SecTitle(_t('Situation des impayés', 'Unpaid situation'),
                sec: _sec, onRefresh: _load),
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '${_t('Imputé au', 'Posted on')}: ${_dateImput.isEmpty ? '…' : _dateImput}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, color: Colors.black54),
                ),
              ),
            ),
            SecCard(
              sec: _sec,
              hasData: _rows.isNotEmpty,
              onRetry: _load,
              child: _rows.isEmpty
                  ? EmptyChart(_t('Aucune donnée', 'No data'), height: 80)
                  : Column(children: [
                      searchField,
                      if (filtered.isEmpty)
                        EmptyChart(_t('Aucun résultat', 'No results'),
                            height: 80)
                      else ...[
                        table,
                        pager,
                      ],
                    ]),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
