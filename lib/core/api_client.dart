import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show compute;
import 'package:http/http.dart' as http;
import 'net.dart';

class ApiException implements Exception {
  final int? status;
  final String message;
  final bool isNetwork; // timeout / unreachable
  ApiException(this.message, {this.status, this.isNetwork = false});

  /// Friendly text for the user (FR/EN), never a raw exception.
  String get friendly => Net.message(this);

  @override
  String toString() => 'ApiException($status): $message';
}

dynamic _decodeJson(String text) => jsonDecode(text);

class Api {
  /// ONE shared client: keeps TCP connections alive, so we don't pay a new
  /// connection (handshake) for every request.
  static final http.Client _client = http.Client();

  static const Duration timeout = Duration(seconds: 15);
  static const int maxRetries = 3;

  /// POST JSON with timeout + retry (like postWithRetry in the Angular app).
  static Future<dynamic> post(
    String url,
    Map<String, dynamic> body, {
    Map<String, String>? query,
    int retries = maxRetries,
    Duration? timeout,
    bool reportOffline = true, // false: a failure here never shows "connexion perdue"
  }) async {
    var uri = Uri.parse(url);
    if (query != null && query.isNotEmpty) {
      uri = uri.replace(queryParameters: query);
    }

    ApiException? last;
    for (var attempt = 0; attempt <= retries; attempt++) {
      try {
        final res = await _client
            .post(
              uri,
              headers: const {
                'Content-Type': 'application/json',
                'Accept': 'application/json',
                'Cache-Control': 'no-cache',
              },
              body: jsonEncode(body),
            )
            .timeout(timeout ?? Api.timeout);

        Net.markOnline(); // the server answered -> connection is fine
        if (res.statusCode >= 200 && res.statusCode < 300) {
          if (res.bodyBytes.isEmpty) return null;
          final text = utf8.decode(res.bodyBytes);
          try {
            // big answers are parsed off the UI thread (no jank)
            return text.length > 30000
                ? await compute(_decodeJson, text)
                : jsonDecode(text);
          } catch (_) {
            return text; // plain text response
          }
        }
        last = ApiException('HTTP ${res.statusCode}', status: res.statusCode);
        // Do not retry client errors (4xx)
        if (res.statusCode >= 400 && res.statusCode < 500) throw last;
      } on ApiException catch (e) {
        last = e;
        if (e.status != null && e.status! >= 400 && e.status! < 500) rethrow;
      } on TimeoutException {
        last = ApiException('Timeout', isNetwork: true);
      } catch (e) {
        last = ApiException(e.toString(), isNetwork: true);
      }
      if (attempt < retries) {
        // automatic retry with growing pause: 0.8s, 1.6s, 2.4s ...
        await Future.delayed(Duration(milliseconds: 800 * (attempt + 1)));
      }
    }
    if (last != null && last.isNetwork && reportOffline) Net.markOffline(); // start auto-reconnect
    throw last ?? ApiException('Unknown error');
  }

  /// Server sometimes returns an array, sometimes an object of objects.
  static List<Map<String, dynamic>> asList(dynamic data) {
    Iterable items;
    if (data is List) {
      items = data;
    } else if (data is Map) {
      items = data.values;
    } else {
      return [];
    }
    return items
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }
}
