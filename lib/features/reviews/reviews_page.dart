import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart'; // 👈 manquait !
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ReviewsPage extends StatefulWidget {
  final String userId;
  const ReviewsPage({super.key, required this.userId});

  @override
  State<ReviewsPage> createState() => _ReviewsPageState();
}

class _ReviewsPageState extends State<ReviewsPage> {
  double avg = 0;
  int total = 0;

  @override
  Widget build(BuildContext context) {
    // 👇 Ces deux lignes doivent être AVANT le Scaffold
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final isOwnProfile = currentUid == widget.userId;

    return Scaffold(
      appBar: AppBar(title: const Text('Avis & Notes')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(widget.userId)
            .collection('reviews')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data!.docs;
          if (docs.isEmpty) {
            return const Center(child: Text('Aucun avis pour le moment.'));
          }

          // moyenne arrondie à 0.5
          final avg = docs.fold<double>(0, (a, b) {
            final r = b['rating'];
            return a + (r is int ? r.toDouble() : (r ?? 0.0));
          }) / docs.length;

          final avgRounded = (avg * 2).round() / 2;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildHeader(avgRounded, docs.length),
              const SizedBox(height: 16),
              ...docs.map((d) => _buildReviewCard(d.data() as Map<String, dynamic>)),
            ],
          );
        },
      ),

      // 👇 le bouton ne s'affiche pas sur son propre profil
      floatingActionButton: isOwnProfile
          ? null
          : FloatingActionButton.extended(
        onPressed: () => _openReviewModal(context),
        label: const Text('Laisser un avis'),
        icon: const Icon(Icons.edit_rounded),
      ),
    );
  }

  Widget _buildHeader(double avg, int total) {
    final violet = const Color(0xFF6C63FF);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      margin: const EdgeInsets.only(bottom: 16),
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
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            avg.toStringAsFixed(1),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 56,
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) {
              final val = avg - i;
              IconData icon = val >= 1
                  ? Icons.star_rounded
                  : val >= 0.5
                  ? Icons.star_half_rounded
                  : Icons.star_border_rounded;
              return Icon(icon, color: Colors.amber.shade400, size: 30);
            }),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(30),
            ),
            child: Text(
              '$total ${total > 1 ? "avis" : "avis"}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildReviewCard(Map<String, dynamic> data) {
    final note = (data['rating'] is int)
        ? (data['rating'] as int).toDouble()
        : (data['rating'] ?? 0.0);

    final comment = data['comment'] ?? '';
    final name = data['authorName'] ?? 'Utilisateur';
    final date = (data['createdAt'] as Timestamp?)?.toDate();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black12.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundImage: data['photoUrl'] != null
                    ? NetworkImage(data['photoUrl'])
                    : null,
                radius: 18,
                child: data['photoUrl'] == null
                    ? const Icon(Icons.person, size: 18)
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 15)),
              ),
              Row(
                children: List.generate(5, (i) {
                  double val = note - i;
                  IconData icon = val >= 1
                      ? Icons.star_rounded
                      : val >= 0.5
                      ? Icons.star_half_rounded
                      : Icons.star_border_rounded;
                  return Icon(icon, color: Colors.amber, size: 16);
                }),
              ),
            ],
          ),
          if (comment.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(comment),
          ],
          if (date != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(DateFormat('d MMM yyyy').format(date),
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ),
        ],
      ),
    );
  }

  void _openReviewModal(BuildContext context) {
    final rating = ValueNotifier<double>(3.0);
    final ctrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 20,
            right: 20,
            top: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Laisser un avis',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            ValueListenableBuilder<double>(
              valueListenable: rating,
              builder: (_, val, __) => Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(10, (i) {
                  final v = (i + 1) / 2;
                  final isSelected = v <= val;
                  return GestureDetector(
                    onTap: () => rating.value = v,
                    child: Icon(
                      v % 1 == 0
                          ? Icons.star_rounded
                          : Icons.star_half_rounded,
                      color: isSelected ? Colors.amber : Colors.grey[300],
                      size: 30,
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(
                hintText: 'Votre commentaire...',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () async {
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(widget.userId)
                    .collection('reviews')
                    .add({
                  'authorName': 'Anonyme',
                  'photoUrl': null,
                  'rating': rating.value,
                  'comment': ctrl.text,
                  'createdAt': FieldValue.serverTimestamp(),
                });
                Navigator.pop(context);
              },
              icon: const Icon(Icons.send_rounded),
              label: const Text('Publier'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(44),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
