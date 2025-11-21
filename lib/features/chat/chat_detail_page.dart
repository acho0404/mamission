import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // ✅ Ajouté pour les retours haptiques
import 'package:mamission/shared/apple_appbar.dart';

class ChatDetailPage extends StatefulWidget {
  final String chatId;
  const ChatDetailPage({super.key, required this.chatId});

  @override
  State<ChatDetailPage> createState() => _ChatDetailPageState();
}

class _ChatDetailPageState extends State<ChatDetailPage> {
  bool _keyboardVisible = false;
  // ✅✅✅ AJOUTEZ CES LIGNES ICI ✅✅✅
  bool _initialScrollDone = false;
  int _firstUnreadIndex = -1;
  final GlobalKey _firstUnreadKey = GlobalKey();
  // ✅✅✅ FIN DES LIGNES À AJOUTER ✅✅✅
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final user = FirebaseAuth.instance.currentUser!;
  StreamSubscription? _msgSub;
  StreamSubscription? _chatSub;

  String? otherId;
  String? otherName;
  String? otherPhoto;
  bool _isTyping = false;
  bool _isOnline = false;
  DateTime? _lastSeen;
  bool _showNewBadge = false;

  final _focusNode = FocusNode();

  // ✅ AMÉLIORATION 10/10 : Timer pour le "Typing" (Performance)
  Timer? _typingTimer;

  @override
  void initState() {
    super.initState();
    _loadChatInfo();
    _listenChat();

    _focusNode.addListener(_onFocusChange);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(const Duration(milliseconds: 250));
      if (!_scrollCtrl.hasClients) return;
      try {
        _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
        _initialScrollDone = true;
      } catch (_) {}
    });

    _scrollCtrl.addListener(() {
      final maxScroll = _scrollCtrl.position.maxScrollExtent;
      final current = _scrollCtrl.position.pixels;
      if (current >= maxScroll - 100) {
        if (_showNewBadge) setState(() => _showNewBadge = false);
        _markMessagesAsRead();
      }
    });
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus) {
      _scrollToBottom(instant: true);
    }
  }

  // =======================================================================
  // ✅ LA FONCTION 10/10 CORRIGÉE
  // =======================================================================
  Future<void> _markMessagesAsRead() async {
    // Sécurité : ne rien faire si l'ID de l'autre n'est pas encore chargé
    if (otherId == null) return;

    final ref = FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.chatId)
        .collection('messages');

    // 1. ✅ CORRECTION : Trouver tous les messages DE L'AUTRE
    // (On ne peut pas faire 'whereDoesNotContain', on filtre donc après)
    final messagesFromOther = await ref
        .where('from', isEqualTo: otherId)
        .get();

    // 2. ✅ CORRECTION : Filtrer en local (en Dart) pour trouver les non-lus
    final unreadDocs = messagesFromOther.docs.where((doc) {
      final data = doc.data();
      final readByList = (data['readBy'] as List?) ?? [];
      // Retourne VRAI si notre ID n'est PAS dans la liste
      return !readByList.contains(user.uid);
    }).toList();

    // S'il n'y a rien à marquer, on arrête.
    if (unreadDocs.isEmpty) return;

    // 3. Créer un "Batch" pour 1 SEULE écriture (10/10 performance)
    final batch = FirebaseFirestore.instance.batch();

    for (var doc in unreadDocs) {
      batch.update(doc.reference, {
        'readBy': FieldValue.arrayUnion([user.uid]),
      });
    }

    // 4. Mettre à jour le chat principal
    batch.update(
        FirebaseFirestore.instance.collection('chats').doc(widget.chatId), {
      'readBy': FieldValue.arrayUnion([user.uid]),
    });

    // 5. Exécuter le batch
    await batch.commit();
  }
  // =======================================================================

  Future<void> _loadChatInfo() async {
    final doc = await FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.chatId)
        .get();
    if (!doc.exists) return;
    final data = doc.data()!;
    final users = List<String>.from(data['users']);
    final currentUid = user.uid;
    otherId = users.firstWhere((id) => id != currentUid);
    final userNames = Map<String, dynamic>.from(data['userNames'] ?? {});
    final userPhotos = Map<String, dynamic>.from(data['userPhotos'] ?? {});
    setState(() {
      otherName = userNames[otherId] ?? 'Utilisateur';
      otherPhoto = userPhotos[otherId] ?? '';
    });
    if (otherName == 'Utilisateur' || otherPhoto!.isEmpty) {
      final userSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(otherId)
          .get();
      final udata = userSnap.data() ?? {};
      setState(() {
        otherName = udata['name'] ?? 'Utilisateur';
        otherPhoto = udata['photoUrl'] ?? '';
      });
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .update({
        'userNames.$otherId': otherName,
        'userPhotos.$otherId': otherPhoto,
      });
    }
    _listenUserPresence();
    _markMessagesAsRead();
  }


  void _listenUserPresence() {
    FirebaseFirestore.instance
        .collection('users')
        .doc(otherId)
        .snapshots()
        .listen((snap) {
      final d = snap.data();
      if (d == null) return;
      setState(() {
        _isOnline = d['isOnline'] == true;
        _lastSeen = (d['lastSeen'] as Timestamp?)?.toDate();
      });
    });
  }

  void _listenChat() {
    _chatSub = FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.chatId)
        .snapshots()
        .listen((snap) {
      final typing = (snap.data()?['typing'] ?? {}) as Map<String, dynamic>;
      setState(() => _isTyping = typing[otherId] == true);
    });

    _msgSub = FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.chatId)
        .collection('messages')
        .orderBy('sentAt', descending: false)
        .snapshots()
        .listen((snap) {
      if (!_scrollCtrl.hasClients) return;
      final atBottom = _scrollCtrl.position.pixels >=
          _scrollCtrl.position.maxScrollExtent - 120;

      if (snap.docChanges.any((c) => c.type == DocumentChangeType.added)) {

        if (snap.docs.length == 1) {
          _scrollToBottom(instant: true);
          setState(() => _showNewBadge = false);
        }
        else if (atBottom || _keyboardVisible) {
          _scrollToBottom(instant: true);
          setState(() => _showNewBadge = false);
          _markMessagesAsRead();
        }
        else {
          setState(() => _showNewBadge = true);
          HapticFeedback.mediumImpact();
        }
      }
    });
  }

  // ✅ LOGIQUE WHATSAPP : Amélioration du statut pour inclure les dates
  String _statusText() {
    if (_isTyping) return "En train d’écrire...";
    if (_isOnline) return "En ligne";
    if (_lastSeen == null) return "Hors ligne";

    final now = DateTime.now();
    final diff = now.difference(_lastSeen!);
    final lastSeenDate = _lastSeen!;

    final time = "${lastSeenDate.hour.toString().padLeft(2, '0')}:${lastSeenDate.minute.toString().padLeft(2, '0')}";

    if (diff.inMinutes < 5) return "Connecté il y a quelques instants";
    if (diff.inHours < 1) return "Connecté il y a ${diff.inMinutes} min";

    if (now.day == lastSeenDate.day && now.month == lastSeenDate.month && now.year == lastSeenDate.year) {
      return "Vu aujourd'hui à $time";
    }

    final yesterday = now.subtract(const Duration(days: 1));
    if (yesterday.day == lastSeenDate.day && yesterday.month == lastSeenDate.month && yesterday.year == lastSeenDate.year) {
      return "Vu hier à $time";
    }

    return "Vu le ${lastSeenDate.day}/${lastSeenDate.month}/${lastSeenDate.year} à $time";
  }


  Future<void> _sendMessage() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;
    _msgCtrl.clear();

    _typingTimer?.cancel();

    final ref = FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.chatId);

    await ref.collection('messages').add({
      'from': user.uid,
      'text': text,
      'sentAt': FieldValue.serverTimestamp(),
      'readBy': [user.uid],
    });

    await ref.update({
      'lastMessage': text,
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastMessageFrom': user.uid,
      'typing.${user.uid}': false,
      'readBy': [user.uid]
    });

    HapticFeedback.lightImpact();
  }

  // ✅ AMÉLIORATION 10/10 : Logique "Typing" efficace (debounce)
  void _updateTypingStatus(String text) {
    if (text.isEmpty) {
      _typingTimer?.cancel();
      FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .update({'typing.${user.uid}': false});
      return;
    }

    if (_typingTimer == null || !_typingTimer!.isActive) {
      FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .update({'typing.${user.uid}': true});
    }

    _typingTimer?.cancel();

    _typingTimer = Timer(const Duration(seconds: 3), () {
      FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .update({'typing.${user.uid}': false});
    });
  }


  void _scrollToBottom({bool instant = false}) {
    if (!_scrollCtrl.hasClients || !_initialScrollDone) return;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!_scrollCtrl.hasClients) return;
      final offset = _scrollCtrl.position.maxScrollExtent;
      if (instant) {
        _scrollCtrl.jumpTo(offset);
      } else {
        await _scrollCtrl.animateTo(
          offset,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }



  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    _msgSub?.cancel();
    _chatSub?.cancel();
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _typingTimer?.cancel(); // ✅ Nettoyer le timer
    super.dispose();
  }

  // --- Fonctions Helper pour les dates (LOGIQUE WHATSAPP) ---
  bool _isSameDay(Timestamp? ts1, Timestamp? ts2) {
    if (ts1 == null || ts2 == null) return false;
    final date1 = ts1.toDate();
    final date2 = ts2.toDate();
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }

  String _formatDateHeader(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final messageDate = DateTime(date.year, date.month, date.day);

    if (messageDate == today) {
      return "AUJOURD'HUI";
    } else if (messageDate == yesterday) {
      return "HIER";
    } else if (now.difference(messageDate).inDays < 7) {
      const days = ['LUNDI', 'MARDI', 'MERCREDI', 'JEUDI', 'VENDREDI', 'SAMEDI', 'DIMANCHE'];
      return days[messageDate.weekday - 1];
    } else {
      return "${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}";
    }
  }

  Widget _buildDateHeader(DateTime date) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 16),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFE1E7F0),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          _formatDateHeader(date),
          style: const TextStyle(
            color: Color(0xFF5A7394),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildUnreadBanner() {
    return Container(
      key: _firstUnreadKey, // La clé pour scroller ici
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          const Expanded(child: Divider(color: Color(0xFF6C63FF))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              "Messages non lus",
              style: const TextStyle(
                color: Color(0xFF6C63FF),
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
          const Expanded(child: Divider(color: Color(0xFF6C63FF))),
        ],
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    _keyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F6FF),
      appBar: buildAppleMissionAppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        centerWidget: Row(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundImage: (otherPhoto != null && otherPhoto!.isNotEmpty)
                      ? NetworkImage(otherPhoto!)
                      : null,
                  backgroundColor: Colors.white24,
                  child: (otherPhoto == null || otherPhoto!.isEmpty)
                      ? const Icon(Icons.person, color: Colors.white)
                      : null,
                ),
                Positioned(
                  bottom: 1,
                  right: 1,
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: _isOnline ? Colors.greenAccent : Colors.grey,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  otherName ?? "",
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                Text(
                  _statusText(), // ✅ Statut 10/10
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // -------------------------------------------------------------
          // 🔥 LISTE DES MESSAGES (Logique de scroll 10/10)
          // -------------------------------------------------------------
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('chats')
                  .doc(widget.chatId)
                  .collection('messages')
                  .orderBy('sentAt', descending: false)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting && !_initialScrollDone) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snap.hasData || snap.data!.docs.isEmpty) {
                  return const Center(child: Text("Aucun message pour le moment 💬"));
                }
                final docs = snap.data!.docs;

                // ✅ LOGIQUE WHATSAPP : Scroll au bon endroit
                if (!_initialScrollDone) {
                  _firstUnreadIndex = docs.indexWhere(
                          (d) {
                        final data = d.data();
                        final readByList = (data['readBy'] as List?) ?? [];
                        return data['from'] != user.uid && !readByList.contains(user.uid);
                      }
                  );

                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!_scrollCtrl.hasClients) return;

                    if (_firstUnreadIndex != -1 && _firstUnreadKey.currentContext != null) {
                      Scrollable.ensureVisible(
                        _firstUnreadKey.currentContext!,
                        duration: const Duration(milliseconds: 100),
                        curve: Curves.easeIn,
                        alignment: 0.1,
                      );
                    }
                    else {
                      _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
                    }
                    _initialScrollDone = true;
                  });
                }

                return ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.only(top: 10, bottom: 16),
                  itemCount: docs.length,
                  itemBuilder: (_, i) {
                    final data = docs[i].data();

                    final String currentSender = data['from'];
                    final Timestamp? currentTime = data['sentAt'] as Timestamp?;

                    final String? prevSender = i > 0 ? docs[i - 1].data()['from'] : null;
                    final Timestamp? prevTime = i > 0 ? (docs[i - 1].data()['sentAt'] as Timestamp?) : null;

                    final bool isSameSenderAsPrevious = currentSender == prevSender;

                    Widget? dateHeader;
                    if (currentTime != null && !_isSameDay(currentTime, prevTime)) {
                      dateHeader = _buildDateHeader(currentTime.toDate());
                    }

                    return Column(
                      children: [
                        if (dateHeader != null) dateHeader,
                        if (i == _firstUnreadIndex) _buildUnreadBanner(),
                        _buildBubble(
                          data,
                          isSameSenderAsPrevious,
                          key: (i == _firstUnreadIndex) ? _firstUnreadKey : null,
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),

          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (child, animation) {
              return ScaleTransition(scale: animation, child: child);
            },
            child: _showNewBadge
                ? GestureDetector(
              key: const ValueKey('new-badge'),
              onTap: () {
                setState(() => _showNewBadge = false);
                _scrollToBottom(instant: true);
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF6C63FF),
                  borderRadius: BorderRadius.circular(50),
                ),
                child: const Text(
                  "↓ Nouveau message",
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ),
            )
                : const SizedBox.shrink(key: ValueKey('no-badge')),
          ),

          // -------------------------------------------------------------
          // 🔥 INPUT MESSAGE (Avec performance "Typing")
          // -------------------------------------------------------------
          SafeArea(
            child: Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(40),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.07),
                      blurRadius: 8,
                      offset: const Offset(0, 3))
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      focusNode: _focusNode,
                      controller: _msgCtrl,
                      minLines: 1,
                      maxLines: 5,
                      // ✅ AMÉLIORATION 10/10 : Utilise la fonction de "debounce"
                      onChanged: _updateTypingStatus,
                      decoration: const InputDecoration(
                        hintText: "Écrire un message...",
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.send_rounded, color: Color(0xFF6C63FF)),
                    onPressed: _sendMessage,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- "Estiquer" les bulles (Inchangé) ---
  Widget _buildBubble(Map<String, dynamic> data, bool isSameSenderAsPrevious, {Key? key}) {
    final isMe = data['from'] == user.uid;
    final ts = (data['sentAt'] as Timestamp?)?.toDate();
    final time = ts != null
        ? "${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}"
        : '';
    final readBy = (data['readBy'] as List?) ?? [];
    final isSeen = otherId != null && readBy.contains(otherId);

    final radius = const Radius.circular(18);
    final smallRadius = const Radius.circular(5);

    final BorderRadius bubbleRadius = isMe
        ? BorderRadius.only(
      topLeft: radius,
      bottomLeft: radius,
      topRight: radius,
      bottomRight: isSameSenderAsPrevious ? smallRadius : radius,
    )
        : BorderRadius.only(
      topRight: radius,
      bottomRight: radius,
      topLeft: radius,
      bottomLeft: isSameSenderAsPrevious ? smallRadius : radius,
    );

    final double verticalMargin = isSameSenderAsPrevious ? 2 : 8;

    return Align(
      key: key,
      alignment:
      isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin:
        EdgeInsets.symmetric(vertical: verticalMargin, horizontal: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isMe ? const Color(0xFF6C63FF) : Colors.white,
          borderRadius: bubbleRadius,
          boxShadow: [
            if (!isSameSenderAsPrevious)
              BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 6,
                  offset: const Offset(2, 3))
          ],
        ),
        child: Column(
          crossAxisAlignment: isMe
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Text(data['text'] ?? '',
                style: TextStyle(
                    color:
                    isMe ? Colors.white : Colors.black87,
                    fontSize: 15)),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(time,
                    style: TextStyle(
                        color: isMe
                            ? Colors.white70
                            : Colors.black45,
                        fontSize: 10)),
                if (isMe) ...[
                  const SizedBox(width: 6),
                  Icon(
                    isSeen ? Icons.done_all : Icons.done,
                    size: 16,
                    color: isSeen
                        ? Colors.lightBlueAccent
                        : Colors.white70,
                  ),
                ]
              ],
            ),
          ],
        ),
      ),
    );
  }
}