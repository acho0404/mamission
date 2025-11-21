import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'old_mission_detail_page.dart';
import 'package:mamission/shared/widgets/status_badge.dart';
import 'package:mamission/shared/widgets/card_mission.dart';
import 'package:mamission/shared/widgets/card_offer.dart';
import 'package:mamission/shared/apple_appbar.dart';


class MissionListPage extends StatefulWidget {
  const MissionListPage({super.key});

  @override
  State<MissionListPage> createState() => _MissionListPageState();
}

class _MissionListPageState extends State<MissionListPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  // ✅ On n'a plus besoin du listener, le TabBar/TabBarView s'en chargent

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F6FF),
      appBar: buildAppleMissionAppBar(
        title: "Mes missions",
      ),

      body: Column(
        children: [
          // --- Voici le nouveau design pour tes onglets ---
          Container(
            // On donne une hauteur fixe et un peu de marge
            height: 48,
            margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              // C'est le "rail" de fond, en gris très clair
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(40),
            ),
            child: TabBar(
              controller: _tabController,
              // C'est l'indicateur (le "cachet" violet qui bouge)
              indicator: BoxDecoration(
                color: const Color(0xFF6C63FF), // Ta couleur principale
                borderRadius: BorderRadius.circular(40),
                boxShadow: [ // Une petite ombre discrète
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),

              // Padding *autour* de l'indicateur pour l'effet "encastré"
              indicatorPadding: const EdgeInsets.all(4.0),
              indicatorSize: TabBarIndicatorSize.tab,

              labelColor: Colors.white, // Texte sélectionné (blanc)
              unselectedLabelColor: const Color(0xFF6C63FF), // Texte non-sélectionné (violet)
              labelStyle: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
              dividerColor: Colors.transparent, // Parfait
              tabs: const [
                Tab(text: "Demandes postées"),
                Tab(text: "Offres envoyées"),
              ],
            ),
          ),

          // --- Ton contenu (qui utilise Firestore) reste ici ---
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [
                PostedMissionsTab(), // Ton widget qui charge les demandes
                SentOffersTab(),      // Ton widget qui charge les offres
              ],
            ),
          ),
        ],
      ),
    );
  }
} // <-- Fin de la classe principale

// =========================================================================
// 🔹 1. Onglet "Missions postées" (gardé en mémoire)
// =========================================================================
class PostedMissionsTab extends StatefulWidget {
  const PostedMissionsTab({super.key});

  @override
  State<PostedMissionsTab> createState() => _PostedMissionsTabState();
}

// ✅ Ajout de AutomaticKeepAliveClientMixin
class _PostedMissionsTabState extends State<PostedMissionsTab>
    with AutomaticKeepAliveClientMixin {

  // ✅ On dit à Flutter de garder cet onglet VIVANT
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    // ✅ OBLIGATOIRE : On doit appeler super.build
    super.build(context);

    final user = FirebaseAuth.instance.currentUser!;
    final ref = FirebaseFirestore.instance
        .collection('missions')
        .where('posterId', isEqualTo: user.uid)
        .orderBy('createdAt', descending: true);

    return StreamBuilder<QuerySnapshot>(
      stream: ref.snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: Color(0xFF6C63FF)));
        }
        if (snap.hasError) {
          return Center(child: Text("Erreur Firestore : ${snap.error}"));
        }
        if (!snap.hasData) {
          return const Center(
              child: CircularProgressIndicator(color: Color(0xFF6C63FF)));
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return const Center(child: Text("Aucune mission postée"));
        }

        return ListView.builder(
          padding: const EdgeInsets.only(top: 12, bottom: 80),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final m = docs[i].data() as Map<String, dynamic>;
            final id = docs[i].id;
            final title = m['title'] ?? '(Sans titre)';
            final createdAt = (m['createdAt'] as Timestamp?)?.toDate();
            final status = m['status'] ?? 'open';

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: CardMission(
                mission: {
                  'id': id,
                  ...m,
                },
                onTap: () => context.push('/missions/$id'),
              ),
            );
            ;
          },
        );
      },
    );
  }
}

// =========================================================================
// 🔹 2. Onglet "Offres envoyées" (gardé en mémoire)
// =========================================================================
class SentOffersTab extends StatefulWidget {
  const SentOffersTab({super.key});

  @override
  State<SentOffersTab> createState() => _SentOffersTabState();
}

// ✅ Ajout de AutomaticKeepAliveClientMixin
class _SentOffersTabState extends State<SentOffersTab>
    with AutomaticKeepAliveClientMixin {

  // ✅ On dit à Flutter de garder cet onglet VIVANT
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    // ✅ OBLIGATOIRE : On doit appeler super.build
    super.build(context);

    final uid = FirebaseAuth.instance.currentUser!.uid;
    final offersRef = FirebaseFirestore.instance
        .collectionGroup('offers')
        .where('userId', isEqualTo: uid)
        .orderBy('createdAt', descending: true);

    return StreamBuilder<QuerySnapshot>(
      stream: offersRef.snapshots(),
      builder: (context, offerSnap) {
        if (offerSnap.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: Color(0xFF6C63FF)));
        }
        if (offerSnap.hasError) {
          return Center(child: Text("Erreur : ${offerSnap.error}"));
        }
        if (!offerSnap.hasData || offerSnap.data!.docs.isEmpty) {
          return const Center(child: Text("Aucune offre envoyée"));
        }

        final offers = offerSnap.data!.docs;

        // 1. Extraire tous les IDs de mission uniques
        final missionIds = offers
            .map((o) => o.reference.parent.parent?.id)
            .where((id) => id != null)
            .toSet()
            .toList();

        if (missionIds.isEmpty) {
          return const Center(child: Text("Aucune offre valide trouvée"));
        }

        // 2. Créer une seule Future pour récupérer TOUTES les missions
        final missionsFuture = FirebaseFirestore.instance
            .collection('missions')
            .where(FieldPath.documentId, whereIn: missionIds.take(30).toList())
            .get();

        // 3. Utiliser FutureBuilder *à l'extérieur* du ListView
        return FutureBuilder<QuerySnapshot>(
          future: missionsFuture,
          builder: (context, missionSnap) {
            if (missionSnap.connectionState == ConnectionState.waiting) {
              return const Center(
                  child: CircularProgressIndicator(color: Color(0xFF6C63FF)));
            }
            if (!missionSnap.hasData) {
              return const Center(child: Text("Chargement des missions..."));
            }

            // 4. Créer un "plan" (Map) des missions pour un accès instantané
            final missionsMap = {
              for (var doc in missionSnap.data!.docs)
                doc.id: doc.data() as Map<String, dynamic>
            };

            // 5. Construire le ListView instantanément
            return ListView.separated(
              padding: const EdgeInsets.only(top: 12, bottom: 120),
              separatorBuilder: (_, __) => const SizedBox(height: 16),
              itemCount: offers.length,
              itemBuilder: (context, i) {
                final o = offers[i];
                final offer = o.data() as Map<String, dynamic>;
                final missionId = o.reference.parent.parent!.id;

                final mission = missionsMap[missionId];
                if (mission == null) return const SizedBox.shrink();

                return CardOffer(
                  offerData: offer,
                  missionData: mission,
                  onTap: () => context.push('/missions/$missionId/offers/${o.id}'),
                );
              },
            );
          },
        );
      },
    );
  }
}