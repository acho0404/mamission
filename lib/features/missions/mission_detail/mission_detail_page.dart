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

// ✅ Import du nouveau service robuste
import 'package:mamission/shared/services/notification_service.dart';
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

  Widget _offerCountChip(int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F4F6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.people, size: 14, color: Color(0xFF8E8E93)),
          const SizedBox(width: 6),
          Text(
            "$count offre${count > 1 ? 's' : ''}",
            style: const TextStyle(
              fontSize: 12.5,
              color: Color(0xFF8E8E93),
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

    // --- Récupère l'offre du worker connecté (pour modifier / retirer) ---
    final currentUser = FirebaseAuth.instance.currentUser;
    if (!isOwner && currentUser != null) {
      final existing = await FirebaseFirestore.instance
          .collection('missions')
          .doc(widget.missionId)
          .collection('offers')
          .where('userId', isEqualTo: currentUser.uid)
          .limit(1)
          .get();

      if (mounted) {
        if (existing.docs.isNotEmpty) {
          final docOffer = existing.docs.first;
          setState(() {
            _hasMadeOffer = true;
            _myOfferId = docOffer.id;
            _myOfferData = docOffer.data() as Map<String, dynamic>;
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
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Faire une offre',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),

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

                    final offersRef = FirebaseFirestore.instance
                        .collection('missions')
                        .doc(widget.missionId)
                        .collection('offers');

                    // 🔥 Vérifier si une offre existe déjà
                    final existing = await offersRef
                        .where('userId', isEqualTo: user.uid)
                        .limit(1)
                        .get();

                    // 🔥 Si offre existe → on la met à jour
                    if (existing.docs.isNotEmpty) {
                      final doc = existing.docs.first;

                      await doc.reference.update({
                        'price': price,
                        'message': message,
                        'status': 'pending',
                        'updatedAt': FieldValue.serverTimestamp(),
                        'cancelledAt': FieldValue.delete(),
                      });

                      // ✅ NOTIF ROBUSTE : Mise à jour offre
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

                    // 🔥 Sinon → nouvelle offre
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


                    // ✅ NOTIF ROBUSTE : Nouvelle offre
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

    final hours = (raw is num) ? raw.toDouble() : double.tryParse(raw.toString());
    if (hours == null || hours <= 0) return "Flexible";

    return "${hours.toString().replaceAll('.0', '')} h";
  }

  // --------------------------------------------------------------------------
  // OFFRE : modifier (tant que mission = open)
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
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Modifier mon offre',
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
                    hintText: "Modifier le message (optionnel)",
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  icon: const Icon(Icons.save_outlined),
                  label: const Text("Enregistrer les modifications"),
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
                        .doc(_myOfferId);

                    await offerRef.update({
                      'price': price,
                      'message': message,
                      'updatedAt': FieldValue.serverTimestamp(),
                    });

                    // ✅ NOTIF ROBUSTE : Modification
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
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // --------------------------------------------------------------------------
  // OFFRE : retirer (tant que mission = open)
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

      // supprime l'offre
      await missionRef.collection('offers').doc(_myOfferId).update({
        'status': 'cancelled',
        'cancelledAt': FieldValue.serverTimestamp(),
      });

      await missionRef.update({
        'offersCount': FieldValue.increment(-1), // on retire du compteur actif
      });

      // ✅ NOTIF ROBUSTE : Retrait offre
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

  // --------------------------------------------------------------------------
  // CHAT
  // --------------------------------------------------------------------------
  Future<void> _handleOpenChat() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || mission == null) return;

    final String missionId = widget.missionId;
    final String posterId = mission?['posterId'] ?? '';
    final String assignedToId = mission?['assignedTo'] ?? '';

    // 🔥 Détermine correctement l'autre utilisateur
    final bool iAmOwner = user.uid == posterId;
    final String otherUserId = iAmOwner ? assignedToId : posterId;

    if (otherUserId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Erreur: destinataire introuvable.")),
      );
      return;
    }

    // --- Vérifie si un chat EXISTE déjà entre les deux utilisateurs pour cette mission
    final chatQuery = await FirebaseFirestore.instance
        .collection('chats')
        .where('missionId', isEqualTo: missionId)
        .where('participants', arrayContains: user.uid)
        .get();

    String? existingChatId;
    for (final doc in chatQuery.docs) {
      final data = doc.data();
      final participants = List<String>.from(data['participants'] ?? []);
      if (participants.contains(otherUserId)) {
        existingChatId = doc.id;
        break;
      }
    }

    // Si trouvé → ouvrir
    if (existingChatId != null) {
      if (mounted) context.push('/chat/$existingChatId');
      return;
    }

    // --- Sinon → créer le nouveau chat proprement
    final myData = (await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get())
        .data() ??
        {};

    final otherData = (await FirebaseFirestore.instance
        .collection('users')
        .doc(otherUserId)
        .get())
        .data() ??
        {};

    final newChat = await FirebaseFirestore.instance.collection('chats').add({
      'missionId': missionId,
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

    if (mounted) context.push('/chat/${newChat.id}');
  }


  // =========================================================================
  // LOGIQUE D'ANNULATION MISSION
  // =========================================================================

  Future<void> _handleCancelMission() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Fonction interne qui exécute la logique lourde après confirmation
    Future<void> _performCancelLogic() async {
      try {
        final missionRef = FirebaseFirestore.instance
            .collection('missions')
            .doc(widget.missionId);

        // --- 1. BATCH UPDATE (Mission + Offres) ---
        final batch = FirebaseFirestore.instance.batch();

        // A. Annuler la Mission
        batch.update(missionRef, {
          'status': 'cancelled',
          'assignedTo': null,
          'cancelledAt': FieldValue.serverTimestamp(),
          'cancelledBy': user.uid, // Utile pour savoir qui a annulé
        });

        // B. Annuler toutes les Offres associées
        final offersSnap = await missionRef.collection('offers').get();
        for (final doc in offersSnap.docs) {
          // On passe tout en 'cancelled', peu importe l'état d'avant
          batch.update(doc.reference, {
            'status': 'cancelled',
            'cancelledAt': FieldValue.serverTimestamp(),
          });
        }

        // C. Valider les changements en base
        await batch.commit();


        // --- 2. NOTIFICATIONS ---

        if (isOwner) {
          // CAS 1 : Le CLIENT annule
          // On utilise la méthode du service qui prévient le prestataire assigné + les autres
          await NotificationService.notifyMissionCancelledByClient(
            missionId: widget.missionId,
            missionTitle: mission?['title'] ?? 'Mission',
            assignedProviderId: mission?['assignedTo'],
          );
        } else {
          // CAS 2 : Le PRESTATAIRE se désiste (Annule sa participation)
          // On récupère le nom du presta pour la notif
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

    // --- 3. BOITE DE DIALOGUE DE CONFIRMATION ---
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

    // --- 4. EXÉCUTION ---
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
  // MARQUER COMME TERMINÉE (CLIENT UNIQUEMENT)
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

    final assignedToId = (mission?['assignedTo'] ?? '') as String? ?? '';

    if (assignedToId.isNotEmpty) {
      // ✅ NOTIF ROBUSTE : Mission terminée
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
  // MÉTHODE BUILD (Reste inchangée, affichage seulement)
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

    // 🔹 Catégorie + durée depuis Firestore
    final categoryLabel =
    (mission?['categoryLabel'] ?? mission?['category'] ?? 'Catégorie non précisée')
        .toString();


    return Scaffold(
      backgroundColor: kBackground,
      appBar: buildAppleMissionAppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: "Détails de la mission",
      ),

      body: SingleChildScrollView(
        controller: _scrollController,
        child: Column(
          children: [
            Container(
              color: kCard,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- Titre & Budget ---
                  Padding(
                    padding:
                    const EdgeInsets.fromLTRB(20, 24, 20, 20),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF2F2E41),
                              height: 1.3,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Text(
                          "${budget.toStringAsFixed(0)} €",
                          style: const TextStyle(
                            color: kPrimary,
                            fontWeight: FontWeight.w800,
                            fontSize: 26,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 0, 20, 16),
                    child: Divider(thickness: 0.5),
                  ),

                  // --- Chips d'infos ---
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // ⬅️ Colonne chips (gauche)
                        Expanded(
                          flex: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _chip(Icons.location_on, mode),
                              const SizedBox(height: 8),

                              _chip(Icons.calendar_month, 'Avant le $deadline'),
                              const SizedBox(height: 8),

                              _chip(Icons.access_time, flexibility),
                              const SizedBox(height: 8),

                              _chip(Icons.timer, _formatDurationHours(mission)),
                              const SizedBox(height: 8),

                              _chip(Icons.category, mission?['category'] ?? 'Catégorie non spécifiée'),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),

                        const SizedBox(width: 12),

                        // ➡️ Stepper des statuts (droite)
                        Expanded(
                          flex: 1,
                          child: Builder(
                            builder: (context) {
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
                                    child: StatusBadge(type: 'mission', status: 'open'),
                                  ),
                                  const SizedBox(height: 6),
                                  Opacity(
                                    opacity: (currentLevel >= 2) ? 1.0 : 0.35,
                                    child: StatusBadge(type: 'mission', status: 'in_progress'),
                                  ),
                                  const SizedBox(height: 6),
                                  Opacity(
                                    opacity: (currentLevel >= 3) ? 1.0 : 0.35,
                                    child: StatusBadge(type: 'mission', status: 'done'),
                                  ),
                                ],
                              );
                            },
                          ),
                        )
                      ],
                    ),
                  ),



                  // --- Badge statuts non-open ---
                  if (status != 'open')
                    Padding(
                      padding:
                      const EdgeInsets.fromLTRB(20, 20, 20, 10),
                      child: _buildNonOpenStatusBadge(status),
                    ),

                  const SizedBox(height: 10),

                  // --- Boutons d'action ---
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!isOwner && status == 'open')
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Color(0xFF2C2C2E),
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.20),
                                      blurRadius: 6,
                                      offset: Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.person, size: 14, color: Colors.white),
                                    const SizedBox(width: 6),
                                    Text(
                                      "${mission?['offersCount'] ?? 0} offre${(mission?['offersCount'] ?? 0) > 1 ? 's' : ''}",
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),

                        if (!isOwner && status == 'open') const SizedBox(height: 12),

                        _buildActionButtons(context, status),
                      ],
                    ),
                  ),


                  // --- Description ---
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
                        PhotoGridSection(
                          photoUrls: allPhotos,
                          onPhotoTap: (url) =>
                              _openPhotoViewer(context, url, allPhotos),
                        ),
                      ],
                    ),
                  ),

                  // --- Questions publiques ---
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

                  // --- Posté par ---
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
                        onPressed: () => context.push('/profile/${mission?['posterId']}'),
                      ),
                    ),
                  ),

                  // --- Localisation ---
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
                                style:
                                const TextStyle(color: kGreyText),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (_position != null)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
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
  // HELPERS UI
  // =========================================================================

  Widget _buildActionButtons(BuildContext context, String status) {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return const SizedBox.shrink();

    final String assignedTo = (mission?['assignedTo'] ?? '').toString();
    final bool isAssignedToMe = (assignedTo == currentUser.uid);



    // --- 1. VUE CLIENT ---
    if (isOwner) {
      switch (status) {
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
                  final count = snap.data?.docs.length ?? 0;
                  return _buildSecondaryButton(
                    context,
                    onPressed: () => context.push('/missions/${widget.missionId}/offers'),
                    icon: Icons.people_outline,
                    label: "Voir les offres reçues ($count)",
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

              // NEW → bouton laisser avis
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
          return _buildStatusBadge(
            text: "Mission clôturée",
            color: kPrimary,
            icon: Icons.lock_outline,
          );


        default:
          return const SizedBox.shrink();
      }
    }

    // --- 2. VUE PRESTATAIRE ---
    // VUE PRESTATAIRE
    else {
      switch (status) {
        case 'open':
          if (_hasMadeOffer) {
            return Column(children: [
              _buildInfoBox(context, icon: Icons.check_circle, label: "Offre envoyée", color: kPrimary),
              const SizedBox(height: 12),
              _buildSecondaryButton(context, onPressed: _onEditOfferPressed, icon: Icons.edit_outlined, label: "Modifier mon offre"),
              const SizedBox(height: 12),
              _buildDangerButton(context, onPressed: _onWithdrawOfferPressed, icon: Icons.delete_outline, label: "Retirer mon offre"),
            ]);
          }
          return _buildPrimaryButton(context, onPressed: _onOfferPressed, icon: Icons.add_circle_outline, label: "Faire une offre");

        case 'in_progress':
          if (isAssignedToMe) {
            return Column(children: [
              _buildInfoBox(context, icon: Icons.handshake_outlined, label: "Vous êtes le prestataire !", color: Colors.green[700]!),
              const SizedBox(height: 12),
              _buildPrimaryButton(context, onPressed: _handleOpenChat, icon: Icons.chat_bubble_outline, label: "Ouvrir la discussion"),
              const SizedBox(height: 12),
              _buildDangerButton(context, onPressed: _handleCancelMission, icon: Icons.cancel_outlined, label: "Annuler (Désistement)"),
            ]);
          }
          return const SizedBox.shrink();

        case 'done':
          if (isAssignedToMe) {
            return _buildPrimaryButton(context, onPressed: _handleLeaveReview, icon: Icons.star_outline, label: "Laisser un avis");
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

  Widget _buildSecondaryButton(
      BuildContext context, {
        required VoidCallback onPressed,
        required IconData icon,
        required String label,
      }) {
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
  Widget _alreadyReviewedBox() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle, color: Colors.green),
          SizedBox(width: 8),
          Text(
            "Avis déjà donné",
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.green,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDangerButton(
      BuildContext context, {
        required VoidCallback onPressed,
        required IconData icon,
        required String label,
      }) {
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

  Widget _buildInfoBox(
      BuildContext context, {
        required IconData icon,
        required String label,
        required Color color,
      }) {
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
          borderRadius: BorderRadius.circular(12),
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

  Widget _buildNonOpenStatusBadge(String status) {
    switch (status) {
      case 'in_progress':
        if (isOwner) {
          // CLIENT → voit le prestataire choisi (normal)
          return _buildInProgressBadge(context);
        }
        // PRESTATAIRE → NE DOIT RIEN VOIR EN HAUT
        return const SizedBox.shrink();


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
    padding:
    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: kBackground,
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: Colors.grey.shade200),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: kGreyText),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            label,
            style: const TextStyle(
              color: kGreyText,
              fontWeight: FontWeight.w500,
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