import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'chat_detail_page.dart';

class ThreadsPage extends StatelessWidget {
  const ThreadsPage({super.key});

  /// 🔹 Stream des conversations
  Stream<QuerySnapshot<Map<String, dynamic>>> _threadsStream(String uid) {
    return FirebaseFirestore.instance
        .collection('chats')
        .where('users', arrayContains: uid)
        .orderBy('lastMessageAt', descending: true)
        .snapshots();
  }

  /// 🔹 Stream du statut utilisateur en direct
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

  /// 🔹 Complète les métadonnées manquantes
  Future<void> _ensureChatMetadata(
      DocumentReference<Map<String, dynamic>> chatRef,
      Map<String, dynamic> chat) async {
    final List users = List<String>.from(chat['users'] ?? const []);
    if (users.length != 2) return;

    final needNames = chat['userNames'] is! Map;
    final needPhotos = chat['userPhotos'] is! Map;
    if (!needNames && !needPhotos) return;

    final Map<String, dynamic> userNames =
    Map<String, dynamic>.from(chat['userNames'] ?? {});
    final Map<String, dynamic> userPhotos =
    Map<String, dynamic>.from(chat['userPhotos'] ?? {});
    final batch = FirebaseFirestore.instance.batch();

    for (final uid in users) {
      final snap =
      await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final data = snap.data() ?? {};
      if (needNames) userNames[uid] = (data['name'] ?? 'Utilisateur').toString();
      if (needPhotos) userPhotos[uid] = (data['photoUrl'] ?? '').toString();
    }

    batch.set(chatRef, {
      if (needNames) 'userNames': userNames,
      if (needPhotos) 'userPhotos': userPhotos,
    }, SetOptions(merge: true));
    await batch.commit();
  }

  @override
  Widget build(BuildContext context) {
    final me = FirebaseAuth.instance.currentUser!;
    return Scaffold(
      backgroundColor: const Color(0xFFF8F6FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFF6C63FF),
        elevation: 2,
        centerTitle: true,
        title: const Text(
          "Messages",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _threadsStream(me.uid),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: Color(0xFF6C63FF)));
          }

          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(
              child: Text(
                "Aucune conversation pour le moment 💬",
                style: TextStyle(color: Colors.black54),
              ),
            );
          }

          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 4),
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemBuilder: (context, i) {
              final doc = docs[i];
              final chat = doc.data();
              final chatRef = doc.reference;
              _ensureChatMetadata(chatRef, chat);

              final List users = List<String>.from(chat['users'] ?? const []);
              final otherId =
              users.firstWhere((id) => id != me.uid, orElse: () => '');
              if (otherId.isEmpty) return const SizedBox.shrink();

              final Map names =
              Map<String, dynamic>.from(chat['userNames'] ?? {});
              final Map photos =
              Map<String, dynamic>.from(chat['userPhotos'] ?? {});
              final String name = (names[otherId] ?? 'Utilisateur').toString();
              final String photo = (photos[otherId] ?? '').toString();

              final String lastMsg = (chat['lastMessage'] ?? '').toString();
              final String lastFrom = (chat['lastMessageFrom'] ?? '').toString();
              final Timestamp? ts = chat['lastMessageAt'] as Timestamp?;
              final String time = ts != null ? _formatTime(ts.toDate()) : '';

              final preview = lastMsg.isEmpty
                  ? "(Aucun message)"
                  : (lastFrom == me.uid ? "Vous : $lastMsg" : lastMsg);

              final List readBy = (chat['readBy'] ?? []) as List;
              final bool isUnread = !readBy.contains(me.uid);

              // 🔹 Widget principal : écoute du statut utilisateur
              return StreamBuilder<Map<String, dynamic>>(
                stream: _userPresence(otherId),
                builder: (context, statusSnap) {
                  final presence = statusSnap.data ?? {};
                  final bool isOnline = presence['isOnline'] ?? false;
                  final DateTime? lastSeen = presence['lastSeen'];
                  final String statusText = _statusText(isOnline, lastSeen);

                  return InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChatDetailPage(chatId: doc.id),
                        ),
                      );
                    },
                    child: Container(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 5),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          // avatar + point vert
                          Stack(
                            children: [
                              CircleAvatar(
                                radius: 28,
                                backgroundImage:
                                photo.isNotEmpty ? NetworkImage(photo) : null,
                                backgroundColor: Colors.grey.shade200,
                                child: photo.isEmpty
                                    ? const Icon(Icons.person,
                                    color: Colors.grey, size: 26)
                                    : null,
                              ),
                              Positioned(
                                right: 2,
                                bottom: 2,
                                child: Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: isOnline
                                        ? Colors.green
                                        : Colors.grey,
                                    border: Border.all(
                                        color: Colors.white, width: 1.5),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(width: 12),
                          // infos
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 15.5,
                                          color: Color(0xFF1C1C1E),
                                        ),
                                      ),
                                    ),
                                    Text(
                                      time,
                                      style: const TextStyle(
                                        color: Color(0xFF9E9E9E),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),

                                const SizedBox(height: 3),


// 🔹 Dernier message
                                Text(
                                  preview,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: const Color(0xFF5E5E6D),
                                    fontSize: 13,
                                    fontWeight: isUnread ? FontWeight.w600 : FontWeight.normal,
                                  ),
                                ),

                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (isUnread)
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: const BoxDecoration(
                                color: Color(0xFF6C63FF),
                                shape: BoxShape.circle,
                              ),
                              child: const SizedBox(width: 8, height: 8),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  /// 🔹 Format heure JJ/MM ou HH:mm
  static String _formatTime(DateTime date) {
    final now = DateTime.now();
    if (now.difference(date).inDays == 0) {
      return "${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}";
    }
    return "${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}";
  }

  /// 🔹 Format texte de statut
  static String _statusText(bool isOnline, DateTime? lastSeen) {
    if (isOnline) return "En ligne";
    if (lastSeen == null) return "Hors ligne";
    final diff = DateTime.now().difference(lastSeen);
    if (diff.inMinutes < 5) return "Vu récemment";
    if (diff.inHours < 1) return "Vu il y a ${diff.inMinutes} min";
    if (diff.inHours < 24) {
      return "Vu à ${lastSeen.hour.toString().padLeft(2, '0')}:${lastSeen.minute.toString().padLeft(2, '0')}";
    }
    return "Vu le ${lastSeen.day}/${lastSeen.month}";
  }
}
