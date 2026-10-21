import 'package:flutter/material.dart';
import '../core/prefs.dart';

/// Startup screen (brand splash) + routing (replaces AuthGuard + default route).
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  static const _blueDark = Color(0xFF005EAB);
  static const _orange = Color(0xFFF39501);

  late final AnimationController _ctrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
    ..forward();
  late final Animation<double> _fade =
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
  late final Animation<double> _scale = Tween<double>(begin: 0.85, end: 1)
      .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _route());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _route() async {
    await Future.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;
    final loggedIn = Prefs.getString('userId').isNotEmpty &&
        Prefs.getString('isLoggedIn') == 'true';
    // Login always comes first. The config screen is only reachable with the
    // admin password (user "sup" + password, or the gear icon on the login page).
    Navigator.of(context).pushReplacementNamed(loggedIn ? '/menu' : '/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: FadeTransition(
                  opacity: _fade,
                  child: ScaleTransition(
                    scale: _scale,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.asset('assets/images/xlia_mark.png', width: 150),
                        const SizedBox(height: 20),
                        const Text(
                          'XLIA',
                          style: TextStyle(
                              fontSize: 34,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 2,
                              color: _blueDark),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(bottom: 40),
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 3, color: _orange),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
