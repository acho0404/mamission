import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:mamission/shared/widgets/status_badge.dart';
import 'package:mamission/shared/services/notification_service.dart';

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
  Future<void> _handleAcceptOffer(Map<String, dynamic> offer, String offerId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Accepter cette offre ?"),
        content: Text(
          "Vous êtes sur le point d'accepter l'offre de ${offer['userName']} pour ${offer['price']} €.\n\nLa mission passera en statut 'En cours'.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Annuler", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6C63FF)),
            child: const Text("Confirmer", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final missionDoc = await FirebaseFirestore.instance
          .collection('missions')
          .doc(widget.missionId)
          .get();
      final missionTitle = missionDoc.data()?['title'] ?? 'Mission';

      final batch = FirebaseFirestore.instance.batch();

      final missionRef = FirebaseFirestore.instance
          .collection('missions')
          .doc(widget.missionId);

      batch.update(missionRef, {
        'status': 'in_progress',
        'assignedTo': offer['userId'],
        'agreedPrice': offer['price'],
        'updatedAt': FieldValue.serverTimestamp(),
      });

      final currentOfferRef = missionRef.collection('offers').doc(offerId);

      batch.update(currentOfferRef, {
        'status': 'accepted',
        'acceptedAt': FieldValue.serverTimestamp(),
      });

      await batch.commit();

      await NotificationService.notifyMissionAssigned(
        providerUserId: offer['userId'],
        missionId: widget.missionId,
        missionTitle: missionTitle,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Offre acceptée ! ${offer['userName']} a été notifié."),
            backgroundColor: const Color(0xFF6C63FF),
          ),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Erreur : $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final offersRef = FirebaseFirestore.instance
        .collection('missions')
        .doc(widget.missionId)
        .collection('offers')
        .where('status', whereIn: ['pending', 'accepted'])
        .orderBy('createdAt', descending: true);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F6FF),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        title: const Text("Offres reçues"),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF6C63FF), Color(0xFF7B6CFF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        foregroundColor: Colors.white,
        elevation: 1,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: offersRef.snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFF6C63FF)),
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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            itemCount: docs.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
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
            "Les offres pour cette mission apparaîtront ici.",
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.black54,
            ),
          ),
        ],
      ),
    );
  }

  // --- OFFRE CLIQUABLE → DÉTAIL ---
  Widget _buildOfferCard(
      BuildContext context,
      QueryDocumentSnapshot<Map<String, dynamic>> doc,
      ) {
    final offer = doc.data();
    final offerId = doc.id;
    final photo = offer['userPhoto'] ?? '';
    final name = offer['userName'] ?? 'Utilisateur';
    final msg = offer['message'] ?? '';
    final price = (offer['price'] ?? 0).toDouble();
    final ts = offer['createdAt'] as Timestamp?;
    final date = ts != null
        ? DateFormat('d MMM à HH:mm', 'fr_FR').format(ts.toDate())
        : 'Date inconnue';
    final status = offer['status'] ?? 'pending';
    final isAccepted = status == 'accepted';

    return GestureDetector(
      onTap: () {
        context.push('/missions/${widget.missionId}/offers/$offerId');
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: isAccepted
              ? Border.all(color: const Color(0xFF6C63FF), width: 2)
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Hero(
                  tag: 'offer_user_$offerId',
                  child: CircleAvatar(
                    radius: 28,
                    backgroundColor: Colors.grey.shade200,
                    backgroundImage: photo.isNotEmpty
                        ? NetworkImage(photo)
                        : const NetworkImage(
                      'https://cdn-icons-png.flaticon.com/512/149/149071.png',
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF2F2E41),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            "${price.toStringAsFixed(price.truncateToDouble() == price ? 0 : 2)} €",
                            style: const TextStyle(
                              color: Color(0xFF6C63FF),
                              fontWeight: FontWeight.bold,
                              fontSize: 17,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        msg.isNotEmpty ? msg : "Aucun message ajouté.",
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontSize: 14,
                          color:
                          msg.isNotEmpty ? Colors.black87 : Colors.black45,
                          fontStyle: msg.isNotEmpty
                              ? FontStyle.normal
                              : FontStyle.italic,
                          height: 1.4,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1, thickness: 0.5),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  date,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.black45,
                    fontSize: 12,
                  ),
                ),
                // 👉 plus de bouton "Accepter" ici, juste le statut
                StatusBadge(type: 'offer', status: status),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
