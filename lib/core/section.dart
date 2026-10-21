import 'package:flutter/material.dart';
import 'lang.dart';
import 'responsive.dart';

/// Loading state of ONE table / chart. Every table and chart of a page owns
/// one, so it shows its own spinner and refreshes on its own.
class Sec {
  bool loading = false;
  bool loaded = false;
  String error = '';
  int gen = 0; // bumped on every (re)load -> older answers are ignored
}

/// Last results kept in memory (per page). Re-opening a page shows them
/// instantly while fresh data loads in the background. Cleared when the
/// hotel changes ([Session.reset]).
class PageCache {
  static final Map<String, Object> _data = {};
  static final Map<String, DateTime> _stamp = {};
  static const Duration ttl = Duration(minutes: 3);

  static T? get<T>(String page, String key) {
    final v = _data['$page/$key'];
    return v is T ? v : null;
  }

  static void put(String page, String key, Object v) => _data['$page/$key'] = v;

  /// Call when a whole page finished loading without error.
  static void stamp(String page) => _stamp[page] = DateTime.now();

  /// True when the page was fully loaded less than [ttl] ago.
  static bool fresh(String page) {
    final t = _stamp[page];
    return t != null && DateTime.now().difference(t) < ttl;
  }

  static void clear() {
    _data.clear();
    _stamp.clear();
  }
}

/// Shared load helpers for a State that owns several [Sec]s.
mixin SecLoader<T extends StatefulWidget> on State<T> {
  bool get isFr => AppLang.lang.value == 'fr';
  String tr(String fr, String en) => isFr ? fr : en;

  bool ok(Sec s, int gen) => mounted && s.gen == gen;

  /// Runs one section: spinner on, [body], spinner off. A failure only marks
  /// THIS section, the others keep loading.
  Future<void> runSec(Sec s, Future<void> Function(int gen) body) async {
    final gen = ++s.gen;
    if (mounted) {
      setState(() {
        s.loading = true;
        s.error = '';
      });
    }
    String err = '';
    try {
      await body(gen);
    } catch (_) {
      err = tr('Erreur de chargement', 'Loading error');
    }
    if (!ok(s, gen)) return;
    setState(() {
      s.loading = false;
      s.loaded = true;
      s.error = err;
    });
  }
}

/// Card that shows its own loading state:
///  * nothing yet      -> spinner in the card
///  * refreshing       -> thin progress bar + slightly faded content
///  * failed, no data  -> message + Retry button
class SecCard extends StatelessWidget {
  final Sec sec;
  final bool hasData;
  final Widget child;
  final VoidCallback? onRetry;
  final double minHeight;

  const SecCard({
    super.key,
    required this.sec,
    required this.hasData,
    required this.child,
    this.onRetry,
    this.minHeight = 140,
  });

  @override
  Widget build(BuildContext context) {
    final fr = AppLang.lang.value == 'fr';
    Widget body;
    if (!hasData && (sec.loading || !sec.loaded) && sec.error.isEmpty) {
      body = SizedBox(
        height: minHeight,
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(
                width: 30,
                height: 30,
                child: CircularProgressIndicator(strokeWidth: 3)),
            const SizedBox(height: 10),
            Text(fr ? 'Chargement…' : 'Loading…',
                style: const TextStyle(color: Colors.black54, fontSize: 12)),
          ]),
        ),
      );
    } else if (!hasData && sec.error.isNotEmpty && !sec.loading) {
      body = SizedBox(
        height: minHeight,
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(sec.error, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 8),
            if (onRetry != null)
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(fr ? 'Réessayer' : 'Retry'),
              ),
          ]),
        ),
      );
    } else {
      body = Column(mainAxisSize: MainAxisSize.min, children: [
        if (sec.loading)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: ClipRRect(
              borderRadius: BorderRadius.all(Radius.circular(4)),
              child: LinearProgressIndicator(minHeight: 3),
            ),
          ),
        AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: sec.loading ? 0.55 : 1,
          child: child,
        ),
      ]);
    }
    return AppCard(child: body);
  }
}

/// Section title with its own refresh button (turns into a spinner while loading).
class SecTitle extends StatelessWidget {
  final String text;
  final Sec sec;
  final VoidCallback onRefresh;
  const SecTitle(this.text, {super.key, required this.sec, required this.onRefresh});

  @override
  Widget build(BuildContext context) => Stack(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 34),
          child: SizedBox(width: double.infinity, child: SectionTitle(text)),
        ),
        Positioned(
          right: 0,
          top: 0,
          child: sec.loading
              ? const Padding(
                  padding: EdgeInsets.all(6),
                  child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : IconButton(
                  visualDensity: VisualDensity.compact,
                  iconSize: 20,
                  tooltip: AppLang.lang.value == 'fr' ? 'Actualiser' : 'Refresh',
                  icon: const Icon(Icons.refresh),
                  onPressed: onRefresh,
                ),
        ),
      ]);
}
