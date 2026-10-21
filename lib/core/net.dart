import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'api_client.dart';
import 'app_config.dart';
import 'lang.dart';

/// Connection state + friendly error messages + automatic reconnection.
///
///  * [Api.post] reports every success / network failure here.
///  * When the connection is lost, [online] becomes false and a background
///    check retries by itself (every 4s, then 8s, then 15s) until the server
///    answers again. It also re-checks at once when the app comes back from
///    the background ([checkNow]).
///  * When the connection comes back, [reconnectTick] is incremented: the
///    shell reloads the current page automatically, no manual refresh needed.
class Net with WidgetsBindingObserver {
  Net._();
  static final Net _i = Net._();

  /// false while the server cannot be reached.
  static final ValueNotifier<bool> online = ValueNotifier<bool>(true);

  /// +1 each time the connection is back after an outage.
  static final ValueNotifier<int> reconnectTick = ValueNotifier<int>(0);

  /// true while a reconnection attempt is running (for the banner).
  static final ValueNotifier<bool> checking = ValueNotifier<bool>(false);

  static Timer? _timer;
  static int _attempt = 0;
  static bool _started = false;

  static void init() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(_i);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // back from the background: check the connection right now
    if (state == AppLifecycleState.resumed && !online.value) checkNow();
  }

  // ------------------------------------------------------ state reports
  static void markOnline() {
    if (online.value) return;
    _timer?.cancel();
    _timer = null;
    _attempt = 0;
    online.value = true;
    reconnectTick.value++;
  }

  static void markOffline() {
    if (!online.value) return;
    online.value = false;
    _schedule();
  }

  static void _schedule() {
    _timer?.cancel();
    final secs = _attempt < 2 ? 4 : (_attempt < 5 ? 8 : 15);
    _timer = Timer(Duration(seconds: secs), checkNow);
  }

  /// Ping the server. ANY http answer (even 404/500) means "reachable".
  static Future<bool> checkNow() async {
    if (checking.value) return online.value;
    checking.value = true;
    _timer?.cancel();
    var ok = false;
    try {
      final base = AppConfig.baseUrlOrDefault;
      await http.get(Uri.parse(base)).timeout(const Duration(seconds: 6));
      ok = true;
    } catch (_) {
      ok = false;
    }
    checking.value = false;
    if (ok) {
      markOnline();
    } else {
      if (online.value) online.value = false;
      _attempt++;
      _schedule();
    }
    return ok;
  }

  // ------------------------------------------------------------ messages
  static bool get _fr => AppLang.lang.value != 'en';

  /// Short, correct message for any error (shown to the user).
  static String message(Object e) {
    if (e is ApiException) {
      final s = e.status;
      if (e.isNetwork) {
        final m = e.message.toLowerCase();
        if (m.contains('timeout')) {
          return _fr
              ? 'Le serveur met trop de temps à répondre. Nouvelle tentative automatique…'
              : 'The server is taking too long to respond. Retrying automatically…';
        }
        if (m.contains('failed host lookup') ||
            m.contains('network is unreachable') ||
            m.contains('no address associated')) {
          return _fr
              ? 'Pas de connexion internet. Vérifiez votre réseau (Wi-Fi / données).'
              : 'No internet connection. Check your network (Wi-Fi / data).';
        }
        if (m.contains('connection refused') || m.contains('connection reset')) {
          return _fr
              ? 'Le serveur est inaccessible pour le moment. Reconnexion automatique…'
              : 'The server is currently unreachable. Reconnecting automatically…';
        }
        return _fr
            ? 'Connexion impossible. Reconnexion automatique en cours…'
            : 'Unable to connect. Reconnecting automatically…';
      }
      if (s == 401 || s == 403) {
        return _fr
            ? 'Session expirée. Veuillez vous reconnecter.'
            : 'Session expired. Please log in again.';
      }
      if (s == 404) {
        return _fr
            ? 'Service introuvable (404). Vérifiez la configuration du serveur.'
            : 'Service not found (404). Check the server configuration.';
      }
      if (s != null && s >= 500) {
        return _fr
            ? 'Erreur du serveur ($s). Réessayez dans un instant.'
            : 'Server error ($s). Please try again shortly.';
      }
      if (s != null) {
        return _fr ? 'Requête refusée ($s).' : 'Request refused ($s).';
      }
      return _fr ? 'Erreur de connexion au serveur.' : 'Server connection error.';
    }
    return _fr
        ? "Une erreur inattendue s'est produite. Réessayez."
        : 'An unexpected error occurred. Try again.';
  }
}

/// Banner shown at the top of the app while the connection is lost
/// (and a green "back online" confirmation for a moment afterwards).
class ConnectionBanner extends StatefulWidget {
  final Widget child;
  const ConnectionBanner({super.key, required this.child});

  @override
  State<ConnectionBanner> createState() => _ConnectionBannerState();
}

class _ConnectionBannerState extends State<ConnectionBanner> {
  bool _restored = false;
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    Net.reconnectTick.addListener(_onBack);
    Net.online.addListener(_rebuild);
    Net.checking.addListener(_rebuild);
    AppLang.lang.addListener(_rebuild);
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  void _onBack() {
    if (!mounted) return;
    setState(() => _restored = true);
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _restored = false);
    });
  }

  @override
  void dispose() {
    _hide?.cancel();
    Net.reconnectTick.removeListener(_onBack);
    Net.online.removeListener(_rebuild);
    Net.checking.removeListener(_rebuild);
    AppLang.lang.removeListener(_rebuild);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fr = AppLang.lang.value != 'en';
    final offline = !Net.online.value;
    Widget? bar;
    if (offline) {
      bar = _bar(
        color: const Color(0xFFD32F2F),
        icon: Icons.wifi_off,
        text: Net.checking.value
            ? (fr ? 'Reconnexion en cours…' : 'Reconnecting…')
            : (fr
                ? 'Connexion perdue. Reconnexion automatique…'
                : 'Connection lost. Reconnecting automatically…'),
        action: Net.checking.value
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : TextButton(
                onPressed: Net.checkNow,
                style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 28),
                    padding: const EdgeInsets.symmetric(horizontal: 8)),
                child: Text(fr ? 'Réessayer' : 'Retry'),
              ),
      );
    } else if (_restored) {
      bar = _bar(
        color: const Color(0xFF2E7D32),
        icon: Icons.wifi,
        text: fr ? 'Connexion rétablie' : 'Back online',
      );
    }
    return Column(children: [
      if (bar != null) bar,
      Expanded(child: widget.child),
    ]);
  }

  Widget _bar(
      {required Color color,
      required IconData icon,
      required String text,
      Widget? action}) {
    return Material(
      color: color,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(
                child: Text(text,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600))),
            if (action != null) action,
          ]),
        ),
      ),
    );
  }
}
