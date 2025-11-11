import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart'; // Import pour DateFormat
import 'package:go_router/go_router.dart';
import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
// ✅ Utilisation de votre widget
import 'package:mamission/shared/widgets/status_badge.dart';

const kPrimary = Color(0xFF6C63FF);
const kBackground = Color(0xFFF8F6FF);
const kCard = Colors.white;
const kGreyText = Colors.black54;

// =========================================================================
// ✅ FONCTIONS HELPER (Inchangées)
// =========================================================================

// Formate le nom en "Prénom N."
String formatUserName(String fullName) {
  if (fullName.trim().isEmpty) return 'Utilisateur';
  final parts = fullName.trim().split(RegExp(r'\s+'));
  if (parts.length == 1) return _capitalize(parts.first);

  // Vérifie si la première partie est en MAJUSCULES (ex: MOUSSEHIL Achraf)
  if (parts.first == parts.first.toUpperCase() && parts.first.length > 1) {
    // Format "NOM prénom" -> "Prénom N."
    final nom = parts.first;
    final prenom = parts.last;
    return "${_capitalize(prenom)} ${nom[0].toUpperCase()}."; // Ex: Achraf M.
  } else {
    // Format "Prénom nom" -> "Prénom N."
    final prenom = parts.first;
    final nom = parts.last;
    return "${_capitalize(prenom)} ${nom[0].toUpperCase()}."; // Ex: Achraf M.
  }
}

String _capitalize(String s) {
  if (s.isEmpty) return s;
  return s[0].toUpperCase() + s.substring(1).toLowerCase();
}

// Formate le temps écoulé
String formatTimeAgo(Timestamp? timestamp) {
  if (timestamp == null) return '';
  final date = timestamp.toDate();
  final now = DateTime.now();
  final difference = now.difference(date);

  if (difference.inSeconds < 60) {
    return 'il y a ${difference.inSeconds} s';
  } else if (difference.inMinutes < 60) {
    return 'il y a ${difference.inMinutes} min';
  } else if (difference.inHours < 24) {
    return 'il y a ${difference.inHours} h';
  } else if (difference.inDays == 1) {
    return 'hier';
  } else if (difference.inDays < 7) {
    return 'il y a ${difference.inDays} j';
  } else {
    // Fallback pour les dates plus anciennes
    return DateFormat('d MMM y', 'fr_FR').format(date);
  }
}

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
  Stream<QuerySnapshot>? _questionsStream;
  final ScrollController _scrollController = ScrollController();
  final _questionCtrl = TextEditingController();

  Map<String, dynamic>? mission;
  Map<String, dynamic>? poster;
  // ✅ NOUVELLE VARIABLE D'ÉTAT pour stocker les infos du prestataire
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

  // --- Fonctions (load, offer, question) ---
  Future<void> _loadMission() async {
    final doc = await FirebaseFirestore.instance
        .collection('missions')
        .doc(widget.missionId)
        .get();
    if (!doc.exists || !mounted) return;

    final m = doc.data()!;
    final user = FirebaseAuth.instance.currentUser;

    // mission + owner
    setState(() {
      mission = m;
      isOwner = (user != null && m['posterId'] == user.uid);
    });

    // position (facultative)
    final pos = (m['position'] as Map<String, dynamic>?) ?? {};
    final lat = (pos['lat'] as num?)?.toDouble();
    final lng = (pos['lng'] as num?)?.toDouble();
    if (lat != null && lng != null) {
      setState(() => _position = LatLng(lat, lng));
    }

    // poster
    final posterId = m['posterId'];
    if (posterId is String && posterId.isNotEmpty) {
      final userDoc =
      await FirebaseFirestore.instance.collection('users').doc(posterId).get();
      if (userDoc.exists && mounted) setState(() => poster = userDoc.data());
    }

    // ✅ NOUVELLE LOGIQUE: Charger le prestataire assigné
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

    // a-t-il déjà fait une offre ?
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
      // le propriétaire ne doit pas voir "Faire une offre"
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
    // ... (Logique inchangée)
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
                    backgroundColor: kPrimary, // Utilisation constante
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(45),
                  ),
                  onPressed: () async {
                    final user = FirebaseAuth.instance.currentUser;
                    if (user == null) return;

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
                      'userName': user.displayName ?? 'Utilisateur',
                      'userPhoto': user.photoURL ?? '',
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
                      await _loadMission(); // Rafraîchit l'état (ex: _hasMadeOffer)
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
    // ... (Logique inchangée)
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
    // ... (Logique inchangée)
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
                  backgroundColor: kPrimary, // Utilisation constante
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

  // =========================================================================
  // ✅ FONCTIONS D'ACTION (Logique 2.0)
  // =========================================================================

  Future<void> _handleOpenChat() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || mission == null) return;

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
      // Logique de création de chat
      final posterId = mission?['posterId'];
      final assignedToId = mission?['assignedTo'];
      final String? otherUserId = isOwner ? assignedToId : posterId;

      // ✅ DEBUG LOGS AJOUTÉS
      print("--- DEBUG CHAT ---");
      print("Rôle: ${isOwner ? 'Client' : 'Prestataire'}");
      print("posterId: $posterId");
      print("assignedToId: $assignedToId");
      print("ID de l'autre participant: $otherUserId");
      // ---

      if (otherUserId == null || otherUserId.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text("Erreur: Impossible de trouver le destinataire.")));
        }
        return;
      }

      final otherUserData =
      await FirebaseFirestore.instance.collection('users').doc(otherUserId).get();

      // ✅ DEBUG LOGS AJOUTÉS
      print("Profil destinataire trouvé: ${otherUserData.exists}");
      if (otherUserData.exists) {
        print("Données destinataire: ${otherUserData.data()}");
      }
      print("--- FIN DEBUG ---");
      // ---

      if (!otherUserData.exists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text("Erreur: Profil destinataire introuvable.")));
        }
        return;
      }

      final otherUserName = otherUserData.data()?['name'] ?? 'Utilisateur';
      if (otherUserName == 'Utilisateur') {
        print(
            "WARNING: Le champ 'name' du destinataire est manquant. Utilisation de 'Utilisateur' par défaut.");
      }

      final newChat = await chatCol.add({
        'missionId': widget.missionId,
        'participants': [user.uid, otherUserId],
        'participantsInfo': {
          user.uid: {
            'name': user.displayName ?? 'Moi',
            'photoUrl': user.photoURL ?? '',
          },
          otherUserId: {
            'name': otherUserName, // Utilise la variable
            'photoUrl': otherUserData.data()?['photoUrl'] ?? '',
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

    if (mounted) {
      context.go('/chat/$chatId'); // Ouvre le chat spécifique
    }
  }

  Future<void> _handleCancelMission() async {
    // TODO: Implémenter la logique d'annulation
    print("Action: Annuler la mission");
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Logique d'annulation à implémenter.")),
    );
  }

  Future<void> _handleLeaveReview() async {
    // TODO: Implémenter la logique d'avis
    print("Action: Laisser un avis");
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Logique d'avis à implémenter.")),
    );
  }

  Future<void> _handleMarkAsDone() async {
    // TODO: Implémenter la logique "Marquer comme terminée"
    print("Action: Marquer comme terminée");
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text("Logique 'Marquer comme terminée' à implémenter.")),
    );
  }

  // =========================================================================
  // ✅ WIDGET CENTRALISÉ POUR LES BOUTONS D'ACTION (Inchangé)
  // =========================================================================

  Widget _buildActionButtons(BuildContext context, String status) {
    final currentUser = FirebaseAuth.instance.currentUser;
    // Si l'utilisateur n'est pas connecté, n'affiche aucun bouton.
    if (currentUser == null) return const SizedBox.shrink();

    final String assignedTo = (mission?['assignedTo'] ?? '').toString();
    final bool isAssignedToMe = (assignedTo == currentUser.uid);

    // --- 🧩 1. VUE CLIENT (Propriétaire de la mission) ---
    if (isOwner) {
      switch (status) {
        case 'open':
        // Bouton "Voir les offres reçues (n)"
          return StreamBuilder<QuerySnapshot>(
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
          );

        case 'in_progress':
        // Boutons "Ouvrir la discussion" + "Annuler la mission"
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
        // Bouton "Laisser un avis au prestataire"
          return _buildPrimaryButton(
            context,
            onPressed: _handleLeaveReview,
            icon: Icons.star_outline,
            label: "Laisser un avis au prestataire",
          );

        case 'cancelled':
        default:
        // Aucun bouton pour 'cancelled' ou autres statuts
          return const SizedBox.shrink();
      }
    }

    // --- 🧩 2. VUE PRESTATAIRE (Visiteur ou Offreur) ---
    else {
      switch (status) {
        case 'open':
          if (_hasMadeOffer) {
            // Box "Offre déjà envoyée"
            return _buildInfoBox(
              context,
              icon: Icons.check_circle,
              label: "Offre déjà envoyée",
              color: kPrimary,
            );
          } else {
            // Bouton "Faire une offre maintenant"
            return _buildPrimaryButton(
              context,
              onPressed: _onOfferPressed,
              icon: Icons.add_circle_outline,
              label: "Faire une offre maintenant",
            );
          }

        case 'in_progress':
          if (isAssignedToMe) {
            // Le prestataire retenu voit "Ouvrir la discussion" + "Marquer comme terminée"
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
            // Un autre prestataire a été choisi -> Aucun bouton
            return const SizedBox.shrink();
          }

        case 'done':
        // Bouton "Voir l'avis du client"
          return _buildSecondaryButton(
            context,
            onPressed: _handleLeaveReview, // Réutilise la page d'avis
            icon: Icons.rate_review_outlined,
            label: "Voir l'avis du client",
          );

        case 'cancelled':
        default:
        // Aucun bouton pour 'cancelled' ou si un autre a été choisi
          return const SizedBox.shrink();
      }
    }
  }

  // --- Helpers de style pour les boutons (Inchangés) ---

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

  // =========================================================================
  // =========================================================================
  //
  //    MÉTHODE BUILD
  //
  // =========================================================================
  // =========================================================================

  @override
  Widget build(BuildContext context) {
    if (mission == null) {
      return Scaffold(
        backgroundColor: kBackground,
        appBar: AppBar(backgroundColor: kPrimary), // AppBar même au chargement
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
                  // --- Titre & Budget ---
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF2F2E41),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: kBackground,
                            borderRadius: BorderRadius.circular(99),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Text(
                            "${budget.toStringAsFixed(0)} €",
                            style: const TextStyle(
                              color: kPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
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

                  // --- Badge de Statut (sauf si 'open') ---
                  if (status != 'open')
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                      // ✅ MODIFIÉ: Appelle la fonction qui gère le cas 'in_progress'
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
  // ✅ HELPERS UI (MODIFIÉS)
  // =========================================================================

  // ✅ NOUVEAU WIDGET HELPER (factorisé)
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

  // ✅ NOUVEAU WIDGET HELPER pour le statut "en cours"
  Widget _buildInProgressBadge(BuildContext context) {
    if (assignedToUser == null) {
      // Fallback si l'utilisateur n'est pas encore chargé
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
    // Assurez-vous que l'ID est bien dans vos documents 'users'
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
          // Couleur verte claire (similaire au screenshot)
          color: const Color(0xFFE4F8E9),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.green[200]!),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Ligne 1: Statut
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.assignment_turned_in_outlined, // Icône du screenshot
                    color: Colors.green[800]!,
                    size: 20),
                const SizedBox(width: 8),
                Text(
                  "En cours avec un prestataire",
                  style: TextStyle(
                    color: Colors.green[800]!,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
            // Ligne 2: Infos prestataire
            Padding(
              padding: const EdgeInsets.only(top: 6.0),
              child: Row(
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
            ),
          ],
        ),
      ),
    );
  }

  // ✅ MODIFIÉ: Utilise les nouveaux helpers
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
    // ... (Logique inchangée)
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

  Widget _chip(IconData icon, String label) {
    // ... (Logique inchangée)
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: kBackground,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: kPrimary),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              style: const TextStyle(
                color: kPrimary,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(BuildContext context,
      {required String title, required Widget child}) {
    // ... (Logique inchangée)
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

// =========================================================================
// SECTION QUESTIONS (Modifiée)
// =========================================================================

class MissionQuestionsSection extends StatefulWidget {
  final String missionId;
  final Stream<QuerySnapshot>? stream;
  final Function(String) onReply;

  const MissionQuestionsSection({
    super.key,
    required this.missionId,
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
      stream: widget.stream,
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
            // ✅ MODIFIÉ: ListView.builder au lieu de ListView.separated
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: visibleQuestions.length,
              // ❌ separatorBuilder supprimé
              itemBuilder: (context, i) {
                final q = visibleQuestions[i];
                final data = q.data() as Map<String, dynamic>;
                final repliesCount = data['repliesCount'] ?? 0;

                return _QuestionTile(
                  data: data,
                  missionId: widget.missionId,
                  questionId: q.id,
                  repliesCount: repliesCount,
                  onReply: () => widget.onReply(q.id),
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

// =========================================================================
// WIDGET TILE QUESTION (Inchangé)
// =========================================================================
class _QuestionTile extends StatefulWidget {
  final Map<String, dynamic> data;
  final String missionId;
  final String questionId;
  final int repliesCount;
  final VoidCallback onReply;

  const _QuestionTile({
    required this.data,
    required this.missionId,
    required this.questionId,
    required this.repliesCount,
    required this.onReply,
  });

  @override
  State<_QuestionTile> createState() => _QuestionTileState();
}

class _QuestionTileState extends State<_QuestionTile> {
  bool showReplies = false;
  Map<String, dynamic>? user;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

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

    // ✅ MODIFIÉ: Le margin est conservé pour l'espacement
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
                date,
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
            _buildReplies(
              context,
              widget.missionId,
              widget.questionId,
            ),
        ],
      ),
    );
  }
}

// =========================================================================
// WIDGET : _buildReplies (Inchangé)
// =========================================================================
Widget _buildReplies(
    BuildContext context, String missionId, String questionId) {
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
        return ListView.builder(
          itemCount: replies.length,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemBuilder: (context, index) {
            final data = replies[index].data() as Map<String, dynamic>;
            return _ReplyTile(data: data);
          },
        );
      },
    ),
  );
}

// =========================================================================
// WIDGET : _ReplyTile (Inchangé)
// =========================================================================
class _ReplyTile extends StatefulWidget {
  final Map<String, dynamic> data;
  const _ReplyTile({required this.data});

  @override
  State<_ReplyTile> createState() => _ReplyTileState();
}

class _ReplyTileState extends State<_ReplyTile> {
  Map<String, dynamic>? user;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

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

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.subdirectory_arrow_right,
              color: Colors.grey, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Row pour Nom + Date
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    GestureDetector(
                      onTap: () {
                        if (userId.isNotEmpty) context.push('/profile/$userId');
                      },
                      child: Text(
                        formattedName,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                    ),
                    Text(
                      date,
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                // Bulle de message
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100, // Bulle plus claire
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    message,
                    style: const TextStyle(
                      fontSize: 13.5,
                      height: 1.4,
                      color: Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =========================================================================
// WIDGET : PhotoGridSection (Inchangé)
// =========================================================================

class PhotoGridSection extends StatelessWidget {
  final List<String> photoUrls;
  final Function(String) onPhotoTap;

  const PhotoGridSection({
    super.key,
    required this.photoUrls,
    required this.onPhotoTap,
  });

  @override
  Widget build(BuildContext context) {
    if (photoUrls.isEmpty) {
      return const SizedBox.shrink(); // Ne rien afficher si pas de photos
    }

    return Padding(
      padding: const EdgeInsets.only(top: 16.0, bottom: 8.0),
      child: Wrap(
        spacing: 12.0, // Espace horizontal
        runSpacing: 12.0, // Espace vertical
        children:
        photoUrls.map((url) => _buildPhotoItem(context, url)).toList(),
      ),
    );
  }

  Widget _buildPhotoItem(BuildContext context, String url) {
    final double itemSize =
        (MediaQuery.of(context).size.width - 40 - 24) / 3;

    return GestureDetector(
      onTap: () => onPhotoTap(url),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8.0),
        child: Container(
          width: itemSize,
          height: itemSize,
          color: Colors.grey[200],
          child: Image.network(
            url,
            fit: BoxFit.cover,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return Center(
                child: CircularProgressIndicator(
                  value: loadingProgress.expectedTotalBytes != null
                      ? loadingProgress.cumulativeBytesLoaded /
                      loadingProgress.expectedTotalBytes!
                      : null,
                  strokeWidth: 2,
                  color: kPrimary,
                ),
              );
            },
            errorBuilder: (context, error, stackTrace) =>
            const Icon(Icons.broken_image, color: Colors.grey, size: 30),
          ),
        ),
      ),
    );
  }
}

// Helper pour String (Inchangé)
extension StringExtension on String {
  String capitalize() {
    return "${this[0].toUpperCase()}${substring(1).toLowerCase()}";
  }
}