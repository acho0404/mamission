import 'dart:io';
import 'dart:ui'; // Pour le flou (Glassmorphism)

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_place/google_place.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:flutter/services.dart';
import 'package:mamission/features/missions/mission_repository.dart';
// -----------------------------------------------------------------------------
// THEME FUTURISTE CLAIR (Light Cyberpunk)
// -----------------------------------------------------------------------------
class AppTheme {
  // Fonds clairs
  static const Color bgLight = Color(0xFFF3F6FF); // Blanc cassé légèrement bleuté
  static const Color cardLight = Colors.white;

  // Accents vibrants
  static const Color neonPrimary = Color(0xFF6C63FF); // Violet électrique
  static const Color neonCyan = Color(0xFF00B8D4);   // Cyan un peu plus soutenu pour le contraste

  // Textes foncés
  static const Color textDark = Color(0xFF1A1F36);   // Presque noir
  static const Color textGrey = Color(0xFF6E7787);   // Gris moyen

  // Box style "Glass" pour fond clair
  static BoxDecoration glassBox() {
    return BoxDecoration(
      color: Colors.white.withOpacity(0.7), // Blanc translucide
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: Colors.white), // Bordure blanche nette
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF6C63FF).withOpacity(0.1), // Ombre violette très douce
          blurRadius: 20,
          offset: const Offset(0, 10),
        ),
      ],
    );
  }

  // Ombre portée colorée pour les boutons/sélections
  static List<BoxShadow> coloredShadow(Color color) {
    return [
      BoxShadow(
        color: color.withOpacity(0.3),
        blurRadius: 12,
        offset: const Offset(0, 6),
      ),
    ];
  }
}

// -----------------------------------------------------------------------------
// WIDGET D'ANIMATION PERSONNALISÉ (Apparition en glissant)
// -----------------------------------------------------------------------------
class FadeInSlide extends StatefulWidget {
  final Widget child;
  final double delay;

  const FadeInSlide({super.key, required this.child, this.delay = 0});

  @override
  State<FadeInSlide> createState() => _FadeInSlideState();
}

class _FadeInSlideState extends State<FadeInSlide> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutQuart));

    Future.delayed(Duration(milliseconds: (widget.delay * 1000).round()), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnim,
      child: SlideTransition(position: _slideAnim, child: widget.child),
    );
  }
}


class MissionCreatePage extends StatefulWidget {
  final String? editMissionId;
  const MissionCreatePage({super.key, this.editMissionId});

  @override
  State<MissionCreatePage> createState() => _MissionCreatePageState();
}

class _MissionCreatePageState extends State<MissionCreatePage> {
  // ---------------------------------------------------------------------------
  // CONTROLLERS & STATE
  // ---------------------------------------------------------------------------
  final _formKey = GlobalKey<FormState>();
  final PageController _pageController = PageController();

  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _budgetCtrl = TextEditingController();
  final _durationCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();

  String? _selectedCategory;
  String _mode = "Sur place";
  String _flexibility = "Flexible";
  DateTime? _missionDate;
  TimeOfDay? _missionTime;
  File? _photoFile;

  bool _loading = false;
  bool _submitting = false;
  late GooglePlace googlePlace;
  List<AutocompletePrediction> _predictions = [];
  final int _totalSteps = 4;
  int _currentStep = 0;

  // ---------------------------------------------------------------------------
  // NOUVELLE LISTE COLORÉE
  // ---------------------------------------------------------------------------
  final List<Map<String, dynamic>> _categoriesList = [
    {"name": "Bricolage", "icon": Icons.handyman_rounded, "color": const Color(0xFFFFF4E5), "accent": const Color(0xFFFF9800)},
    {"name": "Jardinage", "icon": Icons.park_rounded, "color": const Color(0xFFE8F5E9), "accent": const Color(0xFF4CAF50)},
    {"name": "Déménagement", "icon": Icons.local_shipping_rounded, "color": const Color(0xFFE3F2FD), "accent": const Color(0xFF2196F3)},
    {"name": "Ménage", "icon": Icons.cleaning_services_rounded, "color": const Color(0xFFF3E5F5), "accent": const Color(0xFF9C27B0)},
    {"name": "Enfants", "icon": Icons.child_care_rounded, "color": const Color(0xFFFFEBEE), "accent": const Color(0xFFE91E63)},
    {"name": "Animaux", "icon": Icons.pets_rounded, "color": const Color(0xFFEFEBE9), "accent": const Color(0xFF795548)},
    {"name": "Informatique", "icon": Icons.laptop_mac_rounded, "color": const Color(0xFFE0F7FA), "accent": const Color(0xFF00BCD4)},
    {"name": "Aide à domicile", "icon": Icons.elderly_rounded, "color": const Color(0xFFFFF3E0), "accent": const Color(0xFFFF5722)},
    {"name": "Cours particuliers", "icon": Icons.school_rounded, "color": const Color(0xFFE8EAF6), "accent": const Color(0xFF3F51B5)},
    {"name": "Événementiel", "icon": Icons.celebration_rounded, "color": const Color(0xFFFCE4EC), "accent": const Color(0xFFE91E63)},
  ];

  @override
  void initState() {
    super.initState();
    initializeDateFormatting('fr_FR', null);
    // REMPLACEZ PAR VOTRE VRAIE CLÉ API GOOGLE PLACES
    googlePlace = GooglePlace("VOTRE_CLE_API_ICI");

    if (widget.editMissionId != null) {
      _loadMissionForEdit(widget.editMissionId!);
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose(); _descCtrl.dispose(); _budgetCtrl.dispose();
    _durationCtrl.dispose(); _locationCtrl.dispose(); _pageController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // FIREBASE LOGIC
  // ---------------------------------------------------------------------------
  Future<void> _loadMissionForEdit(String id) async {
    setState(() => _loading = true);
    try {
      final snap = await FirebaseFirestore.instance.collection('missions').doc(id).get();
      if (!snap.exists) { setState(() => _loading = false); return; }
      final data = snap.data()!;
      setState(() {
        _titleCtrl.text = data['title'] ?? '';
        _descCtrl.text = data['description'] ?? '';
        _durationCtrl.text = data['duration']?.toString() ?? '';
        _budgetCtrl.text = data['budget']?.toString() ?? '';
        _locationCtrl.text = data['location'] ?? '';
        _selectedCategory = data['category'];
        _mode = data['mode'] ?? 'Sur place';
        _flexibility = data['flexibility'] ?? 'Flexible';
        if (data['deadline'] != null) _missionDate = (data['deadline'] as Timestamp).toDate();
        if (data['missionTime'] != null) {
          final parts = (data['missionTime'] as String).split(':');
          _missionTime = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
        }
        _loading = false;
      });
    } catch (e) { setState(() => _loading = false); }
  }

  Future<void> _saveMission() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCategory == null || _missionDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Catégorie et date requises"), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _submitting = true);

    try {
      // 1. Upload Photo (si présente)
      String? photoUrl;
      if (_photoFile != null) {
        final ref = FirebaseStorage.instance
            .ref()
            .child("missions/${DateTime.now().millisecondsSinceEpoch}.jpg");
        await ref.putFile(_photoFile!);
        photoUrl = await ref.getDownloadURL();
      }

      // 2. Géocodage (Adresse -> Lat/Lng)
      Map<String, double>? position;
      if (_locationCtrl.text.isNotEmpty) {
        try {
          // Petit délai pour éviter le spam API si nécessaire
          final res = await locationFromAddress(_locationCtrl.text);
          if (res.isNotEmpty) {
            position = {"lat": res.first.latitude, "lng": res.first.longitude};
          }
        } catch (_) {
          // On continue même si le géocodage échoue (la mission sera sans map)
        }
      }

      // 3. Formatage de l'heure
      final String? timeStr = _missionTime != null
          ? "${_missionTime!.hour.toString().padLeft(2, '0')}:${_missionTime!.minute.toString().padLeft(2, '0')}"
          : null;

      // 4. APPEL AU REPOSITORY (Sauvegarde)
      await MissionRepository().saveMission(
        missionId: widget.editMissionId,
        title: _titleCtrl.text.trim(),
        description: _descCtrl.text.trim(),
        budget: double.tryParse(_budgetCtrl.text) ?? 0,
        duration: double.tryParse(_durationCtrl.text) ?? 0,
        deadline: _missionDate!,
        timeStr: timeStr,
        category: _selectedCategory!,
        location: _locationCtrl.text.trim(),
        mode: _mode,
        flexibility: _flexibility,
        position: position,
        photoUrl: photoUrl,
      );

      if (mounted) Navigator.pop(context); // Retour à l'accueil
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erreur: $e")));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ---------------------------------------------------------------------------
  // NAVIGATION & OUTILS
  // ---------------------------------------------------------------------------
  void _nextPage() {
    if (_currentStep < _totalSteps - 1) {
      _pageController.nextPage(duration: const Duration(milliseconds: 600), curve: Curves.easeOutQuart);
      setState(() => _currentStep++);
    } else { _saveMission(); }
  }
  void _prevPage() {
    if (_currentStep > 0) {
      _pageController.previousPage(duration: const Duration(milliseconds: 600), curve: Curves.easeOutQuart);
      setState(() => _currentStep--);
    } else { Navigator.pop(context); }
  }
  Future<void> _getCurrentLocation() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
      final pos = await Geolocator.getCurrentPosition();
      final marks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
      if (marks.isNotEmpty) setState(() => _locationCtrl.text = "${marks.first.street ?? ''} ${marks.first.locality ?? ''}".trim());
    }
  }
  Future<void> _searchPlaces(String val) async {
    if (val.isEmpty) { setState(() => _predictions = []); return; }
    final res = await googlePlace.autocomplete.get(val, language: "fr", components: [Component("country", "fr")]);
    if (res?.predictions != null) setState(() => _predictions = res!.predictions!);
  }
  Future<void> _pickImage() async {
    final xfile = await ImagePicker().pickImage(source: ImageSource.gallery);
    if(xfile != null) setState(() => _photoFile = File(xfile.path));
  }

  // ---------------------------------------------------------------------------
  // WIDGETS UI HELPERS
  // ---------------------------------------------------------------------------

  Widget _buildNeonTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType type = TextInputType.text,
    int lines = 1,
    String? Function(String?)? validator,
    Widget? suffix,
    Function(String)? onChanged,
  }) {
    final bool isText = type == TextInputType.text || type == TextInputType.multiline;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: const TextStyle(color: AppTheme.textGrey, fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Container(
          decoration: AppTheme.glassBox(),
          child: TextFormField(
            controller: controller,
            keyboardType: type,
            maxLines: lines,
            onChanged: onChanged,
            textCapitalization: isText ? TextCapitalization.sentences : TextCapitalization.none,
            autocorrect: false,
            enableSuggestions: true,
            style: const TextStyle(color: AppTheme.textDark, fontSize: 16),
            cursorColor: AppTheme.neonPrimary,
            validator: validator,
            decoration: InputDecoration(
              prefixIcon: Icon(icon, color: AppTheme.neonPrimary),
              suffixIcon: suffix,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              hintText: "Entrez ici...",
              hintStyle: TextStyle(color: AppTheme.textGrey.withOpacity(0.5)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSelectionCard(String text, IconData icon, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.white.withOpacity(0.5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isSelected ? AppTheme.neonPrimary : Colors.grey.shade200, width: isSelected ? 2 : 1),
          boxShadow: isSelected ? AppTheme.coloredShadow(AppTheme.neonPrimary) : [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: isSelected ? AppTheme.neonPrimary : AppTheme.textGrey, size: 20),
            const SizedBox(width: 8),
            Text(text, style: TextStyle(color: isSelected ? AppTheme.textDark : AppTheme.textGrey, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // NOUVEAU : MENU CATÉGORIE STYLÉ
  // ---------------------------------------------------------------------------
  // ---------------------------------------------------------------------------
  // NOUVEAU MENU CATÉGORIE (Style "Image Illustrée")
  // ---------------------------------------------------------------------------
  void _showCategoryModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.75, // Un peu plus haut
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              // Barre de drag
              Container(
                width: 40, height: 5,
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10)),
              ),
              const SizedBox(height: 24),

              const Text("CHOISIR UNE CATÉGORIE",
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1.2, color: AppTheme.textGrey)
              ),
              const SizedBox(height: 24),

              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                  itemCount: _categoriesList.length,
                  separatorBuilder: (c, i) => const SizedBox(height: 20), // Plus d'espace entre les éléments
                  itemBuilder: (context, index) {
                    final category = _categoriesList[index];
                    final String name = category['name'];
                    final IconData icon = category['icon'];
                    final Color colorBg = category['color'];
                    final Color colorAccent = category['accent'];

                    final isSelected = _selectedCategory == name;

                    return InkWell(
                      onTap: () {
                        setState(() => _selectedCategory = name);
                        Navigator.pop(context);
                      },
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.all(12), // Padding interne global
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.grey.shade50 : Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: isSelected
                              ? Border.all(color: AppTheme.neonPrimary, width: 2)
                              : Border.all(color: Colors.transparent), // Bordure invisible pour garder l'alignement
                        ),
                        child: Row(
                          children: [
                            // --- LE CARRÉ ILLUSTRÉ (Comme ton image) ---
                            Container(
                              width: 64, // Taille augmentée
                              height: 64,
                              decoration: BoxDecoration(
                                color: colorBg, // Couleur de fond pastel
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Icon(icon, color: colorAccent, size: 32), // Icone colorée
                            ),

                            const SizedBox(width: 20),

                            // TEXTE
                            Expanded(
                              child: Text(
                                  name,
                                  style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.textDark
                                  )
                              ),
                            ),

                            // CHECKMARK SI SÉLECTIONNÉ
                            if (isSelected)
                              const Icon(Icons.check_circle, color: AppTheme.neonPrimary, size: 28)
                            else
                              const Icon(Icons.chevron_right, color: Colors.grey, size: 24),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // ÉTAPES DU FORMULAIRE
  // ---------------------------------------------------------------------------

  // ÉTAPE 1 : QUOI ?
  Widget _buildStep1() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FadeInSlide(delay: 0.1, child: Text("LA MISSION", style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: AppTheme.textDark))),
          const FadeInSlide(delay: 0.2, child: Text("Décrivez ce que vous voulez.", style: TextStyle(fontSize: 16, color: AppTheme.textGrey))),
          const SizedBox(height: 40),

          FadeInSlide(
            delay: 0.3,
            child: _buildNeonTextField(
              controller: _titleCtrl,
              label: "Titre de la mission",
              icon: Icons.rocket_launch_outlined,
              validator: (v) => v!.isEmpty ? "Requis" : null,
            ),
          ),
          const SizedBox(height: 24),

          const FadeInSlide(delay: 0.4, child: Text("CATÉGORIE", style: TextStyle(color: AppTheme.textGrey, fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.bold))),
          const SizedBox(height: 8),
          FadeInSlide(
            delay: 0.45,
            child: Container(
              decoration: AppTheme.glassBox(),
              child: Container(
                decoration: AppTheme.glassBox(),
                child: ListTile(
                  // AFFICHE L'ICÔNE SI UNE CATÉGORIE EST CHOISIE
                  leading: _selectedCategory != null
                      ? Icon(_getIconForCategory(_selectedCategory), color: AppTheme.neonPrimary)
                      : null,
                  title: Text(_selectedCategory ?? "Sélectionner",
                      style: TextStyle(color: _selectedCategory != null ? AppTheme.textDark : AppTheme.textGrey)),
                  trailing: const Icon(Icons.arrow_drop_down_circle, color: AppTheme.neonPrimary),
                  onTap: _showCategoryModal,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),

          FadeInSlide(
            delay: 0.5,
            child: _buildNeonTextField(
              controller: _descCtrl,
              label: "Détails & Contraintes",
              icon: Icons.notes_rounded,
              lines: 5,
              validator: (v) => v!.isEmpty ? "Détails requis" : null,
            ),
          ),
        ],
      ),
    );
  }

  // ÉTAPE 2 : COMBIEN ?
  Widget _buildStep2() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FadeInSlide(delay: 0.1, child: Text("BUDGET & TEMPS", style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: AppTheme.textDark))),
          const FadeInSlide(delay: 0.2, child: Text("Définissez les ressources.", style: TextStyle(fontSize: 16, color: AppTheme.textGrey))),
          const SizedBox(height: 40),

          Row(
            children: [
              Expanded(
                child: FadeInSlide(
                  delay: 0.3,
                  child: _buildNeonTextField(
                    controller: _durationCtrl,
                    label: "Durée (Heures)",
                    icon: Icons.timer_outlined,
                    type: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: FadeInSlide(
                  delay: 0.35,
                  child: _buildNeonTextField(
                    controller: _budgetCtrl,
                    label: "Budget (€)",
                    icon: Icons.euro_rounded,
                    type: TextInputType.number,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),

          const FadeInSlide(delay: 0.4, child: Text("PHOTO (OPTIONNEL)", style: TextStyle(color: AppTheme.textGrey, fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.bold))),
          const SizedBox(height: 12),
          FadeInSlide(
            delay: 0.45,
            child: GestureDetector(
              onTap: _pickImage,
              child: Container(
                height: 200,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.grey.shade300, width: 1),
                  image: _photoFile != null ? DecorationImage(image: FileImage(_photoFile!), fit: BoxFit.cover) : null,
                ),
                child: _photoFile == null ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.add_a_photo_outlined, color: AppTheme.neonPrimary, size: 40),
                    SizedBox(height: 8),
                    Text("Uploader une image", style: TextStyle(color: AppTheme.textGrey))
                  ],
                ) : null,
              ),
            ),
          )
        ],
      ),
    );
  }

  // ÉTAPE 3 : OÙ ?
  Widget _buildStep3() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FadeInSlide(delay: 0.1, child: Text("LOCALISATION", style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: AppTheme.textDark))),
          const FadeInSlide(delay: 0.2, child: Text("Où la mission se déroule-t-elle ?", style: TextStyle(fontSize: 16, color: AppTheme.textGrey))),
          const SizedBox(height: 40),

          FadeInSlide(
            delay: 0.3,
            child: _buildNeonTextField(
              controller: _locationCtrl,
              label: "Adresse ou Ville",
              icon: Icons.map_outlined,
              onChanged: _searchPlaces,
              suffix: IconButton(
                icon: const Icon(Icons.my_location, color: AppTheme.neonPrimary),
                onPressed: _getCurrentLocation,
              ),
            ),
          ),

          if (_predictions.isNotEmpty)
            FadeInSlide(
              delay: 0.1,
              child: Container(
                margin: const EdgeInsets.only(top: 8),
                decoration: AppTheme.glassBox(),
                child: Column(
                  children: _predictions.map((p) => ListTile(
                    title: Text(p.description ?? "", style: const TextStyle(color: AppTheme.textDark)),
                    onTap: () {
                      _locationCtrl.text = p.description ?? "";
                      setState(() => _predictions = []);
                      FocusScope.of(context).unfocus();
                    },
                  )).toList(),
                ),
              ),
            ),

          const SizedBox(height: 32),
          const FadeInSlide(delay: 0.4, child: Text("MODE", style: TextStyle(color: AppTheme.textGrey, fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.bold))),
          const SizedBox(height: 12),
          FadeInSlide(
            delay: 0.45,
            child: Wrap(
              spacing: 12,
              children: [
                _buildSelectionCard("Sur place", Icons.place, _mode == "Sur place", () => setState(() => _mode = "Sur place")),
                _buildSelectionCard("À distance", Icons.wifi, _mode == "À distance", () => setState(() => _mode = "À distance")),
              ],
            ),
          )
        ],
      ),
    );
  }

  // ÉTAPE 4 : QUAND ?
  Widget _buildStep4() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FadeInSlide(delay: 0.1, child: Text("PLANIFICATION", style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: AppTheme.textDark))),
          const FadeInSlide(delay: 0.2, child: Text("Quand êtes-vous disponible ?", style: TextStyle(fontSize: 16, color: AppTheme.textGrey))),
          const SizedBox(height: 40),

          // Calendrier Stylisé Clair
          FadeInSlide(
            delay: 0.3,
            child: Container(
              decoration: AppTheme.glassBox(),
              padding: const EdgeInsets.all(8),
              child: TableCalendar(
                locale: 'fr_FR',
                firstDay: DateTime.now(),
                lastDay: DateTime.now().add(const Duration(days: 365)),
                focusedDay: _missionDate ?? DateTime.now(),
                selectedDayPredicate: (day) => isSameDay(_missionDate, day),
                onDaySelected: (s, f) => setState(() => _missionDate = s),
                headerStyle: const HeaderStyle(
                  formatButtonVisible: false,
                  titleCentered: true,
                  titleTextStyle: TextStyle(color: AppTheme.textDark, fontWeight: FontWeight.bold, fontSize: 16),
                  leftChevronIcon: Icon(Icons.chevron_left, color: AppTheme.neonPrimary),
                  rightChevronIcon: Icon(Icons.chevron_right, color: AppTheme.neonPrimary),
                ),
                calendarStyle: const CalendarStyle(
                  defaultTextStyle: TextStyle(color: AppTheme.textDark),
                  weekendTextStyle: TextStyle(color: AppTheme.neonPrimary),
                  outsideTextStyle: TextStyle(color: Colors.grey),
                  todayDecoration: BoxDecoration(color: Color(0xFFE0E7FF), shape: BoxShape.circle),
                  selectedDecoration: BoxDecoration(color: AppTheme.neonPrimary, shape: BoxShape.circle),
                ),
                daysOfWeekStyle: const DaysOfWeekStyle(
                  weekdayStyle: TextStyle(color: AppTheme.textGrey),
                  weekendStyle: TextStyle(color: AppTheme.neonPrimary),
                ),
              ),
            ),
          ),

          const SizedBox(height: 32),
          const FadeInSlide(delay: 0.4, child: Text("HORAIRE", style: TextStyle(color: AppTheme.textGrey, fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.bold))),
          const SizedBox(height: 12),
          FadeInSlide(
            delay: 0.45,
            child: Wrap(
              spacing: 12,
              children: [
                _buildSelectionCard("Flexible", Icons.all_inclusive, _flexibility == "Flexible", () {
                  setState(() { _flexibility = "Flexible"; _missionTime = null; });
                }),
                _buildSelectionCard(
                    _missionTime?.format(context) ?? "Choisir l'heure",
                    Icons.access_time_filled,
                    _flexibility == "Fixe",
                        () async {
                      setState(() => _flexibility = "Fixe");
                      final t = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay.now(),
                          builder: (context, child) {
                            return Theme(
                              data: ThemeData.light().copyWith(
                                colorScheme: const ColorScheme.light(
                                  primary: AppTheme.neonPrimary,
                                  onPrimary: Colors.white,
                                  surface: Colors.white,
                                  onSurface: AppTheme.textDark,
                                ),
                              ),
                              child: child!,
                            );
                          }
                      );
                      if(t != null) setState(() => _missionTime = t);
                    }
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // ---------------------------------------------------------------------------
  // ---------------------------------------------------------------------------
  // BUILD PRINCIPAL
  // ---------------------------------------------------------------------------
  // ---------------------------------------------------------------------------
// BUILD PRINCIPAL
// ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final double progress = (_currentStep + 1) / _totalSteps;

    // ✅ Détection clavier fiable (même avec d'autres MediaQuery autour)
    final double keyboardInsetPx =
        WidgetsBinding.instance.platformDispatcher.views.first.viewInsets.bottom;
    final bool isKeyboardOpen = keyboardInsetPx > 0;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: AppTheme.bgLight,
        resizeToAvoidBottomInset: true,

        body: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          behavior: HitTestBehavior.translucent,
          child: SafeArea(
            top: false,
            child: Stack(
              children: [
                // --- ORBES DE FOND ---
                Positioned(
                  top: -100,
                  right: -100,
                  child: Container(
                    width: 300,
                    height: 300,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.neonPrimary.withOpacity(0.1),
                    ),
                  ).simplify(),
                ),
                Positioned(
                  bottom: 50,
                  left: -50,
                  child: Container(
                    width: 400,
                    height: 400,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.neonCyan.withOpacity(0.1),
                    ),
                  ).simplify(),
                ),
                Positioned.fill(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                    child: Container(color: Colors.transparent),
                  ),
                ),

                // --- CONTENU AVEC SAFE AREA INTERNE ---
                SafeArea(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        // HEADER
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 16,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              GestureDetector(
                                onTap: _prevPage,
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.white,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.grey.shade200,
                                        blurRadius: 10,
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.arrow_back,
                                    color: AppTheme.textDark,
                                    size: 20,
                                  ),
                                ),
                              ),
                              Text(
                                "ÉTAPE ${_currentStep + 1} / $_totalSteps",
                                style: const TextStyle(
                                  color: AppTheme.textGrey,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 2,
                                ),
                              ),
                              const SizedBox(width: 44),
                            ],
                          ),
                        ),

                        // BARRE DE PROGRESSION
                        Container(
                          height: 6,
                          width: double.infinity,
                          margin: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: progress,
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [AppTheme.neonPrimary, AppTheme.neonCyan],
                                ),
                                borderRadius: BorderRadius.circular(3),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppTheme.neonPrimary.withOpacity(0.4),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        // CONTENU (PAGEVIEW)
                        Expanded(
                          child: _loading
                              ? const Center(
                            child: CircularProgressIndicator(
                              color: AppTheme.neonPrimary,
                            ),
                          )
                              : PageView(
                            controller: _pageController,
                            physics: const NeverScrollableScrollPhysics(),
                            children: [
                              _buildStep1(),
                              _buildStep2(),
                              _buildStep3(),
                              _buildStep4(),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // BOUTON CONTINUER / PUBLIER
        bottomNavigationBar: isKeyboardOpen
            ? null
            : SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.9),
              border: Border(
                top: BorderSide(color: Colors.grey.shade200),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _submitting ? null : _nextPage,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      padding: EdgeInsets.zero,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    child: Ink(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [
                            AppTheme.neonPrimary,
                            Color(0xFF4F46E5),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow:
                        AppTheme.coloredShadow(AppTheme.neonPrimary),
                      ),
                      child: SizedBox(
                        height: 60,
                        child: Center(
                          child: _submitting
                              ? const CircularProgressIndicator(
                            color: Colors.white,
                          )
                              : Row(
                            mainAxisAlignment:
                            MainAxisAlignment.center,
                            children: [
                              Text(
                                _currentStep == _totalSteps - 1
                                    ? "PUBLIER LA MISSION"
                                    : "CONTINUER",
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  letterSpacing: 1,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(
                                Icons.arrow_forward_rounded,
                                color: Colors.white,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Helper pour retrouver l'icône d'après le nom
  IconData _getIconForCategory(String? categoryName) {
    if (categoryName == null) return Icons.category;
    final cat = _categoriesList.firstWhere(
          (element) => element['name'] == categoryName,
      orElse: () => {"icon": Icons.category},
    );
    return cat['icon'];
  }
}

extension on Widget {
  Widget simplify() => this;
}
