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

  bool _isAccepting = false;

  Future<void> _acceptOffer(
      BuildContext context,
      String offerId,
      Map<String, dynamic> offer,
      ) async {
    if (_isAccepting) return;

    final db = FirebaseFirestore.instance;
    final missionRef = db.collection('missions').doc(widget.missionId);
    final offersRef = missionRef.collection('offers');

    setState(() => _isAccepting = true);

    try {
      final offerDoc = await offersRef.doc(offerId).get();
      if (!offerDoc.exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Offre introuvable."),
            backgroundColor: Colors.redAccent,
          ),
        );
        setState(() => _isAccepting = false);
        return;
      }

      final missionSnap = await missionRef.get();
      if (!missionSnap.exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Mission introuvable."),
            backgroundColor: Colors.redAccent,
          ),
        );
        setState(() => _isAccepting = false);
        return;
      }

      final mission = missionSnap.data()!;
      final missionStatus = (mission['status'] ?? 'open').toString();
      if (missionStatus != 'open') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Cette mission n'est plus ouverte (statut : $missionStatus).",
            ),
            backgroundColor: Colors.orange,
          ),
        );
        setState(() => _isAccepting = false);
        return;
      }

      final double assignedPrice =
      (offer['price'] ?? mission['budget'] ?? 0).toDouble();

      final batch = db.batch();

      // 👉 Mise à jour mission
      batch.update(missionRef, {
        'status': 'in_progress',
        'assignedTo': offer['userId'],
        'assignedPrice': assignedPrice,
        'acceptedOfferId': offerId,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // 👉 Accepte UNE offre, rejette les autres (sauf cancelled)
      final allOffersSnap = await offersRef.get();
      for (final doc in allOffersSnap.docs) {
        final data = doc.data();
        final currentStatus = (data['status'] ?? 'pending').toString();
        if (currentStatus == 'cancelled') continue;

        batch.update(doc.reference, {
          'status': doc.id == offerId ? 'accepted' : 'rejected',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Offre acceptée, mission en cours ✅"),
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Erreur lors de l'acceptation : $e"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isAccepting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final offersRef = FirebaseFirestore.instance
        .collection('missions')
        .doc(widget.missionId)
        .collection('offers')
        .where('status', whereIn: [
      'pending',
      'negotiating',
      'accepted',
      'countered',
    ])
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
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
            itemCount: docs.length,
            separatorBuilder: (context, index) => const SizedBox(height: 14),
            itemBuilder: (context, i) => _buildOfferCard(context, docs[i]),
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
  //  CARTE D'OFFRE – FULL UI UPGRADE
  // ---------------------------------------------------------------------------
  Widget _buildOfferCard(
      BuildContext context,
      QueryDocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    final offer = doc.data();
    final offerId = doc.id;

    final photo = (offer['userPhoto'] ?? '') as String;
    final name = (offer['userName'] ?? 'Utilisateur').toString();
    final msg = (offer['message'] ?? '').toString();
    final price = (offer['price'] ?? 0).toDouble();
    final ts = offer['createdAt'] as Timestamp?;
    final status = (offer['status'] ?? 'pending').toString();

    final date = ts != null
        ? DateFormat('d MMM à HH:mm', 'fr_FR').format(ts.toDate())
        : 'Date inconnue';

    final isAccepted = status == 'accepted';
    final isPending = status == 'pending' || status == 'negotiating';

    return GestureDetector(
      onTap: () {
        context.push('/missions/${widget.missionId}/offers/$offerId');
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.96),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isAccepted
                ? const Color(0xFF4ADE80).withOpacity(0.4)
                : Colors.white,
            width: isAccepted ? 1.4 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 22,
              offset: const Offset(0, 10),
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
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
                        const SizedBox(height: 6),
                        Text(
                          msg.isNotEmpty ? msg : "Aucun message ajouté.",
                          style: TextStyle(
                            fontSize: 13.5,
                            height: 1.4,
                            color: msg.isNotEmpty
                                ? const Color(0xFF374151)
                                : const Color(0xFF9CA3AF),
                            fontStyle:
                            msg.isNotEmpty ? FontStyle.normal : FontStyle.italic,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // --- FOOTER ---
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
                  if (isPending)
                    ElevatedButton(
                      onPressed:
                      _isAccepting ? null : () => _acceptOffer(context, offerId, offer),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kPrimary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      child: _isAccepting
                          ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                          : const Text(
                        "Accepter",
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    )
                  else if (isAccepted)
                    const Text(
                      "Offre acceptée ✅",
                      style: TextStyle(
                        color: Color(0xFF16A34A),
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    )
                  else
                    Text(
                      "Offre traitée",
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 13,
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
