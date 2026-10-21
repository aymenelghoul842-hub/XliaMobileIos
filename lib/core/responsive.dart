import 'package:flutter/material.dart';

import 'prefs.dart';

/// Responsive helpers mirroring the Ionic SCSS:
///  - clamp(minRem, vw, maxRem)  ->  R.fluid()
///  - breakpoints 420 / 576 / 768 / 1024
///  - .container { max-width: 1200px; padding: 0 clamp(.5rem,2vw,1rem) }
class R {
  static const double rem = 16;

  static double width(BuildContext c) => MediaQuery.sizeOf(c).width;

  /// Same as CSS clamp(minRem, vw%, maxRem) (result in logical pixels).
  static double fluid(BuildContext c, double minRem, double vw, double maxRem) {
    final v = width(c) * vw / 100;
    final lo = minRem * rem, hi = maxRem * rem;
    return v < lo ? lo : (v > hi ? hi : v);
  }

  static bool phone(BuildContext c) => width(c) <= 420;
  static bool mobile(BuildContext c) => width(c) <= 768; // @media max 768
  static bool desktop(BuildContext c) => width(c) >= 1024; // split pane

  /// Page side padding.
  static double pagePad(BuildContext c) =>
      mobile(c) ? 8 : fluid(c, 0.5, 2, 1);

  // text sizes used by tables
  static double cellFont(BuildContext c) =>
      fluid(c, phone(c) ? 0.5 : 0.55, 1.5, 0.8);
  static double headFont(BuildContext c) => fluid(c, 0.625, 1.8, 1.0);
  static double pillFont(BuildContext c) => fluid(c, 0.55, 1.4, 0.75);
  static double titleFont(BuildContext c) => fluid(c, 1.0, 3, 1.5);
}

/// Scrollable page body: centered, max 1200px, fluid side padding.
class ResponsivePage extends StatelessWidget {
  final List<Widget> children;
  final double maxWidth;
  const ResponsivePage({super.key, required this.children, this.maxWidth = 1200});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Padding(
            padding: EdgeInsets.symmetric(
                horizontal: R.pagePad(context), vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ),
    );
  }
}

class AppCard extends StatelessWidget {
  final Widget child;
  const AppCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) => Card(
        elevation: 2,
        margin: EdgeInsets.zero,
        color: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: EdgeInsets.all(R.fluid(context, 0.5, 1.5, 1.25)),
          child: child,
        ),
      );
}

class SectionTitle extends StatelessWidget {
  final String text;
  const SectionTitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Center(
          child: Text(text,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: R.titleFont(context), fontWeight: FontWeight.w700)),
        ),
      );
}

/// Table that fits the available width (like the Ionic table with
/// shrinking fonts) instead of scrolling horizontally.
class FluidTable extends StatelessWidget {
  final List<String> headers;
  final List<List<Widget>> rows;
  final List<double> flex;
  final int? selectedRow;
  final ValueChanged<int>? onRowTap;

  /// Optional: tap on a header (sorting). [sortColumn]/[sortAscending] draw the arrow.
  final ValueChanged<int>? onHeaderTap;
  final int? sortColumn;
  final bool sortAscending;

  /// Columns whose header + cells are right aligned (numbers).
  final Set<int> rightCols;

  const FluidTable({
    super.key,
    required this.headers,
    required this.rows,
    required this.flex,
    this.selectedRow,
    this.onRowTap,
    this.onHeaderTap,
    this.sortColumn,
    this.sortAscending = true,
    this.rightCols = const {},
  });

  @override
  Widget build(BuildContext context) {
    final hf = R.headFont(context);
    final cf = R.cellFont(context);
    final padH = R.fluid(context, 0.25, 1, 0.75);
    final padV = R.fluid(context, 0.25, 1, 0.75);

    return Table(
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      columnWidths: {
        for (var i = 0; i < headers.length; i++)
          i: FlexColumnWidth(i < flex.length ? flex[i] : 1),
      },
      children: [
        TableRow(
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFFDDDDDD), width: 2)),
          ),
          children: [
            for (var c = 0; c < headers.length; c++)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onHeaderTap == null ? null : () => onHeaderTap!(c),
                child: Padding(
                  padding:
                      EdgeInsets.symmetric(horizontal: padH, vertical: padV + 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.max,
                    mainAxisAlignment: rightCols.contains(c)
                        ? MainAxisAlignment.end
                        : MainAxisAlignment.start,
                    children: [
                      Flexible(
                        child: Text(headers[c],
                            style: TextStyle(
                                fontSize: hf,
                                fontWeight: FontWeight.w700,
                                color: Colors.black87)),
                      ),
                      if (onHeaderTap != null)
                        Icon(
                          sortColumn == c
                              ? (sortAscending
                                  ? Icons.arrow_upward
                                  : Icons.arrow_downward)
                              : Icons.filter_list,
                          size: hf + 2,
                          color: sortColumn == c
                              ? const Color(0xFF2196F3)
                              : Colors.black38,
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        for (var i = 0; i < rows.length; i++)
          TableRow(
            decoration: BoxDecoration(
              color: selectedRow == i ? const Color(0x1A2196F3) : null,
              border: const Border(
                  bottom: BorderSide(color: Color(0xFFEEEEEE))),
            ),
            children: [
              for (var c = 0; c < rows[i].length; c++)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onRowTap == null ? null : () => onRowTap!(i),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
                    child: DefaultTextStyle(
                      style: TextStyle(fontSize: cf, color: Colors.black87),
                      child: rightCols.contains(c)
                          ? Align(
                              alignment: Alignment.centerRight,
                              child: rows[i][c])
                          : rows[i][c],
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

class Pill extends StatelessWidget {
  final String text;
  final Color bg;
  final Color fg;
  final bool center;
  const Pill(this.text, this.bg, this.fg, {super.key, this.center = false});

  @override
  Widget build(BuildContext context) => Align(
        alignment: center ? Alignment.center : Alignment.centerLeft,
        widthFactor: 1,
        heightFactor: 1,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration:
              BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
          child: Text(text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: fg,
                  fontWeight: FontWeight.w600,
                  fontSize: R.pillFont(context))),
        ),
      );
}

class RoomChip extends StatelessWidget {
  final String text;
  const RoomChip(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        widthFactor: 1,
        heightFactor: 1,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
              color: const Color(0xFFEEF2F7),
              borderRadius: BorderRadius.circular(6)),
          child: Text(text,
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: R.fluid(context, 0.58, 1.4, 0.78))),
        ),
      );
}

class DateCell extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const DateCell(this.icon, this.color, this.text, {super.key});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: R.fluid(context, 0.6, 1.6, 0.9), color: color),
          const SizedBox(width: 2),
          Flexible(child: Text(text, overflow: TextOverflow.ellipsis)),
        ],
      );
}

/// Pagination bar (first / prev / 3 numbers / next / last), wraps on tiny screens.
class PageBar extends StatelessWidget {
  final int page;
  final int total;
  final ValueChanged<int> onPage;
  const PageBar(
      {super.key, required this.page, required this.total, required this.onPage});

  @override
  Widget build(BuildContext context) {
    final minW = R.fluid(context, 1.9, 5, 2.4);
    final fs = R.fluid(context, 0.65, 1.7, 0.85);
    const block = 3;
    final startBlock = ((page - 1) ~/ block) * block + 1;
    final numbers = [
      for (var n = startBlock; n < startBlock + block && n <= total; n++) n
    ];

    Widget btn(Widget child, VoidCallback? onTap, {bool active = false}) =>
        SizedBox(
          width: minW,
          height: minW * 0.95,
          child: active
              ? FilledButton(
                  onPressed: onTap,
                  style: FilledButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      textStyle: TextStyle(fontSize: fs)),
                  child: child)
              : OutlinedButton(
                  onPressed: onTap,
                  style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      textStyle: TextStyle(fontSize: fs)),
                  child: child),
        );

    final icon = fs + 4;
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 4,
      runSpacing: 4,
      children: [
        btn(Icon(Icons.first_page, size: icon), page == 1 ? null : () => onPage(1)),
        btn(Icon(Icons.chevron_left, size: icon),
            page == 1 ? null : () => onPage(page - 1)),
        for (final n in numbers) btn(Text('$n'), () => onPage(n), active: n == page),
        btn(Icon(Icons.chevron_right, size: icon),
            page == total ? null : () => onPage(page + 1)),
        btn(Icon(Icons.last_page, size: icon),
            page == total ? null : () => onPage(total)),
      ],
    );
  }
}

/// "Hotel name > page" : the same hotel name as in the drawer.
String hotelTitle(String page) {
  final hotel =
      Prefs.getString('hotelName', Prefs.getString('nomhotel')).trim();
  return hotel.isEmpty ? page : '$hotel > $page';
}

/// Shared top bar for the data pages (logo + title + date + refresh).
PreferredSizeWidget xliaAppBar(
  BuildContext context, {
  required String title,
  required String date,
  required bool loading,
  required VoidCallback? onRefresh,
  VoidCallback? onMenu,
}) {
  return AppBar(
    backgroundColor: Colors.white,
    surfaceTintColor: Colors.white,
    elevation: 1,
    automaticallyImplyLeading: false,
    leading: onMenu == null
        ? null
        : IconButton(icon: const Icon(Icons.menu), onPressed: onMenu),
    titleSpacing: onMenu == null ? R.pagePad(context) + 4 : 0,
    title: Row(children: [
      Image.asset('assets/images/logo_xlia.png',
          height: R.fluid(context, 1.6, 6, 2.2)),
      const SizedBox(width: 8),
      Flexible(
        child: Text(hotelTitle(title),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: R.fluid(context, 0.875, 3, 1.35),
                fontWeight: FontWeight.w700)),
      ),
    ]),
    actions: [
      Center(
        child: Text(date,
            style: TextStyle(
                fontSize: R.fluid(context, 0.65, 2, 0.9), color: Colors.black54)),
      ),
      IconButton(
        icon: loading
            ? const SizedBox(
                width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.refresh),
        onPressed: loading ? null : onRefresh,
      ),
    ],
  );
}
