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
          case 'completed':
            return {
              'bg': const Color(0xFFDDE8FF), // Bleu clair
              'txt': const Color(0xFF2A61FF), // Bleu moyen
              'label': 'Terminée',
              'icon': Icons.check_circle_outline,
            };

          case 'closed':
            return {
              'bg': const Color(0xFFEAE4FF), // Violet clair
              'txt': const Color(0xFF6C63FF), // Violet principal
              'label': 'Clôturée',
              'icon': Icons.lock_outline,
            };

          case 'cancelled':
            return {
              'bg': const Color(0xFFFFE4E4), // Rouge clair
              'txt': const Color(0xFFD32F2F), // Rouge foncé
              'label': 'Annulée',
              'icon': Icons.cancel_rounded,
            };

          default:
            return {
              'bg': Colors.grey.shade200,
              'txt': Colors.black87,
              'label': status,
              'icon': Icons.info_outline_rounded,
            };
        }


    // ──────────────────────────────
    // 🟡 OFFRES
    // ──────────────────────────────
      case 'offer':
        switch (status) {
        // Offre envoyée / en attente (mission ouverte)
          case 'pending':
            return {
              'bg': const Color(0xFFFFF5DA), // Jaune clair
              'txt': const Color(0xFFB38700), // Jaune foncé
              'label': 'En attente',
              'icon': Icons.hourglass_empty_rounded,
            };

        // Offre acceptée (mission en cours ou terminée)
          case 'accepted':
            return {
              'bg': const Color(0xFFDFF6E3), // Vert clair
              'txt': const Color(0xFF1E8E3E), // Vert foncé
              'label': 'Acceptée',
              'icon': Icons.check_circle_rounded,
            };

        // Refus explicite de cette offre
          case 'refused':
          case 'declined':
            return {
              'bg': const Color(0xFFFFE4E4), // Rouge clair
              'txt': const Color(0xFFD32F2F), // Rouge foncé
              'label': 'Refusée',
              'icon': Icons.cancel_rounded,
            };

        // Offres en négociation (contre-offres)
          case 'countered':
          case 'negotiating':
            return {
              'bg': Colors.orange.shade50,
              'txt': Colors.orange.shade700,
              'label': 'En négociation',
              'icon': Icons.swap_horiz_rounded,
            };

        // Offre annulée par le prestataire (retirée)
          case 'cancelled':
            return {
              'bg': Colors.grey.shade200,
              'txt': Colors.grey.shade700,
              'label': 'Annulée',
              'icon': Icons.remove_circle_outline,
            };

        // Mission attribuée à quelqu’un d’autre
          case 'not_selected':
            return {
              'bg': const Color(0xFFF2F2F7), // Gris très clair
              'txt': const Color(0xFF8E8E93), // Gris iOS
              'label': 'Non retenue',
              'icon': Icons.info_outline_rounded,
            };

        // Mission annulée après cette offre
          case 'mission_cancelled':
            return {
              'bg': const Color(0xFFFFE4E4), // Rouge clair
              'txt': const Color(0xFFD32F2F), // Rouge foncé
              'label': 'Mission annulée',
              'icon': Icons.report_problem_rounded,
            };

        // Offre expirée (deadline dépassée)
          case 'expired':
            return {
              'bg': const Color(0xFFF5F5F5),
              'txt': const Color(0xFF9E9E9E),
              'label': 'Expirée',
              'icon': Icons.schedule_outlined,
            };
// Mission terminée / fermée après cette offre
          case 'mission_done':
          case 'closed':
            return {
              'bg': const Color(0xFFDDE8FF), // Bleu clair
              'txt': const Color(0xFF2A61FF), // Bleu foncé
              'label': 'Mission terminée',
              'icon': Icons.done_all_rounded,
            };
        // Mission terminée après acceptation de cette offre
          case 'completed':
            return {
              'bg': const Color(0xFFDDE8FF), // Bleu clair
              'txt': const Color(0xFF2A61FF), // Bleu foncé
              'label': 'Mission terminée',
              'icon': Icons.done_all_rounded,
            };


        // Fallback offres
          default:
            return {
              'bg': Colors.grey.shade200,
              'txt': Colors.black87,
              'label': status,
              'icon': Icons.help_outline_rounded,
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
