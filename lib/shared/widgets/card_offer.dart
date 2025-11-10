// lib/shared/widgets/card_offer.dart

import 'package:flutter/material.dart';
import 'package:mamission/shared/widgets/status_badge.dart';

class CardOffer extends StatelessWidget {
  final Map<String, dynamic> offerData;
  final Map<String, dynamic> missionData;
  final VoidCallback? onTap;

  const CardOffer({
    super.key,
    required this.offerData,
    required this.missionData,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // --- Données de la mission ---
    final missionTitle = missionData['title'] ?? 'Mission inconnue';
    final missionLocation = missionData['location'] ?? '—';
    final missionPhoto = missionData['photoUrl'];

    // --- Données de l'offre ---
    final offerPrice = offerData['price'] ?? 0;
    final offerStatus = offerData['status'] ?? 'pending';

    // --- Couleur d'accent ---
    const Color accentColor = Color(0xFF6C63FF);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE8E8E8), width: 1),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          splashColor: accentColor.withOpacity(0.08),
          highlightColor: accentColor.withOpacity(0.08),
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // --- Ligne haute : photo + titre + badge ---
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: (missionPhoto != null &&
                          '$missionPhoto'.isNotEmpty)
                          ? Image.network(
                        '$missionPhoto',
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                      )
                          : Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F1F1),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(
                          Icons.work_outline,
                          color: Color(0xFFBDBDBD),
                          size: 26,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Titre et localisation
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            missionTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1A1A1A),
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          _buildInfoChip(
                            icon: Icons.location_on_outlined,
                            text: missionLocation,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 8),

                    // --- Badge de statut ---
                    StatusBadge(type: 'offer', status: offerStatus),
                  ],
                ),

                const SizedBox(height: 16),

                // --- Bas : prix + bouton ---
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "$offerPrice €",
                      style: const TextStyle(
                        color: Color(0xFF1A1A1A),
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                    ),
                    ElevatedButton(
                      onPressed: onTap,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 10),
                        elevation: 0,
                      ),
                      child: const Text(
                        "Voir détails",
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- Chip info mission ---
  // --- Chip d'information (harmonisé avec CardMission) ---
  Widget _buildInfoChip({required IconData icon, required String text}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F0F0), // ✅ même fond que CardMission
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF5E5E6D)),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF4A4A4A),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
