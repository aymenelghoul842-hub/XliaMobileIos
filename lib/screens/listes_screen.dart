import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/api_client.dart';
import '../core/net.dart';
import '../core/app_config.dart';
import '../core/lang.dart';
import '../core/responsive.dart';
import '../core/section.dart';

/// Port of ListesPage ("Etat Residents").
/// Endpoints: /hotel/getcountvip, getVIP, getlisteoffre, getlisteanni,
/// getlistrevent, getnoshowlist
class ListesScreen extends StatefulWidget {
  final VoidCallback? onMenu;
  const ListesScreen({super.key, this.onMenu});

  @override
  State<ListesScreen> createState() => _ListesScreenState();
}

class _ListesScreenState extends State<ListesScreen>
    with WidgetsBindingObserver {
  /// Live mode: the lists refresh by themselves every 30 s while the page is
  /// open (silently: no spinner, and old data stays if the server fails).
  static const Duration _liveEvery = Duration(seconds: 30);
  Timer? _liveTimer;
  bool _appActive = true;
  DateTime? _updated;

  bool _loading = false;
  String _error = '';

  List<MapEntry<String, num>> _counts = [];
  List<Map<String, dynamic>> _vip = [];
  List<Map<String, dynamic>> _offers = [];
  List<Map<String, dynamic>> _annif = [];
  List<Map<String, dynamic>> _revenants = [];
  List<Map<String, dynamic>> _noshow = [];

  bool get _fr => AppLang.lang.value == 'fr';
  String _t(String fr, String en) => _fr ? fr : en;

  @override
  void initState() {
    super.initState();
    AppLang.lang.addListener(_onLang);
    WidgetsBinding.instance.addObserver(this);
    _restore();
    if (!PageCache.fresh('listes')) _fetch();
    _liveTimer = Timer.periodic(_liveEvery, (_) {
      if (mounted && _appActive) _fetch(silent: true);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    // back from the background: catch up at once
    if (_appActive && mounted) _fetch(silent: true);
  }

  /// Last answers are shown instantly when the page is re-opened.
  void _restore() {
    final c = PageCache.get<List<MapEntry<String, num>>>('listes', 'counts');
    final v = PageCache.get<List<Map<String, dynamic>>>('listes', 'vip');
    final o = PageCache.get<List<Map<String, dynamic>>>('listes', 'offers');
    final a = PageCache.get<List<Map<String, dynamic>>>('listes', 'annif');
    final r = PageCache.get<List<Map<String, dynamic>>>('listes', 'rev');
    final n = PageCache.get<List<Map<String, dynamic>>>('listes', 'noshow');
    if (c != null && v != null && o != null && a != null && r != null && n != null) {
      _counts = c;
      _vip = v;
      _offers = o;
      _annif = a;
      _revenants = r;
      _noshow = n;
    }
  }

  void _onLang() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    AppLang.lang.removeListener(_onLang);
    super.dispose();
  }

  num _num(dynamic v) =>
      v is num ? v : (num.tryParse(v?.toString() ?? '') ?? 0);

  Future<void> _fetch({bool silent = false}) async {
    if (_loading) return;
    final base = AppConfig.baseUrlOrDefault;
    final body = AppConfig.pointageBody();
    if ((body['url'] as String).isEmpty) {
      setState(() => _error =
          'URL de base de données manquante. Vérifiez la configuration.');
      return;
    }
    if (silent) {
      _loading = true; // no spinner / no flicker for a live refresh
    } else {
      setState(() {
        _loading = true;
        _error = '';
      });
    }

    final errors = <String>[];

    Future<List<Map<String, dynamic>>> list(String endpoint) async {
      try {
        final res = await Api.post('$base/hotel/$endpoint', body);
        // Oracle / JSON may return the keys in upper case or with another
        // spelling: add a lower-case copy of every key (originals are kept)
        return Api.asList(res).map((m) {
          final out = Map<String, dynamic>.from(m);
          m.forEach((k, v) => out.putIfAbsent(k.toString().toLowerCase(), () => v));
          return out;
        }).toList();
      } on ApiException catch (e) {
        errors.add(Net.message(e));
      } catch (e) {
        errors.add('$endpoint: $e');
      }
      return [];
    }

    final results = await Future.wait([
      () async {
        try {
          final res = await Api.post('$base/hotel/getcountvip', body);
          if (res is Map) {
            _counts = res.entries
                .map((e) => MapEntry(e.key.toString(), _num(e.value)))
                .toList();
          }
        } catch (e) {
          errors.add('getcountvip');
        }
        return <Map<String, dynamic>>[];
      }(),
      list('getVIP'),
      list('getlisteoffre'),
      list('getlisteanni'),
      list('getlistrevent'),
      list('getnoshowlist'),
    ]);

    if (!mounted) return;
    if (silent && errors.isNotEmpty) {
      _loading = false; // live refresh failed: keep what is on screen
      return;
    }
    setState(() {
      _updated = DateTime.now();
      _vip = results[1];
      _offers = results[2];
      _annif = results[3];
      _revenants = results[4];
      // One single No Show source: the list itself (same reservation can come
      // from resa_chambre AND no_show -> keep it once). The count shown in the
      // "Nature / Nombre" table is the size of that list, so both always match.
      final seen = <String>{};
      _noshow = results[5].where((r) {
        final k = '${r['coderes'] ?? ''}';
        return k.isEmpty || seen.add(k);
      }).toList();
      final nsCount = _noshow.length;
      var hasNs = false;
      _counts = [
        for (final e in _counts)
          if (e.key == 'noshow')
            () {
              hasNs = true;
              return MapEntry<String, num>('noshow', nsCount);
            }()
          else
            e,
      ];
      if (!hasNs) {
        _counts = [..._counts, MapEntry<String, num>('noshow', nsCount)];
      }
      _loading = false;
      _error = errors.isEmpty ? '' : errors.first;
    });
    if (errors.isEmpty) {
      PageCache.put('listes', 'counts', _counts);
      PageCache.put('listes', 'vip', _vip);
      PageCache.put('listes', 'offers', _offers);
      PageCache.put('listes', 'annif', _annif);
      PageCache.put('listes', 'rev', _revenants);
      PageCache.put('listes', 'noshow', _noshow);
      PageCache.stamp('listes');
    }
  }

  // ---------------------------------------------------------------- UI
  IconData _countIcon(String key) {
    switch (key) {
      case 'anniversaires':
        return Icons.calendar_today_outlined;
      case 'vips':
        return Icons.account_circle_outlined;
      case 'offres':
        return Icons.card_giftcard;
      case 'revenants':
        return Icons.refresh;
      case 'noshow':
        return Icons.error_outline;
      default:
        return Icons.circle_outlined;
    }
  }

  String _countLabel(String key) {
    switch (key) {
      case 'anniversaires':
        return _t('Anniversaires', 'Birthdays');
      case 'vips':
        return 'VIPs';
      case 'offres':
        return _t('Offres', 'Offers');
      case 'revenants':
        return _t('Revenants', 'Returnees');
      case 'noshow':
        return 'No Show';
      default:
        return key;
    }
  }

  String _md(dynamic v) {
    if (v == null) return '';
    final d = v is num
        ? DateTime.fromMillisecondsSinceEpoch(v.toInt())
        : DateTime.tryParse(v.toString());
    return d == null ? v.toString() : DateFormat('MM/dd').format(d);
  }

  @override
  Widget build(BuildContext context) {
    final room = _t('Chb', 'Room');
    final name = _t('Nom', 'Name');
    final arr = _t('Arr', 'Arrival');
    final dep = _t('Dép', 'Departure');
    Widget bold(dynamic v) => Text('${v ?? ''}',
        style: const TextStyle(fontWeight: FontWeight.w600));

    PagedTable guests(String title, List<Map<String, dynamic>> rows,
            {bool times = false}) =>
        PagedTable(
          title: title,
          rows: rows,
          columns: [
            PagedColumn(room, 1, (r) => RoomChip('${r['chambre'] ?? ''}')),
            PagedColumn(name, 2.4, (r) => bold(r['nom'])),
            PagedColumn(arr, 1.3,
                (r) => DateCell(Icons.login, Colors.green, '${r['arrivee'] ?? ''}')),
            PagedColumn(dep, 1.3,
                (r) => DateCell(Icons.logout, Colors.red, '${r['depart'] ?? ''}')),
            if (times)
              PagedColumn(
                  _t('Nb Fois', 'Times'),
                  1,
                  (r) => Pill('${r['nbfois'] ?? r['nb_fois'] ?? r['nbrfois'] ?? r['nbr'] ?? r['nombre'] ?? r['nb'] ?? 0}×', const Color(0xFFEDE7F6),
                      const Color(0xFF6A1B9A))),
          ],
        );

    return Scaffold(
      appBar: xliaAppBar(
        context,
        title: _t('État Résidents', 'Residents Status'),
        date: DateFormat('dd/MM/yyyy').format(DateTime.now()),
        loading: _loading,
        onRefresh: _fetch,
        onMenu: widget.onMenu,
      ),
      body: RefreshIndicator(
        onRefresh: _fetch,
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
            if (_loading && _counts.isEmpty)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (_updated != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  const Icon(Icons.circle, size: 9, color: Color(0xFF2E7D32)),
                  const SizedBox(width: 6),
                  Text(
                    'Live · ${DateFormat('HH:mm:ss').format(_updated!)}',
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF2E7D32)),
                  ),
                ]),
              ),
            if (_counts.isNotEmpty) ...[_countsCard(), const SizedBox(height: 16)],
            guests(_t('Liste des VIPs', 'VIP List'), _vip),
            guests(_t('Liste des Offres', 'Offer List'), _offers),
            guests(_t('Liste des Anniversaires', 'Birthday List'), _annif),
            guests(_t('Liste des Revenants', 'Returnee List'), _revenants,
                times: true),
            PagedTable(
              title: _t('Liste des No Show', 'No Show List'),
              rows: _noshow,
              columns: [
                PagedColumn(
                    _t('Agence', 'Agency'),
                    1.4,
                    (r) => Pill('${r['agence'] ?? ''}', const Color(0xFFFFF3E0),
                        const Color(0xFFE65100))),
                PagedColumn(name, 2, (r) => bold(r['nom'])),
                PagedColumn(_t('Détail', 'Detail'), 2, (r) => Text('${r['deteil'] ?? ''}')),
                PagedColumn(arr, 1.1,
                    (r) => DateCell(Icons.login, Colors.green, _md(r['datearr']))),
                PagedColumn(dep, 1.1,
                    (r) => DateCell(Icons.logout, Colors.red, _md(r['datedep']))),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Same key in different spellings (noshow / noShow / no_show) or sent
  /// twice -> shown once. "No Show" always gets the size of the list.
  List<MapEntry<String, num>> _cleanCounts() {
    final out = <MapEntry<String, num>>[];
    final seen = <String>{};
    for (final e in _counts) {
      final norm = e.key.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
      if (!seen.add(norm.contains('noshow') ? 'noshow' : norm)) continue;
      out.add(norm.contains('noshow')
          ? MapEntry<String, num>('noshow', _noshow.length)
          : e);
    }
    return out;
  }

  Widget _countsCard() => AppCard(
        child: FluidTable(
          headers: [_t('Nature', 'Nature'), _t('Nombre', 'Number')],
          flex: const [3, 1],
          rows: [
            // ONE single "No Show" row (its number = size of the No Show list)
            for (final e in _cleanCounts())
              [
                Row(children: [
                  Icon(_countIcon(e.key),
                      size: R.fluid(context, 0.8, 2.2, 1.1),
                      color: const Color(0xFF2196F3)),
                  const SizedBox(width: 8),
                  Flexible(child: Text(_countLabel(e.key))),
                ]),
                Pill('${e.value}', const Color(0xFFE3F0FF), const Color(0xFF1565C0),
                    center: true),
              ],
          ],
        ),
      );
}

class PagedColumn {
  final String label;
  final double flex;
  final Widget Function(Map<String, dynamic> row) cell;
  PagedColumn(this.label, this.flex, this.cell);
}

/// Reusable paginated table card (5 rows per page).
/// Hidden automatically when [rows] is empty (like the *ngIf in Ionic).
class PagedTable extends StatefulWidget {
  final String title;
  final List<PagedColumn> columns;
  final List<Map<String, dynamic>> rows;
  final int perPage;
  const PagedTable({
    super.key,
    required this.title,
    required this.columns,
    required this.rows,
    this.perPage = 5,
  });

  @override
  State<PagedTable> createState() => _PagedTableState();
}

class _PagedTableState extends State<PagedTable> {
  int _page = 1;

  int get _total => max(1, (widget.rows.length / widget.perPage).ceil());

  @override
  void didUpdateWidget(covariant PagedTable old) {
    super.didUpdateWidget(old);
    if (_page > _total) _page = 1;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.rows.isEmpty) return const SizedBox.shrink();

    final start = (_page - 1) * widget.perPage;
    final items =
        widget.rows.sublist(start, min(start + widget.perPage, widget.rows.length));

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionTitle(widget.title),
          AppCard(
            child: Column(
              children: [
                FluidTable(
                  headers: [for (final c in widget.columns) c.label],
                  flex: [for (final c in widget.columns) c.flex],
                  rows: [
                    for (final r in items) [for (final c in widget.columns) c.cell(r)],
                  ],
                ),
                const SizedBox(height: 10),
                PageBar(
                    page: _page,
                    total: _total,
                    onPage: (p) => setState(() => _page = p)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
