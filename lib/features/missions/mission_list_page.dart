import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mamission/shared/apple_appbar.dart';
import 'package:mamission/shared/widgets/card_mission.dart';
import 'package:mamission/shared/widgets/card_offer.dart';

/// =======================================================================
/// 🔹 ENUMS FILTRES
/// =======================================================================

enum MissionStatusFilter { all, active, finished, cancelled }
enum MissionTimeFilter { all, last7, last30 }
enum MissionSort { newest, oldest }

enum OfferStatusFilter { all, active, finished, refused }

// =======================================================================
// 🔹 PAGE PRINCIPALE
// =======================================================================

class MissionListPage extends StatefulWidget {
  const MissionListPage({super.key});

  @override
  State<MissionListPage> createState() => _MissionListPageState();
}

class _MissionListPageState extends State<MissionListPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser!;
    final uid = user.uid;

    // 🔥 Flux Firestore
    final missionsStream = FirebaseFirestore.instance
        .collection('missions')
        .where('posterId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .snapshots();

    final offersStream = FirebaseFirestore.instance
        .collectionGroup('offers')
        .where('userId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .snapshots();

    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FF),
      appBar: buildAppleMissionAppBar(
        title: "Mes missions",
      ),
      body: Stack(
        children: [
          // 🔹 Fond flouté optimisé
          RepaintBoundary(
            child: Stack(
              children: [
                Positioned(
                  top: -120,
                  right: -80,
                  child: _AnimatedOrb(
                    color: const Color(0xFF6C63FF).withOpacity(0.16),
                    size: 280,
                  ),
                ),
                Positioned(
                  bottom: -60,
                  left: -60,
                  child: _AnimatedOrb(
                    color: const Color(0xFF00B8D4).withOpacity(0.14),
                    size: 360,
                    duration: const Duration(seconds: 6),
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: ClipRect(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                        child: Container(color: Colors.transparent),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // --- CONTENU PRINCIPAL ---
          Column(
            children: [
              const SizedBox(height: 8),
              // --- TAB BAR FLOTTANTE ---
              Container(
                height: 52,
                margin:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(40),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.4),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF6C63FF).withOpacity(0.1),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(40),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: TabBar(
                      controller: _tabController,
                      indicator: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF6C63FF), Color(0xFF8B5CF6)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(40),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF6C63FF).withOpacity(0.4),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      indicatorPadding: const EdgeInsets.all(4.0),
                      indicatorSize: TabBarIndicatorSize.tab,
                      labelColor: Colors.white,
                      unselectedLabelColor: const Color(0xFF6C63FF),
                      labelStyle: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        fontFamily: 'Plus Jakarta Sans',
                      ),
                      dividerColor: Colors.transparent,
                      tabs: const [
                        Tab(text: "Demandes postées"),
                        Tab(text: "Offres envoyées"),
                      ],
                    ),
                  ),
                ),
              ),

              // --- LISTES ---
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  physics: const PageScrollPhysics(),
                  children: [
                    StreamBuilder<QuerySnapshot>(
                      stream: missionsStream,
                      builder: (context, missionsSnap) {
                        if (missionsSnap.connectionState ==
                            ConnectionState.waiting) {
                          return const _MissionListSkeleton();
                        }

                        if (missionsSnap.hasError) {
                          return Center(
                            child: Text(
                              "Une erreur est survenue",
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          );
                        }

                        final missionDocs =
                            missionsSnap.data?.docs ?? <QueryDocumentSnapshot>[];
                        return PostedMissionsTabContent(docs: missionDocs);
                      },
                    ),
                    StreamBuilder<QuerySnapshot>(
                      stream: offersStream,
                      builder: (context, offersSnap) {
                        if (offersSnap.connectionState ==
                            ConnectionState.waiting) {
                          return const _MissionListSkeleton();
                        }

                        if (offersSnap.hasError) {
                          return Center(
                            child: Text(
                              "Une erreur est survenue",
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          );
                        }

                        final offerDocs =
                            offersSnap.data?.docs ?? <QueryDocumentSnapshot>[];
                        return SentOffersTabContent(offerDocs: offerDocs);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// =======================================================================
// 🔹 WIDGETS D'ANIMATION
// =======================================================================

class BouncingButton extends StatefulWidget {
  final Widget child;

  const BouncingButton({super.key, required this.child});

  @override
  State<BouncingButton> createState() => _BouncingButtonState();
}

class _BouncingButtonState extends State<BouncingButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final Duration _duration = const Duration(milliseconds: 100);
  final double _scaleFactor = 0.96;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _duration,
      lowerBound: 0.0,
      upperBound: 1.0,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => _controller.forward(),
      onPointerUp: (_) => _controller.reverse(),
      onPointerCancel: (_) => _controller.reverse(),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (_, child) {
          final scale = 1 - (_controller.value * (1 - _scaleFactor));
          return Transform.scale(scale: scale, child: child);
        },
        child: widget.child,
      ),
    );
  }
}

class _AnimatedOrb extends StatefulWidget {
  final Color color;
  final double size;
  final Duration duration;

  const _AnimatedOrb({
    required this.color,
    required this.size,
    this.duration = const Duration(seconds: 4),
  });

  @override
  State<_AnimatedOrb> createState() => _AnimatedOrbState();
}

class _AnimatedOrbState extends State<_AnimatedOrb>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
    AnimationController(vsync: this, duration: widget.duration)
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.scale(
          scale: 1.0 + (_controller.value * 0.1),
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.color,
            ),
          ),
        );
      },
    );
  }
}

class _MissionListSkeleton extends StatefulWidget {
  const _MissionListSkeleton();

  @override
  State<_MissionListSkeleton> createState() => _MissionListSkeletonState();
}

class _MissionListSkeletonState extends State<_MissionListSkeleton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      key: const PageStorageKey('skeleton_list'),
      padding: const EdgeInsets.only(top: 12),
      itemCount: 4,
      physics: const BouncingScrollPhysics(),
      cacheExtent: 600,
      addAutomaticKeepAlives: true,
      addRepaintBoundaries: true,
      addSemanticIndexes: true,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Opacity(
                opacity: 0.4 + (_controller.value * 0.6),
                child: Container(
                  height: 140,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _StaggeredEntryCard extends StatelessWidget {
  final int index;
  final Widget child;

  const _StaggeredEntryCard({required this.index, required this.child});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, 30 * (1 - value)),
          child: Opacity(
            opacity: value.clamp(0.0, 1.0),
            child: Transform.scale(
              scale: 0.96 + (0.04 * value),
              child: child,
            ),
          ),
        );
      },
      child: child,
    );
  }
}

// =======================================================================
// 🔹 ONGLET DEMANDES POSTÉES
// =======================================================================

class PostedMissionsTabContent extends StatefulWidget {
  final List<QueryDocumentSnapshot> docs;

  const PostedMissionsTabContent({super.key, required this.docs});

  @override
  State<PostedMissionsTabContent> createState() =>
      _PostedMissionsTabContentState();
}

class _PostedMissionsTabContentState extends State<PostedMissionsTabContent>
    with AutomaticKeepAliveClientMixin {
  MissionStatusFilter _statusFilter = MissionStatusFilter.all;
  MissionTimeFilter _timeFilter = MissionTimeFilter.all;
  MissionSort _sort = MissionSort.newest;

  @override
  bool get wantKeepAlive => true;

  Widget _buildChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        labelStyle: TextStyle(
          fontSize: 12,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
        ),
        selectedColor: const Color(0xFF6C63FF).withOpacity(0.15),
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color:
            selected ? const Color(0xFF6C63FF) : Colors.grey.withOpacity(0.3),
          ),
        ),
      ),
    );
  }

  void _openFilterSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        MissionSort tempSort = _sort;
        MissionTimeFilter tempTime = _timeFilter;
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding:
              const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const Text(
                    "Filtrer / trier",
                    style:
                    TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "Tri",
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[800],
                      ),
                    ),
                  ),
                  RadioListTile<MissionSort>(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text("Plus récentes"),
                    value: MissionSort.newest,
                    groupValue: tempSort,
                    onChanged: (v) =>
                        setModalState(() => tempSort = v ?? tempSort),
                  ),
                  RadioListTile<MissionSort>(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text("Plus anciennes"),
                    value: MissionSort.oldest,
                    groupValue: tempSort,
                    onChanged: (v) =>
                        setModalState(() => tempSort = v ?? tempSort),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "Période",
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[800],
                      ),
                    ),
                  ),
                  RadioListTile<MissionTimeFilter>(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text("Tout"),
                    value: MissionTimeFilter.all,
                    groupValue: tempTime,
                    onChanged: (v) =>
                        setModalState(() => tempTime = v ?? tempTime),
                  ),
                  RadioListTile<MissionTimeFilter>(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text("7 derniers jours"),
                    value: MissionTimeFilter.last7,
                    groupValue: tempTime,
                    onChanged: (v) =>
                        setModalState(() => tempTime = v ?? tempTime),
                  ),
                  RadioListTile<MissionTimeFilter>(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text("30 derniers jours"),
                    value: MissionTimeFilter.last30,
                    groupValue: tempTime,
                    onChanged: (v) =>
                        setModalState(() => tempTime = v ?? tempTime),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6C63FF),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: () {
                        setState(() {
                          _sort = tempSort;
                          _timeFilter = tempTime;
                        });
                        Navigator.of(context).pop();
                      },
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 10.0),
                        child: Text(
                          "Appliquer",
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final docs = widget.docs;

    if (docs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.dashboard_customize_outlined,
                size: 60, color: Colors.grey[300]),
            const SizedBox(height: 10),
            Text(
              "Aucune mission postée",
              style: TextStyle(color: Colors.grey[500], fontSize: 16),
            ),
          ],
        ),
      );
    }

    final now = DateTime.now();

    List<QueryDocumentSnapshot> filtered = docs.where((doc) {
      final m = doc.data() as Map<String, dynamic>;
      final status = (m['status'] ?? 'open').toString();
      final ts = m['createdAt'] as Timestamp?;
      final created = ts?.toDate();

      // Statut
      bool statusOk;
      switch (_statusFilter) {
        case MissionStatusFilter.all:
          statusOk = true;
          break;
        case MissionStatusFilter.active:
          statusOk = ['open', 'in_progress', 'assigned'].contains(status);
          break;
        case MissionStatusFilter.finished:
          statusOk = ['done', 'completed', 'closed'].contains(status);
          break;
        case MissionStatusFilter.cancelled:
          statusOk = ['cancelled', 'mission_cancelled'].contains(status);
          break;
      }
      if (!statusOk) return false;

      // Période
      if (created != null) {
        switch (_timeFilter) {
          case MissionTimeFilter.all:
            break;
          case MissionTimeFilter.last7:
            if (created.isBefore(now.subtract(const Duration(days: 7)))) {
              return false;
            }
            break;
          case MissionTimeFilter.last30:
            if (created.isBefore(now.subtract(const Duration(days: 30)))) {
              return false;
            }
            break;
        }
      }
      return true;
    }).toList();

    // Tri
    filtered.sort((a, b) {
      final am = a.data() as Map<String, dynamic>;
      final bm = b.data() as Map<String, dynamic>;
      final ats = (am['createdAt'] as Timestamp?) ?? Timestamp(0, 0);
      final bts = (bm['createdAt'] as Timestamp?) ?? Timestamp(0, 0);

      if (_sort == MissionSort.newest) {
        return bts.compareTo(ats);
      } else {
        return ats.compareTo(bts);
      }
    });

    return Column(
      children: [
        // --- FILTRES (1 seule ligne + icône) ---
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildChip(
                        label: "Toutes",
                        selected: _statusFilter == MissionStatusFilter.all,
                        onTap: () =>
                            setState(() => _statusFilter = MissionStatusFilter.all),
                      ),
                      _buildChip(
                        label: "Actives",
                        selected: _statusFilter == MissionStatusFilter.active,
                        onTap: () => setState(
                                () => _statusFilter = MissionStatusFilter.active),
                      ),
                      _buildChip(
                        label: "Terminées",
                        selected: _statusFilter == MissionStatusFilter.finished,
                        onTap: () => setState(
                                () => _statusFilter = MissionStatusFilter.finished),
                      ),
                      _buildChip(
                        label: "Annulées",
                        selected:
                        _statusFilter == MissionStatusFilter.cancelled,
                        onTap: () => setState(
                                () => _statusFilter = MissionStatusFilter.cancelled),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: _openFilterSheet,
                child: Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.tune_rounded,
                    size: 18,
                    color: Color(0xFF6C63FF),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18.0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              "${filtered.length} mission(s)",
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),

        Expanded(
          child: ListView.builder(
            key: const PageStorageKey('posted_missions_list'),
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            padding: const EdgeInsets.only(top: 8, bottom: 80),
            cacheExtent: 800,
            addAutomaticKeepAlives: true,
            addRepaintBoundaries: true,
            addSemanticIndexes: true,
            itemCount: filtered.length,
            itemBuilder: (context, i) {
              final doc = filtered[i];
              final m = doc.data() as Map<String, dynamic>;
              final id = doc.id;

              return _StaggeredEntryCard(
                index: i,
                child: Padding(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: BouncingButton(
                    child: CardMission(
                      mission: {'id': id, ...m},
                      onTap: () => context.push('/missions/$id'),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// =======================================================================
// 🔹 ONGLET OFFRES ENVOYÉES
// =======================================================================

class SentOffersTabContent extends StatefulWidget {
  final List<QueryDocumentSnapshot> offerDocs;

  const SentOffersTabContent({super.key, required this.offerDocs});

  @override
  State<SentOffersTabContent> createState() => _SentOffersTabContentState();
}

class _SentOffersTabContentState extends State<SentOffersTabContent>
    with AutomaticKeepAliveClientMixin {
  Future<QuerySnapshot>? _missionsFuture;
  late Map<String, QueryDocumentSnapshot> _latestOfferByMission;

  OfferStatusFilter _statusFilter = OfferStatusFilter.all;
  MissionTimeFilter _timeFilter = MissionTimeFilter.all;
  MissionSort _sort = MissionSort.newest;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _computeLatestOffersAndFuture();
  }

  @override
  void didUpdateWidget(covariant SentOffersTabContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.offerDocs != widget.offerDocs) {
      _computeLatestOffersAndFuture();
    }
  }

  void _computeLatestOffersAndFuture() {
    final offerDocs = widget.offerDocs;

    _latestOfferByMission = {};

    for (final o in offerDocs) {
      final missionId = o.reference.parent.parent?.id;
      if (missionId == null) continue;

      final data = o.data() as Map<String, dynamic>;
      final Timestamp? createdAt = data['createdAt'] as Timestamp?;
      final Timestamp? updatedAt = data['updatedAt'] as Timestamp?;
      final Timestamp ts = (updatedAt ?? createdAt) ?? Timestamp(0, 0);

      final existing = _latestOfferByMission[missionId];
      if (existing == null) {
        _latestOfferByMission[missionId] = o;
      } else {
        final existingData = existing.data() as Map<String, dynamic>;
        final Timestamp? eCreated = existingData['createdAt'] as Timestamp?;
        final Timestamp? eUpdated = existingData['updatedAt'] as Timestamp?;
        final Timestamp eTs = (eUpdated ?? eCreated) ?? Timestamp(0, 0);

        if (ts.compareTo(eTs) > 0) {
          _latestOfferByMission[missionId] = o;
        }
      }
    }

    if (_latestOfferByMission.isEmpty) {
      _missionsFuture = null;
      return;
    }

    final missionIds = _latestOfferByMission.keys.toList();

    _missionsFuture = FirebaseFirestore.instance
        .collection('missions')
        .where(FieldPath.documentId, whereIn: missionIds.take(30).toList())
        .get();
  }

  String _deriveOfferStatus(String missionStatus, String baseStatus) {
    var status = baseStatus;
    if (missionStatus == 'cancelled' || missionStatus == 'mission_cancelled') {
      status = 'mission_cancelled';
    } else if (missionStatus == 'done' || missionStatus == 'completed') {
      if (baseStatus == 'accepted') {
        status = 'mission_done';
      }
    } else if (missionStatus == 'closed') {
      if (baseStatus == 'accepted') {
        status = 'closed';
      }
    }
    return status;
  }

  bool _isMissionActive(String missionStatus) =>
      ['open', 'in_progress', 'assigned'].contains(missionStatus);

  bool _isMissionFinished(String missionStatus) =>
      ['done', 'completed', 'closed'].contains(missionStatus);

  bool _isMissionCancelled(String missionStatus) =>
      ['cancelled', 'mission_cancelled'].contains(missionStatus);

  bool _isOfferActiveSide(String baseStatus) =>
      [
        'pending',
        'counter_offer',
        'counter',
        'negotiating',
        'accepted',
      ].contains(baseStatus);

  bool _isOfferRefusedSide(String baseStatus) =>
      [
        'rejected',
        'declined',
        'refused',
        'cancelled_by_presta',
        'expired',
      ].contains(baseStatus);

  Widget _buildChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        labelStyle: TextStyle(
          fontSize: 12,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
        ),
        selectedColor: const Color(0xFF6C63FF).withOpacity(0.15),
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color:
            selected ? const Color(0xFF6C63FF) : Colors.grey.withOpacity(0.3),
          ),
        ),
      ),
    );
  }

  void _openFilterSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        MissionSort tempSort = _sort;
        MissionTimeFilter tempTime = _timeFilter;
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding:
              const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const Text(
                    "Filtrer / trier",
                    style:
                    TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "Tri",
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[800],
                      ),
                    ),
                  ),
                  RadioListTile<MissionSort>(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text("Plus récentes"),
                    value: MissionSort.newest,
                    groupValue: tempSort,
                    onChanged: (v) =>
                        setModalState(() => tempSort = v ?? tempSort),
                  ),
                  RadioListTile<MissionSort>(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text("Plus anciennes"),
                    value: MissionSort.oldest,
                    groupValue: tempSort,
                    onChanged: (v) =>
                        setModalState(() => tempSort = v ?? tempSort),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "Période (basée sur la dernière mise à jour)",
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[800],
                      ),
                    ),
                  ),
                  RadioListTile<MissionTimeFilter>(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text("Tout"),
                    value: MissionTimeFilter.all,
                    groupValue: tempTime,
                    onChanged: (v) =>
                        setModalState(() => tempTime = v ?? tempTime),
                  ),
                  RadioListTile<MissionTimeFilter>(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text("7 derniers jours"),
                    value: MissionTimeFilter.last7,
                    groupValue: tempTime,
                    onChanged: (v) =>
                        setModalState(() => tempTime = v ?? tempTime),
                  ),
                  RadioListTile<MissionTimeFilter>(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text("30 derniers jours"),
                    value: MissionTimeFilter.last30,
                    groupValue: tempTime,
                    onChanged: (v) =>
                        setModalState(() => tempTime = v ?? tempTime),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6C63FF),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: () {
                        setState(() {
                          _sort = tempSort;
                          _timeFilter = tempTime;
                        });
                        Navigator.of(context).pop();
                      },
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 10.0),
                        child: Text(
                          "Appliquer",
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (widget.offerDocs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.send_rounded, size: 60, color: Colors.grey[300]),
            const SizedBox(height: 10),
            Text(
              "Aucune offre envoyée",
              style: TextStyle(color: Colors.grey[500], fontSize: 16),
            ),
          ],
        ),
      );
    }

    if (_latestOfferByMission.isEmpty) {
      return const Center(child: Text("Aucune offre valide trouvée"));
    }

    if (_missionsFuture == null) {
      return const _MissionListSkeleton();
    }

    return FutureBuilder<QuerySnapshot>(
      future: _missionsFuture,
      builder: (context, missionSnap) {
        if (missionSnap.connectionState == ConnectionState.waiting) {
          return const _MissionListSkeleton();
        }
        if (!missionSnap.hasData) {
          return const Center(child: Text("Chargement..."));
        }

        final missionsMap = <String, Map<String, dynamic>>{
          for (var doc in missionSnap.data!.docs)
            doc.id: doc.data() as Map<String, dynamic>,
        };

        var entries = _latestOfferByMission.entries.toList();

        // Tri par updatedAt/createdAt selon _sort
        entries.sort((a, b) {
          final ad = a.value.data() as Map<String, dynamic>;
          final bd = b.value.data() as Map<String, dynamic>;
          final aTs =
              (ad['updatedAt'] ?? ad['createdAt']) as Timestamp? ??
                  Timestamp(0, 0);
          final bTs =
              (bd['updatedAt'] ?? bd['createdAt']) as Timestamp? ??
                  Timestamp(0, 0);
          if (_sort == MissionSort.newest) {
            return bTs.compareTo(aTs);
          } else {
            return aTs.compareTo(bTs);
          }
        });

        final now = DateTime.now();

        // 🔍 Filtrage
        entries = entries.where((entry) {
          final missionId = entry.key;
          final mission = missionsMap[missionId];
          if (mission == null) return false;

          final missionStatus = (mission['status'] ?? 'open').toString();
          final rawOffer = entry.value.data() as Map<String, dynamic>;
          final baseStatus = (rawOffer['status'] ?? 'pending').toString();
          final ts =
          (rawOffer['updatedAt'] ?? rawOffer['createdAt']) as Timestamp?;
          final date = ts?.toDate();

          // Période
          if (date != null) {
            switch (_timeFilter) {
              case MissionTimeFilter.all:
                break;
              case MissionTimeFilter.last7:
                if (date.isBefore(now.subtract(const Duration(days: 7)))) {
                  return false;
                }
                break;
              case MissionTimeFilter.last30:
                if (date.isBefore(now.subtract(const Duration(days: 30)))) {
                  return false;
                }
                break;
            }
          }

          bool statusOk;
          switch (_statusFilter) {
            case OfferStatusFilter.all:
              statusOk = true;
              break;
            case OfferStatusFilter.active:
              statusOk = _isMissionActive(missionStatus) &&
                  _isOfferActiveSide(baseStatus);
              break;
            case OfferStatusFilter.finished:
              statusOk = _isMissionFinished(missionStatus);
              break;
            case OfferStatusFilter.refused:
              statusOk =
                  _isOfferRefusedSide(baseStatus) ||
                      _isMissionCancelled(missionStatus);
              break;
          }
          return statusOk;
        }).toList();

        return Column(
          children: [
            // --- FILTRES (1 ligne + icône) ---
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildChip(
                            label: "Toutes",
                            selected: _statusFilter == OfferStatusFilter.all,
                            onTap: () => setState(
                                    () => _statusFilter = OfferStatusFilter.all),
                          ),
                          _buildChip(
                            label: "Actives",
                            selected: _statusFilter == OfferStatusFilter.active,
                            onTap: () => setState(
                                    () => _statusFilter = OfferStatusFilter.active),
                          ),
                          _buildChip(
                            label: "Terminées",
                            selected:
                            _statusFilter == OfferStatusFilter.finished,
                            onTap: () => setState(
                                    () => _statusFilter = OfferStatusFilter.finished),
                          ),
                          _buildChip(
                            label: "Refusées / annulées",
                            selected:
                            _statusFilter == OfferStatusFilter.refused,
                            onTap: () => setState(
                                    () => _statusFilter = OfferStatusFilter.refused),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: _openFilterSheet,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.06),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.tune_rounded,
                        size: 18,
                        color: Color(0xFF6C63FF),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18.0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "${entries.length} offre(s)",
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),

            Expanded(
              child: ListView.separated(
                key: const PageStorageKey('sent_offers_list'),
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.only(top: 8, bottom: 120),
                separatorBuilder: (_, __) => const SizedBox(height: 0),
                cacheExtent: 800,
                addAutomaticKeepAlives: true,
                addRepaintBoundaries: true,
                addSemanticIndexes: true,
                itemCount: entries.length,
                itemBuilder: (context, i) {
                  final missionId = entries[i].key;
                  final offerDoc = entries[i].value;
                  final mission = missionsMap[missionId];
                  if (mission == null) return const SizedBox.shrink();

                  final rawOffer = offerDoc.data() as Map<String, dynamic>;
                  final missionStatus =
                  (mission['status'] ?? 'open').toString();
                  final baseStatus =
                  (rawOffer['status'] ?? 'pending').toString();
                  final derivedStatus =
                  _deriveOfferStatus(missionStatus, baseStatus);

                  final offer = Map<String, dynamic>.from(rawOffer)
                    ..['status'] = derivedStatus;

                  return _StaggeredEntryCard(
                    index: i,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      child: BouncingButton(
                        child: CardOffer(
                          offerData: offer,
                          missionData: mission,
                          onTap: () => context.push(
                            '/missions/$missionId/offers/${offerDoc.id}',
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
