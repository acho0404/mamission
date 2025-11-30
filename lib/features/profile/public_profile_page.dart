import 'dart:async'; // Pour le Debouncer
import 'dart:convert'; // Pour décoder le JSON Google
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http; // NÉCESSAIRE POUR GOOGLE
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:mamission/core/secrets.dart';
// --- IMPORTS PROJET ---
import 'package:mamission/shared/apple_appbar.dart';
import 'package:mamission/features/reviews/reviews_page.dart';
import 'package:mamission/features/profile/user_repository.dart';
// --- CONSTANTES ---
const Color kPrimary = Color(0xFF6C63FF);
const Color kBackground = Color(0xFFF7F9FC);
const Color kTextDark = Color(0xFF1A1D26);
const Color kTextGrey = Color(0xFF9EA3AE);
const Color kErrorRed = Color(0xFFFF4B4B); // Rouge erreur

// 🔥 METS TA CLÉ GOOGLE ICI 🔥
const String kGoogleApiKey = Secrets.googleMapApiKey;

const List<String> kAllSkills = [
  'Électricité', 'Plomberie', 'Jardinage', 'Ménage',
  'Déménagement', 'Peinture', 'Montage meubles', 'Informatique',
  'Développement Web', 'Soutien Scolaire', 'Baby-sitting', 'Pet-sitting',
];

const List<String> kEquipements = [
  'Véhicule utilitaire', 'Voiture personnelle', 'Outillage complet',
  'Grande échelle', 'EPI (Sécurité)', 'Évacuation déchets'
];

class PublicProfilePage extends StatefulWidget {
  final String userId;
  final bool openEditOnStart;

  const PublicProfilePage({
    super.key,
    required this.userId,
    this.openEditOnStart = false,
  });

  @override
  State<PublicProfilePage> createState() => _PublicProfilePageState();
}

class _PublicProfilePageState extends State<PublicProfilePage> {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;
  final _picker = ImagePicker();

  // Contrôleurs
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _taglineCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _cityInputCtrl = TextEditingController();

  // --- VALIDATION VILLE ---
  bool _isCitySelectedFromList = false; // Est-ce qu'on a cliqué sur une suggestion ?
  String? _cityErrorText; // Texte d'erreur

  double _interventionRadius = 20.0;

  final _skillInputCtrl = TextEditingController();
  final _equipInputCtrl = TextEditingController();

  bool _saving = false;
  bool _didOpenInitialEdit = false;
  late Future<Map<String, int>> _statsFuture;

  bool _isUploadingProfile = false;
  int? _uploadingPortfolioIndex;

  String? _tempProfilePicUrl;
  List<String> _tempPortfolioUrls = [];

  List<String> _currentSkills = [];
  List<String> _currentEquipments = [];

  @override
  void initState() {
    super.initState();
    initializeDateFormatting('fr_FR');
    _statsFuture = _getProfileStats(widget.userId);
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _bioCtrl.dispose();
    _cityInputCtrl.dispose();
    _taglineCtrl.dispose();
    _skillInputCtrl.dispose();
    _equipInputCtrl.dispose();
    super.dispose();
  }

  Future<Map<String, int>> _getProfileStats(String uid) async {
    try {
      final posted = await _db.collection('missions').where('posterId', isEqualTo: uid).count().get();
      final completed = await _db.collection('missions').where('assignedTo', isEqualTo: uid).where('status', isEqualTo: 'done').count().get();
      return {'posted': posted.count ?? 0, 'completed': completed.count ?? 0};
    } catch (e) {
      return {'posted': 0, 'completed': 0};
    }
  }

  String _formatNameShort(String fullName) {
    if (fullName.trim().isEmpty) return "Utilisateur";
    final parts = fullName.trim().replaceAll(RegExp(r'\s+'), ' ').split(' ');
    if (parts.length <= 1) return parts[0];
    return "${parts[0]} ${parts[1][0].toUpperCase()}.";
  }

  Future<String?> _pickAndUpload(String folderName, {required Function(bool) onLoading}) async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
      if (image == null) return null;

      onLoading(true);
      String fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
      Reference ref = _storage.ref().child('users/${widget.userId}/$folderName/$fileName');
      await ref.putFile(File(image.path));
      String downloadUrl = await ref.getDownloadURL();
      onLoading(false);
      return downloadUrl;
    } catch (e) {
      onLoading(false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erreur: $e")));
      return null;
    }
  }

  void _openFullScreenGallery(BuildContext context, List<String> images, int initialIndex) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => _FullScreenGalleryViewer(images: images, initialIndex: initialIndex),
      ),
    );
  }

  // --- SAUVEGARDE AVEC VALIDATION STRICTE ---
  // --- SAUVEGARDE PROPRE (VIA REPOSITORY) ---
  Future<void> _saveProfile(String uid, bool isPro, StateSetter setSheetState) async {
    // 1. Validation Ville
    if (_cityInputCtrl.text.isNotEmpty && !_isCitySelectedFromList) {
      setSheetState(() {
        _cityErrorText = "Veuillez sélectionner une ville dans la liste suggérée.";
      });
      return;
    } else {
      setSheetState(() => _cityErrorText = null);
    }

    // 2. Début Sauvegarde
    setSheetState(() => _saving = true);

    try {
      // APPEL AU REPOSITORY (Code métier isolé)
      await UserRepository().updateProfile(
        uid: uid,
        firstName: _firstNameCtrl.text.trim(),
        lastName: _lastNameCtrl.text.trim(),
        bio: _bioCtrl.text.trim(),
        tagline: _taglineCtrl.text.trim(),
        city: _cityInputCtrl.text.trim(),
        radius: _interventionRadius,
        skills: _currentSkills,
        equipments: _currentEquipments,
        isProvider: isPro,
        photoUrl: _tempProfilePicUrl,
        portfolio: _tempPortfolioUrls,
      );

      if (!mounted) return;
      Navigator.of(context).pop(); // Ferme la modal
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erreur sauvegarde: $e")));
    } finally {
      if (mounted) setSheetState(() => _saving = false);
    }
  }

  // --- UI: SHEET MODIFICATION (FINAL PRO) ---
  void _openEditSheet(Map<String, dynamic> data) {
    String fullName = data['name'] ?? '';
    List<String> nameParts = fullName.split(' ');
    if (nameParts.isNotEmpty) {
      _firstNameCtrl.text = nameParts.first;
      _lastNameCtrl.text = nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '';
    }

    _bioCtrl.text = data['bio'] ?? '';
    _cityInputCtrl.text = data['city'] ?? '';

    // Si une ville est déjà enregistrée, on considère qu'elle est valide au départ
    if (_cityInputCtrl.text.isNotEmpty) {
      _isCitySelectedFromList = true;
    } else {
      _isCitySelectedFromList = false;
    }
    _cityErrorText = null;

    _taglineCtrl.text = data['tagline'] ?? '';
    _tempProfilePicUrl = data['photoUrl'];
    _tempPortfolioUrls = (data['portfolio'] as List?)?.cast<String>() ?? [];
    _currentSkills = (data['skills'] as List?)?.cast<String>() ?? [];
    _currentEquipments = (data['equipments'] as List?)?.cast<String>() ?? [];

    if (data['radius'] != null) {
      _interventionRadius = (data['radius'] as num).toDouble();
    }

    bool isProvider = data['isProvider'] == true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.92,
        minChildSize: 0.8,
        maxChildSize: 0.95,
        builder: (_, scrollController) => StatefulBuilder(
          builder: (sheetContext, setSheetState) {

            final bottomPadding = MediaQuery.of(sheetContext).viewInsets.bottom;
            final isKeyboardOpen = bottomPadding > 0;

            return GestureDetector(
              onTap: () => FocusScope.of(sheetContext).unfocus(),
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                ),
                padding: EdgeInsets.only(bottom: bottomPadding),
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(10))),
                    const SizedBox(height: 20),
                    const Text("Éditer mon profil", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: kTextDark)),
                    const SizedBox(height: 20),

                    Expanded(
                      child: ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        physics: const BouncingScrollPhysics(),
                        children: [
                          // PHOTO
                          Center(
                            child: GestureDetector(
                              onTap: _isUploadingProfile ? null : () async {
                                FocusScope.of(sheetContext).unfocus();
                                String? url = await _pickAndUpload('profile', onLoading: (loading) {
                                  setSheetState(() => _isUploadingProfile = loading);
                                });
                                if (url != null) setSheetState(() => _tempProfilePicUrl = url);
                              },
                              child: Column(
                                children: [
                                  Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      Container(
                                        width: 110, height: 110,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: Colors.grey[100],
                                          border: Border.all(color: Colors.grey[200]!, width: 2),
                                        ),
                                        child: ClipOval(
                                          child: _tempProfilePicUrl != null
                                              ? CachedNetworkImage(imageUrl: _tempProfilePicUrl!, fit: BoxFit.cover)
                                              : const Icon(Icons.person, size: 50, color: Colors.grey),
                                        ),
                                      ),
                                      if (!_isUploadingProfile)
                                        Positioned(
                                          bottom: 0, right: 0,
                                          child: Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: const BoxDecoration(color: kPrimary, shape: BoxShape.circle),
                                            child: const Icon(Icons.camera_alt, color: Colors.white, size: 20),
                                          ),
                                        ),
                                      if (_isUploadingProfile)
                                        const CircularProgressIndicator(color: kPrimary),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  const Text("Modifier la photo", style: TextStyle(color: kPrimary, fontWeight: FontWeight.bold, fontSize: 13)),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 30),
                          const _EditSectionTitle("Identité"),
                          Row(
                            children: [
                              Expanded(child: _ModernInput(ctrl: _firstNameCtrl, label: "Prénom", icon: Icons.person_outline)),
                              const SizedBox(width: 12),
                              Expanded(child: _ModernInput(ctrl: _lastNameCtrl, label: "Nom", icon: Icons.person_rounded)),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _ModernInput(ctrl: _taglineCtrl, label: "Titre (ex: Plombier)", icon: Icons.work_rounded),

                          const SizedBox(height: 30),

                          // --- ZONE D'INTERVENTION ---
                          _ZoneInterventionSelector(
                            controller: _cityInputCtrl,
                            radius: _interventionRadius,
                            errorText: _cityErrorText, // On passe l'erreur
                            onRadiusChanged: (val) => setSheetState(() => _interventionRadius = val),
                            onSuggestionSelected: () {
                              setSheetState(() {
                                _isCitySelectedFromList = true;
                                _cityErrorText = null; // Reset erreur si sélectionné
                              });
                            },
                            onTextChanged: () {
                              // Dès qu'il modifie le texte, on reset la validation
                              if (_isCitySelectedFromList) {
                                setSheetState(() => _isCitySelectedFromList = false);
                              }
                            },
                          ),

                          const SizedBox(height: 30),
                          const _EditSectionTitle("Présentation"),
                          _ModernInput(ctrl: _bioCtrl, label: "Votre parcours...", icon: Icons.format_quote_rounded, maxLines: 4),

                          const SizedBox(height: 30),
                          const Text("Portfolio (Max 3)", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              for (int i = 0; i < 3; i++)
                                _PortfolioUploadSlot(
                                  url: i < _tempPortfolioUrls.length ? _tempPortfolioUrls[i] : null,
                                  isLoading: _uploadingPortfolioIndex == i,
                                  onTap: () async {
                                    FocusScope.of(sheetContext).unfocus();
                                    if (i >= _tempPortfolioUrls.length) {
                                      String? url = await _pickAndUpload('portfolio', onLoading: (loading) {
                                        setSheetState(() => _uploadingPortfolioIndex = loading ? i : null);
                                      });
                                      if (url != null) setSheetState(() => _tempPortfolioUrls.add(url));
                                    }
                                  },
                                  onDelete: () => setSheetState(() => _tempPortfolioUrls.removeAt(i)),
                                ),
                            ],
                          ),

                          const SizedBox(height: 30),
                          _SmartTagSection(
                            title: "Vos Atouts Matériels",
                            controller: _equipInputCtrl,
                            suggestions: kEquipements,
                            selectedTags: _currentEquipments,
                            onChanged: () => setSheetState((){}),
                          ),

                          const SizedBox(height: 24),
                          // --- DERNIER ÉLÉMENT ---
                          _SmartTagSection(
                            title: "Compétences",
                            controller: _skillInputCtrl,
                            suggestions: kAllSkills,
                            selectedTags: _currentSkills,
                            onChanged: () => setSheetState((){}),
                          ),

                          // 🔥 ESPACE GÉANT EN BAS POUR PERMETTRE LE SCROLL COMPLET 🔥
                          const SizedBox(height: 350),
                        ],
                      ),
                    ),

                    // --- BOUTON CACHÉ SI CLAVIER OUVERT ---
                    if (!isKeyboardOpen)
                      Container(
                        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -5))],
                        ),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _saving ? null : () => _saveProfile(widget.userId, isProvider, setSheetState),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: kTextDark,
                              disabledBackgroundColor: kTextDark,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            child: _saving
                                ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                                : const Text("Enregistrer les modifications", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // --- UI: PAGE PRINCIPALE (VITRINE) ---
  @override
  Widget build(BuildContext context) {
    final currentUser = _auth.currentUser;
    final isOwner = currentUser != null && currentUser.uid == widget.userId;

    return Scaffold(
      backgroundColor: kBackground,
      appBar: buildAppleMissionAppBar(
        title: "",
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20, color: Colors.white), // 🔥 BLANC 🔥
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (isOwner)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: IconButton(
                icon: const Icon(Icons.tune_rounded, color: Colors.white), // 🔥 BLANC 🔥
                onPressed: () => _db.collection('users').doc(widget.userId).get().then((doc) {
                  if (doc.exists) _openEditSheet(doc.data()!);
                }),
              ),
            ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _db.collection('users').doc(widget.userId).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          final data = snapshot.data!.data() ?? {};
          final rawName = data['name'] ?? 'Utilisateur';
          final formattedName = _formatNameShort(rawName);
          final tagline = (data['tagline'] ?? 'Membre MaMission') as String;
          final photoUrl = data['photoUrl'];
          final bio = (data['bio'] ?? '') as String;
          final city = (data['city'] ?? '') as String;
          final skills = (data['skills'] as List?)?.cast<String>() ?? [];
          final equipments = (data['equipments'] as List?)?.cast<String>() ?? [];
          final portfolio = (data['portfolio'] as List?)?.cast<String>() ?? [];
          final double radius = (data['radius'] is num) ? (data['radius'] as num).toDouble() : 0.0;

          double rating = (data['rating'] is num) ? (data['rating'] as num).toDouble() : 5.0;
          final int reviewsCount = (data['reviewsCount'] is num) ? (data['reviewsCount'] as num).toInt() : 0;

          if (isOwner && widget.openEditOnStart && !_didOpenInitialEdit) {
            _didOpenInitialEdit = true;
            WidgetsBinding.instance.addPostFrameCallback((_) => _openEditSheet(data));
          }

          return SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(30),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft, end: Alignment.bottomRight,
                        colors: [Color(0xFF7F00FF), Color(0xFF3B82F6), Color(0xFF00D4FF)],
                      ),
                      boxShadow: [BoxShadow(color: const Color(0xFF7F00FF).withOpacity(0.4), blurRadius: 20, offset: const Offset(0, 10))],
                    ),
                    child: Column(
                      children: [
                        const SizedBox(height: 30),
                        Stack(
                          alignment: Alignment.bottomRight,
                          children: [
                            Container(
                              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white.withOpacity(0.3), width: 4)),
                              child: CircleAvatar(
                                radius: 50,
                                backgroundColor: Colors.white.withOpacity(0.1),
                                backgroundImage: photoUrl != null ? CachedNetworkImageProvider(photoUrl) : null,
                                child: photoUrl == null ? const Icon(Icons.person, size: 45, color: Colors.white70) : null,
                              ),
                            ),
                            if (data['idVerified'] == true)
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                                child: const Icon(Icons.check, color: Color(0xFF7F00FF), size: 16),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(formattedName, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 0.5)),
                        const SizedBox(height: 4),
                        Text(tagline, style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.8), fontWeight: FontWeight.w500)),

                        if (city.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.white.withOpacity(0.3))
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.location_on_rounded, size: 14, color: Colors.white),
                                const SizedBox(width: 6),
                                Text(
                                    radius > 0 ? "$city + ${radius.round()} km" : city,
                                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)
                                ),
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 24),
                        Divider(color: Colors.white.withOpacity(0.2), height: 1),
                        const SizedBox(height: 20),
                        FutureBuilder<Map<String, int>>(
                            future: _statsFuture,
                            builder: (ctx, snap) {
                              final stats = snap.data ?? {'posted': 0, 'completed': 0};
                              final int postedCount = stats['posted'] ?? 0;
                              final int completedCount = stats['completed'] ?? 0;
                              final String completionRateStr = postedCount > 0 ? "${((completedCount / postedCount) * 100).round()}%" : "N/A";
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 24),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                  children: [
                                    Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReviewsPage(missionId: '', missionTitle: 'Avis', userId: widget.userId))),
                                        borderRadius: BorderRadius.circular(12),
                                        child: Padding(
                                          padding: const EdgeInsets.all(8.0),
                                          child: Column(children: [
                                            Row(
                                              children: [
                                                const Icon(Icons.star_rounded, color: Colors.amber, size: 22),
                                                const SizedBox(width: 4),
                                                Text(rating.toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: Colors.white)),
                                              ],
                                            ),
                                            const SizedBox(height: 2),
                                            Row(
                                              children: [
                                                Text("$reviewsCount avis", style: const TextStyle(fontSize: 12, color: Colors.white, decoration: TextDecoration.underline, decorationColor: Colors.white70, fontWeight: FontWeight.w500)),
                                                const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white70, size: 10)
                                              ],
                                            ),
                                          ]),
                                        ),
                                      ),
                                    ),
                                    Container(height: 30, width: 1, color: Colors.white24),
                                    _NeonStatItem(value: "$completedCount", label: "Missions finies", icon: Icons.check_circle_rounded, iconColor: Colors.greenAccent),
                                    Container(height: 30, width: 1, color: Colors.white24),
                                    _NeonStatItem(value: completionRateStr, label: "Complétion", icon: Icons.pie_chart_rounded, iconColor: Colors.lightBlueAccent),
                                  ],
                                ),
                              );
                            }
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 30),
                if (!isOwner)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      children: [
                        Expanded(
                            child: ElevatedButton(onPressed: (){}, style: ElevatedButton.styleFrom(backgroundColor: kTextDark, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))), child: const Text("Proposer Mission", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))
                        ),
                        const SizedBox(width: 12),
                        Container(
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey[200]!)),
                          child: IconButton(onPressed: () {}, icon: const Icon(Icons.chat_bubble_outline_rounded), color: kTextDark, padding: const EdgeInsets.all(14)),
                        )
                      ],
                    ),
                  ),
                if (!isOwner) const SizedBox(height: 30),

                Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                  ),
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _SectionHeader(title: "À propos", icon: Icons.person_outline),
                      Text(bio.isEmpty ? "Aucune description fournie." : bio, style: const TextStyle(fontSize: 15, height: 1.5, color: Color(0xFF4A4A4A))),
                      const SizedBox(height: 30),
                      const _SectionHeader(title: "Portfolio", icon: Icons.photo_library_outlined),
                      if (portfolio.isEmpty)
                        const Text("Aucune photo pour le moment.", style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic))
                      else
                        SizedBox(
                          height: 100,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            physics: const BouncingScrollPhysics(),
                            itemCount: portfolio.length,
                            itemBuilder: (ctx, index) {
                              return GestureDetector(
                                onTap: () => _openFullScreenGallery(context, portfolio, index),
                                child: Container(
                                  width: 100,
                                  margin: const EdgeInsets.only(right: 12),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(16),
                                    child: CachedNetworkImage(
                                      imageUrl: portfolio[index],
                                      fit: BoxFit.cover,
                                      placeholder: (context, url) => Container(color: Colors.grey[200]),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      const SizedBox(height: 30),
                      const _SectionHeader(title: "Équipement & Véhicule", icon: Icons.construction_outlined),
                      if (equipments.isEmpty)
                        const Text("Non spécifié", style: TextStyle(color: kTextGrey, fontStyle: FontStyle.italic))
                      else
                        Wrap(
                            spacing: 10, runSpacing: 10,
                            children: equipments.map<Widget>((e) => _EquipmentTag(label: e)).toList()
                        ),
                      const SizedBox(height: 30),
                      const _SectionHeader(title: "Compétences", icon: Icons.handyman_outlined),
                      Wrap(
                        spacing: 8, runSpacing: 8,
                        children: skills.map((s) => Chip(
                          label: Text(s, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          backgroundColor: kBackground,
                          side: BorderSide.none,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        )).toList(),
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ==========================================
// --- WIDGET ZONE D'INTERVENTION (VALIDATION STRICTE) ---
// ==========================================

class _ZoneInterventionSelector extends StatefulWidget {
  final TextEditingController controller;
  final double radius;
  final Function(double) onRadiusChanged;
  final VoidCallback onSuggestionSelected;
  final VoidCallback onTextChanged;
  final String? errorText;

  const _ZoneInterventionSelector({
    required this.controller,
    required this.radius,
    required this.onRadiusChanged,
    required this.onSuggestionSelected,
    required this.onTextChanged,
    this.errorText,
  });

  @override
  State<_ZoneInterventionSelector> createState() => _ZoneInterventionSelectorState();
}

class _ZoneInterventionSelectorState extends State<_ZoneInterventionSelector> {
  List<String> _suggestions = [];
  Timer? _debounce;
  final GlobalKey _inputKey = GlobalKey();

  Future<void> _getPlacePredictions(String input) async {
    if (input.length < 2) {
      setState(() => _suggestions = []);
      return;
    }

    final String url =
        "https://maps.googleapis.com/maps/api/place/autocomplete/json?input=$input&types=(regions)&components=country:fr&language=fr&key=$kGoogleApiKey";

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final predictions = data['predictions'] as List;
        setState(() {
          _suggestions = predictions
              .map((p) => p['description'] as String)
              .take(4)
              .toList();
        });

        // Auto-scroll pour voir les suggestions
        Future.delayed(const Duration(milliseconds: 100), () {
          if (_inputKey.currentContext != null) {
            Scrollable.ensureVisible(
                _inputKey.currentContext!,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                alignment: 0.1
            );
          }
        });
      }
    } catch (e) {
      print("Erreur Google Places: $e");
    }
  }

  void _onSearchChanged(String val) {
    widget.onTextChanged(); // Signale que le texte a changé (donc plus valide)

    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _getPlacePredictions(val);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      key: _inputKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Align(
              alignment: Alignment.centerLeft,
              child: Text("ZONE D'INTERVENTION", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: kTextGrey, letterSpacing: 1.0))
          ),
        ),

        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: widget.controller,
              onChanged: _onSearchChanged,
              onTap: () {
                Future.delayed(const Duration(milliseconds: 300), () {
                  Scrollable.ensureVisible(_inputKey.currentContext!, alignment: 0.1);
                });
              },
              decoration: InputDecoration(
                labelText: "Ville ou Code Postal",
                prefixIcon: Icon(Icons.location_on_rounded, color: kTextDark.withOpacity(0.6), size: 22),
                filled: true,
                fillColor: kBackground,
                // --- BORDURE ROUGE EN CAS D'ERREUR ---
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                enabledBorder: widget.errorText != null
                    ? OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: kErrorRed, width: 1.5))
                    : OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                focusedBorder: widget.errorText != null
                    ? OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: kErrorRed, width: 2))
                    : OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: kPrimary, width: 1.5)),
              ),
            ),

            // Message d'erreur
            if (widget.errorText != null)
              Padding(
                padding: const EdgeInsets.only(top: 8, left: 12),
                child: Text(widget.errorText!, style: const TextStyle(color: kErrorRed, fontSize: 12, fontWeight: FontWeight.bold)),
              ),

            if (_suggestions.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 8),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey[200]!)),
                child: Column(
                  children: _suggestions.map((city) => ListTile(
                    dense: true,
                    title: Text(city),
                    leading: const Icon(Icons.place, size: 16, color: kPrimary),
                    onTap: () {
                      widget.controller.text = city;
                      setState(() => _suggestions = []);
                      FocusScope.of(context).unfocus();
                      widget.onSuggestionSelected(); // Signale que c'est valide
                    },
                  )).toList(),
                ),
              ),
          ],
        ),

        const SizedBox(height: 20),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: kBackground, borderRadius: BorderRadius.circular(16)),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Rayon d'action", style: TextStyle(fontWeight: FontWeight.w600, color: kTextDark)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: kPrimary, borderRadius: BorderRadius.circular(20)),
                    child: Text(
                      "${widget.radius.round()} km",
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                ],
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: kPrimary,
                  inactiveTrackColor: Colors.grey[300],
                  thumbColor: Colors.white,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 12, elevation: 4),
                  overlayColor: kPrimary.withOpacity(0.2),
                ),
                child: Slider(
                  value: widget.radius,
                  min: 5,
                  max: 100,
                  divisions: 19,
                  onChanged: widget.onRadiusChanged,
                ),
              ),
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("5 km", style: TextStyle(fontSize: 11, color: Colors.grey)),
                  Text("100 km", style: TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              )
            ],
          ),
        ),
      ],
    );
  }
}

// ==========================================
// --- WIDGET SMART TAGS (KEY & SCROLL) ---
// ==========================================

class _SmartTagSection extends StatefulWidget {
  final String title;
  final TextEditingController controller;
  final List<String> suggestions;
  final List<String> selectedTags;
  final VoidCallback onChanged;

  const _SmartTagSection({
    super.key,
    required this.title,
    required this.controller,
    required this.suggestions,
    required this.selectedTags,
    required this.onChanged,
  });

  @override
  State<_SmartTagSection> createState() => _SmartTagSectionState();
}

class _SmartTagSectionState extends State<_SmartTagSection> {
  String _searchTerm = "";
  final GlobalKey _inputFieldKey = GlobalKey();

  void _addTag(String tag) {
    if (tag.trim().isEmpty) return;
    final existing = widget.selectedTags.firstWhere(
            (t) => t.toLowerCase() == tag.trim().toLowerCase(),
        orElse: () => "");

    if (existing.isEmpty) {
      widget.selectedTags.add(tag.trim());
      widget.controller.clear();
      setState(() => _searchTerm = "");
      widget.onChanged();
    } else {
      widget.controller.clear();
      setState(() => _searchTerm = "");
    }
  }

  @override
  Widget build(BuildContext context) {
    final availableSuggestions = widget.suggestions.where((s) {
      final matchesSearch = s.toLowerCase().contains(_searchTerm.toLowerCase());
      final isNotSelected = !widget.selectedTags.contains(s);
      return matchesSearch && isNotSelected;
    }).toList();

    final bool showCustomAdd = _searchTerm.isNotEmpty &&
        !widget.suggestions.any((s) => s.toLowerCase() == _searchTerm.toLowerCase()) &&
        !widget.selectedTags.any((t) => t.toLowerCase() == _searchTerm.toLowerCase());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        const SizedBox(height: 10),

        if (widget.selectedTags.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Wrap(
              spacing: 8, runSpacing: 8,
              children: widget.selectedTags.map((tag) => Chip(
                label: Text(tag),
                deleteIcon: const Icon(Icons.close, size: 16, color: Colors.white),
                onDeleted: () {
                  setState(() => widget.selectedTags.remove(tag));
                  widget.onChanged();
                },
                backgroundColor: kPrimary,
                labelStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide.none),
              )).toList(),
            ),
          ),

        // CLÉ POUR SCROLL
        Container(
          key: _inputFieldKey,
          child: TextField(
            controller: widget.controller,
            onChanged: (val) => setState(() => _searchTerm = val),
            onSubmitted: (val) => _addTag(val),
            onTap: () {
              Future.delayed(const Duration(milliseconds: 300), () {
                if (_inputFieldKey.currentContext != null) {
                  Scrollable.ensureVisible(
                    _inputFieldKey.currentContext!,
                    alignment: 0.05,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                }
              });
            },
            decoration: InputDecoration(
              hintText: "Ajouter (ex: ${widget.suggestions.first})...",
              hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
              suffixIcon: IconButton(
                icon: const Icon(Icons.add_circle_rounded, color: kPrimary),
                onPressed: () => _addTag(widget.controller.text),
              ),
              filled: true,
              fillColor: kBackground,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
        ),

        const SizedBox(height: 12),

        Wrap(
          spacing: 8, runSpacing: 8,
          children: [
            ...availableSuggestions.map((tag) => ActionChip(
              label: Text(tag),
              onPressed: () => _addTag(tag),
              backgroundColor: Colors.white,
              side: BorderSide(color: Colors.grey[300]!),
              labelStyle: const TextStyle(color: kTextDark),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            )),

            if (showCustomAdd)
              ActionChip(
                label: Text("Ajouter \"$_searchTerm\" +"),
                onPressed: () => _addTag(_searchTerm),
                backgroundColor: kPrimary.withOpacity(0.1),
                side: const BorderSide(color: kPrimary),
                labelStyle: const TextStyle(color: kPrimary, fontWeight: FontWeight.bold),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
          ],
        ),
      ],
    );
  }
}

class _PortfolioUploadSlot extends StatelessWidget {
  final String? url;
  final bool isLoading;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _PortfolioUploadSlot({this.url, required this.onTap, required this.onDelete, this.isLoading = false});

  @override
  Widget build(BuildContext context) {
    final width = (MediaQuery.of(context).size.width - 48 - 20) / 3;

    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: width, height: width,
            decoration: BoxDecoration(
              color: kBackground,
              borderRadius: BorderRadius.circular(16),
              border: url == null ? Border.all(color: Colors.grey[300]!, width: 2) : null,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (url != null)
                    CachedNetworkImage(
                      imageUrl: url!,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(color: Colors.grey[100]),
                    ),
                  if (url == null && !isLoading)
                    Icon(Icons.add_rounded, color: Colors.grey[400], size: 30),
                  if (isLoading)
                    Container(
                      color: Colors.black12,
                      child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                    ),
                ],
              ),
            ),
          ),
          if (url != null && !isLoading)
            Positioned(
              top: -6, right: -6,
              child: GestureDetector(
                onTap: onDelete,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
                  child: const Icon(Icons.close, color: Colors.white, size: 12),
                ),
              ),
            )
        ],
      ),
    );
  }
}

class _FullScreenGalleryViewer extends StatefulWidget {
  final List<String> images;
  final int initialIndex;

  const _FullScreenGalleryViewer({required this.images, required this.initialIndex});

  @override
  State<_FullScreenGalleryViewer> createState() => _FullScreenGalleryViewerState();
}

class _FullScreenGalleryViewerState extends State<_FullScreenGalleryViewer> {
  late PageController _pageController;
  late int currentIndex;

  @override
  void initState() {
    super.initState();
    currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PhotoViewGallery.builder(
            scrollPhysics: const BouncingScrollPhysics(),
            builder: (BuildContext context, int index) {
              return PhotoViewGalleryPageOptions(
                imageProvider: CachedNetworkImageProvider(widget.images[index]),
                initialScale: PhotoViewComputedScale.contained,
                minScale: PhotoViewComputedScale.contained,
                maxScale: PhotoViewComputedScale.covered * 2,
                heroAttributes: PhotoViewHeroAttributes(tag: widget.images[index]),
              );
            },
            itemCount: widget.images.length,
            loadingBuilder: (context, event) => const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
            backgroundDecoration: const BoxDecoration(color: Colors.black),
            pageController: _pageController,
            onPageChanged: (index) => setState(() => currentIndex = index),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 30),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Text(
                    "${currentIndex + 1} / ${widget.images.length}",
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NeonStatItem extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final Color iconColor;

  const _NeonStatItem({required this.value, required this.label, required this.icon, required this.iconColor});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: iconColor, size: 22),
        const SizedBox(height: 6),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Colors.white)),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.8), fontWeight: FontWeight.w500)),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: kPrimary),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: kTextDark)),
        ],
      ),
    );
  }
}

class _EquipmentTag extends StatelessWidget {
  final String label;
  const _EquipmentTag({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kTextDark)),
    );
  }
}

class _EditSectionTitle extends StatelessWidget {
  final String title;
  const _EditSectionTitle(this.title);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Align(alignment: Alignment.centerLeft, child: Text(title.toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: kTextGrey, letterSpacing: 1.0))),
    );
  }
}

class _ModernInput extends StatelessWidget {
  final TextEditingController ctrl;
  final String label;
  final IconData icon;
  final int maxLines;

  const _ModernInput({required this.ctrl, required this.label, required this.icon, this.maxLines = 1});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      style: const TextStyle(fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.grey[500]),
        prefixIcon: Icon(icon, color: kTextDark.withOpacity(0.6), size: 22),
        filled: true,
        fillColor: kBackground,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: kPrimary, width: 1.5)),
      ),
    );
  }
}