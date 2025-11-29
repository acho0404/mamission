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

  // --- PALETTE FUTURISTE (Light Mode) ---
  static const Color _neonPrimary = Color(0xFF6C63FF); // Violet électrique
  static const Color _neonCyan = Color(0xFF00B8D4); // Cyan
  static const Color _textDark = Color(0xFF1A1F36); // Noir profond
  static const Color _textGrey = Color(0xFF6E7787); // Gris tech

  @override
  Widget build(BuildContext context) {
    final title = missionData['title'] ?? 'Mission';
    final location = missionData['location'] ?? '—';

    // --- Données mission / offre ---
    final String missionStatus =
    (missionData['status'] ?? 'open').toString().toLowerCase();
    final String assignedTo = (missionData['assignedTo'] ?? '').toString();

    final String offerUserId = (offerData['userId'] ?? '').toString();

    // prix : on prend toujours la dernière valeur connue
    final double offerPrice = ((offerData['lastPrice'] ??
        offerData['counterOffer'] ??
        offerData['price'] ??
        0) as num)
        .toDouble();

    final String rawOfferStatus =
    (offerData['status'] ?? 'pending').toString().toLowerCase();

    // statut “intelligent” en fonction mission + offre
    final String displayStatus = _computeEffectiveStatus(
      missionStatus: missionStatus,
      rawOfferStatus: rawOfferStatus,
      assignedTo: assignedTo,
      offerUserId: offerUserId,
    );


    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      // --- DÉCORATION GLASSMORPHISM / FUTURISTE (comme CardMission) ---
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.8),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: _neonPrimary.withOpacity(0.15),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
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
          splashColor: _neonPrimary.withOpacity(0.05),
          highlightColor: _neonCyan.withOpacity(0.05),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // --- LIGNE DU HAUT : BARRE + TITRE + PRIX ---
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Barre dégradée (comme CardMission)
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
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Titre + statut
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
                              color: _textDark,
                              letterSpacing: -0.3,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Transform.scale(
                            scale: 0.9,
                            alignment: Alignment.centerLeft,
                            child: StatusBadge(
                              type: 'offer',
                              status: displayStatus,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 12),

                    // Prix + flèche
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          "${offerPrice.toStringAsFixed(0)} €",
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                            color: _neonPrimary,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: _neonPrimary.withOpacity(0.08),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.arrow_forward_rounded,
                            size: 16,
                            color: _neonPrimary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // --- LIGNE DU MILIEU : VILLE SEULE, COMME UNE CHIP ---
                _glassChip(
                  Icons.place_outlined,
                  location.toString(),
                  maxLines: 1, // une seule ligne, "..." si trop long
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // CHIP VERRE (copie du style CardMission)
  // --------------------------------------------------------------------------
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

  // --------------------------------------------------------------------------
  // LOGIQUE STATUT (mission + offre)
  // --------------------------------------------------------------------------
  String _computeEffectiveStatus({
    required String missionStatus,
    required String rawOfferStatus,
    required String assignedTo,
    required String offerUserId,
  }) {
    missionStatus = missionStatus.toLowerCase();
    rawOfferStatus = rawOfferStatus.toLowerCase();

    // 1️⃣ Mission annulée → info importante côté prestataire
    if (missionStatus == 'cancelled') {
      return 'mission_cancelled';
    }

    // 2️⃣ Offre annulée par le prestataire
    if (rawOfferStatus == 'cancelled') {
      return 'cancelled';
    }

    // 3️⃣ Offre refusée / non retenue (explicite)
    if (rawOfferStatus == 'declined' || rawOfferStatus == 'refused') {
      return 'declined';
    }

    // 4️⃣ Offre expirée
    if (rawOfferStatus == 'expired') {
      return 'expired';
    }

    // 5️⃣ Offre acceptée → on RESTE sur "acceptée"
    //    même si la mission passe ensuite en done/closed
    if (rawOfferStatus == 'accepted') {
      return 'accepted';
    }

    // 6️⃣ Mission attribuée à quelqu’un d’autre → "Non retenue"
    if ((missionStatus == 'in_progress' ||
        missionStatus == 'done' ||
        missionStatus == 'completed' ||
        missionStatus == 'closed') &&
        assignedTo.isNotEmpty &&
        assignedTo != offerUserId) {
      return 'not_selected';
    }

    // 7️⃣ En négociation / contre-offre
    if (rawOfferStatus == 'negotiating' || rawOfferStatus == 'countered') {
      return 'negotiating';
    }

    // 8️⃣ Mission ouverte : offre en attente
    if (missionStatus == 'open' && rawOfferStatus == 'pending') {
      return 'pending';
    }

    // 9️⃣ Fallback : statut brut (mais on n’a plus "mission_done"/"closed" ici)
    return rawOfferStatus;
  }
}
