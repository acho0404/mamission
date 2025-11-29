import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'chat_detail_page.dart';
import 'package:mamission/shared/apple_appbar.dart';

class ThreadsPage extends StatefulWidget {
  const ThreadsPage({super.key});

  @override
  State<ThreadsPage> createState() => _ThreadsPageState();
}

class _ThreadsPageState extends State<ThreadsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  final String myUid = FirebaseAuth.instance.currentUser!.uid;
  Future<void> _syncChatsWithMissions() async {
    try {
      final qs = await FirebaseFirestore.instance
          .collection('chats')
          .where('users', arrayContains: myUid)
          .get();

      final batch = FirebaseFirestore.instance.batch();

      for (final doc in qs.docs) {
        final data = doc.data();
        final missionId = (data['missionId'] ?? '').toString();
        final missionStatus = (data['missionStatus'] ?? '').toString();

        // si pas de mission ou déjà rempli → on touche pas
        if (missionId.isEmpty || missionStatus.isNotEmpty) continue;

        final missionSnap = await FirebaseFirestore.instance
            .collection('missions')
            .doc(missionId)
            .get();

        final mData = missionSnap.data();
        if (mData == null) continue;

        final realStatus = (mData['status'] ?? '').toString();
        if (realStatus.isEmpty) continue;

        batch.update(doc.reference, {
          'missionStatus': realStatus,
        });
      }

      await batch.commit();
    } catch (e) {
      debugPrint('Sync chats<->missions error: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _syncChatsWithMissions(); // 👈 ajout important

  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // 🔹 Helpers statut mission
  // ---------------------------------------------------------------------------

  // VRAIE règle d’archivage, alignée avec ChatDetailPage
  bool _isThreadArchived(String? rawStatus) {
    final s = (rawStatus ?? '').toLowerCase().trim();

    if (s.isEmpty) return false; // pas d'info -> on garde en réception

    return s == 'done' ||
        s == 'completed' ||
        s == 'cancelled' ||
        s == 'closed' ||
        s == 'paid';
  }







  // ---------------------------------------------------------------------------
  // 🔹 Streams
  // ---------------------------------------------------------------------------

  Stream<QuerySnapshot<Map<String, dynamic>>> _threadsStream() {
    return FirebaseFirestore.instance
        .collection('chats')
        .where('users', arrayContains: myUid)
        .orderBy('lastMessageAt', descending: true)
        .snapshots();
  }

  Stream<Map<String, dynamic>> _userPresence(String userId) {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .snapshots()
        .map((snap) {
      final d = snap.data() ?? {};
      return {
        'isOnline': d['isOnline'] ?? false,
        'lastSeen': (d['lastSeen'] as Timestamp?)?.toDate(),
      };
    });
  }

  // ---------------------------------------------------------------------------
  // 🔥 Actions métier
  // ---------------------------------------------------------------------------

  Future<void> _deleteForMe(String chatId) async {
    await FirebaseFirestore.instance.collection('chats').doc(chatId).update({
      'hiddenBy': FieldValue.arrayUnion([myUid]),
    });
  }

  Future<void> _toggleMute(String chatId, bool currentMuted) async {
    final docRef = FirebaseFirestore.instance.collection('chats').doc(chatId);
    if (currentMuted) {
      await docRef.update({'mutedBy': FieldValue.arrayRemove([myUid])});
    } else {
      await docRef.update({'mutedBy': FieldValue.arrayUnion([myUid])});
    }
    Navigator.pop(context); // fermer le bottom sheet
  }

  Future<void> _blockUser(String chatId, String otherUserId) async {
    await FirebaseFirestore.instance.collection('chats').doc(chatId).update({
      'blockedBy': FieldValue.arrayUnion([myUid]),
    });
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Utilisateur bloqué.")),
    );
  }

  Future<bool> _confirmDeleteThread(String otherName) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  "Supprimer cette discussion ?",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "Elle sera supprimée pour vous uniquement.\n"
                      "L’autre personne verra toujours l’historique.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          side: BorderSide(color: Colors.grey.shade300),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text("Annuler", style: TextStyle(color: Colors.black87)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF4B5C),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: const Text(
                          "Supprimer",
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    return result ?? false;
  }

  // ---------------------------------------------------------------------------
  // 🔥 UI PRINCIPALE (FUTURISTE)
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FF), // Fond clair futuriste
      appBar: buildAppleMissionAppBar(title: "Messages"),
      body: Stack(
        children: [
          // --- ORBES DE FOND ANIMÉS ---
          Positioned(
            top: -120,
            right: -80,
            child: _AnimatedOrb(
              color: const Color(0xFF6C63FF).withOpacity(0.16),
              size: 280,
            ),
          ),
          Positioned(
            bottom: -60,
            left: -60,
            child: _AnimatedOrb(
              color: const Color(0xFF00B8D4).withOpacity(0.14),
              size: 360,
              duration: const Duration(seconds: 6),
            ),
          ),
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
              child: Container(color: Colors.transparent),
            ),
          ),

          // --- CONTENU PRINCIPAL ---
          Column(
            children: [
              const SizedBox(height: 8),

              // --- TAB BAR FLOTTANTE (GLASSMORPHISM) ---
              Container(
                height: 52,
                margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(40),
                  border: Border.all(color: Colors.white.withOpacity(0.4), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF6C63FF).withOpacity(0.1),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(40),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: TabBar(
                      controller: _tabController,
                      indicator: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF6C63FF), Color(0xFF8B5CF6)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(40),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF6C63FF).withOpacity(0.4),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      indicatorPadding: const EdgeInsets.all(4.0),
                      indicatorSize: TabBarIndicatorSize.tab,
                      labelColor: Colors.white,
                      unselectedLabelColor: const Color(0xFF6C63FF),
                      labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, fontFamily: 'Plus Jakarta Sans'),
                      dividerColor: Colors.transparent,
                      tabs: const [
                        Tab(text: "Boîte de réception"),
                        Tab(text: "Archivés"),
                      ],
                    ),
                  ),
                ),
              ),

              // --- CONTENU DES ONGLETS ---
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildThreadsList(isArchiveTab: false),
                    _buildThreadsList(isArchiveTab: true),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 🔥 Liste de conversations (inbox / archivés)
  // ---------------------------------------------------------------------------

  Widget _buildThreadsList({required bool isArchiveTab}) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _threadsStream(),
      builder: (context, snap) {
        // --- LOADING SKELETON ---
        if (snap.connectionState == ConnectionState.waiting) {
          return const _ThreadsSkeletonList();
        }

        final allDocs = snap.data?.docs ?? [];

        final filteredDocs = allDocs.where((doc) {
          final data = doc.data();

          // soft delete : si supprimé pour moi
          final hiddenBy = List<String>.from(data['hiddenBy'] ?? []);
          if (hiddenBy.contains(myUid)) return false;

          final missionStatusRaw = (data['missionStatus'] ?? '').toString();

          final isArchived = _isThreadArchived(missionStatusRaw);

          return isArchiveTab ? isArchived : !isArchived;

        }).toList();


        // --- EMPTY STATE ---
        if (filteredDocs.isEmpty) {
          final icon = isArchiveTab ? Icons.archive_outlined : Icons.chat_bubble_outline_rounded;
          final label = isArchiveTab ? "Aucune archive" : "Aucune conversation";
          final subLabel = isArchiveTab
              ? "Vos anciennes discussions apparaîtront ici."
              : "Lancez une conversation pour commencer.";

          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.5),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 48, color: Colors.grey.shade300),
                ),
                const SizedBox(height: 16),
                Text(
                  label,
                  style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 4),
                Text(
                  subLabel,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                ),
              ],
            ),
          );
        }

        // --- LISTE ANIMÉE ---
        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 12),
          itemCount: filteredDocs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12), // Espacement plus aéré
          itemBuilder: (context, i) {
            final doc = filteredDocs[i];
            final data = doc.data();

            final missionStatusRaw = (data['missionStatus'] ?? '').toString();
            final isArchived = _isThreadArchived(missionStatusRaw);



            // Animation Staggered (cascade)
            return _StaggeredEntryCard(
              index: i,
              child: _buildThreadItem(doc, isArchived: isArchived),
            );
          },
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // 🔥 Item de conversation
  // ---------------------------------------------------------------------------

  Widget _buildThreadItem(
      QueryDocumentSnapshot<Map<String, dynamic>> doc, {
        required bool isArchived,
      }) {
    final chat = doc.data();
    final chatId = doc.id;

    final List users = List<String>.from(chat['users'] ?? const []);
    final otherId = users.firstWhere((id) => id != myUid, orElse: () => '');
    if (otherId.isEmpty) return const SizedBox.shrink();

    final names = Map<String, dynamic>.from(chat['userNames'] ?? {});
    final photos = Map<String, dynamic>.from(chat['userPhotos'] ?? {});
    final name = (names[otherId] ?? 'Utilisateur').toString();
    final photo = (photos[otherId] ?? '').toString();

    final lastMsg = (chat['lastMessage'] ?? '').toString();
    final lastFrom = (chat['lastMessageFrom'] ?? '').toString();
    final ts = chat['lastMessageAt'] as Timestamp?;
    final time = ts != null ? _formatTime(ts.toDate()) : '';

    final readBy = List<String>.from(chat['readBy'] ?? []);
    final isUnread = !readBy.contains(myUid);
    final mutedBy = List<String>.from(chat['mutedBy'] ?? []);
    final isMuted = mutedBy.contains(myUid);

    final missionTitle = chat['missionTitle'] as String?;
    final missionStatus = chat['missionStatus'] as String?;
    final missionPrice = chat['missionPrice'];

    final preview = lastMsg.isEmpty
        ? "(Aucun message)"
        : (lastFrom == myUid ? "Vous : $lastMsg" : lastMsg);

    return StreamBuilder<Map<String, dynamic>>(
      stream: _userPresence(otherId),
      builder: (context, statusSnap) {
        final presence = statusSnap.data ?? {};
        final bool isOnline = presence['isOnline'] ?? false;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _BouncingButton(
            child: Container(
              decoration: BoxDecoration(
                color: isArchived ? const Color(0xFFF9FAFB) : Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF6C63FF).withOpacity(0.06),
                    blurRadius: 15,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onLongPress: isArchived
                      ? null
                      : () => _showThreadOptions(context, chatId, isMuted, otherId, name),
                  onTap: () async {
                    await FirebaseFirestore.instance.collection('chats').doc(chatId).update({
                      'readBy': FieldValue.arrayUnion([myUid]),
                    });

                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => ChatDetailPage(chatId: chatId)),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        // AVATAR
                        Stack(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 2),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.05),
                                      blurRadius: 5,
                                      offset: const Offset(0, 2),
                                    )
                                  ]
                              ),
                              child: CircleAvatar(
                                radius: 26,
                                backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null,
                                backgroundColor: Colors.grey.shade100,
                                child: photo.isEmpty ? const Icon(Icons.person, color: Colors.grey) : null,
                              ),
                            ),
                            if (isOnline && !isArchived)
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  width: 14,
                                  height: 14,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF00C853), // Vert vif
                                    border: Border.all(color: Colors.white, width: 2.5),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(width: 16),

                        // CONTENU
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 1. Badge Mission (si existe)
                              if (missionTitle != null) ...[
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF6C63FF).withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        missionTitle.toUpperCase(),
                                        style: const TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFF6C63FF),
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                    if (missionPrice != null) ...[
                                      const SizedBox(width: 6),
                                      Text(
                                        "$missionPrice €",
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF00C853),
                                        ),
                                      ),
                                    ],
                                    const Spacer(),
                                    if (missionStatus != null)
                                      Text(
                                        missionStatus,
                                        style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.grey.shade400,
                                            fontWeight: FontWeight.w500
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                              ],

                              // 2. Nom & Heure
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Flexible(
                                    child: Text(
                                      name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          fontWeight: isUnread && !isArchived ? FontWeight.w800 : FontWeight.w600,
                                          fontSize: 16,
                                          color: Colors.black87
                                      ),
                                    ),
                                  ),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (isMuted && !isArchived)
                                        const Padding(
                                          padding: EdgeInsets.only(right: 6),
                                          child: Icon(Icons.volume_off_rounded, size: 16, color: Colors.grey),
                                        ),
                                      Text(
                                        time,
                                        style: TextStyle(
                                            color: isUnread && !isArchived ? const Color(0xFF6C63FF) : Colors.grey.shade400,
                                            fontSize: 12,
                                            fontWeight: isUnread && !isArchived ? FontWeight.w600 : FontWeight.normal
                                        ),
                                      ),
                                      if (isArchived) ...[
                                        const SizedBox(width: 8),
                                        InkWell(
                                          borderRadius: BorderRadius.circular(16),
                                          onTap: () async {
                                            final confirmed = await _confirmDeleteThread(name);
                                            if (confirmed) await _deleteForMe(chatId);
                                          },
                                          child: const Icon(Icons.more_horiz_rounded, size: 20, color: Colors.grey),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),

                              // 3. Dernier Message
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      preview,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          color: isUnread && !isArchived ? const Color(0xFF2D2D3A) : const Color(0xFF9EA3AE),
                                          fontSize: 14,
                                          fontWeight: isUnread && !isArchived ? FontWeight.w600 : FontWeight.w400,
                                          height: 1.3
                                      ),
                                    ),
                                  ),
                                  if (isUnread && !isArchived)
                                    Container(
                                      margin: const EdgeInsets.only(left: 12),
                                      width: 10,
                                      height: 10,
                                      decoration: const BoxDecoration(
                                          color: Color(0xFF6C63FF),
                                          shape: BoxShape.circle,
                                          boxShadow: [
                                            BoxShadow(
                                                color: Color(0x4D6C63FF),
                                                blurRadius: 6,
                                                offset: Offset(0, 2)
                                            )
                                          ]
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showThreadOptions(BuildContext context, String chatId, bool isMuted, String otherUid, String otherName) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: [
              // Indicateur drag
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 20),
                  width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(10)),
                ),
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), shape: BoxShape.circle),
                  child: Icon(isMuted ? Icons.notifications_active_rounded : Icons.notifications_off_rounded, color: Colors.blue),
                ),
                title: Text(isMuted ? "Réactiver les notifications" : "Mettre en sourdine", style: const TextStyle(fontWeight: FontWeight.w600)),
                onTap: () => _toggleMute(chatId, isMuted),
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), shape: BoxShape.circle),
                  child: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                ),
                title: const Text("Supprimer pour moi", style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
                onTap: () async {
                  final confirmed = await _confirmDeleteThread(otherName);
                  if (confirmed) await _deleteForMe(chatId);
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.grey.withOpacity(0.1), shape: BoxShape.circle),
                  child: const Icon(Icons.block_rounded, color: Colors.black54),
                ),
                title: const Text("Bloquer / Signaler", style: TextStyle(fontWeight: FontWeight.w600)),
                onTap: () => _blockUser(chatId, otherUid),
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  static String _formatTime(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    final msgDate = DateTime(date.year, date.month, date.day);

    final h = date.hour.toString().padLeft(2, '0');
    final m = date.minute.toString().padLeft(2, '0');
    final timeStr = "$h:$m";

    if (msgDate == today) return timeStr;
    if (msgDate == yesterday) return "Hier";
    return "${date.day}/${date.month}";
  }
}

// =========================================================================
// 🔹 WIDGETS D'ANIMATION (FUTURISTES)
// =========================================================================

/// Effet Orbe d'arrière-plan
class _AnimatedOrb extends StatefulWidget {
  final Color color;
  final double size;
  final Duration duration;

  const _AnimatedOrb({required this.color, required this.size, this.duration = const Duration(seconds: 4)});

  @override
  State<_AnimatedOrb> createState() => _AnimatedOrbState();
}

class _AnimatedOrbState extends State<_AnimatedOrb> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.scale(
          scale: 1.0 + (_controller.value * 0.1),
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color),
          ),
        );
      },
    );
  }
}

/// Bouton tactile qui rétrécit (Scale Down) sans bloquer les clics
class _BouncingButton extends StatefulWidget {
  final Widget child;

  const _BouncingButton({required this.child});

  @override
  State<_BouncingButton> createState() => _BouncingButtonState();
}

class _BouncingButtonState extends State<_BouncingButton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final double _scaleFactor = 0.97;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 100), lowerBound: 0.0, upperBound: 1.0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _controller.forward(),
      onPointerUp: (_) => _controller.reverse(),
      onPointerCancel: (_) => _controller.reverse(),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (_, child) {
          final scale = 1 - (_controller.value * (1 - _scaleFactor));
          return Transform.scale(scale: scale, child: child);
        },
        child: widget.child,
      ),
    );
  }
}

/// Animation d'entrée en cascade (Staggered)
class _StaggeredEntryCard extends StatelessWidget {
  final int index;
  final Widget child;

  const _StaggeredEntryCard({required this.index, required this.child});

  @override
  Widget build(BuildContext context) {
    final delay = Duration(milliseconds: (index * 50).clamp(0, 500));

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 600),
      curve: Interval(0.0, 1.0, curve: Curves.easeOutBack),
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, 30 * (1 - value)), // Glisse du bas vers le haut
          child: Opacity(
            opacity: value.clamp(0.0, 1.0),
            child: Transform.scale(
              scale: 0.95 + (0.05 * value), // Léger zoom in
              child: child,
            ),
          ),
        );
      },
      child: FutureBuilder(
        future: Future.delayed(delay),
        builder: (context, snapshot) {
          // Astuce visuelle : on attend le délai avant de lancer l'animation via le builder
          return child!;
        },
      ),
    );
  }
}

/// Squelette de chargement élégant
class _ThreadsSkeletonList extends StatefulWidget {
  const _ThreadsSkeletonList();

  @override
  State<_ThreadsSkeletonList> createState() => _ThreadsSkeletonListState();
}

class _ThreadsSkeletonListState extends State<_ThreadsSkeletonList> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 12),
      itemCount: 6,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Opacity(
                opacity: 0.3 + (_controller.value * 0.4),
                child: Container(
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 16),
                      Container(width: 50, height: 50, decoration: const BoxDecoration(color: Color(0xFFF0F0F0), shape: BoxShape.circle)),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(width: 120, height: 12, decoration: BoxDecoration(color: const Color(0xFFF0F0F0), borderRadius: BorderRadius.circular(4))),
                            const SizedBox(height: 8),
                            Container(width: 200, height: 10, decoration: BoxDecoration(color: const Color(0xFFF0F0F0), borderRadius: BorderRadius.circular(4))),
                          ],
                        ),
                      )
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}