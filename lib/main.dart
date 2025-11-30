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
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:mamission/core/secrets.dart';
// ---------------------------------------------------------------------------
// 🔥 PATCH 1 : Handler Background placé tout en haut (obligatoire)
// ---------------------------------------------------------------------------
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  print("🔔 Background message: ${message.messageId}");
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('fr_FR', null);

  print('🔹 Initialisation Firebase...');
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  print('✅ Firebase initialisée.');
  Stripe.publishableKey = Secrets.stripePublishableKey;
  await Stripe.instance.applySettings();

  // ---------------------------------------------------------------------------
  // 🔥 PATCH 2 : enregistrer le handler background AVANT _initFCM()
  // ---------------------------------------------------------------------------
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // ---------------------------------------------------------------------------
  // 🔥 PATCH 3 : init FCM (foreground + local notifications)
  // ---------------------------------------------------------------------------
  await _initFCM();

  // ---------------------------------------------------------------------------
  // 🔥 PATCH 4 : enregistre fcmToken dès qu'un user se connecte = FIX critique
  // ---------------------------------------------------------------------------
  FirebaseAuth.instance.authStateChanges().listen((user) async {
    if (user == null) return;
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'fcmToken': token,
      });
      print("🟣 Token FCM enregistré pour ${user.uid}");
    }
  });
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );
  // --- Gestion de la présence utilisateur ---
  _initUserPresence();

  runApp(const ProviderScope(child: MyApp()));
  print('🚀 Application lancée !');
}

// ---------------------------------------------------------------------------
// 🔥 FCM INITIALISATION
// ---------------------------------------------------------------------------
Future<void> _initFCM() async {
  final fcm = FirebaseMessaging.instance;

  // Local Notifications
  final localNotifications = FlutterLocalNotificationsPlugin();

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'high_importance_channel',
    'Notifications Importantes',
    description: 'Ce canal est utilisé pour les notifications importantes.',
    importance: Importance.high,
  );

  await localNotifications
      .resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await localNotifications.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      ),
    ),
  );
  await localNotifications
      .resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>()
      ?.requestNotificationsPermission(); // <--- Le nouveau nom
  // Permissions
  await fcm.requestPermission();

  // Token actuel
  final token = await fcm.getToken();
  print('🔑 FCM Token: $token');

  final user = FirebaseAuth.instance.currentUser;
  if (user != null && token != null) {
    await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
      'fcmToken': token,
    });
  }

  // Token refresh
  fcm.onTokenRefresh.listen((newToken) async {
    print('🔄 Nouveau Token FCM: $newToken');
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'fcmToken': newToken,
      });
    }
  });

  // Foreground
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    print('💬 Notification reçue en foreground: ${message.notification?.title}');

    final notification = message.notification;
    final android = message.notification?.android;

    if (notification != null) {
      localNotifications.show(
        notification.hashCode,
        notification.title,
        notification.body,
        NotificationDetails(
          android: android != null
              ? AndroidNotificationDetails(
            channel.id,
            channel.name,
            channelDescription: channel.description,
            icon: '@mipmap/ic_launcher',
            importance: Importance.high,
            priority: Priority.high,
          )
              : null,
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
      );
    }
  });

  // Ouvrir l’app depuis une notif
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    print('📲 Notification ouverte: ${message.notification?.title}');
    // tu pourras ajouter navigation ici
  });
}

// ---------------------------------------------------------------------------
// 🔥 PRESENCE UTILISATEUR (inchangé)
// ---------------------------------------------------------------------------
void _initUserPresence() {
  final auth = FirebaseAuth.instance;
  FirebaseFirestore db = FirebaseFirestore.instance;

  auth.authStateChanges().listen((user) async {
    if (user == null) return;

    final userRef = db.collection('users').doc(user.uid);

    await userRef.update({
      'isOnline': true,
      'lastSeen': FieldValue.serverTimestamp(),
    });

    WidgetsBinding.instance.addObserver(_PresenceObserver(userRef));
  });
}

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
