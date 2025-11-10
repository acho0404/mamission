import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ChatDetailPage extends StatefulWidget {
  final String chatId;
  const ChatDetailPage({super.key, required this.chatId});

  @override
  State<ChatDetailPage> createState() => _ChatDetailPageState();
}

class _ChatDetailPageState extends State<ChatDetailPage> {
  bool _keyboardVisible = false;
  bool _initialScrollDone = false;
  int _firstUnreadIndex = -1;
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final user = FirebaseAuth.instance.currentUser!;
  StreamSubscription? _msgSub;
  StreamSubscription? _chatSub;
  bool _isAutoScrolling = false;

  String? otherId;
  String? otherName;
  String? otherPhoto;
  bool _isTyping = false;
  bool _isOnline = false;
  DateTime? _lastSeen;
  bool _showNewBadge = false;


  @override
  void initState() {
    super.initState();
    _loadChatInfo();
    _listenChat();

    // ✅ Scroll direct tout en bas après rendu complet
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(const Duration(milliseconds: 250));
      if (!_scrollCtrl.hasClients) return;
      try {
        _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
      } catch (_) {}
    });

    // ✅ Listener pour marquer lu et retirer bannière
    _scrollCtrl.addListener(() {
      final maxScroll = _scrollCtrl.position.maxScrollExtent;
      final current = _scrollCtrl.position.pixels;
      if (current >= maxScroll - 100 && _firstUnreadIndex != -1) {
        setState(() => _firstUnreadIndex = -1);
        _markMessagesAsRead();
      }
    });
  }


  // 🔹 Marquer les messages comme lus
  Future<void> _markMessagesAsRead() async {
    final ref = FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.chatId)
        .collection('messages');

    final unread =
    await ref.where('from', isNotEqualTo: user.uid).get();

    for (var doc in unread.docs) {
      await doc.reference.update({
        'readBy': FieldValue.arrayUnion([user.uid]),
      });
    }

    await FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.chatId)
        .update({
      'readBy': FieldValue.arrayUnion([user.uid]),
    });
  }

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

    // 🔹 Lis le modèle actuel basé sur userNames / userPhotos
    final userNames = Map<String, dynamic>.from(data['userNames'] ?? {});
    final userPhotos = Map<String, dynamic>.from(data['userPhotos'] ?? {});

    setState(() {
      otherName = userNames[otherId] ?? 'Utilisateur';
      otherPhoto = userPhotos[otherId] ?? '';
    });

    // 🔹 Fallback si jamais Firestore n’a pas les infos (ancien chat)
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

      // ✅ On met à jour Firestore pour que ce soit persistant
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
        // 🔹 Si c’est le tout premier message → scroll direct sans badge
        if (snap.docs.length == 1) {
          _scrollToBottom(instant: true);
          setState(() => _showNewBadge = false);
        }
        // 🔹 Sinon comportement normal
        else if (atBottom || _keyboardVisible) {
          _scrollToBottom(instant: true);
          setState(() => _showNewBadge = false);
        } else {
          setState(() => _showNewBadge = true);
        }

        _markMessagesAsRead();
      }

      // ✅ ajoute cette ligne :
      _markMessagesAsRead(); // dès qu’un nouveau message arrive → le marquer comme lu
    });
  }

  String _statusText() {
    if (_isTyping) return "En train d’écrire...";
    if (_isOnline) return "En ligne";
    if (_lastSeen == null) return "Hors ligne";
    final diff = DateTime.now().difference(_lastSeen!);
    if (diff.inMinutes < 5) return "Connecté il y a quelques instants";
    if (diff.inHours < 1) return "Connecté il y a ${diff.inMinutes} min";
    if (diff.inHours < 24) {
      return "Connecté à ${_lastSeen!.hour.toString().padLeft(2, '0')}:${_lastSeen!.minute.toString().padLeft(2, '0')}";
    }
    if (diff.inDays == 1) {
      return "Connecté hier à ${_lastSeen!.hour.toString().padLeft(2, '0')}:${_lastSeen!.minute.toString().padLeft(2, '0')}";
    }
    return "Connecté le ${_lastSeen!.day}/${_lastSeen!.month}";
  }

  Future<void> _sendMessage() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;
    _msgCtrl.clear();

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

  }

  void _scrollToBottom({bool instant = false}) {
    if (!_scrollCtrl.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final offset = _scrollCtrl.position.maxScrollExtent + 50;
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    _keyboardVisible = viewInsets > 0;
    return Scaffold(
    backgroundColor: const Color(0xFFF8F6FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFF6C63FF),
        elevation: 2,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: [
            // --- PHOTO + POINT VERT ---
            Stack(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundImage: (otherPhoto != null && otherPhoto!.isNotEmpty)
                      ? NetworkImage(otherPhoto!)
                      : null,
                  backgroundColor: Colors.white24,
                  child: (otherPhoto == null || otherPhoto!.isEmpty)
                      ? const Icon(Icons.person, color: Colors.white)
                      : null,
                ),
                Positioned(
                  bottom: 2,
                  right: 2,
                  child: Container(
                    width: 11,
                    height: 11,
                    decoration: BoxDecoration(
                      color: _isOnline ? Colors.greenAccent : Colors.grey,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 10), // ✅ la virgule manquante était ici

            // --- NOM + STATUT ---
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  otherName ?? 'Utilisateur',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Text(
                    _statusText(),
                    key: ValueKey(_statusText()),
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),


      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('chats')
                  .doc(widget.chatId)
                  .collection('messages')
                  .orderBy('sentAt', descending: false)
                  .snapshots(),
              builder: (context, snap) {
                final docs = snap.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const Center(child: Text("Aucun message pour le moment 💬"));
                }

                // ✅ Détection du premier message non lu (à placer ici)



                if (snap.hasData && snap.data!.docChanges.isNotEmpty) {
                  final hasNew = snap.data!.docChanges
                      .any((c) => c.type == DocumentChangeType.added);
                }
                if (!_initialScrollDone && docs.isNotEmpty) {
                  _initialScrollDone = true;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (_scrollCtrl.hasClients) {
                      _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
                    }
                  });
                }

                return ListView.builder(
                  controller: _scrollCtrl,
                  padding:
                  const EdgeInsets.only(top: 10, bottom: 16),
                  itemCount: docs.length,
                  itemBuilder: (_, i) {
                    final data = docs[i].data();

                    bool showUnreadBanner = false;
                    if (_firstUnreadIndex != -1 && i == _firstUnreadIndex) {
                      showUnreadBanner = true;
                    }

                    return Column(
                      children: [
                        if (showUnreadBanner)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: const [
                                Expanded(child: Divider(color: Color(0xFF6C63FF), thickness: 1.2)),
                                SizedBox(width: 8),
                                Text(
                                  "Messages non lus",
                                  style: TextStyle(color: Color(0xFF6C63FF)),
                                ),
                                SizedBox(width: 8),
                                Expanded(child: Divider(color: Color(0xFF6C63FF), thickness: 1.2)),
                              ],
                            ),
                          ),
                        _buildBubble(data),
                      ],
                    );
                  },

                );
              },
            ),
          ),
          if (_showNewBadge)
            GestureDetector(
              onTap: () {
                setState(() => _showNewBadge = false);
                _scrollToBottom(instant: true); // ✅ ajoute instant scroll ici
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                    color: const Color(0xFF6C63FF),
                    borderRadius: BorderRadius.circular(50)),
                child: const Text("↓ Nouveau message",
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600)),
              ),
            ),
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
                      controller: _msgCtrl,
                      minLines: 1,
                      maxLines: 5,
                      onChanged: (v) => FirebaseFirestore.instance
                          .collection('chats')
                          .doc(widget.chatId)
                          .update(
                          {'typing.${user.uid}': v.isNotEmpty}),
                      decoration: const InputDecoration(
                        hintText: "Écrire un message...",
                        border: InputBorder.none,
                        contentPadding:
                        EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.send_rounded,
                        color: Color(0xFF6C63FF)),
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

  Widget _buildBubble(Map<String, dynamic> data) {
    final isMe = data['from'] == user.uid;
    final ts = (data['sentAt'] as Timestamp?)?.toDate();
    final time = ts != null
        ? "${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}"
        : '';
    final readBy = (data['readBy'] as List?) ?? [];
    final isSeen = otherId != null && readBy.contains(otherId);

    return Align(
      alignment:
      isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin:
        const EdgeInsets.symmetric(vertical: 4, horizontal: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isMe ? const Color(0xFF6C63FF) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
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
