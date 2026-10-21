import 'dart:async';
import 'api_client.dart';

/// Helpers that make the "procedure then read tables" pages (Prévisions, CA)
/// load reliably on the FIRST try, without the user having to refresh.
///
/// Background: the server first runs an Oracle procedure that fills temporary
/// tables for a session id, then the page reads those tables. Reading too early
/// (or while a slow procedure is still writing) returns `[]`, which the old
/// code displayed as "no data" until the user pulled to refresh.
class LoadToken {
  int _gen = 0;

  /// Start a new load; every older load becomes stale.
  int begin() => ++_gen;

  /// Invalidate every running load (call from dispose).
  void cancel() => _gen++;

  bool isCurrent(int g) => g == _gen;
}

class Loader {
  /// Retries while the answer is empty (procedure still writing).
  /// Network / HTTP errors are rethrown (after [Api.post]'s own retries).
  static Future<List<Map<String, dynamic>>> listRetry(
    String url,
    Map<String, dynamic> body, {
    Map<String, String>? query,
    int emptyRetries = 5,
    Duration firstDelay = const Duration(milliseconds: 1200),
    Duration timeout = const Duration(seconds: 30),
    bool Function()? cancelled,
    bool reportOffline = true,
  }) async {
    var delay = firstDelay;
    for (var i = 0; i <= emptyRetries; i++) {
      if (cancelled?.call() ?? false) return [];
      final l = Api.asList(
          await Api.post(url, body,
              query: query, timeout: timeout, retries: 1,
              reportOffline: reportOffline));
      if (l.isNotEmpty) return l;
      if (i < emptyRetries) {
        await Future.delayed(delay);
        // 1.2s, 1.8s, 2.7s, 4s, 6s ... (max 6s) : ~16s total before giving up
        final next = delay.inMilliseconds * 3 ~/ 2;
        delay = Duration(milliseconds: next > 6000 ? 6000 : next);
      }
    }
    return [];
  }

  /// Runs a (heavy) server procedure. Never throws: returns true if it
  /// answered successfully. One quick retry for network hiccups.
  static Future<bool> procedure(
    String url,
    Map<String, dynamic> body,
    Map<String, String> query, {
    Duration timeout = const Duration(seconds: 60),
    int retries = 1,
  }) async {
    try {
      await Api.post(url, body, query: query, retries: retries, timeout: timeout);
      return true;
    } catch (_) {
      return false;
    }
  }
}
