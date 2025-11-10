// lib/features/explore/explore_page.dart
//
// MaMission - Explore Page
// - Conserve la dernière caméra (GPS / recherche / déplacements) -> plus de reset sur Paris
// - Marqueurs missions avec icône custom (assets/icons/mission_marker.png) + fallback violet
// - Tap sur un marqueur mission -> affiche un popup (titre + prix)
// - Tap sur le popup -> push vers /missions/:id via GoRouter
// - Layout fidèle au screenshot : AppBar violette, recherche arrondie, carte en haut, liste en bas
//
// Dépendances :
//   google_maps_flutter, google_place, geolocator, cloud_firestore, go_router, shared_preferences
//
// IMPORTANT : place l’icône ici : assets/icons/mission_marker.png
// Puis: flutter clean && flutter pub get
//
// ------------------------------------------------------------------------------

import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_place/google_place.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'dart:ui' as ui; // ✅ pour les outils d’image (instantiateImageCodec, ImageByteFormat)
import 'package:mamission/shared/widgets/status_badge.dart';

import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter/animation.dart';
import 'package:mamission/shared/widgets/card_mission.dart';


// --- Helper pour charger et redimensionner un PNG avec animation smooth ---
Future<BitmapDescriptor> loadMarkerIcon(String path, {int targetWidth = 96}) async {
  final byteData = await rootBundle.load(path);
  final codec = await ui.instantiateImageCodec(
    byteData.buffer.asUint8List(),
    targetWidth: targetWidth,
  );
  final frame = await codec.getNextFrame();
  final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
  return BitmapDescriptor.fromBytes(data!.buffer.asUint8List());
}

class ExplorePage extends StatefulWidget {
  const ExplorePage({super.key});

  @override
  State<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends State<ExplorePage> with TickerProviderStateMixin {
  // --- Maps / Camera -------------------------------------------------------------------------
  bool _mapReady = false;
  final Completer<GoogleMapController> _controller = Completer();
  CameraPosition? _lastCamera; // cam recente (persistée)
  static const LatLng _kParisLatLng = LatLng(48.8566, 2.3522);
  static const CameraPosition _kParisCam = CameraPosition(target: _kParisLatLng, zoom: 12);
  bool _mapControllerReady = false;

  Future<GoogleMapController> _waitForMapController() async {
    if (_mapControllerReady) return _controller.future;
    for (int i = 0; i < 10; i++) {
      try {
        final ctl = await _controller.future;
        await ctl.getZoomLevel(); // ping
        _mapControllerReady = true;
        return ctl;
      } catch (_) {
        await Future.delayed(const Duration(milliseconds: 300));
      }
    }
    throw 'Carte Google Maps non initialisée';
  }
  // Markers (missions + user)
  final ValueNotifier<Set<Marker>> _markers = ValueNotifier(<Marker>{});
  LatLng? _me;
  Marker? _meMarker;

  // Icônes custom
  BitmapDescriptor? _iconMission;
  BitmapDescriptor? _iconUser;

  // --- UI state ------------------------------------------------------------------------------
  final ValueNotifier<bool> _loadingMissions = ValueNotifier(true);
  final ValueNotifier<bool> _loadingLocation = ValueNotifier(false);
  final ValueNotifier<bool> _isMapFullScreen = ValueNotifier(false);
  final ValueNotifier<String> _error = ValueNotifier('');

  // --- Google Places / Search ----------------------------------------------------------------
  late final GooglePlace _places;
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final ValueNotifier<List<AutocompletePrediction>> _suggestions = ValueNotifier([]);

  // --- Firestore -----------------------------------------------------------------------------
  final ValueNotifier<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _missions =
  ValueNotifier([]);

  // --- Popup mission sélectionnée -------------------------------------------------------------
  String? _selectedMissionId;
  Map<String, dynamic>? _selectedMission;
  Timer? _popupAutoHideTimer;
  late final AnimationController _popupCtrl;
  late final Animation<double> _popupScale;

  // --- API KEY (Places) -----------------------------------------------------------------------
  static const String kPlacesApiKey = "AIzaSyCXltusJoTE4wN04ETzYqLUSFRzRcX7DhY";

  @override
  void initState() {
    super.initState();
    _places = GooglePlace(kPlacesApiKey);
    _initIcons();
    _restoreLastCameraPosition();
    _loadMissions();
    _searchCtrl.addListener(_onSearchChanged);

    _popupCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
      reverseDuration: const Duration(milliseconds: 100),
    );
    _popupCtrl.value = 0.0; // ✅ s'assure que l'animation part bien de 0
    _popupScale = CurvedAnimation(parent: _popupCtrl, curve: Curves.easeOutBack);
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _suggestions.dispose();
    _markers.dispose();
    _loadingMissions.dispose();
    _loadingLocation.dispose();
    _isMapFullScreen.dispose();
    _error.dispose();
    _popupCtrl.dispose();
    _popupAutoHideTimer?.cancel();
    super.dispose();
  }

  // --- Init Icons -----------------------------------------------------------------------------
  Future<void> _initIcons() async {
    // Icône mission violet (96px = parfait équilibre visuel)
    _iconMission = await loadMarkerIcon('assets/icons/mission_marker.png', targetWidth: 250);


    // Icône user bleue
    _iconUser = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure);

    _rebuildMarkers(animated: true); // ⚡ Animation sur apparition
  }

  // --- Persist Camera -------------------------------------------------------------------------
  Future<void> _restoreLastCameraPosition() async {
    final p = await SharedPreferences.getInstance();
    final lat = p.getDouble('cam_lat');
    final lng = p.getDouble('cam_lng');
    final zoom = p.getDouble('cam_zoom') ?? 12.0;
    if (lat != null && lng != null) {
      _lastCamera = CameraPosition(target: LatLng(lat, lng), zoom: zoom);
    } else {
      _lastCamera = _kParisCam;
    }
    setState(() {});
  }

  Future<void> _saveCamera(CameraPosition cam) async {
    _lastCamera = cam;
    final p = await SharedPreferences.getInstance();
    await p.setDouble('cam_lat', cam.target.latitude);
    await p.setDouble('cam_lng', cam.target.longitude);
    await p.setDouble('cam_zoom', cam.zoom);
  }

  // --- Firestore ------------------------------------------------------------------------------
  Future<void> _loadMissions() async {
    try {
      _loadingMissions.value = true;
      final snap = await FirebaseFirestore.instance
          .collection('missions')
          .where('status', isEqualTo: 'open')
          .limit(200)
          .get();



      _missions.value = snap.docs;
      _rebuildMarkers();
    } catch (e) {
      _error.value = 'Erreur chargement missions : $e';
    } finally {
      _loadingMissions.value = false;
    }
  }

  void _rebuildMarkers({bool animated = false}) async {
    final newMarkers = <Marker>{};

    for (final doc in _missions.value) {
      final m = doc.data();
      final pos = (m['position'] as Map<String, dynamic>?) ?? {};
      final lat = (pos['lat'] as num?)?.toDouble();
      final lng = (pos['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;

      final marker = Marker(
        markerId: MarkerId('m:${doc.id}'),
        position: LatLng(lat, lng),
        icon: _iconMission!,
        anchor: const Offset(0.5, 1.0),
        onTap: () => _onMissionMarkerTap(doc.id, m),
      );

      newMarkers.add(marker);

      if (animated) {
        // On rafraîchit la carte marker par marker
        _markers.value = {..._markers.value, marker};
        await Future.delayed(const Duration(milliseconds: 80)); // timing visible
      }
    }

    // Ajoute ton marker utilisateur à la fin
    if (_me != null) {
      final meMarker = Marker(
        markerId: const MarkerId('me'),
        position: _me!,
        icon: _iconUser!,
        infoWindow: const InfoWindow(title: 'Vous êtes ici'),
      );
      newMarkers.add(meMarker);
    }

    if (!animated) _markers.value = newMarkers;
  }

  // --- Mission Marker Tap -> Popup ------------------------------------------------------------
  void _onMissionMarkerTap(String id, Map<String, dynamic> m) {
    _selectedMissionId = id;
    _selectedMission = m;

    // ✅ Fix animation: toujours repartir de 0 pour rejouer l’apparition
    _popupAutoHideTimer?.cancel();
    _popupCtrl.stop();
    _popupCtrl.reset();
    _popupCtrl.forward();

    // Auto-hide doux au bout de 6 sec si pas cliqué
    _popupAutoHideTimer = Timer(const Duration(seconds: 6), () {
      if (mounted) _popupCtrl.reverse();
    });

    setState(() {});
  }

  void _onPopupTap() {
    final id = _selectedMissionId;
    if (id == null) return;
    _popupCtrl.reverse();
    context.push('/missions/$id');
  }

  // --- Localisation ---------------------------------------------------------------------------
  Future<void> _ensureLocationPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      await Geolocator.openLocationSettings();
      throw 'Service de localisation désactivé';
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever || perm == LocationPermission.denied) {
      throw 'Permission localisation refusée';
    }
  }

  Future<void> _recenter() async {
    try {
      _loadingLocation.value = true;
      await _ensureLocationPermission();

      // ✅ récupère la position
      final pos = await Geolocator.getCurrentPosition();
      _me = LatLng(pos.latitude, pos.longitude);

      // ✅ attend que la carte soit prête et stable
      final ctl = await _waitForMapController();
      await Future.delayed(const Duration(milliseconds: 400));

      // ✅ moveCamera stable sans erreur canal
      await ctl.moveCamera(CameraUpdate.newLatLngZoom(_me!, 14));

      // ✅ sauvegarde et affiche le marker utilisateur
      _lastCamera = CameraPosition(target: _me!, zoom: 14);
      await _saveCamera(_lastCamera!);
      _rebuildMarkers();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Centré sur votre position actuelle')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur localisation : $e')),
        );
      }
    } finally {
      _loadingLocation.value = false;
    }
  }


  Future<void> _zoom(int dir) async {
    final ctl = await _controller.future;
    final z = await ctl.getZoomLevel();
    final next = (z + (dir > 0 ? 1 : -1)).clamp(3, 20).toDouble();
    await ctl.animateCamera(CameraUpdate.zoomTo(next));
  }

  // --- Recherche / Google Places --------------------------------------------------------------
  Future<void> _onSearchChanged() async {
    if (_searchCtrl.text.isEmpty) {
      _suggestions.value = [];
      return;
    }
    final res = await _places.autocomplete.get(
      _searchCtrl.text,
      types: '(cities)',
      language: 'fr',
    );
    if (res != null && res.predictions != null) {
      _suggestions.value = res.predictions!;
    }
  }

  Future<void> _onSuggestionTap(AutocompletePrediction s) async {
    if (s.placeId == null) return;
    _searchFocus.unfocus();
    _suggestions.value = [];
    final details = await _places.details.get(s.placeId!);
    final loc = details?.result?.geometry?.location;
    if (loc != null && loc.lat != null && loc.lng != null) {
      final ctl = await _controller.future;
      final cam = CameraPosition(target: LatLng(loc.lat!, loc.lng!), zoom: 12);
      await ctl.animateCamera(CameraUpdate.newCameraPosition(cam));
      await _saveCamera(cam);
    }
  }

  Future<void> _onSearchSubmit() async {
    if (_searchCtrl.text.isEmpty) return;
    _searchFocus.unfocus();
    final res = await _places.autocomplete.get(
      _searchCtrl.text,
      types: '(cities)',
      language: 'fr',
    );
    final first = res?.predictions?.firstOrNull;
    if (first != null) {
      await _onSuggestionTap(first);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucune ville trouvée.')),
      );
    }
  }

  // --- BUILD ----------------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final appBar = AppBar(
      backgroundColor: const Color(0xFF6C63FF),
      elevation: 1,
      centerTitle: true,
      title: const Text(
        'Explorer',
        style: TextStyle(
          color: Color(0xFFF3EEFF),
          fontWeight: FontWeight.w700,
          fontSize: 18,
          letterSpacing: 0.3,
        ),
      ),
    );

    return Scaffold(
      appBar: appBar,
      body: Stack(
        children: [
          _buildSplitLayout(),
          _buildSearchOverlay(), // barre + suggestions
          _buildMissionPopup(),  // popup flottant mission
        ],
      ),
    );
  }

  Widget _buildSplitLayout() {
    return ValueListenableBuilder<bool>(
      valueListenable: _isMapFullScreen,
      builder: (_, full, __) {
        if (full) {
          return Stack(
            children: [
              _buildMap(),
              _rightControls(isFullScreen: true),
            ],
          );
        }
        return Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  _buildMap(),
                  _rightControls(isFullScreen: false),
                ],
              ),
            ),
            Expanded(child: _buildMissionList()),
          ],
        );
      },
    );
  }

  Widget _buildMap() {
    return ValueListenableBuilder<Set<Marker>>(
      valueListenable: _markers,
      builder: (_, mk, __) {
        return GoogleMap(
          myLocationEnabled: false,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          markers: mk,
          initialCameraPosition: _lastCamera ?? _kParisCam,
          onMapCreated: (ctl) async {
            if (!_controller.isCompleted) _controller.complete(ctl);
            await Future.delayed(const Duration(milliseconds: 600));
            _mapReady = true;
            _mapControllerReady = true;
          },
          onCameraMove: (cam) => _lastCamera = cam,
          onCameraIdle: () {
            if (_lastCamera != null) _saveCamera(_lastCamera!);
          },
        );
      },
    );
  }

  Widget _rightControls({required bool isFullScreen}) {
    final double bottom = isFullScreen ? 100 : 20;
    return Positioned(
      right: 16,
      bottom: bottom,
      child: Column(
        children: [
          _fab(
            icon: isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
            onTap: () => _isMapFullScreen.value = !isFullScreen,
          ),
          const SizedBox(height: 10),
          ValueListenableBuilder<bool>(
            valueListenable: _loadingLocation,
            builder: (_, loading, __) {
              return _fab(
                iconWidget: loading
                    ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                    : const Icon(Icons.my_location, size: 22),
                onTap: _recenter,
              );
            },
          ),
          const SizedBox(height: 10),
          _fab(icon: Icons.add, onTap: () => _zoom(1)),
          const SizedBox(height: 10),
          _fab(icon: Icons.remove, onTap: () => _zoom(-1)),
        ],
      ),
    );
  }

  Widget _fab({IconData? icon, Widget? iconWidget, required VoidCallback onTap}) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(12),
      elevation: 4,
      shadowColor: Colors.black.withOpacity(0.2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: iconWidget ?? Icon(icon, size: 22),
        ),
      ),
    );
  }

  // --- LISTE MISSIONS -------------------------------------------------------------------------
  Widget _buildMissionList() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF8F6FF),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: ValueListenableBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
        valueListenable: _missions,
        builder: (_, list, __) {
          return ValueListenableBuilder<bool>(
            valueListenable: _loadingMissions,
            builder: (_, loading, __) {
              if (loading) return const Center(child: CircularProgressIndicator());
              if (list.isEmpty) return const Center(child: Text('Aucune mission trouvée.'));
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text(
                      'Missions à proximité',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        color: Color(0xFF1C1C1E),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      itemCount: list.length,
                      itemBuilder: (_, i) {
                        final doc = list[i];
                        return _buildMissionCard(doc.id, doc.data());
                      },
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildMissionCard(String id, Map<String, dynamic> m) {
    return CardMission(
      mission: {'id': id, ...m},
      onTap: () => context.push('/missions/$id'),
    );
  }

  // --- Barre de recherche + suggestions -------------------------------------------------------
  Widget _buildSearchOverlay() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              _buildSearchBar(),
              const SizedBox(height: 8),
              _buildSuggestions(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(99),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: _searchCtrl,
        focusNode: _searchFocus,
        onSubmitted: (_) => _onSearchSubmit(),
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search),
          suffixIcon: ValueListenableBuilder<List<AutocompletePrediction>>(
            valueListenable: _suggestions,
            builder: (_, s, __) {
              final has = _searchCtrl.text.isNotEmpty || s.isNotEmpty;
              if (!has) return const SizedBox.shrink();
              return IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  _searchCtrl.clear();
                  _suggestions.value = [];
                  _searchFocus.unfocus();
                },
              );
            },
          ),
          hintText: 'Chercher une ville...',
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
    );
  }

  Widget _buildSuggestions() {
    return ValueListenableBuilder<List<AutocompletePrediction>>(
      valueListenable: _suggestions,
      builder: (_, list, __) {
        if (list.isEmpty) return const SizedBox.shrink();
        return Material(
          color: Theme.of(context).colorScheme.surface,
          elevation: 4,
          borderRadius: BorderRadius.circular(12),
          shadowColor: Colors.black.withOpacity(0.2),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 250),
            child: ListView.builder(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              itemCount: list.length,
              itemBuilder: (_, i) {
                final s = list[i];
                return ListTile(
                  title: Text(s.description ?? ''),
                  onTap: () => _onSuggestionTap(s),
                );
              },
            ),
          ),
        );
      },
    );
  }

  // --- Mission Popup --------------------------------------------------------------------------
  Widget _buildMissionPopup() {
    if (_selectedMission == null) return const SizedBox.shrink();

    final m = _selectedMission!;
    final title = '${m['title'] ?? 'Mission'}';
    final price = '${m['budget'] ?? 0} €';

    return Align(
      alignment: Alignment.topCenter,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(top: 88.0, left: 16, right: 16),
          child: FadeTransition(
            // ✅ ajout d'un fondu lié au même controller (animation visible)
            opacity: _popupCtrl.drive(CurveTween(curve: Curves.easeOut)),
            child: ScaleTransition(
              scale: _popupScale,
              child: GestureDetector(
                onTap: _onPopupTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.18),
                        blurRadius: 12,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.task_alt, color: Color(0xFF6C63FF)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        price,
                        style: const TextStyle(
                          color: Color(0xFF6C63FF),
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --- Utils ----------------------------------------------------------------------------------
  String _formatDeadline(Timestamp? deadline) {
    if (deadline == null) return '';
    final date = deadline.toDate();
    final now = DateTime.now();

    final diff = date.difference(now).inDays;
    if (diff < 0) return 'Expirée';
    if (diff == 0) return 'Aujourd’hui';
    if (diff == 1) return 'Demain';
    if (diff < 7) return 'Dans $diff jours';

    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';
  }
}

// Petite extension pour .firstOrNull
extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : this[0];
}

// Petit helper copyWith CameraPosition (zoom/target)
extension _CameraCopy on CameraPosition {
  CameraPosition copyWith({LatLng? targetParam, double? zoomParam, double? tiltParam, double? bearingParam}) {
    return CameraPosition(
      target: targetParam ?? target,
      zoom: zoomParam ?? zoom,
      tilt: tiltParam ?? tilt,
      bearing: bearingParam ?? bearing,
    );
  }
}
