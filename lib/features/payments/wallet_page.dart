import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:mamission/shared/apple_appbar.dart';

class WalletPage extends StatelessWidget {
  const WalletPage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final uid = user.uid;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FF),
      appBar: buildAppleMissionAppBar(
        title: "Mon Portefeuille",
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          onPressed: () => context.pop(),
        ),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snapshot.data!.data() ?? {};

          // 💰 Solde réel dans Firestore
          final double totalBalance =
          (data['walletBalance'] is num) ? (data['walletBalance'] as num).toDouble() : 0.0;

          // Crédits non retirables (ou 0 si absent)
          final double creditsNonWithdrawable =
          (data['walletCreditsNonWithdrawable'] is num)
              ? (data['walletCreditsNonWithdrawable'] as num).toDouble()
              : 0.0;

          final double withdrawableAmount =
          (totalBalance - creditsNonWithdrawable).clamp(0, double.infinity);

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                // ------------------------------------------------------
                // 1. CARTE PRINCIPALE (SOLDE)
                // ------------------------------------------------------
                Container(
                  width: double.infinity,
                  height: 220,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6C63FF), Color(0xFF4F46E5)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF6C63FF).withOpacity(0.4),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "Solde disponible",
                            style: TextStyle(color: Colors.white70, fontSize: 14),
                          ),
                          Icon(
                            Icons.account_balance_wallet,
                            color: Colors.white30,
                            size: 28,
                          ),
                        ],
                      ),
                      Text(
                        "${totalBalance.toStringAsFixed(2)} €",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline,
                                color: Colors.white70, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                "Dont ${creditsNonWithdrawable.toStringAsFixed(0)}€ de crédits (non retirables)",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 30),

                // ------------------------------------------------------
                // 2. BOUTON RETIRER (VÉRIFICATION RIB)
                // ------------------------------------------------------
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      await _handleWithdrawTap(context, withdrawableAmount);
                    },
                    icon: const Icon(Icons.arrow_outward, size: 20),
                    label: const Text("Demander un virement"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1A1F36),
                      foregroundColor: Colors.white,
                      elevation: 4,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 30),

                // ------------------------------------------------------
                // 3. HISTORIQUE RÉEL
                // ------------------------------------------------------
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "Transactions récentes",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A1F36),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('walletTransactions')
                      .where('userId', isEqualTo: uid)
                      .orderBy('createdAt', descending: true)
                      .limit(20)
                      .snapshots(),
                  builder: (context, txSnap) {
                    if (txSnap.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }

                    final docs = txSnap.data?.docs ?? [];
                    if (docs.isEmpty) {
                      return Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.history_toggle_off,
                                color: Colors.grey, size: 20),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                "Aucune transaction pour le moment.",
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    return Column(
                      children: docs.map((doc) {
                        final tx = doc.data();
                        final title = tx['title'] as String? ?? 'Transaction';
                        final type = tx['type'] as String? ?? 'in'; // in / out
                        final isCredit = tx['isCredit'] == true;
                        final num amountNum = tx['amount'] ?? 0;
                        final double amount = amountNum.toDouble();
                        final ts = tx['createdAt'] as Timestamp?;
                        final date = ts?.toDate() ?? DateTime.now();

                        final isIncoming = type != 'out';

                        final formattedDate =
                        _formatTxDate(date); // "Aujourd'hui", "Hier", etc.

                        final sign = isIncoming ? "+" : "-";
                        final amountStr =
                            "$sign ${amount.toStringAsFixed(2)} €";

                        return _buildTransactionItem(
                          title,
                          formattedDate,
                          amountStr,
                          isIncoming,
                          isCredit: isCredit,
                        );
                      }).toList(),
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // --- FORMATAGE DATES (simple mais propre) ---
  static String _formatTxDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(date.year, date.month, date.day);

    if (d == today) {
      return "Aujourd'hui, ${DateFormat.Hm('fr_FR').format(date)}";
    } else if (d == today.subtract(const Duration(days: 1))) {
      return "Hier, ${DateFormat.Hm('fr_FR').format(date)}";
    } else {
      return DateFormat('dd MMM, HH:mm', 'fr_FR').format(date);
    }
  }

  // --- LOGIQUE DE VÉRIFICATION RIB + SNACKBAR UNIQUE ---
  Future<void> _handleWithdrawTap(
      BuildContext context, double withdrawableAmount) async {
    final messenger = ScaffoldMessenger.of(context);

    if (withdrawableAmount <= 0) {
      // 👉 empêche les 50 snackbars qui se stackent
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text("Vous n'avez pas de fonds retirables."),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ));
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // petit loader
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      Navigator.pop(context); // fermer loader

      final data = doc.data() ?? {};
      final String? iban = data['iban'];

      if (iban == null || iban.isEmpty) {
        _showNoRibDialog(context);
      } else {
        _showWithdrawModal(context, withdrawableAmount);
      }
    } catch (e) {
      Navigator.pop(context);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text("Erreur: $e")),
        );
    }
  }

  void _showNoRibDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Informations manquantes"),
        content: const Text(
          "Vous devez renseigner votre IBAN (RIB) avant de pouvoir effectuer un virement.",
        ),
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Annuler"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              // plus tard : context.push('/settings/contact');
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("Redirection vers Paramètres..."),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6C63FF),
              foregroundColor: Colors.white,
            ),
            child: const Text("Ajouter mon RIB"),
          ),
        ],
      ),
    );
  }

  // --- MODALE DE RETRAIT (toujours placeholder, pas Stripe Connect) ---
  void _showWithdrawModal(BuildContext context, double maxAmount) {
    final amountCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          double? currentVal =
          double.tryParse(amountCtrl.text.replaceAll(',', '.'));
          bool isOverLimit = (currentVal ?? 0) > maxAmount;
          bool isValid =
              (currentVal != null) && (currentVal > 0) && !isOverLimit;

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              left: 24,
              right: 24,
              top: 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Effectuer un virement",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.withOpacity(0.2)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info,
                          color: Colors.blue, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          "Plafond disponible : ${maxAmount.toStringAsFixed(2)} €",
                          style: TextStyle(
                            color: Colors.blue.shade800,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: InputDecoration(
                    labelText: "Montant à retirer",
                    suffixText: "€",
                    errorText: isOverLimit
                        ? "Montant supérieur au solde disponible"
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    suffixIcon: TextButton(
                      onPressed: () {
                        setModalState(
                              () => amountCtrl.text =
                              maxAmount.toStringAsFixed(2),
                        );
                      },
                      child: const Text(
                        "MAX",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  onChanged: (_) => setModalState(() {}),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: isValid
                        ? () {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            "Demande de virement de ${amountCtrl.text} € envoyée !",
                          ),
                        ),
                      );
                      // TODO: Cloud Function Stripe Connect pour vrai payout
                    }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6C63FF),
                      disabledBackgroundColor: Colors.grey.shade300,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      "Confirmer le virement",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // --- ITEM TRANSACTION ---
  Widget _buildTransactionItem(
      String title,
      String date,
      String amount,
      bool isPositive, {
        bool isCredit = false,
      }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isCredit
                  ? Colors.purple.withOpacity(0.1)
                  : (isPositive
                  ? Colors.green.withOpacity(0.1)
                  : Colors.red.withOpacity(0.1)),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isCredit
                  ? Icons.card_giftcard
                  : (isPositive
                  ? Icons.arrow_downward
                  : Icons.arrow_upward),
              color: isCredit
                  ? Colors.purple
                  : (isPositive ? Colors.green : Colors.red),
              size: 20,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1F36),
                  ),
                ),
                Text(
                  date,
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                amount,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: isPositive ? Colors.green : Colors.black87,
                ),
              ),
              if (isCredit)
                const Text(
                  "Crédit",
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.purple,
                    fontWeight: FontWeight.bold,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
