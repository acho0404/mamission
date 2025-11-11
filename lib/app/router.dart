import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';

// --- Imports des pages principales ---
import '../features/shell/shell.dart';
import '../features/explore/explore_page.dart';
import '../features/missions/mission_list_page.dart';
import 'package:mamission/features/missions/mission_detail/mission_detail_page.dart';
import '../features/missions/mission_create_page.dart';
import '../features/missions/offers_page.dart';        // ✅ liste des offres reçues
import '../features/missions/offer_detail_page.dart';  // ✅ détail d’une offre
import '../features/chat/threads_page.dart';
import '../features/chat/chat_detail_page.dart';
import '../features/profile/profile_page.dart';
import '../features/reviews/reviews_page.dart';

// --- AUTH ---
import '../features/auth/login_page.dart';
import '../features/auth/register_page.dart';
import '../features/auth/reset_password_page.dart';

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
      final loggingIn = loc == '/login' || loc == '/register';
      if (user == null && !loggingIn) return '/login';
      if (user != null && loggingIn) return '/explore';
      return null;
    },
    routes: [

      // =========================================================
      // 🔹 AUTH
      // =========================================================
      GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
      GoRoute(path: '/register', builder: (context, state) => const RegisterPage()),
      GoRoute(path: '/reset', builder: (context, state) => const ResetPasswordPage()),

      // =========================================================
      // 🔹 PAGE DE CRÉATION / ÉDITION DE MISSION
      // (⚠️ hors Shell pour éviter blocage du push depuis MissionDetail)
      // =========================================================
      GoRoute(
        path: '/missions/create',
        builder: (context, state) {
          final editId = state.uri.queryParameters['edit'];
          print("🟣 [Router] MissionCreatePage appelée avec editId=$editId");
          return MissionCreatePage(editMissionId: editId);
        },
      ),

      // =========================================================
      // 🔹 SHELL PRINCIPAL (bottom navigation)
      // =========================================================
      ShellRoute(
        builder: (context, state, child) => ShellScaffold(child: child),
        routes: [

          // --- Explore ---
          GoRoute(
            path: '/explore',
            builder: (context, state) => const ExplorePage(),
          ),

          // --- Liste des missions ---
          GoRoute(
            path: '/missions',
            builder: (context, state) => const MissionListPage(),
          ),

          // --- Détail d’une mission ---
          GoRoute(
            path: '/missions/:id',
            builder: (context, state) {
              final missionId = state.pathParameters['id']!;
              return MissionDetailPage(missionId: missionId);
            },
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

          // --- Détail d’une seule offre ---
          GoRoute(
            path: '/missions/:missionId/offers/:offerId',
            builder: (context, state) {
              final missionId = state.pathParameters['missionId']!;
              final offerId = state.pathParameters['offerId']!;
              return OfferDetailPage(missionId: missionId, offerId: offerId);
            },
          ),

          // --- Chat ---
          GoRoute(path: '/chat', builder: (context, state) => const ThreadsPage()),
          GoRoute(
            path: '/chat/:id',
            builder: (context, state) {
              final chatId = state.pathParameters['id']!;
              return ChatDetailPage(chatId: chatId);
            },
          ),

          // --- Profil utilisateur ---
          GoRoute(
            path: '/profile',
            builder: (context, state) => const ProfilePage(),
          ),

          // --- Avis utilisateur ---
          GoRoute(
            path: '/reviews/:userId',
            builder: (context, state) {
              final userId = state.pathParameters['userId']!;
              return ReviewsPage(userId: userId);
            },
          ),

          // --- Placeholder Paiement ---
          GoRoute(
            path: '/payments',
            builder: (context, state) => const _PlaceholderPage('Paiement'),
          ),
        ],
      ),
    ],
  );
}
