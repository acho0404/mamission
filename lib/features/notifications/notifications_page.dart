import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'app_notification.dart';
import 'package:mamission/shared/apple_appbar.dart';

const Color _kPrimary = Color(0xFF6C63FF);
const Color _kBackground = Color(0xFFF7F9FC);
const Color _kTextDark = Color(0xFF1A1D26);
const Color _kTextGrey = Color(0xFF9EA3AE);

class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final stream = FirebaseFirestore.instance
        .collection('notifications')
        .where('userId', isEqualTo: user.uid)
        .snapshots();

    return Scaffold(
      backgroundColor: _kBackground,
      appBar: buildAppleMissionAppBar(
        title: 'Notifications',
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          onPressed: () => context.pop(),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: stream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const _EmptyNotifView();
          }

          final notifs = snapshot.data!.docs
              .map((d) => AppNotification.fromDoc(d))
              .toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

          final hasUnread = notifs.any((n) => !n.read);

          final grouped = _groupByDay(notifs);

          final children = <Widget>[];

          if (hasUnread) {
            children.add(
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => _markAllAsRead(user.uid),
                    child: const Text('Tout marquer comme lu'),
                  ),
                ),
              ),
            );
          } else {
            children.add(const SizedBox(height: 12));
          }

          grouped.forEach((label, list) {
            if (list.isEmpty) return;
            children.add(_SectionHeader(label: label));
            children.add(const SizedBox(height: 8));
            for (final notif in list) {
              children.add(
                _NotifCard(
                  notif: notif,
                  onTap: () => _onTap(context, user.uid, notif),
                ),
              );
            }
            children.add(const SizedBox(height: 12));
          });

          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: children,
          );
        },
      ),
    );
  }

  static Map<String, List<AppNotification>> _groupByDay(
      List<AppNotification> list) {
    final Map<String, List<AppNotification>> result = {
      "Aujourd'hui": [],
      "Hier": [],
      "Plus tôt": [],
    };

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    for (final n in list) {
      final d = DateTime(n.createdAt.year, n.createdAt.month, n.createdAt.day);
      if (d.isAtSameMomentAs(today)) {
        result["Aujourd'hui"]!.add(n);
      } else if (d.isAtSameMomentAs(yesterday)) {
        result["Hier"]!.add(n);
      } else {
        result["Plus tôt"]!.add(n);
      }
    }
    return result;
  }

  static Future<void> _markAllAsRead(String uid) async {
    final col = FirebaseFirestore.instance
        .collection('notifications')
        .where('userId', isEqualTo: uid)
        .where('read', isEqualTo: false);

    final snap = await col.get();
    final batch = FirebaseFirestore.instance.batch();
    for (final doc in snap.docs) {
      batch.update(doc.reference, {'read': true});
    }
    await batch.commit();
  }

  static Future<void> _onTap(
      BuildContext context,
      String uid,
      AppNotification notif,
      ) async {
    final ref =
    FirebaseFirestore.instance.collection('notifications').doc(notif.id);
    await ref.update({'read': true});

    switch (notif.type) {
      case 'offer_new':
      case 'offer_edited':
      case 'offer_withdrawn':
      case 'offer_accepted':
      case 'mission_cancelled_client':
      case 'mission_cancelled_provider':
      case 'mission_done':
      case 'review_new':
      case 'reviews_completed':
        if (notif.missionId.isNotEmpty) {
          context.push('/missions/${notif.missionId}');
        }
        break;
      default:
      // Notif purement informative → on reste ici
        break;
    }
  }
}

class _EmptyNotifView extends StatelessWidget {
  const _EmptyNotifView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(
            Icons.notifications_none_rounded,
            size: 52,
            color: _kTextGrey,
          ),
          SizedBox(height: 12),
          Text(
            "Aucune notification pour le moment 👌",
            style: TextStyle(fontSize: 15, color: _kTextGrey),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: _kTextGrey,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _NotifCard extends StatelessWidget {
  final AppNotification notif;
  final VoidCallback onTap;

  const _NotifCard({
    required this.notif,
    required this.onTap,
  });

  IconData _icon() {
    switch (notif.type) {
      case 'offer_new':
      case 'offer_edited':
      case 'offer_withdrawn':
      case 'offer_accepted':
        return Icons.local_offer_outlined;
      case 'mission_cancelled_client':
      case 'mission_cancelled_provider':
      case 'mission_done':
        return Icons.work_outline_rounded;
      case 'review_new':
      case 'reviews_completed':
        return Icons.star_border_rounded;
      default:
        return Icons.notifications_none_rounded;
    }
  }

  String _typeLabel() {
    switch (notif.type) {
      case 'offer_new':
      case 'offer_edited':
      case 'offer_withdrawn':
      case 'offer_accepted':
        return "Offre";
      case 'mission_cancelled_client':
      case 'mission_cancelled_provider':
      case 'mission_done':
        return "Mission";
      case 'review_new':
      case 'reviews_completed':
        return "Avis";
      default:
        return "Système";
    }
  }

  Color _typeColor() {
    switch (notif.type) {
      case 'offer_new':
      case 'offer_edited':
      case 'offer_withdrawn':
      case 'offer_accepted':
        return const Color(0xFFEC4899); // rose pour offres
      case 'mission_cancelled_client':
      case 'mission_cancelled_provider':
      case 'mission_done':
        return const Color(0xFF6366F1); // indigo missions
      case 'review_new':
      case 'reviews_completed':
        return const Color(0xFFF59E0B); // jaune avis
      default:
        return _kPrimary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isUnread = !notif.read;
    final typeColor = _typeColor();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              blurRadius: 14,
              offset: const Offset(0, 8),
              color: Colors.black.withOpacity(0.04),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // barre verticale pour non-lu
            Container(
              width: 4,
              height: 70,
              decoration: BoxDecoration(
                color: isUnread ? typeColor : Colors.transparent,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18),
                  bottomLeft: Radius.circular(18),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFF6C63FF),
                            Color(0xFFB39DFF),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Icon(
                        _icon(),
                        size: 18,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  notif.title,
                                  style: TextStyle(
                                    fontWeight: isUnread
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    fontSize: 14,
                                    color: _kTextDark,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _time(notif.createdAt),
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: _kTextGrey,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            notif.body,
                            style: const TextStyle(
                              fontSize: 13,
                              color: _kTextDark,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: typeColor.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  _typeLabel(),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: typeColor,
                                  ),
                                ),
                              ),
                              if (notif.missionTitle.isNotEmpty) ...[
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    notif.missionTitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: _kTextGrey,
                                    ),
                                  ),
                                ),
                              ],
                              if (isUnread) ...[
                                const SizedBox(width: 6),
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: typeColor,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _time(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return "À l'instant";
    if (diff.inMinutes < 60) return "${diff.inMinutes} min";
    if (diff.inHours < 24) return "${diff.inHours} h";
    if (diff.inDays == 1) return "Hier";
    return "${dt.day}/${dt.month}";
  }
}
