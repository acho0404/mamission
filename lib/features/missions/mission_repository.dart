import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class MissionRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<void> saveMission({
    String? missionId, // null = création, non-null = modification
    required String title,
    required String description,
    required double budget,
    required double duration,
    required DateTime deadline,
    String? timeStr, // "HH:mm"
    required String category,
    required String location,
    required String mode, // "Sur place" ou "À distance"
    required String flexibility,
    required Map<String, double>? position, // {lat, lng}
    String? photoUrl,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception("Vous devez être connecté pour publier.");

    // Données communes (Create & Update)
    final Map<String, dynamic> data = {
      "title": title,
      "description": description,
      "budget": budget,
      "duration": duration,
      "deadline": Timestamp.fromDate(deadline),
      "missionTime": timeStr,
      "category": category,
      "location": location,
      "position": position,
      "mode": mode,
      "flexibility": flexibility,
      "updatedAt": FieldValue.serverTimestamp(),
    };

    if (missionId == null) {
      // --- CAS 1 : CRÉATION ---
      // On récupère les infos du user pour les mettre dans la mission (dénormalisation)
      final userDoc = await _db.collection('users').doc(user.uid).get();
      final userData = userDoc.data() ?? {};

      await _db.collection('missions').add({
        ...data,
        "posterId": user.uid,
        "posterName": userData['name'] ?? 'Utilisateur',
        "posterPhotoUrl": userData['photoUrl'] ?? '',
        "posterRating": userData['rating'] ?? 0.0, // Pour le tri futur
        "posterReviewsCount": userData['reviewsCount'] ?? 0,
        "photoUrl": photoUrl ?? '',
        "status": "open",
        "offersCount": 0,
        "createdAt": FieldValue.serverTimestamp(),
      });
    } else {
      // --- CAS 2 : MISE À JOUR ---
      final updateData = Map<String, dynamic>.from(data);
      // On ne met à jour l'image que si une nouvelle a été envoyée
      if (photoUrl != null) {
        updateData["photoUrl"] = photoUrl;
      }
      await _db.collection('missions').doc(missionId).update(updateData);
    }
  }
}