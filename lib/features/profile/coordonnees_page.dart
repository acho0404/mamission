import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // INDISPENSABLE POUR SYNC LE NOM

class CoordonneesPage extends StatefulWidget {
  const CoordonneesPage({Key? key}) : super(key: key);

  @override
  _CoordonneesPageState createState() => _CoordonneesPageState();
}

class _CoordonneesPageState extends State<CoordonneesPage> {
  // Clé API Google
  static const String kPlacesApiKey = "AIzaSyCXltusJoTE4wN04ETzYqLUSFRzRcX7DhY";

  // État local
  User? _user;
  String _displayName = "";
  String _email = "";
  bool _emailVerified = false;
  String? _address = "Chargement..."; // On va le chercher dans Firestore

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  // Charge les données fraîches depuis Firebase
  Future<void> _loadUserData() async {
    _user = FirebaseAuth.instance.currentUser;
    if (_user != null) {
      await _user!.reload(); // Force le rafraichissement (ex: si email vérifié entre temps)
      _user = FirebaseAuth.instance.currentUser; // Récupère l'instance à jour

      // Récupérer l'adresse depuis Firestore
      DocumentSnapshot doc = await FirebaseFirestore.instance.collection('users').doc(_user!.uid).get();

      setState(() {
        _displayName = _user!.displayName ?? (doc.data() as Map?)?['name'] ?? "Nom inconnu";
        _email = _user!.email ?? "";
        _emailVerified = _user!.emailVerified;
        _address = (doc.data() as Map?)?['city'] ?? "Adresse non renseignée"; // Tu peux adapter le champ 'city' ou 'address'
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          "Coordonnées et sécurité",
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _loadUserData, // Permet de tirer vers le bas pour vérifier si l'email est validé
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),

              // --- CONNEXION ---
              _buildSectionTitle("Connexion"),

              // 1. NOM & PRÉNOM (NOUVEAU)
              _buildAirbnbItem(
                label: "Nom complet",
                value: _displayName,
                onTap: () => _showNameEditSheet(),
              ),

              // 2. EMAIL AVEC STATUT DE VÉRIFICATION
              _buildAirbnbItem(
                label: "Adresse courriel",
                value: _email,
                isEmail: true, // Pour afficher le badge
                isVerified: _emailVerified,
                onTap: () => _showEmailEditSheet(),
              ),

              // 3. MOT DE PASSE
              _buildAirbnbItem(
                label: "Mot de passe",
                value: "••••••••••••",
                isPassword: true,
                onTap: () => _showSecurePasswordSheet(),
              ),

              const SizedBox(height: 30),

              // --- INFOS LÉGALES ---
              _buildSectionTitle("Informations légales"),

              _buildAirbnbItem(
                label: "Adresse postale",
                value: _address,
                onTap: () => _openAddressSearch(),
              ),

              _buildAirbnbItem(
                label: "Identité (KYC)",
                value: "Vérifiée", // À connecter à ton booléen Firestore 'verified'
                isIdentity: true,
                onTap: () {},
              ),

              const SizedBox(height: 50),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // 🛠️ LOGIQUE MÉTIER (MODIFICATION)
  // ===========================================================================

  // 1. MODIFIER LE NOM (AUTH + FIRESTORE)
  void _showNameEditSheet() {
    final controller = TextEditingController(text: _displayName);
    _showEditSheet(
        title: "Modifier votre nom",
        child: _buildTextField("Nom et Prénom", controller),
        onSave: () async {
          if (controller.text.isEmpty) return;
          try {
            // A. Mise à jour Auth
            await _user!.updateDisplayName(controller.text);
            // B. Mise à jour Firestore (CRITIQUE pour que le profil public change)
            await FirebaseFirestore.instance.collection('users').doc(_user!.uid).update({
              'name': controller.text,
            });

            await _loadUserData(); // Rafraichir l'écran
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Nom mis à jour !"), backgroundColor: Colors.green));
          } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erreur: $e"), backgroundColor: Colors.red));
          }
        }
    );
  }

  // 2. MODIFIER EMAIL (SÉCURISÉ)
  void _showEmailEditSheet() {
    final controller = TextEditingController(text: _email);
    _showEditSheet(
        title: "Changer d'email",
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTextField("Nouvelle adresse email", controller, TextInputType.emailAddress),
            const SizedBox(height: 10),
            const Text(
              "⚠️ Attention : Un email de vérification sera envoyé à la nouvelle adresse. Vous devrez cliquer sur le lien reçu pour valider le changement.",
              style: TextStyle(color: Colors.orange, fontSize: 12),
            ),
          ],
        ),
        onSave: () async {
          if (controller.text.isEmpty || !controller.text.contains('@')) return;
          try {
            // Méthode moderne : On vérifie AVANT de changer
            await _user!.verifyBeforeUpdateEmail(controller.text);

            Navigator.pop(context);
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text("Vérifiez vos emails"),
                content: Text("Un lien de confirmation a été envoyé à ${controller.text}. Cliquez dessus pour valider le changement."),
                actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("OK"))],
              ),
            );
          } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erreur: $e"), backgroundColor: Colors.red));
          }
        }
    );
  }

  // 3. MODIFIER ADRESSE
  void _openAddressSearch() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AddressSearchSheet(apiKey: kPlacesApiKey),
    );

    if (result != null) {
      // Sauvegarde dans Firestore
      await FirebaseFirestore.instance.collection('users').doc(_user!.uid).update({
        'city': result, // Ou un champ 'address' complet
      });
      setState(() => _address = result);
    }
  }

  // ===========================================================================
  // 🔐 LOGIQUE MOT DE PASSE (Gardée de la version précédente)
  // ===========================================================================
  void _showSecurePasswordSheet() {
    final _formKey = GlobalKey<FormState>();
    final _currentPassController = TextEditingController();
    final _newPassController = TextEditingController();
    final _confirmPassController = TextEditingController();
    bool _isLoading = false;

    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (context) {
          return StatefulBuilder(
              builder: (BuildContext context, StateSetter setModalState) {
                return Padding(
                  padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 20, left: 24, right: 24, top: 24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Modifier le mot de passe", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 20),
                        _buildPasswordField(controller: _currentPassController, label: "Mot de passe actuel", validator: (val) => val == null || val.isEmpty ? "Requis" : null),
                        const SizedBox(height: 15),
                        _buildPasswordField(controller: _newPassController, label: "Nouveau mot de passe", validator: (val) {
                          if (val == null || val.length < 6) return "Min. 6 caractères"; // Simplifié pour test
                          return null;
                        },
                        ),
                        const SizedBox(height: 15),
                        _buildPasswordField(controller: _confirmPassController, label: "Confirmer", validator: (val) => val != _newPassController.text ? "Différent" : null),
                        const SizedBox(height: 25),
                        SizedBox(
                          width: double.infinity, height: 50,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : () async {
                              if (_formKey.currentState!.validate()) {
                                setModalState(() => _isLoading = true);
                                try {
                                  User? user = FirebaseAuth.instance.currentUser;
                                  AuthCredential credential = EmailAuthProvider.credential(email: user!.email!, password: _currentPassController.text);
                                  await user.reauthenticateWithCredential(credential);
                                  await user.updatePassword(_newPassController.text);
                                  Navigator.pop(context);
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Mot de passe modifié !"), backgroundColor: Colors.green));
                                } catch (e) {
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erreur: $e"), backgroundColor: Colors.red));
                                } finally {
                                  setModalState(() => _isLoading = false);
                                }
                              }
                            },
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                            child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text("Mettre à jour", style: TextStyle(color: Colors.white)),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
          );
        }
    );
  }

  // ===========================================================================
  // WIDGETS UI
  // ===========================================================================

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10.0),
      child: Text(title.toUpperCase(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade800, letterSpacing: 0.8)),
    );
  }

  Widget _buildAirbnbItem({
    required String label,
    required String? value,
    required VoidCallback onTap,
    bool isLast = false,
    bool isPassword = false,
    bool isIdentity = false,
    bool isEmail = false,
    bool isVerified = false,
  }) {
    bool hasValue = value != null && value.isNotEmpty;
    return InkWell(
      onTap: onTap,
      splashColor: Colors.transparent,
      highlightColor: Colors.grey.withOpacity(0.1),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18.0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(label, style: const TextStyle(fontSize: 16, color: Colors.black87, fontWeight: FontWeight.w500)),
                          // Badge Email Vérifié
                          if (isEmail) ...[
                            const SizedBox(width: 8),
                            Icon(isVerified ? Icons.verified : Icons.warning_amber_rounded, size: 16, color: isVerified ? Colors.green : Colors.orange),
                            const SizedBox(width: 4),
                            Text(isVerified ? "Vérifié" : "Non vérifié", style: TextStyle(fontSize: 11, color: isVerified ? Colors.green : Colors.orange, fontWeight: FontWeight.bold))
                          ]
                        ],
                      ),
                      const SizedBox(height: 4),
                      if (isIdentity)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: hasValue && value == "Vérifiée" ? Colors.green.shade50 : Colors.red.shade50, borderRadius: BorderRadius.circular(4)),
                          child: Text(value ?? "À faire", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: hasValue && value == "Vérifiée" ? Colors.green.shade700 : Colors.red.shade700)),
                        )
                      else
                        Text(hasValue ? value : "Non renseigné", style: TextStyle(fontSize: 14, color: hasValue ? Colors.grey.shade600 : Colors.grey.shade400)),
                    ],
                  ),
                ),
                Text(hasValue || isPassword ? "Modifier" : "Ajouter", style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, decoration: TextDecoration.underline)),
              ],
            ),
          ),
          if (!isLast) Divider(height: 1, thickness: 0.5, color: Colors.grey.shade300),
        ],
      ),
    );
  }

  void _showEditSheet({required String title, required Widget child, required Future<void> Function() onSave}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 20, left: 20, right: 20, top: 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          child,
          const SizedBox(height: 20),
          SizedBox(width: double.infinity, height: 50, child: ElevatedButton(onPressed: onSave, style: ElevatedButton.styleFrom(backgroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: const Text("Enregistrer", style: TextStyle(color: Colors.white))))
        ]),
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, [TextInputType type = TextInputType.text]) {
    return TextField(keyboardType: type, controller: controller, decoration: InputDecoration(labelText: label, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), filled: true, fillColor: Colors.grey.shade50));
  }

  Widget _buildPasswordField({required TextEditingController controller, required String label, required String? Function(String?) validator}) {
    return TextFormField(controller: controller, obscureText: true, validator: validator, decoration: InputDecoration(labelText: label, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), filled: true, fillColor: Colors.grey.shade50, suffixIcon: const Icon(Icons.lock_outline, size: 18, color: Colors.grey)));
  }
}

// --- SHEET RECHERCHE ADRESSE ---
class AddressSearchSheet extends StatefulWidget {
  final String apiKey;
  const AddressSearchSheet({Key? key, required this.apiKey}) : super(key: key);
  @override
  _AddressSearchSheetState createState() => _AddressSearchSheetState();
}

class _AddressSearchSheetState extends State<AddressSearchSheet> {
  List<dynamic> _predictions = [];
  Timer? _debounce;
  final TextEditingController _controller = TextEditingController();

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (query.length > 2) _fetchSuggestions(query);
    });
  }

  Future<void> _fetchSuggestions(String input) async {
    final String url = "https://maps.googleapis.com/maps/api/place/autocomplete/json?input=$input&key=${widget.apiKey}&language=fr&components=country:fr";
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() => _predictions = data['predictions']);
      }
    } catch (e) { print("Erreur API Google: $e"); }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      child: Column(children: [
        Padding(padding: const EdgeInsets.all(16.0), child: Row(children: [
          Expanded(child: TextField(controller: _controller, autofocus: true, decoration: InputDecoration(hintText: "Rechercher une adresse...", prefixIcon: const Icon(Icons.search), filled: true, fillColor: Colors.grey.shade100, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14)), onChanged: _onSearchChanged)),
          const SizedBox(width: 10), TextButton(onPressed: () => Navigator.pop(context), child: const Text("Annuler", style: TextStyle(color: Colors.black)))
        ])),
        const Divider(height: 1),
        Expanded(child: ListView.builder(itemCount: _predictions.length, itemBuilder: (context, index) {
          return ListTile(leading: const Icon(Icons.location_on_outlined, color: Colors.grey), title: Text(_predictions[index]['structured_formatting']['main_text'] ?? "", style: const TextStyle(fontWeight: FontWeight.w600)), subtitle: Text(_predictions[index]['structured_formatting']['secondary_text'] ?? ""), onTap: () => Navigator.pop(context, _predictions[index]['description']));
        })),
        Padding(padding: const EdgeInsets.all(8.0), child: Image.network("https://maps.gstatic.com/mapfiles/api-3/images/powered-by-google-on-white3.png", height: 20)),
      ]),
    );
  }
}