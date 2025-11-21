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

  // Couleurs premium
  static const Color _accentColor = Color(0xFF6C63FF);
  static const Color _darkText = Color(0xFF1A1A1A);
  static const Color _subText = Color(0xFF88889D);
  static const Color _bgWhite = Colors.white;

  @override
  Widget build(BuildContext context) {
    final title = missionData['title'] ?? 'Mission inconnue';
    final location = missionData['location'] ?? '—';
    final photo = missionData['photoUrl'];
    final offerPrice = offerData['price'] ?? 0;
    final offerStatus = offerData['status'] ?? 'pending';

    // 🔥 SI OFFRE ANNULÉE → Design "Ghost" (Désactivé mais propre)
    if (offerStatus == 'cancelled') {
      return _buildCancelledCard(title);
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: _bgWhite,
        borderRadius: BorderRadius.circular(24),
        // Ombre subtile et colorée (Glow effect léger)
        boxShadow: [
          BoxShadow(
            color: _accentColor.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          splashColor: _accentColor.withOpacity(0.05),
          highlightColor: _accentColor.withOpacity(0.02),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ----------------------- HEADER -----------------------
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // PHOTO AVEC EFFET DE PROFONDEUR
                    Hero(
                      tag: 'mission_photo_${missionData['id'] ?? title}',
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: (photo != null && '$photo'.isNotEmpty)
                              ? Image.network(
                            '$photo',
                            width: 60,
                            height: 60,
                            fit: BoxFit.cover,
                          )
                              : Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.grey.shade100,
                                  Colors.grey.shade300
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                            child: Icon(Icons.work_outline_rounded,
                                color: Colors.grey.shade500, size: 28),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(width: 16),

                    // INFO COLONNE
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ROW: Title + Badge alignés intelligemment
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.3,
                                    color: _darkText,
                                    fontFamily: 'Plus Jakarta Sans', // Idée font
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 6),

                          // LOCATION CHIP SIMPLIFIÉ
                          Row(
                            children: [
                              Icon(Icons.location_on_rounded,
                                  size: 14, color: _accentColor),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  location,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: _subText,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 10),

                          // BADGE DÉPLACÉ ICI POUR L'ÉQUILIBRE
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Transform.scale(
                              scale: 0.9,
                              alignment: Alignment.centerLeft,
                              child: StatusBadge(type: 'offer', status: offerStatus),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // LIGNE DE SÉPARATION SUBTILE
                Divider(height: 1, color: Colors.grey.withOpacity(0.1)),
                const SizedBox(height: 16),

                // -------------------- BOTTOM ROW ----------------------
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // PRICE BLOCK
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Votre offre".toUpperCase(), // <--- On le fait ici
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _subText.withOpacity(0.7),
                            // plus de 'uppercase: true' ici
                          ),
                        ),
                        const SizedBox(height: 2),
                        RichText(
                          text: TextSpan(
                            children: [
                              TextSpan(
                                text: "$offerPrice",
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  color: _darkText,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              const TextSpan(
                                text: " €",
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  color: _accentColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const Spacer(),

                    // ACTION BUTTON (Arrondi et moderne)
                    ElevatedButton(
                      onPressed: onTap,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF4F2FF), // Light Purple bg
                        foregroundColor: _accentColor,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 14),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Text(
                            "Détails",
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(width: 6),
                          Icon(Icons.arrow_forward_rounded, size: 16),
                        ],
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

  // ----------------------- CARD ANNULÉE (GHOST) -------------------------
  Widget _buildCancelledCard(String title) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA), // Gris très clair
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFEBEE), // Rouge très pâle
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.close_rounded,
                color: Color(0xFFE57373), size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade400, // Texte "off"
                    decoration: TextDecoration.lineThrough, // Barré
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  "Offre annulée",
                  style: TextStyle(
                    color: Color(0xFFE57373),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}