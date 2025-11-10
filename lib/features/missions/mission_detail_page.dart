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
const kBackground = Color(0xFFF8F6FF); // ✅ Utilisation de votre constante
const kCard = Colors.white;
const kGreyText = Colors.black54;

class MissionDetailPage extends StatefulWidget {
  final String missionId;
  const MissionDetailPage({super.key, required this.missionId});

  @override
  State<MissionDetailPage> createState() => _MissionDetailPageState();
}

class _MissionDetailPageState extends State<MissionDetailPage> {
  // =========================================================================
  // =========================================================================
  //
  //    TOUTE VOTRE LOGIQUE (INITSTATE, LOADMISSION, ONOFFERPRESSED...)
  //    RESTE EXACTEMENT LA MÊME. ELLE EST PARFAITE.
  //
  // =========================================================================
  // =========================================================================
  bool _isImageZoomed = false;
  Stream<QuerySnapshot>? _questionsStream;
  final ScrollController _scrollController = ScrollController();
  double _scrollOffset = 0;
  final _questionCtrl = TextEditingController();

  Map<String, dynamic>? mission;
  Map<String, dynamic>? poster;

  LatLng? _position;
  bool isOwner = false;
  bool _hasMadeOffer = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      setState(() => _scrollOffset = _scrollController.offset);
    });
    _loadMission();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _questionCtrl.dispose();
    super.dispose();
  }

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
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(posterId)
          .get();
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

  // ----------------------- OFFRE -----------------------
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

                    // 🔹 Crée l'offre dans Firestore
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

                    // 🔹 Mets à jour le compteur d'offres
                    await FirebaseFirestore.instance
                        .collection('missions')
                        .doc(widget.missionId)
                        .update({
                      'offersCount': FieldValue.increment(1),
                    });

                    // 🔹 Ferme le modal et recharge la mission
                    if (context.mounted) {
                      Navigator.pop(context);

                      // ✅ Recharge les données pour mettre à jour _hasMadeOffer
                      await _loadMission();

                      // ✅ Affiche feedback visuel
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

  // ----------------------- QUESTIONS -----------------------
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
  //    ICI COMMENCE LA NOUVELLE MISE EN PAGE (BUILD METHOD)
  //
  // =========================================================================
  // =========================================================================

  @override
  Widget build(BuildContext context) {
    if (mission == null) {
      return const Scaffold(
        backgroundColor: kBackground, // Utilisation constante
        body: Center(child: CircularProgressIndicator(color: kPrimary)),
      );
    }

    // --- Extraction des données (inchangée) ---
    final title = (mission?['title'] ?? '').toString();
    final desc = (mission?['description'] ?? '').toString();
    final budget = (mission?['budget'] ?? 0).toDouble();
    final photo = (mission?['photoUrl'] ?? '').toString();
    final deadlineRaw = mission?['deadline'];
    final deadline = (deadlineRaw is Timestamp)
        ? DateFormat('d MMM yyyy', 'fr_FR').format(deadlineRaw.toDate())
        : 'Non spécifiée';
    final mode = (mission?['mode'] ?? 'Sur place').toString();
    final location = (mission?['location'] ?? 'Lieu non précisé').toString();
    final flexibility = (mission?['flexibility'] ?? 'Flexible').toString();
    final status = (mission?['status'] ?? 'open').toString();

    return Scaffold(
      backgroundColor: kBackground, // ✅ Fond plus propre
      extendBodyBehindAppBar: true,

      // --- 1. AppBar (INCHANGÉE) ---
      // Elle est parfaite et respecte votre contrainte
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
            child: Container(
              color: _scrollOffset > 60
                  ? kPrimary.withOpacity(0.90)
                  : Colors.black.withOpacity(0.15),
              child: AppBar(
                backgroundColor: Colors.transparent,
                elevation: _scrollOffset > 60 ? 3 : 0,
                foregroundColor: Colors.white,
                title: const Text("Détails de la mission"),
                actions: [
                  IconButton(
                    icon: Icon(_isImageZoomed
                        ? Icons.zoom_in_map_rounded
                        : Icons.zoom_out_map_rounded),
                    tooltip: _isImageZoomed
                        ? "Réduire l'image"
                        : "Agrandir l'image",
                    onPressed: photo.isEmpty
                        ? null
                        : () {
                      setState(() => _isImageZoomed = true);
                      showGeneralDialog(
                        context: context,
                        barrierColor: Colors.black.withOpacity(0.9),
                        barrierDismissible: true,
                        barrierLabel: MaterialLocalizations.of(context)
                            .modalBarrierDismissLabel,
                        transitionDuration:
                        const Duration(milliseconds: 250),
                        pageBuilder: (dialogContext, __, ___) {
                          return Stack(
                            fit: StackFit.expand,
                            children: [
                              InteractiveViewer(
                                minScale: 0.5,
                                maxScale: 4.0,
                                child: Center(
                                    child: Image.network(photo,
                                        fit: BoxFit.contain)),
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
                                      backgroundColor:
                                      Colors.black.withOpacity(0.4),
                                      padding: const EdgeInsets.all(8),
                                    ),
                                    onPressed: () =>
                                        Navigator.pop(dialogContext),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                        transitionBuilder: (_, anim, __, child) =>
                            FadeTransition(opacity: anim, child: child),
                      ).then((_) {
                        if (mounted) {
                          setState(() => _isImageZoomed = false);
                        }
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),

      // --- 2. Le Nouveau Body ---
      body: SingleChildScrollView(
        controller: _scrollController,
        child: Column(
          children: [
            // --- Bannière Image (SANS la carte Positioned) ---
            SizedBox(
              height: 240, // Hauteur fixe pour la bannière
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    photo.isNotEmpty
                        ? photo
                        : 'https://images.unsplash.com/photo-1501594907352-04cda38ebc29?auto=format&fit=crop&w=1000&q=60',
                    fit: BoxFit.cover,
                  ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.black.withOpacity(0.5),
                          Colors.transparent,
                          Colors.black.withOpacity(0.4),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // --- 3. La "Feuille de Contenu" unique ---
            // Elle contient TOUT le reste de la page.
            Container(
              // Elle glisse par-dessus l'image de 40px
              transform: Matrix4.translationValues(0, -40, 0),
              decoration: const BoxDecoration(
                color: kCard, // Fond blanc
                borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- Titre & Budget (ancien "Positioned") ---
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
                              fontSize: 22, // Plus grand
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF2F2E41),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        // Le budget chip
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
                              fontSize: 16, // Plus grand
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
                          flex: 2, // Donne plus d'espace aux chips
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
                          flex: 1, // Moins d'espace pour le stepper
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

                  // --- Barre de "Nombre d'offres" ---
                  Padding(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: kBackground, // kBackground
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "${mission?['offersCount'] ?? 0} offre${(mission?['offersCount'] ?? 0) > 1 ? 's' : ''} au total",
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          if (!isOwner && !_hasMadeOffer && status == 'open')
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
                              side: const BorderSide(color: kPrimary, width: 1.3),
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
                      padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          // ... (votre logique de chat inchangée)
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
                                  'name':
                                  posterData.data()?['name'] ?? 'Utilisateur',
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

                  // --- Reste du contenu (Description, Poster, Map...) ---
                  // On ajoute des "Sections" pour l'élégance
                  _buildSection(
                    context,
                    title: "Description",
                    child: Text(
                      desc.isNotEmpty ? desc : "Aucune description fournie.",
                      style: const TextStyle(fontSize: 15, height: 1.5, color: kGreyText),
                    ),
                  ),

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
                                    borderSide: const BorderSide(color: kPrimary),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide:
                                    const BorderSide(color: kPrimary, width: 2),
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
                      title: Text(_formatUserName(
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
                            Expanded(child: Text(location, style: const TextStyle(color: kGreyText))),
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

  // --------- Helpers UI (INCHANGÉS) ---------

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

  // Helper pour formater le nom de l'utilisateur
  String _formatUserName(String fullName) {
    if (fullName.trim().isEmpty) return 'Utilisateur';
    final parts = fullName.split(' ');
    if (parts.length == 1) return parts.first;
    final first = parts.first;
    final lastInitial =
    parts.last.isNotEmpty ? parts.last[0].toUpperCase() : '';
    return "$first $lastInitial.";
  }

  // ✅ NOUVEAU HELPER pour créer des sections propres
  Widget _buildSection(BuildContext context,
      {required String title, required Widget child}) {
    return Padding(
      // Ajoute une division et un padding pour chaque section
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
// =========================================================================
//
//    LES CLASSES HELPER POUR LES QUESTIONS SONT INCHANGÉES
//
// =========================================================================
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

            return _QuestionTile(
              data: data,
              repliesCount: repliesCount,
              onReply: () => onReply(doc.id),
            );
          },
        );
      },
    );
  }
}

// Widget helper pour afficher une seule question
class _QuestionTile extends StatelessWidget {
  final Map<String, dynamic> data;
  final int repliesCount;
  final VoidCallback onReply;

  const _QuestionTile({
    required this.data,
    required this.repliesCount,
    required this.onReply,
  });

  @override
  Widget build(BuildContext context) {
    final photoUrl = data['userPhoto'] as String? ?? '';
    final name = data['userName'] as String? ?? 'Utilisateur';
    final message = data['message'] as String? ?? '';
    final timestamp = data['createdAt'] as Timestamp?;
    final date = timestamp != null
        ? DateFormat('d MMM', 'fr_FR').format(timestamp.toDate())
        : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header (User + Date)
        Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundImage: (photoUrl.isNotEmpty)
                  ? NetworkImage(photoUrl)
                  : const NetworkImage(
                  'https://cdn-icons-png.flaticon.com/512/149/149071.png'),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                name,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Text(date, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          ],
        ),
        const SizedBox(height: 10),
        // Message
        Padding(
          padding: const EdgeInsets.only(left: 46), // Aligner avec le nom
          child: Text(message, style: const TextStyle(height: 1.4)),
        ),
        const SizedBox(height: 10),
        // Actions (Reply)
        Padding(
          padding: const EdgeInsets.only(left: 38),
          child: Row(
            children: [
              TextButton(
                onPressed: onReply,
                style: TextButton.styleFrom(
                    foregroundColor: kPrimary,
                    padding: const EdgeInsets.symmetric(horizontal: 8)),
                child: const Text("Répondre"),
              ),
              const SizedBox(width: 12),
              if (repliesCount > 0)
                Text(
                  "$repliesCount réponse${repliesCount > 1 ? 's' : ''}",
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                ),
            ],
          ),
        )
      ],
    );
  }
}