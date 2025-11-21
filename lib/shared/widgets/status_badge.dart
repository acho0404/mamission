import 'package:flutter/material.dart';

class StatusBadge extends StatelessWidget {
  final String type; // "mission" ou "offer"
  final String status;

  const StatusBadge({super.key, required this.type, required this.status});

  @override
  Widget build(BuildContext context) {
    final s = _data();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: s['bg'],
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        transitionBuilder: (child, anim) =>
            FadeTransition(opacity: anim, child: child),
        child: Row(
          key: ValueKey('$type-$status'),
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(s['icon'], color: s['txt'], size: 14),
            const SizedBox(width: 5),
            Text(
              s['label'],
              style: TextStyle(
                color: s['txt'],
                fontWeight: FontWeight.w600,
                fontSize: 12,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Map<String, dynamic> _data() {
    switch (type) {
    // ──────────────────────────────
    // 🟣 MISSIONS
    // ──────────────────────────────
      case 'mission':
        switch (status) {
          case 'open':
            return {
              'bg': const Color(0xFFEAE4FF), // Violet clair
              'txt': const Color(0xFF6C63FF), // Violet principal
              'label': 'Ouverte',
              'icon': Icons.hourglass_empty_rounded,
            };
          case 'in_progress':
            return {
              'bg': const Color(0xFFDFF6E3), // Vert clair
              'txt': const Color(0xFF1E8E3E), // Vert foncé
              'label': 'En cours',
              'icon': Icons.play_circle_fill_rounded,
            };
          case 'done':
            return {
              'bg': const Color(0xFFDDE8FF), // Bleu clair
              'txt': const Color(0xFF2A61FF), // Bleu moyen
              'label': 'Terminée',
              'icon': Icons.check_circle_outline,
            };

          default:
            return {
              'bg': const Color(0xFFFFE4E4), // Rouge clair
              'txt': const Color(0xFFD32F2F), // Rouge foncé
              'label': 'Annulée',
              'icon': Icons.cancel_rounded,
            };
        }

    // ──────────────────────────────
    // 🟡 OFFRES
    // ──────────────────────────────
      case 'offer':
        switch (status) {
          case 'pending':
            return {
              'bg': const Color(0xFFFFF5DA), // Jaune clair
              'txt': const Color(0xFFB38700), // Jaune foncé
              'label': 'En attente',
              'icon': Icons.hourglass_empty_rounded,
            };
          case 'accepted':
            return {
              'bg': const Color(0xFFDFF6E3), // Vert clair
              'txt': const Color(0xFF1E8E3E), // Vert foncé
              'label': 'Acceptée',
              'icon': Icons.check_circle_rounded,
            };
          case 'refused':
            return {
              'bg': const Color(0xFFFFE4E4), // Rouge clair
              'txt': const Color(0xFFD32F2F), // Rouge foncé
              'label': 'Refusée',
              'icon': Icons.cancel_rounded,
            };

          case 'countered':
            return {
              'bg': Colors.orange.shade50,
              'text': Colors.orange.shade700,
              'label': 'Contre-offre',
              'icon': Icons.swap_horiz_rounded,
            };



          default:
            return {
              'bg': const Color(0xFFDDE8FF), // Bleu clair
              'txt': const Color(0xFF2A61FF), // Bleu foncé
              'label': 'Terminée',
              'icon': Icons.done_all_rounded,
            };
        }

    // ──────────────────────────────
    // ⚙️ PAR DÉFAUT
    // ──────────────────────────────
      default:
        return {
          'bg': Colors.grey.shade200,
          'txt': Colors.black87,
          'label': status,
          'icon': Icons.help_outline_rounded,
        };
    }
  }
}
