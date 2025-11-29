import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mamission/shared/widgets/status_badge.dart';

class CardMission extends StatelessWidget {
  final Map<String, dynamic> mission;
  final VoidCallback? onTap;

  const CardMission({
    super.key,
    required this.mission,
    this.onTap,
  });

  // --- PALETTE FUTURISTE (Light Mode) ---
  static const Color _neonPrimary = Color(0xFF6C63FF); // Violet électrique
  static const Color _neonCyan = Color(0xFF00B8D4); // Cyan
  static const Color _textDark = Color(0xFF1A1F36); // Noir profond
  static const Color _textGrey = Color(0xFF6E7787); // Gris tech

  @override
  Widget build(BuildContext context) {
    final m = mission;

    final title = '${m['title'] ?? 'Mission'}';
    final budget = '${m['budget'] ?? 0} €';
    final location = '${m['location'] ?? 'Sur place'}';
    final String rawStatus = (m['status'] ?? 'open').toString();
    final String status = _normalizeMissionStatus(rawStatus);
    final offersCount = m['offersCount'] ?? 0;
    final Timestamp? deadline = m['deadline'];

    final photo = (m['posterPhotoUrl'] != null &&
        '${m['posterPhotoUrl']}'.isNotEmpty)
        ? m['posterPhotoUrl']
        : null;

    final deadlineText = _getDeadlineText(deadline);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      // --- DÉCORATION GLASSMORPHISM / FUTURISTE ---
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.8), // Fond blanc translucide
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white, width: 1.5), // Bordure nette
        boxShadow: [
          // Ombre portée colorée (Glow effect)
          BoxShadow(
            color: _neonPrimary.withOpacity(0.15),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
          // Ombre de profondeur légère
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          splashColor: _neonPrimary.withOpacity(0.1),
          highlightColor: _neonCyan.withOpacity(0.05),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // --- LIGNE DU HAUT : HEADER ---
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. INDICATEUR VISUEL (Barre dégradée)
                    Container(
                      width: 4,
                      height: 45,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        gradient: const LinearGradient(
                          colors: [_neonPrimary, _neonCyan],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _neonPrimary.withOpacity(0.4),
                            blurRadius: 6,
                          )
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),

                    // 2. TITRE ET PRIX
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800, // Très gras
                              color: _textDark,
                              height: 1.2,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 6),
                          // PRIX AVEC STYLE NÉON
                          Text(
                            budget,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: _neonPrimary, // Prix en violet
                              letterSpacing: -0.5,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 12),

                    // 3. AVATAR (Avec bordure lumineuse)
                    Hero(
                      tag:
                      'mission_poster_${m['id'] ?? title}_${photo ?? "x"}',
                      child: Container(
                        padding: const EdgeInsets.all(2), // Espace bordure
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [_neonPrimary, _neonCyan],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: _neonPrimary.withOpacity(0.2),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: CircleAvatar(
                          radius: 24,
                          backgroundColor: Colors.white,
                          backgroundImage:
                          photo != null ? NetworkImage(photo) : null,
                          child: photo == null
                              ? const Icon(Icons.person,
                              size: 24, color: _textGrey)
                              : null,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // --- LIGNE DU MILIEU : ADRESSE + DATE SUR UNE SEULE LIGNE ---
                Row(
                  children: [
                    // Adresse : prend tout l'espace restant, se coupe avec ...
                    Expanded(
                      child: _glassChip(
                        Icons.place_outlined,
                        location,
                        maxLines: 1,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Date : taille minimale, jamais sur 2 lignes
                    _glassChip(
                      Icons.calendar_today_outlined,
                      deadlineText,
                      maxLines: 1,
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // --- LIGNE DU BAS : STATUT & OFFRES ---
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    StatusBadge(type: 'mission', status: status),

                    if (status == 'open') _gradientOfferChip(offersCount),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- WIDGETS INTERNES ---

  // Chip style "Verre" (Fond blanc léger, bordure fine)
  Widget _glassChip(
      IconData icon,
      String text, {
        int maxLines = 1,
      }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: _neonPrimary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                color: _textGrey,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Badge Offres avec dégradé complet
  Widget _gradientOfferChip(int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_neonPrimary, Color(0xFF4F46E5)], // Violet vers Indigo
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _neonPrimary.withOpacity(0.4),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.people_alt_rounded, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            "$count offre${count > 1 ? 's' : ''}",
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  // --- HELPERS ---

  String _getDeadlineText(Timestamp? t) {
    if (t == null) return 'Non spécifiée';
    final date = t.toDate();
    final now = DateTime.now();
    final dateOnly = DateTime(date.year, date.month, date.day);
    final nowOnly = DateTime(now.year, now.month, now.day);
    final diff = dateOnly.difference(nowOnly).inDays;

    if (diff < 0) return 'Expirée';
    if (diff == 0) return 'Aujourd’hui';
    if (diff == 1) return 'Demain';
    return DateFormat('dd MMM', 'fr_FR').format(date);
  }

  String _normalizeMissionStatus(String raw) {
    raw = raw.toLowerCase();

    // alias back-end → front propre
    if (raw == 'completed') return 'done'; // Terminée
    if (raw == 'inprogress') return 'in_progress';

    return raw; // open, in_progress, done, cancelled, closed...
  }
}
