import 'package:flutter/material.dart';
import 'package:mamission/shared/apple_appbar.dart';

class WalletPage extends StatelessWidget {
  const WalletPage({super.key});

  @override
  Widget build(BuildContext context) {
    // --- DONNÉES FICTIVES (Pour la démo) ---
    // Scénario : 1240.50€ au total, dont 200€ de crédits non retirables
    const double totalBalance = 1240.50;
    const double creditsNonWithdrawable = 200.00;

    // Calcul du montant que l'on peut vraiment virer
    final double withdrawableAmount = totalBalance - creditsNonWithdrawable;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FF),
      appBar: buildAppleMissionAppBar(
        title: "Mon Portefeuille",
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
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
                  colors: [Color(0xFF6C63FF), Color(0xFF4F46E5)], // Violet -> Indigo
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
                      // CHANGEMENT ICI : "Solde disponible" (plus clair)
                      Text("Solde disponible",
                          style: TextStyle(color: Colors.white70, fontSize: 14)),
                      Icon(Icons.account_balance_wallet,
                          color: Colors.white30, size: 28),
                    ],
                  ),

                  // MONTANT TOTAL (Gros chiffre)
                  Text(
                    "${totalBalance.toStringAsFixed(2)} €",
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 36,
                        fontWeight: FontWeight.bold),
                  ),

                  // PILULE D'INFORMATION (Crédits)
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
                            // CHANGEMENT ICI : Texte explicatif court
                            "Dont ${creditsNonWithdrawable.toStringAsFixed(0)}€ de crédits (non retirables)",
                            style: const TextStyle(
                                color: Colors.white, fontSize: 12),
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
            // 2. BOUTONS D'ACTION
            // ------------------------------------------------------
            Row(
              children: [
                _buildActionButton(
                  context,
                  icon: Icons.add,
                  label: "Recharger",
                  color: const Color(0xFF6C63FF),
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text("Module de paiement (Stripe) à venir")));
                  },
                ),
                const SizedBox(width: 16),
                _buildActionButton(
                  context,
                  icon: Icons.arrow_outward,
                  label: "Retirer",
                  // Grisé si rien à retirer
                  color: withdrawableAmount > 0
                      ? const Color(0xFF1A1F36)
                      : Colors.grey,
                  onTap: () {
                    if (withdrawableAmount <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text(
                            "Vous n'avez pas de fonds retirables (seulement des crédits)."),
                        backgroundColor: Colors.orange,
                      ));
                      return;
                    }
                    // Ouvre la modale avec le VRAI montant retirable
                    _showWithdrawModal(context, withdrawableAmount);
                  },
                ),
              ],
            ),

            const SizedBox(height: 30),

            // ------------------------------------------------------
            // 3. HISTORIQUE
            // ------------------------------------------------------
            const Align(
              alignment: Alignment.centerLeft,
              child: Text("Transactions récentes",
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A1F36))),
            ),
            const SizedBox(height: 16),

            // Exemples de transactions
            _buildTransactionItem("Remboursement (Annulation)",
                "Aujourd'hui, 09:00", "+ 50.00 €", true,
                isCredit: true),
            _buildTransactionItem(
                "Mission Jardinage", "Hier, 14:30", "+ 45.00 €", true,
                isCredit: false),
            _buildTransactionItem(
                "Mission Déménagement", "20 Nov", "+ 120.00 €", true,
                isCredit: false),
          ],
        ),
      ),
    );
  }

  // --- MODALE DE RETRAIT (CLAIRE ET TRANSPARENTE) ---
  // --- MODALE DE RETRAIT INTELLIGENTE ---
  void _showWithdrawModal(BuildContext context, double maxAmount) {
    final amountCtrl = TextEditingController();

    // On utilise un StatefulBuilder pour mettre à jour l'état (erreurs/bouton)
    // uniquement à l'intérieur de la modale sans recharger toute la page.
    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // Permet de remonter quand le clavier s'ouvre
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {

          // Logique de validation
          double? currentVal = double.tryParse(amountCtrl.text.replaceAll(',', '.'));
          bool isOverLimit = (currentVal ?? 0) > maxAmount;
          bool isValid = (currentVal != null) && (currentVal > 0) && !isOverLimit;

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
                const Text("Effectuer un virement",
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),

                // Message informatif
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.withOpacity(0.2)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info, color: Colors.blue, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          "Plafond de retrait disponible : ${maxAmount.toStringAsFixed(2)} €",
                          style: TextStyle(color: Colors.blue.shade800, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Champ de saisie avec bouton MAX
                TextField(
                  controller: amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    labelText: "Montant à retirer",
                    suffixText: "€",
                    errorText: isOverLimit ? "Montant supérieur au solde disponible" : null,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    suffixIcon: TextButton(
                      onPressed: () {
                        // Action bouton MAX
                        setModalState(() {
                          amountCtrl.text = maxAmount.toStringAsFixed(2);
                        });
                      },
                      child: const Text("MAX", style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  onChanged: (val) {
                    // Force la mise à jour de l'UI pour activer/désactiver le bouton
                    setModalState(() {});
                  },
                ),

                const SizedBox(height: 24),

                // Bouton de validation
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: isValid
                        ? () {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(
                              "Demande de virement de ${amountCtrl.text} € envoyée !")));
                      // TODO: Appeler ici la fonction Stripe Payout
                    }
                        : null, // Si pas valide, le bouton est null (grisé)
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6C63FF),
                      disabledBackgroundColor: Colors.grey.shade300, // Couleur grisâtre quand bloqué
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    child: const Text(
                      "Confirmer le virement",
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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

  // --- WIDGETS UI ---

  Widget _buildActionButton(BuildContext context,
      {required IconData icon,
        required String label,
        required Color color,
        required VoidCallback onTap}) {
    return Expanded(
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: color,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          side: BorderSide(color: color.withOpacity(0.3), width: 1),
        ),
      ),
    );
  }

  Widget _buildTransactionItem(String title, String date, String amount,
      bool isPositive,
      {bool isCredit = false}) {
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
              offset: const Offset(0, 4)),
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
                  : (isPositive ? Icons.arrow_downward : Icons.arrow_upward),
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
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, color: Color(0xFF1A1F36))),
                Text(date,
                    style: const TextStyle(color: Colors.grey, fontSize: 12)),
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
                const Text("Crédit",
                    style: TextStyle(
                        fontSize: 10,
                        color: Colors.purple,
                        fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }
}