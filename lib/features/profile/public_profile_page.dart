import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'package:mamission/shared/apple_appbar.dart';

class PublicProfilePage extends StatelessWidget {
  final String userId;
  const PublicProfilePage({super.key, required this.userId});

  static const Color kPrimary = Color(0xFF6C63FF);
  static const Color kBackground = Color(0xFFF7F5FF);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: buildAppleMissionAppBar(
        title: "Profil du prestataire",
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),

      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('users').doc(userId).snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator(color: kPrimary));
          }

          final data = snap.data!.data();
          if (data == null) {
            return const Center(child: Text("Profil introuvable"));
          }

          final name = (data['name'] ?? 'Utilisateur').toString();
          final photoUrl = (data['photoUrl'] ?? '').toString();
          final city = data['city'] ?? 'France';
          final bio = (data['bio'] ?? '').toString();
          final rating = (data['rating'] ?? 0).toDouble();
          final reviews = (data['reviewsCount'] ?? 0) as int? ?? 0;
          final verified = data['verified'] == true;
          final skills = (data['skills'] as List?)?.cast<String>() ?? [];
          final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
          final joined = createdAt != null
              ? 'Membre depuis ${DateFormat.MMMM('fr_FR').format(createdAt)} ${createdAt.year}'
              : '';

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                // --- HEADER ---
                _buildHeader(context, name, photoUrl, city, joined, verified, rating, reviews),

                const SizedBox(height: 24),

                // --- BIO ---
                if (bio.isNotEmpty) _buildSection("À propos de moi", bio),
                if (skills.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _buildCompetencesEtExperiences(skills),
                ],
                const SizedBox(height: 20),

                // --- COMPÉTENCES ---
                if (skills.isNotEmpty) _buildSkills(skills),

                const SizedBox(height: 20),


                const SizedBox(height: 40),

                // --- CTA ---

              ],
            ),
          );
        },
      ),
    );
  }


  // =====================================================
  // ================= WIDGETS ============================
  // =====================================================

  Widget _buildHeader(BuildContext context, String name, String photoUrl, String city,
      String joined, bool verified, double rating, int reviews) {
    final parts = name.split(' ');
    final prenom = parts.isNotEmpty ? parts.first : 'Utilisateur';
    final nomInitiale =
    (parts.length > 1 && parts[1].isNotEmpty) ? '${parts[1][0].toUpperCase()}.' : '';
    final displayName = "$prenom $nomInitiale";

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Hero(
            tag: 'profile-photo-$userId',
            child: CircleAvatar(
              radius: 55,
              backgroundImage: photoUrl.isNotEmpty
                  ? NetworkImage(photoUrl)
                  : const NetworkImage('https://cdn-icons-png.flaticon.com/512/149/149071.png'),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(displayName,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87)),
              if (verified) ...[
                const SizedBox(width: 6),
                const Icon(Icons.verified, color: Colors.blueAccent, size: 20),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(city, style: const TextStyle(color: Colors.black54, fontSize: 14)),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () => context.pushNamed(
              'reviews',
              pathParameters: {'userId': userId},
              queryParameters: {
                'missionId': 'public',      // 👈 n’importe quoi, mais PAS vide
                'missionTitle': 'Profil',
              },
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.star_rounded, color: Colors.amber, size: 18),
                const SizedBox(width: 4),
                Text(
                  rating.toStringAsFixed(1),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '($reviews avis)',
                  style: const TextStyle(
                    color: Color(0xFF6C63FF), // Violet
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.underline, // ✅ souligné
                    decorationColor: Color(0xFF6C63FF),
                  ),
                ),
              ],
            ),
          ),

          if (joined.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(joined, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
          ]
        ],
      ),
    );
  }

  Widget _buildSection(String title, String content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            content,
            style: const TextStyle(fontSize: 14, height: 1.5, color: Colors.black87),
          ),
        ),
      ],
    );
  }

  Widget _buildSkills(List<String> skills) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Compétences",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: skills
                .map((s) => Chip(
              label: Text(s,
                  style: const TextStyle(
                      color: Color(0xFF6C63FF), fontWeight: FontWeight.w600)),
              backgroundColor: const Color(0xFFF4F1FF),
              side: const BorderSide(color: Color(0xFF6C63FF)),
            ))
                .toList(),
          ),
        ),
      ],
    );
  }


}
Widget _buildCompetencesEtExperiences(List<String> skills) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        "Compétences et expériences",
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.black87,
        ),
      ),
      const SizedBox(height: 8),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: skills
              .map(
                (s) => Chip(
              label: Text(
                s,
                style: const TextStyle(
                    color: Color(0xFF6C63FF), fontWeight: FontWeight.w600),
              ),
              backgroundColor: const Color(0xFFF4F1FF),
              side: const BorderSide(color: Color(0xFF6C63FF)),
            ),
          )
              .toList(),
        ),
      ),
    ],
  );
}
