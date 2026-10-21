import 'package:flutter/material.dart';
import '../core/api_client.dart';
import '../core/net.dart';
import '../core/app_config.dart';
import '../core/prefs.dart';
import '../core/responsive.dart';

/// Port of ConfigPage: server address/port + hotel selection.
class ConfigScreen extends StatefulWidget {
  const ConfigScreen({super.key});

  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  final _addrCtrl = TextEditingController();
  final _portCtrl = TextEditingController();

  List<Map<String, dynamic>> _allHotelConfigs = [];
  List<String> _hotels = [];
  String _selectedHotel = '';

  bool _saving = false;
  bool _loadingHotels = false;
  String _error = '';
  String _success = '';

  @override
  void initState() {
    super.initState();
    _addrCtrl.text = Prefs.getString('jarAddress', AppConfig.defaultServer);
    _portCtrl.text = Prefs.getString('jarPort', AppConfig.defaultPort);
    _selectedHotel = Prefs.getString('selectedHotel', AppConfig.defaultHotel);
    if (_addrCtrl.text.isNotEmpty && _portCtrl.text.isNotEmpty) {
      // only auto-fetch when the server was already saved once
      if (AppConfig.hasServerConfig) _fetchAllHotelConfigs();
    }
  }

  @override
  void dispose() {
    _addrCtrl.dispose();
    _portCtrl.dispose();
    super.dispose();
  }

  String get _baseUrl {
    final a = _addrCtrl.text.trim();
    final p = _portCtrl.text.trim();
    if (a.isEmpty || p.isEmpty) return '';
    final clean =
        a.replaceAll(RegExp(r'^https?://'), '').replaceAll(RegExp(r'/+$'), '');
    return 'http://$clean:$p';
  }

  Map<String, dynamic> _initialBody() => {
        'url': Prefs.getString('urlpub', AppConfig.defaultUrlpub),
        'username': Prefs.getString('username', AppConfig.defaultUsername),
        'password': Prefs.getString('password', AppConfig.defaultPassword),
      };

  Future<void> _saveServerConfig() async {
    if (_addrCtrl.text.trim().isEmpty || _portCtrl.text.trim().isEmpty) {
      setState(() => _error = "Veuillez entrer l'adresse et le port du serveur");
      return;
    }
    setState(() {
      _saving = true;
      _error = '';
      _success = '';
    });
    await Prefs.setString('jarAddress', _addrCtrl.text.trim());
    await Prefs.setString('jarPort', _portCtrl.text.trim());
    await Prefs.setString('urlpub', AppConfig.defaultUrlpub);
    await Prefs.setString('username', AppConfig.defaultUsername);
    await Prefs.setString('password', AppConfig.defaultPassword);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _success = 'Configuration du serveur sauvegardée !';
    });
    await _fetchAllHotelConfigs();
  }

  Future<void> _fetchAllHotelConfigs() async {
    final base = _baseUrl;
    if (base.isEmpty) {
      setState(() =>
          _error = "Veuillez d'abord sauvegarder la configuration du serveur");
      return;
    }
    setState(() {
      _loadingHotels = true;
      _error = '';
      _hotels = [];
      _allHotelConfigs = [];
    });
    try {
      final res = await Api.post('$base/hotel/getConfigHotel1', _initialBody(),
          retries: 0);
      final list = Api.asList(res);
      _allHotelConfigs = list;
      _hotels = list
          .map((h) => (h['name'] ?? '').toString())
          .where((n) => n.isNotEmpty)
          .toList();

      if (_hotels.isEmpty) {
        _error = 'Aucun hôtel trouvé';
      } else {
        _success = '${_hotels.length} hôtels trouvés';
        if (_selectedHotel.isEmpty || !_hotels.contains(_selectedHotel)) {
          _selectedHotel = _hotels.first;
        }
        await _saveHotelConfig(silent: true);
      }
    } on ApiException catch (e) {
      _error = Net.message(e);
    } catch (e) {
      _error = Net.message(e);
    }
    if (mounted) setState(() => _loadingHotels = false);
  }

  Future<void> _saveHotelConfig({bool silent = false}) async {
    if (_selectedHotel.isEmpty) {
      setState(() => _error = 'Veuillez sélectionner un hôtel');
      return;
    }
    final target = _selectedHotel.trim().toLowerCase();
    Map<String, dynamic>? cfg;
    for (final h in _allHotelConfigs) {
      if ((h['name'] ?? '').toString().trim().toLowerCase() == target) {
        cfg = h;
        break;
      }
    }
    if (cfg == null) {
      setState(() =>
          _error = 'Configuration de l\'hôtel "$_selectedHotel" non trouvée');
      return;
    }
    final name = (cfg['name'] ?? _selectedHotel).toString();
    await Prefs.setString('selectedHotel', name);
    await Prefs.setString('hotelName', name);
    await Prefs.setString('urlpub', (cfg['urlpub'] ?? '').toString());
    final hp = (cfg['hotelport'] ?? '').toString();
    final pw = (cfg['password'] ?? '').toString();
    await Prefs.setString('username', hp.isEmpty ? AppConfig.defaultUsername : hp);
    await Prefs.setString('password', pw.isEmpty ? AppConfig.defaultPassword : pw);
    if (mounted && !silent) {
      setState(() {
        _error = '';
        _success = 'Hôtel "$name" configuré avec succès !';
      });
    }
  }

  Future<void> _loadDefaults() async {
    _addrCtrl.text = AppConfig.defaultServer;
    _portCtrl.text = AppConfig.defaultPort;
    _selectedHotel = AppConfig.defaultHotel;
    await Prefs.setString('jarAddress', AppConfig.defaultServer);
    await Prefs.setString('jarPort', AppConfig.defaultPort);
    await Prefs.setString('urlpub', AppConfig.defaultUrlpub);
    await Prefs.setString('username', AppConfig.defaultUsername);
    await Prefs.setString('password', AppConfig.defaultPassword);
    await Prefs.setString('selectedHotel', AppConfig.defaultHotel);
    await Prefs.setString('hotelName', AppConfig.defaultHotel);
    if (!mounted) return;
    setState(() {
      _success = 'Configuration par défaut chargée !';
      _error = '';
    });
    await _fetchAllHotelConfigs();
  }

  void _debug() {
    debugPrint('jarAddress: ${Prefs.getString('jarAddress')}');
    debugPrint('jarPort: ${Prefs.getString('jarPort')}');
    debugPrint('selectedHotel: ${Prefs.getString('selectedHotel')}');
    debugPrint('username: ${Prefs.getString('username')}');
    setState(() => _success = 'Config affichée dans la console');
  }

  void _goToLogin() {
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (r) => false);
  }

  // ---------------------------------------------------------------- UI
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(R.width(context) <= 480 ? 12 : 20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: Container(
                  padding: R.width(context) <= 480
                      ? const EdgeInsets.fromLTRB(16, 20, 16, 16)
                      : const EdgeInsets.fromLTRB(24, 30, 24, 24),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.95),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: const [
                      BoxShadow(
                          color: Colors.black26,
                          blurRadius: 40,
                          offset: Offset(0, 20)),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _header(),
                      if (_error.isNotEmpty)
                        _msg(_error, Icons.error_outline, const Color(0xFFFF4757)),
                      if (_success.isNotEmpty)
                        _msg(_success, Icons.check_circle_outline,
                            const Color(0xFF2ED573)),
                      _serverSection(),
                      _hotelSection(),
                      if (_addrCtrl.text.isNotEmpty && _portCtrl.text.isNotEmpty)
                        _currentConfig(),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: _goToLogin,
                        icon: const Icon(Icons.login),
                        label: const Text('Retour à la connexion'),
                        style: _btnStyle(const Color(0xFF667EEA)),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _debug,
                        icon: const Icon(Icons.bug_report_outlined),
                        label: const Text('Debug'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  ButtonStyle _btnStyle(Color c) => FilledButton.styleFrom(
        backgroundColor: c,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      );

  Widget _header() => const Padding(
        padding: EdgeInsets.only(bottom: 24),
        child: Column(
          children: [
            Icon(Icons.settings_outlined, size: 48, color: Color(0xFF667EEA)),
            SizedBox(height: 8),
            Text('Configuration',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
            SizedBox(height: 4),
            Text('Configurez votre connexion au serveur',
                style: TextStyle(fontSize: 14, color: Colors.black54)),
          ],
        ),
      );

  Widget _msg(String text, IconData icon, Color color) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: TextStyle(color: color))),
          ],
        ),
      );

  Widget _section(IconData icon, String title, List<Widget> children) =>
      Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: EdgeInsets.all(R.width(context) <= 480 ? 12 : 16),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.03),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Icon(icon, color: const Color(0xFF667EEA), size: 20),
              const SizedBox(width: 10),
              Text(title,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      );

  InputDecoration _dec(String hint, IconData icon) => InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, color: const Color(0xFF667EEA)),
        filled: true,
        fillColor: Colors.white.withOpacity(0.8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.black.withOpacity(0.06)),
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
      );

  Widget _serverSection() => _section(
        Icons.dns_outlined,
        '1. Configuration du serveur',
        [
          TextField(
            controller: _addrCtrl,
            onChanged: (_) => setState(() {}),
            keyboardType: TextInputType.url,
            decoration: _dec('Adresse IP du serveur (ex: 197.13.4.11)',
                Icons.public),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _portCtrl,
            onChanged: (_) => setState(() {}),
            keyboardType: TextInputType.number,
            decoration: _dec('Port (ex: 8107)', Icons.hub_outlined),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: (_saving ||
                    _addrCtrl.text.trim().isEmpty ||
                    _portCtrl.text.trim().isEmpty)
                ? null
                : _saveServerConfig,
            style: _btnStyle(const Color(0xFF667EEA)),
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Sauvegarder'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _loadDefaults,
            icon: const Icon(Icons.refresh),
            label: const Text('Charger par défaut'),
          ),
        ],
      );

  Widget _hotelSection() => _section(
        Icons.business_outlined,
        "2. Sélection de l'hôtel",
        [
          DropdownButtonFormField<String>(
            value: _hotels.contains(_selectedHotel) ? _selectedHotel : null,
            isExpanded: true,
            decoration: _dec('Sélectionnez un hôtel', Icons.business_outlined),
            items: _hotels
                .map((h) => DropdownMenuItem(value: h, child: Text(h)))
                .toList(),
            onChanged: _loadingHotels
                ? null
                : (v) => setState(() => _selectedHotel = v ?? ''),
          ),
          if (_hotels.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('${_hotels.length} hôtel(s) disponible(s)',
                  style: const TextStyle(fontSize: 12, color: Colors.black54)),
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: (_loadingHotels ||
                    _addrCtrl.text.trim().isEmpty ||
                    _portCtrl.text.trim().isEmpty)
                ? null
                : _fetchAllHotelConfigs,
            icon: _loadingHotels
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
            label: Text(_loadingHotels ? 'Chargement...' : 'Rafraîchir les hôtels'),
            style: _btnStyle(const Color(0xFF5B6BC0)),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _selectedHotel.isEmpty ? null : () => _saveHotelConfig(),
            style: _btnStyle(const Color(0xFF764BA2)),
            child: const Text("Sauvegarder l'hôtel"),
          ),
        ],
      );

  Widget _currentConfig() => _section(
        Icons.check_circle_outline,
        'Configuration actuelle',
        [
          _kv('Serveur:', '${_addrCtrl.text}:${_portCtrl.text}'),
          if (_selectedHotel.isNotEmpty) _kv('Hôtel sélectionné:', _selectedHotel),
          _kv('Hôtels disponibles:', '${_hotels.length}'),
        ],
      );

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(k, style: const TextStyle(color: Colors.black54)),
            Flexible(
                child: Text(v,
                    textAlign: TextAlign.end,
                    style: const TextStyle(fontWeight: FontWeight.w600))),
          ],
        ),
      );
}
