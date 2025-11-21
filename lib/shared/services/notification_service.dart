import 'package:cloud_firestore/cloud_firestore.dart';

class NotificationService {
  static final _col =
  FirebaseFirestore.instance.collection('notifications');

  /// Helper interne unique (généralise toutes les créations de notifs)
  static Future<void> _create({
    required String userId,
    required String type,
    required String title,
    required String body,
    Map<String, dynamic>? extra,
  }) async {
    if (userId.isEmpty) return;

    final doc = _col.doc();

    await doc.set({
      'id': doc.id,
      'userId': userId,
      'type': type,
      'title': title,
      'body': body,
      'extra': extra ?? {},
      'createdAt': FieldValue.serverTimestamp(),
      'read': false,
    });
  }

  // ----------------------------------------------------------
  // 🟣 OFFRES
  // ----------------------------------------------------------

  static Future<void> notifyNewOffer({
    required String clientUserId,
    required String missionId,
    required String missionTitle,
    required String providerName,
    required double price,
  }) {
    return _create(
      userId: clientUserId,
      type: 'offer_new',
      title: 'Nouvelle offre reçue',
      body:
      '$providerName a proposé ${price.toStringAsFixed(0)} € pour "$missionTitle".',
      extra: {
        'missionId': missionId,
        'missionTitle': missionTitle,
        'providerName': providerName,
        'price': price,
      },
    );
  }

  static Future<void> notifyOfferEdited({
    required String clientUserId,
    required String missionId,
    required String providerName,
    required double newPrice,
  }) {
    return _create(
      userId: clientUserId,
      type: 'offer_edited',
      title: 'Offre mise à jour',
      body:
      '$providerName a modifié son offre à ${newPrice.toStringAsFixed(0)} €.',
      extra: {
        'missionId': missionId,
        'providerName': providerName,
        'price': newPrice,
      },
    );
  }

  static Future<void> notifyOfferWithdrawn({
    required String clientUserId,
    required String missionId,
    required String providerName,
  }) {
    return _create(
      userId: clientUserId,
      type: 'offer_withdrawn',
      title: 'Offre retirée',
      body: '$providerName a retiré son offre.',
      extra: {
        'missionId': missionId,
        'providerName': providerName,
      },
    );
  }

  static Future<void> notifyMissionAssigned({
    required String providerUserId,
    required String missionId,
    required String missionTitle,
  }) {
    return _create(
      userId: providerUserId,
      type: 'offer_accepted',
      title: 'Offre acceptée 🎉',
      body: 'Votre offre sur "$missionTitle" a été acceptée.',
      extra: {
        'missionId': missionId,
        'missionTitle': missionTitle,
      },
    );
  }

  // ----------------------------------------------------------
  // 🟢 STATUT MISSION (Annulation, done…)
  // ----------------------------------------------------------

  static Future<void> notifyMissionCancelledByClient({
    required String missionId,
    required String missionTitle,
    String? assignedProviderId,
  }) async {
    if (assignedProviderId == null || assignedProviderId.isEmpty) return;

    return _create(
      userId: assignedProviderId,
      type: 'mission_cancelled_client',
      title: 'Mission annulée',
      body: 'Le client a annulé la mission "$missionTitle".',
      extra: {
        'missionId': missionId,
        'missionTitle': missionTitle,
      },
    );
  }

  static Future<void> notifyMissionCancelledByProvider({
    required String clientUserId,
    required String missionId,
    required String missionTitle,
    required String providerName,
  }) {
    return _create(
      userId: clientUserId,
      type: 'mission_cancelled_provider',
      title: 'Prestataire désisté',
      body: '$providerName s’est désisté de la mission "$missionTitle".',
      extra: {
        'missionId': missionId,
        'missionTitle': missionTitle,
        'providerName': providerName,
      },
    );
  }

  static Future<void> notifyMissionMarkedDone({
    required String providerUserId,
    required String missionId,
    required String missionTitle,
  }) {
    return _create(
      userId: providerUserId,
      type: 'mission_done',
      title: 'Mission terminée',
      body:
      'Le client a marqué la mission "$missionTitle" comme terminée.',
      extra: {
        'missionId': missionId,
        'missionTitle': missionTitle,
      },
    );
  }

  // ----------------------------------------------------------
  // ⭐ AVIS (Review)
  // ----------------------------------------------------------

  static Future<void> notifyNewReview({
    required String clientUserId,
    required String missionId,
    required String missionTitle,
    required String reviewerName,
    required double rating,
    required String reviewText,
  }) {
    return _create(
      userId: clientUserId,
      type: 'review_new',
      title: 'Nouvel avis reçu',
      body:
      '$reviewerName vous a laissé $rating★ pour "$missionTitle".',
      extra: {
        'missionId': missionId,
        'missionTitle': missionTitle,
        'reviewerName': reviewerName,
        'rating': rating,
        'reviewText': reviewText,
      },
    );
  }

  /// 🔥 Dernier cas : les deux avis sont postés → notification spéciale
  static Future<void> notifyMissionReviewsCompleted({
    required String clientUserId,
    required String providerUserId,
    required String missionId,
    required String missionTitle,
  }) async {
    // → Notifier le client
    await _create(
      userId: clientUserId,
      type: 'reviews_completed',
      title: 'Avis complétés',
      body:
      'Vous et votre prestataire avez laissé vos avis pour "$missionTitle".',
      extra: {
        'missionId': missionId,
        'missionTitle': missionTitle,
      },
    );

    // → Notifier le prestataire
    await _create(
      userId: providerUserId,
      type: 'reviews_completed',
      title: 'Avis complétés',
      body:
      'Vous et le client avez laissé vos avis pour "$missionTitle".',
      extra: {
        'missionId': missionId,
        'missionTitle': missionTitle,
      },
    );
  }
}

/// Petit utilitaire pour raccourcir un titre
String MissionTitle(String t) {
  if (t.length <= 40) return t;
  return '${t.substring(0, 37)}...';
}
