import 'dart:convert';
import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/api_client.dart';
import '../core/app_config.dart';
import '../core/lang.dart';
import '../core/net.dart';
import '../core/prefs.dart';
import '../core/responsive.dart';
import '../core/section.dart';
import '../core/session.dart';

/// Port of HomePage ("Etat Hotel"): daily movement, charts, operations, rooms.
class HomeScreen extends StatefulWidget {
  final VoidCallback? onMenu;
  const HomeScreen({super.key, this.onMenu});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _RoomRow {
  final String title;
  final num number;
  _RoomRow(this.title, this.number);
}

class _HomeScreenState extends State<HomeScreen> {
  static const int _perPage = 5;

  bool _refreshing = false;
  bool _dataLoaded = false;
  bool _chartVisible = false;
  String _error = '';

  List<Map<String, dynamic>> _occupation = [];
  List<_RoomRow> _rooms = [];
  List<Map<String, dynamic>> _clients = [];
  final Set<Map<String, dynamic>> _expanded = {};
  int _page = 1;

  // arrivals / departures
  double _arrPrev = 0, _arr = 0, _depPrev = 0, _dep = 0;
  // walk-in / no show
  double _walk = 0, _noShow = 0;

  Map<String, String> _colorMap = {};
  int _selectedRow = 0;
  String _chartTitle = '';
  List<Map<String, dynamic>> _chartData = [];

  @override
  void initState() {
    super.initState();
    AppLang.lang.addListener(_onLang);
    _restore();
    if (!PageCache.fresh('home')) _runAll();
  }

  /// Re-opening the page shows the last numbers at once (cache < 3 min).
  void _restore() {
    final o = PageCache.get<List<Map<String, dynamic>>>('home', 'occ');
    final r = PageCache.get<List<_RoomRow>>('home', 'rooms');
    final c = PageCache.get<List<Map<String, dynamic>>>('home', 'clients');
    final k = PageCache.get<List<double>>('home', 'nums');
    if (o == null || r == null || c == null || k == null || k.length < 6) return;
    _occupation = o;
    _rooms = r;
    _clients = c;
    _arrPrev = k[0];
    _arr = k[1];
    _depPrev = k[2];
    _dep = k[3];
    _walk = k[4];
    _noShow = k[5];
    _chartData = PageCache.get<List<Map<String, dynamic>>>('home', 'chart') ?? [];
    _chartTitle = PageCache.get<String>('home', 'chartTitle') ?? '';
    _chartVisible = _chartData.isNotEmpty;
    _colorMap = PageCache.get<Map<String, String>>('home', 'colors') ?? {};
    _dataLoaded = true;
  }

  void _store() {
    PageCache.put('home', 'occ', _occupation);
    PageCache.put('home', 'rooms', _rooms);
    PageCache.put('home', 'clients', _clients);
    PageCache.put('home', 'nums',
        <double>[_arrPrev, _arr, _depPrev, _dep, _walk, _noShow]);
    PageCache.put('home', 'chart', _chartData);
    PageCache.put('home', 'chartTitle', _chartTitle);
    PageCache.put('home', 'colors', _colorMap);
    PageCache.stamp('home');
  }

  void _onLang() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    AppLang.lang.removeListener(_onLang);
    super.dispose();
  }

  // ------------------------------------------------------------ helpers
  num _num(dynamic v) {
    if (v is num) return v;
    return num.tryParse(v?.toString() ?? '') ?? 0;
  }

  Color _hex(String s, {Color fallback = Colors.grey}) {
    var h = s.trim().replaceAll('#', '');
    try {
      if (h.length == 6) return Color(int.parse('FF$h', radix: 16));
      // CSS #RRGGBBAA -> Flutter AARRGGBB
      if (h.length == 8) {
        return Color(int.parse('${h.substring(6)}${h.substring(0, 6)}', radix: 16));
      }
    } catch (_) {}
    return fallback;
  }

  DateTime? _date(dynamic v) {
    if (v == null) return null;
    if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt());
    return DateTime.tryParse(v.toString());
  }

  String _fmtDate(dynamic v, String pattern) {
    final d = _date(v);
    return d == null ? '' : DateFormat(pattern).format(d);
  }

  String _titleCase(String s) => s
      .split(' ')
      .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1).toLowerCase())
      .join(' ');

  String _timeDiff(String heure) {
    if (heure.isEmpty) return '0m';
    final now = DateTime.now();
    final parts = heure.split(':').map((e) => int.tryParse(e) ?? 0).toList();
    final hh = parts.isNotEmpty ? parts[0] : 0;
    final mm = parts.length > 1 ? parts[1] : 0;
    var diff = (now.hour - hh) * 60 + (now.minute - mm);
    if (diff < 0) diff = diff.abs();
    if (diff < 1) return '${now.second}s';
    if (diff < 60) return '${diff}m';
    final h = diff ~/ 60;
    final m = diff % 60;
    return '${h}h${m > 0 ? ' ${m}m' : ''}';
  }

  String _roomLabel(String key) {
    const labels = {
      'chlibrepropore': 'Libre Propre',
      'chlibreSale': 'Libre Sale',
      'choccupP': 'Occupée Propre',
      'choccupS': 'Occupée Salle',
      'chreserv': 'Arrivée Effectuée',
      'chdep': 'Départ Effectué',
      'choffre': 'Offres',
      'chhs': 'Hors Service',
    };
    return labels[key] ?? key;
  }

  Color _statusColor(String etat) {
    switch (etat.trim()) {
      case 'Check In':
        return const Color(0xFF239E12);
      case 'Reservation':
        return const Color(0xFF2E1FFF);
      case 'Check Out':
        return const Color(0xFFFF4545);
      default:
        return Colors.grey;
    }
  }

  Color _statusText(String etat) =>
      ['Check In', 'Reservation', 'Check Out'].contains(etat.trim())
          ? Colors.white
          : Colors.black;

  // --------------------------------------------------------------- data
  Future<void> _runAll() async {
    if (_refreshing) return;
    setState(() {
      _refreshing = true;
      _error = '';
    });

    final base = AppConfig.baseUrlOrDefault;
    final body = AppConfig.pointageBody();
    final errors = <String>[];
    Object? lastErr;

    Future<void> step(String name, Future<void> Function() f) async {
      try {
        await f();
      } catch (e) {
        debugPrint('❌ $name failed: $e');
        errors.add(name);
        lastErr = e;
      }
      if (mounted) setState(() {});
    }

    // Phase 1: colors + session at the same time
    await Future.wait([
      step('getcolor', () => _loadColors(base, body)),
      step('GetDataproce', () => _loadDataProce(base, body)),
    ]);
    // Phase 2: the two procedures that fill the server tables (in order)
    await step('nbr_etat_chambre', () => _simpleSession(base, body, 'nbr_etat_chambre'));
    await step('getInfo_planning_apk', () => _loadPlanning(base, body));
    // Phase 3: every read at once - each block appears as soon as it arrives
    await Future.wait([
      step('arrdep', () => _loadArrDep(base, body)),
      step('getcountch', () => _loadRooms(base, body)),
      step('getMovementCl', () => _loadClients(base, body)),
      step('getOccupationPaxDetails', () => _loadOccupation(base, body)),
      step('charts', () => _onRoomRow(0)),
    ]);

    if (!mounted) return;
    setState(() {
      _refreshing = false;
      _dataLoaded = true;
      if (errors.isNotEmpty) {
        // every call failed on the network -> say it clearly
        _error = (errors.length >= 3 && lastErr is ApiException && (lastErr as ApiException).isNetwork)
            ? Net.message(lastErr!)
            : '${S.t('partialError')} (${errors.length}/9): ${errors.join(', ')}';
      }
    });
    if (errors.isEmpty) _store();
  }

  Future<void> _loadColors(String base, Map<String, dynamic> body) async {
    final res = await Api.post('$base/hotel/getcolor', body);
    final map = <String, String>{};
    for (final item in Api.asList(res)) {
      final code = (item['cod_categ'] ?? '').toString();
      final raw = item['color'];
      dynamic color = raw;
      try {
        final parsed = jsonDecode(raw.toString());
        color = parsed is Map ? parsed['color'] : parsed;
      } catch (_) {}
      map[code] = (color ?? '').toString();
    }
    _colorMap = map;
    await Prefs.setString('colorMap', jsonEncode(map));
  }

  Future<void> _loadDataProce(String base, Map<String, dynamic> body) async {
    // shared with the drawer: one GetDataproce call, stored by Session
    await Session.load();
  }

  /// Procedures that only need the session id in the URL.
  Future<void> _simpleSession(
      String base, Map<String, dynamic> body, String endpoint) async {
    final sid = AppConfig.sessionId;
    if (sid.isEmpty) return;
    await Api.post('$base/hotel/$endpoint/$sid', body);
  }

  Future<void> _loadPlanning(String base, Map<String, dynamic> body) async {
    final sid = AppConfig.sessionId;
    if (sid.isEmpty) return;
    final cod = Prefs.getString('codhotelnew');
    final d1 = Prefs.getString('d1');
    await Api.post('$base/hotel/getInfo_planning_apk', body, query: {
      'cod_hotel_New': cod.isEmpty ? '0' : cod,
      'd1': d1.isEmpty ? DateFormat('yyyy-MM-dd').format(DateTime.now()) : d1,
      'session_id_': sid,
    });
  }

  Future<void> _loadArrDep(String base, Map<String, dynamic> body) async {
    final data = await Api.post('$base/hotel/getdataarrdep', body);
    if (data is Map) {
      _arrPrev = _num(data['arr_prev']).toDouble();
      _arr = _num(data['per_arr_prev']).toDouble();
      _depPrev = _num(data['dep_prev']).toDouble();
      _dep = _num(data['per_dep_prev']).toDouble();
    }
    final walk = await Api.post('$base/hotel/getwalknoshow', body);
    if (walk is Map) {
      _walk = _num(walk['walk']).toDouble();
      _noShow = _num(walk['chreserv']).toDouble();
    }
  }

  Future<void> _loadRooms(String base, Map<String, dynamic> body) async {
    final sid = AppConfig.sessionId;
    if (sid.isEmpty) return;
    final data = await Api.post('$base/hotel/getcountch/$sid', body);
    if (data is Map && data.isNotEmpty) {
      _rooms = data.entries
          .map((e) => _RoomRow(_roomLabel(e.key.toString()), _num(e.value)))
          .toList();
    } else {
      _rooms = [];
    }
  }

  Future<void> _loadClients(String base, Map<String, dynamic> body) async {
    final data = await Api.post('$base/hotel/getMovementCl', body);
    _clients = Api.asList(data).map((c) {
      return {...c, 'timeDiff': _timeDiff((c['heure'] ?? '00:00').toString())};
    }).toList();
    _expanded.clear();
    _page = 1;
  }

  Future<void> _loadOccupation(String base, Map<String, dynamic> body) async {
    final sid = AppConfig.sessionId;
    if (sid.isEmpty) return;
    final data =
        await Api.post('$base/hotel/getOccupationPaxDetails/$sid', body);
    _occupation = Api.asList(data);
  }

  static const _apiMappings = [
    ['getcountchlibreProporeList', 'Libre Propre'],
    ['getcountchlibreSalleList', 'Libre Salle'],
    ['getcountchOccupProporeList', 'Occupée Propre'],
    ['getcountchOccupSaleList', 'Occupée Salle'],
    ['getcountReservList', 'Arrivée Effectuée'],
    ['getcountDepartList', 'Départ Effectué'],
    ['getcountOffreList', 'Offre'],
    ['getcountHSList', 'Hors Service'],
  ];

  Future<void> _onRoomRow(int index) async {
    _selectedRow = index;
    if (index < 0 || index >= _apiMappings.length) return;
    final sid = AppConfig.sessionId;
    if (sid.isEmpty) return;
    final endpoint = _apiMappings[index][0];
    final title = _apiMappings[index][1];
    final data = await Api.post(
        '${AppConfig.baseUrlOrDefault}/hotel/$endpoint/$sid',
        AppConfig.pointageBody());
    final list = Api.asList(data);
    _chartData = list;
    _chartTitle = title;
    _chartVisible = list.isNotEmpty;
  }

  num _pieValue(Map<String, dynamic> item) {
    for (final k in [
      'nbrPropore', 'nbrSale', 'nbrocP', 'nbrocS',
      'nbrreserv', 'nbrdep', 'nbroffre', 'nbrHS'
    ]) {
      final v = _num(item[k]);
      if (v != 0) return v;
    }
    return 0;
  }

  // ------------------------------------------------------------------ UI
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: xliaAppBar(
        context,
        title: S.t('homeTitle'),
        date: DateFormat('dd/MM/yyyy').format(DateTime.now()),
        loading: _refreshing,
        onRefresh: _runAll,
        onMenu: widget.onMenu,
      ),
      body: RefreshIndicator(
        onRefresh: _runAll,
        child: ResponsivePage(
          children: [
            if (_error.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(_error, style: const TextStyle(color: Colors.deepOrange)),
              ),
            SectionTitle(S.t('dailyMovement')),
            if (_dataLoaded || _occupation.isNotEmpty) _occupationCard(),
            const SizedBox(height: 16),
            // col-12 col-md-6
            Builder(builder: (context) {
              final two = R.width(context) >= 768;
              final h = two
                  ? 260.0
                  : (R.width(context) * 0.6).clamp(200.0, 300.0).toDouble();
              final a = AppCard(child: _arrDepChart(h));
              final b = AppCard(child: _walkChart(h));
              if (two) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: a),
                    const SizedBox(width: 12),
                    Expanded(child: b),
                  ],
                );
              }
              return Column(children: [a, const SizedBox(height: 12), b]);
            }),
            const SizedBox(height: 16),
            SectionTitle(S.t('clients')),
            _clientsCard(),
            const SizedBox(height: 12),
            PageBar(
                page: _page,
                total: _totalPages,
                onPage: (p) => setState(() => _page = p)),
            const SizedBox(height: 16),
            SectionTitle(S.t('roomStatus')),
            _roomsCard(),
            const SizedBox(height: 16),
            if (_chartVisible) _categoryCard(),
          ],
        ),
      ),
    );
  }

  // ---- daily movement table
  Widget _occupationCard() => AppCard(
        child: FluidTable(
          headers: [
            S.t('label'),
            S.t('room'),
            S.t('occupancyRate'),
            S.t('pax'),
            S.t('occupancyRate'),
          ],
          flex: const [2.2, 1, 1.4, 1, 1.4],
          rows: [
            for (final p in _occupation)
              [
                Text(_titleCase((p['labelle'] ?? '').toString()),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Text((p['chambre'] ?? '').toString()),
                Pill('${p['tau'] ?? 0}%', const Color(0xFFE3F0FF),
                    const Color(0xFF1565C0),
                    center: true),
                Pill('${p['pax'] ?? 0}', const Color(0xFFEEEEEE), Colors.black87),
                Pill('${p['taux'] ?? 0}%', const Color(0xFFEDE7F6),
                    const Color(0xFF6A1B9A),
                    center: true),
              ],
          ],
        ),
      );

  // ---- arrivals / departures bar chart
  Widget _arrDepChart(double h) {
    final labels = ['Arr. Prévues', 'Arr. Effectuées', 'Dep. Prévus', 'Dep. Effectués'];
    final values = [_arrPrev, _arr, _depPrev, _dep];
    final colors = [const Color(0xFFFF9500), const Color(0xFF007BFF)];
    final maxV = values.reduce(max);
    final maxY = maxV <= 0 ? 10.0 : (maxV * 1.2).ceilToDouble();
    final small = R.fluid(context, 0.5, 1.8, 0.7);

    return Column(
      children: [
        Text('Arrivées & Départs',
            style: TextStyle(
                fontSize: R.fluid(context, 0.9, 2.5, 1.15),
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        SizedBox(
          height: h,
          child: BarChart(
            BarChartData(
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
                  getTitlesWidget: (v, meta) => Text(v.toInt().toString(),
                      style: TextStyle(fontSize: small)),
                )),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 44,
                    getTitlesWidget: (v, meta) {
                      final i = v.toInt();
                      if (i < 0 || i >= labels.length) return const SizedBox();
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          '${labels[i]}\n${values[i].toInt()}',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: small),
                        ),
                      );
                    },
                  ),
                ),
              ),
              barGroups: [
                for (var i = 0; i < values.length; i++)
                  BarChartGroupData(x: i, barRods: [
                    BarChartRodData(
                      toY: values[i],
                      width: (R.width(context) * 0.045).clamp(12.0, 24.0).toDouble(),
                      color: colors[i % 2],
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(4)),
                    ),
                  ]),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ---- walk-in / no show donut
  Widget _walkChart(double h) {
    final total = _walk + _noShow;
    final radius = (h * 0.24).clamp(36.0, 60.0).toDouble();
    return Column(
      children: [
        Text('Walk-in & No Show',
            style: TextStyle(
                fontSize: R.fluid(context, 0.9, 2.5, 1.15),
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        SizedBox(
          height: h,
          child: total <= 0
              ? Center(child: Text(S.t('noData')))
              : PieChart(PieChartData(
                  centerSpaceRadius: radius * 0.8,
                  sectionsSpace: 2,
                  sections: [
                    PieChartSectionData(
                      value: _walk,
                      color: const Color(0xFFBB20A0),
                      radius: radius,
                      title: '${(_walk / total * 100).toStringAsFixed(0)}%',
                      titleStyle: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    PieChartSectionData(
                      value: _noShow,
                      color: const Color(0xFF4169E1),
                      radius: radius,
                      title: '${(_noShow / total * 100).toStringAsFixed(0)}%',
                      titleStyle: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ],
                )),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 16,
          runSpacing: 4,
          alignment: WrapAlignment.center,
          children: [
            _legend(const Color(0xFFBB20A0), 'Passagers (Walk-in): ${_walk.toInt()}'),
            _legend(const Color(0xFF4169E1), 'No Show: ${_noShow.toInt()}'),
          ],
        ),
      ],
    );
  }

  Widget _legend(Color c, String t) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(t, style: TextStyle(fontSize: R.fluid(context, 0.65, 1.8, 0.8))),
        ],
      );

  // ---- clients / operations table
  int get _totalPages => max(1, (_clients.length / _perPage).ceil());

  List<Map<String, dynamic>> get _pageItems {
    final start = (_page - 1) * _perPage;
    if (start >= _clients.length) return [];
    return _clients.sublist(start, min(start + _perPage, _clients.length));
  }

  Widget _clientsCard() => AppCard(
        child: FluidTable(
          headers: [
            S.t('status'),
            S.t('roomNumber'),
            S.t('name'),
            S.t('arrival'),
            S.t('departure'),
            S.t('time'),
          ],
          flex: const [1.7, 1, 1.5, 1.2, 1.2, 1.2],
          rows: [
            for (final c in _pageItems)
              () {
                final etat = (c['etat'] ?? '').toString();
                final nom = (c['nom'] ?? '').toString();
                final expanded = _expanded.contains(c);
                final shown = expanded || nom.length <= 7
                    ? nom
                    : '${nom.substring(0, 7)}…';
                return <Widget>[
                  Pill(etat, _statusColor(etat), _statusText(etat)),
                  RoomChip((c['chb'] ?? '').toString()),
                  GestureDetector(
                    onTap: () => setState(() {
                      expanded ? _expanded.remove(c) : _expanded.add(c);
                    }),
                    child: Text(shown,
                        style: const TextStyle(
                            color: Color(0xFF1565C0), fontWeight: FontWeight.w500)),
                  ),
                  DateCell(Icons.login, Colors.green, _fmtDate(c['date_arr'], 'dd/MM')),
                  DateCell(Icons.logout, Colors.red, _fmtDate(c['date_dep'], 'dd/MM')),
                  Pill((c['timeDiff'] ?? '').toString(), const Color(0xFFFFF3E0),
                      const Color(0xFFE65100)),
                ];
              }(),
          ],
        ),
      );

  // ---- room status table
  Widget _roomsCard() => AppCard(
        child: FluidTable(
          headers: [S.t('roomStatus'), S.t('number')],
          flex: const [3, 1],
          selectedRow: _selectedRow,
          onRowTap: (i) async {
            setState(() => _selectedRow = i);
            try {
              await _onRoomRow(i);
            } catch (_) {
              _chartVisible = false;
            }
            if (mounted) setState(() {});
          },
          rows: [
            for (final r in _rooms)
              [
                Text(r.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                Pill('${r.number}', const Color(0xFFECEFF1), Colors.black87,
                    center: true),
              ],
          ],
        ),
      );

  // ---- category pie chart
  Widget _categoryCard() {
    var data = [..._chartData];
    final total = data.fold<num>(0, (a, b) => a + _pieValue(b));
    if (data.length > 20) {
      data.sort((a, b) => _pieValue(b).compareTo(_pieValue(a)));
      final top = data.sublist(0, 19);
      final others = data.sublist(19).fold<num>(0, (a, b) => a + _pieValue(b));
      data = [
        ...top,
        {'cod_categ': 'Autres', 'nbrPropore': others}
      ];
    }

    final rnd = Random(7);
    final entries = data.map((item) {
      final code = (item['cod_categ'] ?? '').toString();
      Color color;
      if (code == 'Autres') {
        color = const Color(0xFFCCCCCC);
      } else if ((_colorMap[code] ?? '').isNotEmpty) {
        color = _hex(_colorMap[code]!, fallback: Colors.blueGrey);
      } else {
        color = Color.fromARGB(
            255, rnd.nextInt(200), rnd.nextInt(200), rnd.nextInt(200));
      }
      return (code: code, value: _pieValue(item), color: color);
    }).toList();

    final h = (R.width(context) * 0.65).clamp(220.0, 340.0).toDouble();
    final radius = (h * 0.3).clamp(60.0, 100.0).toDouble();

    return AppCard(
      child: Column(
        children: [
          Text(S.t('roomCategory'),
              style: TextStyle(
                  fontSize: R.titleFont(context), fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(_chartTitle,
              style: TextStyle(
                  color: Colors.black54, fontSize: R.fluid(context, 0.8, 2.2, 1.0))),
          const SizedBox(height: 12),
          SizedBox(
            height: h,
            child: total <= 0
                ? Center(child: Text(S.t('noData')))
                : PieChart(PieChartData(
                    centerSpaceRadius: radius * 0.5,
                    sectionsSpace: 2,
                    sections: [
                      for (final e in entries)
                        if (e.value > 0)
                          PieChartSectionData(
                            value: e.value.toDouble(),
                            color: e.color,
                            radius: radius,
                            title: (e.value / total * 100) >= 5
                                ? '${(e.value / total * 100).toStringAsFixed(0)}%'
                                : '',
                            titleStyle: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold),
                          ),
                    ],
                  )),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            alignment: WrapAlignment.center,
            children: [
              for (final e in entries)
                _legend(
                    e.color,
                    '${e.code} (${total > 0 ? (e.value / total * 100).toStringAsFixed(1) : '0.0'}%)'),
            ],
          ),
        ],
      ),
    );
  }
}
