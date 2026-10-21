import 'dart:convert';
import 'package:flutter/material.dart';
import '../core/api_client.dart';
import '../core/app_config.dart';
import '../core/lang.dart';
import '../core/net.dart';
import '../core/prefs.dart';
import '../core/responsive.dart';
import '../core/session.dart';
import 'ca_screen.dart';
import 'home_screen.dart';
import 'listes_screen.dart';
import 'placeholder_screen.dart';
import 'previsions_screen.dart';
import 'pv_screen.dart';
import 'settings_screen.dart';
import 'stat_revenues_screen.dart';
import 'tiers_screen.dart';

class DrawerItem {
  final String name;
  final String icon;
  final String? url;
  final String badge;
  const DrawerItem(
      {required this.name, required this.icon, this.url, this.badge = ''});

  Map<String, dynamic> toJson() =>
      {'name': name, 'icon': icon, 'url': url, 'badge': badge};

  factory DrawerItem.fromJson(Map<String, dynamic> j) => DrawerItem(
        name: (j['name'] ?? 'Unnamed').toString(),
        icon: (j['icon'] ?? 'radio-button-off').toString(),
        url: (j['url'] == null || j['url'].toString().isEmpty)
            ? null
            : j['url'].toString(),
        badge: (j['badge'] ?? '').toString(),
      );
}

/// Maps the Material icon names sent by the server to Flutter icons.
IconData iconFromName(String name) {
  const map = <String, IconData>{
    'dashboard': Icons.dashboard,
    'hotel': Icons.hotel,
    'group': Icons.group,
    'groups': Icons.groups,
    'people': Icons.people,
    'person': Icons.person,
    'timeline': Icons.timeline,
    'assessment': Icons.assessment,
    'receipt': Icons.receipt,
    'receipt_long': Icons.receipt_long,
    'business': Icons.business,
    'settings': Icons.settings,
    'home': Icons.home,
    'bed': Icons.bed,
    'bar_chart': Icons.bar_chart,
    'pie_chart': Icons.pie_chart,
    'show_chart': Icons.show_chart,
    'trending_up': Icons.trending_up,
    'euro': Icons.euro,
    'attach_money': Icons.attach_money,
    'payments': Icons.payments,
    'account_balance': Icons.account_balance,
    'swap_horiz': Icons.swap_horiz,
    'flight_land': Icons.flight_land,
    'flight_takeoff': Icons.flight_takeoff,
    'list': Icons.list,
    'list_alt': Icons.list_alt,
    'help': Icons.help_outline,
    'feedback': Icons.feedback,
    'share': Icons.share,
    'info': Icons.info_outline,
    'event': Icons.event,
    'calendar_today': Icons.calendar_today,
    'star': Icons.star,
    'domain': Icons.domain,
    'apartment': Icons.apartment,
    'analytics': Icons.analytics,
    'insights': Icons.insights,
    'stat & revenus': Icons.insights,
    'revenus': Icons.insights,
    'stat': Icons.query_stats,
    'radio-button-off': Icons.radio_button_off,
    'radio_button_off': Icons.radio_button_off,
  };
  return map[name] ?? map[name.trim().toLowerCase()] ?? Icons.radio_button_unchecked;
}

/// url of the "Stat & Revenus" module (same value as in the modules table).
const String statRevUrl = '/menu/Revenus';

bool _isStatRev(DrawerItem p) =>
    (p.url ?? '').toLowerCase() == statRevUrl.toLowerCase();

/// "Stat & Revenus" always sits right after "CA". If the server menu already
/// has it (modules table) it is moved there; if not, it is added locally.
List<DrawerItem> withStatRev(List<DrawerItem> pages) {
  final existing = pages.where(_isStatRev).toList();
  final out = pages.where((p) => !_isStatRev(p)).toList();
  final item = existing.isNotEmpty
      ? existing.first
      : const DrawerItem(
          name: 'Stat & Revenus', icon: 'insights', url: statRevUrl);
  final ca = out.indexWhere((p) => p.url == '/menu/feedback');
  out.insert(ca >= 0 ? ca + 1 : out.length, item);
  return out;
}

/// url sent by the server -> Flutter screen. Add new ported screens here.
Widget buildPage(DrawerItem item, VoidCallback? onMenu) {
  switch (item.url) {
    case '/menu/home':
      return HomeScreen(key: const ValueKey('home'), onMenu: onMenu);
    case '/menu/listes':
      return ListesScreen(key: const ValueKey('listes'), onMenu: onMenu);
    case '/menu/help': // "Previsions"
      return PrevisionsScreen(key: const ValueKey('previsions'), onMenu: onMenu);
    case '/menu/invitefriend': // "Etat tiers"
      return TiersScreen(key: const ValueKey('tiers'), onMenu: onMenu);
    case '/menu/recaptilatif': // "PV"
      return PvScreen(key: const ValueKey('pv'), onMenu: onMenu);
    case '/menu/feedback': // "CA"
      return CaScreen(key: const ValueKey('ca'), onMenu: onMenu);
    case '/menu/Revenus': // "Stat & Revenus" (static report)
    case '/menu/revenus':
      return StatRevenuesScreen(key: const ValueKey('statrev'), onMenu: onMenu);
    default:
      return PlaceholderScreen(
          key: ValueKey(item.name), title: item.name, onMenu: onMenu);
  }
}

class DrawerShell extends StatefulWidget {
  const DrawerShell({super.key});

  @override
  State<DrawerShell> createState() => _DrawerShellState();
}

class _DrawerShellState extends State<DrawerShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  List<DrawerItem> _pages = [];
  int _active = 0;
  bool _loading = true;
  String _apiError = '';
  String _hotelName = '';
  String _sigle = '';
  int _pageEpoch = 0; // bumped when the hotel changes -> pages are rebuilt

  @override
  void initState() {
    super.initState();
    AppLang.lang.addListener(_onLang);
    Net.reconnectTick.addListener(_onReconnected);
    if (Prefs.getString('userId').isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) =>
          Navigator.of(context).pushReplacementNamed('/login'));
      return;
    }
    _hotelName = Prefs.getString('hotelName', Prefs.getString('nomhotel'));
    _sigle = Prefs.getString('getsiglehotel');
    _fetchHotelName();
    _fetchModules();
  }

  void _onLang() {
    if (mounted) setState(() {});
  }

  /// Connection is back after an outage: reconnect everything by itself
  /// (new session, menu, and the current page reloads its data).
  void _onReconnected() {
    if (!mounted || Prefs.getString('userId').isEmpty) return;
    Session.reset();
    setState(() {
      _apiError = '';
      _pageEpoch++; // rebuild current page -> it fetches again
    });
    _fetchHotelName();
    if (_apiError.isNotEmpty || _pages.length <= 2) _fetchModules();
  }

  @override
  void dispose() {
    AppLang.lang.removeListener(_onLang);
    Net.reconnectTick.removeListener(_onReconnected);
    super.dispose();
  }

  Future<void> _fetchHotelName() async {
    try {
      // shared with the data pages: one GetDataproce call at a time, so the
      // session id can never change in the middle of a page load
      final res = await Session.load();
      final nom = (res['nomhotel'] ?? '').toString();
      final sigle = (res['getsiglehotel'] ?? '').toString();
      if (mounted) {
        setState(() {
          if (nom.isNotEmpty) _hotelName = nom;
          if (sigle.isNotEmpty) _sigle = sigle;
        });
      }
    } catch (_) {
      // keep cached name
    }
  }

  Future<void> _fetchModules() async {
    final userId = Prefs.getString('userId');
    final body = AppConfig.pointageBody();
    if ((body['url'] as String).isEmpty) {
      _setFallback('Missing database configuration');
      return;
    }
    try {
      final res = await Api.post(
          '${AppConfig.baseUrlOrDefault}/api/module/user/$userId', body);
      final list = Api.asList(res);
      if (list.isEmpty) {
        _setFallback('');
        return;
      }
      final pages = withStatRev(list.map(DrawerItem.fromJson).toList());
      await Prefs.setString(
          'cachedModules', jsonEncode(pages.map((e) => e.toJson()).toList()));
      final stored = Prefs.getString('selectedTab');
      final idx = pages.indexWhere((p) => p.name == stored);
      if (!mounted) return;
      setState(() {
        _pages = pages;
        _active = idx >= 0 ? idx : 0;
        _loading = false;
        _apiError = '';
      });
    } catch (e) {
      // try cached modules first
      final cached = Prefs.getString('cachedModules');
      if (cached.isNotEmpty) {
        try {
          var parsed = (jsonDecode(cached) as List)
              .map((e) => DrawerItem.fromJson(Map<String, dynamic>.from(e)))
              .toList();
          parsed = withStatRev(parsed);
          if (parsed.isNotEmpty && mounted) {
            setState(() {
              _pages = parsed;
              _active = 0;
              _loading = false;
              _apiError = Net.message(e);
            });
            return;
          }
        } catch (_) {}
      }
      _setFallback(Net.message(e));
    }
  }

  void _setFallback(String err) {
    if (!mounted) return;
    setState(() {
      _pages = withStatRev(const [
        DrawerItem(name: 'Etat Hotel', icon: 'hotel', url: '/menu/home'),
        DrawerItem(name: 'Dashboard', icon: 'dashboard', url: '/dashboard'),
      ]);
      _active = 0;
      _loading = false;
      _apiError = err;
    });
  }

  Future<void> _logout() async {
    await Prefs.remove('userId');
    await Prefs.remove('sessionId');
    await Prefs.remove('isLoggedIn');
    await Prefs.remove('selectedTab');
    await Prefs.remove('hotelName');
    await Prefs.remove('getsiglehotel');
    await Prefs.remove('cachedModules');
    await Prefs.remove('loginId');
    await Prefs.remove('colorMap');
    if (!Prefs.getBool('rememberMe')) {
      await Prefs.remove('emailOrTelephone');
      await Prefs.remove('savedPassword');
      await Prefs.remove('selectedHotel');
    }
    await Prefs.setString('justLoggedOut', 'true');
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (r) => false);
  }

  void _select(int i, {required bool closeDrawer}) {
    setState(() => _active = i);
    Prefs.setString('selectedTab', _pages[i].name);
    if (closeDrawer) Navigator.of(context).pop();
  }

  Future<void> _openSettings({required bool closeDrawer}) async {
    if (closeDrawer) Navigator.of(context).pop();
    final res = await Navigator.of(context).push<SettingsResult>(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
    if (!mounted) return;
    switch (res) {
      case SettingsResult.logout:
        await _logout();
        break;
      case SettingsResult.hotelChanged:
        // new hotel -> new header, new menu, and every page reloads its data
        ScaffoldMessenger.of(context).clearSnackBars();
        Session.reset();
        setState(() {
          _hotelName = Prefs.getString('hotelName');
          _sigle = '';
          _loading = true;
          _pageEpoch++;
        });
        _fetchHotelName();
        _fetchModules();
        break;
      default:
        break;
    }
  }

  // ----------------------------------------------------------------- UI
  @override
  Widget build(BuildContext context) {
    final wide = R.desktop(context); // >= 1024 : split pane

    final page = _loading || _pages.isEmpty
        ? const Center(child: CircularProgressIndicator())
        : KeyedSubtree(
            key: ValueKey('epoch$_pageEpoch'),
            child: buildPage(
              _pages[_active],
              wide ? null : () => _scaffoldKey.currentState?.openDrawer(),
            ),
          );

    if (wide) {
      return Scaffold(
        key: _scaffoldKey,
        body: Row(
          children: [
            SizedBox(width: 300, child: _menu(closeDrawer: false)), // 300px >=1024
            const VerticalDivider(width: 1),
            Expanded(child: page),
          ],
        ),
      );
    }
    return Scaffold(
      key: _scaffoldKey,
      drawer: Drawer(
        // Ionic: min(75% of width, 320) and 280 on <=768
        width: (R.width(context) * 0.75)
            .clamp(0.0, R.mobile(context) ? 280.0 : 320.0)
            .toDouble(),
        child: _menu(closeDrawer: true),
      ),
      body: page,
    );
  }

  Widget _menu({required bool closeDrawer}) {
    const primary = Color(0xFF2196F3);
    const primaryDark = Color(0xFF1976D2);
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        children: [
          // header
          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(
                R.mobile(context) ? 16 : 24, MediaQuery.of(context).padding.top + (R.mobile(context) ? 24 : 40), R.mobile(context) ? 16 : 24, 20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [primary, primaryDark],
              ),
            ),
            child: Column(
              children: [
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white70, width: 2),
                  ),
                  child: ClipOval(
                    child: SizedBox(
                        width: 72, height: 72, child: _hotelImage(_sigle)),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _hotelName.isEmpty ? S.t('guest') : _hotelName,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(S.t('member'),
                    style: const TextStyle(color: Colors.white70, fontSize: 13)),
              ],
            ),
          ),
          if (_apiError.isNotEmpty)
            Container(
              width: double.infinity,
              color: Colors.orange.withOpacity(0.15),
              padding: const EdgeInsets.all(8),
              child: Text(_apiError,
                  style: const TextStyle(fontSize: 11, color: Colors.deepOrange)),
            ),
          // items
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    children: [
                      for (var i = 0; i < _pages.length; i++)
                        _navTile(i, closeDrawer),
                      const Divider(height: 24),
                      ListTile(
                        leading: const Icon(Icons.settings_outlined),
                        title: Text(S.t('settings')),
                        onTap: () => _openSettings(closeDrawer: closeDrawer),
                      ),
                      ListTile(
                        leading: const Icon(Icons.logout, color: Colors.red),
                        title: Text(S.t('logout'),
                            style: const TextStyle(color: Colors.red)),
                        onTap: _logout,
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _navTile(int i, bool closeDrawer) {
    final p = _pages[i];
    final active = i == _active;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: active ? const Color(0xFF2196F3) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: ListTile(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          leading: Icon(iconFromName(p.icon),
              color: active ? Colors.white : Colors.black54),
          title: Text(p.name,
              style: TextStyle(
                  color: active ? Colors.white : Colors.black87,
                  fontWeight: active ? FontWeight.w600 : FontWeight.normal)),
          trailing: p.badge.isEmpty
              ? null
              : Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                      color: Colors.redAccent,
                      borderRadius: BorderRadius.circular(10)),
                  child: Text(p.badge,
                      style:
                          const TextStyle(color: Colors.white, fontSize: 11)),
                ),
          onTap: () => _select(i, closeDrawer: closeDrawer),
        ),
      ),
    );
  }

  /// `getsiglehotel` can be an http URL, a data URI or raw base64.
  Widget _hotelImage(String s) {
    const fallback = Image(
        image: AssetImage('assets/images/default-avatar.png'),
        fit: BoxFit.cover);
    if (s.isEmpty) return fallback;
    try {
      if (s.startsWith('http')) {
        return Image.network(s,
            fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback);
      }
      final b64 = s.contains(',') ? s.split(',').last : s;
      return Image.memory(base64Decode(b64.trim()),
          fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback);
    } catch (_) {
      return fallback;
    }
  }
}
