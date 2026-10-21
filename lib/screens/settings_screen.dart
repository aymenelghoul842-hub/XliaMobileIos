import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../core/app_config.dart';
import '../core/lang.dart';
import '../core/prefs.dart';
import '../core/responsive.dart';
import 'change_hotel_screen.dart';

/// What the drawer must do after the settings screen is closed.
enum SettingsResult { none, hotelChanged, logout }

/// Port of the Ionic SettingsComponent + ChangeHotelComponent + password change.
///
///  * profile + current hotel
///  * change hotel   (list of the user's hotels -> saves pointage_* config)
///  * change password (PUT /api/users/modif-password, same rules as Ionic)
///  * language FR / EN
///  * logout
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _blue = Color(0xFF2196F3);
  static const _blueDark = Color(0xFF1976D2);

  String _currentHotel = '';

  bool get _fr => AppLang.lang.value == 'fr';
  String _t(String fr, String en) => _fr ? fr : en;

  String get _loginId {
    for (final k in ['loginId', 'emailOrTelephone']) {
      final v = Prefs.getString(k);
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  @override
  void initState() {
    super.initState();
    AppLang.lang.addListener(_onLang);
    _currentHotel = Prefs.getString('hotelName', Prefs.getString('nomhotel'));
  }

  void _onLang() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    AppLang.lang.removeListener(_onLang);
    super.dispose();
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red.shade700 : null,
      ));
  }

  // ------------------------------------------------------------ hotels
  /// Ionic onChangeHotel(): simple redirect to the change-hotel page.
  Future<void> _changeHotel() async {
    final res = await Navigator.of(context).push<SettingsResult>(
      MaterialPageRoute(builder: (_) => const ChangeHotelScreen()),
    );
    if (!mounted) return;
    if (res == SettingsResult.hotelChanged) {
      // like Ionic: back to the app, everything reloads with the new hotel
      Navigator.of(context).pop(SettingsResult.hotelChanged);
    } else {
      setState(() => _currentHotel =
          Prefs.getString('hotelName', Prefs.getString('nomhotel')));
    }
  }

  // ------------------------------------------------- preferences (Ionic)
  bool _darkMode = Prefs.getBool('darkMode', false);
  bool _notifications = Prefs.getBool('notifications', true);

  Future<void> _toggleDark() async {
    setState(() => _darkMode = !_darkMode);
    await Prefs.setBool('darkMode', _darkMode);
    _snack(_darkMode
        ? _t('Mode sombre activé', 'Dark mode activated')
        : _t('Mode clair activé', 'Light mode activated'));
  }

  Future<void> _toggleNotifications() async {
    setState(() => _notifications = !_notifications);
    await Prefs.setBool('notifications', _notifications);
    _snack(_notifications
        ? _t('Notifications activées', 'Notifications enabled')
        : _t('Notifications désactivées', 'Notifications disabled'));
  }

  void _refresh() {
    setState(() {
      _currentHotel = Prefs.getString('hotelName', Prefs.getString('nomhotel'));
      _darkMode = Prefs.getBool('darkMode', false);
      _notifications = Prefs.getBool('notifications', true);
    });
    _snack(_t('Paramètres actualisés', 'Settings refreshed'));
  }

  // ---------------------------------------------------------- password
  Future<void> _changePassword() async {
    final login = TextEditingController(text: _loginId);
    final oldP = TextEditingController();
    final newP = TextEditingController();
    final confP = TextEditingController();
    var busy = false;
    var hide = true;
    String? error;

    // same rules as the Ionic reset-password page
    final strong =
        RegExp(r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[\W_]).{8,}$');

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        Future<void> submit() async {
          String? err;
          if (login.text.trim().isEmpty ||
              oldP.text.isEmpty ||
              newP.text.isEmpty ||
              confP.text.isEmpty) {
            err = _t('Veuillez remplir tous les champs.',
                'Please fill all fields.');
          } else if (newP.text != confP.text) {
            err = _t('Les mots de passe ne correspondent pas.',
                'Passwords do not match.');
          } else if (!strong.hasMatch(newP.text)) {
            err = _t(
                'Au moins 8 caractères, une majuscule, une minuscule, un chiffre et un caractère spécial.',
                'At least 8 characters with uppercase, lowercase, number and special character.');
          } else if (newP.text == oldP.text) {
            err = _t("Le nouveau mot de passe doit être différent de l'ancien.",
                'New password must be different from the old one.');
          }
          if (err != null) {
            setD(() => error = err);
            return;
          }
          setD(() {
            busy = true;
            error = null;
          });
          try {
            final res = await http
                .put(
                  Uri.parse(
                      '${AppConfig.baseUrlOrDefault}/api/users/modif-password'),
                  headers: const {'Content-Type': 'application/json'},
                  body: jsonEncode({
                    'login': login.text.trim(),
                    'oldPassword': oldP.text.trim(),
                    'newPassword': newP.text.trim(),
                    'confirmPassword': confP.text.trim(),
                  }),
                )
                .timeout(const Duration(seconds: 20));
            final text = utf8.decode(res.bodyBytes);
            if (res.statusCode >= 200 &&
                res.statusCode < 300 &&
                text.toLowerCase().contains('success')) {
              if (ctx.mounted) Navigator.of(ctx).pop();
              _snack(_t('Mot de passe changé avec succès !',
                  'Password changed successfully!'));
              return;
            }
            setD(() {
              busy = false;
              error = text.isNotEmpty && text.length < 160
                  ? text
                  : _t('Échec du changement de mot de passe.',
                      'Failed to change password.');
            });
          } catch (_) {
            setD(() {
              busy = false;
              error = _t('Le serveur est inaccessible. Essayez plus tard.',
                  'Server is unreachable. Try again later.');
            });
          }
        }

        InputDecoration dec(String label) => InputDecoration(
              labelText: label,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              isDense: true,
            );

        return AlertDialog(
          title: Text(_t('Changer le mot de passe', 'Change password')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: login,
                  enabled: !busy,
                  decoration: dec(_t('Identifiant', 'Login'))),
              const SizedBox(height: 10),
              TextField(
                  controller: oldP,
                  enabled: !busy,
                  obscureText: hide,
                  decoration: dec(_t('Ancien mot de passe', 'Current password'))),
              const SizedBox(height: 10),
              TextField(
                  controller: newP,
                  enabled: !busy,
                  obscureText: hide,
                  decoration: dec(_t('Nouveau mot de passe', 'New password'))),
              const SizedBox(height: 10),
              TextField(
                  controller: confP,
                  enabled: !busy,
                  obscureText: hide,
                  decoration: dec(_t('Confirmer', 'Confirm')).copyWith(
                    suffixIcon: IconButton(
                      icon: Icon(
                          hide ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setD(() => hide = !hide),
                    ),
                  )),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(error!,
                      style: const TextStyle(color: Colors.red, fontSize: 13)),
                ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: busy ? null : () => Navigator.of(ctx).pop(),
                child: Text(_t('Annuler', 'Cancel'))),
            FilledButton(
              onPressed: busy ? null : submit,
              child: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(_t('Enregistrer', 'Save')),
            ),
          ],
        );
      }),
    );
    login.dispose();
    oldP.dispose();
    newP.dispose();
    confP.dispose();
  }

  // ---------------------------------------------------------- language
  Future<void> _pickLanguage() async {
    final l = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final e in const {'fr': 'Français', 'en': 'English'}.entries)
            ListTile(
              leading: const Icon(Icons.language),
              title: Text(e.value),
              trailing: AppLang.lang.value == e.key
                  ? const Icon(Icons.check_circle, color: _blue)
                  : null,
              onTap: () => Navigator.of(ctx).pop(e.key),
            ),
        ]),
      ),
    );
    if (l != null) await AppLang.set(l);
  }

  // ------------------------------------------------------------ logout
  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.t('logout')),
        content: Text(_t('Voulez-vous vraiment vous déconnecter ?',
            'Are you sure you want to log out?')),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(_t('Annuler', 'Cancel'))),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(S.t('logout'))),
        ],
      ),
    );
    if (ok == true && mounted) {
      Navigator.of(context).pop(SettingsResult.logout);
    }
  }

  // ---------------------------------------------------------------- UI
  @override
  Widget build(BuildContext context) {
    final id = _loginId;
    final name = Prefs.getString('userName', id.isEmpty ? 'User' : id);
    final pad = R.pagePad(context);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 1,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop()),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_t('Paramètres', 'Settings'),
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
          Text(_t('Gérez votre compte', 'Manage your account'),
              style: const TextStyle(fontSize: 12, color: Colors.black54)),
        ]),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ListView(
            padding: EdgeInsets.all(pad < 12 ? 12 : pad),
            children: [
              _profile(name, id),
              const SizedBox(height: 12),
              _hotelCard(),
              const SizedBox(height: 12),
              // same order as the Ionic page
              _option(
                icon: Icons.lock_outline,
                color: const Color(0xFFFF9800),
                title: _t('Changer le mot de passe', 'Change Password'),
                subtitle: _t('Mettre à jour votre mot de passe',
                    'Update your account password'),
                onTap: _changePassword,
              ),
              _option(
                icon: Icons.business_outlined,
                color: const Color(0xFF7E57C2),
                title: _t("Changer d'hôtel", 'Change Hotel'),
                subtitle: _t('Passer à un autre hôtel', 'Switch to a different hotel'),
                onTap: _changeHotel,
              ),
              _option(
                icon: Icons.language,
                color: const Color(0xFF26A69A),
                title: S.t('language'),
                subtitle: _t("Changer la langue de l'application", 'Change app language'),
                onTap: _pickLanguage,
              ),
              _option(
                icon: _darkMode ? Icons.wb_sunny_outlined : Icons.nightlight_outlined,
                color: const Color(0xFF5C6BC0),
                title: _darkMode
                    ? _t('Mode clair', 'Light Mode')
                    : _t('Mode sombre', 'Dark Mode'),
                subtitle: _darkMode
                    ? _t('Passer au thème clair', 'Switch to light theme')
                    : _t('Passer au thème sombre', 'Switch to dark theme'),
                onTap: _toggleDark,
                trailing: Switch(value: _darkMode, onChanged: (_) => _toggleDark()),
              ),
              _option(
                icon: Icons.notifications_outlined,
                color: const Color(0xFFEC407A),
                title: 'Notifications',
                subtitle: _notifications
                    ? _t('Activées', 'Enabled')
                    : _t('Désactivées', 'Disabled'),
                onTap: _toggleNotifications,
                trailing: Switch(
                    value: _notifications,
                    onChanged: (_) => _toggleNotifications()),
              ),
              _option(
                icon: Icons.arrow_back,
                color: const Color(0xFF78909C),
                title: _t('Retour au tableau de bord', 'Return to Dashboard'),
                subtitle: _t('Retourner au menu principal', 'Go back to main menu'),
                onTap: () => Navigator.of(context).pop(),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _confirmLogout,
                icon: const Icon(Icons.logout),
                label: Text(_t('Se déconnecter', 'Logout')),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),
              const Center(
                child: Text('Version 2.0.1',
                    style: TextStyle(color: Colors.black45, fontSize: 12)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _profile(String name, String id) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_blue, _blueDark],
          ),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white70, width: 2),
            ),
            child: const ClipOval(
              child: SizedBox(
                width: 76,
                height: 76,
                child: Image(
                    image: AssetImage('assets/images/default-avatar.png'),
                    fit: BoxFit.cover),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(name,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700)),
          if (id.isNotEmpty && id != name)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(id,
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ),
        ]),
      );

  Widget _hotelCard() => Card(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: ListTile(
          leading: const CircleAvatar(
              backgroundColor: Color(0xFFE3F2FD),
              child: Icon(Icons.business_outlined, color: _blue)),
          title: Text(_t('Hôtel actuel', 'Current Hotel'),
              style: const TextStyle(fontSize: 12, color: Colors.black54)),
          subtitle: Text(
              _currentHotel.isEmpty
                  ? _t('Aucun hôtel sélectionné', 'No Hotel Selected')
                  : _currentHotel,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87)),
        ),
      );

  Widget _option({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Widget? trailing,
  }) =>
      Card(
        elevation: 0,
        color: Colors.white,
        margin: const EdgeInsets.only(bottom: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: ListTile(
          onTap: onTap,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          leading: CircleAvatar(
              backgroundColor: color.withOpacity(0.12),
              child: Icon(icon, color: color)),
          title:
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
          trailing: trailing ?? const Icon(Icons.chevron_right),
        ),
      );
}
