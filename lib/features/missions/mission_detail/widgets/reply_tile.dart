import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mamission/core/formatters.dart'; // Import

// Renommé de _ReplyTile à ReplyTile
class ReplyTile extends StatefulWidget {
  final Map<String, dynamic> data;
  const ReplyTile({super.key, required this.data}); // Clé ajoutée

  @override
  State<ReplyTile> createState() => _ReplyTileState();
}

class _ReplyTileState extends State<ReplyTile> {
  Map<String, dynamic>? user;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  // Va chercher les infos (nom, etc.) de l'utilisateur qui a répondu
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
    final date = formatTimeAgo(timestamp); // Utilise le temps écoulé
    final userId = data['userId'] ?? '';

    // Utilise les données 'user' si chargées, sinon fallback
    final name = user?['name'] ?? data['userName'] ?? 'Utilisateur';
    final formattedName = formatUserName(name); // Nom formaté

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
                        formattedName, // Affiche le nom de celui qui répond
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                    ),
                    Text(
                      date, // Affiche le temps écoulé
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