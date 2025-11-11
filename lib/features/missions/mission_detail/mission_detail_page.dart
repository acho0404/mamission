import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';

// ✅ Imports de votre propre code (avec le nouveau chemin)
import 'package:mamission/shared/widgets/status_badge.dart';
import 'package:mamission/core/constants.dart';
import 'package:mamission/core/formatters.dart';
import 'package:mamission/features/missions/mission_detail/widgets/mission_questions_section.dart';
import 'package:mamission/features/missions/mission_detail/widgets/photo_grid_section.dart';
// =========================================================================
// CLASSE PRINCIPALE (MissionDetailPage)
// =========================================================================

class MissionDetailPage extends StatefulWidget {
  final String missionId;
  const MissionDetailPage({super.key, required this.missionId});

  @override
  State<MissionDetailPage> createState() => _MissionDetailPageState();
}

class _MissionDetailPageState extends State<MissionDetailPage> {
  // --- État (inchangé) ---
  Stream<QuerySnapshot>? _questionsStream;
  final ScrollController _scrollController = ScrollController();
  final _questionCtrl = TextEditingController();

  Map<String, dynamic>? mission;
  Map<String, dynamic>? poster;
  Map<String, dynamic>? assignedToUser;

  LatLng? _position;
  bool isOwner = false;
  bool _hasMadeOffer = false;

  @override
  void initState() {
    super.initState();
    _loadMission();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _questionCtrl.dispose();
    super.dispose();
  }

  // =========================================================================
  // LOGIQUE (load, offer, question, actions) - (inchangée)
  // =========================================================================

  Future<void> _loadMission() async {
    final doc = await FirebaseFirestore.instance
        .collection('missions')
        .doc(widget.missionId)
        .get();
    if (!doc.exists || !mounted) return;

    final m = doc.data()!;
    final user = FirebaseAuth.instance.currentUser;

    setState(() {
      mission = m;
      isOwner = (user != null && m['posterId'] == user.uid);
    });

    final pos = (m['position'] as Map<String, dynamic>?) ?? {};
    final lat = (pos['lat'] as num?)?.toDouble();
    final lng = (pos['lng'] as num?)?.toDouble();
    if (lat != null && lng != null) {
      setState(() => _position = LatLng(lat, lng));
    }

    final posterId = m['posterId'];
    if (posterId is String && posterId.isNotEmpty) {
      final userDoc =
      await FirebaseFirestore.instance.collection('users').doc(posterId).get();
      if (userDoc.exists && mounted) setState(() => poster = userDoc.data());
    }

    final status = (m['status'] ?? 'open').toString();
    final assignedToId = (m['assignedTo'] as String?) ?? '';

    if (status == 'in_progress' && assignedToId.isNotEmpty) {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(assignedToId)
          .get();
      if (userDoc.exists && mounted) {
        setState(() => assignedToUser = userDoc.data());
      }
    }

    if (!isOwner && user != null) {
      final existing = await FirebaseFirestore.instance
          .collection('missions')
          .doc(widget.missionId)
          .collection('offers')
          .where('userId', isEqualTo: user.uid)
          .limit(1)
          .get();
      if (mounted) {
        setState(() => _hasMadeOffer = existing.docs.isNotEmpty);
      }
    } else if (isOwner) {
      setState(() => _hasMadeOffer = true);
    }
    _questionsStream = FirebaseFirestore.instance
        .collection('missions')
        .doc(widget.missionId)
        .collection('questions')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  Future<void> _onOfferPressed() async {
    final priceCtrl = TextEditingController();
    final msgCtrl = TextEditingController();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Faire une offre',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: priceCtrl,
                  decoration: const InputDecoration(
                    hintText: "Votre prix (€)",
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.euro_symbol),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: msgCtrl,
                  decoration: const InputDecoration(
                    hintText: "Ajouter un message (optionnel)",
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  icon: const Icon(Icons.add_circle_outline),
                  label: const Text("Envoyer l'offre"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(45),
                  ),
                  onPressed: () async {
                    final user = FirebaseAuth.instance.currentUser;
                    if (user == null) return;
                    final userDoc = await FirebaseFirestore.instance
                        .collection('users')
                        .doc(user.uid)
                        .get();
                    final userData = userDoc.data() ?? {};
                    final priceText = priceCtrl.text.trim();
                    final message = msgCtrl.text.trim();
                    if (priceText.isEmpty) return;

                    final price = double.tryParse(priceText) ?? 0;

                    final offerRef = FirebaseFirestore.instance
                        .collection('missions')
                        .doc(widget.missionId)
                        .collection('offers')
                        .doc();

                    await offerRef.set({
                      'id': offerRef.id,
                      'userId': user.uid,
                      'userName': userData['name'] ?? 'Utilisateur',
                      'userPhoto': userData['photoUrl'] ?? '',
                      'price': price,
                      'message': message,
                      'createdAt': FieldValue.serverTimestamp(),
                      'status': 'pending',
                    });

                    await FirebaseFirestore.instance
                        .collection('missions')
                        .doc(widget.missionId)
                        .update({
                      'offersCount': FieldValue.increment(1),
                    });

                    if (context.mounted) {
                      Navigator.pop(context);
                      await _loadMission();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("✅ Offre envoyée avec succès !"),
                          backgroundColor: Color(0xFF6C63FF),
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _sendQuestion() async {
    final txt = _questionCtrl.text.trim();
    if (txt.isEmpty) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await FirebaseFirestore.instance
        .collection('missions')
        .doc(widget.missionId)
        .collection('questions')
        .add({
      'userId': user.uid,
      'userName': user.displayName ?? 'Utilisateur',
      'userPhoto': user.photoURL ?? '',
      'message': txt,
      'imageUrl': '',
      'createdAt': FieldValue.serverTimestamp(),
      'isEdited': false,
      'repliesCount': 0,
    });

    _questionCtrl.clear();
  }

  Future<void> _openReplySheet(String questionId) async {
    final ctrl = TextEditingController();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Répondre à la question",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                decoration: const InputDecoration(
                  hintText: "Écris ta réponse...",
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                icon: const Icon(Icons.send),
                label: const Text("Publier la réponse"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(45),
                ),
                onPressed: () async {
                  final txt = ctrl.text.trim();
                  if (txt.isEmpty) return;
                  final user = FirebaseAuth.instance.currentUser;
                  if (user == null) return;

                  await FirebaseFirestore.instance
                      .collection('missions')
                      .doc(widget.missionId)
                      .collection('questions')
                      .doc(questionId)
                      .collection('replies')
                      .add({
                    'userId': user.uid,
                    'userName': user.displayName ?? 'Utilisateur',
                    'userPhoto': user.photoURL ?? '',
                    'message': txt,
                    'createdAt': FieldValue.serverTimestamp(),
                  });

                  await FirebaseFirestore.instance
                      .collection('missions')
                      .doc(widget.missionId)
                      .collection('questions')
                      .doc(questionId)
                      .update({'repliesCount': FieldValue.increment(1)});

                  if (context.mounted) Navigator.pop(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleOpenChat() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || mission == null) return;

    // 🔹 Récupère les infos Firestore du user connecté
    final userDoc =
    await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    final myData = userDoc.data() ?? {};

    final chatCol = FirebaseFirestore.instance.collection('chats');
    final chatSnap = await chatCol
        .where('missionId', isEqualTo: widget.missionId)
        .where('participants', arrayContains: user.uid)
        .limit(1)
        .get();

    String chatId;
    if (chatSnap.docs.isNotEmpty) {
      chatId = chatSnap.docs.first.id;
    } else {
      final posterId = mission?['posterId'];
      final assignedToId = mission?['assignedTo'];
      final String? otherUserId = isOwner ? assignedToId : posterId;

      if (otherUserId == null || otherUserId.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text("Erreur: Impossible de trouver le destinataire.")),
          );
        }
        return;
      }

      final otherDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(otherUserId)
          .get();
      final otherData = otherDoc.data() ?? {};

      // 🔹 Création du chat avec vrais noms + photos Firestore
      final newChat = await chatCol.add({
        'missionId': widget.missionId,
        'participants': [user.uid, otherUserId],
        'participantsInfo': {
          user.uid: {
            'name': myData['name'] ?? 'Moi',
            'photoUrl': myData['photoUrl'] ?? '',
          },
          otherUserId: {
            'name': otherData['name'] ?? 'Utilisateur',
            'photoUrl': otherData['photoUrl'] ?? '',
          },
        },
        'lastMessage': '',
        'lastSenderId': '',
        'status': 'active',
        'typing': {
          user.uid: false,
          otherUserId: false,
        },
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      chatId = newChat.id;
    }

    // 🔹 Utilise push() (et non go()) pour éviter l’écran noir au retour
    if (mounted) context.push('/chat/$chatId');
  }

  // =========================================================================
  // LOGIQUE D'ANNULATION (inchangée)
  // =========================================================================

  Future<void> _handleCancelMission() async {
    Future<void> _performCancelLogic() async {
      try {
        await FirebaseFirestore.instance
            .collection('missions')
            .doc(widget.missionId)
            .update({
          'status': 'cancelled',
          'assignedTo': null,
          'cancelledAt': FieldValue.serverTimestamp(),
        });

        // tu pourras plus tard ajouter une notif ici
        // await NotificationService.sendMissionCancelledNotification(...);
      } catch (e) {
        print("Erreur annulation: $e");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Erreur: impossible d’annuler la mission."),
            backgroundColor: Colors.redAccent,
          ));
        }
      }
    }

    if (mission == null) return;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: false,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 50,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                "Annuler la mission ?",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: kPrimary,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                "Cette action est irréversible. Voulez-vous vraiment annuler cette mission ?",
                textAlign: TextAlign.center,
                style: TextStyle(color: kGreyText, height: 1.5),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: kPrimary, width: 1.4),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text("Non, revenir",
                          style: TextStyle(
                              color: kPrimary, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        Navigator.pop(context, true);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text("Oui, annuler",
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );

    if (confirmed == true) {
      await _performCancelLogic();
      if (mounted) {
        setState(() => mission?['status'] = 'cancelled');
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("🚫 Mission annulée avec succès."),
          backgroundColor: Colors.redAccent,
        ));
      }
    }
  }

  Future<void> _confirmEditMission() async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: false,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 50,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                "Modifier la mission ?",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: kPrimary,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                "Modifier cette mission effacera toutes les offres reçues.\nSouhaitez-vous continuer ?",
                textAlign: TextAlign.center,
                style: TextStyle(color: kGreyText, height: 1.5),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: kPrimary, width: 1.4),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text(
                        "Non, revenir",
                        style: TextStyle(
                          color: kPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kPrimary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text(
                        "Oui, modifier",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );

    if (confirmed == true && mounted) {
      // ✅ Correction : on construit correctement l'URI avec le paramètre
      final uri = Uri(
        path: '/missions/create',
        queryParameters: {'edit': widget.missionId},
      ).toString();

      print("🟣 [DEBUG] Navigation vers $uri"); // ← devrait apparaître maintenant

      await context.push(uri);
      await _loadMission(); // recharge la mission après retour
    }
  }

  Future<void> _handleReopenMission() async {
    if (mission == null) return;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: false,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 50,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                "Rouvrir la mission ?",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: kPrimary,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                "Voulez-vous rouvrir cette mission pour recevoir de nouvelles offres ?",
                textAlign: TextAlign.center,
                style: TextStyle(color: kGreyText, height: 1.5),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: kPrimary, width: 1.4),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text("Non, annuler",
                          style: TextStyle(
                              color: kPrimary, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        Navigator.pop(context, true);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kPrimary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text("Oui, rouvrir",
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );

    if (confirmed == true) {
      final missionRef = FirebaseFirestore.instance
          .collection('missions')
          .doc(widget.missionId);

      // 🔹 1. Réinitialise le statut et supprime les anciens champs
      await missionRef.update({
        'status': 'open',
        'assignedTo': null,
        'offersCount': 0,
        'cancelledAt': FieldValue.delete(),
        'cancelledBy': FieldValue.delete(),
        'reopenedAt': FieldValue.serverTimestamp(),
      });

      // 🔹 2. Supprime les anciennes offres
      final offersRef = missionRef.collection('offers');
      final oldOffers = await offersRef.get();
      for (var doc in oldOffers.docs) {
        await doc.reference.delete();
      }

      // 🔹 3. (Optionnel) Supprime les anciennes questions
      final questionsRef = missionRef.collection('questions');
      final oldQuestions = await questionsRef.get();
      for (var doc in oldQuestions.docs) {
        await doc.reference.delete();
      }

      // 🔹 4. Rafraîchit l’UI
      if (mounted) {
        setState(() => mission?['status'] = 'open');
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("✅ Mission rouverte avec succès."),
          backgroundColor: kPrimary,
        ));
      }
    }
  }

  Future<void> _handleLeaveReview() async {
    print("Action: Laisser un avis");
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Logique d'avis à implémenter.")),
    );
  }

  Future<void> _handleMarkAsDone() async {
    print("Action: Marquer comme terminée");
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text("Logique 'Marquer comme terminée' à implémenter.")),
    );
  }

  // =========================================================================
  // =========================================================================
  //
  //    MÉTHODE BUILD (Contient les helpers UI)
  //
  // =========================================================================
  // =========================================================================

  @override
  Widget build(BuildContext context) {
    if (mission == null) {
      return Scaffold(
        backgroundColor: kBackground,
        appBar: AppBar(backgroundColor: kPrimary),
        body: const Center(child: CircularProgressIndicator(color: kPrimary)),
      );
    }

    // --- Extraction des données ---
    final title = (mission?['title'] ?? '').toString();
    final desc = (mission?['description'] ?? '').toString();
    final budget = (mission?['budget'] ?? 0).toDouble();

    final String mainPhoto = (mission?['photoUrl'] ?? '').toString();
    final List<String> additionalPhotos =
        (mission?['additionalPhotos'] as List?)
            ?.map((item) => item.toString())
            .toList() ??
            [];
    final List<String> allPhotos =
    [mainPhoto, ...additionalPhotos].where((url) => url.isNotEmpty).toList();

    final deadlineRaw = mission?['deadline'];
    final deadline = (deadlineRaw is Timestamp)
        ? DateFormat('d MMM yyyy', 'fr_FR').format(deadlineRaw.toDate())
        : 'Non spécifiée';
    final mode = (mission?['mode'] ?? 'Sur place').toString();
    final location = (mission?['location'] ?? 'Lieu non précisé').toString();
    final flexibility = (mission?['flexibility'] ?? 'Flexible').toString();
    final status = (mission?['status'] ?? 'open').toString();

    return Scaffold(
      backgroundColor: kBackground,
      // --- 1. AppBar ---
      appBar: AppBar(
        backgroundColor: kPrimary,
        elevation: 3,
        foregroundColor: Colors.white,
        title: const Text("Détails de la mission"),
      ),

      // --- 2. Le Body ---
      body: SingleChildScrollView(
        controller: _scrollController,
        child: Column(
          children: [
            // --- 3. La "Feuille de Contenu" unique ---
            Container(
              color: kCard, // Fond blanc
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // =========================================================
                  // ✅ SECTION MODIFIÉE (Premium Layout v4: Typo Pure)
                  // =========================================================

                  // --- Titre & Budget (Typo "Premium") ---
                  Padding(
                    padding:
                    const EdgeInsets.fromLTRB(20, 24, 20, 20), // Padding
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontSize: 28, // ✅ Très grand
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF2F2E41),
                              height: 1.3, // Espace de ligne
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        // ✅ Plus de Container, juste du texte.
                        Text(
                          "${budget.toStringAsFixed(0)} €",
                          style: const TextStyle(
                            color: kPrimary,
                            fontWeight: FontWeight.w800, // Plus gras
                            fontSize: 26, // ✅ Très grand
                          ),
                        ),
                      ],
                    ),
                  ),

                  // --- Séparateur Visuel ---
                  const Padding(
                    padding:
                    EdgeInsets.fromLTRB(20, 0, 20, 16), // Padding ajusté
                    child: Divider(thickness: 0.5), // ✅ Séparateur
                  ),

                  // --- Chips d'info & Stepper de Statut ---
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Colonne gauche (infos)
                        Expanded(
                          flex: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _chip(Icons.location_on, mode),
                              const SizedBox(height: 6),
                              _chip(Icons.calendar_month, 'Avant le $deadline'),
                              const SizedBox(height: 6),
                              _chip(Icons.timer, flexibility),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Colonne droite (statuts)
                        Expanded(
                          flex: 1,
                          child: (status == 'cancelled' || status == 'draft')
                              ? Align(
                            alignment: Alignment.centerRight,
                            child: StatusBadge(
                                type: 'mission', status: status),
                          )
                              : Builder(builder: (context) {
                            final statusMap = {
                              'open': 1,
                              'in_progress': 2,
                              'done': 3,
                              'cancelled': 0,
                            };

                            final currentLevel = statusMap[status] ?? 0;

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Opacity(
                                  opacity: 1.0,
                                  child: StatusBadge(
                                      type: 'mission', status: 'open'),
                                ),
                                const SizedBox(height: 6),
                                Opacity(
                                  opacity:
                                  (currentLevel >= 2) ? 1.0 : 0.4,
                                  child: StatusBadge(
                                      type: 'mission',
                                      status: 'in_progress'),
                                ),
                                const SizedBox(height: 6),
                                Opacity(
                                  opacity:
                                  (currentLevel >= 3) ? 1.0 : 0.4,
                                  child: StatusBadge(
                                      type: 'mission', status: 'done'),
                                ),
                              ],
                            );
                          }),
                        ),
                      ],
                    ),
                  ),

                  // =========================================================
                  // FIN DE LA SECTION MODIFIÉE
                  // =========================================================

                  // --- Badge de Statut (sauf si 'open') ---
                  if (status != 'open')
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                      child: _buildNonOpenStatusBadge(status),
                    ),

                  // --- Boutons d'action ---
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 20),
                    child: _buildActionButtons(context, status),
                  ),

                  // --- Section Description ---
                  _buildSection(
                    context,
                    title: "Description",
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          desc.isNotEmpty
                              ? desc
                              : "Aucune description fournie.",
                          style: const TextStyle(
                              fontSize: 15, height: 1.5, color: kGreyText),
                        ),
                        // ✅ Widget Extrait
                        PhotoGridSection(
                          photoUrls: allPhotos,
                          onPhotoTap: (url) =>
                              _openPhotoViewer(context, url, allPhotos),
                        ),
                      ],
                    ),
                  ),

                  // --- Section Questions Publiques ---
                  _buildSection(
                    context,
                    title: "Questions publiques",
                    child: Column(
                      children: [
                        // ✅ Widget Extrait
                        MissionQuestionsSection(
                          missionId: widget.missionId,
                          stream: _questionsStream,
                          onReply: (questionId) => _openReplySheet(questionId),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _questionCtrl,
                                decoration: InputDecoration(
                                  hintText: "Poser une question...",
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 10),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide:
                                    const BorderSide(color: kPrimary),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(
                                        color: kPrimary, width: 2),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.send, color: kPrimary),
                              onPressed: _sendQuestion,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // --- Section Posté par ---
                  _buildSection(
                    context,
                    title: "Posté par",
                    child: (poster == null)
                        ? const Center(child: CircularProgressIndicator())
                        : ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        radius: 26,
                        backgroundImage:
                        (poster?['photoUrl']?.isNotEmpty ?? false)
                            ? NetworkImage(poster!['photoUrl'])
                            : const NetworkImage(
                            'https://cdn-icons-png.flaticon.com/512/149/149071.png'),
                      ),
                      title: Text(
                          formatUserName(poster?['name'] ?? 'Utilisateur')),
                      subtitle: Row(
                        children: [
                          const Icon(Icons.star,
                              color: Colors.amber, size: 16),
                          const SizedBox(width: 4),
                          Text(
                            "${poster?['rating']?.toStringAsFixed(1) ?? '...'} "
                                "(${poster?['reviewsCount'] ?? 0} avis)",
                            style: const TextStyle(
                                fontSize: 13, color: kGreyText),
                          ),
                        ],
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.chevron_right),
                        onPressed: () {
                          if (poster?['id'] != null) {
                            context.push('/profile/${poster!['id']}');
                          }
                        },
                      ),
                    ),
                  ),

                  // --- Section Localisation ---
                  _buildSection(
                    context,
                    title: "Localisation",
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.place_outlined, color: kGreyText),
                            const SizedBox(width: 6),
                            Expanded(
                                child: Text(location,
                                    style: const TextStyle(color: kGreyText))),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (_position != null)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: SizedBox(
                              height: 160,
                              child: GoogleMap(
                                initialCameraPosition:
                                CameraPosition(target: _position!, zoom: 13.5),
                                markers: {
                                  Marker(
                                    markerId: const MarkerId("mission"),
                                    position: _position!,
                                  )
                                },
                                zoomControlsEnabled: false,
                                liteModeEnabled: true,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  // Espace en bas pour le défilement
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // HELPERS UI (Restent ici car dépendent de l'état local)
  // =========================================================================

  Widget _buildActionButtons(BuildContext context, String status) {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return const SizedBox.shrink();

    final String assignedTo = (mission?['assignedTo'] ?? '').toString();
    final bool isAssignedToMe = (assignedTo == currentUser.uid);

    // --- 🧩 1. VUE CLIENT ---
    if (isOwner) {
      switch (status) {
        case 'open':
          return Column(
            children: [
              // --- Bouton "Voir les offres reçues"
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('missions')
                    .doc(widget.missionId)
                    .collection('offers')
                    .snapshots(),
                builder: (context, snap) {
                  final count = snap.data?.docs.length ?? 0;
                  return _buildSecondaryButton(
                    context,
                    onPressed: () =>
                        context.push('/missions/${widget.missionId}/offers'),
                    icon: Icons.people_outline,
                    label: "Voir les offres reçues ($count)",
                  );
                },
              ),
              const SizedBox(height: 12),

              // --- Bouton "Modifier la mission"
              _buildPrimaryButton(
                context,
                onPressed: _confirmEditMission,
                icon: Icons.edit_outlined,
                label: "Modifier la mission",
              ),
              const SizedBox(height: 12),

              // --- Bouton "Annuler la mission"
              _buildDangerButton(
                context,
                onPressed: _handleCancelMission,
                icon: Icons.cancel_outlined,
                label: "Annuler la mission",
              ),
            ],
          );

        case 'in_progress':
          return Column(
            children: [
              _buildPrimaryButton(
                context,
                onPressed: _handleOpenChat,
                icon: Icons.chat_bubble_outline,
                label: "Ouvrir la discussion",
              ),
              const SizedBox(height: 12),
              _buildDangerButton(
                context,
                onPressed: _handleCancelMission,
                icon: Icons.cancel_outlined,
                label: "Annuler la mission",
              ),
            ],
          );
        case 'done':
          return _buildPrimaryButton(
            context,
            onPressed: _handleLeaveReview,
            icon: Icons.star_outline,
            label: "Laisser un avis au prestataire",
          );
        case 'cancelled':
          return _buildPrimaryButton(
            context,
            onPressed: _handleReopenMission,
            icon: Icons.refresh_outlined,
            label: "Rouvrir la mission",
          );
        default:
          return const SizedBox.shrink();
      }
    }
    // --- 🧩 2. VUE PRESTATAIRE ---
    else {
      switch (status) {
        case 'open':
          if (_hasMadeOffer) {
            return _buildInfoBox(
              context,
              icon: Icons.check_circle,
              label: "Offre déjà envoyée",
              color: kPrimary,
            );
          } else {
            return _buildPrimaryButton(
              context,
              onPressed: _onOfferPressed,
              icon: Icons.add_circle_outline,
              label: "Faire une offre maintenant",
            );
          }
        case 'in_progress':
          if (isAssignedToMe) {
            return Column(
              children: [
                _buildPrimaryButton(
                  context,
                  onPressed: _handleOpenChat,
                  icon: Icons.chat_bubble_outline,
                  label: "Ouvrir la discussion",
                ),
                const SizedBox(height: 12),
                _buildSuccessButton(
                  context,
                  onPressed: _handleMarkAsDone,
                  icon: Icons.check_circle_outline,
                  label: "Marquer comme terminée",
                ),
              ],
            );
          } else {
            return const SizedBox.shrink();
          }
        case 'done':
          return _buildSecondaryButton(
            context,
            onPressed: _handleLeaveReview,
            icon: Icons.rate_review_outlined,
            label: "Voir l'avis du client",
          );
        case 'cancelled':
        default:
          return const SizedBox.shrink();
      }
    }
  }

  // --- Helpers de style pour les boutons ---

  Widget _buildPrimaryButton(BuildContext context,
      {required VoidCallback onPressed,
        required IconData icon,
        required String label}) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: kPrimary,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(55),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }

  Widget _buildSecondaryButton(BuildContext context,
      {required VoidCallback onPressed,
        required IconData icon,
        required String label}) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
        minimumSize: const Size.fromHeight(50),
        side: const BorderSide(color: kPrimary, width: 1.3),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        foregroundColor: kPrimary,
      ),
    );
  }

  Widget _buildSuccessButton(BuildContext context,
      {required VoidCallback onPressed,
        required IconData icon,
        required String label}) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
        minimumSize: const Size.fromHeight(50),
        side: const BorderSide(color: Colors.green, width: 1.3),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        foregroundColor: Colors.green,
      ),
    );
  }

  Widget _buildDangerButton(BuildContext context,
      {required VoidCallback onPressed,
        required IconData icon,
        required String label}) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
        minimumSize: const Size.fromHeight(50),
        side: BorderSide(color: Colors.red[700]!, width: 1.3),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        foregroundColor: Colors.red[700],
      ),
    );
  }

  Widget _buildInfoBox(BuildContext context,
      {required IconData icon, required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // --- Helpers de statut ---

  Widget _buildStatusBadge({
    required String text,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInProgressBadge(BuildContext context) {
    if (assignedToUser == null) {
      // Fallback
      return _buildStatusBadge(
        text: "Mission en cours...",
        color: Colors.orange[700]!,
        icon: Icons.hourglass_bottom_outlined,
      );
    }

    // Données du prestataire
    final name = assignedToUser?['name'] ?? 'Prestataire';
    final formattedName = formatUserName(name);
    final rating = (assignedToUser?['rating'] ?? 0).toDouble();
    final reviewsCount = assignedToUser?['reviewsCount'] ?? 0;
    final userId = assignedToUser?['id'] ?? assignedToUser?['uid'] ?? '';

    return GestureDetector(
      onTap: () {
        if (userId.isNotEmpty) {
          context.push('/profile/$userId');
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFE4F8E9),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.green[200]!),
        ),
        // ✅ C'est ce Column qui crée les deux lignes
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // --- Ligne 1: "En cours avec un prestataire" ---
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.handshake_outlined, // ou Icons.assignment_turned_in_outlined
                    color: Colors.green[800]!,
                    size: 16), // Taille 16
                const SizedBox(width: 6),
                Text(
                  "En cours avec un prestataire",
                  style: TextStyle(
                    color: Colors.green[800]!,
                    fontWeight: FontWeight.w600,
                    fontSize: 14, // Taille 14
                  ),
                ),
              ],
            ),

            const SizedBox(height: 6), // Espace entre les deux lignes

            // --- Ligne 2: "Moulay C. ⭐ 5.0 (1 avis)" ---
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  formattedName,
                  style: const TextStyle(
                    color: kGreyText,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.star, color: Colors.amber, size: 14),
                const SizedBox(width: 2),
                Text(
                  "${rating.toStringAsFixed(1)} ($reviewsCount avis)",
                  style: const TextStyle(fontSize: 13, color: kGreyText),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNonOpenStatusBadge(String status) {
    switch (status) {
      case 'in_progress':
        return _buildInProgressBadge(context);

      case 'completed':
      case 'done':
        return _buildStatusBadge(
          text: "Mission terminée",
          color: kPrimary,
          icon: Icons.check_circle_outline,
        );

      case 'cancelled':
        return _buildStatusBadge(
          text: "Mission annulée",
          color: Colors.red[700]!,
          icon: Icons.cancel_outlined,
        );

      default:
        return _buildStatusBadge(
          text: "Statut: ${status.capitalize()}",
          color: Colors.grey,
          icon: Icons.info_outline,
        );
    }
  }

  void _openPhotoViewer(
      BuildContext context, String initialUrl, List<String> allPhotos) {
    showGeneralDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.9),
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (dialogContext, __, ___) {
        return Stack(
          fit: StackFit.expand,
          children: [
            InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child:
              Center(child: Image.network(initialUrl, fit: BoxFit.contain)),
            ),
            Positioned(
              top: 60.0,
              left: 16.0,
              child: Material(
                type: MaterialType.transparency,
                child: IconButton(
                  icon:
                  const Icon(Icons.close, color: Colors.white, size: 30.0),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black.withOpacity(0.4),
                    padding: const EdgeInsets.all(8),
                  ),
                  onPressed: () => Navigator.pop(dialogContext),
                ),
              ),
            ),
          ],
        );
      },
      transitionBuilder: (_, anim, __, child) =>
          FadeTransition(opacity: anim, child: child),
    );
  }

  Widget _chip(IconData icon, String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: kBackground,
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: Colors.grey.shade200),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: kGreyText), // <- couleur kGreyText
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            label,
            style: const TextStyle(
              color: kGreyText, // <- couleur kGreyText
              fontWeight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );

  Widget _buildSection(BuildContext context,
      {required String title, required Widget child}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 40, thickness: 0.5),
          Text(
            title,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w700, fontSize: 18),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}