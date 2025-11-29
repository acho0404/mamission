import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:mamission/shared/services/notification_service.dart';
import 'package:mamission/shared/services/notification_service.dart';
import 'package:mamission/shared/apple_appbar.dart';

class OfferDetailPage extends StatefulWidget {
  final String missionId;
  final String offerId;

  const OfferDetailPage({
    super.key,
    required this.missionId,
    required this.offerId,
  });

  @override
  State<OfferDetailPage> createState() => _OfferDetailPageState();
}

class _OfferDetailPageState extends State<OfferDetailPage> {
  DocumentSnapshot? _offerData;
  Map<String, dynamic>? _missionData;
  Map<String, dynamic>? _providerUserData;
  Map<String, dynamic>? _clientUserData;

  bool _isOwner = false; // client (poster de la mission)
  bool _isProvider = false; // prestataire (owner de l'offre)
  bool _isLoading = true;
  bool _isActionLoading = false;

  static const Color kPrimary = Color(0xFF6C63FF);
  static const Color kPrimaryLight = Color(0xFF8A7FFC);
  static const Color kBackground = Color(0xFFF8F6FF);
  static const Color kDangerRed = Colors.red;
  static const Color kWarningOrange = Colors.orange;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // ------------------------------------------------------------
  // LOAD DATA (mission + offer + profils + seed négociation)
  // ------------------------------------------------------------
  Future<void> _loadData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() => _isLoading = false);
        return;
      }

      final db = FirebaseFirestore.instance;

      final missionRef = db.collection('missions').doc(widget.missionId);
      final offerRef = missionRef.collection('offers').doc(widget.offerId);

      final offerDoc = await offerRef.get();
      if (!offerDoc.exists) {
        setState(() => _isLoading = false);
        return;
      }

      final missionDoc = await missionRef.get();
      final missionData = missionDoc.data() as Map<String, dynamic>?;

      final offerMap = offerDoc.data() as Map<String, dynamic>;
      final providerUserId = (offerMap['userId'] ?? '').toString();
      final clientUserId = (missionData?['posterId'] ?? '').toString();

      Map<String, dynamic>? providerUserData;
      Map<String, dynamic>? clientUserData;

      if (providerUserId.isNotEmpty) {
        final providerDoc =
        await db.collection('users').doc(providerUserId).get();
        providerUserData = providerDoc.data();
      }

      if (clientUserId.isNotEmpty) {
        final clientDoc =
        await db.collection('users').doc(clientUserId).get();
        clientUserData = clientDoc.data();
      }

      setState(() {
        _offerData = offerDoc;
        _missionData = missionData;
        _providerUserData = providerUserData;
        _clientUserData = clientUserData;
        _isOwner = missionDoc.exists && clientUserId == user.uid;
        _isProvider = providerUserId == user.uid;
        _isLoading = false;
      });

      await _ensureInitialNegotiationSeed();
    } catch (e) {
      debugPrint('Erreur _loadData: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _ensureInitialNegotiationSeed() async {
    try {
      if (_offerData == null) return;

      final db = FirebaseFirestore.instance;
      final offerRef = db
          .collection('missions')
          .doc(widget.missionId)
          .collection('offers')
          .doc(widget.offerId);

      final negoSnap =
      await offerRef.collection('negotiations').limit(1).get();
      if (negoSnap.docs.isNotEmpty) return;

      final data = _offerData!.data() as Map<String, dynamic>;

      final double initialPrice =
      ((data['price'] ?? 0) as num).toDouble();
      final String initialMessage = (data['message'] ?? '').toString();
      final String providerUserId = (data['userId'] ?? '').toString();
      final Timestamp? createdAt = data['createdAt'] as Timestamp?;

      await offerRef.collection('negotiations').add({
        'price': initialPrice,
        'message': initialMessage,
        'senderId': providerUserId,
        'senderRole': 'provider',
        'type': 'initial',
        'createdAt': createdAt ?? FieldValue.serverTimestamp(),
      });

      await offerRef.update({
        'lastPrice': initialPrice,
        'lastSenderId': providerUserId,
      });
    } catch (e) {
      debugPrint('Erreur _ensureInitialNegotiationSeed: $e');
    }
  }

  // ------------------------------------------------------------
  // HELPERS STATUT & CHAT
  // ------------------------------------------------------------

  String _computeEffectiveStatus({
    required String missionStatus,
    required String rawOfferStatus,
    required String assignedTo,
    required String offerUserId,
  }) {
    missionStatus = missionStatus.toLowerCase();
    rawOfferStatus = rawOfferStatus.toLowerCase();

    // Mission annulée
    if (missionStatus == 'cancelled') {
      return 'mission_cancelled';
    }

    // Offre annulée
    if (rawOfferStatus == 'cancelled') {
      return 'cancelled';
    }

    // Offre refusée
    if (rawOfferStatus == 'declined' || rawOfferStatus == 'refused') {
      return 'declined';
    }

    // Offre expirée
    if (rawOfferStatus == 'expired') {
      return 'expired';
    }

    // Offre acceptée
    if (rawOfferStatus == 'accepted') {
      if (missionStatus == 'done' ||
          missionStatus == 'completed' ||
          missionStatus == 'closed') {
        return 'completed';
      }
      return 'accepted';
    }

    // Mission attribuée à quelqu’un d’autre
    if ((missionStatus == 'in_progress' ||
        missionStatus == 'done' ||
        missionStatus == 'completed' ||
        missionStatus == 'closed') &&
        assignedTo.isNotEmpty &&
        assignedTo != offerUserId) {
      return 'not_selected';
    }

    // Négociation
    if (rawOfferStatus == 'negotiating' || rawOfferStatus == 'countered') {
      return 'negotiating';
    }

    // Offre en attente sur mission ouverte
    if (missionStatus == 'open' && rawOfferStatus == 'pending') {
      return 'pending';
    }

    return rawOfferStatus;
  }

  Future<String> _createOrGetChatForMission({
    required String missionId,
    required String clientUserId,
    required String providerUserId,
  }) async {
    final db = FirebaseFirestore.instance;

    final ids = <String>[missionId, clientUserId, providerUserId]..sort();
    final chatId = ids.join('_');
    final chatRef = db.collection('chats').doc(chatId);

    final snap = await chatRef.get();
    if (snap.exists) return chatId;

    final posterDoc =
    await db.collection('users').doc(clientUserId).get();
    final workerDoc =
    await db.collection('users').doc(providerUserId).get();

    final posterData = posterDoc.data() ?? {};
    final workerData = workerDoc.data() ?? {};

    final posterName = (posterData['name'] ?? 'Client').toString();
    final posterPhoto = (posterData['photoUrl'] ?? '').toString();

    final workerName = (workerData['name'] ?? 'Prestataire').toString();
    final workerPhoto = (workerData['photoUrl'] ?? '').toString();

    await chatRef.set({
      'missionId': missionId,
      'users': [clientUserId, providerUserId],
      'userNames': {
        clientUserId: posterName,
        providerUserId: workerName,
      },
      'userPhotos': {
        clientUserId: posterPhoto,
        providerUserId: workerPhoto,
      },
      'typing': {
        clientUserId: false,
        providerUserId: false,
      },
      'readBy': <String>[],
      'lastMessage': '',
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastMessageFrom': '',
      'participants': [clientUserId, providerUserId],
      'participantsInfo': {
        clientUserId: {'name': posterName, 'photoUrl': posterPhoto},
        providerUserId: {'name': workerName, 'photoUrl': workerPhoto},
      },
      'status': 'active',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    return chatId;
  }

  // ------------------------------------------------------------
  // ACTIONS MÉTIER
  // ------------------------------------------------------------

  Future<void> _acceptOffer() async {
    if (_isActionLoading) return;
    setState(() => _isActionLoading = true);

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null || _offerData == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content:
              Text("Utilisateur non connecté ou offre introuvable."),
              backgroundColor: kDangerRed,
            ),
          );
        }
        return;
      }

      // Seul le client accepte l'offre
      if (!_isOwner) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Seul le client peut accepter une offre."),
              backgroundColor: kDangerRed,
            ),
          );
        }
        return;
      }

      final db = FirebaseFirestore.instance;
      final missionRef = db.collection('missions').doc(widget.missionId);
      final offersRef = missionRef.collection('offers');

      // Relecture de l'offre choisie
      final offerSnap = await offersRef.doc(widget.offerId).get();
      if (!offerSnap.exists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Offre introuvable."),
              backgroundColor: kDangerRed,
            ),
          );
        }
        return;
      }

      final offerData = offerSnap.data() as Map<String, dynamic>;
      final providerUserId = (offerData['userId'] ?? '').toString();

      final missionSnap = await missionRef.get();
      final missionData = missionSnap.data() as Map<String, dynamic>?;
      final clientUserId = (missionData?['posterId'] ?? '').toString();

      final lastSenderId =
      (offerData['lastSenderId'] ?? providerUserId).toString();

      // Celui qui a envoyé la dernière proposition ne peut pas accepter sa propre proposition
      if (lastSenderId == currentUser.uid) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  "Tu ne peux pas accepter ta propre proposition. Attends la réponse de l'autre."),
              backgroundColor: kWarningOrange,
            ),
          );
        }
        return;
      }

      final double price =
      ((offerData['lastPrice'] ?? offerData['price'] ?? 0) as num)
          .toDouble();
      final String missionTitle =
      (missionData?['title'] ?? 'Mission').toString();

      final allOffersSnap = await offersRef.get();
      final batch = db.batch();

      batch.update(missionRef, {
        'status': 'in_progress',
        'assignedTo': providerUserId,
        'assignedPrice': price,
        'acceptedOfferId': widget.offerId,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      for (final doc in allOffersSnap.docs) {
        final data = doc.data();
        final currentStatus = (data['status'] ?? 'pending').toString();

        if (doc.id == widget.offerId) {
          batch.update(doc.reference, {
            'status': 'accepted',
            'acceptedAt': FieldValue.serverTimestamp(),
            'finalPrice': price,
            'lastPrice': price,
          });
        } else if (currentStatus != 'cancelled') {
          batch.update(doc.reference, {
            'status': 'declined',
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      }

      await batch.commit();

      await offersRef
          .doc(widget.offerId)
          .collection('negotiations')
          .add({
        'price': price,
        'message':
        'Le client a accepté l\'offre à ${price.toStringAsFixed(2)} €.',
        'senderId': currentUser.uid,
        'senderRole': 'client',
        'type': 'accept',
        'createdAt': FieldValue.serverTimestamp(),
      });

      await NotificationService.notifyMissionAssigned(
        providerUserId: providerUserId,
        missionId: widget.missionId,
        missionTitle: missionTitle,
      );

      // Chat unique mission + client + prestataire
      final chatId = await _createOrGetChatForMission(
        missionId: widget.missionId,
        clientUserId: clientUserId,
        providerUserId: providerUserId,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Offre acceptée ! La mission est en cours.'),
          backgroundColor: Colors.green,
        ),
      );

      context.go('/chat/$chatId');
    } catch (e) {
      debugPrint('Erreur acceptOffer: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur lors de l\'acceptation : $e'),
            backgroundColor: kDangerRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  Future<void> _refuseOffer() async {
    if (_isActionLoading) return;
    setState(() => _isActionLoading = true);

    try {
      final currentUser = FirebaseAuth.instance.currentUser;

      final db = FirebaseFirestore.instance;
      final offerRef = db
          .collection('missions')
          .doc(widget.missionId)
          .collection('offers')
          .doc(widget.offerId);

      await offerRef.update({
        'status': 'declined',
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await offerRef.collection('negotiations').add({
        'price': 0,
        'message': 'Offre refusée.',
        'senderId': currentUser?.uid ?? '',
        'senderRole': _isOwner
            ? 'client'
            : _isProvider
            ? 'provider'
            : 'system',
        'type': 'refuse',
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Offre refusée.'),
          backgroundColor: kDangerRed,
        ),
      );
      context.pop();
    } catch (e) {
      debugPrint('Erreur refuseOffer: $e');
    } finally {
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  Future<void> _cancelOffer() async {
    if (_isActionLoading) return;
    setState(() => _isActionLoading = true);

    try {
      final currentUser = FirebaseAuth.instance.currentUser;

      final db = FirebaseFirestore.instance;
      final offerRef = db
          .collection('missions')
          .doc(widget.missionId)
          .collection('offers')
          .doc(widget.offerId);
      final missionRef =
      db.collection('missions').doc(widget.missionId);

      final currentData =
          _offerData?.data() as Map<String, dynamic>? ?? {};
      final double lastPrice =
      ((currentData['lastPrice'] ?? currentData['price'] ?? 0)
      as num)
          .toDouble();

      await offerRef.update({
        'status': 'cancelled',
        'updatedAt': FieldValue.serverTimestamp(),
        'cancelledAt': FieldValue.serverTimestamp(),
      });

      // décrémente le compteur d'offres actives
      await missionRef.update({
        'offersCount': FieldValue.increment(-1),
      });

      await offerRef.collection('negotiations').add({
        'price': lastPrice,
        'message': 'Offre annulée.',
        'senderId': currentUser?.uid ?? '',
        'senderRole': _isProvider
            ? 'provider'
            : _isOwner
            ? 'client'
            : 'system',
        'type': 'cancel',
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Offre annulée.'),
          backgroundColor: kDangerRed,
        ),
      );

      await _loadData();
    } catch (e) {
      debugPrint('Erreur cancelOffer: $e');
    } finally {
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  Future<void> _sendCounterOffer(double newPrice) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Utilisateur non connecté."),
              backgroundColor: kDangerRed,
            ),
          );
        }
        return;
      }

      final db = FirebaseFirestore.instance;
      final offerRef = db
          .collection('missions')
          .doc(widget.missionId)
          .collection('offers')
          .doc(widget.offerId);

      // relire pour savoir qui a envoyé la dernière proposition
      final offerSnap = await offerRef.get();
      if (!offerSnap.exists) return;

      final data = offerSnap.data() as Map<String, dynamic>;
      final providerUserId = (data['userId'] ?? '').toString();
      final lastSenderId =
      (data['lastSenderId'] ?? providerUserId).toString();

      if (lastSenderId == currentUser.uid) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  "Tu as déjà envoyé la dernière proposition."),
              backgroundColor: kWarningOrange,
            ),
          );
        }
        return;
      }

      final clientUserId =
      (_missionData?['posterId'] ?? '').toString();

      await offerRef.collection('negotiations').add({
        'price': newPrice,
        'message': '',
        'senderId': currentUser.uid,
        'senderRole':
        currentUser.uid == clientUserId ? 'client' : 'provider',
        'type': 'counter',
        'createdAt': FieldValue.serverTimestamp(),
      });

      await offerRef.update({
        'counterOffer': newPrice,
        'lastPrice': newPrice,
        'lastSenderId': currentUser.uid,
        'status': 'negotiating',
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '💬 Nouvelle contre-offre à ${newPrice.toStringAsFixed(2)} €',
            ),
            backgroundColor: kWarningOrange,
          ),
        );
        _loadData();
      }
    } catch (e) {
      debugPrint('Erreur sendCounterOffer: $e');
    }
  }

  void _showCounterOfferDialog() {
    final controller = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 20,
            right: 20,
            top: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Proposer une contre-offre",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: "Montant (€)",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimary,
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () {
                  final value = double.tryParse(
                    controller.text.replaceAll(',', '.'),
                  );
                  if (value == null || value <= 0) return;
                  Navigator.pop(context);
                  _sendCounterOffer(value);
                },
                child: const Text("Envoyer la contre-offre"),
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  // ------------------------------------------------------------
  // BUILD
  // ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    String title = "Détail de l'offre";
    if (_offerData != null) {
      final data = _offerData!.data() as Map<String, dynamic>;
      final pseudo = (data['userName'] ?? '').toString();
      if (pseudo.isNotEmpty) {
        title = "Offre de @$pseudo";
      }
    }

    return Scaffold(
      backgroundColor: kBackground,
      appBar: buildAppleMissionAppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: "Détails de l'offre",
      ),
      body: _isLoading
          ? const Center(
        child: CircularProgressIndicator(color: kPrimary),
      )
          : _offerData == null
          ? const Center(child: Text("Offre introuvable"))
          : _buildBody(theme),
      bottomNavigationBar: _buildActionBar(),
      floatingActionButton: _buildFloatingStatusButton(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  // ------------------------------------------------------------
  // HEADER MISSION (chip cliquable)
  // ------------------------------------------------------------

  Widget _buildMissionHeader() {
    if (_missionData == null) return const SizedBox.shrink();
    final m = _missionData!;
    final title = m['title'] ?? 'Mission';
    final budget = m['budget'] != null ? "${m['budget']} €" : '';
    final location = m['location'] ?? '';

    return GestureDetector(
      onTap: () => context.push('/missions/${widget.missionId}'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 18),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black12.withOpacity(0.06),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.work_outline_rounded, color: kPrimary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (budget.isNotEmpty)
                        Text(
                          budget,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: kPrimary,
                            fontSize: 13,
                          ),
                        ),
                      if (budget.isNotEmpty && location.isNotEmpty)
                        const SizedBox(width: 8),
                      if (location.isNotEmpty)
                        Flexible(
                          child: Text(
                            location,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: Colors.grey, size: 20),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------
  // BODY
  // ------------------------------------------------------------

  Widget _buildBody(ThemeData theme) {
    final data = _offerData!.data() as Map<String, dynamic>;

    final String rawStatus =
    (data['status'] ?? 'pending').toString().toLowerCase();
    final String missionStatus =
    (_missionData?['status'] ?? '').toString().toLowerCase();
    final String assignedTo =
    (_missionData?['assignedTo'] ?? '').toString();
    final String offerUserId =
    (data['userId'] ?? '').toString();

    final String status = _computeEffectiveStatus(
      missionStatus: missionStatus,
      rawOfferStatus: rawStatus,
      assignedTo: assignedTo,
      offerUserId: offerUserId,
    );

    final double lastPrice = ((data['lastPrice'] ??
        data['counterOffer'] ??
        data['price'] ??
        0) as num)
        .toDouble();

    final bool viewerIsProvider = _isProvider;
    // final bool viewerIsClient = _isOwner; // utile plus tard si besoin

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 🔹 Le prestataire voit la mission en haut
          if (_missionData != null && viewerIsProvider) _buildMissionHeader(),

          // 🔹 Statut de l'offre / mission
          _buildStatus(status, lastPrice),
          const SizedBox(height: 16),


          // 🔹 Historique de négo (bulles)
          Text(
            "Historique de la négociation",
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          _buildNegotiationHistory(data),

          const SizedBox(height: 32),
          // ❌ plus de "Offre créée le ..." ici : date uniquement dans les bulles
        ],
      ),
    );
  }


  // ------------------------------------------------------------
  // BLOC 1 – Résumé du deal
  // ------------------------------------------------------------

  Widget _buildDealSummaryCard(Map<String, dynamic> offerData) {
    final double lastPrice = ((offerData['lastPrice'] ??
        offerData['counterOffer'] ??
        offerData['price'] ??
        0) as num)
        .toDouble();

    final m = _missionData ?? {};
    final String missionTitle = (m['title'] ?? 'Mission').toString();
    final String missionCity =
    (m['city'] ?? m['location'] ?? '').toString();
    final Timestamp? missionDateTs = m['date'] as Timestamp?;
    final String? missionDate = missionDateTs != null
        ? DateFormat('d MMM', 'fr_FR').format(missionDateTs.toDate())
        : null;

    final String providerPseudo = (_providerUserData?['displayName'] ??
        offerData['userName'] ??
        'Prestataire')
        .toString();

    final String clientPseudo =
    (_clientUserData?['displayName'] ?? 'Client').toString();

    final Timestamp? ts = offerData['createdAt'] as Timestamp?;
    final String createdAtStr = ts != null
        ? DateFormat('d MMM yyyy, HH:mm', 'fr_FR').format(ts.toDate())
        : '';

    final bool viewerIsClient = _isOwner;
    final bool viewerIsProvider = _isProvider;

    String subtitle;
    if (viewerIsClient) {
      subtitle = "Proposée par @$providerPseudo";
    } else if (viewerIsProvider) {
      subtitle = "Envoyée à @$clientPseudo";
    } else {
      subtitle = "Offre de @$providerPseudo";
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black12.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "$lastPrice €",
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: kPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
          if (createdAtStr.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              "Le $createdAtStr",
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade500,
              ),
            ),
          ],
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.work_outline_rounded,
                  size: 18, color: kPrimary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  missionTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (missionCity.isNotEmpty || missionDate != null)
            Row(
              children: [
                if (missionCity.isNotEmpty) ...[
                  const Icon(Icons.location_on_outlined,
                      size: 14, color: kPrimary),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      missionCity,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                ],
                if (missionCity.isNotEmpty && missionDate != null)
                  const SizedBox(width: 10),
                if (missionDate != null) ...[
                  const Icon(Icons.event_outlined,
                      size: 14, color: kPrimary),
                  const SizedBox(width: 4),
                  Text(
                    missionDate,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------
  // BLOC 3 – Historique négo (style chat)
  // ------------------------------------------------------------

  Widget _buildNegotiationHistory(Map<String, dynamic> offerData) {
    final String providerPhoto =
    (offerData['userPhoto'] ?? '').toString();
    final String providerUserId =
    (offerData['userId'] ?? '').toString();

    final String clientPhoto =
    (_missionData?['posterPhoto'] ?? '').toString();
    final String clientUserId =
    (_missionData?['posterId'] ?? '').toString();

    final db = FirebaseFirestore.instance;

    return StreamBuilder<QuerySnapshot>(
      stream: db
          .collection('missions')
          .doc(widget.missionId)
          .collection('offers')
          .doc(widget.offerId)
          .collection('negotiations')
          .orderBy('createdAt')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: CircularProgressIndicator(color: kPrimary),
            ),
          );
        }

        final docs = snapshot.data?.docs ?? [];

        if (docs.isEmpty) {
          final fallback = _buildFallbackHistory(offerData);
          if (fallback.isEmpty) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                "Aucune négociation pour le moment.",
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
            );
          }
          return Column(children: fallback);
        }

        return Column(
          children: [
            for (final doc in docs)
              _buildNegotiationStepBubble(
                data: doc.data() as Map<String, dynamic>,
                providerPhoto: providerPhoto,
                clientPhoto: clientPhoto,
                providerUserId: providerUserId,
                clientUserId: clientUserId,
              ),
          ],
        );
      },
    );
  }

  List<Widget> _buildFallbackHistory(Map<String, dynamic> data) {
    final double initialPrice =
    ((data['price'] ?? 0) as num).toDouble();
    final String initialMessage = (data['message'] ?? '').toString();
    final double counterPrice =
    ((data['counterOffer'] ?? 0) as num).toDouble();
    final Timestamp? ts = data['createdAt'] as Timestamp?;

    final String providerUserId = (data['userId'] ?? '').toString();
    final String providerPhoto =
    (data['userPhoto'] ?? '').toString();
    final String clientUserId =
    (_missionData?['posterId'] ?? '').toString();
    final String clientPhoto =
    (_missionData?['posterPhoto'] ?? '').toString();

    final List<Widget> widgets = [];

    widgets.add(
      _buildOfferBubble(
        price: initialPrice,
        message:
        initialMessage.isNotEmpty ? initialMessage : "Aucun message.",
        fromProvider: true,
        timestamp: ts,
        providerPhoto: providerPhoto,
        clientPhoto: clientPhoto,
        providerUserId: providerUserId,
        clientUserId: clientUserId,
      ),
    );

    if (counterPrice > 0) {
      widgets.add(
        _buildOfferBubble(
          price: counterPrice,
          message: null,
          fromProvider: false,
          timestamp: null,
          providerPhoto: providerPhoto,
          clientPhoto: clientPhoto,
          providerUserId: providerUserId,
          clientUserId: clientUserId,
        ),
      );
    }

    return widgets;
  }

  Widget _buildNegotiationStepBubble({
    required Map<String, dynamic> data,
    required String providerPhoto,
    required String clientPhoto,
    required String providerUserId,
    required String clientUserId,
  }) {
    final String type = (data['type'] ?? 'counter').toString();
    final Timestamp? ts = data['createdAt'] as Timestamp?;
    final double price =
    ((data['price'] ?? 0) as num).toDouble();
    final String message = (data['message'] ?? '').toString();
    final String senderId = (data['senderId'] ?? '').toString();
    final String senderRole = (data['senderRole'] ??
        (senderId == clientUserId ? 'client' : 'provider'))
        .toString();

    if (type == 'system') {
      final String text = message.isNotEmpty
          ? message
          : 'Mise à jour de l\'offre';
      final String? dateStr = ts != null
          ? DateFormat('d MMM, HH:mm', 'fr_FR').format(ts.toDate())
          : null;

      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
            ),
            if (dateStr != null)
              Text(
                dateStr,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade400,
                ),
              ),
          ],
        ),
      );
    }

    final bool fromProvider = senderRole == 'provider';

    return _buildOfferBubble(
      price: price,
      message: message.isEmpty ? null : message,
      fromProvider: fromProvider,
      timestamp: ts,
      providerPhoto: providerPhoto,
      clientPhoto: clientPhoto,
      providerUserId: providerUserId,
      clientUserId: clientUserId,
    );
  }

  // ------------------------------------------------------------
  // BULLES STYLE VINTED
  // ------------------------------------------------------------

  Widget _buildAvatar(String photo) {
    return CircleAvatar(
      radius: 18,
      backgroundImage: photo.isNotEmpty
          ? NetworkImage(photo)
          : const NetworkImage(
        'https://cdn-icons-png.flaticon.com/512/149/149071.png',
      ),
    );
  }

  Widget _buildOfferBubble({
    required double price,
    String? message,
    required bool fromProvider,
    Timestamp? timestamp,
    required String providerPhoto,
    required String clientPhoto,
    required String providerUserId,
    required String clientUserId,
  }) {
    final bool isClientView = _isOwner;
    final bool isFromClient = !fromProvider;

    final bool isMe = (isClientView && isFromClient) ||
        (!isClientView && fromProvider);

    final String profileUserId =
    fromProvider ? providerUserId : clientUserId;
    final String avatarPhoto =
    fromProvider ? providerPhoto : clientPhoto;

    final String nameLabel;
    if (isMe) {
      nameLabel = "Vous";
    } else {
      nameLabel = fromProvider ? "Prestataire" : "Client";
    }

    final String? dateStr = timestamp != null
        ? DateFormat('d MMM, HH:mm', 'fr_FR').format(timestamp.toDate())
        : null;

    final mainAlign =
    isMe ? Alignment.centerRight : Alignment.centerLeft;

    return Align(
      alignment: mainAlign,
      child: Column(
        crossAxisAlignment:
        isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: profileUserId.isEmpty
                ? null
                : () => context.push('/profile/$profileUserId'),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment:
              isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
              children: [
                if (!isMe) _buildAvatar(avatarPhoto),
                if (!isMe) const SizedBox(width: 8),
                Flexible(
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black12.withOpacity(0.05),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          nameLabel,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF7A7A7A),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "${price.toStringAsFixed(2)} €",
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: kPrimary,
                          ),
                        ),
                        if (message != null && message.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            message,
                            style: const TextStyle(
                              fontSize: 14,
                              color: Color(0xFF333333),
                              height: 1.4,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (isMe) const SizedBox(width: 8),
                if (isMe) _buildAvatar(avatarPhoto),
              ],
            ),
          ),
          if (dateStr != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 8, right: 8),
              child: Text(
                dateStr,
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.grey,
                ),
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ------------------------------------------------------------
  // STATUS CHIP
  // ------------------------------------------------------------

  Widget _buildStatus(String status, double lastPrice) {
    Color color;
    String text;
    IconData icon;

    final normalized = status.toLowerCase();

    switch (normalized) {
      case 'accepted':
        color = Colors.green;
        text = 'Offre acceptée';
        icon = Icons.check_circle;
        break;
      case 'declined':
        color = kDangerRed;
        text = 'Offre refusée';
        icon = Icons.cancel;
        break;
      case 'cancelled':
        color = Colors.grey;
        text = 'Offre annulée';
        icon = Icons.cancel_outlined;
        break;
      case 'expired':
        color = Colors.grey;
        text = 'Offre expirée';
        icon = Icons.schedule_outlined;
        break;
      case 'negotiating':
      case 'countered':
        color = kWarningOrange;
        text = 'En négociation (${lastPrice.toStringAsFixed(2)} €)';
        icon = Icons.swap_horiz_rounded;
        break;
      case 'paid':
        color = Colors.green;
        text = 'Paiement effectué';
        icon = Icons.lock_rounded;
        break;
      case 'completed':
        color = Colors.green;
        text = 'Mission terminée';
        icon = Icons.flag_circle_rounded;
        break;
      case 'mission_cancelled':
        color = kDangerRed;
        text = 'Mission annulée';
        icon = Icons.block;
        break;
      case 'not_selected':
        color = Colors.grey;
        text = 'Offre non retenue';
        icon = Icons.info_outline_rounded;
        break;
      default:
        color = Colors.blue;
        text = _isOwner
            ? 'En attente de votre décision'
            : _isProvider
            ? 'En attente de réponse du client'
            : 'Offre en attente';
        icon = Icons.hourglass_top;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF4A4A4A),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------
  // BOUTON FLOTTANT STATUT
  // ------------------------------------------------------------

  Widget? _buildFloatingStatusButton() {
    if (_isLoading || _offerData == null) return null;
    final data = _offerData!.data() as Map<String, dynamic>;

    final String rawStatus =
    (data['status'] ?? 'pending').toString().toLowerCase();
    final String missionStatus =
    (_missionData?['status'] ?? '').toString().toLowerCase();
    final String assignedTo =
    (_missionData?['assignedTo'] ?? '').toString();
    final String offerUserId =
    (data['userId'] ?? '').toString();

    final String status = _computeEffectiveStatus(
      missionStatus: missionStatus,
      rawOfferStatus: rawStatus,
      assignedTo: assignedTo,
      offerUserId: offerUserId,
    );

    if (status == 'mission_cancelled') {
      return null;
    }

    if (status != 'accepted' &&
        status != 'declined' &&
        status != 'completed' &&
        status != 'not_selected') {
      return null;
    }

    final bool isCompleted = status == 'completed';
    final bool isAccepted = status == 'accepted';
    final bool isDeclined = status == 'declined';
    final bool isNotSelected = status == 'not_selected';

    late final Color color;
    late final IconData icon;
    late final String text;

    if (isCompleted) {
      color = Colors.green;
      icon = Icons.flag_circle_rounded;
      text = "Mission terminée";
    } else if (isAccepted) {
      color = Colors.green;
      icon = Icons.check_rounded;
      text = "Offre acceptée";
    } else if (isNotSelected) {
      color = Colors.grey;
      icon = Icons.info_outline_rounded;
      text = "Offre non retenue";
    } else if (isDeclined) {
      color = kDangerRed;
      icon = Icons.close_rounded;
      text = "Offre refusée";
    } else {
      return null;
    }

    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      child: Material(
        color: Colors.transparent,
        elevation: 0,
        child: Container(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: Colors.black26.withOpacity(0.12),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: () {},
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 12,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    text,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------
  // ACTION BAR (CTA bas écran)
  // ------------------------------------------------------------

  Widget? _buildActionBar() {
    if (_isLoading || _offerData == null) return null;

    final data = _offerData!.data() as Map<String, dynamic>;

    final String rawStatus =
    (data['status'] ?? 'pending').toString().toLowerCase();
    final String missionStatus =
    (_missionData?['status'] ?? '').toString().toLowerCase();
    final String assignedTo =
    (_missionData?['assignedTo'] ?? '').toString();
    final String offerUserId =
    (data['userId'] ?? '').toString();

    final String status = _computeEffectiveStatus(
      missionStatus: missionStatus,
      rawOfferStatus: rawStatus,
      assignedTo: assignedTo,
      offerUserId: offerUserId,
    );

    if (_isActionLoading) {
      return Container(
        height: 100,
        padding: const EdgeInsets.all(20),
        child: const Center(
            child: CircularProgressIndicator(color: kPrimary)),
      );
    }

    if (!_isOwner && !_isProvider) {
      return _infoBar(
        "Vous ne pouvez pas participer à cette négociation.",
      );
    }

    // états terminés → pas d'action
    if (status == 'accepted' ||
        status == 'declined' ||
        status == 'cancelled' ||
        status == 'expired' ||
        status == 'paid' ||
        status == 'completed' ||
        status == 'mission_cancelled' ||
        status == 'not_selected') {
      return null;
    }

    if (_isOwner) {
      // client
      return _actionBar([
        _actionButton("Refuser", kDangerRed, _refuseOffer, outlined: true),
        _actionButton(
          "Contre-offre",
          kWarningOrange,
          _showCounterOfferDialog,
          outlined: true,
        ),
        _actionButton("Accepter", kPrimary, _acceptOffer),
      ]);
    }

    if (_isProvider) {
      // prestataire
      return _actionBar([
        _actionButton(
          "Nouveau prix",
          kPrimary,
          _showCounterOfferDialog,
        ),
        _actionButton(
          "Annuler mon offre",
          kDangerRed,
          _cancelOffer,
          outlined: true,
        ),
      ]);
    }

    return null;
  }

  Widget _actionBar(List<Widget> children) => Container(
    padding: EdgeInsets.fromLTRB(
      16,
      12,
      16,
      MediaQuery.of(context).padding.bottom + 12,
    ),
    decoration: const BoxDecoration(
      color: Colors.white,
      boxShadow: [
        BoxShadow(
          color: Colors.black12,
          blurRadius: 8,
          offset: Offset(0, -4),
        )
      ],
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: children
          .map(
            (w) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: w,
          ),
        ),
      )
          .toList(),
    ),
  );

  Widget _actionButton(
      String text,
      Color color,
      VoidCallback onPressed, {
        bool outlined = false,
      }) {
    return outlined
        ? OutlinedButton(
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: color),
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(
          horizontal: 8,
          vertical: 14,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      onPressed: onPressed,
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
    )
        : ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(
          horizontal: 8,
          vertical: 14,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      onPressed: onPressed,
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _infoBar(String text) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 8,
            offset: Offset(0, -4),
          )
        ],
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: Color(0xFF4A4A4A),
        ),
      ),
    );
  }
}
