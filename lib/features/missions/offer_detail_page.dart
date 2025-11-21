import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

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
  bool _isOwner = false;
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

  Future<void> _loadData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() => _isLoading = false);
        return;
      }

      final offerDoc = await FirebaseFirestore.instance
          .collection('missions')
          .doc(widget.missionId)
          .collection('offers')
          .doc(widget.offerId)
          .get();

      if (!offerDoc.exists) {
        setState(() => _isLoading = false);
        return;
      }

      final missionDoc = await FirebaseFirestore.instance
          .collection('missions')
          .doc(widget.missionId)
          .get();

      final missionData = missionDoc.data() as Map<String, dynamic>?;

      setState(() {
        _offerData = offerDoc;
        _missionData = missionData;
        _isOwner =
            missionDoc.exists && (missionData?['posterId'] == user.uid);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Erreur _loadData: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _acceptOffer() async {
    if (_isActionLoading) return;
    setState(() => _isActionLoading = true);

    try {
      final batch = FirebaseFirestore.instance.batch();
      final missionRef =
      FirebaseFirestore.instance.collection('missions').doc(widget.missionId);
      final offerRef = missionRef.collection('offers').doc(widget.offerId);
      final offerData = _offerData!.data() as Map<String, dynamic>;

      batch.update(offerRef, {'status': 'accepted'});
      batch.update(missionRef, {
        'status': 'in_progress',
        'assignedTo': offerData['userId'],
        'assignedPrice':
        offerData['counterOffer'] ?? offerData['price'] ?? 0.0,
      });

      final otherOffers = await missionRef
          .collection('offers')
          .where('status', isEqualTo: 'pending')
          .get();

      for (final doc in otherOffers.docs) {
        if (doc.id != widget.offerId) {
          batch.update(doc.reference, {'status': 'declined'});
        }
      }

      await batch.commit();

      final chatRef =
      FirebaseFirestore.instance.collection('chats').doc();
      await chatRef.set({
        'missionId': widget.missionId,
        'users': [
          FirebaseAuth.instance.currentUser!.uid,
          offerData['userId'],
        ],
        'createdAt': FieldValue.serverTimestamp(),
        'lastMessage': null,
        'lastSender': null,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Offre acceptée ! La mission est en cours.'),
          backgroundColor: Colors.green,
        ),
      );
      context.go('/chat/${chatRef.id}');
    } catch (e) {
      debugPrint('Erreur acceptOffer: $e');
    } finally {
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  Future<void> _refuseOffer() async {
    if (_isActionLoading) return;
    setState(() => _isActionLoading = true);
    try {
      final offerRef = FirebaseFirestore.instance
          .collection('missions')
          .doc(widget.missionId)
          .collection('offers')
          .doc(widget.offerId);

      await offerRef.update({'status': 'declined'});
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

  Future<void> _sendCounterOffer(double newPrice) async {
    final offerRef = FirebaseFirestore.instance
        .collection('missions')
        .doc(widget.missionId)
        .collection('offers')
        .doc(widget.offerId);

    await offerRef.update({
      'counterOffer': newPrice,
      'status': 'countered',
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
          Text('💬 Contre-offre envoyée à ${newPrice.toStringAsFixed(2)} €'),
          backgroundColor: kWarningOrange,
        ),
      );
      _loadData();
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
                  final value = double.tryParse(controller.text);
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          "Détail de l'offre",
          style: TextStyle(color: Colors.white),
        ),
        centerTitle: true,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [kPrimary, kPrimaryLight],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(
        child: CircularProgressIndicator(color: kPrimary),
      )
          : _offerData == null
          ? const Center(child: Text("Offre introuvable"))
          : _buildBody(theme),
      bottomNavigationBar: _buildActionBar(),
    );
  }

  // ---------- BODY ----------

  Widget _buildMissionHeader() {
    if (_missionData == null) return const SizedBox.shrink();
    final m = _missionData!;
    final title = m['title'] ?? 'Mission';
    final budget =
    m['budget'] != null ? "${m['budget']} €" : '';
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

  Widget _buildBody(ThemeData theme) {
    final data = _offerData!.data() as Map<String, dynamic>;
    final userName = data['userName'] ?? 'Utilisateur';
    final userPhoto = data['userPhoto'] ?? '';
    final status = data['status'] ?? 'pending';
    final ts = data['createdAt'] as Timestamp?;
    final date = ts != null
        ? DateFormat('d MMM yyyy, HH:mm', 'fr_FR').format(ts.toDate())
        : 'Date inconnue';

    final initialPrice = (data['price'] ?? 0).toDouble();
    final initialMessage = data['message'] ?? '';
    final counterPrice = (data['counterOffer'] ?? 0).toDouble();

    final List<Widget> historyEvents = [];

    historyEvents.add(
      _buildOfferBubble(
        label: "Offre initiale du prestataire",
        price: initialPrice,
        message:
        initialMessage.isNotEmpty ? initialMessage : "Aucun message.",
        isMe: !_isOwner,
        timestamp: ts,
      ),
    );

    if (counterPrice > 0) {
      historyEvents.add(
        _buildOfferBubble(
          label:
          _isOwner ? "Votre contre-offre" : "Contre-offre du client",
          price: counterPrice,
          message: null,
          isMe: _isOwner,
          timestamp: null,
        ),
      );
    }

    if (status == 'accepted' || status == 'declined') {
      historyEvents.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16.0),
          child: _buildStatus(status, counterPrice),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          if (_missionData != null) _buildMissionHeader(),
          _buildUserCard(userName, userPhoto, date),
          const SizedBox(height: 24),
          if (status == 'pending' || status == 'countered') ...[
            _buildStatus(status, counterPrice),
            const SizedBox(height: 16),
          ],
          const Divider(height: 16),
          const SizedBox(height: 16),
          ...historyEvents,
          const SizedBox(height: 60),
        ],
      ),
    );
  }

  // ---------- BULLES ----------

  Widget _buildOfferBubble({
    required String label,
    required double price,
    String? message,
    required bool isMe,
    Timestamp? timestamp,
  }) {
    final align = isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final bubbleAlign = isMe ? Alignment.centerRight : Alignment.centerLeft;
    final bgColor = isMe ? kPrimary : Colors.white;
    final textColor = isMe ? Colors.white : Colors.black87;
    final priceColor = isMe ? Colors.white : kPrimary;

    final date = timestamp != null
        ? DateFormat('d MMM, HH:mm', 'fr_FR').format(timestamp.toDate())
        : null;

    return Align(
      alignment: bubbleAlign,
      child: Column(
        crossAxisAlignment: align,
        children: [
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(20),
                topRight: const Radius.circular(20),
                bottomLeft:
                isMe ? const Radius.circular(20) : const Radius.circular(4),
                bottomRight:
                isMe ? const Radius.circular(4) : const Radius.circular(20),
              ),
              boxShadow: !isMe
                  ? [
                BoxShadow(
                  color: Colors.black12.withOpacity(0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ]
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    color: textColor.withOpacity(0.9),
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "${price.toStringAsFixed(2)} €",
                  style: TextStyle(
                    color: priceColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 26,
                  ),
                ),
                if (message != null && message.isNotEmpty) ...[
                  Divider(height: 24, color: textColor.withOpacity(0.2)),
                  Text(
                    message,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 15,
                      height: 1.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (date != null)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 8, right: 8),
              child: Text(
                date,
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // ---------- USER CARD & STATUS ----------

  Widget _buildUserCard(String fullName, String photo, String date) {
    final parts = fullName.split(' ');
    final prenom = parts.isNotEmpty ? parts.first : 'Utilisateur';
    final nomInitiale =
    (parts.length > 1 && parts[1].isNotEmpty)
        ? '${parts[1][0].toUpperCase()}.'
        : '';
    final displayName = "$prenom $nomInitiale";

    final double moyenne = 4.8; // TODO
    final int nbAvis = 15; // TODO
    final userId =
        (_offerData?.data() as Map<String, dynamic>?)?['userId'] ?? '';

    return GestureDetector(
      onTap: () => context.push('/profile/$userId'),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black12.withOpacity(0.08),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundImage: photo.isNotEmpty
                  ? NetworkImage(photo)
                  : const NetworkImage(
                'https://cdn-icons-png.flaticon.com/512/149/149071.png',
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.star_rounded,
                          color: Colors.amber, size: 18),
                      const SizedBox(width: 4),
                      Text(
                        moyenne.toStringAsFixed(1),
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        "($nbAvis avis)",
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "Offre envoyée le $date",
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 13,
                    ),
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

  Widget _buildStatus(String status, double counter) {
    Color color;
    String text;
    IconData icon;
    switch (status) {
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
      case 'countered':
        color = kWarningOrange;
        text = _isOwner
            ? 'Vous avez proposé ${counter.toStringAsFixed(2)} €'
            : 'Contre-offre reçue : ${counter.toStringAsFixed(2)} €';
        icon = Icons.swap_horiz_rounded;
        break;
      default:
        color = Colors.blue;
        text = 'Offre en attente';
        icon = Icons.hourglass_top;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF5E5E6D)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
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

  // ---------- ACTION BAR ----------

  Widget? _buildActionBar() {
    if (_isLoading || _offerData == null) return null;
    final data = _offerData!.data() as Map<String, dynamic>;
    final status = data['status'];

    if (_isActionLoading) {
      return Container(
        height: 100,
        padding: const EdgeInsets.all(20),
        child:
        const Center(child: CircularProgressIndicator(color: kPrimary)),
      );
    }

    if (_isOwner && status == 'pending') {
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

    if (!_isOwner && status == 'countered') {
      return _actionBar([
        _actionButton("Refuser", kDangerRed, _refuseOffer, outlined: true),
        _actionButton("Accepter", kPrimary, _acceptOffer),
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
        padding:
        const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
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
        padding:
        const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
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
}
