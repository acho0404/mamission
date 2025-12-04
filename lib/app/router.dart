import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';

// --- Imports des pages ---
import '../features/shell/shell.dart';
import '../features/explore/explore_page.dart';
import '../features/missions/mission_list_page.dart';
import '../features/missions/mission_detail/mission_detail_page.dart';
import '../features/missions/mission_create_page.dart';
import '../features/missions/offers_page.dart';
import '../features/missions/offer_detail_page.dart';
import '../features/chat/threads_page.dart';
import '../features/chat/chat_detail_page.dart';
import '../features/profile/profile_page.dart';
import '../features/profile/public_profile_page.dart';
import '../features/reviews/reviews_page.dart';
import 'package:mamission/features/explore/all_providers_page.dart';
import 'package:mamission/features/shell/shell.dart';
import '../features/auth/login_page.dart';
import '../features/auth/register_page.dart';
import '../features/auth/reset_password_page.dart';
import '../features/payments/wallet_page.dart'; // Assurez-vous d'avoir créé le fichier
import '../features/profile/coordonnees_page.dart'; // <-- AJOUTER CETTE LIGNE
import '../features/payments/banking_page.dart'; // <--- AJOUTE CECI
import 'package:mamission/features/notifications/notifications_page.dart';
import 'package:mamission/features/payments/subscription_page.dart';

// --- Placeholder générique ---
class _PlaceholderPage extends StatelessWidget {
  final String title;
  const _PlaceholderPage(this.title, {super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: const Color(0xFF6C63FF),
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: Center(
        child: Text(
          "Page $title non encore implémentée",
          style: const TextStyle(fontSize: 16, color: Colors.black54),
        ),
      ),
    );
  }
}

// =============================================================
// 🔹 ROUTER PRINCIPAL
// =============================================================
GoRouter buildRouter() {
  return GoRouter(
    initialLocation: '/explore',
    redirect: (context, state) {
      final user = FirebaseAuth.instance.currentUser;
      final loc = state.matchedLocation;

      final isAuthPage = loc == '/login' || loc == '/register';

      if (user == null && !isAuthPage) return '/login';
      if (user != null && isAuthPage) return '/explore';
      return null;
    },

    routes: [
      // =========================================================
      // 🔹 AUTH
      // =========================================================
      GoRoute(path: '/login', builder: (_, __) => const LoginPage()),
      GoRoute(path: '/register', builder: (_, __) => const RegisterPage()),
      GoRoute(path: '/reset', builder: (_, __) => const ResetPasswordPage()),

      // =========================================================
      // 🔹 PAGE CREATION MISSION (hors shell)
      // =========================================================
      GoRoute(
        path: '/missions/create',
        builder: (context, state) {
          final editId = state.uri.queryParameters['edit'];
          return MissionCreatePage(editMissionId: editId);
        },
      ),
      GoRoute(
        path: '/notifications',
        name: 'notifications',
        builder: (context, state) => const NotificationsPage(),
      ),
      GoRoute(
        path: '/subscriptions/checkout',
        name: 'subscriptions_checkout',
        builder: (context, state) {
          final args = state.extra as Map<String, dynamic>?;
          final plan = args?['plan'] as String? ?? 'standard';
          return VisibilitySubscriptionCheckoutPage(plan: plan);
        },
      ),


      GoRoute(
        path: '/payments',
        builder: (_, __) => const WalletPage(),
      ),
      GoRoute(
        path: '/providers',
        builder: (context, state) => const AllProvidersPage(),
      ),

// AJOUTEZ cette route pour les settings (utilisera aussi WalletPage ou une page Settings dédiée)
      // =========================================================
      // 🔹 SETTINGS (Gestion dynamique)
      // =========================================================
      // =========================================================
      // 🔹 SETTINGS (Gestion dynamique)
      // =========================================================
      GoRoute(
        path: '/settings/:type', // type = kyc, security, contact, banking
        builder: (context, state) {
          final type = state.pathParameters['type'];

          if (type == 'contact') {
            return const CoordonneesPage();
          }

          // 👇 AJOUT : La route pour le RIB
          if (type == 'banking') {
            return const BankingPage();
          }

          // Pour les autres types (kyc, security...), on garde le placeholder
          return Scaffold(
            appBar: AppBar(title: Text("Paramètres: $type")),
            body: Center(child: Text("Module $type en construction")),
          );
        },
      ),
      // 🔹 VITRINE PUBLIQUE DE SOI
      GoRoute(
        path: '/profile/public',
        builder: (context, state) {
          final uidParam = state.uri.queryParameters['uid'];
          final editParam = state.uri.queryParameters['edit'];

          final currentUser = FirebaseAuth.instance.currentUser;
          final uid = uidParam ?? currentUser!.uid;
          final openEdit = editParam == '1';

          return PublicProfilePage(
            userId: uid,
            openEditOnStart: openEdit,
          );
        },
      ),

      // =========================================================
      // 🔹 SHELL GLOBAL (bottom bar)
      // =========================================================
      ShellRoute(
        builder: (context, state, child) => ShellScaffold(child: child),
        routes: [
          // --- Explore ---
          GoRoute(
            path: '/explore',
            builder: (_, __) => const ExplorePage(),
          ),

          // --- Liste missions ---
          GoRoute(
            path: '/missions',
            builder: (_, __) => const MissionListPage(),
          ),

          // --- Détail mission ---
          GoRoute(
            path: '/missions/:id',
            builder: (context, state) {
              final missionId = state.pathParameters['id']!;
              return MissionDetailPage(missionId: missionId);
            },
          ),

          // --- Page CREATE depuis navbar ---
          GoRoute(
            path: '/create-mission',
            builder: (_, __) => const MissionCreatePage(),
          ),

          // --- Liste des offres reçues ---
          GoRoute(
            path: '/missions/:id/offers',
            builder: (context, state) {
              final id = state.pathParameters['id']!;
              final posterId = FirebaseAuth.instance.currentUser?.uid ?? '';
              return OffersPage(missionId: id, posterId: posterId);
            },
          ),

          // --- Détail offre ---
          GoRoute(
            path: '/missions/:missionId/offers/:offerId',
            builder: (context, state) {
              final missionId = state.pathParameters['missionId']!;
              final offerId = state.pathParameters['offerId']!;
              return OfferDetailPage(
                missionId: missionId,
                offerId: offerId,
              );
            },
          ),

          // --- Chat ---
          GoRoute(
            path: '/chat',
            builder: (_, __) => const ThreadsPage(),
          ),
          GoRoute(
            path: '/chat/:id',
            builder: (_, state) {
              final chatId = state.pathParameters['id']!;
              return ChatDetailPage(chatId: chatId);
            },
          ),

          // --- Profil privé ---
          GoRoute(
            path: '/profile',
            builder: (_, __) => const ProfilePage(),
          ),

          // --- Profil public d’un autre user ---
          GoRoute(
            path: '/profile/:userId',
            builder: (_, state) {
              final userId = state.pathParameters['userId']!;
              return PublicProfilePage(userId: userId);
            },
          ),

          // =========================================================
          // 🔹 AVIS & NOTES
          // =========================================================
          GoRoute(
            path: '/reviews/:userId',
            name: 'reviews',
            builder: (context, state) {
              final userId = state.pathParameters['userId']!;
              final missionId = state.uri.queryParameters['missionId'] ?? '';
              final missionTitle = state.uri.queryParameters['missionTitle'] ?? '';

              return ReviewsPage(
                userId: userId,
                missionId: missionId,
                missionTitle: missionTitle,
              );
            },
          ),

          // --- Paiements (placeholder) ---
        ],
      ),
    ],
  );
}
