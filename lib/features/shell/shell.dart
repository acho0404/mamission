import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Importé pour SystemNavigator
import 'package:go_router/go_router.dart';

class ShellScaffold extends StatefulWidget {
  final Widget child;
  const ShellScaffold({super.key, required this.child});

  @override
  State<ShellScaffold> createState() => _ShellScaffoldState();
}

class _ShellScaffoldState extends State<ShellScaffold> {
  DateTime? _lastBackPressTime;
  static const _routes = ['/explore', '/missions', '/chat', '/profile'];

  // ✅ Fonction corrigée
  int _calculateCurrentIndex(BuildContext context) {
    // --- ✅ CORRECTION ICI ---
    // On récupère le "RouteMatchList"
    final RouteMatchList matchList = GoRouter.of(context).routerDelegate.currentConfiguration;
    // On prend l'URI de cette liste et on la convertit en String
    final String location = matchList.uri.toString();
    // --- ⛔ FIN CORRECTION ---

    // On trouve quel onglet correspond à la route actuelle
    if (location.startsWith(_routes[1])) return 1; // Missions
    if (location.startsWith(_routes[2])) return 2; // Chat
    if (location.startsWith(_routes[3])) return 3; // Profil
    return 0; // Explorer (par défaut)
  }


  void _onTap(int i) {
    // On navigue avec GoRouter. L'index sera mis à jour
    // automatiquement par le 'build' suivant.
    context.go(_routes[i]);
  }

  void _onPopInvoked(bool didPop) {
    if (didPop) return; // Si un pop a déjà eu lieu, on ne fait rien

    final int currentIndex = _calculateCurrentIndex(context);

    // 🔹 Si on n’est pas sur l’accueil → on revient à "Explorer"
    if (currentIndex != 0) {
      context.go(_routes[0]);
      return; // On ne quitte pas l'app
    }

    // 🔹 Si on est déjà sur l’accueil → double appui pour quitter
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
      // On ne quitte pas l'app (on attend le 2e clic)
    } else {
      // ✅ C'est le 2e clic, on quitte l'app
      SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = theme.colorScheme.primary;
    final inactive = Colors.grey.shade700;

    final items = const [
      (icon: Icons.explore, label: 'Explorer'),
      (icon: Icons.work_outline, label: 'Missions'),
      (icon: Icons.chat_bubble_outline, label: 'Chat'),
      (icon: Icons.person_outline, label: 'Profil'),
    ];

    // ✅ On calcule l'index à chaque build, basé sur GoRouter
    final int currentIndex = _calculateCurrentIndex(context);

    return PopScope(
      canPop: false, // On gère le "retour" nous-mêmes
      onPopInvoked: _onPopInvoked, // 👈 On utilise la nouvelle méthode
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        body: widget.child,
        bottomNavigationBar: SafeArea(
          minimum: const EdgeInsets.only(bottom: 6),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            height: 72,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: active.withOpacity(0.25),
                width: 1.2,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x11000000),
                  blurRadius: 10,
                  offset: Offset(0, -1),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(items.length, (i) {
                final item = items[i];
                // ✅ On utilise currentIndex (calculé) au lieu de _index (état)
                final selected = currentIndex == i;

                return InkWell(
                  onTap: () => _onTap(i),
                  splashColor: Colors.transparent,
                  highlightColor: Colors.transparent,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Transform.translate(
                      offset: Offset(0, selected ? -2 : 0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AnimatedScale(
                            scale: selected ? 1.15 : 1.0,
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOutBack,
                            child: Icon(
                              item.icon,
                              size: 26,
                              color: selected ? active : inactive,
                            ),
                          ),
                          const SizedBox(height: 4),
                          AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 180),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w400,
                              color: selected ? active : inactive,
                              letterSpacing: 0.1,
                            ),
                            child: Text(item.label),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}