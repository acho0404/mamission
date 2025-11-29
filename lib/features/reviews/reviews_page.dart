import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:mamission/core/constants.dart';
import 'package:mamission/shared/apple_appbar.dart';
import 'package:mamission/shared/services/notification_service.dart';

// Enum pour le tri
enum SortOption { newest, oldest, highest, lowest }

class ReviewsPage extends StatefulWidget {
  final String userId;
  final String missionId;
  final String missionTitle;

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
  final _formKey = GlobalKey<FormState>();
  final _commentController = TextEditingController();

  double _currentRating = 5;
  bool _isSubmitting = false;

  // 🔹 FILTRES & TRI
  // null = Tous, 5=5★, 4=4★+, 3=3★+, 2=2★ ou moins
  double? _minRatingFilter;
  SortOption _currentSort = SortOption.newest;

  // 🔹 PAGINATION : Je remets 5 pour que le bouton "Voir plus" s'active vite
  int _limit = 5;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<bool> _hasUserAlreadyReviewed() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;
    if (widget.missionId.isEmpty || widget.missionId == 'none') return false;

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

    if (widget.missionId.isEmpty || widget.missionId == 'none') {
      return _buildReviewsScaffold(isOwnProfile: isOwnProfile, canLeaveReview: false);
    }

    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance.collection('missions').doc(widget.missionId).get(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator(color: Color(0xFF6C63FF))));
        }

        bool canReview = false;
        if (snap.hasData && snap.data!.exists) {
          final status = (snap.data!.data()!['status'] ?? '').toString();
          final isDone = ['done', 'completed', 'closed', 'paid'].contains(status);
          canReview = !isOwnProfile && isDone;
        }

        return _buildReviewsScaffold(isOwnProfile: isOwnProfile, canLeaveReview: canReview);
      },
    );
  }

  Widget _buildReviewsScaffold({required bool isOwnProfile, required bool canLeaveReview}) {
    final reviewsQuery = FirebaseFirestore.instance
        .collection('reviews')
        .where('targetUserId', isEqualTo: widget.userId);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FE),
      appBar: buildAppleMissionAppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: "Avis & Notes",
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: reviewsQuery.snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFF6C63FF)));
          }

          final allDocs = snap.data?.docs ?? [];
          final allData = allDocs.map((d) => d.data() as Map<String, dynamic>).toList();

          // 1. Calculs Statistiques
          double avg = 0;
          Map<int, int> distribution = {5: 0, 4: 0, 3: 0, 2: 0, 1: 0};

          if (allData.isNotEmpty) {
            double totalScore = 0;
            for (var data in allData) {
              final r = ((data['rating'] ?? 0) as num).toDouble();
              totalScore += r;
              int star = r.round().clamp(1, 5);
              distribution[star] = (distribution[star] ?? 0) + 1;
            }
            avg = totalScore / allData.length;
          }

          // 2. Filtrage Logic
          List<Map<String, dynamic>> filteredList = allData;
          if (_minRatingFilter != null) {
            if (_minRatingFilter == 5) {
              filteredList = allData.where((d) => ((d['rating'] as num).toDouble()) >= 4.8).toList();
            } else if (_minRatingFilter == 2) {
              filteredList = allData.where((d) => ((d['rating'] as num).toDouble()) < 3.0).toList();
            } else {
              filteredList = allData.where((d) => ((d['rating'] as num).toDouble()) >= _minRatingFilter!).toList();
            }
          }

          // 3. Tri
          filteredList.sort((a, b) {
            final dateA = (a['createdAt'] as Timestamp?)?.toDate() ?? DateTime(2000);
            final dateB = (b['createdAt'] as Timestamp?)?.toDate() ?? DateTime(2000);
            final ratingA = (a['rating'] as num).toDouble();
            final ratingB = (b['rating'] as num).toDouble();

            switch (_currentSort) {
              case SortOption.newest: return dateB.compareTo(dateA);
              case SortOption.oldest: return dateA.compareTo(dateB);
              case SortOption.highest: return ratingB.compareTo(ratingA);
              case SortOption.lowest: return ratingA.compareTo(ratingB);
            }
          });

          final displayedList = filteredList.take(_limit).toList();

          return CustomScrollView(
            slivers: [
              // HEADER SOPHISTIQUÉ
              SliverToBoxAdapter(
                child: _ProHeader(
                  average: avg,
                  totalCount: allData.length,
                  distribution: distribution,
                ),
              ),

              // BARRE DE FILTRES
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _FilterChip(
                                label: "Tous",
                                isSelected: _minRatingFilter == null,
                                onTap: () => setState(() => _minRatingFilter = null),
                              ),
                              _FilterChip(
                                label: "5 ★",
                                isSelected: _minRatingFilter == 5,
                                onTap: () => setState(() => _minRatingFilter = 5),
                                icon: Icons.star,
                              ),
                              _FilterChip(
                                label: "4 ★ et +",
                                isSelected: _minRatingFilter == 4,
                                onTap: () => setState(() => _minRatingFilter = 4),
                                icon: Icons.star_half,
                              ),
                              _FilterChip(
                                label: "3 ★ et +",
                                isSelected: _minRatingFilter == 3,
                                onTap: () => setState(() => _minRatingFilter = 3),
                              ),
                              _FilterChip(
                                label: "2 ★ ou -",
                                isSelected: _minRatingFilter == 2,
                                onTap: () => setState(() => _minRatingFilter = 2),
                                icon: Icons.star_border,
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Bouton de Tri
                      PopupMenuButton<SortOption>(
                        icon: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade200),
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))],
                          ),
                          child: const Icon(Icons.sort_rounded, size: 20, color: Colors.black87),
                        ),
                        onSelected: (val) => setState(() => _currentSort = val),
                        itemBuilder: (context) => [
                          const PopupMenuItem(value: SortOption.newest, child: Text("Plus récents")),
                          const PopupMenuItem(value: SortOption.highest, child: Text("Note: Haute → Basse")),
                          const PopupMenuItem(value: SortOption.lowest, child: Text("Note: Basse → Haute")),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // LISTE
              if (displayedList.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.filter_list_off_rounded, size: 50, color: Colors.grey.shade300),
                        const SizedBox(height: 16),
                        Text(
                          "Aucun avis correspondant.",
                          style: TextStyle(color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                        (context, index) {
                      return _ReviewCard(data: displayedList[index]);
                    },
                    childCount: displayedList.length,
                  ),
                ),

              // BOUTON VOIR PLUS
              if (filteredList.length > displayedList.length)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: TextButton(
                        onPressed: () => setState(() => _limit += 5),
                        child: Text("Afficher plus d'avis (${filteredList.length - displayedList.length} restants)"),
                      ),
                    ),
                  ),
                ),

              const SliverPadding(padding: EdgeInsets.only(bottom: 80)),
            ],
          );
        },
      ),

      floatingActionButton: !canLeaveReview ? null : FutureBuilder<bool>(
        future: _hasUserAlreadyReviewed(),
        builder: (context, snap) {
          if (snap.data == true) return const SizedBox.shrink();
          return FloatingActionButton.extended(
            onPressed: () => _openReviewModal(context),
            label: const Text('Écrire un avis', style: TextStyle(fontWeight: FontWeight.w600)),
            icon: const Icon(Icons.create_rounded),
            backgroundColor: const Color(0xFF6C63FF),
            elevation: 4,
          );
        },
      ),
    );
  }

  // MODAL POUR AJOUTER AVIS
  void _openReviewModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        builder: (_, scrollController) {
          double selectedRating = _currentRating;
          return Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
            ),
            child: StatefulBuilder(
              builder: (context, setModalState) {
                return Form(
                  key: _formKey,
                  child: ListView(
                    controller: scrollController,
                    children: [
                      Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),
                      const SizedBox(height: 20),
                      const Text("Notez l'expérience", textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(5, (i) {
                          return GestureDetector(
                            onTap: () => setModalState(() => selectedRating = (i + 1).toDouble()),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: Icon(
                                i < selectedRating ? Icons.star_rounded : Icons.star_outline_rounded,
                                color: Colors.amber,
                                size: 42,
                              ),
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 30),
                      TextFormField(
                        controller: _commentController,
                        minLines: 3, // 🔹 Plus confortable
                        maxLines: 8,
                        decoration: InputDecoration(
                          hintText: "Racontez-nous...",
                          filled: true,
                          fillColor: const Color(0xFFF5F6FA),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                        ),
                        validator: (v) => v!.trim().isEmpty ? "Veuillez écrire un commentaire" : null,
                      ),
                      const SizedBox(height: 30),
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton(
                          onPressed: _isSubmitting ? null : () => _submitReview(selectedRating),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6C63FF),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          child: _isSubmitting
                              ? const CircularProgressIndicator(color: Colors.white)
                              : const Text("Envoyer", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(height: 30),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Future<void> _submitReview(double rating) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final reviewerName = userDoc.data()?['name'] ?? 'Utilisateur';
      final reviewerPhoto = userDoc.data()?['photoUrl'] ?? userDoc.data()?['avatar'];

      final reviewRef = FirebaseFirestore.instance.collection('reviews').doc();
      final comment = _commentController.text.trim();

      await reviewRef.set({
        'id': reviewRef.id,
        'targetUserId': widget.userId,
        'missionId': widget.missionId,
        'missionTitle': widget.missionTitle,
        'reviewerId': uid,
        'reviewerName': reviewerName,
        'reviewerPhoto': reviewerPhoto,
        'rating': rating,
        'comment': comment,
        'createdAt': FieldValue.serverTimestamp(),
      });

      await NotificationService.notifyNewReview(
        clientUserId: widget.userId,
        missionId: widget.missionId,
        missionTitle: widget.missionTitle,
        reviewerName: reviewerName,
        rating: rating,
        reviewText: comment,
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Avis publié !")));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Erreur...")));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}

// ===================================================================
//  WIDGETS PRO & SOPHISTIQUÉS
// ===================================================================

class _ProHeader extends StatelessWidget {
  final double average;
  final int totalCount;
  final Map<int, int> distribution;

  const _ProHeader({required this.average, required this.totalCount, required this.distribution});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      height: 160,
      decoration: BoxDecoration(
        // Dégradé plus sophistiqué
        gradient: const LinearGradient(
          colors: [
            Color(0xFF5B50F6), // Violet un peu plus profond
            Color(0xFF8B85FF),
          ],
          begin: Alignment.bottomLeft,
          end: Alignment.topRight,
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(color: const Color(0xFF6C63FF).withOpacity(0.4), blurRadius: 25, offset: const Offset(0, 10)),
        ],
      ),
      child: Stack(
        children: [
          // 1. Cercles décoratifs (effet visuel moderne)
          Positioned(
            top: -30,
            right: -30,
            child: Container(
              width: 120, height: 120,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            bottom: -20,
            left: 20,
            child: Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
            ),
          ),

          // 2. Contenu Réel
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Row(
              children: [
                // Note Globale
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(average.toStringAsFixed(1), style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w900, color: Colors.white, height: 1)),
                    const SizedBox(height: 6),
                    _StarDisplay(rating: average, size: 16, color: Colors.amber),
                    const SizedBox(height: 6),
                    Text("$totalCount Avis", style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500)),
                  ],
                ),
                const SizedBox(width: 30),
                // Barres de progression
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [5, 4, 3, 2, 1].map((star) {
                      final count = distribution[star] ?? 0;
                      final pct = totalCount == 0 ? 0.0 : count / totalCount;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2.5),
                        child: Row(
                          children: [
                            Text("$star", style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Stack(
                                children: [
                                  Container(height: 5, decoration: BoxDecoration(color: Colors.black.withOpacity(0.15), borderRadius: BorderRadius.circular(2.5))),
                                  FractionallySizedBox(
                                    widthFactor: pct,
                                    child: Container(height: 5, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(2.5))),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                )
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final IconData? icon;

  const _FilterChip({required this.label, required this.isSelected, required this.onTap, this.icon});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF6C63FF) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: isSelected ? const Color(0xFF6C63FF) : Colors.grey.shade300),
            boxShadow: isSelected
                ? [const BoxShadow(color: Color(0x446C63FF), blurRadius: 6, offset: Offset(0, 3))]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: isSelected ? Colors.white : Colors.amber),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  final Map<String, dynamic> data;

  const _ReviewCard({required this.data});

  // 🔹 Fonction réintroduite pour masquer le nom
  String _shortName(String full) {
    if (full.isEmpty) return "Utilisateur";
    final parts = full.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first;
    // Prend le prénom + la première lettre du nom
    final first = parts.first;
    final last = parts.last;
    final initial = last.isNotEmpty ? '${last[0].toUpperCase()}.' : '';
    return '$first $initial';
  }

  @override
  Widget build(BuildContext context) {
    final rating = (data['rating'] ?? 0) as num;
    final comment = data['comment'] ?? '';
    final date = (data['createdAt'] as Timestamp?)?.toDate();
    final rawName = (data['reviewerName'] ?? 'Anonyme').toString();

    // ✅ Utilisation de la fonction de masquage
    final displayName = _shortName(rawName);

    final photo = data['reviewerPhoto'];
    final reviewerId = data['reviewerId'];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Color(0x08000000), blurRadius: 10, offset: Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _AvatarFetcher(uid: reviewerId, url: photo, name: displayName),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(displayName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black87)),
                    if (date != null)
                      Text(
                        DateFormat('d MMMM yyyy', 'fr_FR').format(date),
                        style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.amber.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                child: Row(
                  children: [
                    const Icon(Icons.star_rounded, color: Colors.amber, size: 16),
                    const SizedBox(width: 4),
                    Text(rating.toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.amber, fontSize: 13)),
                  ],
                ),
              )
            ],
          ),
          if (comment.toString().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(comment, style: const TextStyle(color: Color(0xFF4B5563), height: 1.4, fontSize: 14)),
          ]
        ],
      ),
    );
  }
}

class _AvatarFetcher extends StatelessWidget {
  final String? uid;
  final String? url;
  final String name;

  const _AvatarFetcher({this.uid, this.url, required this.name});

  @override
  Widget build(BuildContext context) {
    if (url != null && url!.isNotEmpty) {
      return CircleAvatar(backgroundImage: NetworkImage(url!), radius: 20, backgroundColor: Colors.grey.shade200);
    }
    return FutureBuilder<DocumentSnapshot>(
      future: uid != null ? FirebaseFirestore.instance.collection('users').doc(uid).get() : null,
      builder: (context, snap) {
        String? finalUrl;
        if (snap.hasData && snap.data!.exists) {
          final d = snap.data!.data() as Map<String, dynamic>;
          finalUrl = d['photoUrl'] ?? d['avatarUrl'] ?? d['avatar'];
        }

        if (finalUrl != null) {
          return CircleAvatar(backgroundImage: NetworkImage(finalUrl), radius: 20);
        }
        return CircleAvatar(
          radius: 20,
          backgroundColor: const Color(0xFFE0E7FF),
          child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: const TextStyle(color: Color(0xFF6C63FF), fontWeight: FontWeight.bold)),
        );
      },
    );
  }
}

class _StarDisplay extends StatelessWidget {
  final double rating;
  final double size;
  final Color color;
  const _StarDisplay({required this.rating, this.size = 20, this.color = Colors.amber});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        IconData icon = Icons.star_outline_rounded;
        if (index < rating.floor()) icon = Icons.star_rounded;
        else if (index < rating) icon = Icons.star_half_rounded;
        return Icon(icon, color: color, size: size);
      }),
    );
  }
}