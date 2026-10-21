import 'dart:async';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../core/api_client.dart';
import '../core/net.dart';
import '../core/app_config.dart';
import '../core/hotels.dart';
import '../core/lang.dart';
import '../core/prefs.dart';
import '../core/responsive.dart';

/// Port of LoginPage (chatbot + weather widget are not ported yet).
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _idCtrl = TextEditingController();
  final _pwdCtrl = TextEditingController();

  bool _obscure = true;
  bool _remember = false;
  bool _loading = false;
  bool _fetchingHotels = false;
  bool _noHotels = false;
  String _error = '';
  String _success = '';

  List<Map<String, dynamic>> _hotels = []; // user's hotels (namehotel)
  List<Map<String, dynamic>> _allConfigs = []; // /hotel/getConfigHotel1
  String _selectedHotel = '';
  Map<String, dynamic>? _selectedConfig;
  String? _currentUserId;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    AppLang.lang.addListener(_onLang);
    _restoreSaved();
    _restoreCachedHotels();
    _loadAllHotelConfigs();
    if (_idCtrl.text.trim().isNotEmpty) _loadHotelsForUser();
  }

  void _onLang() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    AppLang.lang.removeListener(_onLang);
    _debounce?.cancel();
    _idCtrl.dispose();
    _pwdCtrl.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------ helpers
  void _restoreSaved() {
    final remember = Prefs.getBool('rememberMe');
    if (remember) {
      _idCtrl.text = Prefs.getString('emailOrTelephone');
      _pwdCtrl.text = Prefs.getString('savedPassword');
      _selectedHotel = Prefs.getString('selectedHotel');
      _remember = true;
    }
  }

  /// Last list shown for the remembered identifier (instant, before the call).
  void _restoreCachedHotels() {
    if (_idCtrl.text.trim().isEmpty) return;
    try {
      final raw = Prefs.getString('loginHotels');
      if (raw.isEmpty) return;
      // never show another user's cached hotels
      if (Prefs.getString('loginHotelsFor') != _idCtrl.text.trim()) return;
      final l = Hotels.visible((jsonDecode(raw) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList());
      if (l.isNotEmpty) {
        _hotels = l;
        _hotelsFor = _idCtrl.text.trim();
        if (!l.any((h) => h['namehotel'] == _selectedHotel)) {
          _selectedHotel = (l.first['namehotel'] ?? '').toString();
        }
      }
    } catch (_) {}
  }

  String _handleError(Object e) {
    return Net.message(e);
  }

  Future<void> _loadAllHotelConfigs() async {
    final base = AppConfig.baseUrl;
    if (base.isEmpty) return;
    try {
      final res = await Api.post(
          '$base/hotel/getConfigHotel1', AppConfig.initialBody());
      _allConfigs = Api.asList(res);
    } catch (e) {
      _allConfigs = [];
      if (mounted) setState(() => _error = _handleError(e));
    }
  }

  void _onCredentialsChanged() {
    _debounce?.cancel();
    if (_hotels.isNotEmpty &&
        _hotelsFor.isNotEmpty &&
        _idCtrl.text.trim() != _hotelsFor) {
      setState(() {
        _hotels = [];
        _noHotels = false;
      });
    }
    if (_idCtrl.text.trim().isEmpty) {
      if (_hotels.isNotEmpty || _noHotels) {
        setState(() {
          _hotels = [];
          _noHotels = false;
        });
      }
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 800), _loadHotelsForUser);
  }

  Future<Map<String, dynamic>?> _findUser(String base) async {
    final res =
        await Api.post('$base/hotel/getlistuser', AppConfig.initialBody());
    final users = Api.asList(res);
    final id = _idCtrl.text.trim();
    for (final u in users) {
      if (u['email']?.toString() == id || u['telephone']?.toString() == id) {
        return u;
      }
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> _getUserHotels(String base) async {
    final res = await Api.post(
        '$base/hotel/getConfigHotelbyemail/$_currentUserId',
        AppConfig.initialBody());
    return Hotels.visible(Api.asList(res)); // "App Mobile" = config page only
  }

  String _hotelsFor = ''; // identifier the current list belongs to
  int _hotelRetry = 0;

  /// The list of hotels is fetched as soon as the identifier is typed (no need
  /// for the password), kept while typing, re-fetched if the identifier changed
  /// during the call, and retried by itself when the server does not answer.
  Future<void> _loadHotelsForUser() async {
    final id = _idCtrl.text.trim();
    if (id.isEmpty) return;
    if (_fetchingHotels) return; // finally{} re-runs it if the id changed
    final base = AppConfig.baseUrl;
    if (base.isEmpty) return;
    setState(() {
      _fetchingHotels = true;
      _noHotels = false;
    });
    var failed = false;
    try {
      final user = await _findUser(base);
      if (!mounted) return;
      if (user == null) {
        setState(() {
          _hotels = [];
          _noHotels = false;
          _hotelsFor = '';
        });
      } else {
        _currentUserId = user['id'].toString();
        final hotels = await _getUserHotels(base);
        if (!mounted) return;
        _hotelRetry = 0;
        setState(() {
          _hotels = hotels;
          _hotelsFor = id;
          _noHotels = hotels.isEmpty;
          if (hotels.isNotEmpty) {
            _error = '';
            final saved = Prefs.getString('selectedHotel');
            _selectedHotel = hotels.any((h) => h['namehotel'] == saved)
                ? saved
                : (hotels.first['namehotel'] ?? '').toString();
          }
        });
        if (hotels.isNotEmpty) {
          Prefs.setString('loginHotels', jsonEncode(hotels));
          Prefs.setString('loginHotelsFor', id);
          _applyHotelConfig();
        }
      }
    } catch (e) {
      failed = true; // keep the list already shown (same identifier only)
      if (mounted && _hotelsFor != id && _hotels.isNotEmpty) {
        setState(() => _hotels = []);
      }
    } finally {
      if (mounted) {
        setState(() => _fetchingHotels = false);
        if (_idCtrl.text.trim().isNotEmpty &&
            (_idCtrl.text.trim() != id ||
                (failed && _hotelRetry < 3))) {
          if (failed) _hotelRetry++;
          _debounce?.cancel();
          _debounce = Timer(Duration(seconds: failed ? 3 : 0), _loadHotelsForUser);
        }
      }
    }
  }

  /// Stores pointage_* config of the selected hotel.
  void _applyHotelConfig() {
    if (_selectedHotel.isEmpty) return;
    final target = _selectedHotel.trim().toLowerCase();
    Map<String, dynamic>? cfg;
    for (final h in _allConfigs) {
      final n = (h['name'] ?? '').toString().trim().toLowerCase();
      final nh = (h['namehotel'] ?? '').toString().trim().toLowerCase();
      if (n == target || nh == target) {
        cfg = h;
        break;
      }
    }
    if (cfg == null) {
      setState(() => _error = S.t('hotelConfigMissing'));
      return;
    }
    _selectedConfig = cfg;
    final name = (cfg['name'] ?? cfg['namehotel'] ?? _selectedHotel).toString();
    final url = (cfg['urlpub'] ?? '').toString();
    final user = (cfg['hotelport'] ?? '').toString();
    final pass = (cfg['password'] ?? '').toString();
    if (url.isNotEmpty) Prefs.setString('pointage_url', url);
    Prefs.setString(
        'pointage_username', user.isEmpty ? AppConfig.defaultUsername : user);
    Prefs.setString(
        'pointage_password', pass.isEmpty ? AppConfig.defaultPassword : pass);
    Prefs.setString('pointageHotelName', name);
    Prefs.setString('selectedHotel', _selectedHotel);
    if (mounted) setState(() => _error = '');
  }

  // -------------------------------------------------------------- login
  Future<void> _login() async {
    if (_loading) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _error = '';
      _success = '';
      _loading = true;
    });

    try {
      final id = _idCtrl.text.trim();
      final pwd = _pwdCtrl.text;
      if (id.isEmpty || pwd.isEmpty) {
        setState(() => _error = S.t('fillFields'));
        return;
      }

      // Admin shortcut: "sup" + admin password -> config screen
      if (id.toLowerCase() == AppConfig.adminUser &&
          pwd == AppConfig.adminPassword) {
        Navigator.of(context).pushReplacementNamed('/config');
        return;
      }

      final base = AppConfig.baseUrl;
      if (base.isEmpty) {
        setState(() => _error = S.t('configError'));
        return;
      }

      final md5pwd = md5.convert(utf8.encode(pwd)).toString();

      // 1. find user
      final user = await _findUser(base);
      if (user == null) {
        setState(() => _error = S.t('invalidCredentials'));
        return;
      }
      _currentUserId = user['id'].toString();

      // 2. authenticate
      final loginRes = await Api.post('$base/api/usersmob/login', {
        'emailOrTelephone': id,
        'password': md5pwd,
      });
      if (loginRes is! Map || loginRes['user'] == null) {
        setState(() => _error = S.t('invalidPassword'));
        return;
      }

      // 3. hotels
      final hotels = await _getUserHotels(base);
      if (hotels.isEmpty) {
        setState(() => _error = S.t('noHotels'));
        return;
      }
      _hotels = hotels;
      if (_selectedHotel.isEmpty ||
          !hotels.any((h) => h['namehotel'] == _selectedHotel)) {
        _selectedHotel = (hotels.first['namehotel'] ?? '').toString();
      }
      if (_allConfigs.isEmpty) await _loadAllHotelConfigs();
      _applyHotelConfig();
      if (_selectedConfig == null) {
        setState(() => _error = S.t('selectHotel'));
        return;
      }

      // 4. session data
      final session =
          await Api.post('$base/hotel/GetDataproce', AppConfig.pointageBody());
      final sessionId = session is Map
          ? (session['saissionid'] ??
              session['sessionid'] ??
              session['sessionId'] ??
              session['sessionID'])
          : null;
      if (sessionId == null || sessionId.toString().isEmpty) {
        setState(() => _error = S.t('sessionError'));
        return;
      }

      await _saveLoginData(loginRes['user'].toString(), session as Map);
      await _saveCredentials();

      if (!mounted) return;
      setState(() => _success = S.t('success'));
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/menu');
    } catch (e) {
      if (mounted) setState(() => _error = _handleError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveLoginData(String userId, Map s) async {
    String v(String k) => (s[k] ?? '').toString();
    final sessionId = (s['saissionid'] ??
            s['sessionid'] ??
            s['sessionId'] ??
            s['sessionID'] ??
            '')
        .toString();

    await Prefs.setString('userId', userId);
    await Prefs.setString('userDbId', _currentUserId ?? '');
    await Prefs.setString('loginId', _idCtrl.text.trim());
    await Prefs.setString('sessionId', sessionId);
    for (final k in [
      'codhotelnew', 'd1', 'six', 'firstday', 'lastday', 'anncom', 'setHier',
      'hierPass', 'dd', 'nomhotel', 'getsiglehotel', 'codagence', 'tom',
      'dayly1', 'dayly', 'tomm', 'device', 'dateimputcontrol'
    ]) {
      await Prefs.setString(k, v(k));
    }
    await Prefs.setString(
        'lastChangeTimestamp', DateTime.now().millisecondsSinceEpoch.toString());
    await Prefs.setString('isLoggedIn', 'true');
    await Prefs.remove('justLoggedOut');
  }

  Future<void> _saveCredentials() async {
    if (_remember) {
      await Prefs.setString('emailOrTelephone', _idCtrl.text.trim());
      await Prefs.setString('savedPassword', _pwdCtrl.text);
      await Prefs.setString('selectedHotel', _selectedHotel);
      await Prefs.setBool('rememberMe', true);
    } else {
      await Prefs.remove('emailOrTelephone');
      await Prefs.remove('savedPassword');
      await Prefs.setBool('rememberMe', false);
    }
  }

  // ----------------------------------------------------------------- UI
  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 768;
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: SafeArea(
        child: Row(
          children: [
            if (wide) Expanded(child: _leftPanel()),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(R.width(context) <= 576 ? 8 : 16),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: _formCard(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _leftPanel() => Container(
        color: Theme.of(context).colorScheme.primary,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset('assets/images/xliaarab.png', width: 120),
              const SizedBox(height: 16),
              Text(S.t('welcome'),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(S.t('welcomeSub'),
                  style: const TextStyle(color: Colors.white70, fontSize: 17)),
            ],
          ),
        ),
      );

  Widget _alert(String text, IconData icon, Color color) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          border: Border.all(color: color.withOpacity(0.4)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(color: color))),
        ]),
      );

  Widget _formCard() {
    final primary = Theme.of(context).colorScheme.primary;
    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        // Ionic: 1.5rem (<=768) / 1rem (<=576)
        padding: EdgeInsets.all(R.width(context) <= 576 ? 16 : 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Image.asset('assets/images/logo_xlia.png', height: 60),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(S.t('loginTitle'),
                  style: TextStyle(
                      fontSize: R.width(context) <= 576 ? 20 : 22,
                      fontWeight: FontWeight.bold,
                      color: primary)),
            ),
            Center(
              child: Text(S.t('loginSub'),
                  style: const TextStyle(color: Colors.black54, fontSize: 13)),
            ),
            const SizedBox(height: 20),
            if (_error.isNotEmpty)
              _alert(_error, Icons.error_outline, Colors.red.shade700),
            if (_success.isNotEmpty)
              _alert(_success, Icons.check_circle_outline, Colors.green.shade700),

            // language
            DropdownButtonFormField<String>(
              value: AppLang.lang.value,
              decoration: InputDecoration(
                labelText: S.t('language'),
                prefixIcon: const Icon(Icons.language),
                border: const OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'fr', child: Text('🇫🇷 Français')),
                DropdownMenuItem(value: 'en', child: Text('🇬🇧 English')),
              ],
              onChanged: (v) {
                if (v != null) AppLang.set(v);
              },
            ),
            const SizedBox(height: 14),

            // identifier
            TextField(
              controller: _idCtrl,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.username],
              onChanged: (_) => _onCredentialsChanged(),
              decoration: InputDecoration(
                labelText: S.t('identifier'),
                hintText: S.t('identifierPlaceholder'),
                prefixIcon: const Icon(Icons.mail_outline),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),

            // password
            TextField(
              controller: _pwdCtrl,
              obscureText: _obscure,
              autofillHints: const [AutofillHints.password],
              onChanged: (_) {
                setState(() {});
                _onCredentialsChanged();
              },
              onSubmitted: (_) => _login(),
              decoration: InputDecoration(
                labelText: S.t('password'),
                hintText: S.t('passwordPlaceholder'),
                prefixIcon: const Icon(Icons.vpn_key_outlined),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_obscure
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // hotels
            if (_fetchingHotels)
              const Padding(
                padding: EdgeInsets.only(bottom: 14),
                child: LinearProgressIndicator(),
              ),
            if (_hotels.isNotEmpty) ...[
              DropdownButtonFormField<String>(
                value: _hotels.any((h) => h['namehotel'] == _selectedHotel)
                    ? _selectedHotel
                    : null,
                isExpanded: true,
                hint: Text(S.t('chooseUnit')),
                decoration: InputDecoration(
                  labelText: S.t('unit'),
                  prefixIcon: const Icon(Icons.business_outlined),
                  border: const OutlineInputBorder(),
                ),
                items: _hotels
                    .map((h) => DropdownMenuItem<String>(
                          value: (h['namehotel'] ?? '').toString(),
                          child: Text((h['namehotel'] ?? '').toString(),
                              overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _selectedHotel = v);
                  Prefs.setString('selectedHotel', v);
                  _applyHotelConfig();
                },
              ),
              const SizedBox(height: 14),
            ],
            if (_noHotels)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.warning_amber_outlined,
                        size: 18, color: Colors.black54),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(S.t('noUnits'),
                          style: const TextStyle(color: Colors.black54)),
                    ),
                  ],
                ),
              ),

            // login button
            FilledButton.icon(
              onPressed: (_idCtrl.text.isEmpty || _pwdCtrl.text.isEmpty || _loading)
                  ? null
                  : _login,
              style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14)),
              icon: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.login),
              label: Text(_loading ? S.t('loggingIn') : S.t('login'),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              value: _remember,
              onChanged: (v) => setState(() => _remember = v ?? false),
              title: Text(S.t('rememberMe'),
                  style: const TextStyle(color: Colors.black54)),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                '${S.t('rights')} © ${DateTime.now().year} XLiaMobile',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
