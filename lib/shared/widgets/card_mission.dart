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

  // --- PALETTE PREMIUM ---
  static const Color _accentColor = Color(0xFF6C63FF);
  static const Color _primaryText = Color(0xFF1C1C1E);
  static const Color _secondaryText = Color(0xFF8E8E93);

  @override
  Widget build(BuildContext context) {
    final m = mission;

    final title = '${m['title'] ?? 'Mission'}';
    final budget = '${m['budget'] ?? 0} €';
    final location = '${m['location'] ?? 'Sur place'}';
    final status = m['status'] ?? 'open';
    final offersCount = m['offersCount'] ?? 0;
    final Timestamp? deadline = m['deadline'];

    final photo = (m['posterPhotoUrl'] != null &&
        '${m['posterPhotoUrl']}'.isNotEmpty)
        ? m['posterPhotoUrl']
        : null;

    final deadlineText = _getDeadlineText(deadline);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white, Color(0xFFF8F8F9)],
        ),
        boxShadow: [
          BoxShadow(
            color: _accentColor.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
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
          splashColor: _accentColor.withOpacity(0.05),
          highlightColor: _accentColor.withOpacity(0.02),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // --- BANDELETTE VIOLETTE ---
                Container(
                  width: 6,
                  color: _accentColor,
                ),

                // --- CONTENU ---
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // --- HEADER ---
                        // --- HEADER ---
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // TITRE + PRIX – FLEXIBLE (à gauche)
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: _primaryText,
                                      height: 1.2,
                                      letterSpacing: -0.2,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    budget,
                                    style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800,
                                      color: _accentColor,
                                      letterSpacing: -0.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(width: 16),

                            // PHOTO À DROITE
                            Hero(
                              tag:
                              'mission_poster_${m['id'] ?? title}_${photo ?? "x"}',
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.08),
                                      blurRadius: 8,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: CircleAvatar(
                                  radius: 26,
                                  backgroundColor: const Color(0xFFF2F2F7),
                                  backgroundImage:
                                  photo != null ? NetworkImage(photo) : null,
                                  child: photo == null
                                      ? const Icon(Icons.person,
                                      size: 26, color: _secondaryText)
                                      : null,
                                ),
                              ),
                            ),
                          ],
                        ),


                        const SizedBox(height: 16),

                        // --- CHIPS INFO ---
                        Wrap(
                          spacing: 10,
                          runSpacing: 8,
                          children: [
                            _greyChip(Icons.place_rounded, location),
                            _greyChip(
                                Icons.calendar_today_rounded, deadlineText),
                          ],
                        ),

                        const SizedBox(height: 20),

                        // --- STATUT + OFFRES ---
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            StatusBadge(type: 'mission', status: status),

                            if (status == 'open')
                              _offerChip(offersCount)
                            else if (status == 'in_progress')
                              _simpleStatus('En cours', Colors.blueAccent)
                            else if (status == 'done')
                                _simpleStatus('Terminée', Colors.green),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- WIDGETS ---

  Widget _greyChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F4F6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: _secondaryText),
          const SizedBox(width: 6),

          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.5,
                color: _secondaryText,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),

        ],
      ),
    );
  }



  Widget _offerChip(int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF2C2C2E),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.20),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.person, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            "$count offre${count > 1 ? 's' : ''}",
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _simpleStatus(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_rounded, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

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
}
