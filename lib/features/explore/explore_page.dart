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

// --- Helper loadMarkerIcon (Inchangé) ---
Future<BitmapDescriptor> loadMarkerIcon(String path, {int targetWidth = 96}) async {
  // ... (code inchangé)
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

class ExplorePage extends StatefulWidget {
  const ExplorePage({super.key});

  @override
  State<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends State<ExplorePage> with TickerProviderStateMixin {
  // --- Toutes les variables (Inchangées) ---
  bool _mapReady = false;
  final Completer<GoogleMapController> _controller = Completer();
  CameraPosition? _lastCamera;
  static const LatLng _kFranceLatLng = LatLng(47.5, 2.3);
  static const CameraPosition _kFranceCam =
  CameraPosition(target: _kFranceLatLng, zoom: 5.0);
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

  final ValueNotifier<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _selectedMissions = ValueNotifier([]);
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
  ZoneFilterMode _zoneFilterMode = ZoneFilterMode.currentPosition;
  LatLng? _zoneFilterCenter;
  String _dateFilter = 'all';
  Set<String> _categoryFilters = {};
  bool _withPhotoFilter = false;

  late final GooglePlace _places;

  final ValueNotifier<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _missions =
  ValueNotifier([]);

  static const String kPlacesApiKey =
      "AIzaSyCXltusJoTE4wN04ETzYqLUSFRzRcX7DhY";

  // --- initState (Inchangé) ---
  @override
  void initState() {
    super.initState();
    _places = GooglePlace(kPlacesApiKey);

    _cardCarouselController = PageController(viewportFraction: 0.85);
    _cardCarouselController.addListener(_onCardCarouselScrolled);

    _initIcons();
    _restoreLastCameraPosition();
    _loadMissions();

    _scrollableController.addListener(() {
      _panelPosition.value = _scrollableController.size;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureSearchOverlay();
    });
  }

  // --- _measureSearchOverlay (Inchangé) ---
  void _measureSearchOverlay() {
    // ... (code inchangé)
    final context = _searchOverlayKey.currentContext;
    if (context != null) {
      final box = context.findRenderObject() as RenderBox;
      _searchOverlayHeight.value = box.size.height;
    }
  }

  // --- dispose (Inchangé) ---
  @override
  void dispose() {
    // ... (code inchangé)
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

  // --- Toutes les fonctions de logique (Inchangées) ---
  // _initIcons, _restoreLastCameraPosition, _saveCamera, _loadMissions,
  // _docDistanceKm, _onMarkerTap, _onCardCarouselScrolled,
  // _animateToSelectedMission, _rebuildMarkers, _ensureLocationPermission,
  // _getUserLocation, _zoom, _calculateZoomFromDistance, _animateToZone,
  // _onMapTapped
  // ... (Tout ce code est identique au précédent) ...
  Future<void> _initIcons() async {
    _iconMission = await loadMarkerIcon(
      'assets/icons/mission_marker.png',
      targetWidth: 100,
    );
    _iconMissionSelected = await loadMarkerIcon(
      'assets/icons/mission_marker.png',
      targetWidth: 140,
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
        await ctl.getZoomLevel(); // ping
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
      _lastCamera = _kFranceCam;
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
          if (_priceRange.start > 0 || _priceRange.end < 1000) {
            docs = docs.where((doc) {
              final budget = (doc.data()['budget'] as num?)?.toDouble() ?? 0.0;
              return budget >= _priceRange.start && budget <= _priceRange.end;
            }).toList();
          }
          LatLng? filterCenter;
          if (_zoneFilterMode == ZoneFilterMode.currentPosition) {
            filterCenter = _me;
          } else {
            filterCenter = _zoneFilterCenter;
          }
          if (filterCenter != null) {
            docs = docs.where((doc) {
              final distance = _docDistanceKm(doc, filterCenter!);
              return distance <= _distanceKm;
            }).toList();
          }
          if (_sortOrder == 'distance' && _me != null) {
            final userLatLng = _me!;
            docs.sort((a, b) {
              final da = _docDistanceKm(a, userLatLng);
              final db = _docDistanceKm(b, userLatLng);
              return da.compareTo(db);
            });
          } else if (_sortOrder == 'prix_asc') {
            docs.sort((a, b) =>
                (a.data()['budget'] as num? ?? 0).compareTo(b.data()['budget'] as num? ?? 0)
            );
          } else if (_sortOrder == 'prix_desc') {
            docs.sort((a, b) =>
                (b.data()['budget'] as num? ?? 0).compareTo(a.data()['budget'] as num? ?? 0)
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
  void _onMarkerTap(QueryDocumentSnapshot<Map<String, dynamic>> missionDoc) async {
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
    if (_selectedCardIndex.value != newIndex && newIndex < _selectedMissions.value.length) {
      _selectedCardIndex.value = newIndex;
      _rebuildMarkers();
      _animateToSelectedMission(newIndex, moveCamera: true);
    }
  }
  Future<void> _animateToSelectedMission(int index, {bool moveCamera = false}) async {
    if (index >= _selectedMissions.value.length) return;
    final doc = _selectedMissions.value[index];
    final m = doc.data();
    final pos = (m['position'] as Map<String, dynamic>?) ?? {};
    final lat = (pos['lat'] as num?)?.toDouble();
    final lng = (pos['lng'] as num?)?.toDouble();
    if (lat != null && lng != null && moveCamera) {
      final ctl = await _controller.future;
      ctl.moveCamera(CameraUpdate.newLatLng(LatLng(lat, lng)));
    }
  }
  void _rebuildMarkers() async {
    if (!mounted || _iconMission == null || _iconUser == null || _iconMissionSelected == null) return;
    final newMarkers = <Marker>{};
    final selectedDocId = _selectedCardIndex.value < _selectedMissions.value.length
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
    if(mounted) {
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
      if(mounted) {
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
      await ctl.moveCamera(CameraUpdate.newCameraPosition(cam));
      await _saveCamera(cam);
    } catch (e) {
      print("Erreur animation caméra: $e");
    }
  }
  void _onMapTapped() {
    if (_selectedMissions.value.isNotEmpty) {
      _selectedMissions.value = [];
      _rebuildMarkers();
      return;
    }
    if (!_scrollableController.isAttached) return;
    final currentSize = _scrollableController.size;
    if ((currentSize - _midSnap).abs() < 0.05) {
      _scrollableController.animateTo(
        _lowSnap,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }


  // --- BUILD (Inchangé) ---
  @override
  Widget build(BuildContext context) {
    // ... (code inchangé)

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

  // --- _buildSplitLayout (Inchangé) ---
  Widget _buildSplitLayout() {
    final appBar = buildAppleMissionAppBar(
      title: "Explorer",
    );
    // ... (code inchangé)
    final screenHeight = MediaQuery.of(context).size.height;
    final appBarHeight = appBar.preferredSize.height;
    final statusBarHeight = MediaQuery.of(context).padding.top;
    final availableHeight = screenHeight - appBarHeight - statusBarHeight;

    return ValueListenableBuilder<double>(
      valueListenable: _searchOverlayHeight,
      builder: (context, overlayHeight, child) {
        _highSnap = (availableHeight - overlayHeight) / availableHeight;
        _midSnap = 0.55;
        _lowSnap = 110 / availableHeight; // ~110px

        _highSnap = _highSnap.clamp(_midSnap + 0.1, 1.0);

        if (_highSnap <= _midSnap || _midSnap <= _lowSnap) {
          return const Center(child: CircularProgressIndicator());
        }

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

  // =========================================================================
  // ✅ MODIFICATION 1 : _buildDraggableList
  // On utilise un CustomScrollView pour que la poignée, le titre, ET la
  // liste fassent tous partie de la même zone de scroll.
  // =========================================================================
  Widget _buildDraggableList(double lowSnap, double midSnap, double highSnap) {
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
            final bool isFullScreen = (position - highSnap).abs() < 0.02;
            final bool isLow = (position - lowSnap).abs() < 0.02;
            final double handleOpacity = isFullScreen ? 0.0 : 1.0;

            return ClipRRect(
              borderRadius: isFullScreen ? BorderRadius.zero : const BorderRadius.vertical(top: Radius.circular(30)),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.88),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 30,
                        offset: const Offset(0, -6),
                      ),
                    ],
                  ),

                  // ✅ MODIFIÉ : On utilise CustomScrollView
                  // Cela permet à la poignée/titre ET à la liste
                  // de répondre au même "scrollController".
                  child: CustomScrollView(
                    controller: scrollController, // ✅ Le contrôleur principal
                    slivers: [

                      // --- PARTIE 1: Poignée et Titre ---
                      SliverToBoxAdapter(
                        child: Column(
                          children: [
                            AnimatedOpacity(
                              duration: const Duration(milliseconds: 200),
                              opacity: handleOpacity,
                              child: _buildHandle(),
                            ),
                            _buildListTitle(),
                          ],
                        ),
                      ),

                      // --- PARTIE 2: La liste des missions ---
                      ValueListenableBuilder<bool>(
                        valueListenable: _loadingMissions,
                        builder: (_, loading, __) {
                          return ValueListenableBuilder<
                              List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
                            valueListenable: _missions,
                            builder: (_, list, __) {

                              // On cache avec l'opacité si la liste est en bas
                              return _buildMissionSliverList(loading, list); // ❤️ direct


                            },
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // =========================================================================
  // ✅ MODIFICATION 2 : NOUVEAU WIDGET _buildMissionSliverList
  // Cette fonction construit la liste de missions pour le CustomScrollView
  // =========================================================================
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
          padding: EdgeInsets.symmetric(vertical: 40.0, horizontal: 16.0),
          child: Center(child: Text('Aucune mission trouvée pour ces filtres.')),
        ),
      );
    }

    // ✅ On retourne un SliverList (une liste "lazy" pour CustomScrollView)
    return SliverList(
      delegate: SliverChildBuilderDelegate(
            (context, index) {
          final doc = list[index];
          final m = doc.data();
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: _buildMissionCard(doc.id, m),
          );
        },
        childCount: list.length,
      ),
    );
  }

  // ✅ SUPPRIMÉ : L'ancienne fonction _buildMissionListContent
  // (elle est remplacée par la logique ci-dessus)
  // Widget _buildMissionListContent(ScrollController scrollController, bool isLow) { ... }


  // --- _buildMap (Inchangé) ---
  Widget _buildMap(double availableHeight) {
    // ... (code inchangé)
    return ValueListenableBuilder<double>(
        valueListenable: _panelPosition,
        builder: (context, position, child) {
          final double bottomPadding = availableHeight * position;

          return ValueListenableBuilder<Set<Marker>>(
            valueListenable: _markers,
            builder: (_, mk, __) {
              return GoogleMap(
                padding: EdgeInsets.only(bottom: bottomPadding),
                myLocationEnabled: false,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                mapToolbarEnabled: false,
                markers: mk,
                initialCameraPosition: _lastCamera ?? _kFranceCam,
                onMapCreated: (ctl) async {
                  if (!_controller.isCompleted) _controller.complete(ctl);
                  final style = await rootBundle.loadString('assets/config/map_style.json');
                  ctl.setMapStyle(style);
                  ctl.animateCamera(
                    CameraUpdate.newLatLngZoom(const LatLng(46.8, 2.1), 6.3),
                  );

                  _mapReady = true;
                  _mapControllerReady = true;
                },
                onCameraMove: (cam) => _lastCamera = cam,
                onCameraIdle: () {
                  if (_lastCamera != null) _saveCamera(_lastCamera!);
                },
                onTap: (_) => _onMapTapped(),
              );
            },
          );
        }
    );
  }


  // --- _buildDynamicMapControls (Inchangé) ---
  Widget _buildDynamicMapControls(double lowSnap, double midSnap, double highSnap, double availableHeight) {
    // ... (code inchangé)
    return AnimatedBuilder(
      animation: _scrollableController,
      builder: (context, child) {
        double panelFraction = midSnap;
        if (_scrollableController.isAttached) {
          panelFraction = _scrollableController.size;
        }

        final bottomPosition = (panelFraction * availableHeight) + 30;
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
          _fab(icon: Icons.add, onTap: () => _zoom(1)),
          const SizedBox(height: 10),
          _fab(icon: Icons.remove, onTap: () => _zoom(-1)),
        ],
      ),
    );
  }

  // =========================================================================
  // ✅ MODIFICATION 3 : _buildShowMapButton
  // On s'assure que le onPressed anime bien vers `_lowSnap`
  // =========================================================================
  Widget _buildShowMapButton() {
    return ValueListenableBuilder<double>(
      valueListenable: _panelPosition,
      builder: (context, position, child) {
        final bool isListFullScreen = (position - _highSnap).abs() < 0.05;
        final bool isCarouselVisible = _selectedMissions.value.isNotEmpty;
        final bool showButton = isListFullScreen && !isCarouselVisible;

        return AnimatedPositioned(
          duration: const Duration(milliseconds: 200),
          bottom: showButton ? 30 : -80,
          left: 0,
          right: 0,
          child: Center(
            child: FloatingActionButton.extended(
              onPressed: () {
                // ✅ CORRECTION : Ramène la liste en BAS
                _scrollableController.animateTo(
                  _lowSnap, // <-- C'est bien la position basse
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                );
              },
              backgroundColor: const Color(0xFF222222),
              icon: const Icon(Icons.map_outlined, color: Colors.white),
              label: const Text(
                "Afficher la carte",
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        );
      },
    );
  }

  // --- _buildCardCarousel (Inchangé) ---
  Widget _buildCardCarousel() {
    final screenHeight = MediaQuery.of(context).size.height;
    final safeBottom = MediaQuery.of(context).padding.bottom;
    final double maxHeight = 275.0;

    // ... (code inchangé)
    return ValueListenableBuilder<
        List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
      valueListenable: _selectedMissions,
      builder: (context, missions, child) {
        final bool isVisible = missions.isNotEmpty;

        return AnimatedPositioned(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          bottom: isVisible
              ? (10.0 + safeBottom)
              : -(maxHeight + 50.0),
          left: 0,
          right: 0,
          child: SizedBox(
            height: maxHeight,
            child: PageView.builder(
            controller: _cardCarouselController,
              itemCount: missions.length,
              itemBuilder: (context, index) {
                final doc = missions[index];
                final m = doc.data() as Map<String, dynamic>;

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
                  child: _buildMissionCard(doc.id, m),
                );
              },
            ),
          ),
        );
      },
    );
  }

  // --- _fab (Inchangé) ---
  Widget _fab({IconData? icon, Widget? iconWidget, required VoidCallback onTap}) {
    // ... (code inchangé)
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: Material(
          color: Colors.white.withOpacity(0.85),
          elevation: 6,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: EdgeInsets.all(12),
              child: iconWidget ??
                  Icon(icon, size: 22, color: MaMissionColors.textDark),
            ),
          ),
        ),
      ),
    );
  }

  // --- _buildHandle (Inchangé) ---
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



  // --- _buildListTitle (Inchangé) ---
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
            icon: Icon(Icons.sort_rounded, size: 20, color: MaMissionColors.textDark),
            label: Text(
              "Trier",
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: MaMissionColors.textDark
              ),
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            onPressed: _showSortModal,
          ),
        ],
      ),
    );
  }

  // --- _buildMissionCard (Inchangé) ---
  Widget _buildMissionCard(String id, Map<String, dynamic> m) {
    return CardMission(
      mission: {'id': id, ...m},
      onTap: () => context.push('/missions/$id'),
    );
  }

  // --- Barre de recherche + Filtres (Inchangé) ---
  Widget _buildSearchAndFilterOverlay() {
    // ... (code inchangé)
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: ClipRRect(
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 5, sigmaY: 5),
            child: Container(
              key: _searchOverlayKey,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.88),
                  border: Border(
                      bottom: BorderSide(color: Colors.grey.shade300, width: 0.5)
                  )
              ),
              child: _buildFilterBar(),
            ),
          ),
        ),
      ),
    );
  }
  // =========================================================================
  // ⚡ MODIFICATION 1 : _buildFilterBar
  // On sépare les filtres rapides (qui scrollent) du bouton "Tous les filtres"
  // =========================================================================
  Widget _buildFilterBar() {

    return Row(
      children: [
        // --- La liste des filtres qui scrolle ---
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // On garde vos filtres principaux
                _buildFilterChip('budget', 'Budget', Icons.euro_rounded, _showBudgetModal),
                _buildFilterChip('categorie', 'Catégorie', Icons.category_rounded, _showCategoryModal),
                _buildFilterChip('zone', 'Zone', Icons.location_on_rounded, _showZoneModal),
                // Vous pouvez facilement en ajouter d'autres ici si besoin
              ],
            ),
          ),
        ),

        // --- Le séparateur vertical pour la finesse ---
        Container(
          width: 1.2,
          height: 24,
          margin: const EdgeInsets.symmetric(horizontal: 10),
          color: Colors.grey.shade300,
        ),

        // --- Le nouveau bouton "Tous les filtres" (votre "critère severe") ---
        GestureDetector(
          onTap: _showAllFiltersModal, // ✅ On appelle une nouvelle fonction
          child: Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              border: Border.all(color: Colors.grey.shade300, width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 8,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: Icon(
              Icons.tune_rounded, // L'icône classique pour les filtres
              color: MaMissionColors.textDark,
              size: 20,
            ),
          ),
        ),
      ],
    );
  }
  // =========================================================================
  // ⚡ MODIFICATION 2 : _buildFilterChip
  // Style plus élégant : on remplace le gradient par un fond + bordure
  // =========================================================================
  Widget _buildFilterChip(
      String id, String label, IconData icon, VoidCallback onTap) {
    bool isSelected = false;
    if (id == 'budget' && (_priceRange.start != 0 || _priceRange.end != 1000)) {
      isSelected = true;
    }
    if (id == 'categorie' && _categoryFilters.isNotEmpty) isSelected = true;
    if (id == 'zone' &&
        (_zoneFilterMode == ZoneFilterMode.customLocation ||
            _distanceKm < 50)) isSelected = true;

    // La couleur principale pour la sélection (au lieu du gradient)
    final Color selectedColor = const Color(0xFF6C63FF);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Duration(milliseconds: 200), // Animation plus rapide
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        margin: EdgeInsets.only(right: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          // ✅ Style plus subtil
          color: isSelected ? selectedColor.withOpacity(0.12) : Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06), // Ombre plus douce
              blurRadius: 8,
              offset: Offset(0, 3),
            ),
          ],
          border: Border.all(
            // ✅ Bordure de couleur si sélectionné
            color: isSelected
                ? selectedColor
                : Colors.grey.shade300,
            width: 1.2,
          ),
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 16,
                // ✅ Couleur d'icône qui matche la sélection
                color: isSelected ? selectedColor : MaMissionColors.textLight),
            SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                // ✅ Couleur de texte qui matche la sélection
                color: isSelected ? selectedColor : MaMissionColors.textDark,
              ),
            ),
          ],
        ),
      ),
    );
  }


  // --- Modales de Filtre (Inchangées) ---
  // (Tout le reste du code est inchangé)

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
        color: selected ? const Color(0xFF6C63FF) : Colors.grey.shade600,
      ),
      title: Text(label),
      onTap: () {
        Navigator.pop(context);
        setState(() => _sortOrder = value);
        _loadMissions();
      },
    );
  }
  void _showBudgetModal() {
    RangeValues currentRange = _priceRange;
    final minCtrl = TextEditingController(text: currentRange.start.toInt().toString());
    final maxCtrl = TextEditingController(text: currentRange.end.toInt().toString());
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
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
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
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            decoration: const InputDecoration(
                              labelText: "Min",
                              prefixText: "€ ",
                            ),
                            onSubmitted: (_) => updateRangeFromText(),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextField(
                            controller: maxCtrl,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            decoration: const InputDecoration(
                              labelText: "Max",
                              prefixText: "€ ",
                            ),
                            onSubmitted: (_) => updateRangeFromText(),
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
                          minCtrl.text = values.start.toInt().toString();
                          maxCtrl.text = values.end.toInt().toString();
                        });
                      },
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () {
                            setS(() {
                              currentRange = const RangeValues(0, 1000);
                              minCtrl.text = "0";
                              maxCtrl.text = "1000";
                            });
                          },
                          child: const Text("Réinitialiser"),
                        ),
                        const Spacer(),
                        ElevatedButton(
                          onPressed: () {
                            Navigator.pop(context);
                            setState(() => _priceRange = currentRange);
                            _loadMissions();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6C63FF),
                          ),
                          child: const Text(
                            "Appliquer",
                            style: TextStyle(color: Colors.white),
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
  void _showCategoryModal() {
    const categories = [
      "Maison & Bricolage",
      "Déménagement & Transport",
      "Ménage & Aide à domicile",
      "Jardinage & Extérieur",
      "Informatique & High-tech",
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setS) {
            return _BottomModalContainer(
              title: "Catégories",
              child: Column(
                children: [
                  for (final c in categories)
                    ListTile(
                      leading: Icon(
                        _categoryFilters.contains(c) ? Icons.check_box : Icons.check_box_outline_blank,
                        color: _categoryFilters.contains(c) ? const Color(0xFF6C63FF) : Colors.grey.shade600,
                      ),
                      title: Text(c),
                      onTap: () {
                        setS(() {
                          if (_categoryFilters.contains(c)) {
                            _categoryFilters.remove(c);
                          } else {
                            _categoryFilters.add(c);
                          }
                        });
                      },
                    ),
                  const Divider(),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () {
                          setS(() {
                            _categoryFilters.clear();
                          });
                        },
                        child: const Text("Réinitialiser"),
                      ),
                      const Spacer(),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          setState(() {});
                          _loadMissions();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6C63FF),
                        ),
                        child: const Text(
                          "Appliquer",
                          style: TextStyle(color: Colors.white),
                        ),

                      ),
                    ],
                  )
                ],
              ),
            );
          },
        );
      },
    );
  }
  void _showZoneModal() {
    double localKm = _distanceKm;
    ZoneFilterMode localMode = _zoneFilterMode;
    LatLng? localCenter = _zoneFilterCenter;
    String localCityName = "";
    final TextEditingController zoneSearchCtrl = TextEditingController();
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
                  components: [Component("country", "fr")],
                );
                setS(() {
                  modalSuggestions = res?.predictions ?? [];
                  modalLoading = false;
                });
              } catch (e) {
                setS(() {
                  modalSuggestions = [];
                  modalLoading = false;
                });
              }
            }
            Future<void> _selectModalCity(AutocompletePrediction s) async {
              if (s.placeId == null) return;
              setS(() => modalLoading = true);
              try {
                final details = await _places.details.get(s.placeId!);
                final loc = details?.result?.geometry?.location;
                if (loc != null) {
                  setS(() {
                    localCenter = LatLng(loc.lat!, loc.lng!);
                    localCityName = s.description ?? '';
                    zoneSearchCtrl.text = localCityName;
                    localMode = ZoneFilterMode.customLocation;
                    modalSuggestions = [];
                  });
                }
              } catch (_) {}
              setS(() => modalLoading = false);
            }
            return _BottomModalContainer(
              title: "Zone de recherche",
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ToggleButtons(
                      isSelected: [
                        localMode == ZoneFilterMode.currentPosition,
                        localMode == ZoneFilterMode.customLocation,
                      ],
                      onPressed: (index) async {
                        if (index == 0) {
                          final myLoc = await _getUserLocation();
                          if (myLoc != null) {
                            setS(() {
                              localMode = ZoneFilterMode.currentPosition;
                            });
                          }
                        } else {
                          setS(() => localMode = ZoneFilterMode.customLocation);
                        }
                      },
                      borderRadius: BorderRadius.circular(8),
                      fillColor: const Color(0xFF6C63FF).withOpacity(0.1),
                      selectedColor: const Color(0xFF6C63FF),
                      children: const [
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              Icon(Icons.my_location),
                              SizedBox(width: 8),
                              Text("Autour de moi"),
                            ],
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
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
                    if (localMode == ZoneFilterMode.customLocation)
                      Column(
                        children: [
                          TextField(
                            controller: zoneSearchCtrl,
                            decoration: const InputDecoration(
                              labelText: "Rechercher une ville",
                              prefixIcon: Icon(Icons.search),
                            ),
                            onChanged: _searchModalCity,
                          ),
                          if (modalLoading)
                            const Padding(
                              padding: EdgeInsets.all(8.0),
                              child: CircularProgressIndicator(),
                            ),
                          if (modalSuggestions.isNotEmpty)
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 150),
                              child: ListView.builder(
                                shrinkWrap: true,
                                itemCount: modalSuggestions.length,
                                itemBuilder: (c, i) => ListTile(
                                  title: Text(modalSuggestions[i].description ?? ''),
                                  onTap: () => _selectModalCity(modalSuggestions[i]),
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
                      onChanged: (v) => setS(() => localKm = v),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () {
                            Navigator.pop(context);
                            setState(() {
                              _zoneFilterMode = ZoneFilterMode.customLocation; // Pour ne PAS utiliser _me
                              _zoneFilterCenter = null; // Pour ne PAS utiliser de ville
                              _distanceKm = 50; // La valeur par défaut du slider, peu importe
                            });
                            _loadMissions();
                          },
                          child: const Text("Réinitialiser"),
                        ),
                        const Spacer(),
                        ElevatedButton(
                          onPressed: () async {
                            if (localMode == ZoneFilterMode.customLocation &&
                                localCenter == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text("Choisissez une ville.")),
                              );
                              return;
                            }
                            if (localMode == ZoneFilterMode.currentPosition &&
                                _me == null) {
                              final myLoc = await _getUserLocation();
                              if(myLoc == null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text("Activez la localisation pour utiliser 'Autour de moi'.")),
                                );
                                return;
                              }
                            }
                            Navigator.pop(context);
                            setState(() {
                              _zoneFilterMode = localMode;
                              _distanceKm = localKm;
                              _zoneFilterCenter =
                              localMode == ZoneFilterMode.customLocation
                                  ? localCenter
                                  : null;
                            });
                            _loadMissions();
                            if (_zoneFilterMode == ZoneFilterMode.currentPosition &&
                                _me != null) {
                              _animateToZone(_me!, _distanceKm);
                            } else if (_zoneFilterMode == ZoneFilterMode.customLocation &&
                                _zoneFilterCenter != null) {
                              _animateToZone(_zoneFilterCenter!, _distanceKm);
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6C63FF),
                          ),
                          child: const Text(
                            "Appliquer",
                            style: TextStyle(color: Colors.white),
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
  void _showAllFiltersModal() {
    // TODO: Construire la modale qui regroupe tous les filtres

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Bientôt : Modale 'Tous les filtres'")),
    );
  }

  // --- Utils (Inchangé) ---
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
} // <-- FIN DE LA CLASSE _ExplorePageState


// *******************************************************************
//
// WIDGETS ET EXTENSIONS EXTERNES (Inchangés)
//
// *******************************************************************

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

class _BottomModalContainer extends StatelessWidget {
  final Widget child;
  final String title;

  const _BottomModalContainer({required this.child, required this.title});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          color: Colors.white.withOpacity(0.92),
          padding: EdgeInsets.only(top: 18),
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
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                SizedBox(height: 14),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: MaMissionColors.textDark,
                  ),
                ),
                SizedBox(height: 20),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 18),
                  child: child,
                ),
                SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}