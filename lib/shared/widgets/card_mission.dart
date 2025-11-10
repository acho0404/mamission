import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mamission/shared/widgets/status_badge.dart';

class _ChipStyle {
  final Color backgroundColor;
  final Color foregroundColor;
  final Color? iconColor;

  const _ChipStyle({
    required this.backgroundColor,
    required this.foregroundColor,
    this.iconColor,
  });
}

class CardMission extends StatelessWidget {
  final Map<String, dynamic> mission;
  final VoidCallback? onTap;

  const CardMission({
    super.key,
    required this.mission,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final m = mission;
    final title = '${m['title'] ?? 'Mission'}';
    final budget = '${m['budget'] ?? 0} €';
    final location = '${m['location'] ?? 'Sur place'}';
    final status = m['status'] ?? 'open';
    final offersCount = m['offersCount'] ?? 0;
    final flexibility = '${m['flexibility'] ?? 'Flexible'}';
    final Timestamp? deadline = m['deadline'];

    final (deadlineText, deadlineIconColor) = _getDeadlineInfo(deadline);

    const Color accentColor = Color(0xFF6C63FF);

    final _ChipStyle defaultChipStyle = const _ChipStyle(
      backgroundColor: Color(0xFFF0F0F0),
      foregroundColor: Color(0xFF4A4A4A),
      iconColor: Color(0xFF5E5E6D),
    );

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE0E0E0), width: 1),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF505090).withOpacity(0.1),
            blurRadius: 22,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 6,
              decoration: const BoxDecoration(
                color: accentColor,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20),
                  bottomLeft: Radius.circular(20),
                ),
              ),
            ),
            Expanded(
              child: Material(
                color: Colors.transparent,
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                ),
                child: InkWell(
                  onTap: onTap,
                  splashColor: accentColor.withOpacity(0.1),
                  highlightColor: accentColor.withOpacity(0.1),
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(20),
                    bottomRight: Radius.circular(20),
                  ),
                  child: Padding(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // --- HEADER ---
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: (m['photoUrl'] != null &&
                                  '${m['photoUrl']}'.isNotEmpty)
                                  ? Image.network(
                                '${m['photoUrl']}',
                                width: 52,
                                height: 52,
                                fit: BoxFit.cover,
                              )
                                  : Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: const Icon(
                                  Icons.work_outline,
                                  color: Color(0xFFBDBDBD),
                                  size: 28,
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF1A1A1A),
                                      fontSize: 17,
                                      height: 1.3,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    budget,
                                    style: const TextStyle(
                                      color: accentColor,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // --- INFOS (Chips) ---
                        Wrap(
                          spacing: 8.0,
                          runSpacing: 6.0,
                          children: [
                            _buildInfoChip(
                              icon: Icons.location_on_outlined,
                              text: location,
                              style: defaultChipStyle,
                            ),
                            _buildInfoChip(
                              icon: Icons.calendar_month_outlined,
                              text: deadlineText,
                              style: _ChipStyle(
                                backgroundColor:
                                defaultChipStyle.backgroundColor,
                                foregroundColor:
                                defaultChipStyle.foregroundColor,
                                iconColor: deadlineIconColor,
                              ),
                            ),
                            _buildInfoChip(
                              icon: Icons.access_time_outlined,
                              text: flexibility,
                              style: defaultChipStyle,
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // --- FOOTER ---
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            StatusBadge(type: 'mission', status: status),

                            // logique dynamique ici ↓↓↓
                            if (status == 'open')
                              _buildOfferCounter(offersCount, accentColor)
                            else if (status == 'in_progress')
                Row(
            children: [
            const Icon(Icons.handshake_outlined, size: 14, color: Color(0xFF1E8E3E)),
            const SizedBox(width: 4),
            Text(
              'En cours avec un prestataire',
              style: const TextStyle(
                color: Color(0xFF1E8E3E),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        )

          else if (status == 'completed')
                                const Text(
                                  'Mission terminée ✅',
                                  style: TextStyle(
                                    color: Colors.green,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOfferCounter(int count, Color accentColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: accentColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.person_outline, size: 16, color: accentColor),
          const SizedBox(width: 6),
          Text(
            '$count offre${count <= 1 ? '' : 's'}',
            style: TextStyle(
              color: accentColor,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildInfoChip({
    required IconData icon,
    required String text,
    required _ChipStyle style,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: style.backgroundColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: style.iconColor ?? style.foregroundColor),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: style.foregroundColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  (String, Color) _getDeadlineInfo(Timestamp? deadline) {
    const urgentColor = Color(0xFFF57C00);
    const expiredColor = Color(0xFFD32F2F);
    const approachingColor = Color(0xFF388E3C);
    const defaultIconColor = Color(0xFF5E5E6D);

    if (deadline == null) return ('Non spécifiée', defaultIconColor);

    final date = deadline.toDate();
    final now = DateTime.now();
    final diff = date.difference(now).inDays;

    if (date.isBefore(now.subtract(const Duration(days: 1)))) {
      return ('Expirée', expiredColor);
    }
    if (diff == 0) return ('Aujourd’hui', urgentColor);
    if (diff == 1) return ('Demain', defaultIconColor);
    if (diff > 1 && diff < 7) return ('Dans $diff jours', approachingColor);

    return ('Le ${DateFormat('dd/MM/yyyy').format(date)}', defaultIconColor);
  }
}
