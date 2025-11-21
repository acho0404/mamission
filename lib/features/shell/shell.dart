import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

class ShellScaffold extends StatefulWidget {
  final Widget child;
  const ShellScaffold({super.key, required this.child});

  @override
  State<ShellScaffold> createState() => _ShellScaffoldState();
}

class _ShellScaffoldState extends State<ShellScaffold> {
  DateTime? _lastBackPressTime;

  // --- ROUTES : inchangé ---
  static const _routes = [
    '/explore',        // index 0
    '/missions',       // index 1
    '/create-mission', // index 2 (special, jamais "sélectionné")
    '/chat',           // index 3
    '/profile',        // index 4
  ];

  int _calculateCurrentIndex(BuildContext context) {
    final location = GoRouter.of(context)
        .routerDelegate
        .currentConfiguration
        .uri
        .toString();

    if (location.startsWith('/missions')) return 1;
    if (location.startsWith('/create-mission')) return 2;
    if (location.startsWith('/chat')) return 3;
    if (location.startsWith('/profile')) return 4;
    return 0; // Explorer
  }

  void _onTap(int i) {
    HapticFeedback.lightImpact();
    context.go(_routes[i]);
  }

  void _onCreateTap() {
    HapticFeedback.lightImpact();
    context.push('/create-mission');
  }

  void _onPopInvoked(bool didPop) {
    if (didPop) return;

    final currentIndex = _calculateCurrentIndex(context);

    if (currentIndex != 0) {
      context.go('/explore');
      return;
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
    } else {
      SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFF6C63FF);
    const primarySoft = Color(0xFF9381FF);
    final inactive = Colors.grey.shade400;

    // ✅ On garde tes rôles d’icônes
    const items = [
      Icons.search_rounded,              // 0 Explorer
      Icons.work_outline_rounded,        // 1 Missions
      Icons.add,                         // 2 Créer (centre)
      Icons.chat_bubble_outline_rounded, // 3 Messages
      Icons.account_circle_outlined,     // 4 Profil
    ];

    final currentIndex = _calculateCurrentIndex(context);

    return PopScope(
      canPop: false,
      onPopInvoked: _onPopInvoked,
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        body: widget.child,
        bottomNavigationBar: SafeArea(
          top: false,
          child: SizedBox(
            height: 64, // 🔹 plus fin
            child: Stack(
              children: [
                // Fond blanc + légère ombre
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 12,
                          offset: const Offset(0, -3),
                        ),
                      ],
                    ),
                  ),
                ),

                // Quart de cercle violet discret
                Positioned(
                  left: -80,
                  bottom: -80,
                  child: Container(
                    width: 180,
                    height: 180,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [primary, primarySoft],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                  ),
                ),

                // Ligne d’icônes
                Positioned.fill(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // 0 - Explorer (sur violet)
                      _buildNavIcon(
                        icon: items[0],
                        index: 0,
                        currentIndex: currentIndex,
                        activeColorOnPurple: Colors.white,
                        activeColorOnWhite: primary,
                        inactiveColor: Colors.white.withOpacity(0.55),
                        isOnPurpleBackground: true,
                        onTap: () => _onTap(0),
                      ),

                      // 1 - Missions (sur blanc)
                      _buildNavIcon(
                        icon: items[1],
                        index: 1,
                        currentIndex: currentIndex,
                        activeColorOnPurple: Colors.white,
                        activeColorOnWhite: primary,
                        inactiveColor: inactive,
                        isOnPurpleBackground: false,
                        onTap: () => _onTap(1),
                      ),

                      // 2 - Créer (central, jamais sélectionné)
                      _buildCreateIcon(
                        icon: items[2],
                        onTap: _onCreateTap,
                      ),

                      // 3 - Messages
                      _buildNavIcon(
                        icon: items[3],
                        index: 3,
                        currentIndex: currentIndex,
                        activeColorOnPurple: Colors.white,
                        activeColorOnWhite: primary,
                        inactiveColor: inactive,
                        isOnPurpleBackground: false,
                        onTap: () => _onTap(3),
                      ),

                      // 4 - Profil
                      _buildNavIcon(
                        icon: items[4],
                        index: 4,
                        currentIndex: currentIndex,
                        activeColorOnPurple: Colors.white,
                        activeColorOnWhite: primary,
                        inactiveColor: inactive,
                        isOnPurpleBackground: false,
                        onTap: () => _onTap(4),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- Icône classique (sans texte) ---
  Widget _buildNavIcon({
    required IconData icon,
    required int index,
    required int currentIndex,
    required Color activeColorOnPurple,
    required Color activeColorOnWhite,
    required Color inactiveColor,
    required bool isOnPurpleBackground,
    required VoidCallback onTap,
  }) {
    final bool selected = currentIndex == index;
    final Color color;

    if (!selected) {
      color = inactiveColor;
    } else {
      color = isOnPurpleBackground ? activeColorOnPurple : activeColorOnWhite;
    }

    return InkWell(
      onTap: onTap,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: AnimatedScale(
          scale: selected ? 1.08 : 1.0,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          child: Icon(
            icon,
            size: selected ? 24 : 22,
            color: color,
          ),
        ),
      ),
    );
  }

  // --- Bouton central "Créer" ---
  Widget _buildCreateIcon({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    const primary = Color(0xFF6C63FF);
    const primarySoft = Color(0xFF9381FF);

    return InkWell(
      onTap: onTap,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [primary, primarySoft],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: primary.withOpacity(0.35),
                blurRadius: 12,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Center(
            child: Icon(
              icon,
              size: 22,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
