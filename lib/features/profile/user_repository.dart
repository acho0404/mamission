import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class UserRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Mise à jour du profil complet
  Future<void> updateProfile({
    required String uid,
    required String firstName,
    required String lastName,
    required String bio,
    required String tagline,
    required String city,
    required double radius,
    required List<String> skills,
    required List<String> equipments,
    required bool isProvider,
    String? photoUrl,
    List<String>? portfolio,
  }) async {
    // 1. Mise à jour Auth (Nom d'affichage)
    String fullName = "$firstName $lastName".trim();
    if (fullName.isEmpty) fullName = "Utilisateur";
    await _auth.currentUser?.updateDisplayName(fullName);

    // 2. Mise à jour Firestore
    await _db.collection('users').doc(uid).set({
      'name': fullName,
      'bio': bio,
      'tagline': tagline,
      'city': city,
      'radius': radius,
      'skills': skills,
      'equipments': equipments,
      'isProvider': isProvider,
      'photoUrl': photoUrl,
      'portfolio': portfolio,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
  // --- AJOUTER CECI DANS LA CLASSE UserRepository ---

  // 2. Mise à jour BANCAIRE (Moyens de paiement / RIB)
  Future<void> updateBankingInfo({
    required String uid,
    required String iban,
    required String bic,
    required String accountHolderName, // <--- C'EST CE PARAMÈTRE QUI MANQUAIT
  }) async {
    await _db.collection('users').doc(uid).update({
      'iban': iban,
      'bic': bic,
      'accountHolderName': accountHolderName,
      'bankingUpdatedAt': FieldValue.serverTimestamp(),
    });
  }
  // 3. Supprimer les infos bancaires
  Future<void> deleteBankingInfo(String uid) async {
    await _db.collection('users').doc(uid).update({
      'iban': FieldValue.delete(),
      'bic': FieldValue.delete(),
      'accountHolderName': FieldValue.delete(),
      'bankingUpdatedAt': FieldValue.serverTimestamp(),
    });
  }
}