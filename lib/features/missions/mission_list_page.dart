import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mamission/shared/apple_appbar.dart';
// Assure-toi que ces imports existent bien dans ton projet
import 'package:mamission/shared/widgets/card_mission.dart';
import 'package:mamission/shared/widgets/card_offer.dart';

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

    // 🔥 Même requêtes, mais sans includeMetadataChanges (perf +)
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
          // 🔹 On met tout le fond dans un RepaintBoundary pour ne pas le recalculer à chaque frame
          RepaintBoundary(
            child: Stack(
              children: [
                // --- FOND FUTURISTE (Orbes) ---
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
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                    child: Container(color: Colors.transparent),
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
                      color: Colors.white.withOpacity(0.4), width: 1.5),
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

              // --- LISTES : 1 StreamBuilder par tab (même rendu, plus fluide) ---
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  physics: const BouncingScrollPhysics(),
                  children: [
                    // 🔹 Demandes postées
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

                    // 🔹 Offres envoyées
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

// =========================================================================
// 🔹 WIDGETS D'ANIMATION (CORRIGÉS)
// =========================================================================

/// Utilise Listener au lieu de GestureDetector pour ne pas bloquer le clic enfant
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
      padding: const EdgeInsets.only(top: 12),
      itemCount: 4,
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
    final delay = Duration(milliseconds: (index * 50).clamp(0, 500));

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 600),
      curve: const Interval(0.0, 1.0, curve: Curves.easeOutBack),
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, 50 * (1 - value)),
          child: Opacity(
            opacity: value.clamp(0.0, 1.0),
            child: Transform.scale(
              scale: 0.9 + (0.1 * value),
              child: child,
            ),
          ),
        );
      },
      child: FutureBuilder(
        future: Future.delayed(delay),
        builder: (context, snapshot) {
          return child!;
        },
      ),
    );
  }
}

// =========================================================================
// 🔹 TABS CONTENU (NAVIGATION RÉPARÉE)
// =========================================================================

class PostedMissionsTabContent extends StatelessWidget {
  final List<QueryDocumentSnapshot> docs;

  const PostedMissionsTabContent({super.key, required this.docs});

  @override
  Widget build(BuildContext context) {
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

    return ListView.builder(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      padding: const EdgeInsets.only(top: 12, bottom: 80),
      itemCount: docs.length,
      itemBuilder: (context, i) {
        final m = docs[i].data() as Map<String, dynamic>;
        final id = docs[i].id;

        return _StaggeredEntryCard(
          index: i,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: BouncingButton(
              // Suppression du onTap ici, on laisse la carte gérer
              child: CardMission(
                mission: {'id': id, ...m},
                // ✅ LA NAVIGATION EST ICI MAINTENANT
                onTap: () => context.push('/missions/$id'),
              ),
            ),
          ),
        );
      },
    );
  }
}

class SentOffersTabContent extends StatelessWidget {
  final List<QueryDocumentSnapshot> offerDocs;

  const SentOffersTabContent({super.key, required this.offerDocs});

  @override
  Widget build(BuildContext context) {
    if (offerDocs.isEmpty) {
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

    final Map<String, QueryDocumentSnapshot> latestOfferByMission = {};

    for (final o in offerDocs) {
      final missionId = o.reference.parent.parent?.id;
      if (missionId == null) continue;

      final data = o.data() as Map<String, dynamic>;
      final Timestamp? createdAt = data['createdAt'] as Timestamp?;
      final Timestamp? updatedAt = data['updatedAt'] as Timestamp?;
      final Timestamp ts = (updatedAt ?? createdAt) ?? Timestamp(0, 0);

      final existing = latestOfferByMission[missionId];
      if (existing == null) {
        latestOfferByMission[missionId] = o;
      } else {
        final existingData = existing.data() as Map<String, dynamic>;
        final Timestamp? eCreated = existingData['createdAt'] as Timestamp?;
        final Timestamp? eUpdated = existingData['updatedAt'] as Timestamp?;
        final Timestamp eTs = (eUpdated ?? eCreated) ?? Timestamp(0, 0);

        if (ts.compareTo(eTs) > 0) {
          latestOfferByMission[missionId] = o;
        }
      }
    }

    if (latestOfferByMission.isEmpty) {
      return const Center(child: Text("Aucune offre valide trouvée"));
    }

    final missionIds = latestOfferByMission.keys.toList();
    final missionsFuture = FirebaseFirestore.instance
        .collection('missions')
        .where(FieldPath.documentId, whereIn: missionIds.take(30).toList())
        .get();

    return FutureBuilder<QuerySnapshot>(
      future: missionsFuture,
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

        final entries = latestOfferByMission.entries.toList()
          ..sort((a, b) {
            final ad = a.value.data() as Map<String, dynamic>;
            final bd = b.value.data() as Map<String, dynamic>;
            final aTs = (ad['updatedAt'] ?? ad['createdAt']) as Timestamp?;
            final bTs = (bd['updatedAt'] ?? bd['createdAt']) as Timestamp?;
            return (bTs ?? Timestamp(0, 0)).compareTo(aTs ?? Timestamp(0, 0));
          });

        return ListView.separated(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.only(top: 12, bottom: 120),
          separatorBuilder: (_, __) => const SizedBox(height: 0),
          itemCount: entries.length,
          itemBuilder: (context, i) {
            final missionId = entries[i].key;
            final offerDoc = entries[i].value;
            final mission = missionsMap[missionId];
            if (mission == null) return const SizedBox.shrink();

            final rawOffer = offerDoc.data() as Map<String, dynamic>;
            final missionStatus = (mission['status'] ?? 'open').toString();
            final offer = Map<String, dynamic>.from(rawOffer);

            if (missionStatus == 'cancelled') {
              offer['status'] = 'mission_cancelled';
            } else if (missionStatus == 'done' ||
                missionStatus == 'completed') {
              if ((rawOffer['status'] ?? 'pending') == 'accepted') {
                offer['status'] = 'mission_done';
              }
            } else if (missionStatus == 'closed') {
              if ((rawOffer['status'] ?? 'pending') == 'accepted') {
                offer['status'] = 'closed';
              }
            }

            return _StaggeredEntryCard(
              index: i,
              child: Padding(
                padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: BouncingButton(
                  child: CardOffer(
                    offerData: offer,
                    missionData: mission,
                    // ✅ LA NAVIGATION EST ICI MAINTENANT
                    onTap: () => context.push(
                        '/missions/$missionId/offers/${offerDoc.id}'),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
