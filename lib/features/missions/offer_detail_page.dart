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

  bool _isOwner = false;
  bool _isLoading = true;
  bool _isActionLoading = false; // Pour les boutons Accepter/Refuser

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      // Récupérer l'offre
      final offerDoc = await FirebaseFirestore.instance
          .collection('missions')
          .doc(widget.missionId)
          .collection('offers')
          .doc(widget.offerId)
          .get();

      if (!offerDoc.exists) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      // Récupérer la mission (pour vérifier si on est propriétaire)
      final missionDoc = await FirebaseFirestore.instance
          .collection('missions')
          .doc(widget.missionId)
          .get();

      if (mounted) {
        setState(() {
          _offerData = offerDoc;
          _isOwner = missionDoc.exists && missionDoc['posterId'] == user.uid;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      print('Erreur _loadData: $e');
    }
  }

  // ✅ ACTION : Accepter une offre
  Future<void> _acceptOffer() async {
    if (_isActionLoading) return;
    setState(() => _isActionLoading = true);

    try {
      final batch = FirebaseFirestore.instance.batch();
      final missionRef =
      FirebaseFirestore.instance.collection('missions').doc(widget.missionId);
      final offerRef = missionRef.collection('offers').doc(widget.offerId);

      final offerData = _offerData!.data() as Map<String, dynamic>;

      // 1️⃣ Accepter cette offre
      batch.update(offerRef, {'status': 'accepted'});

      // 2️⃣ Mettre à jour la mission
      batch.update(missionRef, {
        'status': 'in_progress',
        'assignedTo': offerData['userId'],
        'assignedPrice': offerData['price'],
      });

      // 3️⃣ Refuser toutes les autres offres "en attente"
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

      // 4️⃣ Créer le chat automatiquement
      final chatRef = FirebaseFirestore.instance.collection('chats').doc();
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

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Offre acceptée ! La mission est en cours.'),
            backgroundColor: Colors.green,
          ),
        );
        context.go('/chat/${chatRef.id}');
      }
    } catch (e) {
      print('Erreur acceptOffer: $e');
    } finally {
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  // ❌ Refuser une offre
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

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Offre refusée.'),
            backgroundColor: Colors.red,
          ),
        );
        context.pop();
      }
    } catch (e) {
      print('Erreur refuseOffer: $e');
    } finally {
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F8FF),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        title: const Text("Détail de l'offre"),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF6C63FF), Color(0xFF7B6CFF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _buildBody(),
      bottomNavigationBar: _buildActionButtons(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFF6C63FF)));
    }

    if (_offerData == null || !_offerData!.exists) {
      return const Center(child: Text("Offre introuvable."));
    }

    final data = _offerData!.data() as Map<String, dynamic>;
    final userName = data['userName'] ?? 'Utilisateur';
    final userPhoto = data['userPhoto'] ?? '';
    final message = data['message'] ?? '';
    final price = (data['price'] ?? 0).toDouble();
    final status = data['status'] ?? 'pending';
    final ts = data['createdAt'] as Timestamp?;
    final date = ts != null
        ? DateFormat('d MMM yyyy, HH:mm', 'fr_FR').format(ts.toDate())
        : 'Date inconnue';

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 300),
      opacity: _isLoading ? 0 : 1,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        children: [
          _buildUserInfoCard(userName, date, userPhoto),
          const SizedBox(height: 24),
          _buildStatusBadge(status),
          const SizedBox(height: 24),
          _buildPriceCard(price),
          const SizedBox(height: 24),
          _buildMessageCard(message),
        ],
      ),
    );
  }

  Widget _buildUserInfoCard(String name, String date, String photoUrl) {
    return Material(
      color: Colors.white,
      elevation: 2,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: ListTile(
        onTap: () {},
        leading: CircleAvatar(
          radius: 24,
          backgroundColor: Colors.grey.shade200,
          backgroundImage: photoUrl.isNotEmpty
              ? NetworkImage(photoUrl)
              : const NetworkImage(
              'https://cdn-icons-png.flaticon.com/512/149/149071.png'),
        ),
        title: Text(
          name,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          "Offre envoyée le $date",
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Colors.black54,
          ),
        ),
        trailing: Icon(Icons.chevron_right, color: Colors.grey.shade400),
      ),
    );
  }

  Widget _buildPriceCard(double price) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F6FF),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 6,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            "PRIX PROPOSÉ",
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: const Color(0xFF6C63FF),
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "${price.toStringAsFixed(price.truncateToDouble() == price ? 0 : 2)} €",
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
              color: const Color(0xFF6C63FF),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageCard(String message) {
    final bool hasMessage = message.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Message du prestataire",
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            hasMessage ? message : "Aucun message fourni par le prestataire.",
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: hasMessage ? Colors.black87 : Colors.black45,
              height: 1.6,
              fontStyle: hasMessage ? FontStyle.normal : FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color backgroundColor;
    Color textColor;
    String label;
    IconData iconData;

    switch (status) {
      case 'accepted':
        backgroundColor = Colors.green.shade50;
        textColor = Colors.green.shade700;
        label = 'Offre Acceptée';
        iconData = Icons.check_circle;
        break;
      case 'declined':
        backgroundColor = Colors.red.shade50;
        textColor = Colors.red.shade700;
        label = 'Offre Refusée';
        iconData = Icons.cancel;
        break;
      default:
        backgroundColor = Colors.orange.shade50;
        textColor = Colors.orange.shade700;
        label = 'Offre en attente';
        iconData = Icons.hourglass_top;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: textColor.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(iconData, color: textColor, size: 18),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: textColor,
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }

  Widget? _buildActionButtons() {
    if (_isLoading || _offerData == null) return null;

    final status = (_offerData!.data() as Map<String, dynamic>)['status'];

    if (_isOwner && status == 'pending') {
      return Container(
        padding:
        const EdgeInsets.only(left: 16, right: 16, bottom: 30, top: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 10,
              offset: const Offset(0, -5),
            )
          ],
        ),
        child: _isActionLoading
            ? const Center(
            heightFactor: 1,
            child: CircularProgressIndicator(color: Color(0xFF6C63FF)))
            : Row(
          children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  foregroundColor: Colors.red.shade700,
                  side: BorderSide(color: Colors.red.shade700),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _refuseOffer,
                child: const Text('Refuser',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: const Color(0xFF6C63FF),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _acceptOffer,
                child: const Text('Accepter',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      );
    }
    return null;
  }
}
