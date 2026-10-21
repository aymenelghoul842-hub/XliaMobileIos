import 'package:flutter/material.dart';
import '../core/lang.dart';

/// Shown for modules that are not ported to Flutter yet.
class PlaceholderScreen extends StatelessWidget {
  final String title;
  final VoidCallback? onMenu;
  final bool showBack;
  const PlaceholderScreen(
      {super.key, required this.title, this.onMenu, this.showBack = false});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: showBack
            ? null
            : (onMenu == null
                ? null
                : IconButton(icon: const Icon(Icons.menu), onPressed: onMenu)),
        automaticallyImplyLeading: showBack,
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.construction, size: 56, color: Colors.black38),
            const SizedBox(height: 12),
            Text(title,
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(S.t('comingSoonPage'),
                style: const TextStyle(color: Colors.black54)),
          ],
        ),
      ),
    );
  }
}
