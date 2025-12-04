import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mamission/shared/apple_appbar.dart'; // Assure-toi que ce chemin est bon

// --- CONSTANTES ---
const List<String> kAllSkills = [
  '⚡ Électricité', '🔧 Plomberie', '🌿 Jardinage', '🧹 Ménage',
  '📦 Déménagement', '🎨 Peinture', '🔨 Montage meubles', '📱 Tech Support',
  '💻 Web Dev', '🎓 Soutien Scolaire', '🍼 Baby-sitting', '🐶 Pet-sitting',
];

const Color kPrimary = Color(0xFF6C63FF);
const Color kPrimaryDark = Color(0xFF5A52D5);
const Color kBackground = Color(0xFFF7F9FC);
const Color kTextDark = Color(0xFF1A1D26);
const Color kTextGrey = Color(0xFF9EA3AE);
const Color kAccentGold = Color(0xFFFFD700); // Pour le badge Premium
const Color kSuccess = Color(0xFF00C853);    // Pour les checks verts

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;
  int _unreadNotifCount = 0;
  StreamSubscription<QuerySnapshot>? _notifSub;

  // Controllers
  final _nameCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _taglineCtrl = TextEditingController();

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    initializeDateFormatting('fr_FR');
    _listenNotifications();
  }

  void _listenNotifications() {
    final user = _auth.currentUser;
    if (user == null) return;

    _notifSub = _db
        .collection('notifications')
        .where('userId', isEqualTo: user.uid)
        .where('read', isEqualTo: false)
        .snapshots()
        .listen((snap) {
      setState(() {
        _unreadNotifCount = snap.docs.length;
      });
    });
  }

  Future<void> _logout() async {
    await _auth.signOut();
    if (mounted) context.go('/login');
  }

  Future<void> _pickAndUploadPhoto(String uid) async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked == null) return;
    setState(() => _saving = true);

    final file = File(picked.path);
    final ref = FirebaseStorage.instance.ref('users/$uid/profile_v2.jpg');
    await ref.putFile(file);
    final url = await ref.getDownloadURL();

    await _db.collection('users').doc(uid).update({'photoUrl': url});
    await _auth.currentUser?.updatePhotoURL(url);
    setState(() => _saving = false);
  }

  Future<void> _saveProfile(String uid, List<String> skills, bool isClient, bool isProvider, int radiusKm, bool remoteAvailable) async {
    setState(() => _saving = true);
    final newName = _nameCtrl.text.trim();
    if (newName.isNotEmpty) {
      await _auth.currentUser?.updateDisplayName(newName);
    }

    await _db.collection('users').doc(uid).set(
      {
        'name': newName,
        'bio': _bioCtrl.text.trim(),
        'tagline': _taglineCtrl.text.trim(),
        'city': _cityCtrl.text.trim(),
        'skills': skills,
        'isClient': isClient,
        'isProvider': isProvider,
        'radiusKm': radiusKm,
        'remoteAvailable': remoteAvailable,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✨ Profil mis à jour avec succès !'), backgroundColor: kPrimary),
      );
      setState(() => _saving = false);
    }
  }

  // --- SHEET D'ÉDITION DE PROFIL ---
  void _openEditSheet(Map<String, dynamic> data, String uid) {
    _nameCtrl.text = data['name'] ?? '';
    _bioCtrl.text = data['bio'] ?? '';
    _cityCtrl.text = data['city'] ?? '';
    _taglineCtrl.text = data['tagline'] ?? '';

    List<String> selectedSkills = (data['skills'] as List?)?.cast<String>() ?? [];
    bool isClient = data['isClient'] is bool ? data['isClient'] : true;
    bool isProvider = data['isProvider'] is bool ? data['isProvider'] : false;
    int radiusKm = (data['radiusKm'] is int) ? data['radiusKm'] : 10;
    bool remoteAvailable = data['remoteAvailable'] == true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.6,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return StatefulBuilder(
              builder: (sheetContext, setSheetState) {
                return Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                  ),
                  child: Column(
                    children: [
                      const SizedBox(height: 12),
                      Container(
                        width: 40, height: 4,
                        decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(999)),
                      ),
                      const SizedBox(height: 16),
                      const Text("Modifier ma vitrine", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      Expanded(
                        child: ListView(
                          controller: scrollController,
                          padding: const EdgeInsets.all(24),
                          children: [
                            _EditInput(ctrl: _nameCtrl, label: "Nom d'affichage", icon: Icons.person_outline),
                            const SizedBox(height: 16),
                            _EditInput(ctrl: _taglineCtrl, label: "Accroche (ex: Expert Plombier)", icon: Icons.flash_on_outlined),
                            const SizedBox(height: 16),
                            _EditInput(ctrl: _cityCtrl, label: "Ville", icon: Icons.location_on_outlined),
                            const SizedBox(height: 16),
                            _EditInput(ctrl: _bioCtrl, label: "À propos de vous", icon: Icons.history_edu, maxLines: 4),
                            const SizedBox(height: 24),
                            const Text("Compétences", style: TextStyle(fontWeight: FontWeight.w600)),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8, runSpacing: 8,
                              children: kAllSkills.map((skill) {
                                final isSel = selectedSkills.contains(skill);
                                return FilterChip(
                                  label: Text(skill),
                                  selected: isSel,
                                  onSelected: (v) {
                                    setSheetState(() => v ? selectedSkills.add(skill) : selectedSkills.remove(skill));
                                  },
                                  backgroundColor: kBackground,
                                  selectedColor: kPrimary.withOpacity(0.15),
                                  labelStyle: TextStyle(color: isSel ? kPrimary : kTextDark),
                                  checkmarkColor: kPrimary,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide.none),
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 32),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _saving ? null : () => _saveProfile(uid, selectedSkills, isClient, isProvider, radiusKm, remoteAvailable),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: kPrimary,
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                ),
                                child: _saving
                                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                    : const Text("Enregistrer", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                              ),
                            ),
                            const SizedBox(height: 40),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  // --- NOUVELLE SHEET ABONNEMENT "HIGH CONVERSION" ---
  void _openSubscriptionSheet({required String currentType, required bool active}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.85, // Plus grand pour afficher l'offre complète
          minChildSize: 0.6,
          maxChildSize: 0.95,
          builder: (_, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Stack(
                children: [
                  // Décoration de fond
                  Positioned(
                    top: -50, right: -50,
                    child: Container(
                      width: 200, height: 200,
                      decoration: BoxDecoration(color: kPrimary.withOpacity(0.05), shape: BoxShape.circle),
                    ),
                  ),
                  Column(
                    children: [
                      const SizedBox(height: 12),
                      Container(
                        width: 42, height: 4,
                        decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(20)),
                      ),

                      // CONTENU SCROLLABLE
                      Expanded(
                        child: ListView(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(24, 20, 24, 100), // Padding bottom pour le bouton fixe
                          children: [
                            // 1. HEADER VISUEL (Badge + Étoile)
                            Center(
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  Container(
                                    width: 70, height: 70,
                                    decoration: BoxDecoration(color: kPrimary.withOpacity(0.1), shape: BoxShape.circle),
                                  ),
                                  const Icon(Icons.verified, size: 40, color: kPrimary),
                                  Positioned(
                                    top: 0, right: 0,
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: const BoxDecoration(color: kAccentGold, shape: BoxShape.circle),
                                      child: const Icon(Icons.star, size: 10, color: Colors.white),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),

                            // 2. TITRE & ACCROCHE
                            const Text(
                              'Passez devant vos concurrents',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: kTextDark, height: 1.2),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Les profils vérifiés décrochent en moyenne 3x plus de missions.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 14, color: kTextGrey, height: 1.4),
                            ),

                            const SizedBox(height: 24),

                            // 3. CARTE "OFFRE RECOMMANDÉE"
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: kPrimary.withOpacity(0.15), width: 1.5),
                                boxShadow: [
                                  BoxShadow(
                                    color: kPrimary.withOpacity(0.08),
                                    blurRadius: 20,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: Column(
                                children: [
                                  // Header Carte
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    decoration: const BoxDecoration(
                                      color: kPrimary,
                                      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
                                    ),
                                    child: const Text(
                                      'OFFRE RECOMMANDÉE',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 1.0),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(20),
                                    child: Column(
                                      children: [
                                        // PRIX
                                        Row(
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: const [
                                            Text('9,99€', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: kTextDark)),
                                            Padding(
                                              padding: EdgeInsets.only(bottom: 5, left: 4),
                                              child: Text('/ mois', style: TextStyle(fontSize: 14, color: kTextGrey, fontWeight: FontWeight.w500)),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        const Text(
                                          'Rentabilisé dès la 1ère mission',
                                          style: TextStyle(fontSize: 12, color: kSuccess, fontWeight: FontWeight.w700),
                                        ),
                                        const SizedBox(height: 20),
                                        const Divider(height: 1),
                                        const SizedBox(height: 20),

                                        // LISTE AVANTAGES (Checkmarks verts)
                                        // LISTE AVANTAGES (Checkmarks verts)
                                        const _BenefitRowHighEnd(
                                          text: 'Votre profil apparaît en vitrine, vu en premier par les clients de votre zone.',
                                          isBold: true,
                                        ),
                                        const _BenefitRowHighEnd(
                                          text: 'Vous recevez des demandes directes quand un client vous choisit dans la vitrine.',
                                          isBold: true,
                                        ),
                                        const _BenefitRowHighEnd(
                                          text: 'Vous affichez un badge Vérifié qui rassure et fait cliquer plus de clients.',
                                        ),
                                        const _BenefitRowHighEnd(
                                          text: 'Vous êtes mieux classé que les comptes non vérifiés dans la liste des prestataires.',
                                        ),

                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 20),

                            // 4. PREUVE SOCIALE
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.people_outline, size: 16, color: kTextGrey.withOpacity(0.8)),
                                const SizedBox(width: 6),
                                Text(
                                  'Rejoint par +1,500 freelances ce mois-ci',
                                  style: TextStyle(fontSize: 12, color: kTextGrey.withOpacity(0.8)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  // BOUTON FIXE EN BAS (CTA)
                  Positioned(
                    left: 0, right: 0, bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(24, 20, 24, 30),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -5)),
                        ],
                      ),
                      child: Column(
                        children: [
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () {
                                Navigator.pop(context); // Fermer la sheet
                                context.push('/subscriptions/checkout', extra: {'plan': 'standard'});
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: kPrimary,
                                foregroundColor: Colors.white,
                                elevation: 8,
                                shadowColor: kPrimary.withOpacity(0.4),
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                              child: Text(
                                active ? "Gérer mon abonnement" : "Activer mon avantage maintenant",
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Sans engagement. Annulez en 1 clic à tout moment.',
                            style: TextStyle(fontSize: 11, color: kTextGrey),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _notifSub?.cancel();
    _nameCtrl.dispose();
    _bioCtrl.dispose();
    _cityCtrl.dispose();
    _taglineCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: kBackground,
      appBar: buildAppleMissionAppBar(title: "Mon Profil"),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _db.collection('users').doc(user.uid).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snapshot.data!.data() ?? {};
          final name = data['name'] ?? 'Utilisateur';
          final tagline = data['tagline'] ?? 'Membre MaMission';
          final photoUrl = data['photoUrl'];
          final isVerified = data['idVerified'] == true;
          final bool isProvider = data['isProvider'] == true;

          // --- Abonnement visibilité ---
          final String subType = (data['subType'] ?? 'none') as String;
          final String subStatus = (data['subStatus'] ?? 'none') as String;
          final bool subActive = subStatus == 'active';
          final bool isStandardActive = subActive && subType == 'standard';
          final bool isProActive = subActive && subType == 'pro';
          DateTime? subRenewsAt;
          final renewTs = data['subRenewsAt'];
          if (renewTs is Timestamp) {
            subRenewsAt = renewTs.toDate();
          }

          double balance = 0.0;
          if (data['walletBalance'] is num) {
            balance = (data['walletBalance'] as num).toDouble();
          }
          final soldeStr = balance.toStringAsFixed(2);

          Timestamp? memberTs = data['memberSince'] as Timestamp?;
          if (memberTs == null && user.metadata.creationTime != null) {
            memberTs = Timestamp.fromDate(user.metadata.creationTime!);
          }
          final memberDate = memberTs?.toDate() ?? DateTime.now();
          final memberLabel = DateFormat.yMMMM('fr_FR').format(memberDate);

          return SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 50),
            child: Column(
              children: [
                const SizedBox(height: 10),

                // Bouton notif
                Row(
                  children: [
                    const Spacer(),
                    _NotifCircleButton(
                      count: _unreadNotifCount,
                      onTap: () => context.push('/notifications'),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                _ProfileHeaderHighEnd(
                  name: name,
                  tagline: tagline,
                  photoUrl: photoUrl,
                  isVerified: isVerified,
                  onTapAvatar: () => _pickAndUploadPhoto(user.uid),
                ),

                const SizedBox(height: 20),

                // CTA vitrine
                Row(
                  children: [
                    Expanded(
                      child: _ActionButton(
                        label: isProvider ? "Voir ma vitrine" : "Créer ma vitrine prestataire",
                        icon: Icons.visibility_outlined,
                        isPrimary: true,
                        onTap: () => context.push(
                          '/profile/public',
                          extra: {'userId': user.uid, 'openEditOnStart': !isProvider},
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // VISIBILITÉ & ABONNEMENT
                const _SectionHeader(title: "VISIBILITÉ & ABONNEMENT"),
                _VisibilityCard(
                  isStandardActive: isStandardActive,
                  isProActive: isProActive,
                  active: subActive,
                  renewAt: subRenewsAt,
                  onTapPrimary: () => _openSubscriptionSheet(
                    currentType: subType,
                    active: subActive,
                  ),
                ),

                const SizedBox(height: 28),

                // ESPACE PRIVÉ
                const _SectionHeader(title: "ESPACE PRIVÉ & VÉRIFICATIONS"),
                _MenuCard(
                  children: [
                    _MenuRow(
                      icon: Icons.fingerprint_rounded,
                      title: "Identité & Vérification",
                      subtitle: isVerified ? "Compte vérifié" : "Action requise",
                      statusColor: isVerified ? Colors.green : Colors.orange,
                      onTap: () => context.push('/settings/kyc'),
                    ),
                    const _MenuDivider(),
                    _MenuRow(
                      icon: Icons.phone_iphone_rounded,
                      title: "Coordonnées",
                      subtitle: "Tél, Email, Adresse",
                      onTap: () => context.push('/settings/contact'),
                    ),
                    const _MenuDivider(),
                    _MenuRow(
                      icon: Icons.lock_outline_rounded,
                      title: "Connexion & Sécurité",
                      subtitle: "Mot de passe, FaceID",
                      onTap: () => context.push('/settings/security'),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // FINANCES
                const _SectionHeader(title: "FINANCES"),
                _MenuCard(
                  children: [
                    _MenuRow(
                      icon: Icons.account_balance_wallet_rounded,
                      title: "Mon Portefeuille",
                      trailing: Text(
                        "$soldeStr €",
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: kTextDark),
                      ),
                      onTap: () => context.push('/payments'),
                    ),
                    const _MenuDivider(),
                    _MenuRow(
                      icon: Icons.credit_card_rounded,
                      title: "Moyens de paiement",
                      subtitle: "Cartes & IBAN",
                      onTap: () => context.push('/settings/banking'),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // LOGOUT
                TextButton(
                  onPressed: _logout,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    backgroundColor: Colors.red.withOpacity(0.05),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.logout_rounded, size: 18),
                      SizedBox(width: 8),
                      Text("Me déconnecter", style: TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),

                const SizedBox(height: 12),
                Text(
                  "Membre depuis $memberLabel",
                  style: TextStyle(color: kTextGrey.withOpacity(0.6), fontSize: 11),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ================== WIDGETS UI & HELPERS ==================

class _BenefitRowHighEnd extends StatelessWidget {
  final String text;
  final bool isBold;

  const _BenefitRowHighEnd({required this.text, this.isBold = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(2),
            decoration: const BoxDecoration(
              color: Color(0xFFE8F5E9),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check, size: 14, color: kSuccess),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                color: kTextDark,
                fontWeight: isBold ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileHeaderHighEnd extends StatelessWidget {
  final String name;
  final String tagline;
  final String? photoUrl;
  final bool isVerified;
  final VoidCallback onTapAvatar;

  const _ProfileHeaderHighEnd({
    required this.name,
    required this.tagline,
    required this.photoUrl,
    required this.isVerified,
    required this.onTapAvatar,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          onTap: onTapAvatar,
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 4),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: CircleAvatar(
                  radius: 50,
                  backgroundColor: Colors.grey[200],
                  backgroundImage: photoUrl != null ? NetworkImage(photoUrl!) : null,
                  child: photoUrl == null ? const Icon(Icons.person, size: 40, color: Colors.grey) : null,
                ),
              ),
              if (isVerified)
                Positioned(
                  bottom: 2, right: 2,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                    child: const Icon(Icons.verified, color: kPrimary, size: 22),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: kTextDark)),
        const SizedBox(height: 4),
        Text(tagline, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: kTextGrey, fontWeight: FontWeight.w500)),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isPrimary;
  final VoidCallback onTap;

  const _ActionButton({required this.label, required this.icon, required this.isPrimary, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = isPrimary ? kPrimary : Colors.white;
    final textColor = isPrimary ? Colors.white : kTextDark;

    return Material(
      color: color,
      borderRadius: BorderRadius.circular(16),
      elevation: isPrimary ? 4 : 0,
      shadowColor: isPrimary ? kPrimary.withOpacity(0.4) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: isPrimary ? null : BoxDecoration(
            border: Border.all(color: const Color(0xFFE0E0E0)),
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: textColor),
              const SizedBox(width: 8),
              Text(label, style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}

class _VisibilityCard extends StatelessWidget {
  final bool isStandardActive;
  final bool isProActive;
  final bool active;
  final DateTime? renewAt;
  final VoidCallback onTapPrimary;

  const _VisibilityCard({required this.isStandardActive, required this.isProActive, required this.active, required this.renewAt, required this.onTapPrimary});

  @override
  Widget build(BuildContext context) {
    String title;
    String subtitle;
    String helper;
    String pillLabel;
    IconData icon;

    if (!active) {
      title = "Booster ma visibilité";
      subtitle = "Badge vérifié et profil mis en avant auprès des clients.";
      helper = "Compte vérifié • 9,99 € / mois • Sans engagement.";
      pillLabel = "Voir le compte vérifié";
      icon = Icons.rocket_launch_rounded;
    } else if (isProActive) {
      title = "Abonnement PRO actif";
      subtitle = "Vitrine mise en avant et priorité sur les missions.";
      helper = renewAt != null ? "Renouvellement le ${DateFormat('dd MMM', 'fr_FR').format(renewAt!)}" : "Renouvellement mensuel.";
      pillLabel = "Gérer";
      icon = Icons.workspace_premium_rounded;
    } else {
      title = "Compte vérifié actif";
      subtitle = "Badge vérifié + profil priorisé dans les offres.";
      helper = renewAt != null ? "Renouvellement le ${DateFormat('dd MMM', 'fr_FR').format(renewAt!)}" : "Renouvellement mensuel.";
      pillLabel = "Gérer";
      icon = Icons.verified_user_rounded;
    }

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTapPrimary,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(
              colors: [Color(0xFFEEF2FF), Color(0xFFE0ECFF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(color: const Color(0xFF7F00FF).withOpacity(0.05), blurRadius: 14, offset: const Offset(0, 6)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                    child: Icon(icon, color: kPrimary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: kTextDark)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(999)),
                    child: Text(pillLabel, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: kPrimary)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(subtitle, style: const TextStyle(fontSize: 12, color: kTextDark)),
              const SizedBox(height: 4),
              Text(helper, style: const TextStyle(fontSize: 11, color: kTextGrey)),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotifCircleButton extends StatelessWidget {
  final VoidCallback onTap;
  final int count;
  const _NotifCircleButton({required this.onTap, required this.count});
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFE5E5EA)),
                color: Colors.white,
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 2))],
              ),
              child: const Icon(Icons.notifications_none_rounded, size: 22, color: kTextDark),
            ),
            if (count > 0)
              Positioned(
                bottom: -8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.07), blurRadius: 8, offset: const Offset(0, 3))],
                  ),
                  child: Text(count > 9 ? '9+' : count.toString(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: kTextDark)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  final List<Widget> children;
  const _MenuCard({required this.children});
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Column(children: children),
    );
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Color? statusColor;
  final VoidCallback onTap;
  const _MenuRow({required this.icon, required this.title, this.subtitle, this.trailing, this.statusColor, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: kBackground, borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: kTextDark, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: kTextDark)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, style: TextStyle(fontSize: 12, color: statusColor ?? kTextGrey, fontWeight: statusColor != null ? FontWeight.w600 : FontWeight.normal)),
                  ],
                ],
              ),
            ),
            if (trailing != null) trailing!,
            if (trailing == null) const Icon(Icons.chevron_right_rounded, color: Color(0xFFE0E0E0), size: 22),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});
  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 12, bottom: 8, top: 4),
        child: Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: kTextGrey, letterSpacing: 1.0)),
      ),
    );
  }
}

class _MenuDivider extends StatelessWidget {
  const _MenuDivider();
  @override
  Widget build(BuildContext context) {
    return const Divider(height: 1, indent: 60, color: Color(0xFFF0F0F0));
  }
}

class _EditInput extends StatelessWidget {
  final TextEditingController ctrl;
  final String label;
  final IconData icon;
  final int maxLines;
  const _EditInput({required this.ctrl, required this.label, required this.icon, this.maxLines = 1});
  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label, prefixIcon: Icon(icon, color: kTextGrey),
        filled: true, fillColor: kBackground,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      ),
    );
  }
}