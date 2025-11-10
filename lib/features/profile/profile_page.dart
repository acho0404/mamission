import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage>
    with SingleTickerProviderStateMixin {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;
  final _nameCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();

  bool _saving = false;
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _slideAnim = Tween(begin: const Offset(0, 0.05), end: Offset.zero)
        .animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic));
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _bioCtrl.dispose();
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _logout() async {
    await _auth.signOut();
    if (mounted) context.go('/login');
  }

  Future<void> _pickAndUploadPhoto(String uid) async {
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (picked == null) return;
      setState(() => _saving = true);
      final file = File(picked.path);
      final ref = FirebaseStorage.instance.ref('users/$uid/profile.jpg');
      await ref.putFile(file);
      final url = await ref.getDownloadURL();
      await _db.collection('users').doc(uid).update({'photoUrl': url});
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveProfile(String uid) async {
    setState(() => _saving = true);
    await _db.collection('users').doc(uid).set({
      if (_nameCtrl.text.trim().isNotEmpty) 'name': _nameCtrl.text.trim(),
      'bio': _bioCtrl.text.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profil mis à jour ✅')));
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _openEditSheet(Map<String, dynamic> userData, String uid) async {
    _nameCtrl.text = (userData['name'] ?? '').toString();
    _bioCtrl.text = (userData['bio'] ?? '').toString();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          top: 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            const SizedBox(height: 16),
            Text('Modifier le profil',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 14),
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Nom complet',
                prefixIcon: Icon(Icons.person_outline),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bioCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Bio',
                prefixIcon: Icon(Icons.info_outline),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _saving ? null : () => _pickAndUploadPhoto(uid),
                    icon: const Icon(Icons.photo_camera_back_outlined),
                    label: const Text('Changer la photo'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _saving ? null : () => _saveProfile(uid),
                    icon: _saving
                        ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                        : const Icon(Icons.save_outlined),
                    label: const Text('Enregistrer'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<int> _countMissions(String uid, String field) async {
    try {
      final agg = await _db
          .collection('missions')
          .where('posterId', isEqualTo: uid)
          .where('status', isEqualTo: field)
          .count()
          .get();
      return agg.count ?? 0;
    } catch (e) {
      final snap = await _db
          .collection('missions')
          .where('posterId', isEqualTo: uid)
          .where('status', isEqualTo: field)
          .get();
      return snap.size;
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;
    final violet = const Color(0xFF6C63FF);

    if (user == null) {
      return const Scaffold(body: Center(child: Text('Non connecté')));
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF7F5FF),
      appBar: AppBar(
        backgroundColor: violet,
        centerTitle: true,
        elevation: 0,
        title: const Text('Mon profil',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _db.collection('users').doc(user.uid).snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snap.data!.data() ?? {};
          final name = (data['name'] ?? 'Utilisateur').toString();
          final verified = data['verified'] == true;
          final city = data['city'] ?? 'France';
          final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
          final joined = createdAt != null
              ? 'Membre depuis ${DateFormat.MMMM('fr_FR').format(createdAt)} ${createdAt.year}'
              : '';
          final photoUrl = (data['photoUrl'] ?? '').toString();
          final rating = (data['rating'] ?? 0).toDouble();
          final reviews = (data['reviewsCount'] ?? 0) as int? ?? 0;
          final bio = (data['bio'] ?? '').toString();

          return RefreshIndicator(
            onRefresh: () async => setState(() {}),
            child: FadeTransition(
              opacity: _fadeAnim,
              child: SlideTransition(
                position: _slideAnim,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Hero(
                        tag: 'profile-photo',
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                            boxShadow: [
                              BoxShadow(
                                color: violet.withOpacity(0.3),
                                blurRadius: 12,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: CircleAvatar(
                            radius: 55,
                            backgroundColor: violet.withOpacity(0.1),
                            backgroundImage: photoUrl.isNotEmpty
                                ? NetworkImage(photoUrl)
                                : null,
                            child: photoUrl.isEmpty
                                ? const Icon(Icons.person,
                                size: 60, color: Colors.grey)
                                : null,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(name,
                              style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87)),
                          if (verified) ...[
                            const SizedBox(width: 6),
                            Icon(Icons.verified,
                                color: Colors.blue.shade600, size: 20),
                          ]
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text('$joined – $city',
                          style: TextStyle(
                              color: Colors.grey.shade700, fontSize: 13)),
                      const SizedBox(height: 6),
                      GestureDetector(
                        onTap: () => context.push('/reviews/${user.uid}'),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.star_rounded, color: Colors.amber, size: 18),
                            const SizedBox(width: 4),
                            Text(
                              rating.toStringAsFixed(1),
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: Colors.black87),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '($reviews avis)',
                              style: const TextStyle(
                                color: Colors.deepPurple,
                                decoration: TextDecoration.underline,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      _actionTile(Icons.person_outline, 'Modifier mon profil',
                              () => _openEditSheet(data, user.uid), violet),
                      _actionTile(Icons.assignment, 'Mes missions publiées',
                              () => context.push('/missions/published'), violet),
                      _actionTile(Icons.history, 'Historique des missions',
                              () => context.push('/missions/history'), violet),
                      _actionTile(Icons.settings, 'Paramètres',
                              () => context.push('/settings'), violet),
                      _actionTile(Icons.logout, 'Se déconnecter', _logout,
                          Colors.redAccent),
                      const SizedBox(height: 30),

                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text('À propos de moi',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black12,
                                blurRadius: 6,
                                offset: const Offset(0, 2))
                          ],
                        ),
                        child: Text(
                          bio.isEmpty
                              ? "Je suis disponible pour aider sur vos missions locales et à distance."
                              : bio,
                          style: const TextStyle(
                              fontSize: 14, color: Colors.black87, height: 1.4),
                        ),
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _actionTile(
      IconData icon, String title, VoidCallback onTap, Color color) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
