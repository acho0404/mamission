import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class PushTokenService {
  static final _auth = FirebaseAuth.instance;
  static final _db = FirebaseFirestore.instance;

  /// À appeler après login / register
  static Future<void> saveDeviceToken() async {
    final user = _auth.currentUser;
    if (user == null) return;

    // Récupère le token FCM du device
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null) return;

    await _db.collection('users').doc(user.uid).set({
      'fcmTokens': FieldValue.arrayUnion([token]),
    }, SetOptions(merge: true));
  }
}
