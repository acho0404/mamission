import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:mamission/shared/widgets/status_badge.dart';
import 'package:mamission/shared/apple_appbar.dart';

class OffersPage extends StatefulWidget {
  final String missionId;
  final String posterId;

  const OffersPage({
    super.key,
    required this.missionId,
    required this.posterId,
  });

  @override
  State<OffersPage> createState() => _OffersPageState();
}

class _OffersPageState extends State<OffersPage> {
  static const Color kPrimary = Color(0xFF6C63FF);
  static const Color kBackground = Color(0xFFF6F3FF);

  /// Pour ne pas réanimer 50 fois les mêmes cartes
  final Set<String> _animatedOffers = {};

  @override
  Widget build(BuildContext context) {
    final offersRef = FirebaseFirestore.instance
        .collection('missions')
        .doc(widget.missionId)
        .collection('offers')
    // 🔹 On prend TOUTES les offres, tous statuts confondus
        .orderBy('createdAt', descending: true);

    return Scaffold(
      backgroundColor: kBackground,
      appBar: buildAppleMissionAppBar(
        title: "Offres reçues",
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: offersRef.snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(
                color: kPrimary,
              ),
            );
          }
          if (snap.hasError) {
            return Center(
              child: Text(
                "Erreur : ${snap.error}",
                style: const TextStyle(color: Colors.red),
              ),
            );
          }

          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) return _buildEmptyState();

          return ListView.separated(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
            itemCount: docs.length,
            separatorBuilder: (context, index) => const SizedBox(height: 14),
            itemBuilder: (context, i) {
              final doc = docs[i];
              final offerId = doc.id;

              final shouldAnimate = !_animatedOffers.contains(offerId);
              _animatedOffers.add(offerId);

              // ✨ Animation ultra légère à la première apparition
              return TweenAnimationBuilder<double>(
                tween: Tween(
                  begin: shouldAnimate ? 0.0 : 1.0,
                  end: 1.0,
                ),
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) {
                  return Opacity(
                    opacity: value,
                    child: Transform.translate(
                      offset: Offset(0, (1 - value) * 12),
                      child: child,
                    ),
                  );
                },
                child: _buildOfferCard(context, doc),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox_outlined, size: 90, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            "Aucune offre reçue",
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: const Color(0xFF2F2E41),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "Tu verras ici toutes les propositions\nsur ta mission.",
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  //  CARTE D'OFFRE – ULTRA LÉGÈRE & FLUIDE
  // ---------------------------------------------------------------------------
  Widget _buildOfferCard(
      BuildContext context,
      QueryDocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    final offer = doc.data();
    final offerId = doc.id;

    final photo = (offer['userPhoto'] ?? '') as String;
    final name = (offer['userName'] ?? 'Utilisateur').toString();
    final price = (offer['price'] ?? 0).toDouble();
    final ts = offer['createdAt'] as Timestamp?;
    final status = (offer['status'] ?? 'pending').toString();

    final date = ts != null
        ? DateFormat('d MMM à HH:mm', 'fr_FR').format(ts.toDate())
        : 'Date inconnue';

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        // 👉 Le détail gère le message, le bouton "Accepter", etc.
        context.push('/missions/${widget.missionId}/offers/$offerId');
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.97),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- HEADER ---
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Hero(
                    tag: 'offer_user_$offerId',
                    child: CircleAvatar(
                      radius: 26,
                      backgroundColor: Colors.grey.shade200,
                      backgroundImage:
                      photo.isNotEmpty ? NetworkImage(photo) : null,
                      child: photo.isEmpty
                          ? const Icon(
                        Icons.person_rounded,
                        color: Color(0xFF9CA3AF),
                        size: 26,
                      )
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Nom
                        Expanded(
                          child: Text(
                            name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15.5,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Prix + statut
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: kPrimary.withOpacity(0.06),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                "${price.toStringAsFixed(price.truncateToDouble() == price ? 0 : 2)} €",
                                style: const TextStyle(
                                  color: kPrimary,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14.5,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            StatusBadge(
                              type: 'offer',
                              status: status,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // --- FOOTER : date + flèche seulement ---
              Row(
                children: [
                  Icon(
                    Icons.schedule_rounded,
                    size: 15,
                    color: Colors.grey.shade500,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    date,
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 12,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    decoration: BoxDecoration(
                      color: kPrimary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    padding: const EdgeInsets.all(6),
                    child: const Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: kPrimary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
