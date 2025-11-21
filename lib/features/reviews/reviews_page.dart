import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// Notifications
import '../../shared/services/notification_service.dart';

class ReviewsPage extends StatefulWidget {
  final String userId;        // Celui qui reçoit l'avis
  final String missionId;     // Mission liée (peut être vide si on vient du profil)
  final String missionTitle;  // Titre mission

  const ReviewsPage({
    super.key,
    required this.userId,
    required this.missionId,
    required this.missionTitle,
  });

  @override
  State<ReviewsPage> createState() => _ReviewsPageState();
}

class _ReviewsPageState extends State<ReviewsPage> {
  /// Vérifie si l’utilisateur a déjà noté POUR CETTE MISSION
  Future<bool> _hasUserAlreadyReviewed() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || widget.missionId.isEmpty) return false;

    final snap = await FirebaseFirestore.instance
        .collection('reviews')
        .where('missionId', isEqualTo: widget.missionId)
        .where('reviewerId', isEqualTo: uid)
        .limit(1)
        .get();

    return snap.docs.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final isOwnProfile = currentUid == widget.userId;

    // 🔹 CAS 1 : on vient du PROFIL → pas de missionId, on ignore complètement la mission
    if (widget.missionId.isEmpty || widget.missionId == 'none') {
      return _buildReviewsScaffold(
        isOwnProfile: isOwnProfile,
        canLeaveReview: false, // pas de bouton "laisser un avis"
      );
    }

    // 🔹 CAS 2 : on vient d'une mission terminée → missionId présent
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance
          .collection('missions')
          .doc(widget.missionId)
          .get(),
      builder: (context, missionSnap) {
        // Attente du doc mission
        if (missionSnap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: Color(0xFF6C63FF)),
            ),
          );
        }

        // Erreur ou mission inexistante → on affiche juste la liste d'avis (pas de bouton)
        if (!missionSnap.hasData || !missionSnap.data!.exists) {
          return _buildReviewsScaffold(
            isOwnProfile: isOwnProfile,
            canLeaveReview: false,
          );
        }

        final mission = missionSnap.data!;
        final assigned = mission.data()?['assignedTo'] ?? '';

        // 🔒 Aucun prestataire assigné → pas d'avis possible pour cette mission
        if (assigned.isEmpty) {
          return const Scaffold(
            body: Center(
              child: Padding(
                padding: EdgeInsets.all(20.0),
                child: Text(
                  "Aucun prestataire n’a été assigné à cette mission.",
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
              ),
            ),
          );
        }

        // Mission OK → on affiche les avis + bouton pour laisser un avis
        return _buildReviewsScaffold(
          isOwnProfile: isOwnProfile,
          canLeaveReview: true,
        );
      },
    );
  }

  // -----------------------------------------------------------
  // SCAFFOLD PRINCIPAL
  // -----------------------------------------------------------
  Widget _buildReviewsScaffold({
    required bool isOwnProfile,
    required bool canLeaveReview,
  }) {
    final reviewsQuery = FirebaseFirestore.instance
        .collection('reviews')
        .where('targetUserId', isEqualTo: widget.userId)
        .orderBy('createdAt', descending: true);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD),
      appBar: AppBar(
        title: const Text('Avis & Notes', style: TextStyle(color: Colors.black)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: reviewsQuery.snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFF6C63FF)),
            );
          }

          if (snap.hasError) {
            return const Center(
              child: Text(
                "Erreur lors du chargement des avis.",
                style: TextStyle(color: Colors.redAccent),
              ),
            );
          }

          if (!snap.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFF6C63FF)),
            );
          }

          final docs = snap.data!.docs;

          // ---- Calcul moyenne ----
          double avg = 0;
          if (docs.isNotEmpty) {
            final totalRating = docs.fold<double>(0, (sum, doc) {
              final data = doc.data() as Map<String, dynamic>;
              return sum + ((data['rating'] ?? 0) as num).toDouble();
            });
            avg = totalRating / docs.length;
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildHeader(avg, docs.length),
              const SizedBox(height: 16),
              if (docs.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(30.0),
                  child: Text(
                    "Aucun avis pour le moment.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              else
                ...docs.map(
                      (d) => _buildReviewCard(d.data() as Map<String, dynamic>),
                ),
            ],
          );
        },
      ),

      // FAB
      floatingActionButton:
      (!canLeaveReview || isOwnProfile) // 🔒 pas de bouton dans ces cas
          ? null
          : FloatingActionButton.extended(
        onPressed: () async {
          // Vérifie si déjà noté cette mission
          final already = await _hasUserAlreadyReviewed();
          if (already) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("Vous avez déjà donné votre avis."),
                backgroundColor: Colors.grey,
              ),
            );
            return;
          }
          _openReviewModal(context);
        },
        label: const Text('Laisser un avis'),
        icon: const Icon(Icons.edit_rounded),
        backgroundColor: const Color(0xFF6C63FF),
      ),
    );
  }

  // -----------------------------------------------------------
  // HEADER
  // -----------------------------------------------------------
  Widget _buildHeader(double avg, int total) {
    const violet = Color(0xFF6C63FF);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [violet.withOpacity(0.9), violet.withOpacity(0.75)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: violet.withOpacity(0.25),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            avg.toStringAsFixed(1),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 56,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) {
              if (i < avg.floor()) {
                return const Icon(Icons.star_rounded, color: Colors.amber, size: 30);
              } else if (i < avg && (avg - i) >= 0.5) {
                return const Icon(Icons.star_half_rounded, color: Colors.amber, size: 30);
              } else {
                return Icon(
                  Icons.star_outline_rounded,
                  color: Colors.amber.shade100,
                  size: 30,
                );
              }
            }),
          ),
          const SizedBox(height: 10),
          Text(
            '$total avis',
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
        ],
      ),
    );
  }

  // -----------------------------------------------------------
  // CARTE AVIS
  // -----------------------------------------------------------
  Widget _buildReviewCard(Map<String, dynamic> data) {
    final note = (data['rating'] as num?)?.toDouble() ?? 0.0;
    final comment = data['comment'] ?? '';
    final name = data['reviewerName'] ?? 'Utilisateur';
    final photo = data['reviewerPhoto'];
    final date = (data['createdAt'] as Timestamp?)?.toDate();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundImage:
                (photo != null && photo.isNotEmpty) ? NetworkImage(photo) : null,
                radius: 20,
                backgroundColor: Colors.grey.shade200,
                child: (photo == null || photo.isEmpty)
                    ? const Icon(Icons.person, color: Colors.grey)
                    : null,
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15)),
                  if (date != null)
                    Text(
                      DateFormat('d MMM yyyy', 'fr_FR').format(date),
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                ],
              ),
              const Spacer(),
              Row(
                children: [
                  const Icon(Icons.star_rounded,
                      color: Colors.amber, size: 18),
                  const SizedBox(width: 3),
                  Text(
                    note.toString(),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.amber),
                  ),
                ],
              )
            ],
          ),
          if (comment.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              comment,
              style: const TextStyle(color: Color(0xFF4A4A4A), height: 1.4),
            ),
          ]
        ],
      ),
    );
  }

  // -----------------------------------------------------------
  // MODAL D’AJOUT D'AVIS
  // -----------------------------------------------------------
  void _openReviewModal(BuildContext context) {
    double selectedRating = 0;
    final ctrl = TextEditingController();
    bool isLoading = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
            left: 20,
            right: 20,
            top: 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Laisser un avis',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),

              // Étoiles
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) {
                  return IconButton(
                    iconSize: 40,
                    onPressed: () async {
                      final missionSnap = await FirebaseFirestore.instance
                          .collection('missions')
                          .doc(widget.missionId)
                          .get();
                      if (!missionSnap.exists ||
                          missionSnap.data()?['status'] != 'done') {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                                "Vous pourrez laisser un avis une fois la mission terminée."),
                            backgroundColor: Colors.redAccent,
                          ),
                        );
                        return;
                      }
                      setModalState(() => selectedRating = i + 1.0);
                    },
                    icon: Icon(
                      i < selectedRating
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      color: Colors.amber,
                    ),
                  );
                }),
              ),

              const SizedBox(height: 20),

              TextField(
                controller: ctrl,
                decoration: InputDecoration(
                  hintText: 'Votre commentaire (optionnel)…',
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                maxLines: 3,
              ),

              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6C63FF),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: (isLoading || selectedRating == 0)
                      ? null
                      : () async {
                    setModalState(() => isLoading = true);

                    try {
                      final currentUser =
                          FirebaseAuth.instance.currentUser;
                      if (currentUser == null) return;

                      final already = await _hasUserAlreadyReviewed();
                      if (already) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                                "Vous avez déjà laissé un avis."),
                          ),
                        );
                        return;
                      }

                      final userDoc = await FirebaseFirestore.instance
                          .collection('users')
                          .doc(currentUser.uid)
                          .get();

                      final myName =
                          userDoc.data()?['name'] ?? 'Utilisateur';
                      final myPhoto =
                          userDoc.data()?['photoUrl'] ?? null;

                      // 🚀 Création de l'avis
                      final reviewRef = FirebaseFirestore.instance
                          .collection('reviews')
                          .doc();

                      await reviewRef.set({
                        'id': reviewRef.id,
                        'targetUserId': widget.userId,
                        'reviewerId': currentUser.uid,
                        'reviewerName': myName,
                        'reviewerPhoto': myPhoto,
                        'rating': selectedRating,
                        'comment': ctrl.text.trim(),
                        'createdAt': FieldValue.serverTimestamp(),
                        'missionId': widget.missionId,
                        'missionTitle': widget.missionTitle,
                      });

                      // Notif "nouvel avis"
                      await NotificationService.notifyNewReview(
                        clientUserId: widget.userId,
                        missionId: widget.missionId,
                        missionTitle: widget.missionTitle,
                        reviewerName: myName,
                        rating: selectedRating,
                        reviewText: ctrl.text.trim(),
                      );

                      // Vérifier si un autre avis existe déjà → 2 avis OK
                      final other = await FirebaseFirestore.instance
                          .collection('reviews')
                          .where('missionId',
                          isEqualTo: widget.missionId)
                          .where('reviewerId',
                          isNotEqualTo: currentUser.uid)
                          .limit(1)
                          .get();

                      if (other.docs.isNotEmpty) {
                        final missionSnap = await FirebaseFirestore
                            .instance
                            .collection('missions')
                            .doc(widget.missionId)
                            .get();

                        final clientId =
                        missionSnap.data()?['posterId'];
                        final providerId =
                        missionSnap.data()?['assignedTo'];

                        await NotificationService
                            .notifyMissionReviewsCompleted(
                          clientUserId: clientId,
                          providerUserId: providerId,
                          missionId: widget.missionId,
                          missionTitle: widget.missionTitle,
                        );
                      }

                      Navigator.pop(context);
                    } catch (e) {
                      debugPrint("Erreur avis: $e");
                    } finally {
                      setModalState(() => isLoading = false);
                    }
                  },
                  child: isLoading
                      ? const CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2)
                      : const Text(
                    'Publier',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}
