import 'package:cloud_firestore/cloud_firestore.dart';

class AppNotification {
  final String id;
  final String userId;
  final String type;
  final String title;
  final String body;
  final Map<String, dynamic> extra;
  final DateTime createdAt;
  final bool read;

  AppNotification({
    required this.id,
    required this.userId,
    required this.type,
    required this.title,
    required this.body,
    required this.extra,
    required this.createdAt,
    required this.read,
  });

  factory AppNotification.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final ts = data['createdAt'] as Timestamp?;

    return AppNotification(
      id: data['id'] as String? ?? doc.id,
      userId: data['userId'] as String? ?? '',
      type: data['type'] as String? ?? '',
      title: data['title'] as String? ?? '',
      body: data['body'] as String? ?? '',
      extra: (data['extra'] as Map<String, dynamic>?) ?? <String, dynamic>{},
      createdAt: ts?.toDate() ?? DateTime.now(),
      read: data['read'] as bool? ?? false,
    );
  }

  String get missionId => (extra['missionId'] as String?) ?? '';
  String get missionTitle => (extra['missionTitle'] as String?) ?? '';
  String get providerName => (extra['providerName'] as String?) ?? '';
}
