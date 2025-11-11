import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

// ✅ NOUVEAU: Définissez votre liste de compétences ici
// Idéalement, elle devrait venir de Firebase, mais commençons comme ça.
const List<String> kAllSkills = [
  'Plomberie',
  'Électricité',
  'Jardinage',
  'Ménage',
  'Déménagement',
  'Peinture',
  'Montage de meubles',
  'Réparation smartphone',
  'Design graphique',
  'Développement Web',
  'Cours de maths',
  'Baby-sitting',
  'Pet-sitting',
  'Chauffagiste',
  'Climatisation',
];

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
  final _cityCtrl = TextEditingController();
  // ❌ _skillsCtrl n'est plus nécessaire, nous gérons une List<String>
  // final _skillsCtrl = TextEditingController();

  bool _saving = false;
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  late Future<Map<String, int>> _profileStats;

  @override
  void initState() {
    super.initState();
    initializeDateFormatting('fr_FR');

    if (_auth.currentUser != null) {
      _profileStats = _getProfileStats(_auth.currentUser!.uid);
    } else {
      _profileStats = Future.value({'posted': 0, 'completed': 0});
    }

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
    _cityCtrl.dispose();
    // ❌ _skillsCtrl.dispose();
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _logout() async {
    await _auth.signOut();
    if (mounted) context.go('/login');
  }

  Future<void> _pickAndUploadPhoto(String uid) async {
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 70);
      if (picked == null) return;
      setState(() => _saving = true);
      final file = File(picked.path);
      final ref = FirebaseStorage.instance.ref('users/$uid/profile.jpg');
      await ref.putFile(file);
      final url = await ref.getDownloadURL();

      await _db.collection('users').doc(uid).update({'photoUrl': url});
      await _auth.currentUser?.updatePhotoURL(url);

    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ✅ Fonction de sauvegarde MISE À JOUR
  // Elle prend maintenant la liste des compétences directement
  Future<void> _saveProfile(String uid, List<String> skillsList) async {
    setState(() => _saving = true);

    final newName = _nameCtrl.text.trim();
    if (newName.isNotEmpty && newName != _auth.currentUser?.displayName) {
      await _auth.currentUser?.updateDisplayName(newName);
    }

    await _db.collection('users').doc(uid).set({
      'name': newName,
      'bio': _bioCtrl.text.trim(),
      'city': _cityCtrl.text.trim(),
      'skills': skillsList, // ✅ Sauvegarde la liste propre
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profil mis à jour ✅')));
    }
    if (mounted) setState(() => _saving = false);
  }

  // ✅ Modal de modification TRÈS MODIFIÉ
  Future<void> _openEditSheet(Map<String, dynamic> userData, String uid) async {
    _nameCtrl.text = (userData['name'] ?? '').toString();
    _bioCtrl.text = (userData['bio'] ?? '').toString();
    _cityCtrl.text = (userData['city'] ?? '').toString();

    // Gère l'état des compétences DANS le modal
    List<String> selectedSkills = (userData['skills'] as List?)?.cast<String>() ?? [];
    // Contrôleur pour le champ Autocomplete
    final skillsTextCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      // ✅ StatefulBuilder est crucial pour gérer l'état des chips
      builder: (ctx) => StatefulBuilder(
        builder: (sheetContext, sheetSetState) {
          return Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              top: 16,
            ),
            child: SingleChildScrollView( // Ajout d'un SingleChildScrollView
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: Text('Modifier le profil',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nom complet',
                      prefixIcon: Icon(Icons.person_outline),
                      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _cityCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Ville',
                      prefixIcon: Icon(Icons.location_on_outlined),
                      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _bioCtrl,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Bio (À propos de moi)',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // --- ✅ NOUVEAU BLOC COMPÉTENCES ---
                  const Text('Compétences', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),

                  // 1. Les "Chips" (style Tinder)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade400)
                    ),
                    child: Wrap(
                      spacing: 8.0,
                      runSpacing: 4.0,
                      children: [
                        ...selectedSkills.map((skill) {
                          return Chip(
                            label: Text(skill),
                            backgroundColor: const Color(0xFFF7F5FF),
                            labelStyle: const TextStyle(color: Color(0xFF6C63FF), fontWeight: FontWeight.w600),
                            side: const BorderSide(color: Color(0xFF6C63FF)),
                            onDeleted: () {
                              sheetSetState(() { // Met à jour l'état du modal
                                selectedSkills.remove(skill);
                              });
                            },
                          );
                        }).toList(),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  // 2. Le champ de saisie avec suggestions
                  Autocomplete<String>(
                    optionsBuilder: (TextEditingValue textEditingValue) {
                      if (textEditingValue.text.isEmpty) {
                        return const Iterable<String>.empty();
                      }
                      // Filtre les suggestions :
                      // - celles qui correspondent à la frappe
                      // - ET qui ne sont pas déjà sélectionnées
                      return kAllSkills.where((String option) {
                        return option.toLowerCase().contains(textEditingValue.text.toLowerCase()) &&
                            !selectedSkills.contains(option);
                      });
                    },

                    // Quand l'utilisateur choisit une suggestion
                    onSelected: (String selection) {
                      sheetSetState(() {
                        selectedSkills.add(selection); // Ajoute au chip
                      });
                      skillsTextCtrl.clear(); // Vide le champ de texte
                    },

                    // Construit le champ de texte
                    fieldViewBuilder: (BuildContext context, TextEditingController fieldController,
                        FocusNode fieldFocusNode, VoidCallback onFieldSubmitted) {
                      // On assigne notre contrôleur externe pour pouvoir le vider
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        fieldController.text = skillsTextCtrl.text;
                      });

                      return TextField(
                        controller: fieldController,
                        focusNode: fieldFocusNode,
                        decoration: const InputDecoration(
                          hintText: 'Ajouter une compétence...',
                          prefixIcon: Icon(Icons.add),
                          border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                        ),
                        onSubmitted: (value) {
                          // Optionnel: ajoute la compétence même si non suggérée
                          if(value.trim().isNotEmpty && !selectedSkills.contains(value.trim())) {
                            sheetSetState(() {
                              selectedSkills.add(value.trim());
                            });
                          }
                          fieldController.clear();
                          skillsTextCtrl.clear();
                        },
                      );
                    },
                  ),
                  // --- FIN BLOC COMPÉTENCES ---

                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _saving ? null : () => _pickAndUploadPhoto(uid),
                          icon: const Icon(Icons.photo_camera_back_outlined),
                          label: const Text('Changer la photo'),
                          style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.icon(
                          // ✅ Envoie la liste à jour
                          onPressed: _saving ? null : () => _saveProfile(uid, selectedSkills),
                          icon: _saving
                              ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                              : const Icon(Icons.save_outlined),
                          label: const Text('Enregistrer'),
                          style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
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
      ),
    );
  }

  // ... (TOUT LE RESTE DE VOTRE CODE EST INCHANGÉ) ...
  // ... (_getProfileStats, build, _buildHeaderSection, _buildStatsBlock, etc.)

  // ✅ NOUVELLE fonction optimisée pour les stats
  Future<Map<String, int>> _getProfileStats(String uid) async {
    // Exécute 2 requêtes d'agrégation en parallèle
    final postedFuture = _db
        .collection('missions')
        .where('posterId', isEqualTo: uid)
        .count()
        .get();

    final completedFuture = _db
        .collection('missions')
        .where('posterId', isEqualTo: uid)
        .where('status', isEqualTo: 'completed') // ou 'done'
        .count()
        .get();

    try {
      final results = await Future.wait([postedFuture, completedFuture]);
      return {
        'posted': results[0].count ?? 0,
        'completed': results[1].count ?? 0,
      };
    } catch (e) {
      // Fallback si .count() n'est pas supporté (vieux SDK, etc.)
      final postedSnap = await _db
          .collection('missions')
          .where('posterId', isEqualTo: uid)
          .get();
      final completedSnap = await _db
          .collection('missions')
          .where('posterId', isEqualTo: uid)
          .where('status', isEqualTo: 'completed')
          .get();
      return {
        'posted': postedSnap.size,
        'completed': completedSnap.size,
      };
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
      backgroundColor: const Color(0xFFF7F5FF), // Fond d'écran
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
          final idVerified = data['idVerified'] == true; // ✅ Nouveau
          final phoneVerified = data['phoneVerified'] == true; // ✅ Nouveau
          final city = data['city'] ?? 'France';
          final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
          final joined = createdAt != null
              ? 'Membre depuis ${DateFormat.MMMM('fr_FR').format(createdAt)} ${createdAt.year}'
              : '';
          final photoUrl = (data['photoUrl'] ?? '').toString();
          final rating = (data['rating'] ?? 0).toDouble();
          final reviews = (data['reviewsCount'] ?? 0) as int? ?? 0;
          final bio = (data['bio'] ?? '').toString();
          final skills = (data['skills'] as List?)?.cast<String>() ?? [];

          return RefreshIndicator(
            onRefresh: () async {
              // Rafraîchit les stats lors du pull-to-refresh
              setState(() {
                _profileStats = _getProfileStats(user.uid);
              });
            },
            child: FadeTransition(
              opacity: _fadeAnim,
              child: SlideTransition(
                position: _slideAnim,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Column(
                    children: [
                      // --- 1. BLOC HEADER (Infos utilisateur) ---
                      _buildHeaderSection(context, photoUrl, name, verified, joined, city, rating, reviews, user.uid, violet),

                      const SizedBox(height: 24),

                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // --- 2. BLOC STATISTIQUES ---
                            _buildStatsBlock(context, _profileStats),

                            const SizedBox(height: 24),

                            // --- 3. BLOC ACTIONS ---
                            _buildSectionTitle(context, 'Tableau de bord'),
                            _actionTile(Icons.person_outline, 'Modifier mon profil',
                                    () => _openEditSheet(data, user.uid), violet),
                            _actionTile(Icons.assignment, 'Mes missions publiées',
                                    () => context.push('/missions/published'), violet),
                            _actionTile(Icons.history, 'Historique des missions',
                                    () => context.push('/missions/history'), violet),
                            _actionTile(Icons.settings, 'Paramètres',
                                    () => context.push('/settings'), violet),

                            const SizedBox(height: 24),

                            // --- 4. BLOC À PROPOS (BIO) ---
                            _buildSectionTitle(context, 'À propos de moi'),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Text(
                                bio.isEmpty
                                    ? "Modifiez votre profil pour ajouter une bio."
                                    : bio,
                                style: TextStyle(
                                    fontSize: 14, color: bio.isEmpty ? Colors.grey.shade600 : Colors.black87, height: 1.5),
                              ),
                            ),

                            const SizedBox(height: 24),

                            // --- 5. BLOC COMPÉTENCES ---
                            _buildSkillsSection(context, skills),

                            const SizedBox(height: 24),

                            // --- 6. BLOC VÉRIFICATIONS ---
                            _buildVerificationSection(context, user.emailVerified, phoneVerified, idVerified),

                            const SizedBox(height: 24),

                            // --- 7. DÉCONNEXION ---
                            _actionTile(Icons.logout, 'Se déconnecter', _logout, Colors.redAccent, isLast: true),

                            const SizedBox(height: 40),
                          ],
                        ),
                      ),
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

  // =========================================================================
  // =========================================================================
  //
  //    WIDGETS HELPER (INCHANGÉS)
  //
  // =========================================================================
  // =========================================================================

  /// --- 1. LE HEADER ---
  Widget _buildHeaderSection(
      BuildContext context,
      String photoUrl,
      String name,
      bool verified,
      String joined,
      String city,
      double rating,
      int reviews,
      String uid,
      Color violet,
      ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(30)),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 5),
          )
        ],
      ),
      child: Column(
        children: [
          Hero(
            tag: 'profile-photo-$uid',
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: violet.withOpacity(0.5), width: 2),
                boxShadow: [
                  BoxShadow(
                    color: violet.withOpacity(0.2),
                    blurRadius: 12,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: CircleAvatar(
                radius: 55,
                backgroundColor: violet.withOpacity(0.1),
                backgroundImage:
                photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
                child: photoUrl.isEmpty
                    ? const Icon(Icons.person, size: 60, color: Colors.grey)
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
                Icon(Icons.verified, color: Colors.blue.shade600, size: 20),
              ]
            ],
          ),
          const SizedBox(height: 6),
          Text('$joined – $city',
              style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () => context.push('/reviews/$uid'),
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
        ],
      ),
    );
  }

  /// --- 2. LE BLOC STATS ---
  Widget _buildStatsBlock(BuildContext context, Future<Map<String, int>> statsFuture) {
    return FutureBuilder<Map<String, int>>(
      future: statsFuture,
      builder: (context, snapshot) {
        Widget content;
        if (snapshot.connectionState == ConnectionState.waiting) {
          content = const Center(child: SizedBox(height: 48, child: CircularProgressIndicator(strokeWidth: 2)));
        } else if (snapshot.hasError) {
          content = const Center(child: Text('Erreur stats'));
        } else {
          final stats = snapshot.data ?? {'posted': 0, 'completed': 0};
          content = Row(
            children: [
              _buildStatItem(context, stats['posted'].toString(), 'Missions publiées'),
              Container(width: 1, height: 30, color: Colors.grey.shade300, margin: const EdgeInsets.symmetric(horizontal: 16)),
              _buildStatItem(context, stats['completed'].toString(), 'Missions complétées'),
            ],
          );
        }

        return Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
          ),
          child: content,
        );
      },
    );
  }

  Widget _buildStatItem(BuildContext context, String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF6C63FF),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: Colors.black54,
            ),
          ),
        ],
      ),
    );
  }

  /// --- 3. LE BLOC COMPÉTENCES ---
  Widget _buildSkillsSection(BuildContext context, List<String> skills) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(context, 'Compétences'),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
          ),
          child: skills.isEmpty
              ? Text(
            "Ajoutez vos compétences dans \"Modifier mon profil\" pour inspirer confiance.",
            style: TextStyle(color: Colors.grey.shade600),
          )
              : Wrap(
            spacing: 8.0, // Espace horizontal
            runSpacing: 8.0, // Espace vertical
            children: skills.map((skill) {
              return Chip(
                label: Text(skill, style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF6C63FF))),
                backgroundColor: const Color(0xFFF7F5FF),
                side: BorderSide(color: Colors.grey.shade300),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  /// --- 4. LE BLOC VÉRIFICATIONS ---
  Widget _buildVerificationSection(BuildContext context, bool emailVerified, bool phoneVerified, bool idVerified) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(context, 'Vérifications'),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              _buildVerificationItem(context, 'Email', emailVerified),
              const Divider(height: 20),
              _buildVerificationItem(context, 'Téléphone', phoneVerified),
              const Divider(height: 20),
              _buildVerificationItem(context, 'Pièce d\'identité', idVerified),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildVerificationItem(BuildContext context, String label, bool isVerified) {
    return Row(
      children: [
        Icon(
          isVerified ? Icons.check_circle : Icons.pending_outlined,
          color: isVerified ? Colors.green.shade600 : Colors.grey.shade400,
          size: 20,
        ),
        const SizedBox(width: 12),
        Text(
          label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const Spacer(),
        Text(
          isVerified ? 'Vérifié' : 'Non vérifié',
          style: TextStyle(
              fontSize: 13,
              color: isVerified ? Colors.green.shade600 : Colors.grey.shade600,
              fontWeight: isVerified ? FontWeight.bold : FontWeight.normal
          ),
        ),
      ],
    );
  }

  /// --- 5. TITRE DE SECTION GÉNÉRIQUE ---
  Widget _buildSectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10.0),
      child: Text(
        title,
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }

  /// --- 6. TUILE D'ACTION GÉNÉRIQUE ---
  Widget _actionTile(
      IconData icon, String title, VoidCallback onTap, Color color, {bool isLast = false}) {
    return Container(
      margin: EdgeInsets.only(bottom: isLast ? 0 : 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        trailing: const Icon(Icons.chevron_right, size: 20),
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}