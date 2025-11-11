import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
// Note : Pas d'import de 'constants.dart' ici. C'est 'question_tile.dart' qui s'en charge.
import 'package:mamission/features/missions/mission_detail/widgets/question_tile.dart';

class MissionQuestionsSection extends StatefulWidget {
  final String missionId;
  // ✅ IL MANQUAIT CES DEUX LIGNES DANS VOTRE FICHIER :
  final Stream<QuerySnapshot>? stream;
  final Function(String) onReply;

  const MissionQuestionsSection({
    super.key,
    required this.missionId,
    // ✅ IL MANQUAIT CES DEUX LIGNES DANS VOTRE FICHIER :
    required this.stream,
    required this.onReply,
  });

  @override
  State<MissionQuestionsSection> createState() => _MissionQuestionsSectionState();
}

class _MissionQuestionsSectionState extends State<MissionQuestionsSection> {
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: widget.stream, // ✅ Utilise le paramètre
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                "Soyez le premier à poser votre question ✍️",
                style: TextStyle(color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        final questions = snapshot.data!.docs;
        final visibleQuestions =
        _showAll ? questions : questions.take(2).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- Liste des questions ---
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: visibleQuestions.length,
              itemBuilder: (context, i) {
                final q = visibleQuestions[i];
                final data = q.data() as Map<String, dynamic>;
                final repliesCount = data['repliesCount'] ?? 0;

                return QuestionTile(
                  data: data,
                  missionId: widget.missionId,
                  questionId: q.id,
                  repliesCount: repliesCount,
                  onReply: () => widget.onReply(q.id), // ✅ Utilise le paramètre
                );
              },
            ),

            if (questions.length > 2)
              Center(
                child: TextButton(
                  onPressed: () => setState(() => _showAll = !_showAll),
                  child: Text(
                    _showAll ? "Voir moins" : "Voir plus de questions",
                    style: const TextStyle(
                      // ✅ Couleur hardcodée pour éviter le conflit d'import
                      color: Color(0xFF6C63FF),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}