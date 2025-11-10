import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../app/router.dart';

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  DateTime? _lastBackPressTime;

  Future<bool> _onWillPop(BuildContext context) async {
    final router = GoRouter.of(context);
    final routeState = router.routerDelegate.currentConfiguration.last;
    final location = routeState.matchedLocation;

    // Liste des routes principales (onglets)
    const mainTabs = ['/explore', '/missions', '/chat', '/profile'];

    if (location != '/explore' && mainTabs.contains(location)) {
      router.go('/explore');
      return false;
    }

    final now = DateTime.now();
    if (_lastBackPressTime == null ||
        now.difference(_lastBackPressTime!) > const Duration(seconds: 2)) {
      _lastBackPressTime = now;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Appuyez encore pour quitter'),
          backgroundColor: Color(0xFF6C63FF),
          duration: Duration(seconds: 2),
        ),
      );
      return false;
    }

    return true;
  }


  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'MaMission',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF6C63FF),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF8F6FF),
      ),
      routerConfig: buildRouter(),
      builder: (context, child) {
        return WillPopScope(
          onWillPop: () => _onWillPop(context),
          child: child ??
              const Scaffold(
                body: Center(
                  child: Text(
                    'Aucune page trouvée ⚠️',
                    style: TextStyle(fontSize: 18, color: Colors.black54),
                  ),
                ),
              ),
        );
      },
    );
  }
}
