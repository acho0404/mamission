import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mamission/shared/apple_appbar.dart';

class FinanceDashboardPage extends StatefulWidget {
  const FinanceDashboardPage({super.key});

  @override
  State<FinanceDashboardPage> createState() => _FinanceDashboardPageState();
}

class _FinanceDashboardPageState extends State<FinanceDashboardPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.04),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic),
    );

    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    const kPrimary = Color(0xFF6C63FF);

    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Non connecté')),
      );
    }

    final missionsRef = FirebaseFirestore.instance
        .collection('missions')
        .where('assignedTo', isEqualTo: user.uid);

    return Scaffold(
      backgroundColor: const Color(0xFFF7F5FF),
      appBar: buildAppleMissionAppBar(
        title: "Portefeuille",
      ),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SlideTransition(
          position: _slideAnim,
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: missionsRef.snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(color: kPrimary),
                );
              }

              if (snap.hasError) {
                return Center(
                  child: Text(
                    "Erreur : ${snap.error}",
                    style: const TextStyle(color: Colors.red),
                  ),
                );
              }

              final docs = snap.data?.docs ?? [];

              // ---- Calcul des stats financières ----
              double totalCompleted = 0;
              double totalInProgress = 0;
              double totalPendingPayout = 0;

              final now = DateTime.now();
              final monthStart = DateTime(now.year, now.month, 1);

              double thisMonthEarnings = 0;
              int missionsCompletedCount = 0;
              int missionsInProgressCount = 0;

              // Pour le graphique (revenus sur les 7 derniers jours)
              final Map<String, double> dailyEarnings = {};

              for (final doc in docs) {
                final data = doc.data();
                final status = (data['status'] ?? '').toString();
                final double price = ((data['assignedPrice'] ??
                    data['agreedPrice'] ??
                    data['budget'] ??
                    0) as num)
                    .toDouble();

                // Date de référence pour earnings
                final Timestamp? tsCompleted = data['completedAt'] as Timestamp?;
                final Timestamp? tsUpdated = data['updatedAt'] as Timestamp?;
                final Timestamp? tsCreated = data['createdAt'] as Timestamp?;
                final DateTime refDate = (tsCompleted ??
                    tsUpdated ??
                    tsCreated ??
                    Timestamp.now())
                    .toDate();

                if (status == 'completed' || status == 'paid') {
                  totalCompleted += price;
                  missionsCompletedCount++;

                  if (refDate.isAfter(monthStart)) {
                    thisMonthEarnings += price;
                  }

                  // Graphique 7 jours
                  final dateKey = DateFormat('yyyy-MM-dd').format(refDate);
                  dailyEarnings[dateKey] = (dailyEarnings[dateKey] ?? 0) + price;
                } else if (status == 'in_progress') {
                  totalInProgress += price;
                  totalPendingPayout += price;
                  missionsInProgressCount++;
                } else if (status == 'pending_payment') {
                  totalPendingPayout += price;
                }
              }

              final availableBalance = totalCompleted; // à adapter plus tard si besoin

              // Prépare les points du graphique (7 derniers jours)
              final List<_EarningPoint> points = [];
              for (int i = 6; i >= 0; i--) {
                final day = now.subtract(Duration(days: i));
                final key = DateFormat('yyyy-MM-dd').format(day);
                final amount = dailyEarnings[key] ?? 0;
                points.add(_EarningPoint(day, amount));
              }

              return RefreshIndicator(
                onRefresh: () async {
                  // simple "no-op" : le StreamBuilder se mettra à jour tout seul
                  await Future<void>.delayed(const Duration(milliseconds: 200));
                },
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                        child: _HeaderCard(
                          available: availableBalance,
                          pending: totalPendingPayout,
                          thisMonth: thisMonthEarnings,
                        ),
                      ),
                    ),

                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20.0),
                        child: _StatsGrid(
                          missionsInProgress: missionsInProgressCount,
                          missionsCompleted: missionsCompletedCount,
                          thisMonth: thisMonthEarnings,
                          totalEarned: totalCompleted,
                        ),
                      ),
                    ),

                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                        child: _EarningsChartCard(points: points),
                      ),
                    ),

                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              "Transactions récentes",
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              "Voir tout",
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade600,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                            (context, index) {
                          if (index >= math.min(10, docs.length)) {
                            return null;
                          }
                          final doc = docs[index];
                          final data = doc.data();
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                            child: _TransactionTile(data: data),
                          );
                        },
                      ),
                    ),

                    const SliverToBoxAdapter(
                      child: SizedBox(height: 32),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// HEADER CARD
// ---------------------------------------------------------------------------

class _HeaderCard extends StatelessWidget {
  final double available;
  final double pending;
  final double thisMonth;

  const _HeaderCard({
    required this.available,
    required this.pending,
    required this.thisMonth,
  });

  @override
  Widget build(BuildContext context) {
    const kPrimary = Color(0xFF6C63FF);
    final currencyFormat = NumberFormat.currency(locale: 'fr_FR', symbol: '€');

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [kPrimary, Color(0xFF8A7FFC)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.16),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_balance_wallet_rounded,
                  color: Colors.white, size: 22),
              const SizedBox(width: 8),
              Text(
                "Solde disponible",
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Icon(Icons.shield_moon_outlined,
                        size: 14, color: Colors.white.withOpacity(0.9)),
                    const SizedBox(width: 4),
                    Text(
                      "Sécurisé",
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              )
            ],
          ),
          const SizedBox(height: 14),
          Text(
            currencyFormat.format(available),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _HeaderPill(
                label: "En attente",
                value: currencyFormat.format(pending),
              ),
              const SizedBox(width: 8),
              _HeaderPill(
                label: "Ce mois-ci",
                value: currencyFormat.format(thisMonth),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeaderPill extends StatelessWidget {
  final String label;
  final String value;

  const _HeaderPill({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 11,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// STATS GRID (petites cartes)
// ---------------------------------------------------------------------------

class _StatsGrid extends StatelessWidget {
  final int missionsInProgress;
  final int missionsCompleted;
  final double thisMonth;
  final double totalEarned;

  const _StatsGrid({
    required this.missionsInProgress,
    required this.missionsCompleted,
    required this.thisMonth,
    required this.totalEarned,
  });

  @override
  Widget build(BuildContext context) {
    final numberFormat = NumberFormat.compactCurrency(
      locale: 'fr_FR',
      symbol: '€',
      decimalDigits: 1,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 18),
        const Text(
          "Résumé",
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 2,
          childAspectRatio: 1.7,
          shrinkWrap: true,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _StatCard(
              icon: Icons.trending_up_rounded,
              iconBg: const Color(0xFFEFF3FF),
              title: "Revenus ce mois",
              value: numberFormat.format(thisMonth),
              subtitle: "Basé sur les missions terminées",
            ),
            _StatCard(
              icon: Icons.emoji_events_outlined,
              iconBg: const Color(0xFFFFF4E5),
              title: "Total gagné",
              value: numberFormat.format(totalEarned),
              subtitle: "Depuis vos débuts",
            ),
            _StatCard(
              icon: Icons.work_outline_rounded,
              iconBg: const Color(0xFFE9FBF1),
              title: "Missions en cours",
              value: missionsInProgress.toString(),
              subtitle: "En statut \"En cours\"",
            ),
            _StatCard(
              icon: Icons.check_circle_outline_rounded,
              iconBg: const Color(0xFFFBE9FF),
              title: "Missions complétées",
              value: missionsCompleted.toString(),
              subtitle: "Prêtes à être notées",
            ),
          ],
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final String title;
  final String value;
  final String subtitle;

  const _StatCard({
    required this.icon,
    required this.iconBg,
    required this.title,
    required this.value,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    const borderRadius = 18.0;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 18, color: const Color(0xFF6C63FF)),
          ),
          const Spacer(),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF2F2E41),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// EARNINGS CHART
// ---------------------------------------------------------------------------

class _EarningPoint {
  final DateTime date;
  final double value;

  _EarningPoint(this.date, this.value);
}

class _EarningsChartCard extends StatelessWidget {
  final List<_EarningPoint> points;

  const _EarningsChartCard({required this.points});

  @override
  Widget build(BuildContext context) {
    final maxValue = points.isEmpty
        ? 0.0
        : points.map((e) => e.value).reduce(math.max);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                "Évolution des revenus",
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1EEFF),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: const [
                    Icon(Icons.timeline_rounded,
                        size: 14, color: Color(0xFF6C63FF)),
                    SizedBox(width: 4),
                    Text(
                      "7 derniers jours",
                      style: TextStyle(
                        color: Color(0xFF6C63FF),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            maxValue == 0
                ? "Les revenus apparaîtront ici une fois des missions terminées."
                : "Vue simplifiée de vos gains récents.",
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 140,
            child: CustomPaint(
              painter: _EarningsPainter(points),
              child: Container(),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final p in points)
                Expanded(
                  child: Text(
                    DateFormat('E', 'fr_FR').format(p.date)[0],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ),
            ],
          )
        ],
      ),
    );
  }
}

class _EarningsPainter extends CustomPainter {
  final List<_EarningPoint> points;

  _EarningsPainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    final maxVal = points
        .map((e) => e.value)
        .fold<double>(0, (prev, element) => math.max(prev, element));

    final double padding = 8.0;

    final linePaint = Paint()
      ..color = const Color(0xFF6C63FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()
      ..shader = const LinearGradient(
        colors: [
          Color(0xFF6C63FF),
          Color(0xFF6C63FF),
        ],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill
      ..color = const Color(0xFF6C63FF).withOpacity(0.12);

    final path = Path();
    final fillPath = Path();

    final int n = points.length;
    if (n < 2) return;

    double dx(int i) {
      if (n == 1) return size.width / 2;
      return padding +
          (size.width - 2 * padding) * (i / (n - 1));
    }

    double dy(double v) {
      if (maxVal == 0) {
        return size.height / 2;
      }
      final normalized = v / maxVal;
      return padding + (1 - normalized) * (size.height - 2 * padding);
    }

    // Build line path
    for (int i = 0; i < n; i++) {
      final x = dx(i);
      final y = dy(points[i].value);
      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height - padding);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    // Close fill path
    fillPath.lineTo(dx(n - 1), size.height - padding);
    fillPath.close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, linePaint);

    // Points
    final pointPaint = Paint()
      ..color = const Color(0xFF6C63FF)
      ..style = PaintingStyle.fill;

    for (int i = 0; i < n; i++) {
      final x = dx(i);
      final y = dy(points[i].value);
      canvas.drawCircle(Offset(x, y), 3.2, pointPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _EarningsPainter oldDelegate) {
    return oldDelegate.points != points;
  }
}

// ---------------------------------------------------------------------------
// TRANSACTION TILE
// ---------------------------------------------------------------------------

class _TransactionTile extends StatelessWidget {
  final Map<String, dynamic> data;

  const _TransactionTile({required this.data});

  @override
  Widget build(BuildContext context) {
    final status = (data['status'] ?? '').toString();
    final title = (data['title'] ?? 'Mission').toString();
    final double amount = ((data['assignedPrice'] ??
        data['agreedPrice'] ??
        data['budget'] ??
        0) as num)
        .toDouble();

    final Timestamp? ts = data['completedAt'] ??
        data['updatedAt'] ??
        data['createdAt'];
    final date = (ts is Timestamp) ? ts.toDate() : DateTime.now();
    final dateLabel = DateFormat('d MMM, HH:mm', 'fr_FR').format(date);

    Color badgeColor;
    String badgeText;

    switch (status) {
      case 'completed':
      case 'paid':
        badgeColor = Colors.green.shade50;
        badgeText = "Payé";
        break;
      case 'in_progress':
        badgeColor = Colors.blue.shade50;
        badgeText = "En cours";
        break;
      case 'pending_payment':
        badgeColor = Colors.orange.shade50;
        badgeText = "En attente";
        break;
      default:
        badgeColor = Colors.grey.shade100;
        badgeText = status.isEmpty ? "N/A" : status;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFF1EEFF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.work_outline_rounded,
                color: Color(0xFF6C63FF), size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  dateLabel,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                "${amount.toStringAsFixed(amount.truncateToDouble() == amount ? 0 : 2)} €",
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2F2E41),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: badgeColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  badgeText,
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey.shade800,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          )
        ],
      ),
    );
  }
}
