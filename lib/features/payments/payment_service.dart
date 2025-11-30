import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

class PaymentService {
  final _functions = FirebaseFunctions.instanceFor(region: 'us-central1');

  /// Retourne true si paiement OK, false si annulé
  Future<bool> makePayment(double amountEur) async {
    try {
      final int amountCents = (amountEur * 100).toInt();

      // 1️⃣ Appel Cloud Function → clientSecret
      final result = await _functions
          .httpsCallable('createPaymentIntent')
          .call(<String, dynamic>{
        'amount': amountCents,
        'currency': 'eur',
      });

      final clientSecret = result.data['clientSecret'] as String;

      // 2️⃣ Init PaymentSheet
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: clientSecret,
          merchantDisplayName: 'MaMission',
          style: ThemeMode.light,
          appearance: const PaymentSheetAppearance(
            primaryButton: PaymentSheetPrimaryButtonAppearance(
              colors: PaymentSheetPrimaryButtonTheme(
                light: PaymentSheetPrimaryButtonThemeColors(
                  background: Color(0xFF6C63FF),
                  text: Colors.white,
                ),
              ),
            ),
          ),
        ),
      );

      // 3️⃣ Affiche la feuille de paiement
      await Stripe.instance.presentPaymentSheet();

      // ✅ Paiement validé
      return true;
    } on StripeException {
      // ❌ utilisateur a annulé ou carte refusée
      return false;
    } catch (e) {
      rethrow;
    }
  }
}
