import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Small formatting / parsing helpers shared by the data screens.
class Fmt {
  static const _months = [
    'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
    'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'
  ];

  /// 13-OCT-2026  (format expected by the Oracle procedures).
  static String apiDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}-${_months[d.month - 1]}-${d.year}';

  /// dd/MM/yyyy from a DateTime.
  static String dmy(DateTime d) => DateFormat('dd/MM/yyyy').format(d);

  /// Any server date (ISO string, "yyyy-MM-dd HH:mm:ss", epoch ms) -> dd/MM/yyyy.
  static String dmyAny(dynamic v) {
    if (v == null) return '';
    DateTime? d;
    if (v is num) {
      d = DateTime.fromMillisecondsSinceEpoch(v.toInt());
    } else {
      final s = v.toString().trim();
      d = DateTime.tryParse(s);
      if (d == null) {
        // "yyyy-MM-dd" prefix of something unusual
        final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(s);
        if (m != null) {
          d = DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
        }
      }
    }
    return d == null ? v.toString() : dmy(d);
  }

  static double toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString().replaceAll(',', '.') ?? '') ?? 0;
  }

  /// Plain number for table cells: 12 -> "12", 12.5 -> "12.5", 12.3456 -> "12.35".
  static String n(dynamic v) {
    if (v == null) return '';
    if (v is! num) {
      final p = double.tryParse(v.toString());
      if (p == null) return v.toString();
      v = p;
    }
    final d = v.toDouble();
    if (d == d.roundToDouble()) return d.toInt().toString();
    return d
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  /// 1234567 -> "1 234 567" (same as formatNumber() in the Ionic pages).
  static String thousands(dynamic v) {
    var s = n(v ?? 0);
    if (s.isEmpty) s = '0';
    final neg = s.startsWith('-');
    if (neg) s = s.substring(1);
    final parts = s.split('.');
    parts[0] = parts[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ' ');
    return '${neg ? '-' : ''}${parts.join('.')}';
  }

  /// Axis labels: 1500 -> 1.5k, 2000000 -> 2M.
  static String compact(double v) {
    final a = v.abs();
    String t(double x) => x == x.roundToDouble()
        ? x.toInt().toString()
        : x.toStringAsFixed(1);
    if (a >= 1000000) return '${t(v / 1000000)}M';
    if (a >= 1000) return '${t(v / 1000)}k';
    return t(v);
  }

  /// "FF8800" / "#FF8800" / "80FF8800" -> Color.
  static Color hex(String? raw, {Color fallback = Colors.blueGrey}) {
    var h = (raw ?? '').trim().replaceAll('#', '');
    if (h.length == 6) h = 'FF$h';
    if (h.length != 8) return fallback;
    final v = int.tryParse(h, radix: 16);
    return v == null ? fallback : Color(v);
  }
}
