import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'fmt.dart';
import 'responsive.dart';

class ChartSeries {
  final String name;
  final List<double> values;
  final Color color;
  const ChartSeries(this.name, this.values, this.color);
}

class LegendDot extends StatelessWidget {
  final Color color;
  final String text;
  final VoidCallback? onTap;
  const LegendDot(this.color, this.text, {super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    final fs = R.fluid(context, 0.7, 2, 0.85);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 11,
              height: 11,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(text, style: TextStyle(fontSize: fs)),
        ]),
      ),
    );
  }
}

class EmptyChart extends StatelessWidget {
  final String text;
  final double height;
  const EmptyChart(this.text, {super.key, this.height = 120});

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        child: Center(
            child: Text(text, style: const TextStyle(color: Colors.black45))),
      );
}

/// Line chart with 1..n series sharing the same x labels (Chart.js `line`).
class LineSeriesChart extends StatelessWidget {
  final List<String> labels;
  final List<ChartSeries> series;
  final double height;
  final bool filled;
  final bool curved;
  final String emptyText;

  const LineSeriesChart({
    super.key,
    required this.labels,
    required this.series,
    this.height = 260,
    this.filled = false,
    this.curved = true,
    this.emptyText = 'Aucune donnée',
  });

  @override
  Widget build(BuildContext context) {
    final n = labels.length;
    final hasData =
        n > 0 && series.any((s) => s.values.any((v) => v != 0)) ;
    if (!hasData) return EmptyChart(emptyText, height: height);

    final fs = R.fluid(context, 0.55, 1.7, 0.75);
    final step = (n / 6).ceil().clamp(1, n).toInt();
    var maxY = 0.0;
    for (final s in series) {
      for (final v in s.values) {
        if (v > maxY) maxY = v;
      }
    }
    if (maxY <= 0) maxY = 10;

    String shortLabel(String l) => l.length == 10 ? l.substring(0, 5) : l;

    return Column(children: [
      SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsets.only(right: 12, top: 8),
          child: LineChart(
            LineChartData(
              minY: 0,
              maxY: maxY * 1.15,
              borderData: FlBorderData(show: false),
              gridData: const FlGridData(show: true, drawVerticalLine: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 38,
                    getTitlesWidget: (v, meta) => Text(Fmt.compact(v),
                        style: TextStyle(fontSize: fs, color: Colors.black54)),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    interval: 1,
                    getTitlesWidget: (v, meta) {
                      if (v != v.roundToDouble()) return const SizedBox();
                      final i = v.toInt();
                      if (i < 0 || i >= n || i % step != 0) {
                        return const SizedBox();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(shortLabel(labels[i]),
                            style: TextStyle(fontSize: fs, color: Colors.black87)),
                      );
                    },
                  ),
                ),
              ),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipItems: (spots) => [
                    for (final s in spots)
                      LineTooltipItem(
                        '${s.x.toInt() < n ? labels[s.x.toInt()] : ''}\n'
                        '${series[s.barIndex].name}: ${Fmt.thousands(s.y)}',
                        const TextStyle(color: Colors.white, fontSize: 11),
                      ),
                  ],
                ),
              ),
              lineBarsData: [
                for (final s in series)
                  LineChartBarData(
                    spots: [
                      for (var i = 0; i < n; i++)
                        FlSpot(i.toDouble(), i < s.values.length ? s.values[i] : 0),
                    ],
                    isCurved: curved,
                    curveSmoothness: 0.25,
                    preventCurveOverShooting: true,
                    color: s.color,
                    barWidth: 2.5,
                    dotData: FlDotData(show: n <= 14),
                    belowBarData: BarAreaData(
                        show: filled, color: s.color.withOpacity(0.18)),
                  ),
              ],
            ),
          ),
        ),
      ),
      const SizedBox(height: 6),
      Wrap(
        alignment: WrapAlignment.center,
        spacing: 12,
        children: [for (final s in series) LegendDot(s.color, s.name)],
      ),
    ]);
  }
}

class PieEntry {
  final String code;
  final String label;
  final double value;
  final Color color;
  const PieEntry(this.code, this.label, this.value, this.color);
}

/// Pie chart + legend. Slices and legend chips are tappable ([onTap] gets the index).
class PieLegendChart extends StatelessWidget {
  final List<PieEntry> entries;
  final double height;
  final ValueChanged<int>? onTap;
  final String emptyText;

  const PieLegendChart({
    super.key,
    required this.entries,
    this.height = 240,
    this.onTap,
    this.emptyText = 'Aucune donnée',
  });

  @override
  Widget build(BuildContext context) {
    final visible = entries.where((e) => e.value > 0).toList();
    final total = visible.fold<double>(0, (a, e) => a + e.value);
    if (visible.isEmpty || total <= 0) {
      return EmptyChart(emptyText, height: height);
    }
    final radius = (height / 2) * 0.82;

    return Column(children: [
      SizedBox(
        height: height,
        child: PieChart(PieChartData(
          centerSpaceRadius: radius * 0.25,
          sectionsSpace: 2,
          pieTouchData: PieTouchData(
            touchCallback: (event, resp) {
              if (onTap == null || event is! FlTapUpEvent) return;
              final i = resp?.touchedSection?.touchedSectionIndex ?? -1;
              if (i >= 0 && i < entries.length) {
                // map back to the original index (visible list may be filtered)
                final code = visible[i].code;
                final orig = entries.indexWhere((e) => e.code == code);
                if (orig >= 0) onTap!(orig);
              }
            },
          ),
          sections: [
            for (final e in visible)
              PieChartSectionData(
                value: e.value,
                color: e.color,
                radius: radius,
                title: (e.value / total * 100) >= 5
                    ? '${(e.value / total * 100).toStringAsFixed(0)}%'
                    : '',
                titleStyle: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold),
              ),
          ],
        )),
      ),
      const SizedBox(height: 8),
      Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 2,
        children: [
          for (var i = 0; i < entries.length; i++)
            if (entries[i].value > 0)
              LegendDot(entries[i].color, entries[i].label,
                  onTap: onTap == null ? null : () => onTap!(i)),
        ],
      ),
    ]);
  }
}

/// Simple bar chart (Chart.js `bar`): one value per label, per-bar colors.
class BarSeriesChart extends StatelessWidget {
  final List<String> labels;
  final List<double> values;
  final List<Color> colors;
  final String legend;
  final double height;
  final String emptyText;

  const BarSeriesChart({
    super.key,
    required this.labels,
    required this.values,
    required this.colors,
    required this.legend,
    this.height = 260,
    this.emptyText = 'Aucune donnée',
  });

  @override
  Widget build(BuildContext context) {
    final n = labels.length;
    if (n == 0 || values.every((v) => v == 0)) {
      return EmptyChart(emptyText, height: height);
    }
    final fs = R.fluid(context, 0.6, 1.8, 0.8);
    var maxV = 0.0;
    for (final v in values) {
      if (v > maxV) maxV = v;
    }
    Color colorAt(int i) => colors[i % colors.length];
    String cut(String s) => s.length > 12 ? '${s.substring(0, 11)}…' : s;

    return Column(children: [
      SizedBox(
        height: height,
        child: BarChart(BarChartData(
          maxY: maxV * 1.2,
          alignment: BarChartAlignment.spaceAround,
          borderData: FlBorderData(show: false),
          gridData: const FlGridData(show: true, drawVerticalLine: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                getTitlesWidget: (v, m) => Text(Fmt.compact(v),
                    style: TextStyle(fontSize: fs, color: Colors.black54)),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 36,
                getTitlesWidget: (v, m) {
                  final i = v.toInt();
                  if (i < 0 || i >= n) return const SizedBox();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(cut(labels[i]),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        style: TextStyle(fontSize: fs)),
                  );
                },
              ),
            ),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, gi, rod, ri) => BarTooltipItem(
                '${labels[gi]}\n${Fmt.thousands(rod.toY)}',
                const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < n; i++)
              BarChartGroupData(x: i, barRods: [
                BarChartRodData(
                  toY: i < values.length ? values[i] : 0,
                  width: (R.width(context) * 0.07).clamp(16.0, 40.0).toDouble(),
                  color: colorAt(i),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(4)),
                ),
              ]),
          ],
        )),
      ),
      const SizedBox(height: 6),
      LegendDot(colors.first, legend),
    ]);
  }
}
