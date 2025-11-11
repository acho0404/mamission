import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mamission/core/constants.dart'; // Import
import 'package:mamission/core/formatters.dart'; // Import
import 'package:mamission/features/missions/mission_detail/widgets/reply_tile.dart';

// Renommé de _QuestionTile à QuestionTile
class QuestionTile extends StatefulWidget {
  final Map<String, dynamic> data;
  final String missionId;
  final String questionId;
  final int repliesCount;
  final VoidCallback onReply;

  const QuestionTile({
    super.key, // Clé ajoutée
    required this.data,
    required this.missionId,
    required this.questionId,
    required this.repliesCount,
    required this.onReply,
  });

  @override
  State<QuestionTile> createState() => _QuestionTileState();
}

class _QuestionTileState extends State<QuestionTile> {
  bool showReplies = false;
  Map<String, dynamic>? user;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  // Récupère les infos (note, etc.) de l'utilisateur qui a posé la question
  Future<void> _loadUserData() async {
    final uid = widget.data['userId'];
    if (uid == null || uid.isEmpty) return;
    final snap =
    await FirebaseFirestore.instance.collection('users').doc(uid).get();
    if (snap.exists && mounted) {
      setState(() => user = snap.data());
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final message = data['message'] ?? '';
    final timestamp = data['createdAt'] as Timestamp?;
    final date = formatTimeAgo(timestamp);
    final userId = data['userId'] ?? '';

    final name = user?['name'] ?? data['userName'] ?? 'Utilisateur';
    final formattedName = formatUserName(name);
    final photo = user?['photoUrl'] ??
        data['userPhoto'] ??
        'https://cdn-icons-png.flaticon.com/512/149/149071.png';
    final rating = (user?['rating'] ?? 0).toDouble();
    final reviewsCount = user?['reviewsCount'] ?? 0;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- Header (avatar + nom + date)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: () {
                  if (userId.isNotEmpty) context.push('/profile/$userId');
                },
                child: CircleAvatar(
                  radius: 18,
                  backgroundImage: NetworkImage(photo),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: () {
                        if (userId.isNotEmpty) context.push('/profile/$userId');
                      },
                      child: Text(
                        formattedName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14.5,
                        ),
                      ),
                    ),
                    if (rating > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 2.0),
                        child: Row(
                          children: [
                            const Icon(Icons.star,
                                size: 13, color: Colors.amber),
                            const SizedBox(width: 2),
                            Text(
                              '${rating.toStringAsFixed(1)}',
                              style: const TextStyle(
                                  color: Colors.black87, fontSize: 12),
                            ),
                            Text(
                              ' ($reviewsCount avis)',
                              style: const TextStyle(
                                  color: Colors.grey, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              Text(
                date, // Affiche le temps écoulé
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // --- Message principal (Bulle de lecture) ---
          Padding(
            padding: const EdgeInsets.only(left: 48), // Aligné avec le nom
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F6FF), // kBackground
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                message,
                style: const TextStyle(
                    fontSize: 14.5, height: 1.4, color: Colors.black87),
              ),
            ),
          ),
          const SizedBox(height: 6),
          // --- Bouton Répondre / Voir réponses
          Padding(
            padding: const EdgeInsets.only(left: 38), // Alignement visuel
            child: Row(
              children: [
                TextButton(
                  onPressed: () => widget.onReply(), // Ouvre le bottom sheet
                  style: TextButton.styleFrom(
                      foregroundColor: kPrimary,
                      padding: const EdgeInsets.symmetric(horizontal: 8)),
                  child: const Text("Répondre"),
                ),
                const SizedBox(width: 10),
                if (widget.repliesCount > 0)
                  GestureDetector(
                    onTap: () => setState(() => showReplies = !showReplies),
                    child: Text(
                      showReplies
                          ? 'Masquer les réponses'
                          : '${widget.repliesCount} réponse${widget.repliesCount > 1 ? 's' : ''}',
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 13,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // --- Liste des réponses (visible seulement quand showReplies = true)
          if (showReplies)
            _RepliesList( // Utilise le nouveau widget privé
              missionId: widget.missionId,
              questionId: widget.questionId,
            ),
        ],
      ),
    );
  }
}

// Nouveau widget privé pour afficher la liste des réponses
// (Anciennement _buildReplies)
class _RepliesList extends StatelessWidget {
  final String missionId;
  final String questionId;

  const _RepliesList({
    required this.missionId,
    required this.questionId,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 48, top: 12), // Indenté
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('missions')
            .doc(missionId)
            .collection('questions')
            .doc(questionId)
            .collection('replies')
            .orderBy('createdAt',
            descending: false) // Trié du plus ancien au plus récent
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const SizedBox(height: 10);
          final replies = snapshot.data!.docs;
          if (replies.isEmpty) {
            return const Padding(
              padding: EdgeInsets.only(left: 12, top: 4),
              child: Text(
                "Aucune réponse pour l’instant",
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
            );
          }
          // Utilise ListView.builder pour créer un ReplyTile pour chaque réponse
          return ListView.builder(
            itemCount: replies.length,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemBuilder: (context, index) {
              final data = replies[index].data() as Map<String, dynamic>;
              return ReplyTile(data: data); // Utilise le widget public
            },
          );
        },
      ),
    );
  }
}