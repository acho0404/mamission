import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

const Color kPrimary = Color(0xFF6C63FF);
const Color kTextDark = Color(0xFF1A1D26);
const Color kTextGrey = Color(0xFF9EA3AE);
const Color kBackground = Color(0xFFF7F9FC);

class VisibilitySubscriptionCheckoutPage extends StatefulWidget {
  final String plan;

  const VisibilitySubscriptionCheckoutPage({
    super.key,
    required this.plan,
  });

  @override
  State<VisibilitySubscriptionCheckoutPage> createState() =>
      _VisibilitySubscriptionCheckoutPageState();
}

class _VisibilitySubscriptionCheckoutPageState
    extends State<VisibilitySubscriptionCheckoutPage> {
  bool _loading = false;
  String? _error;

  // ---------------------------------------------------------------------------
  // LOGIQUE STRIPE (inchangée, juste entourée de joli UI)
  // ---------------------------------------------------------------------------
  Future<void> _startPaymentProcess() async {
    if (_loading) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // ✅ région par défaut (us-central1, comme tes fonctions)
      final functions = FirebaseFunctions.instance;

      // 1. Création du PaymentIntent (backend Stripe)
      final result = await functions
          .httpsCallable('createVisibilitySubscriptionPaymentIntent')
          .call(<String, dynamic>{
        'plan': widget.plan, // même si ta CF ne s’en sert pas pour l’instant
      });

      // On force en Map pour éviter les cast foireux
      final data = Map<String, dynamic>.from(result.data as Map);
      debugPrint('Visibility paymentIntent data: $data');

      final String? clientSecret =
      (data['clientSecret'] ??
          data['paymentIntentClientSecret'] ??
          data['paymentIntent'])
      as String?;

      if (clientSecret == null || clientSecret.isEmpty) {
        throw Exception('Client secret manquant dans la réponse CF.');
      }

      // 2. Init Stripe PaymentSheet
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: clientSecret,
          merchantDisplayName: 'MaMission Premium',
          style: ThemeMode.light,
          appearance: const PaymentSheetAppearance(
            colors: PaymentSheetAppearanceColors(
              primary: kPrimary,
            ),
          ),
        ),
      );

      // 3. Affichage de la sheet Stripe (carte / GPay / ApplePay…)
      await Stripe.instance.presentPaymentSheet();

      // 4. Activation Backend (profil vérifié + abonnement)
      await functions
          .httpsCallable('activateVisibilitySubscription')
          .call(<String, dynamic>{
        'plan': widget.plan,
      });

      if (!mounted) return;

      // Succès UX
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Paiement réussi ! Votre compte est vérifié.'),
          backgroundColor: Colors.green,
        ),
      );

      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return;
      Navigator.of(context).pop();
    } on StripeException catch (e) {
      debugPrint('StripeException: ${e.error.code} - ${e.error.message}');
      if (!mounted) return;

      if (e.error.code != FailureCode.Canceled) {
        setState(() {
          _error = e.error.message ?? 'Paiement échoué.';
        });
      }
      // si annulé volontairement → pas d’erreur, juste on enlève le loading
    } on FirebaseFunctionsException catch (e) {
      debugPrint(
          'FirebaseFunctionsException: code=${e.code} message=${e.message} details=${e.details}');
      if (!mounted) return;

      String msg;
      switch (e.code) {
        case 'unauthenticated':
          msg = "Vous devez être connecté pour activer cet avantage.";
          break;
        case 'not-found':
          msg =
          "Service de paiement indisponible. Vérifie que les fonctions Stripe sont bien déployées.";
          break;
        default:
          msg = e.message ?? 'Erreur serveur (${e.code}).';
      }

      setState(() {
        _error = msg;
      });
    } catch (e, st) {
      debugPrint('Unexpected error in _startPaymentProcess: $e');
      debugPrint(st.toString());
      if (!mounted) return;
      setState(() {
        _error = 'Une erreur technique est survenue.';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: kBackground,
        foregroundColor: kTextDark,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
        centerTitle: true,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.lock_outline_rounded, size: 16, color: Colors.black54),
            SizedBox(width: 6),
            Text(
              'Paiement sécurisé',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),

      // 🟣 CTA FIXE EN BAS COMME LES APPS PRO
      bottomNavigationBar: Container(
        padding: EdgeInsets.fromLTRB(
          24,
          12,
          24,
          16 + MediaQuery.of(context).padding.bottom,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 18,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  _error!,
                  style: const TextStyle(
                    color: Colors.red,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: _loading ? null : _startPaymentProcess,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kTextDark,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: _loading
                    ? const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
                    : const Text(
                  'Confirmer et payer 9,99 €',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.shield_outlined, size: 12, color: kTextGrey),
                SizedBox(width: 4),
                Text(
                  'Paiement crypté SSL et sécurisé par Stripe',
                  style: TextStyle(fontSize: 10, color: kTextGrey),
                ),
              ],
            ),
          ],
        ),
      ),

      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Petit stepper "Étape 2/2"
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.03),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.bolt_rounded,
                        size: 14, color: kPrimary),
                    SizedBox(width: 6),
                    Text(
                      'Étape 2 / 2 · Confirmation',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: kTextDark,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              const Text(
                'Plus qu’une étape ✨',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: kTextDark,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Vérifiez votre commande puis validez le paiement pour booster votre profil dans les recherches.',
                style: TextStyle(
                  fontSize: 13,
                  color: kTextGrey,
                  height: 1.4,
                ),
              ),

              const SizedBox(height: 24),

              // --- CARTE OFFRE PREMIUM (style proche du drag) ---
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // header violet
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      decoration: const BoxDecoration(
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(24),
                          topRight: Radius.circular(24),
                        ),
                        gradient: LinearGradient(
                          colors: [kPrimary, Color(0xFF8B7CFF)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Row(
                        children: const [
                          Icon(Icons.verified, color: Colors.white, size: 18),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Compte vérifié – offre recommandée',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // prix
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: const [
                              Text(
                                '9,99€',
                                style: TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.w900,
                                  color: kTextDark,
                                ),
                              ),
                              SizedBox(width: 4),
                              Padding(
                                padding: EdgeInsets.only(bottom: 4),
                                child: Text(
                                  '/ mois',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: kTextGrey,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Rentabilisé dès la 1ère mission réussie.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.green,
                              fontWeight: FontWeight.w600,
                            ),
                          ),

                          const SizedBox(height: 18),
                          const Divider(height: 1),

                          const SizedBox(height: 16),

                          // BÉNÉFICES
                          const _BenefitRow(
                            text: 'Apparaît en vitrine, vu en premier par les clients',
                            bold: true,
                          ),
                          const _BenefitRow(
                            text: 'Reçoit des demandes directes de clients',
                            bold: true,
                          ),
                          const _BenefitRow(
                            text: 'Affiche un badge Vérifié qui rassure plus de clients',
                            bold: true,
                          ),
                          const _BenefitRow(
                            text: 'Mieux classé que les comptes non vérifiés',
                            bold: true,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // --- RÉASSURANCE / ARGUMENTS ---
              const Text(
                'Ce que vous gagnez concrètement',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: kTextDark,
                ),
              ),
              const SizedBox(height: 12),
              const _IconTextRow(
                icon: Icons.trending_up,
                text:
                'Les profils vérifiés décrochent en moyenne 3x plus de missions.',
              ),
              const SizedBox(height: 8),
              const _IconTextRow(
                icon: Icons.cancel_outlined,
                text: 'Sans engagement : annulez en 1 clic depuis votre profil.',
              ),
              const SizedBox(height: 8),
              const _IconTextRow(
                icon: Icons.visibility_off_outlined,
                text:
                'Aucune carte stockée sur nos serveurs : tout est géré par Stripe.',
              ),
              const SizedBox(height: 8),
              const _IconTextRow(
                icon: Icons.receipt_long_outlined,
                text:
                'Facture disponible pour votre comptabilité après chaque prélèvement.',
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// PETITS WIDGETS DE LISTE POUR LE LOOK PREMIUM
// ---------------------------------------------------------------------------

class _BenefitRow extends StatelessWidget {
  final String text;
  final bool bold;

  const _BenefitRow({required this.text, this.bold = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: const BoxDecoration(
              color: Color(0xFFE8F5E9),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check,
              size: 14,
              color: Colors.green,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                color: kTextDark,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IconTextRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _IconTextRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: kTextDark.withOpacity(0.85)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 12.5,
              color: kTextGrey,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}
