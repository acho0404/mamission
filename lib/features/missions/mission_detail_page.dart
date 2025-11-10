import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'dart:ui';
// ✅ Utilisation de votre widget
import 'package:mamission/shared/widgets/status_badge.dart';

const kPrimary = Color(0xFF6C63FF);
const kBackground = Color(0xFFF8F6FF);
const kCard = Colors.white;
const kGreyText = Colors.black54;

// ✅ FONCTION HELPER MISE AU NIVEAU SUPÉRIEUR
// Pour être accessible par _QuestionTile
String formatUserName(String fullName) {
  if (fullName.trim().isEmpty) return 'Utilisateur';
  final parts = fullName.split(' ');
  if (parts.length == 1) return parts.first;
  final first = parts.first;
  final lastInitial =
  parts.last.isNotEmpty ? parts.last[0].toUpperCase() : '';
  return "$first $lastInitial.";
}

class MissionDetailPage extends StatefulWidget {
  final String missionId;
  const MissionDetailPage({super.key, required this.missionId});

  @override
  State<MissionDetailPage> createState() => _MissionDetailPageState();
}

class _MissionDetailPageState extends State<MissionDetailPage> {
  // --- Tout votre état et logique (inchangés) ---
  Stream<QuerySnapshot>? _questionsStream;
  final ScrollController _scrollController = ScrollController();
  final _questionCtrl = TextEditingController();

  Map<String, dynamic>? mission;
  Map<String, dynamic>? poster;

  LatLng? _position;
  bool isOwner = false;
  bool _hasMadeOffer = false;

  @override
  void initState() {
    super.initState();
    // Note: _scrollOffset n'est plus utile car l'AppBar est solide
    _loadMission();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _questionCtrl.dispose();
    super.dispose();
  }

  // --- Toutes vos fonctions (load, offer, question) sont INCHANGÉES ---
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
  // =========================================================================
  //
  //    ICI COMMENCE LA MISE EN PAGE (BUILD METHOD) MODIFIÉE
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

    // ✅ NOUVEAU: Récupération de TOUTES les photos
    final String mainPhoto = (mission?['photoUrl'] ?? '').toString();
    // (Suppose que vos photos additionnelles sont dans un champ 'additionalPhotos')
    final List<String> additionalPhotos =
        (mission?['additionalPhotos'] as List?)
            ?.map((item) => item.toString())
            .toList() ??
            [];
    // Crée une liste unique de toutes les photos, en filtrant les URLs vides
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
      // ❌ extendBodyBehindAppBar: false (par défaut)

      // --- 1. AppBar (MODIFIÉE) ---
      appBar: AppBar(
        backgroundColor: kPrimary, // Couleur solide
        elevation: 3,
        foregroundColor: Colors.white,
        title: const Text("Détails de la mission"),
        // ❌ Plus d'actions de zoom ici, car plus de bannière
      ),

      // --- 2. Le Body ---
      body: SingleChildScrollView(
        controller: _scrollController,
        child: Column(
          children: [
            // ❌ BANNIÈRE IMAGE SUPPRIMÉE

            // --- 3. La "Feuille de Contenu" unique ---
            Container(
              color: kCard, // Fond blanc
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
                              'assigned': 1,
                              'in_progress': 2,
                              'completed': 3,
                              'done': 3,
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

                  // --- ✅ LOGIQUE MODIFIÉE: Barre "Offres" ou "Statut" ---
                  if (status == 'open')
                  // Si OUVERTE, on affiche le compteur d'offres
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: kBackground,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              "${mission?['offersCount'] ?? 0} offre${(mission?['offersCount'] ?? 0) > 1 ? 's' : ''} au total",
                              style:
                              const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            if (!isOwner && !_hasMadeOffer)
                              Row(
                                children: const [
                                  Icon(Icons.hourglass_empty,
                                      color: Colors.grey, size: 18),
                                  SizedBox(width: 6),
                                  Text(
                                    'Aucune offre envoyée',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    )
                  else
                  // Si PAS OUVERTE, on affiche le statut
                    Padding(
                      padding:
                      const EdgeInsets.fromLTRB(20, 20, 20, 10),
                      child: _buildNonOpenStatusBadge(status),
                    ),

                  // --- Boutons d'action (Offre / Chat) ---
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('missions')
                          .doc(widget.missionId)
                          .collection('offers')
                          .snapshots(),
                      builder: (context, snap) {
                        final count = snap.data?.docs.length ?? 0;

                        // CAS 1: L'utilisateur est le propriétaire
                        if (isOwner) {
                          return OutlinedButton.icon(
                            onPressed: () => context
                                .push('/missions/${widget.missionId}/offers'),
                            icon: const Icon(Icons.people_outline, size: 18),
                            label: Text("Voir les offres reçues ($count)"),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 14, horizontal: 18),
                              side:
                              const BorderSide(color: kPrimary, width: 1.3),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              foregroundColor: kPrimary,
                            ),
                          );
                        }

                        // CAS 2: L'utilisateur n'est PAS propriétaire
                        else {
                          if (status == 'open') {
                            if (!_hasMadeOffer) {
                              return ElevatedButton.icon(
                                onPressed: _onOfferPressed,
                                icon: const Icon(Icons.add_circle_outline),
                                label: const Text("Faire une offre maintenant"),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: kPrimary,
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size.fromHeight(55),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                              );
                            } else {
                              return Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: kBackground,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.check_circle, color: kPrimary),
                                    SizedBox(width: 8),
                                    Text(
                                      "Offre déjà envoyée",
                                      style: TextStyle(
                                        color: kPrimary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }
                          } else {
                            return const SizedBox.shrink();
                          }
                        }
                      },
                    ),
                  ),
                  if (mission?['status'] == 'in_progress' &&
                      FirebaseAuth.instance.currentUser != null &&
                      (mission?['assignedTo'] ==
                          FirebaseAuth.instance.currentUser!.uid ||
                          mission?['posterId'] ==
                              FirebaseAuth.instance.currentUser!.uid))
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final user = FirebaseAuth.instance.currentUser;
                          if (user == null) return;
                          final chatCol =
                          FirebaseFirestore.instance.collection('chats');
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
                            final posterData = await FirebaseFirestore.instance
                                .collection('users')
                                .doc(posterId)
                                .get();
                            final newChat = await chatCol.add({
                              'missionId': widget.missionId,
                              'participants': [user.uid, posterId],
                              'participantsInfo': {
                                user.uid: {
                                  'name': user.displayName ?? 'Moi',
                                  'photoUrl': user.photoURL ?? '',
                                },
                                posterId: {
                                  'name': posterData.data()?['name'] ??
                                      'Utilisateur',
                                  'photoUrl':
                                  posterData.data()?['photoUrl'] ?? '',
                                },
                              },
                              'lastMessage': '',
                              'lastSenderId': '',
                              'status': 'active',
                              'typing': {
                                user.uid: false,
                                posterId: false,
                              },
                              'createdAt': FieldValue.serverTimestamp(),
                              'updatedAt': FieldValue.serverTimestamp(),
                            });
                            chatId = newChat.id;
                          }
                          if (context.mounted) context.go('/chat');
                        },
                        icon: const Icon(Icons.chat_bubble_outline),
                        label: const Text("Ouvrir la discussion"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kPrimary,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(55),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),

                  // --- ✅ SECTION DESCRIPTION MODIFIÉE ---
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
                        // ✅ Grille de photos ajoutée ici
                        PhotoGridSection(
                          photoUrls: allPhotos,
                          onPhotoTap: (url) =>
                              _openPhotoViewer(context, url, allPhotos),
                        ),
                      ],
                    ),
                  ),

                  // --- Section Questions (utilise _QuestionTile modifié) ---
                  _buildSection(
                    context,
                    title: "Questions publiques",
                    child: Column(
                      children: [
                        MissionQuestionsSection(
                          stream: _questionsStream,
                          onReply: _openReplySheet,
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

                  // --- Section Posté par (utilise formatUserName) ---
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
                      title: Text(formatUserName(
                          poster?['name'] ?? 'Utilisateur')),
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
                          // if (poster?['id'] != null) { ... }
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
                            const Icon(Icons.place_outlined,
                                color: kGreyText),
                            const SizedBox(width: 6),
                            Expanded(
                                child: Text(location,
                                    style:
                                    const TextStyle(color: kGreyText))),
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

  // --------- Helpers UI ---------

  // ✅ NOUVEAU: Helper pour le badge de statut (remplace la barre d'offres)
  Widget _buildNonOpenStatusBadge(String status) {
    String text;
    Color color;
    IconData icon;

    switch (status) {
      case 'assigned':
      case 'in_progress':
        text = "En cours avec un prestataire";
        color = Colors.green[700]!;
        icon = Icons.handshake_outlined;
        break;
      case 'completed':
      case 'done':
        text = "Mission terminée";
        color = kPrimary;
        icon = Icons.check_circle_outline;
        break;
      case 'cancelled':
        text = "Mission annulée";
        color = Colors.red[700]!;
        icon = Icons.cancel_outlined;
        break;
      default:
        text = "Statut: ${status.capitalize()}"; // Fallback
        color = Colors.grey;
        icon = Icons.info_outline;
    }

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

  // ✅ NOUVEAU: Helper pour ouvrir la visionneuse de photos
  void _openPhotoViewer(
      BuildContext context, String initialUrl, List<String> allPhotos) {
    // Note: pour l'instant, ouvre seulement l'image cliquée.
    // Un PageView serait nécessaire pour swiper entre elles.
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

  // Helper pour créer les "chips" d'info
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

  // Helper pour créer des sections
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

// =========================================================================
// SECTION QUESTIONS (Modifiée)
// =========================================================================

class MissionQuestionsSection extends StatelessWidget {
  final Stream<QuerySnapshot>? stream;
  final Function(String) onReply;

  const MissionQuestionsSection({
    super.key,
    required this.stream,
    required this.onReply,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: stream,
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

        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: questions.length,
          separatorBuilder: (context, index) =>
          const Divider(height: 24, thickness: 0.5),
          itemBuilder: (context, index) {
            final doc = questions[index];
            final data = doc.data() as Map<String, dynamic>;
            final repliesCount = (data['repliesCount'] ?? 0) as int;

            // --- Section : Questions publiques ---
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('missions')
                  .doc(widget.missionId)
                  .collection('questions')
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final questions = snapshot.data!.docs;

                if (questions.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Text(
                      "Aucune question pour l’instant",
                      style: TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                  );
                }

                // Limite à 3 questions visibles
                final displayQuestions =
                questions.length > 3 ? questions.take(3).toList() : questions;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Questions publiques",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // --- Liste des 3 premières questions ---
                    ...displayQuestions.map((q) {
                      final data = q.data() as Map<String, dynamic>;
                      final repliesCount = data['repliesCount'] ?? 0;

                      return _QuestionTile(
                        data: data,
                        missionId: widget.missionId, // ✅ clé manquante ajoutée ici
                        questionId: q.id,
                        repliesCount: repliesCount,
                        onReply: () {
                          print("Répondre à la question ${q.id}");
                        },
                      );
                    }),

                    // --- Bouton "Voir plus" si > 3 questions ---
                    if (questions.length > 3)
                      Padding(
                        padding: const EdgeInsets.only(top: 10, left: 6),
                        child: GestureDetector(
                          onTap: () {
                            print("Voir toutes les questions");
                          },
                          child: const Text(
                            "Voir plus de questions",
                            style: TextStyle(
                              color: Color(0xFF6C63FF),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            )
          },
        );
      },
    );
  }
}

// ✅ WIDGET TILE QUESTION (MODIFIÉ)
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
    if (snap.exists) {
      setState(() => user = snap.data());
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final message = data['message'] ?? '';
    final timestamp = data['createdAt'] as Timestamp?;
    final date = timestamp != null
        ? DateFormat('d MMM', 'fr_FR').format(timestamp.toDate())
        : '';
    final userId = data['userId'] ?? '';

    final name = user?['name'] ?? data['userName'] ?? 'Utilisateur';
    final formattedName = _formatName(name);
    final photo = user?['photoUrl'] ??
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
                      Row(
                        children: [
                          const Icon(Icons.star,
                              size: 13, color: Colors.amberAccent),
                          Text(
                            '${rating.toStringAsFixed(1)}',
                            style: const TextStyle(
                                color: Colors.black87, fontSize: 12),
                          ),
                          Text(
                            ' ($reviewsCount)',
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 12),
                          ),
                        ],
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

          // --- Message principal
          Padding(
            padding: const EdgeInsets.only(left: 48),
            child: Text(
              message,
              style: const TextStyle(fontSize: 14.5, height: 1.4),
            ),
          ),

          const SizedBox(height: 6),

          // --- Bouton Répondre / Voir réponses
          Padding(
            padding: const EdgeInsets.only(left: 48),
            child: Row(
              children: [
                TextButton(
                  onPressed: () {
                    setState(() => showReplies = !showReplies);
                    if (showReplies) widget.onReply();
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF6C63FF),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: Text(
                    showReplies ? 'Masquer réponses' : 'Répondre',
                  ),
                ),
                const SizedBox(width: 10),
                if (widget.repliesCount > 0)
                  GestureDetector(
                    onTap: () => setState(() => showReplies = !showReplies),
                    child: Text(
                      showReplies
                          ? ''
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
          if (showReplies) _buildReplies(context),
        ],
      ),
    );
  }

  Widget _buildReplies(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 56, top: 8),
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('missions')
            .doc(widget.missionId)
            .collection('questions')
            .doc(widget.questionId)
            .collection('replies')
            .orderBy('createdAt', descending: false)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const SizedBox.shrink();
          final replies = snapshot.data!.docs;
          if (replies.isEmpty) {
            return const Padding(
              padding: EdgeInsets.only(left: 6),
              child: Text(
                "Aucune réponse pour l’instant",
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: replies.map((r) {
              final d = r.data() as Map<String, dynamic>;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.subdirectory_arrow_right,
                        color: Colors.grey, size: 18),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '${d['userName'] ?? 'Utilisateur'} : ${d['message'] ?? ''}',
                        style: const TextStyle(
                            fontSize: 13, color: Colors.black87, height: 1.4),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }

  String _formatName(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      final first = parts.first;
      final last = parts.last;
      return '${_capitalize(first)} ${last[0].toUpperCase()}.';
    }
    return _capitalize(name);
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

// =========================================================================
// ✅ NOUVEAU WIDGET : PhotoGridSection
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
      padding:
      const EdgeInsets.only(top: 16.0, bottom: 8.0),
      child: Wrap(
        spacing: 12.0, // Espace horizontal
        runSpacing: 12.0, // Espace vertical
        children:
        photoUrls.map((url) => _buildPhotoItem(context, url)).toList(),
      ),
    );
  }

  Widget _buildPhotoItem(BuildContext context, String url) {
    // Calcule la taille pour 3 photos par ligne
    // (Largeur écran - padding page (20*2) - spacing (12*2)) / 3
    final double itemSize =
        (MediaQuery.of(context).size.width - 40 - 24) / 3;

    return GestureDetector(
      onTap: () => onPhotoTap(url), // ✅ Action de clic
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8.0),
        child: Container(
          width: itemSize,
          height: itemSize,
          color: Colors.grey[200], // Fond en attendant le chargement
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

// Helper pour String (pour le fallback du statut)
extension StringExtension on String {
  String capitalize() {
    return "${this[0].toUpperCase()}${substring(1).toLowerCase()}";
  }
}