import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_place/google_place.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:table_calendar/table_calendar.dart';

import 'package:mamission/shared/apple_appbar.dart';

class MissionCreatePage extends StatefulWidget {
  final String? editMissionId;
  const MissionCreatePage({super.key, this.editMissionId});

  @override
  State<MissionCreatePage> createState() => _MissionCreatePageState();
}

class _MissionCreatePageState extends State<MissionCreatePage>
    with SingleTickerProviderStateMixin {
  // --- DESIGN TOKENS MAMISSION ---
  static const Color _bgGradientTop = Color(0xFF6C63FF);
  static const Color _bgGradientBottom = Color(0xFF9381FF);
  static const Color _cardBackground = Colors.white;
  static const Color _primaryText = Color(0xFF111827);
  static const Color _secondaryText = Color(0xFF6B7280);
  static const Color _accent = Color(0xFF6C63FF);
  static const Color _accentSoft = Color(0xFFB59CFF);
  static const Color _border = Color(0xFFE5E7EB);
  static const Color _chipBg = Color(0xFFF3F4F6);

  // --- ETAPES ---
  static const int _totalSteps = 4;
  final List<String> _stepTitles = const [
    "Décrire",
    "Budget",
    "Lieu",
    "Date",
  ];
  final List<String> _stepSubtitles = const [
    "Titre, catégorie, description",
    "Durée, budget, photo",
    "Adresse et mode",
    "Jour et flexibilité",
  ];
  final List<IconData> _stepIcons = const [
    Icons.notes_rounded,
    Icons.euro_rounded,
    Icons.place_rounded,
    Icons.calendar_month_rounded,
  ];

  int _currentStep = 0;

  // --- CONTROLLERS FORM ---
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _descCtrl = TextEditingController();
  final TextEditingController _budgetCtrl = TextEditingController();
  final TextEditingController _durationCtrl = TextEditingController();
  final TextEditingController _locationCtrl = TextEditingController();

  String? _selectedCategory;
  String _mode = "Sur place";
  String _flexibility = "Flexible";
  DateTime? _missionDate;
  TimeOfDay? _missionTime;

  File? _photo;
  bool _isSaving = false;
  bool _isLoadingInitialData = false;

  // --- ANIMATION ---
  late AnimationController _stepChangeController;
  late Animation<Offset> _slideAnimation;

  // --- GOOGLE PLACES ---
  late GooglePlace googlePlace;
  List<AutocompletePrediction> _predictions = [];

  // --- FORMATTER DATE ---
  final DateFormat _dateFormatter = DateFormat("d MMM yyyy", "fr_FR");

  @override
  void initState() {
    super.initState();
    initializeDateFormatting('fr_FR', null);

    _stepChangeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0.1, 0), end: Offset.zero)
            .animate(CurvedAnimation(
          parent: _stepChangeController,
          curve: Curves.easeOutCubic,
        ));

    googlePlace = GooglePlace(
      // ⚠️ garde ta clé actuelle si besoin
      "AIzaSyCXltusJoTE4wN04ETzYqLUSFRzRcX7DhY",
    );

    if (widget.editMissionId != null) {
      _loadMissionForEdit(widget.editMissionId!);
    }
  }

  @override
  void dispose() {
    _stepChangeController.dispose();
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _budgetCtrl.dispose();
    _durationCtrl.dispose();
    _locationCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  //  HELPERS UI
  // ---------------------------------------------------------------------------

  List<BoxShadow> _softShadow([double opacity = 0.08]) => [
    BoxShadow(
      color: Colors.black.withOpacity(opacity),
      blurRadius: 22,
      offset: const Offset(0, 12),
    ),
  ];

  InputDecoration _inputDecoration(
      String placeholder, {
        IconData? icon,
        Widget? trailing,
        int? maxLines,
      }) {
    return InputDecoration(
      hintText: placeholder,
      hintStyle: const TextStyle(
        color: _secondaryText,
        fontSize: 14,
      ),
      prefixIcon: icon != null
          ? Icon(icon, size: 20, color: _secondaryText)
          : null,
      suffixIcon: trailing,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 14,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: _border, width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: _border, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: _accent, width: 1.4),
      ),
    );
  }

  Widget _tip(String text) {
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 18),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lightbulb_outline,
              size: 18, color: _accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                height: 1.4,
                color: _secondaryText,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? _accent.withOpacity(0.1) : _chipBg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? _accent : Colors.transparent,
            width: 1.3,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: selected ? _accent : _secondaryText,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: selected ? _accent : _secondaryText,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  //  GOOGLE PLACE + IMAGE + PICKERS
  // ---------------------------------------------------------------------------

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    setState(() {
      _photo = File(picked.path);
    });
  }

  Future<void> _updatePredictions(String value) async {
    if (value.isEmpty) {
      setState(() => _predictions = []);
      return;
    }

    final res = await googlePlace.autocomplete.get(
      value,
      language: "fr",
      components: [Component("country", "fr")],
    );

    if (!mounted) return;
    setState(() {
      _predictions = res?.predictions ?? [];
    });
  }

  Future<void> _useCurrentLocation() async {
    final perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Autorise la localisation dans les réglages."),
        ),
      );
      return;
    }

    final pos = await Geolocator.getCurrentPosition();
    final placemarks =
    await placemarkFromCoordinates(pos.latitude, pos.longitude);

    final street = placemarks.isNotEmpty ? placemarks.first.street ?? "" : "";
    final city =
    placemarks.isNotEmpty ? placemarks.first.locality ?? "" : "";

    setState(() {
      _locationCtrl.text =
      street.isNotEmpty ? "$street, $city" : city;
      _predictions = [];
    });
  }

  Future<void> _pickDate() async {
    DateTime focusedDay = _missionDate ?? DateTime.now();
    DateTime? selected = _missionDate;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                "Choisir une date",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: _primaryText,
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 360,
                child: StatefulBuilder(
                  builder: (ctx, setModalState) {
                    return TableCalendar(
                      locale: 'fr_FR',
                      firstDay: DateTime.now(),
                      lastDay: DateTime.now().add(
                        const Duration(days: 365 * 2),
                      ),
                      focusedDay: focusedDay,
                      selectedDayPredicate: (day) =>
                          isSameDay(selected, day),
                      onDaySelected: (d, f) {
                        setModalState(() {
                          selected = d;
                          focusedDay = f;
                        });
                      },
                      onPageChanged: (f) => focusedDay = f,
                      headerStyle: const HeaderStyle(
                        formatButtonVisible: false,
                        titleCentered: true,
                      ),
                      calendarStyle: CalendarStyle(
                        selectedDecoration: const BoxDecoration(
                          color: _accent,
                          shape: BoxShape.circle,
                        ),
                        todayDecoration: BoxDecoration(
                          color: _accent.withOpacity(0.25),
                          shape: BoxShape.circle,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text(
                    "Valider",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted) return;
    if (selected != null) {
      setState(() => _missionDate = selected);
    }
  }

  Future<void> _pickTime() async {
    TimeOfDay temp = _missionTime ?? TimeOfDay.now();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final now = DateTime.now();
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                "Choisir une heure",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: _primaryText,
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 220,
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.time,
                  initialDateTime: DateTime(
                    now.year,
                    now.month,
                    now.day,
                    temp.hour,
                    temp.minute,
                  ),
                  use24hFormat: true,
                  onDateTimeChanged: (d) {
                    temp = TimeOfDay.fromDateTime(d);
                  },
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text(
                    "Valider",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted) return;
    setState(() => _missionTime = temp);
  }

  // ---------------------------------------------------------------------------
  //  FIREBASE : CHARGEMENT / SAUVEGARDE
  // ---------------------------------------------------------------------------

  Future<void> _loadMissionForEdit(String id) async {
    setState(() => _isLoadingInitialData = true);
    try {
      final doc = await FirebaseFirestore.instance
          .collection('missions')
          .doc(id)
          .get();

      if (!doc.exists) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Mission introuvable ou supprimée."),
          ),
        );
        setState(() => _isLoadingInitialData = false);
        return;
      }

      final data = doc.data()!;
      if (!mounted) return;

      setState(() {
        _titleCtrl.text = data['title'] ?? '';
        _descCtrl.text = data['description'] ?? '';
        _budgetCtrl.text =
            (data['budget'] ?? '').toString();
        _durationCtrl.text =
            (data['duration'] ?? '').toString();
        _locationCtrl.text = data['location'] ?? '';
        _selectedCategory = data['category'];
        _mode = data['mode'] ?? 'Sur place';
        _flexibility = data['flexibility'] ?? 'Flexible';
        if (data['deadline'] != null) {
          _missionDate = (data['deadline'] as Timestamp).toDate();
        }
        if (data['missionTime'] != null) {
          final parts = (data['missionTime'] as String).split(':');
          if (parts.length == 2) {
            _missionTime = TimeOfDay(
              hour: int.tryParse(parts[0]) ?? 0,
              minute: int.tryParse(parts[1]) ?? 0,
            );
          }
        }
        _isLoadingInitialData = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingInitialData = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Erreur de chargement : $e")),
      );
    }
  }

  bool _isStepValid(int step) {
    switch (step) {
      case 0:
        return _titleCtrl.text.trim().isNotEmpty &&
            _descCtrl.text.trim().isNotEmpty &&
            _selectedCategory != null;
      case 1:
        final d = double.tryParse(_durationCtrl.text);
        final b = double.tryParse(_budgetCtrl.text);
        return d != null && d > 0 && b != null && b > 0;
      case 2:
        return _locationCtrl.text.trim().isNotEmpty;
      case 3:
        return _missionDate != null;
      default:
        return false;
    }
  }

  Future<void> _saveMission() async {
    if (!_isStepValid(_currentStep)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
          Text("Complète cette étape avant de continuer."),
        ),
      );
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception("Utilisateur non connecté");
      }

      // upload photo si besoin
      String? photoUrl;
      if (_photo != null) {
        final ref = FirebaseStorage.instance
            .ref()
            .child("missions/${DateTime.now().millisecondsSinceEpoch}.jpg");
        await ref.putFile(_photo!);
        photoUrl = await ref.getDownloadURL();
      }

      // localisation -> lat/lng
      double? lat;
      double? lng;
      if (_locationCtrl.text.trim().isNotEmpty) {
        try {
          final locations =
          await locationFromAddress(_locationCtrl.text.trim());
          if (locations.isNotEmpty) {
            lat = locations.first.latitude;
            lng = locations.first.longitude;
          }
        } catch (_) {
          // on ignore une erreur de geocoding
        }
      }

      // user profile
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final userData = userDoc.data() ?? {};

      final missionsRef =
      FirebaseFirestore.instance.collection('missions');

      final String? missionTimeString = _missionTime != null
          ? "${_missionTime!.hour.toString().padLeft(2, '0')}:${_missionTime!.minute.toString().padLeft(2, '0')}"
          : null;

      final baseData = {
        "title": _titleCtrl.text.trim(),
        "description": _descCtrl.text.trim(),
        "duration": double.tryParse(_durationCtrl.text),
        "budget": double.tryParse(_budgetCtrl.text) ?? 0,
        "photoUrl": photoUrl,
        "posterId": user.uid,
        "category": _selectedCategory,
        "posterName": userData['name'] ?? "",
        "posterPhotoUrl": userData['photoUrl'] ?? "",
        "posterRating": userData['rating'] ?? 0,
        "posterReviewsCount": userData['reviewsCount'] ?? 0,
        "position": lat != null && lng != null
            ? {"lat": lat, "lng": lng}
            : {},
        "location": _locationCtrl.text.trim(),
        "mode": _mode,
        "flexibility": _flexibility,
        "deadline": _missionDate != null
            ? Timestamp.fromDate(_missionDate!)
            : null,
        "missionTime": missionTimeString,
      };

      if (widget.editMissionId != null) {
        await missionsRef.doc(widget.editMissionId!).update({
          ...baseData,
          "updatedAt": FieldValue.serverTimestamp(),
        });

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Mission mise à jour ✅"),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        await missionsRef.add({
          ...baseData,
          "status": "open",
          "offersCount": 0,
          "createdAt": FieldValue.serverTimestamp(),
        });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Mission publiée avec succès ✅"),
            backgroundColor: Colors.green,
          ),
        );
      }

      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Erreur : $e")),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ---------------------------------------------------------------------------
  //  NAV ET CONFIRMATION SORTIE
  // ---------------------------------------------------------------------------

  Future<bool> _confirmExit() async {
    final hasData = _titleCtrl.text.isNotEmpty ||
        _descCtrl.text.isNotEmpty ||
        _selectedCategory != null ||
        _budgetCtrl.text.isNotEmpty ||
        _durationCtrl.text.isNotEmpty ||
        _locationCtrl.text.isNotEmpty;

    if (!hasData) return true;

    final result = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text("Quitter la création ?"),
        content: const Text(
          "Les informations non enregistrées seront perdues.",
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text("Continuer"),
            onPressed: () => Navigator.pop(ctx, false),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text("Quitter"),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    ) ??
        false;

    return result;
  }

  void _goToStep(int index) {
    if (index == _currentStep) return;
    setState(() {
      _currentStep = index;
      _stepChangeController
        ..reset()
        ..forward();
    });
  }

  void _nextStepOrSave() {
    if (!_isStepValid(_currentStep)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
          Text("Complète cette étape pour continuer."),
        ),
      );
      return;
    }
    if (_currentStep == _totalSteps - 1) {
      _saveMission();
    } else {
      _goToStep(_currentStep + 1);
    }
  }

  void _previousStep() {
    if (_currentStep == 0) return;
    _goToStep(_currentStep - 1);
  }

  // ---------------------------------------------------------------------------
  //  HEADER / STEPPER / APERCU
  // ---------------------------------------------------------------------------

  Widget _buildVerticalStepper() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(_totalSteps, (index) {
        final bool isActive = index == _currentStep;
        final bool isPast = index < _currentStep;

        final Color dotColor =
        isActive || isPast ? _accent : _border;
        final Color lineColor = isPast ? _accent : _border;

        return InkWell(
          onTap: () => _goToStep(index),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: isActive
                            ? _accent
                            : Colors.white,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: dotColor,
                          width: 2,
                        ),
                      ),
                      child: Icon(
                        _stepIcons[index],
                        size: 12,
                        color: isActive
                            ? Colors.white
                            : dotColor,
                      ),
                    ),
                    if (index != _totalSteps - 1)
                      Container(
                        width: 2,
                        height: 32,
                        margin: const EdgeInsets.only(top: 2),
                        decoration: BoxDecoration(
                          color: lineColor,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Étape ${index + 1}",
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isActive || isPast
                                ? _accent
                                : _secondaryText,
                          ),
                        ),
                        Text(
                          _stepTitles[index],
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight:
                            isActive ? FontWeight.w700 : FontWeight.w600,
                            color: _primaryText,
                          ),
                        ),
                        Text(
                          _stepSubtitles[index],
                          style: const TextStyle(
                            fontSize: 12,
                            color: _secondaryText,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _buildRecapMiniCard() {
    final String titlePreview = _titleCtrl.text.trim().isEmpty
        ? "Titre de votre mission"
        : _titleCtrl.text.trim();

    final String catPreview =
        _selectedCategory ?? "Catégorie";
    final String budgetPreview = _budgetCtrl.text.trim().isEmpty
        ? "Budget à définir"
        : "${_budgetCtrl.text.trim()} €";
    final String locationPreview = _locationCtrl.text.trim().isEmpty
        ? "Lieu à préciser"
        : _locationCtrl.text.trim();
    final String datePreview = _missionDate != null
        ? _dateFormatter.format(_missionDate!)
        : "Date à définir";

    String timePreview;
    if (_flexibility == "Fixe" && _missionTime != null) {
      timePreview = _missionTime!.format(context);
    } else if (_flexibility == "Flexible") {
      timePreview = "Horaire flexible";
    } else {
      timePreview = "Horaire à préciser";
    }

    return Container(
      margin: const EdgeInsets.only(top: 18),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF171717),
        borderRadius: BorderRadius.circular(18),
        boxShadow: _softShadow(0.2),
        gradient: const LinearGradient(
          colors: [
            Color(0xFF1F2933),
            Color(0xFF111827),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.visibility_rounded,
            color: Colors.white70,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Aperçu en temps réel",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  titlePreview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    _recapPill(Icons.category, catPreview),
                    _recapPill(Icons.euro, budgetPreview),
                    _recapPill(Icons.place, locationPreview),
                    _recapPill(Icons.calendar_today, datePreview),
                    _recapPill(Icons.access_time, timePreview),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _recapPill(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.white70),
          const SizedBox(width: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  //  CONTENU DES ETAPES
  // ---------------------------------------------------------------------------

  Widget _step1Content() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Décrire la mission",
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: _primaryText,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          "Explique simplement ce dont tu as besoin.",
          style: TextStyle(fontSize: 13, color: _secondaryText),
        ),
        _tip(
          "Un titre clair et une description précise aident les prestataires "
              "à comprendre rapidement la mission.",
        ),
        TextFormField(
          controller: _titleCtrl,
          decoration: _inputDecoration(
            "Titre (ex : Monter un meuble IKEA)",
            icon: Icons.work_outline_rounded,
          ),
          onChanged: (_) => setState(() {}),
          validator: (v) =>
          v == null || v.trim().isEmpty ? "Le titre est requis" : null,
        ),
        const SizedBox(height: 14),
        GestureDetector(
          onTap: _openCategoryPicker,
          child: AbsorbPointer(
            child: TextFormField(
              decoration: _inputDecoration(
                "Catégorie",
                icon: Icons.category_outlined,
                trailing: const Icon(Icons.expand_more_rounded,
                    color: _secondaryText),
              ),
              controller: TextEditingController(
                text: _selectedCategory ?? "",
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: _descCtrl,
          maxLines: 4,
          decoration: _inputDecoration(
            "Description (détails, contraintes, matériel fourni…)",
            icon: Icons.description_outlined,
          ),
          onChanged: (_) => setState(() {}),
          validator: (v) => v == null || v.trim().isEmpty
              ? "La description est requise"
              : null,
        ),
      ],
    );
  }

  Widget _step2Content() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Budget & durée",
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: _primaryText,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          "Indique une durée réaliste et un budget cohérent.",
          style: TextStyle(fontSize: 13, color: _secondaryText),
        ),
        _tip(
          "Un budget clair évite les malentendus et attire des prestataires sérieux.",
        ),
        TextFormField(
          controller: _durationCtrl,
          keyboardType:
          const TextInputType.numberWithOptions(decimal: true),
          decoration: _inputDecoration(
            "Durée estimée (en heures)",
            icon: Icons.hourglass_bottom_rounded,
          ),
          onChanged: (_) => setState(() {}),
          validator: (v) {
            if (v == null || v.trim().isEmpty) {
              return "La durée est requise";
            }
            final d = double.tryParse(v);
            if (d == null || d <= 0) {
              return "Indique une durée valide";
            }
            return null;
          },
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: _budgetCtrl,
          keyboardType:
          const TextInputType.numberWithOptions(decimal: true),
          decoration: _inputDecoration(
            "Budget proposé (€)",
            icon: Icons.euro_symbol_rounded,
          ),
          onChanged: (_) => setState(() {}),
          validator: (v) {
            if (v == null || v.trim().isEmpty) {
              return "Le budget est requis";
            }
            final b = double.tryParse(v);
            if (b == null || b <= 0) {
              return "Indique un montant valide";
            }
            return null;
          },
        ),
        const SizedBox(height: 22),
        const Text(
          "Photo (optionnel)",
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: _primaryText,
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _pickImage,
          child: Container(
            height: 170,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              color: const Color(0xFFF3F4F6),
              border: Border.all(color: _border),
              image: _photo != null
                  ? DecorationImage(
                image: FileImage(_photo!),
                fit: BoxFit.cover,
                colorFilter: ColorFilter.mode(
                  Colors.black.withOpacity(0.3),
                  BlendMode.darken,
                ),
              )
                  : null,
            ),
            child: _photo == null
                ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(
                  Icons.add_a_photo_outlined,
                  color: _accent,
                  size: 28,
                ),
                SizedBox(height: 6),
                Text(
                  "Ajouter une photo",
                  style: TextStyle(
                    color: _primaryText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  "Optionnel, mais souvent utile",
                  style: TextStyle(
                    color: _secondaryText,
                    fontSize: 12,
                  ),
                ),
              ],
            )
                : const Center(
              child: Icon(
                Icons.edit_outlined,
                color: Colors.white,
                size: 40,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _step3Content() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Lieu & modalité",
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: _primaryText,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          "Précise la ville ou l’adresse.",
          style: TextStyle(fontSize: 13, color: _secondaryText),
        ),
        _tip(
          "MaMission met en avant les prestations proches : une localisation précise "
              "augmente tes chances de recevoir des offres.",
        ),
        TextFormField(
          controller: _locationCtrl,
          decoration: _inputDecoration(
            "Localisation (ville ou adresse)",
            icon: Icons.place_outlined,
            trailing: IconButton(
              onPressed: _useCurrentLocation,
              icon: const Icon(
                Icons.my_location_rounded,
                color: _accent,
              ),
            ),
          ),
          onChanged: (value) {
            _updatePredictions(value);
            setState(() {});
          },
          validator: (v) =>
          v == null || v.trim().isEmpty ? "La localisation est requise" : null,
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: _predictions.isNotEmpty
              ? Container(
            key: const ValueKey("predictions"),
            margin: const EdgeInsets.only(top: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: _softShadow(0.06),
            ),
            child: ListView.builder(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _predictions.length,
              itemBuilder: (context, index) {
                final p = _predictions[index];
                return ListTile(
                  leading: const Icon(
                    Icons.location_on_outlined,
                    color: _accent,
                  ),
                  title: Text(p.description ?? ""),
                  onTap: () {
                    setState(() {
                      _locationCtrl.text = p.description ?? "";
                      _predictions = [];
                    });
                    FocusScope.of(context).unfocus();
                  },
                );
              },
            ),
          )
              : const SizedBox.shrink(),
        ),
        const SizedBox(height: 22),
        const Text(
          "Mode d’exécution",
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: _primaryText,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          children: [
            _chip(
              label: "Sur place",
              icon: Icons.location_on_outlined,
              selected: _mode == "Sur place",
              onTap: () => setState(() => _mode = "Sur place"),
            ),
            _chip(
              label: "À distance",
              icon: Icons.computer_rounded,
              selected: _mode == "À distance",
              onTap: () => setState(() => _mode = "À distance"),
            ),
          ],
        ),
      ],
    );
  }

  Widget _step4Content() {
    final String dateLabel = _missionDate != null
        ? _dateFormatter.format(_missionDate!)
        : "Choisir une date";
    final String timeLabel = _missionTime != null
        ? _missionTime!.format(context)
        : "Choisir une heure";

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Date & flexibilité",
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: _primaryText,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          "Plus tu es flexible, plus tu reçois d’offres.",
          style: TextStyle(fontSize: 13, color: _secondaryText),
        ),
        _tip(
          "Les prestataires peuvent adapter leur agenda si tu indiques une flexibilité horaire.",
        ),
        GestureDetector(
          onTap: _pickDate,
          child: AbsorbPointer(
            child: TextFormField(
              decoration: _inputDecoration(
                "Date souhaitée",
                icon: Icons.calendar_today_rounded,
              ),
              controller: TextEditingController(text: dateLabel),
            ),
          ),
        ),
        const SizedBox(height: 22),
        const Text(
          "Flexibilité horaire",
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: _primaryText,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          children: [
            _chip(
              label: "Flexible",
              icon: Icons.watch_later_outlined,
              selected: _flexibility == "Flexible",
              onTap: () {
                setState(() {
                  _flexibility = "Flexible";
                  _missionTime = null;
                });
              },
            ),
            _chip(
              label: "Fixe",
              icon: Icons.access_time_filled_rounded,
              selected: _flexibility == "Fixe",
              onTap: () async {
                setState(() => _flexibility = "Fixe");
                if (_missionTime == null) {
                  await _pickTime();
                }
              },
            ),
          ],
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeInOutCubic,
          child: _flexibility == "Fixe"
              ? Padding(
            padding: const EdgeInsets.only(top: 16.0),
            child: GestureDetector(
              onTap: _pickTime,
              child: AbsorbPointer(
                child: TextFormField(
                  decoration: _inputDecoration(
                    "Heure de la mission",
                    icon: Icons.access_time_rounded,
                  ),
                  controller: TextEditingController(
                    text: timeLabel,
                  ),
                ),
              ),
            ),
          )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildStepBody() {
    Widget content;
    switch (_currentStep) {
      case 0:
        content = _step1Content();
        break;
      case 1:
        content = _step2Content();
        break;
      case 2:
        content = _step3Content();
        break;
      case 3:
      default:
        content = _step4Content();
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: _slideAnimation,
            child: child,
          ),
        );
      },
      child: Form(
        key: _formKey,
        child: content,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  //  BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final bool isLastStep = _currentStep == _totalSteps - 1;
    final bool canProceed = _isStepValid(_currentStep);

    return WillPopScope(
      onWillPop: () async {
        final ok = await _confirmExit();
        return ok;
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: buildAppleMissionAppBar(
          title: widget.editMissionId != null
              ? "Modifier la mission"
              : "Créer une mission",
          leading: IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () async {
              final ok = await _confirmExit();
              if (ok && mounted) Navigator.pop(context);
            },
          ),
        ),
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [_bgGradientTop, _bgGradientBottom],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: SafeArea(
            top: false,
            child: _isLoadingInitialData
                ? const Center(
              child: CircularProgressIndicator(
                color: Colors.white,
              ),
            )
                : LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight - 40,
                    ),
                    child: Column(
                      children: [
                        // CARTE PRINCIPALE
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: _cardBackground,
                            borderRadius: BorderRadius.circular(26),
                            boxShadow: _softShadow(),
                          ),
                          child: Column(
                            crossAxisAlignment:
                            CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment:
                                CrossAxisAlignment.start,
                                children: [
                                  // STEPPER VERTICAL
                                  SizedBox(
                                    width: 130,
                                    child: _buildVerticalStepper(),
                                  ),
                                  const SizedBox(width: 18),
                                  // CONTENU ETAPE
                                  Expanded(
                                    child: _buildStepBody(),
                                  ),
                                ],
                              ),
                              _buildRecapMiniCard(),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        // BARRE DE NAVIGATION
                        Container(
                          padding:
                          const EdgeInsets.symmetric(horizontal: 8),
                          child: Row(
                            children: [
                              if (_currentStep > 0)
                                SizedBox(
                                  height: 52,
                                  width: 52,
                                  child: OutlinedButton(
                                    onPressed:
                                    _isSaving ? null : _previousStep,
                                    style: OutlinedButton.styleFrom(
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                        BorderRadius.circular(16),
                                      ),
                                      side: const BorderSide(
                                        color: Colors.white70,
                                      ),
                                      backgroundColor:
                                      Colors.white.withOpacity(0.05),
                                    ),
                                    child: const Icon(
                                      Icons.arrow_back_ios_new_rounded,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                  ),
                                ),
                              if (_currentStep > 0)
                                const SizedBox(width: 12),
                              Expanded(
                                child: SizedBox(
                                  height: 52,
                                  child: ElevatedButton(
                                    onPressed: !_isSaving &&
                                        (canProceed || isLastStep)
                                        ? _nextStepOrSave
                                        : _nextStepOrSave,
                                    style: ElevatedButton.styleFrom(
                                      elevation: canProceed ? 8 : 0,
                                      backgroundColor: canProceed
                                          ? Colors.white
                                          : Colors.white.withOpacity(0.6),
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                        BorderRadius.circular(18),
                                      ),
                                    ),
                                    child: _isSaving
                                        ? const SizedBox(
                                      height: 22,
                                      width: 22,
                                      child:
                                      CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                        AlwaysStoppedAnimation<
                                            Color>(_accent),
                                      ),
                                    )
                                        : Row(
                                      mainAxisAlignment:
                                      MainAxisAlignment.center,
                                      mainAxisSize:
                                      MainAxisSize.min,
                                      children: [
                                        Text(
                                          isLastStep
                                              ? (widget.editMissionId !=
                                              null
                                              ? "Enregistrer la mission"
                                              : "Publier la mission")
                                              : "Étape suivante",
                                          style: const TextStyle(
                                            color: _accent,
                                            fontWeight:
                                            FontWeight.w800,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Icon(
                                          isLastStep
                                              ? Icons
                                              .check_circle_outline_rounded
                                              : Icons
                                              .arrow_forward_ios_rounded,
                                          size: 18,
                                          color: _accent,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  //  CATEGORY PICKER
  // ---------------------------------------------------------------------------

  static const Map<String, IconData> _categories = {
    "Maison & Bricolage": Icons.home_repair_service_outlined,
    "Déménagement & Transport": Icons.local_shipping_outlined,
    "Ménage & Aide à domicile": Icons.cleaning_services_outlined,
    "Jardinage & Extérieur": Icons.yard_outlined,
    "Informatique & High-tech": Icons.laptop_chromebook_outlined,
    "Événementiel & Service": Icons.celebration_outlined,
    "Cours & Aide scolaire": Icons.school_outlined,
  };

  Future<void> _openCategoryPicker() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                "Choisir une catégorie",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: _primaryText,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 380,
                child: ListView.separated(
                  itemCount: _categories.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, index) {
                    final name = _categories.keys.elementAt(index);
                    final icon = _categories.values.elementAt(index);
                    final selected = _selectedCategory == name;
                    return ListTile(
                      leading: Icon(
                        icon,
                        color: selected ? _accent : _primaryText,
                      ),
                      title: Text(
                        name,
                        style: TextStyle(
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: selected ? _accent : _primaryText,
                        ),
                      ),
                      trailing: selected
                          ? const Icon(Icons.check_circle_rounded,
                          color: _accent)
                          : null,
                      onTap: () {
                        setState(() => _selectedCategory = name);
                        Navigator.pop(ctx);
                      },
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
}
