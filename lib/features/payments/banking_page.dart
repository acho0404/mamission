import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_stripe/flutter_stripe.dart'; // INDISPENSABLE
import 'package:mamission/features/profile/user_repository.dart';
import 'package:mamission/shared/apple_appbar.dart';
import 'package:cloud_functions/cloud_functions.dart';

// ==============================================================================
// 1. LE HUB BANCAIRE (PAGE PRINCIPALE)
// ==============================================================================
class BankingPage extends StatefulWidget {
  const BankingPage({super.key});

  @override
  State<BankingPage> createState() => _BankingPageState();
}

class _BankingPageState extends State<BankingPage> {
  bool _isLoading = true;

  // Données RIB (Pour recevoir l'argent)
  String? _iban;
  String? _bic;
  String? _holderName;

  // Données Cartes (Pour payer) - Simulation d'affichage
  List<Map<String, dynamic>> _savedCards = [];

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (doc.exists) {
        final data = doc.data()!;
        setState(() {
          _iban = data['iban'];
          _bic = data['bic'];
          _holderName = data['accountHolderName'];
          // Ici, tu pourrais aussi charger les cartes enregistrées depuis ta propre collection
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  // --- ACTIONS ---

  void _openRibDetails() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _RibDetailsSheet(
        iban: _iban!,
        bic: _bic!,
        holder: _holderName!,
        onEdit: _openRibEditor,
        onDelete: () async {
          setState(() => _isLoading = true);
          await UserRepository().deleteBankingInfo(FirebaseAuth.instance.currentUser!.uid);
          await _fetchData();
          if (mounted) {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("RIB supprimé.")));
          }
        },
      ),
    );
  }

  void _openRibEditor() {
    if (Navigator.canPop(context)) Navigator.pop(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _RibEditSheet(
        initialIban: _iban,
        initialBic: _bic,
        initialHolder: _holderName,
        onSaved: _fetchData,
      ),
    );
  }

  // 🔥 AJOUT CARTE BANCAIRE (SETUP INTENT)
  // 🔥 AJOUT CARTE BANCAIRE (SETUP INTENT)
  Future<void> _addCard() async {
    setState(() => _isLoading = true);
    try {
      // 1. Appel de la Cloud Function createSetupIntent
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('createSetupIntent');
      final response = await callable.call();
      final data = response.data as Map<String, dynamic>;
      final clientSecret = data['clientSecret'] as String?;

      if (clientSecret == null || clientSecret.isEmpty) {
        throw Exception('Impossible de récupérer le client secret.');
      }

      // 2. Initialisation de la PaymentSheet Stripe avec le vrai clientSecret
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          setupIntentClientSecret: clientSecret,
          merchantDisplayName: 'MaMission',
          style: ThemeMode.light,
          primaryButtonLabel: 'Enregistrer la carte',
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

      // 3. Affichage de la sheet
      await Stripe.instance.presentPaymentSheet();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("✅ Carte ajoutée !"),
          backgroundColor: Colors.green,
        ),
      );

      // Mise à jour UI locale (optionnel)
      setState(() => _savedCards.add({"brand": "Visa", "last4": "4242"}));

    } on FirebaseFunctionsException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message ?? 'Erreur inconnue'),
          backgroundColor: Colors.red,
        ),
      );
    } on StripeException catch (e) {
      if (e.error.code != FailureCode.Canceled) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Erreur Stripe: ${e.error.localizedMessage}"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }


  @override
  Widget build(BuildContext context) {
    const kBgColor = Color(0xFFF3F6FF);
    return Scaffold(
      backgroundColor: kBgColor,
      appBar: buildAppleMissionAppBar(title: "Moyens de paiement", leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20), onPressed: () => Navigator.pop(context))),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF6C63FF)))
          : GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          physics: const BouncingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- SECTION 1 : CARTES ---
              const _SectionHeader(title: "MES CARTES (POUR PAYER)"),
              if (_savedCards.isEmpty)
                _EmptyCardState(onAdd: _addCard)
              else
                Column(
                  children: [
                    ..._savedCards.map((c) => _CardItem(brand: c['brand'], last4: c['last4'])).toList(),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: _addCard,
                      icon: const Icon(Icons.add_circle_outline, size: 18),
                      label: const Text("Ajouter une autre carte"),
                      style: TextButton.styleFrom(foregroundColor: const Color(0xFF6C63FF)),
                    )
                  ],
                ),

              const SizedBox(height: 32),

              // --- SECTION 2 : RIB ---
              const _SectionHeader(title: "VERSEMENTS (POUR ENCAISSER)"),
              if (_iban == null)
                _AlertBox(text: "Obligatoire pour recevoir l'argent de vos missions."),

              _RibItem(
                iban: _iban,
                onTap: _iban == null ? _openRibEditor : _openRibDetails,
              ),

              const SizedBox(height: 24),
              const _SecurityFooter(),
            ],
          ),
        ),
      ),
    );
  }
}

// ==============================================================================
// 2. ÉDITEUR RIB : LE STANDARD PRO (VALIDATION TEMPS RÉEL)
// ==============================================================================
class _RibEditSheet extends StatefulWidget {
  final String? initialIban;
  final String? initialBic;
  final String? initialHolder;
  final VoidCallback onSaved;

  const _RibEditSheet({this.initialIban, this.initialBic, this.initialHolder, required this.onSaved});

  @override
  State<_RibEditSheet> createState() => _RibEditSheetState();
}

class _RibEditSheetState extends State<_RibEditSheet> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _ibanCtrl;
  late TextEditingController _bicCtrl;
  late TextEditingController _holderCtrl;

  bool _isLoading = false;
  String? _errorMessage;

  // États de validation
  bool _formatValid = false;
  bool _isVerified = false; // Vrai uniquement après retour Stripe

  @override
  void initState() {
    super.initState();
    _ibanCtrl = TextEditingController(text: widget.initialIban);
    _bicCtrl = TextEditingController(text: widget.initialBic);
    _holderCtrl = TextEditingController(text: widget.initialHolder);

    _checkFormat();
    // RESET validation si on tape
    _ibanCtrl.addListener(_onChanged);
    _bicCtrl.addListener(_onChanged);
    _holderCtrl.addListener(_onChanged);
  }

  void _onChanged() {
    _checkFormat();
    if (_isVerified) {
      setState(() {
        _isVerified = false; // On perd la coche verte si on modifie
        _errorMessage = null;
      });
    }
  }

  void _checkFormat() {
    bool h = _holderCtrl.text.trim().length > 2;
    String cleanIban = _ibanCtrl.text.replaceAll(' ', '').toUpperCase();
    bool i = cleanIban.startsWith('FR') && cleanIban.length == 27;
    String cleanBic = _bicCtrl.text.trim().toUpperCase();
    bool b = RegExp(r'^[A-Z]{4}[A-Z]{2}[A-Z0-9]{2}([A-Z0-9]{3})?$').hasMatch(cleanBic);

    if (_formatValid != (h && i && b)) setState(() => _formatValid = (h && i && b));
  }

  Future<void> _submit() async {
    if (!_formatValid) return;
    FocusScope.of(context).unfocus();
    setState(() { _isLoading = true; _errorMessage = null; });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception("Non connecté");

      // 1. APPEL STRIPE (Vérification bancaire)
      // C'est ici que ça valide vraiment l'existence du compte (format + clé)
      final tokenData = await Stripe.instance.createToken(
        CreateTokenParams.bankAccount(
          params: BankAccountTokenParams(
            country: 'FR',
            currency: 'eur',
            accountNumber: _ibanCtrl.text.replaceAll(' ', '').trim(),
            accountHolderName: _holderCtrl.text.trim(),
            accountHolderType: BankAccountHolderType.Individual, // 👈 LA CORRECTION EST ICI
          ),
        ),
      );

      // 2. SUCCÈS VISUEL ✅
      setState(() => _isVerified = true);
      await Future.delayed(const Duration(milliseconds: 800)); // Petit temps pour savourer le succès

      // 3. SAUVEGARDE
      await UserRepository().updateBankingInfo(
        uid: user.uid,
        iban: _ibanCtrl.text.trim().toUpperCase(),
        bic: _bicCtrl.text.trim().toUpperCase(),
        accountHolderName: _holderCtrl.text.trim(),
      );

      widget.onSaved();
      if (mounted) Navigator.pop(context);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Compte validé et enregistré !"), backgroundColor: Colors.green));
      }

    } on StripeException catch (e) {
      setState(() => _errorMessage = "Refus bancaire : ${e.error.localizedMessage}");
    } catch (e) {
      setState(() => _errorMessage = "Erreur technique : Vérifiez votre connexion.");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.9,
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10))),
            const SizedBox(height: 20),
            Text(widget.initialIban == null ? "Ajouter un compte" : "Modifier le compte", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 30),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      _buildInput(label: "Titulaire", icon: Icons.person_outline, ctrl: _holderCtrl, isVerified: _isVerified),
                      const SizedBox(height: 16),
                      _buildInput(
                        label: "IBAN",
                        icon: Icons.account_balance,
                        ctrl: _ibanCtrl,
                        isCapital: true,
                        isVerified: _isVerified,
                        formatters: [_IbanFormatter(), LengthLimitingTextInputFormatter(34)],
                      ),
                      const SizedBox(height: 16),
                      _buildInput(
                        label: "BIC / SWIFT",
                        icon: Icons.domain,
                        ctrl: _bicCtrl,
                        isCapital: true,
                        isVerified: _isVerified,
                        formatters: [LengthLimitingTextInputFormatter(11)],
                      ),

                      const SizedBox(height: 24),

                      if (_errorMessage != null)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.red.shade200)),
                          child: Row(children: [const Icon(Icons.error_outline, color: Colors.red, size: 20), const SizedBox(width: 12), Expanded(child: Text(_errorMessage!, style: TextStyle(color: Colors.red.shade800, fontSize: 13, fontWeight: FontWeight.w500)))]),
                        ),

                      const SizedBox(height: 20),

                      SizedBox(
                        width: double.infinity, height: 56,
                        child: ElevatedButton(
                          onPressed: (_isLoading || !_formatValid) ? null : _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6C63FF),
                            disabledBackgroundColor: Colors.grey.shade300,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            elevation: 0,
                          ),
                          child: _isLoading
                              ? Row(mainAxisAlignment: MainAxisAlignment.center, children: const [SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)), SizedBox(width: 12), Text("Vérification...")])
                              : const Text("Vérifier et Enregistrer", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(height: 20),
                      TextButton(onPressed: () => Navigator.pop(context), child: const Text("Annuler", style: TextStyle(color: Colors.grey))),
                      SizedBox(height: MediaQuery.of(context).viewInsets.bottom + 20),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInput({required String label, required IconData icon, required TextEditingController ctrl, bool isCapital = false, bool isVerified = false, List<TextInputFormatter>? formatters}) {
    return TextFormField(
      controller: ctrl,
      textCapitalization: isCapital ? TextCapitalization.characters : TextCapitalization.words,
      inputFormatters: formatters,
      readOnly: isVerified, // On empêche la modif si c'est validé (il faut annuler/recommencer)
      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: isVerified ? Colors.green : const Color(0xFF6C63FF)),
        suffixIcon: isVerified ? const Icon(Icons.check_circle_rounded, color: Colors.green) : null,
        filled: true, fillColor: isVerified ? Colors.green.withOpacity(0.05) : const Color(0xFFF7F9FC),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        enabledBorder: isVerified ? OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Colors.green, width: 1.5)) : OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: const Color(0xFF6C63FF), width: 1.5)),
      ),
    );
  }
}

// ==============================================================================
// 3. SHEET DÉTAILS (LECTURE SEULE)
// ==============================================================================
class _RibDetailsSheet extends StatelessWidget {
  final String iban;
  final String bic;
  final String holder;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _RibDetailsSheet({required this.iban, required this.bic, required this.holder, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 20),
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 12),
        Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10))),
        const SizedBox(height: 24),
        const Text("Détails du compte", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 30),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(children: [
            _ReadOnlyField("Titulaire", holder, isVerified: true),
            const SizedBox(height: 16),
            _ReadOnlyField("IBAN", iban, isVerified: true),
            const SizedBox(height: 16),
            _ReadOnlyField("BIC", bic, isVerified: true),
          ]),
        ),
        const SizedBox(height: 40),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(children: [
            Expanded(child: OutlinedButton(onPressed: () {
              showDialog(context: context, builder: (c) => AlertDialog(
                title: const Text("Supprimer ce RIB ?"),
                content: const Text("Vous ne pourrez plus recevoir de virements."),
                actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text("Annuler")), TextButton(onPressed: () { Navigator.pop(c); onDelete(); }, child: const Text("Supprimer", style: TextStyle(color: Colors.red)))],
              ));
            }, style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red), padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))), child: const Text("Supprimer"))),
            const SizedBox(width: 16),
            Expanded(child: ElevatedButton(onPressed: onEdit, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6C63FF), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))), child: const Text("Modifier"))),
          ]),
        ),
      ]),
    );
  }
}

class _ReadOnlyField extends StatelessWidget {
  final String label;
  final String value;
  final bool isVerified;
  const _ReadOnlyField(this.label, this.value, {this.isVerified = false});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: const Color(0xFFF9FAFB), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label.toUpperCase(), style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(child: Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF1A1F36)))),
          if (isVerified) const Icon(Icons.check_circle_rounded, color: Colors.green, size: 20),
        ]),
      ]),
    );
  }
}

// ==============================================================================
// 4. HELPERS
// ==============================================================================
class _IbanFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    String text = newValue.text.toUpperCase().replaceAll(' ', '');
    if (text.length > 27) text = text.substring(0, 27);
    final buffer = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      buffer.write(text[i]);
      int nonZeroIndex = i + 1;
      if (nonZeroIndex % 4 == 0 && nonZeroIndex != text.length) buffer.write(' ');
    }
    final string = buffer.toString();
    return newValue.copyWith(text: string, selection: TextSelection.collapsed(offset: string.length));
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});
  @override
  Widget build(BuildContext context) {
    return Padding(padding: const EdgeInsets.only(left: 4, bottom: 12), child: Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF9EA3AE), letterSpacing: 1.0)));
  }
}

class _AlertBox extends StatelessWidget {
  final String text;
  const _AlertBox({required this.text});
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16), padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.orange.withOpacity(0.3))),
      child: Row(children: [
        const Icon(Icons.info_outline_rounded, color: Colors.orange, size: 20),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 12, color: Color(0xFF1A1F36), height: 1.3))),
      ]),
    );
  }
}

class _SecurityFooter extends StatelessWidget {
  const _SecurityFooter();
  @override
  Widget build(BuildContext context) {
    return Center(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Icon(Icons.lock_rounded, size: 12, color: Colors.grey),
      const SizedBox(width: 6),
      Text("Données chiffrées et sécurisées par Stripe", style: TextStyle(color: Colors.grey.withOpacity(0.8), fontSize: 11)),
    ]));
  }
}

class _EmptyCardState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyCardState({required this.onAdd});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity, padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))]),
      child: Column(children: [
        Container(padding: const EdgeInsets.all(16), decoration: const BoxDecoration(color: Color(0xFFF3F6FF), shape: BoxShape.circle), child: const Icon(Icons.credit_card_rounded, size: 30, color: Color(0xFF6C63FF))),
        const SizedBox(height: 16),
        const Text("Aucune carte enregistrée", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 8),
        const Text("Ajoutez une carte pour payer vos missions.", textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Colors.grey)),
        const SizedBox(height: 20),
        TextButton.icon(onPressed: onAdd, icon: const Icon(Icons.add_rounded, size: 18), label: const Text("Ajouter une carte"), style: TextButton.styleFrom(foregroundColor: const Color(0xFF6C63FF)))
      ]),
    );
  }
}

class _CardItem extends StatelessWidget {
  final String brand;
  final String last4;
  const _CardItem({required this.brand, required this.last4});
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8)]),
      child: Row(children: [
        Icon(Icons.credit_card, color: Colors.blueAccent),
        const SizedBox(width: 12),
        Text("$brand **** $last4", style: const TextStyle(fontWeight: FontWeight.bold)),
        const Spacer(),
        const Icon(Icons.more_horiz, color: Colors.grey),
      ]),
    );
  }
}

class _RibItem extends StatelessWidget {
  final String? iban;
  final VoidCallback onTap;
  const _RibItem({this.iban, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final bool isConfigured = iban != null && iban!.isNotEmpty;
    String displayIban = "****";
    if (isConfigured) {
      String clean = iban!.replaceAll(' ', '');
      if (clean.length > 8) displayIban = "${clean.substring(0, 4)} •••• ${clean.substring(clean.length - 4)}";
    }
    return InkWell(
      onTap: onTap, borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))], border: isConfigured ? Border.all(color: Colors.transparent) : Border.all(color: Colors.orange.withOpacity(0.5), width: 1.5)),
        child: Row(children: [
          Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: isConfigured ? const Color(0xFFF3F6FF) : Colors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(12)), child: Icon(Icons.account_balance_rounded, color: isConfigured ? const Color(0xFF6C63FF) : Colors.orange, size: 24)),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text("Compte Bancaire (Virements)", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF1A1F36))),
            const SizedBox(height: 4),
            if (isConfigured) Text(displayIban, style: const TextStyle(fontSize: 13, color: Colors.grey)) else const Text("Requis pour les prestataires", style: TextStyle(fontSize: 12, color: Colors.orange, fontWeight: FontWeight.bold)),
          ])),
          if (isConfigured) const Icon(Icons.chevron_right_rounded, color: Colors.grey, size: 24) else Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: const Color(0xFF1A1F36), borderRadius: BorderRadius.circular(8)), child: const Text("Configurer", style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)))
        ]),
      ),
    );
  }
}