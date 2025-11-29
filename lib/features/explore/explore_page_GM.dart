// --- IMPORTS (Inchangés) ---
import 'dart:async';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_place/google_place.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/animation.dart';
import 'package:mamission/shared/widgets/status_badge.dart';
import 'package:mamission/shared/widgets/card_mission.dart';
import 'package:mamission/app/colors.dart';
import 'package:mamission/shared/apple_appbar.dart';

// --- FIN DES IMPORTS ---
// --- BOITE FRANCE MÉTROPOLITAINE ---
final LatLngBounds kFranceBounds = LatLngBounds(
  southwest: const LatLng(42.0, -4.5),
  northeast: const LatLng(50.5, 7.5),
);

// --- Helper loadMarkerIcon (Inchangé) ---
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

// Enum pour le mode de filtre de zone
enum ZoneFilterMode { currentPosition, customLocation }
enum _PanelLevel { low, mid, high }

class ExplorePage extends StatefulWidget {
  const ExplorePage({super.key});

  @override
  State<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends State<ExplorePage> with TickerProviderStateMixin {
  // --- Toutes les variables (Inchangées / + ajoutées) ---
  bool _mapReady = false;
  final Completer<GoogleMapController> _controller = Completer();
  CameraPosition? _lastCamera;
  CameraPosition? _cameraForLow; // vue mémorisée quand la feuille est en bas

  static const LatLng _kFranceLatLng = LatLng(46.8, 2.5);

  // 👇 Vue quand la feuille est BASSE
  static const CameraPosition _kFranceCamLow = CameraPosition(
    target: _kFranceLatLng,
    zoom: 6.2,
  );

  // 👇 Vue quand la feuille est au MILIEU / HAUT
  static const CameraPosition _kFranceCamMid = CameraPosition(
    target: _kFranceLatLng,
    zoom: 5.6,
  );

  bool _mapControllerReady = false;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _missionsSub;

  final DraggableScrollableController _scrollableController =
  DraggableScrollableController();

  final GlobalKey _searchOverlayKey = GlobalKey();
  final ValueNotifier<double> _searchOverlayHeight = ValueNotifier(160.0);

  double _lowSnap = 0.1;
  double _midSnap = 0.4;
  double _highSnap = 0.8;

  final ValueNotifier<double> _panelPosition = ValueNotifier(0.4);

  _PanelLevel _currentPanelLevel = _PanelLevel.mid;

  final ValueNotifier<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  _selectedMissions = ValueNotifier([]);

  final ValueNotifier<int> _selectedCardIndex = ValueNotifier(0);
  late final PageController _cardCarouselController;

  final ValueNotifier<Set<Marker>> _markers = ValueNotifier(<Marker>{});
  LatLng? _me;
  Marker? _meMarker;

  BitmapDescriptor? _iconMission;
  BitmapDescriptor? _iconMissionSelected;
  BitmapDescriptor? _iconUser;

  final ValueNotifier<bool> _loadingMissions = ValueNotifier(true);
  final ValueNotifier<bool> _loadingLocation = ValueNotifier(false);
  final ValueNotifier<String> _error = ValueNotifier('');

  String _sortOrder = 'pertinence';
  RangeValues _priceRange = const RangeValues(0, 1000);
  double _distanceKm = 50;

  /// Nouveau : vrai flag d’activation de filtre zone
  bool _zoneFilterEnabled = false;
  ZoneFilterMode _zoneFilterMode = ZoneFilterMode.currentPosition;
  LatLng? _zoneFilterCenter;
  String? _zoneCityLabel;

  /// Date : all / today / next7 / weekend
  String _dateFilter = 'all';
  Set<String> _categoryFilters = {};
  bool _withPhotoFilter = false;

  late final GooglePlace _places;

  final ValueNotifier<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _missions =
  ValueNotifier([]);

  static const String kPlacesApiKey =
      "AIzaSyCXltusJoTE4wN04ETzYqLUSFRzRcX7DhY";

  // Liste catégories (pour modale)
  final List<Map<String, dynamic>> _categoriesList = [
    {
      "name": "Bricolage",
      "icon": Icons.handyman_rounded,
      "color": const Color(0xFFFFF4E5),
      "accent": const Color(0xFFFF9800)
    },
    {
      "name": "Jardinage",
      "icon": Icons.park_rounded,
      "color": const Color(0xFFE8F5E9),
      "accent": const Color(0xFF4CAF50)
    },
    {
      "name": "Déménagement",
      "icon": Icons.local_shipping_rounded,
      "color": const Color(0xFFE3F2FD),
      "accent": const Color(0xFF2196F3)
    },
    {
      "name": "Ménage",
      "icon": Icons.cleaning_services_rounded,
      "color": const Color(0xFFF3E5F5),
      "accent": const Color(0xFF9C27B0)
    },
    {
      "name": "Informatique",
      "icon": Icons.computer_rounded,
      "color": const Color(0xFFE0F7FA),
      "accent": const Color(0xFF00BCD4)
    },
    {
      "name": "Animaux",
      "icon": Icons.pets_rounded,
      "color": const Color(0xFFEFEBE9),
      "accent": const Color(0xFF795548)
    },
  ];

  // --- Helpers filtres (pour UI / All filters) ---
  bool get _hasActiveBudgetFilter =>
      _priceRange.start > 0 || _priceRange.end < 1000;

  bool get _hasActiveZoneFilter => _zoneFilterEnabled;

  bool get _hasActiveCategoryFilter => _categoryFilters.isNotEmpty;

  bool get _hasActiveDateFilter => _dateFilter != 'all';

  bool get _hasAnyFilterActive =>
      _hasActiveBudgetFilter ||
          _hasActiveZoneFilter ||
          _hasActiveCategoryFilter ||
          _withPhotoFilter ||
          _hasActiveDateFilter;

  String _buildZoneSummary() {
    if (!_zoneFilterEnabled) {
      return "Toute la France";
    }

    final radius = "${_distanceKm.toInt()} km";

    if (_zoneFilterMode == ZoneFilterMode.currentPosition) {
      return "Autour de moi • $radius";
    }

    if (_zoneFilterMode == ZoneFilterMode.customLocation &&
        _zoneFilterCenter != null) {
      final label = _zoneCityLabel ?? "Ville choisie";
      return "$label • $radius";
    }

    return "Zone personnalisée • $radius";
  }

  String _buildBudgetSummary() {
    if (!_hasActiveBudgetFilter) {
      return "Tous les budgets";
    }
    return "De ${_priceRange.start.toInt()}€ à ${_priceRange.end.toInt()}€";
  }

  String _buildCategorySummary() {
    if (_categoryFilters.isEmpty) return "Toutes les catégories";
    if (_categoryFilters.length == 1) return _categoryFilters.first;
    return "${_categoryFilters.length} catégories sélectionnées";
  }

  String _buildDateSummary() {
    switch (_dateFilter) {
      case 'today':
        return "Aujourd’hui";
      case 'next7':
        return "7 prochains jours";
      case 'weekend':
        return "Ce week-end";
      default:
        return "Toutes les dates";
    }
  }

  void _resetAllFilters() {
    _priceRange = const RangeValues(0, 1000);
    _zoneFilterEnabled = false;
    _zoneFilterMode = ZoneFilterMode.currentPosition;
    _zoneFilterCenter = null;
    _zoneCityLabel = null;
    _distanceKm = 50;
    _categoryFilters.clear();
    _withPhotoFilter = false;
    _dateFilter = 'all';
  }

  // --- initState ---
  @override
  void initState() {
    super.initState();
    _places = GooglePlace(kPlacesApiKey);

    _cardCarouselController = PageController(viewportFraction: 0.85);
    _cardCarouselController.addListener(_onCardCarouselScrolled);

    _initIcons();
    _restoreLastCameraPosition();
    _loadMissions();

    _scrollableController.addListener(_handleSheetChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureSearchOverlay();
    });
  }

  // --- _measureSearchOverlay (Inchangé) ---
  void _measureSearchOverlay() {
    final context = _searchOverlayKey.currentContext;
    if (context != null) {
      final box = context.findRenderObject() as RenderBox;
      _searchOverlayHeight.value = box.size.height;
    }
  }

  // --- dispose ---
  @override
  void dispose() {
    _scrollableController.removeListener(_handleSheetChanged);
    _scrollableController.dispose();

    _cardCarouselController.removeListener(_onCardCarouselScrolled);
    _cardCarouselController.dispose();

    _markers.dispose();
    _loadingMissions.dispose();
    _loadingLocation.dispose();
    _error.dispose();
    _panelPosition.dispose();
    _selectedMissions.dispose();
    _selectedCardIndex.dispose();
    _missionsSub?.cancel();

    super.dispose();
  }

  // --- LOGIQUE ---
  Future<void> _initIcons() async {
    _iconMission = await loadMarkerIcon(
      'assets/icons/mission_marker.png',
      targetWidth: 130,
    );
    _iconMissionSelected = await loadMarkerIcon(
      'assets/icons/mission_marker.png',
      targetWidth: 170,
    );
    _iconUser = await loadMarkerIcon(
      'assets/icons/user_marker_red.png',
      targetWidth: 100,
    );
    _rebuildMarkers();
  }

  Future<GoogleMapController> _waitForMapController() async {
    if (_mapControllerReady) return _controller.future;
    for (int i = 0; i < 10; i++) {
      try {
        final ctl = await _controller.future;
        await ctl.getZoomLevel();
        _mapControllerReady = true;
        return ctl;
      } catch (_) {
        await Future.delayed(const Duration(milliseconds: 300));
      }
    }
    throw 'Carte Google Maps non initialisée';
  }

  Future<void> _restoreLastCameraPosition() async {
    final p = await SharedPreferences.getInstance();
    final lat = p.getDouble('cam_lat');
    final lng = p.getDouble('cam_lng');
    final zoom = p.getDouble('cam_zoom') ?? 12.0;
    if (lat != null && lng != null) {
      _lastCamera = CameraPosition(target: LatLng(lat, lng), zoom: zoom);
    } else {
      _lastCamera = _kFranceCamMid;
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

  Future<void> _loadMissions() async {
    _missionsSub?.cancel();
    try {
      _loadingMissions.value = true;
      Query<Map<String, dynamic>> query = FirebaseFirestore.instance
          .collection('missions')
          .where('status', isEqualTo: 'open');

      if (_categoryFilters.isNotEmpty) {
        query = query.where('category', whereIn: _categoryFilters.toList());
      }

      if (_sortOrder == 'recent') {
        query = query.orderBy('createdAt', descending: true);
      } else if (_sortOrder == 'urgent') {
        query = query.orderBy('deadline', descending: false);
      }

      _missionsSub = query.limit(200).snapshots().listen(
            (snap) {
          var docs = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(
            snap.docs,
          );

          // BUDGET
          if (_priceRange.start > 0 || _priceRange.end < 1000) {
            docs = docs.where((doc) {
              final budget =
                  (doc.data()['budget'] as num?)?.toDouble() ?? 0.0;
              return budget >= _priceRange.start &&
                  budget <= _priceRange.end;
            }).toList();
          }

          // PHOTO
          if (_withPhotoFilter) {
            docs = docs.where((doc) {
              final data = doc.data();
              final photos = data['photos'];
              if (photos is List && photos.isNotEmpty) return true;
              if (photos is String && photos.isNotEmpty) return true;
              final main = data['mainPhotoUrl'];
              return main is String && main.isNotEmpty;
            }).toList();
          }

          // DATE
          if (_dateFilter != 'all') {
            final now = DateTime.now();
            docs = docs.where((doc) {
              final ts = doc.data()['deadline'] as Timestamp?;
              if (ts == null) return false;
              final d = ts.toDate();
              switch (_dateFilter) {
                case 'today':
                  return d.year == now.year &&
                      d.month == now.month &&
                      d.day == now.day;
                case 'next7':
                  final start = DateTime(now.year, now.month, now.day);
                  final end = start.add(const Duration(days: 7));
                  return !d.isBefore(start) && d.isBefore(end);
                case 'weekend':
                  final weekday = d.weekday;
                  return weekday == DateTime.saturday ||
                      weekday == DateTime.sunday;
                default:
                  return true;
              }
            }).toList();
          }

          // ZONE (position ou ville)
          LatLng? filterCenter;
          if (_zoneFilterEnabled) {
            if (_zoneFilterMode == ZoneFilterMode.currentPosition) {
              filterCenter = _me;
            } else if (_zoneFilterMode == ZoneFilterMode.customLocation) {
              filterCenter = _zoneFilterCenter;
            }
          }

          if (filterCenter != null) {
            docs = docs.where((doc) {
              final distance = _docDistanceKm(doc, filterCenter!);
              return distance <= _distanceKm;
            }).toList();
          }

          // TRI distance / prix
          if (_sortOrder == 'distance' && _me != null) {
            final userLatLng = _me!;
            docs.sort((a, b) {
              final da = _docDistanceKm(a, userLatLng);
              final db = _docDistanceKm(b, userLatLng);
              return da.compareTo(db);
            });
          } else if (_sortOrder == 'prix_asc') {
            docs.sort(
                  (a, b) => (a.data()['budget'] as num? ?? 0)
                  .compareTo(b.data()['budget'] as num? ?? 0),
            );
          } else if (_sortOrder == 'prix_desc') {
            docs.sort(
                  (a, b) => (b.data()['budget'] as num? ?? 0)
                  .compareTo(a.data()['budget'] as num? ?? 0),
            );
          }

          _missions.value = docs;
          _rebuildMarkers();
          _loadingMissions.value = false;
        },
        onError: (e) {
          _error.value = 'Erreur chargement missions : $e';
          _loadingMissions.value = false;
        },
      );
    } catch (e) {
      _error.value = 'Erreur chargement missions : $e';
      _loadingMissions.value = false;
    }
  }

  double _docDistanceKm(
      QueryDocumentSnapshot<Map<String, dynamic>> doc, LatLng me) {
    final m = doc.data();
    final pos = (m['position'] as Map<String, dynamic>?) ?? {};
    final lat = (pos['lat'] as num?)?.toDouble();
    final lng = (pos['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return 999999;
    final d = Geolocator.distanceBetween(
      me.latitude,
      me.longitude,
      lat,
      lng,
    );
    return d / 1000.0;
  }

  void _onMarkerTap(
      QueryDocumentSnapshot<Map<String, dynamic>> missionDoc) async {
    if (_scrollableController.isAttached) {
      final currentSize = _scrollableController.size;
      if (currentSize > _lowSnap + 0.05) {
        await _scrollableController.animateTo(
          _lowSnap,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
        await Future.delayed(const Duration(milliseconds: 50));
      }
    }
    final allMissions = _missions.value;
    final index = allMissions.indexWhere((doc) => doc.id == missionDoc.id);
    if (index == -1) return;
    _selectedMissions.value = allMissions;
    _selectedCardIndex.value = index;
    if (_cardCarouselController.hasClients) {
      _cardCarouselController.animateToPage(
        index,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
    _rebuildMarkers();
    _animateToSelectedMission(index, moveCamera: true);
  }

  void _onCardCarouselScrolled() {
    if (!_cardCarouselController.hasClients) return;
    final page = _cardCarouselController.page;
    if (page == null) return;
    final newIndex = page.round();
    if (_selectedCardIndex.value != newIndex &&
        newIndex < _selectedMissions.value.length) {
      _selectedCardIndex.value = newIndex;
      _rebuildMarkers();
      _animateToSelectedMission(newIndex, moveCamera: true);
    }
  }

  Future<void> _animateToSelectedMission(int index,
      {bool moveCamera = false}) async {
    if (index >= _selectedMissions.value.length) return;
    final doc = _selectedMissions.value[index];
    final m = doc.data();
    final pos = (m['position'] as Map<String, dynamic>?) ?? {};
    final lat = (pos['lat'] as num?)?.toDouble();
    final lng = (pos['lng'] as num?)?.toDouble();
    if (lat != null && lng != null && moveCamera) {
      final ctl = await _controller.future;
      await ctl
          .animateCamera(CameraUpdate.newLatLng(LatLng(lat, lng)));
    }
  }

  void _rebuildMarkers() async {
    if (!mounted ||
        _iconMission == null ||
        _iconUser == null ||
        _iconMissionSelected == null) return;

    final newMarkers = <Marker>{};
    final selectedDocId =
    _selectedCardIndex.value < _selectedMissions.value.length
        ? _selectedMissions.value[_selectedCardIndex.value].id
        : null;

    for (final doc in _missions.value) {
      final m = doc.data();
      final pos = (m['position'] as Map<String, dynamic>?) ?? {};
      final lat = (pos['lat'] as num?)?.toDouble();
      final lng = (pos['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;

      final isSelected = doc.id == selectedDocId;
      final icon = isSelected ? _iconMissionSelected! : _iconMission!;

      final marker = Marker(
        markerId: MarkerId('m:${doc.id}'),
        position: LatLng(lat, lng),
        icon: icon,
        anchor: const Offset(0.5, 1.0),
        zIndex: isSelected ? 10 : 1,
        onTap: () {
          _onMarkerTap(doc);
        },
      );
      newMarkers.add(marker);
    }

    if (_me != null) {
      final meMarker = Marker(
        markerId: const MarkerId('me'),
        position: _me!,
        icon: _iconUser!,
        infoWindow: const InfoWindow(title: 'Vous êtes ici'),
      );
      newMarkers.add(meMarker);
    }

    if (mounted) {
      _markers.value = newMarkers;
    }
  }

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
    if (perm == LocationPermission.deniedForever ||
        perm == LocationPermission.denied) {
      throw 'Permission localisation refusée';
    }
  }

  Future<LatLng?> _getUserLocation() async {
    try {
      await _ensureLocationPermission();
      _loadingLocation.value = true;
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      _me = LatLng(pos.latitude, pos.longitude);
      _rebuildMarkers();
      return _me;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur localisation : $e')),
        );
      }
      return null;
    } finally {
      if (mounted) {
        _loadingLocation.value = false;
      }
    }
  }

  Future<void> _zoom(int dir) async {
    final ctl = await _controller.future;
    final z = await ctl.getZoomLevel();
    final next = (z + (dir > 0 ? 1 : -1)).clamp(3, 20).toDouble();
    await ctl.animateCamera(CameraUpdate.zoomTo(next));
  }

  double _calculateZoomFromDistance(double km) {
    if (km <= 1) return 14;
    if (km >= 50) return 9;
    double zoom = 14.5 - math.log(km) / math.log(2.2);
    return zoom.clamp(9, 16);
  }

  Future<void> _animateToZone(LatLng center, double km) async {
    try {
      final ctl = await _waitForMapController();
      final zoom = _calculateZoomFromDistance(km);
      final cam = CameraPosition(target: center, zoom: zoom);
      await ctl.animateCamera(CameraUpdate.newCameraPosition(cam));
      await _saveCamera(cam);
    } catch (e) {
      // ignore
    }
  }

  void _onMapTapped(LatLng pos) {
    if (_selectedMissions.value.isNotEmpty) {
      _selectedMissions.value = [];
      _rebuildMarkers();
    }

    if (!_scrollableController.isAttached) return;

    _scrollableController.animateTo(
      _lowSnap,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  // Met à jour la position du panneau + détecte LOW / MID / HIGH
  Future<void> _handleSheetChanged() async {
    if (!_scrollableController.isAttached) return;

    final size = _scrollableController.size;
    final oldPos = _panelPosition.value;
    if ((size - oldPos).abs() > 0.01) {
      _panelPosition.value = size;
    }

    final double low = _lowSnap;
    final double mid = _midSnap;
    final double high = _highSnap;

    _PanelLevel? newLevel;

    if ((size - low).abs() < 0.03) {
      newLevel = _PanelLevel.low;
    } else if ((size - mid).abs() < 0.03) {
      newLevel = _PanelLevel.mid;
    } else if ((size - high).abs() < 0.03) {
      newLevel = _PanelLevel.high;
    }

    if (newLevel == null || newLevel == _currentPanelLevel) return;

    _currentPanelLevel = newLevel;

    await _animateCameraForPanelLevel(newLevel);
  }

  // Anime la caméra pour garder la même zone visible
  Future<void> _animateCameraForPanelLevel(_PanelLevel level) async {
    try {
      final ctl = await _controller.future;
      final CameraPosition? base = _cameraForLow ?? _lastCamera;
      if (base == null) return;

      if (level == _PanelLevel.low) {
        await ctl.animateCamera(CameraUpdate.newCameraPosition(base));
        await _saveCamera(base);
        return;
      }

      final double baseFactor = 1 - _lowSnap;
      final double newFactor =
          1 - (level == _PanelLevel.mid ? _midSnap : _highSnap);

      if (baseFactor <= 0 || newFactor <= 0) return;

      final ratio = baseFactor / newFactor;
      final double deltaZoom = math.log(ratio) / math.ln2;
      final double newZoom =
      (base.zoom - deltaZoom).clamp(3.0, 20.0);

      final targetCam = CameraPosition(
        target: base.target,
        zoom: newZoom,
        tilt: base.tilt,
        bearing: base.bearing,
      );

      await ctl.animateCamera(
          CameraUpdate.newCameraPosition(targetCam));
      await _saveCamera(targetCam);
    } catch (_) {}
  }

  // --- BUILD ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: buildAppleMissionAppBar(
        title: "Explorer",
      ),
      body: Stack(
        children: [
          _buildSplitLayout(),
          _buildSearchAndFilterOverlay(),
          _buildCardCarousel(),
          _buildShowMapButton(),
        ],
      ),
    );
  }

  // --- _buildSplitLayout ---
  // --- _buildSplitLayout (NOUVELLE VERSION) ---
  Widget _buildSplitLayout() {
    final appBar = buildAppleMissionAppBar(
      title: "Explorer",
    );
    final screenHeight = MediaQuery.of(context).size.height;
    final appBarHeight = appBar.preferredSize.height;
    final statusBarHeight = MediaQuery.of(context).padding.top;
    final availableHeight = screenHeight - appBarHeight - statusBarHeight;

    return ValueListenableBuilder<double>(
      valueListenable: _searchOverlayHeight,
      builder: (context, overlayHeight, child) {
        // 👉 Feuille qui peut monter jusqu’à coller l’appbar
        _lowSnap = 110 / availableHeight; // ~110px
        _midSnap = 0.55;
        _highSnap = 1.0; // plein écran sous l’appbar

        return Stack(
          children: [
            _buildMap(availableHeight),
            _buildDraggableList(_lowSnap, _midSnap, _highSnap),
            _buildDynamicMapControls(_lowSnap, _midSnap, _highSnap, availableHeight),
          ],
        );
      },
    );
  }


  // --- _buildDraggableList (avec glass + anims) ---
  Widget _buildDraggableList(
      double lowSnap, double midSnap, double highSnap) {
    return DraggableScrollableSheet(
      controller: _scrollableController,
      initialChildSize: midSnap,
      minChildSize: lowSnap,
      maxChildSize: highSnap,
      snap: true,
      snapSizes: [lowSnap, midSnap, highSnap],
      expand: true,
      builder: (context, scrollController) {
        return ValueListenableBuilder<double>(
          valueListenable: _panelPosition,
          builder: (context, position, child) {
            final bool isFullScreen =
                (position - highSnap).abs() < 0.02;
            final double handleOpacity = isFullScreen ? 0.0 : 1.0;
            final double blurSigma = isFullScreen ? 14.0 : 6.0;

            // Petit effet de translation selon le niveau
            final double translateY =
            isFullScreen ? 0.0 : 6.0 * (1 - position);

            return Transform.translate(
              offset: Offset(0, translateY),
              child: ClipRRect(
                borderRadius: isFullScreen
                    ? BorderRadius.zero
                    : const BorderRadius.vertical(
                    top: Radius.circular(32)),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(
                      sigmaX: blurSigma, sigmaY: blurSigma),
                  child: AnimatedContainer(
                    duration:
                    const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          const Color(0xFFE8EEFF)
                              .withOpacity(isFullScreen ? 0.9 : 0.85),
                          Colors.white.withOpacity(0.95),
                        ],
                      ),
                      border: Border(
                        top: BorderSide(
                          color:
                          Colors.white.withOpacity(0.7),
                          width: 1.5,
                        ),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF6C63FF)
                              .withOpacity(
                              isFullScreen ? 0.05 : 0.18),
                          blurRadius: isFullScreen ? 24 : 40,
                          offset: const Offset(0, -5),
                        ),
                      ],
                    ),
                    child: CustomScrollView(
                      controller: scrollController,
                      physics: const BouncingScrollPhysics(
                          parent:
                          AlwaysScrollableScrollPhysics()),
                      slivers: [
                        SliverToBoxAdapter(
                          child: Column(
                            children: [
                              AnimatedOpacity(
                                duration: const Duration(
                                    milliseconds: 200),
                                opacity: handleOpacity,
                                child: _buildHandle(),
                              ),
                              _buildListTitle(),
                            ],
                          ),
                        ),
                        ValueListenableBuilder<bool>(
                          valueListenable: _loadingMissions,
                          builder: (_, loading, __) {
                            return ValueListenableBuilder<
                                List<
                                    QueryDocumentSnapshot<
                                        Map<String, dynamic>>>>(
                              valueListenable: _missions,
                              builder: (_, list, __) {
                                return _buildMissionSliverList(
                                    loading, list);
                              },
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // --- Liste missions (avec anims par carte) ---
  Widget _buildMissionSliverList(
      bool loading,
      List<QueryDocumentSnapshot<Map<String, dynamic>>> list,
      ) {
    if (loading) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 40.0),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (list.isEmpty) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding:
          EdgeInsets.symmetric(vertical: 40.0, horizontal: 16.0),
          child: Center(
              child:
              Text('Aucune mission trouvée pour ces filtres.')),
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
            (context, index) {
          final doc = list[index];
          final m = doc.data();

          return TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.96, end: 1.0),
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOut,
            builder: (context, scale, child) {
              return Transform.scale(
                scale: scale,
                child: child,
              );
            },
            child: Padding(
              padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: _buildMissionCard(doc.id, m),
            ),
          );
        },
        childCount: list.length,
      ),
    );
  }

  // --- _buildMap ---
  Widget _buildMap(double availableHeight) {
    return ValueListenableBuilder<double>(
      valueListenable: _panelPosition,
      builder: (context, position, child) {
        final double bottomPadding = availableHeight * position;

        return ValueListenableBuilder<Set<Marker>>(
          valueListenable: _markers,
          builder: (_, mk, __) {
            return GoogleMap(
              onMapCreated: (controller) async {
                if (!_controller.isCompleted) {
                  _controller.complete(controller);
                }
              },
              initialCameraPosition: _lastCamera ?? _kFranceCamMid,
              onCameraMove: (pos) {
                _lastCamera = pos;
                if (_currentPanelLevel == _PanelLevel.low) {
                  _cameraForLow = pos;
                }
              },
              onTap: _onMapTapped,
              cameraTargetBounds:
              CameraTargetBounds(kFranceBounds),
              minMaxZoomPreference:
              const MinMaxZoomPreference(5.3, 18),
              myLocationEnabled: true,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              markers: mk,
              padding: EdgeInsets.only(bottom: bottomPadding),
            );
          },
        );
      },
    );
  }

  // --- _buildDynamicMapControls ---
  Widget _buildDynamicMapControls(double lowSnap, double midSnap,
      double highSnap, double availableHeight) {
    return AnimatedBuilder(
      animation: _scrollableController,
      builder: (context, child) {
        double panelFraction = midSnap;
        if (_scrollableController.isAttached) {
          panelFraction = _scrollableController.size;
        }

        final bottomPosition =
            (panelFraction * availableHeight) + 30;
        final opacity =
        (panelFraction > (highSnap * 0.8)) ? 0.0 : 1.0;

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
          _fab(icon: Icons.add, onTap: () => _zoom(1)),
          const SizedBox(height: 10),
          _fab(icon: Icons.remove, onTap: () => _zoom(-1)),
        ],
      ),
    );
  }

  // --- Bouton "Afficher la carte" ---
  Widget _buildShowMapButton() {
    return ValueListenableBuilder<double>(
      valueListenable: _panelPosition,
      builder: (context, position, child) {
        final bool isListFullScreen =
            (position - _highSnap).abs() < 0.05;
        final bool isCarouselVisible =
            _selectedMissions.value.isNotEmpty;
        final bool showButton =
            isListFullScreen && !isCarouselVisible;

        return AnimatedPositioned(
          duration: const Duration(milliseconds: 200),
          bottom: showButton ? 30 : -80,
          left: 0,
          right: 0,
          child: Center(
            child: FloatingActionButton.extended(
              onPressed: () {
                _scrollableController.animateTo(
                  _lowSnap,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                );
              },
              backgroundColor: const Color(0xFF222222),
              icon: const Icon(Icons.map_outlined,
                  color: Colors.white),
              label: const Text(
                "Afficher la carte",
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ),
        );
      },
    );
  }

  // --- Carousel cartes mission (avec animation de focus) ---
  Widget _buildCardCarousel() {
    final safeBottom = MediaQuery.of(context).padding.bottom;
    const double maxHeight = 275.0;

    return ValueListenableBuilder<
        List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
      valueListenable: _selectedMissions,
      builder: (context, missions, child) {
        final bool isVisible = missions.isNotEmpty;

        return AnimatedPositioned(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          bottom:
          isVisible ? (10.0 + safeBottom) : -(maxHeight + 50.0),
          left: 0,
          right: 0,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 220),
            opacity: isVisible ? 1.0 : 0.0,
            child: SizedBox(
              height: maxHeight,
              child: missions.isEmpty
                  ? const SizedBox.shrink()
                  : PageView.builder(
                controller: _cardCarouselController,
                itemCount: missions.length,
                itemBuilder: (context, index) {
                  final doc = missions[index];
                  final m =
                  doc.data() as Map<String, dynamic>;

                  return ValueListenableBuilder<int>(
                    valueListenable: _selectedCardIndex,
                    builder:
                        (context, selectedIndex, _) {
                      final bool isFocused =
                          index == selectedIndex;
                      return AnimatedScale(
                        scale: isFocused ? 1.0 : 0.94,
                        duration: const Duration(
                            milliseconds: 220),
                        curve: Curves.easeOut,
                        child: AnimatedOpacity(
                          duration: const Duration(
                              milliseconds: 220),
                          opacity: isFocused ? 1.0 : 0.75,
                          child: Padding(
                            padding: const EdgeInsets
                                .symmetric(
                                horizontal: 8.0,
                                vertical: 8.0),
                            child: _buildMissionCard(
                                doc.id, m),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  // --- _fab (Inchangé + petit effet tap) ---
  Widget _fab(
      {IconData? icon,
        Widget? iconWidget,
        required VoidCallback onTap}) {
    return GestureDetector(
      onTapDown: (_) {},
      onTapUp: (_) => onTap(),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 1.0, end: 1.0),
        duration: const Duration(milliseconds: 150),
        builder: (context, scale, child) {
          return Transform.scale(scale: scale, child: child);
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
            child: Material(
              color: Colors.white.withOpacity(0.85),
              elevation: 6,
              child: InkWell(
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: iconWidget ??
                      Icon(icon,
                          size: 22,
                          color: MaMissionColors.textDark),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --- _buildHandle ---
  Widget _buildHandle() {
    return Center(
      child: Container(
        width: 42,
        height: 5.5,
        margin: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.22),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.white.withOpacity(0.55),
            width: 1,
          ),
        ),
      ),
    );
  }

  // --- _buildListTitle ---
  Widget _buildListTitle() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Missions à proximité',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 18,
              color: Color(0xFF1C1C1E),
            ),
          ),
          TextButton.icon(
            icon: Icon(Icons.sort_rounded,
                size: 20, color: MaMissionColors.textDark),
            label: Text(
              "Trier",
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: MaMissionColors.textDark),
            ),
            style: TextButton.styleFrom(
              padding:
              const EdgeInsets.symmetric(horizontal: 10),
            ),
            onPressed: _showSortModal,
          ),
        ],
      ),
    );
  }

  // --- _buildMissionCard ---
  Widget _buildMissionCard(String id, Map<String, dynamic> m) {
    return CardMission(
      mission: {'id': id, ...m},
      onTap: () => context.push('/missions/$id'),
    );
  }

  // --- Barre de recherche + Filtres (overlay animé léger) ---
  Widget _buildSearchAndFilterOverlay() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: ValueListenableBuilder<double>(
          valueListenable: _panelPosition,
          builder: (context, pos, child) {
            final double opacity =
            (pos > _highSnap * 0.95) ? 0.0 : 1.0;
            return AnimatedOpacity(
              duration:
              const Duration(milliseconds: 180),
              opacity: opacity,
              child: Container(
                key: _searchOverlayKey,
                padding:
                const EdgeInsets.fromLTRB(16, 12, 16, 20),
                color: Colors.transparent,
                child: _buildFilterBar(),
              ),
            );
          },
        ),
      ),
    );
  }

  // --- Filtres en ligne ---
  Widget _buildFilterBar() {
    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: [
                _buildFilterChip(
                    'zone',
                    'Zone',
                    Icons.location_on_rounded,
                    _showZoneModal),
                _buildFilterChip('budget', 'Budget',
                    Icons.euro_rounded, _showBudgetModal),
                Container(
                  width: 1,
                  height: 24,
                  margin:
                  const EdgeInsets.symmetric(horizontal: 8),
                  color: Colors.grey.shade300,
                ),
                _buildCategoryDirectChip(
                    "Bricolage", Icons.handyman_rounded),
                _buildCategoryDirectChip(
                    "Jardinage", Icons.park_rounded),
                _buildCategoryDirectChip("Déménagement",
                    Icons.local_shipping_rounded),
                _buildCategoryDirectChip("Ménage",
                    Icons.cleaning_services_rounded),
                _buildCategoryDirectChip("Informatique",
                    Icons.computer_rounded),
                _buildCategoryDirectChip(
                    "Animaux", Icons.pets_rounded),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ),
        Container(
          width: 1.2,
          height: 24,
          margin: const EdgeInsets.only(left: 4, right: 10),
          color: Colors.grey.shade300,
        ),
        GestureDetector(
          onTap: _showAllFiltersModal,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  border: Border.all(
                      color: Colors.grey.shade300, width: 1.2),
                  boxShadow: [
                    BoxShadow(
                      color:
                      Colors.black.withOpacity(0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.tune_rounded,
                  color: Color(0xFF1C1C1E),
                  size: 22,
                ),
              ),
              if (_hasAnyFilterActive)
                Positioned(
                  right: 2,
                  top: 2,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFF6C63FF),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // --- Puce catégorie directe ---
  Widget _buildCategoryDirectChip(String label, IconData icon) {
    final bool isSelected = _categoryFilters.contains(label);
    final Color activeColor = const Color(0xFF6C63FF);

    return GestureDetector(
      onTap: () {
        setState(() {
          if (isSelected) {
            _categoryFilters.remove(label);
          } else {
            _categoryFilters.add(label);
          }
        });
        _loadMissions();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? activeColor : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? activeColor
                : Colors.grey.shade300,
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected
                  ? activeColor.withOpacity(0.3)
                  : Colors.black.withOpacity(0.05),
              blurRadius: isSelected ? 8 : 4,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected
                  ? Colors.white
                  : const Color(0xFF5E5E6D),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: isSelected
                    ? Colors.white
                    : const Color(0xFF1C1C1E),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Puces Zone / Budget ---
  Widget _buildFilterChip(
      String id, String label, IconData icon, VoidCallback onTap) {
    bool isSelected = false;
    if (id == 'budget' && _hasActiveBudgetFilter) {
      isSelected = true;
    }
    if (id == 'zone' && _hasActiveZoneFilter) {
      isSelected = true;
    }

    final Color selectedColor = const Color(0xFF6C63FF);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 10),
        margin: const EdgeInsets.only(right: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: isSelected
              ? selectedColor.withOpacity(0.12)
              : Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
          border: Border.all(
            color: isSelected
                ? selectedColor
                : Colors.grey.shade300,
            width: 1.2,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected
                  ? selectedColor
                  : MaMissionColors.textLight,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: isSelected
                    ? selectedColor
                    : MaMissionColors.textDark,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Modale TRIER ---
  void _showSortModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return _BottomModalContainer(
          title: "Trier par",
          child: Column(
            children: [
              _sortTile("Recommandé", "pertinence"),
              _sortTile("Plus récents", "recent"),
              _sortTile("Urgent", "urgent"),
              _sortTile("Le plus proche", "distance"),
              _sortTile("Prix le plus bas", "prix_asc"),
              _sortTile("Prix le plus élevé", "prix_desc"),
            ],
          ),
        );
      },
    );
  }

  Widget _sortTile(String label, String value) {
    final bool selected = _sortOrder == value;
    return ListTile(
      leading: Icon(
        selected ? Icons.star : Icons.circle_outlined,
        color: selected
            ? const Color(0xFF6C63FF)
            : Colors.grey.shade600,
      ),
      title: Text(label),
      onTap: () {
        Navigator.pop(context);
        setState(() => _sortOrder = value);
        _loadMissions();
      },
    );
  }

  // --- Modale BUDGET ---
  void _showBudgetModal() {
    RangeValues currentRange = _priceRange;
    final minCtrl = TextEditingController(
        text: currentRange.start.toInt().toString());
    final maxCtrl = TextEditingController(
        text: currentRange.end.toInt().toString());

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setS) {
            void updateRangeFromText() {
              final min = double.tryParse(minCtrl.text) ?? 0;
              final max = double.tryParse(maxCtrl.text) ?? 1000;
              if (min < max && min >= 0 && max <= 1000) {
                setS(() {
                  currentRange = RangeValues(min, max);
                });
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context)
                      .viewInsets
                      .bottom),
              child: _BottomModalContainer(
                title: "Budget",
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: minCtrl,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter
                                  .digitsOnly
                            ],
                            decoration:
                            const InputDecoration(
                              labelText: "Min",
                              prefixText: "€ ",
                            ),
                            onSubmitted: (_) =>
                                updateRangeFromText(),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextField(
                            controller: maxCtrl,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter
                                  .digitsOnly
                            ],
                            decoration:
                            const InputDecoration(
                              labelText: "Max",
                              prefixText: "€ ",
                            ),
                            onSubmitted: (_) =>
                                updateRangeFromText(),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    RangeSlider(
                      values: currentRange,
                      min: 0,
                      max: 1000,
                      divisions: 20,
                      labels: RangeLabels(
                        "${currentRange.start.toInt()} €",
                        "${currentRange.end.toInt()} €",
                      ),
                      onChanged: (values) {
                        setS(() {
                          currentRange = values;
                          minCtrl.text =
                              values.start.toInt().toString();
                          maxCtrl.text =
                              values.end.toInt().toString();
                        });
                      },
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () {
                            setS(() {
                              currentRange =
                              const RangeValues(0, 1000);
                              minCtrl.text = "0";
                              maxCtrl.text = "1000";
                            });
                          },
                          child:
                          const Text("Réinitialiser"),
                        ),
                        const Spacer(),
                        ElevatedButton(
                          onPressed: () {
                            Navigator.pop(context);
                            setState(() =>
                            _priceRange = currentRange);
                            _loadMissions();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                            const Color(0xFF6C63FF),
                          ),
                          child: const Text(
                            "Appliquer",
                            style: TextStyle(
                                color: Colors.white),
                          ),
                        ),
                      ],
                    )
                  ],
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      minCtrl.dispose();
      maxCtrl.dispose();
    });
  }

  // --- Modale CATÉGORIE détaillée ---
  void _showCategoryModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              height:
              MediaQuery.of(context).size.height * 0.75,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius:
                BorderRadius.vertical(top: Radius.circular(32)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius:
                      BorderRadius.circular(10),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    "FILTRER PAR CATÉGORIE",
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      color: Color(0xFF6E7787),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Expanded(
                    child: ListView.separated(
                      padding:
                      const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 10),
                      itemCount: _categoriesList.length,
                      separatorBuilder: (c, i) =>
                      const SizedBox(height: 16),
                      itemBuilder: (context, index) {
                        final category =
                        _categoriesList[index];
                        final String name =
                        category['name'];
                        final IconData icon =
                        category['icon'];
                        final Color colorBg =
                        category['color'];
                        final Color colorAccent =
                        category['accent'];

                        final isSelected =
                        _categoryFilters.contains(name);

                        return InkWell(
                          onTap: () {
                            setModalState(() {
                              if (isSelected) {
                                _categoryFilters
                                    .remove(name);
                              } else {
                                _categoryFilters.add(name);
                              }
                            });
                            setState(() {});
                            _loadMissions();
                          },
                          borderRadius:
                          BorderRadius.circular(20),
                          child: Container(
                            padding:
                            const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFFF3F6FF)
                                  : Colors.white,
                              borderRadius:
                              BorderRadius.circular(20),
                              border: isSelected
                                  ? Border.all(
                                color:
                                const Color(
                                    0xFF6C63FF),
                                width: 2,
                              )
                                  : Border.all(
                                color:
                                Colors.transparent,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 50,
                                  height: 50,
                                  decoration:
                                  BoxDecoration(
                                    color: colorBg,
                                    borderRadius:
                                    BorderRadius.circular(
                                        14),
                                  ),
                                  child: Icon(
                                    icon,
                                    color: colorAccent,
                                    size: 26,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Text(
                                    name,
                                    style:
                                    const TextStyle(
                                      fontSize: 16,
                                      fontWeight:
                                      FontWeight.w600,
                                      color:
                                      Color(0xFF1C1C1E),
                                    ),
                                  ),
                                ),
                                if (isSelected)
                                  const Icon(
                                    Icons.check_circle,
                                    color:
                                    Color(0xFF6C63FF),
                                    size: 24,
                                  )
                                else
                                  Icon(
                                    Icons.circle_outlined,
                                    color:
                                    Colors.grey.shade300,
                                    size: 24,
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                        const Color(0xFF6C63FF),
                        minimumSize: const Size(
                            double.infinity, 50),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                          BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        "Valider",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  )
                ],
              ),
            );
          },
        );
      },
    );
  }

  // --- Modale ZONE (refaite avec _zoneFilterEnabled) ---
  void _showZoneModal() {
    double localKm = _distanceKm;
    ZoneFilterMode localMode = _zoneFilterMode;
    LatLng? localCenter = _zoneFilterCenter;
    final TextEditingController zoneSearchCtrl =
    TextEditingController();
    List<AutocompletePrediction> modalSuggestions = [];
    bool modalLoading = false;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setS) {
            Future<void> _searchModalCity(String query) async {
              if (query.isEmpty) {
                setS(() => modalSuggestions = []);
                return;
              }
              setS(() => modalLoading = true);
              try {
                final res = await _places.autocomplete.get(
                  query,
                  language: 'fr',
                  components: [
                    Component("country", "fr")
                  ],
                );
                setS(() {
                  modalSuggestions =
                      res?.predictions ?? [];
                  modalLoading = false;
                });
              } catch (e) {
                setS(() {
                  modalSuggestions = [];
                  modalLoading = false;
                });
              }
            }

            Future<void> _selectModalCity(
                AutocompletePrediction s) async {
              if (s.placeId == null) return;
              setS(() => modalLoading = true);
              try {
                final details =
                await _places.details.get(s.placeId!);
                final loc = details
                    ?.result
                    ?.geometry
                    ?.location;
                if (loc != null) {
                  setS(() {
                    localCenter =
                        LatLng(loc.lat!, loc.lng!);
                    zoneSearchCtrl.text =
                        s.description ?? '';
                    localMode =
                        ZoneFilterMode.customLocation;
                    modalSuggestions = [];
                  });
                  // On mémorise le label côté page
                  setState(() {
                    _zoneCityLabel =
                        s.description ?? '';
                  });
                }
              } catch (_) {}
              setS(() => modalLoading = false);
            }

            return _BottomModalContainer(
              title: "Zone de recherche",
              child: Padding(
                padding: EdgeInsets.only(
                  bottom:
                  MediaQuery.of(context).viewInsets.bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ToggleButtons(
                      isSelected: [
                        localMode ==
                            ZoneFilterMode.currentPosition,
                        localMode ==
                            ZoneFilterMode.customLocation,
                      ],
                      onPressed: (index) async {
                        if (index == 0) {
                          final myLoc =
                          await _getUserLocation();
                          if (myLoc != null) {
                            setS(() {
                              localMode = ZoneFilterMode
                                  .currentPosition;
                            });
                          }
                        } else {
                          setS(() => localMode =
                              ZoneFilterMode
                                  .customLocation);
                        }
                      },
                      borderRadius:
                      BorderRadius.circular(8),
                      fillColor:
                      const Color(0xFF6C63FF)
                          .withOpacity(0.1),
                      selectedColor:
                      const Color(0xFF6C63FF),
                      children: const [
                        Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: 16),
                          child: Row(
                            children: [
                              Icon(Icons.my_location),
                              SizedBox(width: 8),
                              Text("Autour de moi"),
                            ],
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: 16),
                          child: Row(
                            children: [
                              Icon(Icons.location_city),
                              SizedBox(width: 8),
                              Text("Autour d'une ville"),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (localMode ==
                        ZoneFilterMode.customLocation)
                      Column(
                        children: [
                          TextField(
                            controller: zoneSearchCtrl,
                            decoration: const InputDecoration(
                              labelText:
                              "Rechercher une ville",
                              prefixIcon:
                              Icon(Icons.search),
                            ),
                            onChanged: _searchModalCity,
                          ),
                          if (modalLoading)
                            const Padding(
                              padding:
                              EdgeInsets.all(8.0),
                              child:
                              CircularProgressIndicator(),
                            ),
                          if (modalSuggestions.isNotEmpty)
                            ConstrainedBox(
                              constraints:
                              const BoxConstraints(
                                  maxHeight: 150),
                              child: ListView.builder(
                                shrinkWrap: true,
                                itemCount:
                                modalSuggestions.length,
                                itemBuilder: (c, i) =>
                                    ListTile(
                                      title: Text(
                                          modalSuggestions[i]
                                              .description ??
                                              ''),
                                      onTap: () =>
                                          _selectModalCity(
                                              modalSuggestions[
                                              i]),
                                    ),
                              ),
                            ),
                        ],
                      ),
                    const SizedBox(height: 16),
                    Text("Rayon : ${localKm.toInt()} km"),
                    Slider(
                      value: localKm,
                      min: 1,
                      max: 50,
                      divisions: 49,
                      label: "${localKm.toInt()} km",
                      onChanged: (v) =>
                          setS(() => localKm = v),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () {
                            Navigator.pop(context);
                            setState(() {
                              _zoneFilterEnabled = false;
                              _zoneFilterMode =
                                  ZoneFilterMode
                                      .currentPosition;
                              _zoneFilterCenter = null;
                              _zoneCityLabel = null;
                              _distanceKm = 50;
                            });
                            _loadMissions();
                          },
                          child: const Text(
                              "Réinitialiser"),
                        ),
                        const Spacer(),
                        ElevatedButton(
                          onPressed: () async {
                            if (localMode ==
                                ZoneFilterMode
                                    .customLocation &&
                                localCenter == null) {
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(
                                const SnackBar(
                                  content: Text(
                                      "Choisissez une ville."),
                                ),
                              );
                              return;
                            }
                            if (localMode ==
                                ZoneFilterMode
                                    .currentPosition) {
                              if (_me == null) {
                                final myLoc =
                                await _getUserLocation();
                                if (myLoc == null) {
                                  ScaffoldMessenger.of(
                                      context)
                                      .showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                          "Activez la localisation pour utiliser 'Autour de moi'."),
                                    ),
                                  );
                                  return;
                                }
                              }
                            }
                            Navigator.pop(context);
                            setState(() {
                              _zoneFilterMode =
                                  localMode;
                              _distanceKm =
                                  localKm;
                              _zoneFilterCenter = localMode ==
                                  ZoneFilterMode
                                      .customLocation
                                  ? localCenter
                                  : null;
                              _zoneFilterEnabled =
                              true;
                            });
                            _loadMissions();
                            if (_zoneFilterMode ==
                                ZoneFilterMode
                                    .currentPosition &&
                                _me != null) {
                              _animateToZone(
                                  _me!, _distanceKm);
                            } else if (_zoneFilterMode ==
                                ZoneFilterMode
                                    .customLocation &&
                                _zoneFilterCenter !=
                                    null) {
                              _animateToZone(
                                  _zoneFilterCenter!,
                                  _distanceKm);
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                            const Color(0xFF6C63FF),
                          ),
                          child: const Text(
                            "Appliquer",
                            style: TextStyle(
                                color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // --- Modale ALL FILTERS (global pro) ---
  void _showAllFiltersModal() {
    bool localWithPhoto = _withPhotoFilter;
    String localDate = _dateFilter;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setS) {
            return _BottomModalContainer(
              title: "Tous les filtres",
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      contentPadding:
                      const EdgeInsets.symmetric(
                          vertical: 4),
                      leading: const Icon(
                        Icons.location_on_rounded,
                        color: Color(0xFF6C63FF),
                      ),
                      title: const Text("Zone"),
                      subtitle: Text(_buildZoneSummary()),
                      trailing:
                      const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.pop(context);
                        _showZoneModal();
                      },
                    ),
                    ListTile(
                      contentPadding:
                      const EdgeInsets.symmetric(
                          vertical: 4),
                      leading: const Icon(
                        Icons.euro_rounded,
                        color: Color(0xFF6C63FF),
                      ),
                      title: const Text("Budget"),
                      subtitle: Text(_buildBudgetSummary()),
                      trailing:
                      const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.pop(context);
                        _showBudgetModal();
                      },
                    ),
                    ListTile(
                      contentPadding:
                      const EdgeInsets.symmetric(
                          vertical: 4),
                      leading: const Icon(
                        Icons.category_rounded,
                        color: Color(0xFF6C63FF),
                      ),
                      title: const Text("Catégories"),
                      subtitle:
                      Text(_buildCategorySummary()),
                      trailing:
                      const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.pop(context);
                        _showCategoryModal();
                      },
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        "Date",
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: MaMissionColors.textDark,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      children: [
                        _buildDateChoiceChip(
                          "Toutes les dates",
                          "all",
                          localDate,
                              (v) => setS(() => localDate = v),
                        ),
                        _buildDateChoiceChip(
                          "Aujourd’hui",
                          "today",
                          localDate,
                              (v) => setS(() => localDate = v),
                        ),
                        _buildDateChoiceChip(
                          "7 prochains jours",
                          "next7",
                          localDate,
                              (v) => setS(() => localDate = v),
                        ),
                        _buildDateChoiceChip(
                          "Ce week-end",
                          "weekend",
                          localDate,
                              (v) => setS(() => localDate = v),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      title:
                      const Text("Missions avec photo"),
                      value: localWithPhoto,
                      onChanged: (v) =>
                          setS(() => localWithPhoto = v),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () {
                            Navigator.pop(context);
                            setState(() {
                              _resetAllFilters();
                            });
                            _loadMissions();
                          },
                          child: const Text(
                              "Réinitialiser tout"),
                        ),
                        const Spacer(),
                        ElevatedButton(
                          onPressed: () {
                            Navigator.pop(context);
                            setState(() {
                              _withPhotoFilter =
                                  localWithPhoto;
                              _dateFilter = localDate;
                            });
                            _loadMissions();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                            const Color(0xFF6C63FF),
                          ),
                          child: const Text(
                            "Appliquer",
                            style: TextStyle(
                                color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDateChoiceChip(
      String label,
      String value,
      String current,
      ValueChanged<String> onSelected,
      ) {
    final bool selected = current == value;
    return Padding(
      padding:
      const EdgeInsets.only(right: 8.0, bottom: 8.0),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onSelected(value),
        selectedColor:
        const Color(0xFF6C63FF).withOpacity(0.15),
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: selected
                ? const Color(0xFF6C63FF)
                : Colors.grey.shade300,
          ),
        ),
        labelStyle: TextStyle(
          color: selected
              ? const Color(0xFF6C63FF)
              : MaMissionColors.textDark,
          fontWeight:
          selected ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    );
  }

  // --- Utils ---
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
} // FIN DE LA CLASSE _ExplorePageState

// *******************************************************************
// WIDGETS ET EXTENSIONS EXTERNES (Inchangés)
// *******************************************************************

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : this[0];
}

extension _CameraCopy on CameraPosition {
  CameraPosition copyWith({
    LatLng? targetParam,
    double? zoomParam,
    double? tiltParam,
    double? bearingParam,
  }) {
    return CameraPosition(
      target: targetParam ?? target,
      zoom: zoomParam ?? zoom,
      tilt: tiltParam ?? tilt,
      bearing: bearingParam ?? bearing,
    );
  }
}

class _BottomModalContainer extends StatelessWidget {
  final Widget child;
  final String title;

  const _BottomModalContainer({
    required this.child,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius:
      const BorderRadius.vertical(top: Radius.circular(32)),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          color: Colors.white.withOpacity(0.92),
          padding: const EdgeInsets.only(top: 18),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 50,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius:
                    BorderRadius.circular(10),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: MaMissionColors.textDark,
                  ),
                ),
                const SizedBox(height: 20),
                Padding(
                  padding:
                  const EdgeInsets.symmetric(
                      horizontal: 18),
                  child: child,
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
