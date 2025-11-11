import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'firebase_options.dart';
import 'app/app.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('fr_FR', null);

  // --- Initialisation Firebase ---
  print('🔹 Initialisation Firebase...');
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  print('✅ Firebase initialisée.');

  // --- Initialisation FCM ---
  await _initFCM();

  // --- Gestion de la présence utilisateur ---
  _initUserPresence();

  // --- Lancement de l’application ---
  runApp(const ProviderScope(child: MyApp()));
  print('🚀 Application lancée !');
}

/// 🔹 Initialisation de Firebase Cloud Messaging
Future<void> _initFCM() async {
  final fcm = FirebaseMessaging.instance;

  // Demande de permission (iOS + Android 13+)
  await fcm.requestPermission();

  // Récupère le token unique de l’appareil
  final token = await fcm.getToken();
  print('🔑 FCM Token: $token');

  // Sauvegarde du token dans Firestore (user connecté)
  final user = FirebaseAuth.instance.currentUser;
  if (user != null && token != null) {
    await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
      'fcmToken': token,
    });
  }

  // Écoute des messages reçus en foreground
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    print('💬 Notification reçue: ${message.notification?.title}');
  });

  // (Optionnel) Écoute quand l’utilisateur clique sur une notif
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    print('📲 Notification ouverte: ${message.notification?.title}');
  });
}

/// 🔹 Gère la présence (en ligne / hors ligne)
void _initUserPresence() {
  final auth = FirebaseAuth.instance;
  FirebaseFirestore db = FirebaseFirestore.instance;

  auth.authStateChanges().listen((user) async {
    if (user == null) return;

    final userRef = db.collection('users').doc(user.uid);

    // Marquer en ligne
    await userRef.update({
      'isOnline': true,
      'lastSeen': FieldValue.serverTimestamp(),
    });

    // Écoute du cycle de vie de l’app
    WidgetsBinding.instance.addObserver(_PresenceObserver(userRef));
  });
}

/// 🔹 Classe qui écoute les états du cycle de vie Flutter
class _PresenceObserver with WidgetsBindingObserver {
  final DocumentReference userRef;

  _PresenceObserver(this.userRef);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _setOnline();
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _setOffline();
    }
  }

  Future<void> _setOnline() async {
    await userRef.update({
      'isOnline': true,
      'lastSeen': FieldValue.serverTimestamp(),
    });
    print("🟢 Utilisateur en ligne");
  }

  Future<void> _setOffline() async {
    await userRef.update({
      'isOnline': false,
      'lastSeen': FieldValue.serverTimestamp(),
    });
    print("🔴 Utilisateur hors ligne");
  }
}
