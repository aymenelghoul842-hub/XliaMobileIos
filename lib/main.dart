import 'package:flutter/material.dart';
import 'core/lang.dart';
import 'core/net.dart';
import 'core/prefs.dart';
import 'screens/config_screen.dart';
import 'screens/drawer_shell.dart';
import 'screens/login_screen.dart';
import 'screens/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Prefs.init();
  AppLang.load();
  Net.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'XLiaMobile',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2196F3)),
        scaffoldBackgroundColor: const Color(0xFFF4F6FA),
      ),
      builder: (context, child) =>
          ConnectionBanner(child: child ?? const SizedBox.shrink()),
      initialRoute: '/',
      routes: {
        '/': (_) => const SplashScreen(),
        '/login': (_) => const LoginScreen(),
        '/config': (_) => const ConfigScreen(),
        '/menu': (_) => const DrawerShell(),
      },
    );
  }
}
