import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mamission/shared/apple_appbar.dart';

// ✅ Imports de ton app
import 'package:mamission/shared/widgets/status_badge.dart';
import 'package:mamission/core/constants.dart';
import 'package:mamission/core/formatters.dart';
import 'package:mamission/features/missions/mission_detail/widgets/mission_questions_section.dart';
import 'package:mamission/features/missions/mission_detail/widgets/photo_grid_section.dart';

// ✅ Import du service de notif
import 'package:mamission/shared/services/notification_service.dart';

// ---------------------------------------------------------------------------
// Dégradé de fond néon pour la page
// ---------------------------------------------------------------------------
const LinearGradient _detailBackgroundGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [
    Color(0xFFEEF0FF),
    Color(0xFFE7F5FF),
    Color(0xFFF9FBFF),
  ],
);

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
  // --- État ---
  Stream<QuerySnapshot>? _questionsStream;
  final ScrollController _scrollController = ScrollController();
  final _questionCtrl = TextEditingController();

  Map<String, dynamic>? mission;
  Map<String, dynamic>? poster;
  Map<String, dynamic>? assignedToUser;

  LatLng? _position;
  bool isOwner = false;

  bool _hasMadeOffer = false;
  String? _myOfferId;
  Map<String, dynamic>? _myOfferData;

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
  // LOGIQUE (load, offer, question, actions)
  // =========================================================================
  Future<bool> _hasUserAlreadyReviewed() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return false;

    final query = await FirebaseFirestore.instance
        .collection('reviews')
        .where('missionId', isEqualTo: widget.missionId)
        .where('reviewerId', isEqualTo: currentUser.uid)
        .limit(1)
        .get();

    return query.docs.isNotEmpty;
  }

  // Pastille noire "X offres"
  Widget _offerCountChip(int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.9),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.local_offer, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            "$count offre${count > 1 ? 's' : ''}",
            style: const TextStyle(
              fontSize: 12.5,
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

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
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(posterId)
          .get();
      if (userDoc.exists && mounted) setState(() => poster = userDoc.data());
    }

    // NOUVEAU
    final status = (m['status'] ?? 'open').toString();
    final assignedToId = (m['assignedTo'] as String?) ?? '';

    // 🔹 On garde le prestataire visible en "en cours", "terminée" ET "clôturée"
    if ((status == 'in_progress' || status == 'done' || status == 'closed') &&
        assignedToId.isNotEmpty) {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(assignedToId)
          .get();
      if (userDoc.exists && mounted) {
        setState(() => assignedToUser = userDoc.data());
      }
    }

    // --- Récupère l'offre du worker connecté (pour modifier / retirer) ---
    final currentUser = FirebaseAuth.instance.currentUser;
    if (!isOwner && currentUser != null) {
      final existing = await FirebaseFirestore.instance
          .collection('missions')
          .doc(widget.missionId)
          .collection('offers')
          .where('userId', isEqualTo: currentUser.uid)
          .get();

      if (mounted) {
        Map<String, dynamic>? activeOfferData;
        String? activeOfferId;

        for (final docOffer in existing.docs) {
          final data = docOffer.data() as Map<String, dynamic>;
          final st = (data['status'] ?? 'pending').toString();
          if (st != 'cancelled' && st != 'closed') {
            activeOfferId = docOffer.id;
            activeOfferData = data;
            break;
          }
        }

        if (activeOfferId != null && activeOfferData != null) {
          setState(() {
            _hasMadeOffer = true;
            _myOfferId = activeOfferId;
            _myOfferData = activeOfferData;
          });
        } else {
          setState(() {
            _hasMadeOffer = false;
            _myOfferId = null;
            _myOfferData = null;
          });
        }
      }
    }

    _questionsStream = FirebaseFirestore.instance
        .collection('missions')
        .doc(widget.missionId)
        .collection('questions')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  // --------------------------------------------------------------------------
  // OFFRE : créer
  // --------------------------------------------------------------------------
  Future<void> _onOfferPressed() async {
    final priceCtrl = TextEditingController();
    final msgCtrl = TextEditingController();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Padding(
          padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Faire une offre',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: priceCtrl,
                  decoration: InputDecoration(
                    hintText: "Votre prix (€)",
                    prefixIcon: const Icon(Icons.euro_symbol),
                    filled: true,
                    fillColor: const Color(0xFFF3F3FA),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: msgCtrl,
                  decoration: InputDecoration(
                    hintText: "Ajouter un message (optionnel)",
                    filled: true,
                    fillColor: const Color(0xFFF3F3FA),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                _buildPrimaryButton(
                  context,
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

                    final offersRef = FirebaseFirestore.instance
                        .collection('missions')
                        .doc(widget.missionId)
                        .collection('offers');

                    // Vérifier si une offre existe déjà
                    final existing = await offersRef
                        .where('userId', isEqualTo: user.uid)
                        .limit(1)
                        .get();

                    // Si offre existe → update
                    if (existing.docs.isNotEmpty) {
                      final doc = existing.docs.first;

                      await doc.reference.update({
                        'price': price,
                        'message': message,
                        'status': 'pending',
                        'updatedAt': FieldValue.serverTimestamp(),
                        'cancelledAt': FieldValue.delete(),
                      });

                      await NotificationService.notifyOfferEdited(
                        clientUserId: mission?['posterId'] ?? '',
                        missionId: widget.missionId,
                        providerName: userData['name'] ?? 'Un prestataire',
                        newPrice: price,
                      );

                      if (context.mounted) {
                        Navigator.pop(context);
                        await _loadMission();
                      }
                      return;
                    }

                    // Sinon → nouvelle offre
                    final newOffer = offersRef.doc();

                    await newOffer.set({
                      'id': newOffer.id,
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

                    await NotificationService.notifyNewOffer(
                      clientUserId: mission?['posterId'] ?? '',
                      missionId: widget.missionId,
                      missionTitle: mission?['title'] ?? 'Mission',
                      providerName: userData['name'] ?? 'Un prestataire',
                      price: price,
                    );

                    if (context.mounted) {
                      Navigator.pop(context);
                      await _loadMission();
                    }
                  },
                  icon: Icons.add_circle_outline,
                  label: "Envoyer l'offre",
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatDurationHours(Map<String, dynamic>? mission) {
    if (mission == null) return "Flexible";

    final raw = mission['duration'];
    if (raw == null) return "Flexible";

    final hours =
    (raw is num) ? raw.toDouble() : double.tryParse(raw.toString());
    if (hours == null || hours <= 0) return "Flexible";

    return "${hours.toString().replaceAll('.0', '')} h";
  }

  // --------------------------------------------------------------------------
  // OFFRE : modifier
  // --------------------------------------------------------------------------
  Future<void> _onEditOfferPressed() async {
    if (_myOfferId == null || _myOfferData == null) return;

    final priceCtrl = TextEditingController(
      text: (_myOfferData?['price']?.toString() ?? ''),
    );
    final msgCtrl = TextEditingController(
      text: (_myOfferData?['message']?.toString() ?? ''),
    );

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
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Modifier mon offre',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: priceCtrl,
                  decoration: InputDecoration(
                    hintText: "Votre prix (€)",
                    prefixIcon: const Icon(Icons.euro_symbol),
                    filled: true,
                    fillColor: const Color(0xFFF3F3FA),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: msgCtrl,
                  decoration: InputDecoration(
                    hintText: "Modifier le message (optionnel)",
                    filled: true,
                    fillColor: const Color(0xFFF3F3FA),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                _buildPrimaryButton(
                  context,
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
                        .doc(_myOfferId);

                    await offerRef.update({
                      'price': price,
                      'message': message,
                      'updatedAt': FieldValue.serverTimestamp(),
                    });

                    await NotificationService.notifyOfferEdited(
                      clientUserId: mission?['posterId'] ?? '',
                      missionId: widget.missionId,
                      providerName: userData['name'] ?? 'Un prestataire',
                      newPrice: price,
                    );

                    if (context.mounted) {
                      Navigator.pop(context);
                      await _loadMission();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("✅ Offre mise à jour."),
                          backgroundColor: kPrimary,
                        ),
                      );
                    }
                  },
                  icon: Icons.save_outlined,
                  label: "Enregistrer les modifications",
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // --------------------------------------------------------------------------
  // OFFRE : retirer
  // --------------------------------------------------------------------------
  Future<void> _onWithdrawOfferPressed() async {
    if (_myOfferId == null) return;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
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
                "Retirer votre offre ?",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: kPrimary,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                "Vous ne serez plus visible parmi les offres reçues.",
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
                        "Non, garder",
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
                        backgroundColor: Colors.redAccent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text(
                        "Oui, retirer",
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

    if (confirmed != true) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final missionRef = FirebaseFirestore.instance
          .collection('missions')
          .doc(widget.missionId);

      await missionRef.collection('offers').doc(_myOfferId).update({
        'status': 'cancelled',
        'cancelledAt': FieldValue.serverTimestamp(),
      });

      await missionRef.update({
        'offersCount': FieldValue.increment(-1),
      });

      final userData = (await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get())
          .data();

      await NotificationService.notifyOfferWithdrawn(
        clientUserId: mission?['posterId'] ?? '',
        missionId: widget.missionId,
        providerName: userData?['name'] ?? 'Le prestataire',
      );

      if (mounted) {
        setState(() {
          _hasMadeOffer = false;
          _myOfferId = null;
          _myOfferData = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("🚫 Offre retirée."),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Erreur: impossible de retirer l'offre."),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  // --------------------------------------------------------------------------
  // QUESTIONS PUBLIQUES
  // --------------------------------------------------------------------------
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
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                "Répondre à la question",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                decoration: InputDecoration(
                  hintText: "Écris ta réponse...",
                  filled: true,
                  fillColor: const Color(0xFFF3F3FA),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              _buildPrimaryButton(
                context,
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
                icon: Icons.send,
                label: "Publier la réponse",
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // CHAT
  // --------------------------------------------------------------------------
  // --------------------------------------------------------------------------
  // CHAT
  // --------------------------------------------------------------------------
  Future<void> _handleOpenChat() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null || mission == null) return;

    final String missionId = widget.missionId;
    final String posterId = (mission?['posterId'] ?? '').toString();
    final String assignedToId = (mission?['assignedTo'] ?? '').toString();

    if (posterId.isEmpty || assignedToId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Erreur : prestataire introuvable.")),
        );
      }
      return;
    }

    final ids = <String>[missionId, posterId, assignedToId]..sort();
    final String chatId = ids.join('_');

    final chatRef = FirebaseFirestore.instance.collection('chats').doc(chatId);
    final snap = await chatRef.get();

    if (!snap.exists) {
      final posterDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(posterId)
          .get();
      final workerDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(assignedToId)
          .get();

      final posterData = posterDoc.data() ?? {};
      final workerData = workerDoc.data() ?? {};

      final posterName = (posterData['name'] ?? 'Client') as String;
      final posterPhoto = (posterData['photoUrl'] ?? '') as String;

      final workerName = (workerData['name'] ?? 'Prestataire') as String;
      final workerPhoto = (workerData['photoUrl'] ?? '') as String;

      if (!snap.exists) {
        final posterDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(posterId)
            .get();
        final workerDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(assignedToId)
            .get();

        final posterData = posterDoc.data() ?? {};
        final workerData = workerDoc.data() ?? {};

        final posterName = (posterData['name'] ?? 'Client') as String;
        final posterPhoto = (posterData['photoUrl'] ?? '') as String;

        final workerName = (workerData['name'] ?? 'Prestataire') as String;
        final workerPhoto = (workerData['photoUrl'] ?? '') as String;

        await chatRef.set({
          'missionId': missionId,
          'users': [posterId, assignedToId],
          'userNames': {
            posterId: posterName,
            assignedToId: workerName,
          },
          'userPhotos': {
            posterId: posterPhoto,
            assignedToId: workerPhoto,
          },
          'typing': {
            posterId: false,
            assignedToId: false,
          },
          'readBy': <String>[],
          'lastMessage': '',
          'lastMessageAt': FieldValue.serverTimestamp(),
          'lastMessageFrom': '',
          'participants': [posterId, assignedToId],
          'participantsInfo': {
            posterId: {'name': posterName, 'photoUrl': posterPhoto},
            assignedToId: {'name': workerName, 'photoUrl': workerPhoto},
          },

          // 👇👇 IMPORTANT POUR L’ONGLET BOÎTE DE RÉCEPTION
          'missionStatus': 'in_progress',
          'missionTitle': mission?['title'] ?? '',
          'missionPrice': mission?['budget'] ?? 0,

          'status': 'active',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

    }

    if (mounted) {
      context.push('/chat/$chatId');
    }
  }


  // =========================================================================
  // LOGIQUE D'ANNULATION MISSION
  // =========================================================================

  // =========================================================================
  // LOGIQUE D'ANNULATION MISSION
  // =========================================================================

  Future<void> _handleCancelMission() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    Future<void> _performCancelLogic() async {
      try {
        final missionRef = FirebaseFirestore.instance
            .collection('missions')
            .doc(widget.missionId);

        final batch = FirebaseFirestore.instance.batch();

        batch.update(missionRef, {
          'status': 'cancelled',
          'assignedTo': null,
          'cancelledAt': FieldValue.serverTimestamp(),
          'cancelledBy': user.uid,
        });

        final offersSnap = await missionRef.collection('offers').get();
        for (final doc in offersSnap.docs) {
          batch.update(doc.reference, {
            'status': 'cancelled',
            'cancelledAt': FieldValue.serverTimestamp(),
          });
        }

        await batch.commit();

        // 🔹 synchro statut mission côté chat
        final posterId = (mission?['posterId'] ?? '').toString();
        final assignedToId = (mission?['assignedTo'] ?? '').toString();

        if (posterId.isNotEmpty && assignedToId.isNotEmpty) {
          final ids = <String>[widget.missionId, posterId, assignedToId]..sort();
          final chatId = ids.join('_');

          await FirebaseFirestore.instance
              .collection('chats')
              .doc(chatId)
              .set(
            {
              'missionStatus': 'cancelled',
            },
            SetOptions(merge: true),
          );
        }

        if (isOwner) {
          await NotificationService.notifyMissionCancelledByClient(
            missionId: widget.missionId,
            missionTitle: mission?['title'] ?? 'Mission',
            assignedProviderId: mission?['assignedTo'],
          );
        } else {
          final userData = (await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get())
              .data();

          await NotificationService.notifyMissionCancelledByProvider(
            clientUserId: mission?['posterId'] ?? '',
            missionId: widget.missionId,
            missionTitle: mission?['title'] ?? 'Mission',
            providerName: userData?['name'] ?? 'Le prestataire',
          );
        }
      } catch (e) {
        debugPrint("Erreur lors de l'annulation : $e");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Erreur technique lors de l'annulation."),
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
              Text(
                isOwner ? "Annuler la mission ?" : "Vous désister ?",
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: kPrimary,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                isOwner
                    ? "Cela annulera la mission et toutes les offres en cours."
                    : "Cela annulera votre participation à cette mission.",
                textAlign: TextAlign.center,
                style: const TextStyle(color: kGreyText, height: 1.5),
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
                      child: const Text("Non, retour",
                          style: TextStyle(
                              color: kPrimary, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text("Oui, confirmer",
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
          content: Text("🚫 Annulation confirmée."),
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
      final uri = Uri(
        path: '/missions/create',
        queryParameters: {'edit': widget.missionId},
      ).toString();

      await context.push(uri);
      await _loadMission();
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

      await missionRef.update({
        'status': 'open',
        'assignedTo': null,
        'offersCount': 0,
        'cancelledAt': FieldValue.delete(),
        'cancelledBy': FieldValue.delete(),
        'reopenedAt': FieldValue.serverTimestamp(),
      });

      final offersRef = missionRef.collection('offers');
      final oldOffers = await offersRef.get();
      for (var doc in oldOffers.docs) {
        await doc.reference.delete();
      }

      final questionsRef = missionRef.collection('questions');
      final oldQuestions = await questionsRef.get();
      for (var doc in oldQuestions.docs) {
        await doc.reference.delete();
      }

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
    if (!mounted || mission == null) return;

    final current = FirebaseAuth.instance.currentUser?.uid;
    final posterId = mission?['posterId'] ?? '';
    final providerId = mission?['assignedTo'] ?? '';

    if (current == posterId && providerId.isNotEmpty) {
      context.pushNamed(
        'reviews',
        pathParameters: {'userId': providerId},
        queryParameters: {
          'missionId': widget.missionId,
          'missionTitle': mission?['title'] ?? 'Mission',
        },
      );
    } else if (current == providerId && posterId.isNotEmpty) {
      context.pushNamed(
        'reviews',
        pathParameters: {'userId': posterId},
        queryParameters: {
          'missionId': widget.missionId,
          'missionTitle': mission?['title'] ?? 'Mission',
        },
      );
    }
  }

  // --------------------------------------------------------------------------
  // MARQUER COMME TERMINÉE
  // --------------------------------------------------------------------------
  // --------------------------------------------------------------------------
  // MARQUER COMME TERMINÉE
  // --------------------------------------------------------------------------
  Future<void> _handleMarkAsDone() async {
    if (!mounted || mission == null) return;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
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
                "Marquer la mission comme terminée ?",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: kPrimary,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                "Confirme que le prestataire a bien terminé la mission.",
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
                        "Annuler",
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
                        "Oui, terminé",
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

    if (confirmed != true) return;

    final missionRef =
    FirebaseFirestore.instance.collection('missions').doc(widget.missionId);
    await missionRef.update({
      'status': 'done',
      'doneAt': FieldValue.serverTimestamp(),
    });

    // 🔹 synchro statut mission côté chat
    final posterId = (mission?['posterId'] ?? '').toString();
    final assignedToId = (mission?['assignedTo'] ?? '').toString();

    if (posterId.isNotEmpty && assignedToId.isNotEmpty) {
      final ids = <String>[widget.missionId, posterId, assignedToId]..sort();
      final chatId = ids.join('_');

      await FirebaseFirestore.instance
          .collection('chats')
          .doc(chatId)
          .set(
        {
          'missionStatus': 'done',
        },
        SetOptions(merge: true),
      );
    }

    if (assignedToId.isNotEmpty) {
      await NotificationService.notifyMissionMarkedDone(
        providerUserId: assignedToId,
        missionId: widget.missionId,
        missionTitle: mission?['title'] ?? 'Mission',
      );
    }

    if (mounted) {
      setState(() => mission?['status'] = 'done');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("✅ Mission marquée comme terminée."),
          backgroundColor: kPrimary,
        ),
      );
    }
  }


  // =========================================================================
  // MÉTHODE BUILD (UI ONLY)
  // =========================================================================

  String _formatDurationLabel(dynamic raw) {
    if (raw == null) return "Durée non précisée";
    if (raw is String && raw.trim().isNotEmpty) return raw;
    if (raw is num) {
      if (raw <= 0) return "Durée non précisée";
      if (raw < 1.5) {
        return "≈ ${raw.toStringAsFixed(1)} h";
      }
      return "${raw.toStringAsFixed(1)} h";
    }
    return "Durée non précisée";
  }

  @override
  Widget build(BuildContext context) {
    if (mission == null) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        appBar: buildAppleMissionAppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          title: "Détails de la mission",
        ),
        body: Container(
          decoration: const BoxDecoration(
            gradient: _detailBackgroundGradient,
          ),
          child:
          const Center(child: CircularProgressIndicator(color: kPrimary)),
        ),
      );
    }

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

    final categoryLabel = (mission?['categoryLabel'] ??
        mission?['category'] ??
        'Catégorie non précisée')
        .toString();

    final offersCount = (mission?['offersCount'] ?? 0) as int;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: buildAppleMissionAppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: "Détails de la mission",
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: _detailBackgroundGradient,
        ),
        child: SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            children: [
              // ----------------------------------------------------------------
              // CARD PRINCIPALE
              // ----------------------------------------------------------------
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.92),
                  borderRadius: BorderRadius.circular(26),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Titre + Prix
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF2F2E41),
                              height: 1.3,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEEF0FF),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Text(
                            "${budget.toStringAsFixed(0)} €",
                            style: const TextStyle(
                              color: kPrimary,
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // --- Statut + timeline horizontale + chips en grille ---
                    if (status != 'cancelled') ...[
                      SmartMissionStepper(status: status), // <--- LE NOUVEAU WIDGET
                      const SizedBox(height: 24), // Un peu plus d'espace pour respirer
                    ],

                    // ... juste après SmartMissionStepper(status: status),
                    // ... et le SizedBox(height: 24),

                    // REMPLACE _buildSmartInfoGrid PAR CECI :
                    // ---------------------------------------------------------
                    // NOUVEAU DESIGN : TOUT EN GRIS (Agencement Intelligent)
                    // ---------------------------------------------------------
                    // ---------------------------------------------------------
                    // NOUVEAU DESIGN : TOUT EN GRIS (Agencement Intelligent)
                    // ---------------------------------------------------------
                    Wrap(
                      spacing: 8, // Espace horizontal
                      runSpacing: 8, // Espace vertical
                      children: [
                        // 1. Échéance (L'info la plus importante)
                        _buildSmartGrayTag(
                            Icons.calendar_today_rounded, "Avant le $deadline"),

                        // 2. Lieu / Mode (Contexte géographique)
                        _buildSmartGrayTag(
                          mode == 'À distance'
                              ? Icons.laptop_mac
                              : Icons.place_outlined,
                          mode == 'À distance' ? "À distance" : location,
                        ),

                        // 3. Catégorie
                        _buildSmartGrayTag(
                            Icons.category_outlined, categoryLabel),

                        // 4. Durée & Flexibilité
                        _buildSmartGrayTag(
                            Icons.timer_outlined, _formatDurationHours(mission)),
                        _buildSmartGrayTag(
                            Icons.watch_later_outlined, flexibility),
                      ],
                    ),

                    // ... La suite de ton code (SizedBox, statusBadge...) reste pareil

                    const SizedBox(height: 14),

                    if (status != 'open')
                      Padding(
                        padding: const EdgeInsets.only(top: 6, bottom: 4),
                        child: _buildNonOpenStatusBadge(status),
                      ),

                    const SizedBox(height: 8),

                    if (!isOwner && status == 'open')
                      Align(
                        alignment: Alignment.centerRight,
                        child: _offerCountChip(offersCount),
                      ),

                    if (!isOwner && status == 'open')
                      const SizedBox(height: 12),

                    _buildActionButtons(context, status),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // Description
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
                        fontSize: 15,
                        height: 1.5,
                        color: kGreyText,
                      ),
                    ),
                    const SizedBox(height: 14),
                    PhotoGridSection(
                      photoUrls: allPhotos,
                      onPhotoTap: (url) =>
                          _openPhotoViewer(context, url, allPhotos),
                    ),
                  ],
                ),
              ),

              // Questions publiques
              _buildSection(
                context,
                title: "Questions publiques",
                child: Column(
                  children: [
                    MissionQuestionsSection(
                      missionId: widget.missionId,
                      stream: _questionsStream,
                      onReply: (questionId) => _openReplySheet(questionId),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFFF3F3FA),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 2),
                            child: TextField(
                              controller: _questionCtrl,
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                isDense: true,
                                hintText: "Poser une question...",
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: _sendQuestion,
                          borderRadius: BorderRadius.circular(999),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: kPrimary,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Icon(
                              Icons.send_rounded,
                              size: 18,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Posté par
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
                    formatUserName(
                        poster?['name'] ?? 'Utilisateur'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
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
                  trailing: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F3FA),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    padding: const EdgeInsets.all(6),
                    child: const Icon(Icons.chevron_right),
                  ),
                  onTap: () => context
                      .push('/profile/${mission?['posterId']}'),
                ),
              ),

              // Localisation
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
                          child: Text(
                            location,
                            style: const TextStyle(color: kGreyText),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_position != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: SizedBox(
                          height: 160,
                          child: GoogleMap(
                            initialCameraPosition: CameraPosition(
                                target: _position!, zoom: 13.5),
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
            ],
          ),
        ),
      ),
    );
  }

  // =========================================================================
  // HELPERS UI
  // =========================================================================


  Widget _buildStatusStepper(String status) {
    int level;
    switch (status) {
      case 'open':
        level = 0;
        break;
      case 'in_progress':
        level = 1;
        break;
      case 'done':
      case 'completed':
      case 'closed':
        level = 2;
        break;
      default:
        level = 0;
    }

    return SizedBox(
      width: 120,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              // ligne verticale derrière les badges
              Positioned(
                left: 22,
                top: 4,
                bottom: 4,
                child: Container(
                  width: 2,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE3E4FA),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  StatusBadge(type: 'mission', status: 'open'),
                  const SizedBox(height: 4),
                  Opacity(
                    opacity: level >= 1 ? 1.0 : 0.35,
                    child:
                    StatusBadge(type: 'mission', status: 'in_progress'),
                  ),
                  const SizedBox(height: 4),
                  Opacity(
                    opacity: level >= 2 ? 1.0 : 0.25,
                    child: StatusBadge(type: 'mission', status: 'done'),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }


  Widget _buildActionButtons(BuildContext context, String status) {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return const SizedBox.shrink();

    final String assignedTo = (mission?['assignedTo'] ?? '').toString();
    final bool isAssignedToMe = (assignedTo == currentUser.uid);

    // CLIENT
    if (isOwner) {
      switch (status) {
        case 'open':
        case 'open':
          return Column(
            children: [
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('missions')
                    .doc(widget.missionId)
                    .collection('offers')
                    .snapshots(),
                builder: (context, snap) {
                  final docs = snap.data?.docs ?? [];

                  // 🔹 Total d'offres reçues (inclut annulées)
                  final totalCount = docs.length;

                  // (optionnel) si un jour tu veux le nombre d'actives :
                  // final activeCount = docs.where((d) {
                  //   final data = d.data() as Map<String, dynamic>;
                  //   final st = (data['status'] ?? 'pending').toString();
                  //   return st != 'cancelled';
                  // }).length;

                  return _buildSecondaryButton(
                    context,
                    onPressed: () => context
                        .push('/missions/${widget.missionId}/offers'),
                    icon: Icons.people_outline,
                    // 🔹 On affiche le TOTAL, annulées incluses
                    label: "Voir les offres reçues ($totalCount)",
                  );
                },
              ),
              const SizedBox(height: 12),
              _buildPrimaryButton(
                context,
                onPressed: _confirmEditMission,
                icon: Icons.edit_outlined,
                label: "Modifier la mission",
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


        case 'in_progress':
          return Column(
            children: [
              _buildPrimaryButton(
                context,
                onPressed: _handleMarkAsDone,
                icon: Icons.check_circle_outline,
                label: "Marquer comme terminée",
              ),
              const SizedBox(height: 12),
              _buildSecondaryButton(
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
        case 'completed':
          return FutureBuilder<bool>(
            future: _hasUserAlreadyReviewed(),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const SizedBox.shrink();
              }

              final already = snap.data!;

              if (already) {
                return _buildInfoBox(
                  context,
                  icon: Icons.check_circle,
                  label: "Vous avez déjà laissé un avis",
                  color: Colors.green,
                );
              }

              return _buildPrimaryButton(
                context,
                onPressed: _handleLeaveReview,
                icon: Icons.star_outline,
                label: "Laisser un avis",
              );
            },
          );

        case 'cancelled':
          return _buildPrimaryButton(
            context,
            onPressed: _handleReopenMission,
            icon: Icons.refresh_outlined,
            label: "Rouvrir la mission",
          );
        case 'closed':
          return const SizedBox.shrink();

        default:
          return const SizedBox.shrink();
      }
    }

    // PRESTATAIRE
    else {
      switch (status) {
        case 'open':
          if (_hasMadeOffer) {
            return Column(
              children: [
                _buildInfoBox(
                  context,
                  icon: Icons.check_circle,
                  label: "Offre envoyée",
                  color: kPrimary,
                ),
                const SizedBox(height: 12),
                if (_myOfferId != null)
                  _buildSecondaryButton(
                    context,
                    onPressed: () => context.push(
                        '/missions/${widget.missionId}/offers/$_myOfferId'),
                    icon: Icons.remove_red_eye_outlined,
                    label: "Voir mon offre",
                  ),
              ],
            );
          }
          return _buildPrimaryButton(
            context,
            onPressed: _onOfferPressed,
            icon: Icons.add_circle_outline,
            label: "Faire une offre",
          );

        case 'in_progress':
          if (isAssignedToMe) {
            return Column(
              children: [
                _buildInfoBox(
                  context,
                  icon: Icons.handshake_outlined,
                  label: "Vous êtes le prestataire !",
                  color: Colors.green[700]!,
                ),
                const SizedBox(height: 12),
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
                  label: "Annuler (Désistement)",
                ),
              ],
            );
          }
          return const SizedBox.shrink();

        case 'done':
          if (isAssignedToMe) {
            return _buildPrimaryButton(
              context,
              onPressed: _handleLeaveReview,
              icon: Icons.star_outline,
              label: "Laisser un avis",
            );
          }
          return const SizedBox.shrink();

        default:
          return const SizedBox.shrink();
      }
    }
  }

  Widget _buildPrimaryButton(
      BuildContext context, {
        required VoidCallback onPressed,
        required IconData icon,
        required String label,
      }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        label: Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: kPrimary,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
    );
  }

  Widget _buildSecondaryButton(
      BuildContext context, {
        required VoidCallback onPressed,
        required IconData icon,
        required String label,
      }) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        label: Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
          minimumSize: const Size.fromHeight(48),
          side: const BorderSide(color: kPrimary, width: 1.3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          foregroundColor: kPrimary,
        ),
      ),
    );
  }

  Widget _buildDangerButton(
      BuildContext context, {
        required VoidCallback onPressed,
        required IconData icon,
        required String label,
      }) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        label: Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
          minimumSize: const Size.fromHeight(48),
          side: BorderSide(color: Colors.red[700]!, width: 1.3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          foregroundColor: Colors.red[700],
        ),
      ),
    );
  }

  Widget _buildInfoBox(
      BuildContext context, {
        required IconData icon,
        required String label,
        required Color color,
      }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5FA),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge({
    required String text,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
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
    final name = assignedToUser?['name'] ?? 'Prestataire';
    final formattedName = formatUserName(name);
    final rating = (assignedToUser?['rating'] ?? 0).toDouble();
    final reviewsCount = assignedToUser?['reviewsCount'] ?? 0;
    final userId = mission?['assignedTo'] ?? '';

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
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.green[200]!),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.handshake_outlined,
                  color: Colors.green[800]!,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  "En cours avec un prestataire",
                  style: TextStyle(
                    color: Colors.green[800]!,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
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

  Widget _buildDoneWithProviderBadge(
      BuildContext context, {
        required String title,
      }) {
    final name = assignedToUser?['name'] ?? 'Prestataire';
    final formattedName = formatUserName(name);
    final rating = (assignedToUser?['rating'] ?? 0).toDouble();
    final reviewsCount = assignedToUser?['reviewsCount'] ?? 0;
    final userId = mission?['assignedTo'] ?? '';

    return GestureDetector(
      onTap: () {
        if (userId.toString().isNotEmpty) {
          context.push('/profile/$userId');
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFE4F8E9),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.green[200]!),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.check_circle_outline,
                  color: Colors.green[800]!,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.green[800]!,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
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
    final s = status.toLowerCase();

    switch (s) {
      case 'in_progress':
        if (isOwner) {
          return _buildInProgressBadge(context);
        }
        return const SizedBox.shrink();

      case 'done':
      case 'completed':
        if (isOwner && assignedToUser != null) {
          return _buildDoneWithProviderBadge(
            context,
            title: "Mission terminée avec un prestataire",
          );
        }
        return _buildStatusBadge(
          text: "Mission terminée",
          color: kPrimary,
          icon: Icons.check_circle_outline,
        );

      case 'closed':
        if (isOwner && assignedToUser != null) {
          return _buildDoneWithProviderBadge(
            context,
            title: "Mission clôturée avec un prestataire",
          );
        }
        return _buildStatusBadge(
          text: "Mission clôturée",
          color: Colors.grey.shade700,
          icon: Icons.lock_outline,
        );
      case 'cancelled':
        return _buildStatusBadge(
          text: "Mission annulée",
          color: Colors.redAccent,
          icon: Icons.cancel_outlined,
        );

      default:
        return _buildStatusBadge(
          text: "Statut : ${status.capitalize()}",
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
              child: Center(
                child: Image.network(initialUrl, fit: BoxFit.contain),
              ),
            ),
            Positioned(
              top: 60.0,
              left: 16.0,
              child: Material(
                type: MaterialType.transparency,
                child: IconButton(
                  icon: const Icon(Icons.close,
                      color: Colors.white, size: 30.0),
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
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: const Color(0xFFF3F3FA),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: kGreyText),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            style: const TextStyle(
              color: kGreyText,
              fontWeight: FontWeight.w500,
              fontSize: 13,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );

  Widget _buildSection(
      BuildContext context, {
        required String title,
        required Widget child,
      }) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.94),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
  int _statusStepIndex(String status) {
    switch (status) {
      case 'open':
        return 0;
      case 'in_progress':
        return 1;
      case 'done':
      case 'completed':
      case 'closed':
        return 2;
      default:
        return 0;
    }
  }

  Widget _buildMissionStatusHeader(String status) {
    final currentStep = _statusStepIndex(status);
    const allStatuses = ['open', 'in_progress', 'done'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: List.generate(allStatuses.length, (index) {
            final st = allStatuses[index];
            final isActive = index == currentStep;
            return Expanded(
              child: Opacity(
                opacity: isActive ? 1.0 : 0.35,
                child: Center(
                  child: StatusBadge(
                    type: 'mission',
                    status: st,
                  ),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  // ===========================================================================
  // ✨ NOUVEAU DESIGN : PASTILLES "JOLIES ET SIMPLES"
  // ===========================================================================

  // ===========================================================================
  // ✨ DESIGN "SMART GRAY" : Sobre, Propre, Gris (Code Final)
  // ===========================================================================

  Widget _buildSmartGrayTag(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        // Fond Gris clair solide (plus net que la transparence)
        color: const Color(0xFFF4F6F8),
        borderRadius: BorderRadius.circular(12),
        // Bordure subtile
        border: Border.all(color: const Color(0xFFE0E0E0), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Icône gris moyen
          Icon(icon, size: 15, color: const Color(0xFF757575)),
          const SizedBox(width: 8),
          // Texte Gris Foncé / Noir
          Flexible(
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF2C2C2C),
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrettyChip(IconData icon, String label, {required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        // Fond très léger de la couleur demandée
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        // Bordure subtile pour bien définir la forme
        border: Border.all(color: color.withOpacity(0.2), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // L'icône prend la couleur vive
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          // Le texte reste sombre pour la lisibilité
          Flexible(
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF2F2E41), // Noir doux
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class SmartMissionStepper extends StatelessWidget {
  final String status;

  const SmartMissionStepper({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final int currentStep = _getStepFromStatus(status);

    const List<Color> activeGradient = [
      Color(0xFF6C63FF),
      Color(0xFF00B8D4),
    ];
    final Color shadowColor = activeGradient.last.withOpacity(0.5);
    final List<String> labels = ["Ouverte", "En cours", "Terminée"];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0),
          child: Row(
            children: List.generate(3, (index) {
              final bool isReached = index <= currentStep;
              final bool isLineActive = index < currentStep;

              return Expanded(
                flex: index == 2 ? 0 : 1,
                child: Row(
                  children: [
                    // ROND
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.easeOutBack,
                      width: isReached ? 20 : 14,
                      height: isReached ? 20 : 14,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: isReached
                            ? const LinearGradient(
                          colors: activeGradient,
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                            : null,
                        color: isReached ? null : const Color(0xFFE0E5ED),
                        boxShadow: isReached
                            ? [
                          BoxShadow(
                            color: shadowColor,
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          )
                        ]
                            : [],
                        border: Border.all(
                            color: Colors.white, width: isReached ? 2.5 : 0),
                      ),
                      child: Center(
                        child: isReached
                            ? const Icon(Icons.check,
                            size: 10, color: Colors.white)
                            : null,
                      ),
                    ),
                    // LIGNE
                    if (index != 2)
                      Expanded(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 700),
                          height: 4,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(2),
                            gradient: isLineActive
                                ? const LinearGradient(colors: activeGradient)
                                : null,
                            color:
                            isLineActive ? null : const Color(0xFFE0E5ED),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(3, (index) {
            final bool isCurrentStep = index == currentStep;
            final Color labelColor = index <= currentStep
                ? const Color(0xFF1A1D26)
                : Colors.grey.shade400;

            return Text(
              labels[index],
              style: TextStyle(
                fontSize: 12,
                fontWeight: isCurrentStep ? FontWeight.w800 : FontWeight.w500,
                color: labelColor,
              ),
            );
          }),
        )
      ],
    );
  }

  int _getStepFromStatus(String status) {
    switch (status) {
      case 'in_progress':
      case 'confirmed':
        return 1;
      case 'done':
      case 'completed':
      case 'paid':
      case 'closed':
        return 2;
      case 'open':
      default:
        return 0;
    }
  }
}

