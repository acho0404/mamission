import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_place/google_place.dart';
import 'package:image_picker/image_picker.dart';

class MissionCreatePage extends StatefulWidget {
  const MissionCreatePage({super.key});

  @override
  State<MissionCreatePage> createState() => _MissionCreatePageState();
}

class _MissionCreatePageState extends State<MissionCreatePage> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _budgetCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();

  File? _photo;
  bool _loading = false;
  DateTime? _missionDate;
  TimeOfDay? _missionTime;

  String _mode = "Sur place";
  String _flexibility = "Flexible";

  late GooglePlace googlePlace;
  List<AutocompletePrediction> _predictions = [];

  static const Color _backgroundColor = Color(0xFFF4F6FA);
  static const Color _primaryColor = Color(0xFF2D2F41);
  static const Color _accentColor = Color(0xFF8A7FFC);
  static const Color _textColor = Color(0xFF2D2F41);
  static const Color _secondaryTextColor = Color(0xFF6A707C);
  static const Color _borderColor = Color(0xFFE0E5F0);

  @override
  void initState() {
    super.initState();
    googlePlace = GooglePlace("VOTRE_CLE_API_GOOGLE_MAPS");
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) setState(() => _photo = File(picked.path));
  }

  Future<void> _getCurrentLocation() async {
    final perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Autorisez la localisation pour continuer")),
      );
      return;
    }
    final pos = await Geolocator.getCurrentPosition();
    final placemarks =
    await placemarkFromCoordinates(pos.latitude, pos.longitude);
    final city = placemarks.isNotEmpty ? placemarks.first.locality ?? "" : "";
    setState(() => _locationCtrl.text = city);
  }

  Future<void> _onSearchChanged(String value) async {
    if (value.isEmpty) {
      setState(() => _predictions = []);
      return;
    }
    final result = await googlePlace.autocomplete.get(value, language: "fr");
    if (result != null && result.predictions != null) {
      setState(() => _predictions = result.predictions!);
    }
  }

  Future<void> _saveMission() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception("Utilisateur non connecté");

      String photoUrl = "";
      if (_photo != null) {
        final ref = FirebaseStorage.instance
            .ref()
            .child("missions/${DateTime.now().millisecondsSinceEpoch}.jpg");
        await ref.putFile(_photo!);
        photoUrl = await ref.getDownloadURL();
      }

      double? lat;
      double? lng;
      if (_locationCtrl.text.isNotEmpty) {
        final locs = await locationFromAddress(_locationCtrl.text);
        if (locs.isNotEmpty) {
          lat = locs.first.latitude;
          lng = locs.first.longitude;
        }
      }

      final userDoc =
      await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final userData = userDoc.data() ?? {};

      await FirebaseFirestore.instance.collection('missions').add({
        "title": _titleCtrl.text.trim(),
        "description": _descCtrl.text.trim(),
        "budget": double.tryParse(_budgetCtrl.text) ?? 0,
        "photoUrl": photoUrl,
        "posterId": user.uid,
        "posterName": userData['name'] ?? "",
        "posterPhotoUrl": userData['photoUrl'] ?? "",
        "posterRating": userData['rating'] ?? 0,
        "posterReviewsCount": userData['reviewsCount'] ?? 0,
        "position": lat != null && lng != null ? {"lat": lat, "lng": lng} : {},
        "location": _locationCtrl.text.trim(),
        "mode": _mode,
        "flexibility": _flexibility,
        "deadline":
        _missionDate != null ? Timestamp.fromDate(_missionDate!) : null,
        "missionTime": _missionTime != null
            ? "${_missionTime!.hour}:${_missionTime!.minute.toString().padLeft(2, '0')}"
            : null,
        "status": "open",
        "offersCount": 0,
        "createdAt": FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Mission publiée avec succès ✅")),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erreur: ${e.toString()}")),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  InputDecoration _buildInputDecoration(String label, IconData icon,
      {Widget? suffixIcon}) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: _secondaryTextColor),
      floatingLabelStyle: const TextStyle(color: _accentColor),
      prefixIcon: Icon(icon, color: _secondaryTextColor, size: 20),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: _borderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: _borderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: _accentColor, width: 2),
      ),
    );
  }

  Widget _buildStyledChip({
    required String label,
    required IconData icon,
    required bool isSelected,
    required ValueChanged<bool> onSelected,
  }) {
    return ChoiceChip(
      showCheckmark: false,
      label: Text(label),
      selected: isSelected,
      onSelected: onSelected,
      backgroundColor: Colors.white,
      selectedColor: _accentColor.withOpacity(0.1),
      avatar: Icon(icon,
          size: 18, color: isSelected ? _accentColor : _secondaryTextColor),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected ? _accentColor : _borderColor,
          width: isSelected ? 1.5 : 1.0,
        ),
      ),
    );
  }

  List<BoxShadow> _elegantShadow() => [
    BoxShadow(
      color: const Color(0xFF5A6B8B).withOpacity(0.04),
      blurRadius: 20,
      spreadRadius: 1,
      offset: const Offset(0, 10),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        } else {
          Navigator.pushNamed(context, '/missions');
        }
        return false;
      },
      child: Scaffold(
        backgroundColor: _backgroundColor,
        appBar: AppBar(
          backgroundColor: _accentColor,
          elevation: 0,
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () {
              if (Navigator.canPop(context)) {
                Navigator.pop(context);
              } else {
                Navigator.pushNamed(context, '/missions');
              }
            },
          ),
          title: const Text(
            "Créer une mission",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: _accentColor))
            : SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Détails de la mission",
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _titleCtrl,
                  decoration: _buildInputDecoration(
                      "Titre de la mission", Icons.work_outline),
                  validator: (v) =>
                  v == null || v.isEmpty ? "Le titre est requis" : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _descCtrl,
                  maxLines: 4,
                  decoration: _buildInputDecoration(
                      "Description", Icons.description_outlined),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _budgetCtrl,
                  keyboardType: TextInputType.number,
                  decoration: _buildInputDecoration(
                      "Budget (€)", Icons.euro_symbol),
                ),
                const SizedBox(height: 24),

                const Text("Lieu et date",
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _locationCtrl,
                  decoration: _buildInputDecoration(
                    "Localisation (ville ou adresse)",
                    Icons.place_outlined,
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.my_location,
                          color: _accentColor),
                      onPressed: _getCurrentLocation,
                    ),
                  ),
                  onChanged: _onSearchChanged,
                ),

                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.only(top: 8),
                  child: _predictions.isNotEmpty
                      ? Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: _elegantShadow(),
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _predictions.length,
                      itemBuilder: (context, i) {
                        final p = _predictions[i];
                        return ListTile(
                          leading: const Icon(
                              Icons.location_on_outlined,
                              color: _accentColor),
                          title: Text(p.description ?? ""),
                          onTap: () {
                            _locationCtrl.text =
                                p.description ?? "";
                            setState(() => _predictions = []);
                            FocusScope.of(context).unfocus();
                          },
                        );
                      },
                    ),
                  )
                      : const SizedBox.shrink(),
                ),
                const SizedBox(height: 16),
                InkWell(
                  onTap: () async {
                    final now = DateTime.now();
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _missionDate ?? now,
                      firstDate: now,
                      lastDate: DateTime(now.year + 1),
                      builder: (context, child) {
                        return Theme(
                          data: Theme.of(context).copyWith(
                            colorScheme: const ColorScheme.light(
                              primary: _accentColor,
                              onPrimary: Colors.white,
                            ),
                          ),
                          child: child!,
                        );
                      },
                    );
                    if (picked != null) {
                      setState(() => _missionDate = picked);
                    }
                  },
                  child: InputDecorator(
                    decoration: _buildInputDecoration(
                        "Date de la mission",
                        Icons.calendar_today_outlined),
                    child: Text(
                      _missionDate != null
                          ? "${_missionDate!.day}/${_missionDate!.month}/${_missionDate!.year}"
                          : "Choisir une date",
                      style: TextStyle(
                          color: _missionDate != null
                              ? _textColor
                              : _secondaryTextColor),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                const Text("Modalités",
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  children: [
                    _buildStyledChip(
                      label: "Sur place",
                      icon: Icons.location_on_outlined,
                      isSelected: _mode == "Sur place",
                      onSelected: (s) =>
                          setState(() => _mode = "Sur place"),
                    ),
                    _buildStyledChip(
                      label: "À distance",
                      icon: Icons.computer_outlined,
                      isSelected: _mode == "À distance",
                      onSelected: (s) =>
                          setState(() => _mode = "À distance"),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  children: [
                    _buildStyledChip(
                      label: "Flexible",
                      icon: Icons.watch_later_outlined,
                      isSelected: _flexibility == "Flexible",
                      onSelected: (s) {
                        setState(() {
                          _flexibility = "Flexible";
                          _missionTime = null;
                        });
                      },
                    ),
                    _buildStyledChip(
                      label: "Fixe",
                      icon: Icons.access_time_filled_outlined,
                      isSelected: _flexibility == "Fixe",
                      onSelected: (s) async {
                        setState(() => _flexibility = "Fixe");
                        final t = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay.now(),
                        );
                        if (t != null) {
                          setState(() => _missionTime = t);
                        } else {
                          setState(() => _flexibility = "Flexible");
                        }
                      },
                    ),
                  ],
                ),
                if (_flexibility == "Fixe" && _missionTime != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      "Heure choisie : ${_missionTime!.format(context)}",
                      style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: _primaryColor),
                    ),
                  ),
                const SizedBox(height: 24),

                const Text("Photo (Optionnel)",
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                InkWell(
                  onTap: _pickImage,
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    height: 180,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _borderColor),
                      image: _photo != null
                          ? DecorationImage(
                        image: FileImage(_photo!),
                        fit: BoxFit.cover,
                        colorFilter: ColorFilter.mode(
                            Colors.black.withOpacity(0.3),
                            BlendMode.darken),
                      )
                          : null,
                      color: _backgroundColor,
                    ),
                    child: _photo == null
                        ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_a_photo_outlined,
                              color: _accentColor, size: 30),
                          SizedBox(height: 8),
                          Text("Ajouter une photo",
                              style: TextStyle(
                                  color: _textColor,
                                  fontWeight: FontWeight.w600))
                        ],
                      ),
                    )
                        : const Center(
                      child: Icon(Icons.edit_outlined,
                          color: Colors.white, size: 48),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _saveMission,
                    icon: const Icon(Icons.check_circle_outline,
                        color: Colors.white),
                    label: const Text(
                      "Publier la mission",
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 16),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accentColor,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
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
}
