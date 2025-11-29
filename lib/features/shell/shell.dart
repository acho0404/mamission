import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

class ShellScaffold extends StatefulWidget {
  final Widget child;
  const ShellScaffold({super.key, required this.child});

  @override
  State<ShellScaffold> createState() => _ShellScaffoldState();
}

class _ShellScaffoldState extends State<ShellScaffold>
    with TickerProviderStateMixin {
  DateTime? _lastBackPressTime;

  static const Color _neonPrimary = Color(0xFF6C63FF);
  static const Color _neonIndigo = Color(0xFF4F46E5);

  // ---------------------------------------------------------------------------
  // INDEX NAV EN FONCTION DE LA ROUTE
  // ---------------------------------------------------------------------------
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
    return 0; // explore par défaut
  }

  void _onTap(int i) {
    if (i == 2) {
      _onCreateTap();
      return;
    }
    HapticFeedback.selectionClick();
    switch (i) {
      case 0:
        context.go('/explore');
        break;
      case 1:
        context.go('/missions');
        break;
      case 3:
        context.go('/chat');
        break;
      case 4:
        context.go('/profile');
        break;
    }
  }

  void _onCreateTap() {
    HapticFeedback.mediumImpact();
    context.push('/create-mission');
  }

  void _onPopInvoked(bool didPop) {
    if (didPop) return;

    final currentIndex = _calculateCurrentIndex(context);
    // back = retour Explorer si on n'y est pas
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
          backgroundColor: _neonPrimary,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    } else {
      SystemNavigator.pop();
    }
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final currentIndex = _calculateCurrentIndex(context);
    final bool keyboardVisible = mq.viewInsets.bottom > 0;
    final double bottomPadding = mq.padding.bottom;

    return PopScope(
      canPop: false,
      onPopInvoked: _onPopInvoked,
      child: Scaffold(
        // 🔥 IMPORTANT : on laisse le Scaffold gérer le clavier
        resizeToAvoidBottomInset: true,
        backgroundColor: const Color(0xFFF3F6FF),
        extendBody: false,
        body: widget.child,
        // quand clavier ouvert => on cache la barre (zéro espace)
        bottomNavigationBar: keyboardVisible
            ? null
            : _buildBottomBar(
          currentIndex: currentIndex,
          bottomPadding: bottomPadding,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // BOTTOM BAR GLASSMORPHISM
  // ---------------------------------------------------------------------------
  Widget _buildBottomBar({
    required int currentIndex,
    required double bottomPadding,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // fin trait violet dégradé
        Container(
          height: 6,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color(0x406C63FF),
                Color(0x404F46E5),
              ],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
          ),
        ),
        ClipRRect(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.65),
                border: Border(
                  top: BorderSide(
                    color: Colors.white.withOpacity(0.4),
                    width: 0.6,
                  ),
                ),
              ),
              padding: EdgeInsets.only(
                left: 12,
                right: 12,
                top: 6,
                bottom: (bottomPadding > 0 ? bottomPadding : 12),
              ),
              child: SizedBox(
                height: 56,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _NavBarItem(
                      icon: Icons.search_rounded,
                      label: "Explorer",
                      index: 0,
                      currentIndex: currentIndex,
                      onTap: () => _onTap(0),
                    ),
                    _NavBarItem(
                      icon: Icons.assignment_rounded,
                      label: "Missions",
                      index: 1,
                      currentIndex: currentIndex,
                      onTap: () => _onTap(1),
                    ),
                    _NavBarItem(
                      icon: Icons.add_rounded,
                      label: "Créer",
                      index: 2,
                      currentIndex: currentIndex,
                      onTap: () => _onTap(2),
                    ),
                    _NavBarItem(
                      icon: Icons.chat_bubble_rounded,
                      label: "Messages",
                      index: 3,
                      currentIndex: currentIndex,
                      onTap: () => _onTap(3),
                    ),
                    _NavBarItem(
                      icon: Icons.person_rounded,
                      label: "Profil",
                      index: 4,
                      currentIndex: currentIndex,
                      onTap: () => _onTap(4),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// ITEM NAV
// ---------------------------------------------------------------------------
class _NavBarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final int index;
  final int currentIndex;
  final VoidCallback onTap;

  const _NavBarItem({
    required this.icon,
    required this.label,
    required this.index,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool isSelected = index == currentIndex;
    const Color activeBg = Color(0xFF6C63FF);
    const Color activeIcon = Colors.white;
    const Color inactiveIcon = Color(0xFF9CA3AF);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 60,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutBack,
              width: isSelected ? 48 : 24,
              height: 32,
              decoration: BoxDecoration(
                color: isSelected ? activeBg : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Center(
                child: Icon(
                  icon,
                  size: 24,
                  color: isSelected ? activeIcon : inactiveIcon,
                ),
              ),
            ),
            const SizedBox(height: 4),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                fontSize: 10,
                fontFamily: 'Plus Jakarta Sans',
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? activeBg : inactiveIcon,
              ),
              child: Text(label),
            ),
          ],
        ),
      ),
    );
  }
}
