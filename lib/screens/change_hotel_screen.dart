import 'dart:async';
import 'package:flutter/material.dart';
import '../core/api_client.dart';
import '../core/app_config.dart';
import '../core/hotels.dart';
import '../core/lang.dart';
import '../core/net.dart';
import '../core/prefs.dart';
import '../core/responsive.dart';
import '../core/session.dart';
import 'settings_screen.dart';

/// Exact port of the Ionic ChangehotelComponent ("Changer la config Pointage").
///
///  * ngOnInit: fetchHotels() -> POST /hotel/getConfigHotel1 (all hotels)
///  * the current hotel is auto-selected and its pointage config re-saved
///  * choosing a hotel in the dropdown saves the pointage config right away
///  * "Confirmer" saves again, shows the success message, then goes back to
///    the app (Ionic: navigate to /menu/home + reload) -> pages reload.
class ChangeHotelScreen extends StatefulWidget {
  const ChangeHotelScreen({super.key});

  @override
  State<ChangeHotelScreen> createState() => _ChangeHotelScreenState();
}

class _ChangeHotelScreenState extends State<ChangeHotelScreen> {
  static const _brand = Color(0xFF2196F3);
  static const _violet = Color(0xFF7E57C2);

  List<Map<String, dynamic>> _hotels = [];
  Map<String, dynamic>? _selected;
  String _currentHotel = '';

  bool _loading = false;
  bool _saving = false;
  String _error = '';
  String _success = '';

  bool get _fr => AppLang.lang.value == 'fr';
  String _t(String fr, String en) => _fr ? fr : en;

  @override
  void initState() {
    super.initState();
    AppLang.lang.addListener(_onLang);
    _currentHotel = Prefs.getString('hotelName');
    _fetchHotels();
  }

  void _onLang() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    AppLang.lang.removeListener(_onLang);
    super.dispose();
  }

  static String _name(Map<String, dynamic> h) =>
      (h['name'] ?? h['namehotel'] ?? '').toString();

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red.shade700 : const Color(0xFF2E7D32),
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
            label: 'OK',
            textColor: Colors.white,
            onPressed: () => ScaffoldMessenger.of(context).hideCurrentSnackBar()),
      ));
  }

  // ------------------------------------------------------------- fetch
  Future<void> _fetchHotels() async {
    final base = AppConfig.baseUrl;
    if (base.isEmpty) {
      setState(() {
        _error = 'Configuration du serveur manquante.';
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final body = AppConfig.initialBody();
      if ((body['url'] as String).isEmpty) body['url'] = AppConfig.defaultUrlpub;
      final res = await Api.post('$base/hotel/getConfigHotel1', body,
          timeout: const Duration(seconds: 15));
      // only the hotels assigned to this user (not all the hotels)
      final list = await Hotels.forCurrentUser(base, Api.asList(res), body: body);
      if (!mounted) return;
      Map<String, dynamic>? found;
      if (_currentHotel.isNotEmpty) {
        for (final h in list) {
          if ((h['name'] ?? '').toString() == _currentHotel ||
              (h['namehotel'] ?? '').toString() == _currentHotel) {
            found = h;
            break;
          }
        }
      }
      setState(() {
        _hotels = list;
        _selected = found;
        _loading = false;
        if (list.isEmpty) _error = 'Aucun hôtel affecté à cet utilisateur';
      });
      if (found != null) _savePointage(found, toast: false); // like Ionic
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _hotels = [];
        _loading = false;
        _error = Net.message(e);
      });
    }
  }

  // -------------------------------------------------------------- save
  /// Ionic savePointageConfig(): pointage_* + hotelName only.
  Future<void> _savePointage(Map<String, dynamic> hotel,
      {bool toast = true}) async {
    final name = _name(hotel).isEmpty ? 'Unknown' : _name(hotel);
    await Prefs.setString('pointage_url', (hotel['urlpub'] ?? '').toString());
    await Prefs.setString(
        'pointage_username', (hotel['hotelport'] ?? '').toString());
    await Prefs.setString(
        'pointage_password', (hotel['password'] ?? '').toString());
    await Prefs.setString('pointageHotelName', name);
    await Prefs.setString('hotelName', name);
    await Prefs.setString('selectedHotel', name);
    if (toast) _toast('Hôtel "$name" sélectionné');
  }

  void _onSelect(String? name) {
    if (name == null) return;
    final h = _hotels.firstWhere((e) => _name(e) == name, orElse: () => {});
    if (h.isEmpty) return;
    setState(() {
      _selected = h;
      _error = '';
      _success = '';
    });
    _savePointage(h);
  }

  Future<void> _onSave() async {
    final hotel = _selected;
    if (hotel == null) {
      const m = 'Veuillez sélectionner un hôtel';
      setState(() => _error = m);
      _toast(m, error: true);
      return;
    }
    setState(() {
      _saving = true;
      _error = '';
      _success = '';
    });
    await _savePointage(hotel, toast: false);
    // data tied to the previous hotel (also the old session id, so no page
    // can run with the previous hotel's session)
    await Prefs.remove('colorMap');
    await Prefs.remove('cachedModules');
    await Prefs.remove('getsiglehotel');
    await Prefs.remove('sessionId');
    await Prefs.remove('saissionid');
    Session.reset();
    if (!mounted) return;
    // Restart IMMEDIATELY: no delay, no message left on screen.
    ScaffoldMessenger.of(context).clearSnackBars();
    Navigator.of(context).pop(SettingsResult.hotelChanged);
  }

  // ---------------------------------------------------------------- UI
  @override
  Widget build(BuildContext context) {
    final selName = _selected == null ? '' : _name(_selected!);
    final currentName = _selected != null
        ? _name(_selected!)
        : (_currentHotel.isEmpty ? 'Aucun' : _currentHotel);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop()),
        title: Text(_t('Changer la config Pointage', 'Change Pointage Config'),
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loading
                  ? null
                  : () {
                      _currentHotel = Prefs.getString('hotelName');
                      _fetchHotels();
                    }),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ListView(
            padding: EdgeInsets.all(R.pagePad(context) < 12 ? 12 : R.pagePad(context)),
            children: [
              if (_success.isNotEmpty)
                _message(_success, Icons.check_circle_outline,
                    const Color(0xFF2E7D32)),
              if (_error.isNotEmpty)
                _message(_error, Icons.error_outline, const Color(0xFFD32F2F)),
              _card(
                icon: Icons.business_outlined,
                iconColor: _brand,
                title: _t('Hôtel actuel:', 'Current Hotel:'),
                subtitle: 'Your active hotel',
                child: Row(children: [
                  const CircleAvatar(
                      radius: 24,
                      backgroundColor: Color(0xFFE3F2FD),
                      child: Icon(Icons.business, color: _brand)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(currentName,
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          _selected != null
                              ? Text(
                                  '${_selected!['urlpub'] ?? ''}:${_selected!['hotelport'] ?? ''}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 12, color: Colors.black54))
                              : const Text('Aucun hôtel sélectionné',
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.black38)),
                        ]),
                  ),
                  if (_selected != null)
                    const Icon(Icons.check_circle, color: Color(0xFF2E7D32)),
                ]),
              ),
              const SizedBox(height: 12),
              _card(
                icon: Icons.list,
                iconColor: _violet,
                title: _t('Changer la config Pointage', 'Change Pointage Config'),
                subtitleWidget: Row(children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                    decoration: BoxDecoration(
                        color: _violet, borderRadius: BorderRadius.circular(10)),
                    child: Text('${_hotels.length}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 6),
                  Text(
                      '${_hotels.length == 1 ? 'hôtel' : 'hôtels'} disponible(s)',
                      style: const TextStyle(fontSize: 12, color: Colors.black54)),
                ]),
                child: _selection(selName),
              ),
              const SizedBox(height: 16),
              if (_selected != null)
                FilledButton.icon(
                  onPressed: _saving ? null : _onSave,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check_circle_outline),
                  label: Text(_saving
                      ? _t('Confirmation...', 'Confirming...')
                      : _t('Confirmer', 'Confirm')),
                  style: FilledButton.styleFrom(
                    backgroundColor: _brand,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back),
                label: Text(_t('Retour', 'Back')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _selection(String selName) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Column(children: [
          CircularProgressIndicator(),
          SizedBox(height: 12),
          Text('Chargement des hôtels...'),
        ]),
      );
    }
    if (_hotels.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(children: [
          const Icon(Icons.business_outlined, size: 40, color: Colors.black38),
          const SizedBox(height: 8),
          Text(_t('Aucun hôtel disponible', 'No hotels available'),
              style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text('Aucun hôtel trouvé pour cet utilisateur',
              style: TextStyle(color: Colors.black54, fontSize: 12)),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _fetchHotels,
            icon: const Icon(Icons.refresh),
            label: Text(_t('Rafraîchir', 'Refresh')),
          ),
        ]),
      );
    }
    // Same view as the login list: outlined field + hotel icon, and a roomy
    // menu (up to 60% of the screen height) instead of a tiny 4-row box.
    return DropdownButtonFormField<String>(
      value: _hotels.any((h) => _name(h) == selName) ? selName : null,
      isExpanded: true,
      menuMaxHeight: MediaQuery.sizeOf(context).height * 0.6,
      borderRadius: BorderRadius.circular(12),
      hint: Text(_t('-- Choisissez un hôtel --', '-- Choose a hotel --')),
      decoration: InputDecoration(
        labelText: _t('Unité', 'Unit'),
        prefixIcon: const Icon(Icons.business_outlined),
        border: const OutlineInputBorder(),
      ),
      items: [
        for (final h in _hotels)
          DropdownMenuItem(
            value: _name(h),
            child: Text(_name(h), overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: _saving ? null : _onSelect,
    );
  }

  Widget _message(String text, IconData icon, Color color) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(color: color))),
        ]),
      );

  Widget _card({
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    Widget? subtitleWidget,
    required Widget child,
  }) =>
      Card(
        elevation: 0,
        color: Colors.white,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              CircleAvatar(
                  backgroundColor: iconColor.withOpacity(0.12),
                  child: Icon(icon, color: iconColor)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                      if (subtitleWidget != null)
                        subtitleWidget
                      else if (subtitle != null)
                        Text(subtitle,
                            style: const TextStyle(
                                fontSize: 12, color: Colors.black54)),
                    ]),
              ),
            ]),
            const SizedBox(height: 14),
            child,
          ]),
        ),
      );
}
