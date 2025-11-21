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
import 'dart:ui' as ui;
import 'package:mamission/shared/widgets/status_badge.dart'; // Inchangé
import 'dart:typed_data';
import 'package:mamission/shared/widgets/card_mission.dart'; // Inchangé

// --- Helper pour charger et redimensionner un PNG ---
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

// ✅ MODIFIÉ : TickerProviderStateMixin est supprimé
class _ExplorePageState extends State<ExplorePage> {
  // --- Maps / Camera -------------------------------------------------------------------------
  bool _mapReady = false;
  final Completer<GoogleMapController> _controller = Completer();
  CameraPosition? _lastCamera;
  static const LatLng _kParisLatLng = LatLng(48.8566, 2.3522);
  static const CameraPosition _kParisCam =
  CameraPosition(target: _kParisLatLng, zoom: 12);
  bool _mapControllerReady = false;

  final DraggableScrollableController _scrollableController =
  DraggableScrollableController();

  final GlobalKey _searchOverlayKey = GlobalKey();
  final ValueNotifier<double> _searchOverlayHeight = ValueNotifier(160.0);

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

  // ✅ NOUVEAU : Animation pour les marqueurs
  // [ Supprimé ] -> TOUT LE CODE D'ANIMATION EST SUPPRIMÉ
  // [ Supprimé ]


  // --- UI state ------------------------------------------------------------------------------
  final ValueNotifier<bool> _loadingMissions = ValueNotifier(true);
  final ValueNotifier<bool> _loadingLocation = ValueNotifier(false);
  final ValueNotifier<String> _error = ValueNotifier('');

  // --- ✅ NOUVEAU : State pour les filtres (PRO) ---
  String _sortOrder = 'pertinence'; // pertinence, prix_asc, prix_desc, date, distance
  RangeValues _priceRange = const RangeValues(0, 1000); // [min, max]
  String _categoryFilter = 'all';
  LatLng _searchZoneCenter = _kParisLatLng; // Centre de la recherche
  double _searchZoneRadius = 20.0; // Rayon de recherche en KM

  // --- Google Places / Search ----------------------------------------------------------------
  late final GooglePlace _places;
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final ValueNotifier<List<AutocompletePrediction>> _suggestions =
  ValueNotifier([]);

  // --- Firestore -----------------------------------------------------------------------------
  final ValueNotifier<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _missions =
  ValueNotifier([]);

  // ✅ NOUVEAU : Listener Firestore
  StreamSubscription? _missionSubscription;
  bool _isInitialLoad = true;


  // --- API KEY (Places) -----------------------------------------------------------------------
  static const String kPlacesApiKey =
      "AIzaSyCXltusJoTE4wN04ETzYqLUSFRzRcX7DhY";

  @override
  void initState() {
    super.initState();
    _places = GooglePlace(kPlacesApiKey);
    _initIcons();
    _restoreLastCameraPosition();
    _setupMissionListener(); // ✅ MODIFIÉ : On lance le listener
    _searchCtrl.addListener(_onSearchChanged);

    // ✅ NOUVEAU : Initialisation de l'animation des marqueurs
    // [ Supprimé ] -> TOUT LE CODE D'ANIMATION EST SUPPRIMÉ

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureSearchOverlay();
    });
  }

  void _measureSearchOverlay() {
    final context = _searchOverlayKey.currentContext;
    if (context != null) {
      final box = context.findRenderObject() as RenderBox;
      _searchOverlayHeight.value = box.size.height;
    }
  }


  @override
  void dispose() {
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _scrollableController.dispose();
    _suggestions.dispose();
    _markers.dispose();
    _loadingMissions.dispose();
    _loadingLocation.dispose();
    _error.dispose();
    _missionSubscription?.cancel(); // ✅ NOUVEAU : Annule le listener
    // [ Supprimé ] -> TOUT LE CODE D'ANIMATION EST SUPPRIMÉ
    super.dispose();
  }

  // --- Init Icons -----------------------------------------------------------------------------
  Future<void> _initIcons() async {
    _iconMission =
    await loadMarkerIcon('assets/icons/mission_marker.png', targetWidth: 250);
    // ✅ MODIFIÉ : Icône utilisateur rouge
    _iconUser = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);
    _rebuildMarkers();
  }

  // --- Persist Camera -------------------------------------------------------------------------
  Future<void> _restoreLastCameraPosition() async {
    final p = await SharedPreferences.getInstance();
    final lat = p.getDouble('cam_lat');
    final lng = p.getDouble('cam_lng');
    final zoom = p.getDouble('cam_zoom') ?? 12.0;
    if (lat != null && lng != null) {
      _lastCamera = CameraPosition(target: LatLng(lat, lng), zoom: zoom);
      _searchZoneCenter = LatLng(lat, lng); // ✅ NOUVEAU : Centre la recherche ici
    } else {
      _lastCamera = _kParisCam;
    }
    setState(() {});
  }

  Future<void> _saveCamera(CameraPosition cam) async {
    _lastCamera = cam;
    // On ne sauvegarde que si le mouvement est significatif
    if (_lastCamera != null && (cam.target.latitude - _lastCamera!.target.latitude).abs() < 0.01) return;

    final p = await SharedPreferences.getInstance();
    await p.setDouble('cam_lat', cam.target.latitude);
    await p.setDouble('cam_lng', cam.target.longitude);
    await p.setDouble('cam_zoom', cam.zoom);
  }

  // --- ✅ NOUVEAU : Listener Firestore en temps réel ---
  void _setupMissionListener() {
    _loadingMissions.value = true;

    // Annule l'ancien listener s'il existe
    _missionSubscription?.cancel();

    try {
      Query<Map<String, dynamic>> query = FirebaseFirestore.instance
          .collection('missions')
          .where('status', isEqualTo: 'open');

      // --- Filtre Budget ---
      if (_priceRange.start > 0) {
        query = query.where('budget', isGreaterThanOrEqualTo: _priceRange.start);
      }
      if (_priceRange.end < 1000) {
        query = query.where('budget', isLessThanOrEqualTo: _priceRange.end);
      }

      // --- Filtre Catégorie ---
      if (_categoryFilter != 'all') {
        query = query.where('category', isEqualTo: _categoryFilter);
      }

      // TODO: Implémenter le filtre de 'Zone' (Geohash/Geoflutterfire)
      // Pour l'instant, on filtre manuellement

      // --- Tri ---
      if (_sortOrder == 'prix_asc') {
        query = query.orderBy('budget', descending: false);
      } else if (_sortOrder == 'prix_desc') {
        query = query.orderBy('budget', descending: true);
      } else if (_sortOrder == 'date') { // Urgent / Fin prochaine
        query = query.orderBy('deadline', descending: false);
      } else {
        // 'pertinence' ou 'plus récents' (par défaut)
        query = query.orderBy('createdAt', descending: true);
      }

      // Attache le listener
      _missionSubscription = query.snapshots().listen((snapshot) {

        // ✅ NOUVEAU : Logique de pop-up "Nouvelle Mission"
        if (!_isInitialLoad && snapshot.docChanges.isNotEmpty) {
          for (var change in snapshot.docChanges) {
            if (change.type == DocumentChangeType.added) {
              _showNewMissionPopup(change.doc.data()?['title'] ?? 'une mission');
              break; // Un seul popup suffit
            }
          }
        }
        _isInitialLoad = false;

        // TODO: Tri par distance (à faire ici en Dart si _sortOrder == 'distance')
        // ...

        _missions.value = snapshot.docs;
        _rebuildMarkers();
        _loadingMissions.value = false;

      }, onError: (e) {
        _error.value = 'Erreur chargement missions : $e';
        _loadingMissions.value = false;
        debugPrint('Erreur Firestore: $e');
      });

    } catch (e) {
      _error.value = 'Erreur chargement missions : $e';
      _loadingMissions.value = false;
      debugPrint('Erreur Firestore: $e');
    }
  }

  // ✅ NOUVEAU : Popup "Nouvelle Mission"
  void _showNewMissionPopup(String missionTitle) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.new_releases, color: Colors.white.withOpacity(0.8)),
            const SizedBox(width: 12),
            Expanded(child: Text("Nouvelle mission : $missionTitle")),
          ],
        ),
        backgroundColor: const Color(0xFF6C63FF).withOpacity(0.9),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 100, left: 16, right: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }


  void _rebuildMarkers({bool animated = false}) async {
    final newMarkers = <Marker>{};

    for (final doc in _missions.value) {
      final m = doc.data();
      final pos = (m['position'] as Map<String, dynamic>?) ?? {};
      final lat = (pos['lat'] as num?)?.toDouble();
      final lng = (pos['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;

      // TODO: Filtrer par distance (Geohash/Geoflutterfire est mieux)
      final distance = Geolocator.distanceBetween(_searchZoneCenter.latitude, _searchZoneCenter.longitude, lat, lng);
      if (distance > (_searchZoneRadius * 1000)) {
        continue;
      }

      final marker = Marker(
        markerId: MarkerId('m:${doc.id}'),
        position: LatLng(lat, lng),
        icon: _iconMission!,
        anchor: const Offset(0.5, 1.0),
        infoWindow: InfoWindow(
          title: m['title'] ?? 'Mission',
          snippet:
          "${(m['budget'] ?? 0).toStringAsFixed(2)} € - Voir les détails",
          onTap: () {
            context.push('/missions/${doc.id}');
          },
        ),
      );
      newMarkers.add(marker);
    }

    if (_me != null) {
      final meMarker = Marker(
        markerId: const MarkerId('me'),
        position: _me!,
        icon: _iconUser!, // ✅ Icône ROUGE
        infoWindow: const InfoWindow(title: 'Vous êtes ici'),
      );
      newMarkers.add(meMarker);
    }

    _markers.value = newMarkers;
  }

  // --- Localisation ---------------------------------------------------------------------------
  Future<void> _ensureLocationPermission() async {
    // ... (code inchangé)
  }

  Future<void> _recenter() async {
    try {
      _loadingLocation.value = true;
      await _ensureLocationPermission();
      final pos = await Geolocator.getCurrentPosition();
      _me = LatLng(pos.latitude, pos.longitude);

      // ✅ NOUVEAU : Centre aussi la recherche sur 'moi'
      _searchZoneCenter = _me!;

      final ctl = await _waitForMapController();
      await Future.delayed(const Duration(milliseconds: 400));
      await ctl.moveCamera(CameraUpdate.newLatLngZoom(_me!, 14));
      _lastCamera = CameraPosition(target: _me!, zoom: 14);
      await _saveCamera(_lastCamera!);
      _rebuildMarkers();

      // ✅ NOUVEAU : Relance la recherche avec la nouvelle zone
      _setupMissionListener();

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
    // ... (code inchangé)
  }

  // --- Recherche / Google Places --------------------------------------------------------------
  Future<void> _onSearchChanged() async {
    // ... (code inchangé)
  }

  Future<void> _onSuggestionTap(AutocompletePrediction s) async {
    if (s.placeId == null) return;
    _searchFocus.unfocus();
    _suggestions.value = [];
    _searchCtrl.text = s.description ?? '';
    final details = await _places.details.get(s.placeId!);
    final loc = details?.result?.geometry?.location;
    if (loc != null && loc.lat != null && loc.lng != null) {
      final latLng = LatLng(loc.lat!, loc.lng!);

      // ✅ NOUVEAU : Centre la recherche sur cette nouvelle zone
      _searchZoneCenter = latLng;

      final ctl = await _controller.future;
      final cam = CameraPosition(target: latLng, zoom: 12);
      await ctl.animateCamera(CameraUpdate.newCameraPosition(cam));
      await _saveCamera(cam);

      // ✅ NOUVEAU : Relance la recherche
      _setupMissionListener();
    }
  }

  Future<void> _onSearchSubmit() async {
    // ... (code inchangé)
  }

  // --- BUILD ----------------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final appBar = AppBar(
      backgroundColor: const Color(0xFF6C63FF),
      elevation: 1,
      centerTitle: true,
      title: const Text('Explorer', style: TextStyle(color: Color(0xFFF3EEFF), fontWeight: FontWeight.w700, fontSize: 18, letterSpacing: 0.3)),
    );

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: appBar,
      body: Stack(
        children: [
          _buildSplitLayout(appBar),
          _buildSearchAndFilterOverlay(),
        ],
      ),
    );
  }

  Widget _buildSplitLayout(AppBar appBar) {
    final screenHeight = MediaQuery.of(context).size.height;
    final appBarHeight = appBar.preferredSize.height;
    final statusBarHeight = MediaQuery.of(context).padding.top;
    final availableHeight = screenHeight - appBarHeight - statusBarHeight;

    return ValueListenableBuilder<double>(
      valueListenable: _searchOverlayHeight,
      builder: (context, overlayHeight, child) {

        // --- ✅ MODIFIÉ : Calcul des 3 positions "snap" ---

        // 1. Position HAUTE :
        final double highSnap = (availableHeight - overlayHeight) / availableHeight;

        // 2. Position MILIEU :
        const double midSnap = 0.4;

        // 3. Position BASSE :
        // 60px = poignée (25px) + titre (35px)
        final double lowSnap = 60 / availableHeight;

        if (highSnap <= midSnap || midSnap <= lowSnap) {
          return const Center(child: CircularProgressIndicator());
        }

        return Stack(
          children: [
            _buildMap(),
            _buildDraggableList(lowSnap, midSnap, highSnap),
            _buildDynamicMapControls(lowSnap, midSnap, highSnap, availableHeight),
          ],
        );
      },
    );
  }

  Widget _buildDraggableList(double lowSnap, double midSnap, double highSnap) {
    return DraggableScrollableSheet(
      controller: _scrollableController,
      initialChildSize: midSnap,
      minChildSize: lowSnap,
      maxChildSize: highSnap,
      snap: true,
      snapSizes: [lowSnap, midSnap, highSnap], // ✅ 3 NIVEAUX
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF8F6FF),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 10.0,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: _buildMissionList(scrollController),
        );
      },
    );
  }

  Widget _buildMap() {
    return ValueListenableBuilder<Set<Marker>>(
      valueListenable: _markers,
      builder: (_, mk, __) {
        // ✅ Le AnimatedBuilder est supprimé

        return GoogleMap(
          myLocationEnabled: false,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          markers: mk, // ✅ Utilise les marqueurs de base `mk`
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
        // ✅ L'accolade de AnimatedBuilder est supprimée
        // );
      },
    );
  }

  Widget _buildDynamicMapControls(double lowSnap, double midSnap, double highSnap, double availableHeight) {
    return AnimatedBuilder(
      animation: _scrollableController,
      builder: (context, child) {
        double panelFraction = midSnap;
        if (_scrollableController.isAttached) {
          panelFraction = _scrollableController.size;
        }

        // Position dynamique : 30px au-dessus du panneau
        final bottomPosition = (panelFraction * availableHeight) + 30;

        // Disparaît si le panneau est presque en haut
        final opacity = (panelFraction > (highSnap * 0.8)) ? 0.0 : 1.0;

        return Positioned(
          right: 16,
          bottom: bottomPosition,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 150),
            opacity: opacity,
            child: child,
          ),
        );
      },
      child: Column(
        children: [
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

  Widget _fab(
      {IconData? icon, Widget? iconWidget, required VoidCallback onTap}) {
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
  Widget _buildMissionList(ScrollController scrollController) {
    return ValueListenableBuilder<
        List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
      valueListenable: _missions,
      builder: (_, list, __) {
        return ValueListenableBuilder<bool>(
          valueListenable: _loadingMissions,
          builder: (_, loading, __) {
            if (loading) {
              return ListView(
                controller: scrollController,
                padding: EdgeInsets.zero,
                children: [
                  _buildHandle(),
                  _buildListTitle(),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40.0),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ],
              );
            }

            if (list.isEmpty) {
              return ListView(
                controller: scrollController,
                padding: EdgeInsets.zero,
                children: [
                  _buildHandle(),
                  _buildListTitle(),
                  const Padding(
                    padding: EdgeInsets.symmetric(
                        vertical: 40.0, horizontal: 16.0),
                    child: Center(child: Text('Aucune mission trouvée.')),
                  ),
                ],
              );
            }

            return ListView.builder(
              controller: scrollController,
              padding: EdgeInsets.zero,
              itemCount: list.length + 2,
              itemBuilder: (context, index) {
                if (index == 0) return _buildHandle();
                if (index == 1) return _buildListTitle();

                final docIndex = index - 2;
                final doc = list[docIndex];
                final m = doc.data();
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: _buildMissionCard(doc.id, m),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildHandle() {
    return Center(
      child: Container(
        width: 40,
        height: 5,
        margin: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: Colors.grey.shade300,
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  Widget _buildListTitle() {
    return const Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Text(
        'Missions à proximité',
        style: TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 18,
          color: Color(0xFF1C1C1E),
        ),
      ),
    );
  }

  Widget _buildMissionCard(String id, Map<String, dynamic> m) {
    return CardMission(
      mission: {'id': id, ...m},
      onTap: () => context.push('/missions/$id'),
    );
  }

  // --- ✅ MODIFIÉ : Barre de recherche + Filtres -------------------------------------------
  Widget _buildSearchAndFilterOverlay() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Container(
          key: _searchOverlayKey,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          color: const Color(0xFFF8F6FF),
          child: Column(
            children: [
              _buildSearchBar(),
              const SizedBox(height: 12),
              _buildFilterBar(),
              _buildSuggestions(),
            ],
          ),
        ),
      ),
    );
  }

  // ✅ NOUVEAU : Barre de filtres (logique)
  Widget _buildFilterBar() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildFilterChip('trier', 'Trier', Icons.sort, _showSortModal),
          const SizedBox(width: 8),
          _buildFilterChip('budget', 'Budget', Icons.euro, _showBudgetModal),
          const SizedBox(width: 8),
          _buildFilterChip('categorie', 'Catégorie', Icons.category_outlined, _showCategoryModal),
          const SizedBox(width: 8),
          _buildFilterChip('zone', 'Zone', Icons.location_on_outlined, _showZoneModal),
        ],
      ),
    );
  }

  // Helper pour les filtres (visuel)
  Widget _buildFilterChip(String id, String label, IconData icon, VoidCallback onTap) {
    bool isSelected = false;
    if (id == 'trier' && _sortOrder != 'pertinence') isSelected = true;
    if (id == 'budget' && (_priceRange.start != 0 || _priceRange.end != 1000)) isSelected = true;
    if (id == 'categorie' && _categoryFilter != 'all') isSelected = true;
    if (id == 'zone' && _searchZoneRadius != 20.0) isSelected = true;

    return ActionChip(
      label: Text(label),
      avatar: Icon(icon, size: 16, color: isSelected ? const Color(0xFF6C63FF) : Colors.grey.shade700),
      onPressed: onTap,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: isSelected ? const Color(0xFF6C63FF) : Colors.grey.shade300)
      ),
    );
  }

  // --- ✅ NOUVEAU : Fonctions "stub" pour les modales de filtre ---
  void _showSortModal() {
    // TODO: Afficher un showModalBottomSheet pour changer _sortOrder
    // (Recommandé, Plus récents, Urgent, Le plus proche, Prix bas, Prix haut)
    // Exemple:
    // setState(() { _sortOrder = 'prix_asc'; });
    // _setupMissionListener(); // Relance la recherche
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Modal 'Trier' à implémenter")));
  }

  void _showBudgetModal() {
    // TODO: Afficher un showModalBottomSheet avec un RangeSlider pour changer _priceRange
    // (Min/Max, <20, 20-50, 50-100, >100)
    // Exemple:
    // setState(() { _priceRange = RangeValues(50, 100); });
    // _setupMissionListener();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Modal 'Budget' à implémenter")));
  }

  void _showCategoryModal() {
    // TODO: Afficher un showModalBottomSheet pour changer _categoryFilter
    // (Maison, Déménagement, Ménage, Jardinage, Informatique)
    // Exemple:
    // setState(() { _categoryFilter = 'menage'; });
    // _setupMissionListener();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Modal 'Catégorie' à implémenter")));
  }

  void _showZoneModal() {
    // TODO: Afficher un showModalBottomSheet pour changer _searchZoneCenter et _searchZoneRadius
    // (Champ recherche ville, Slider rayon, Bouton 'Ma position')
    // Exemple:
    // setState(() { _searchZoneRadius = 5.0; });
    // _setupMissionListener();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Modal 'Zone' à implémenter")));
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
          hintText: 'Chercher une adresse...',
          border: InputBorder.none,
          contentPadding:
          const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
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

// ✅ LES EXTENSIONS SONT ICI, À L'EXTÉRIEUR DE LA CLASSE
extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : this[0];
}

extension _CameraCopy on CameraPosition {
  CameraPosition copyWith(
      {LatLng? targetParam,
        double? zoomParam,
        double? tiltParam,
        double? bearingParam}) {
    return CameraPosition(
      target: targetParam ?? this.target,
      zoom: zoomParam ?? this.zoom,
      tilt: tiltParam ?? this.tilt,
      bearing: bearingParam ?? this.bearing,
    );
  }
}