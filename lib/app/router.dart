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

      // routes auth
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

      // =========================================================
      // 🔹 SHELL GLOBAL
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
          GoRoute(path: '/chat', builder: (_, __) => const ThreadsPage()),

          GoRoute(
            path: '/chat/:id',
            builder: (_, state) {
              final chatId = state.pathParameters['id']!;
              return ChatDetailPage(chatId: chatId);
            },
          ),

          // --- Profil ---
          GoRoute(
            path: '/profile',
            builder: (_, __) => const ProfilePage(),
          ),

          // --- Profil public ---
          GoRoute(
            path: '/profile/:userId',
            builder: (_, state) {
              final userId = state.pathParameters['userId']!;
              return PublicProfilePage(userId: userId);
            },
          ),

          // =========================================================
          // 🔹 AVIS & NOTES — CORRIGÉ
          // =========================================================
          GoRoute(
            name: 'reviews',
            path: '/reviews/:userId',
            builder: (context, state) {
              final userId = state.pathParameters['userId']!;
              final missionId = state.uri.queryParameters['mission'] ?? '';
              final missionTitle = state.uri.queryParameters['title'] ?? 'Mission';

              return ReviewsPage(
                userId: userId,
                missionId: missionId,
                missionTitle: missionTitle,
              );
            },
          ),



          // --- Paiements (placeholder) ---
          GoRoute(
            path: '/payments',
            builder: (_, __) => const _PlaceholderPage('Paiement'),
          ),
        ],
      ),
    ],
  );
}
