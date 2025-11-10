import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    try {
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text.trim(),
      );

      final uid = cred.user!.uid;

      // --- création du profil Firestore cohérent avec ta structure
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        "name": _nameCtrl.text.trim(),
        "email": _emailCtrl.text.trim(),
        "phone": _phoneCtrl.text.trim(),
        "photoUrl": "https://picsum.photos/200",
        "bio": "Motivé pour vous aider ! et aussi pour déléguer mes tâches.",
        "rating": 5.0,
        "reviewsCount": 0,
        "updatedAt": FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Compte créé avec succès 🎉")),
        );
        context.go('/explore');
      }
    } on FirebaseAuthException catch (e) {
      String msg = "Erreur d’inscription";
      if (e.code == 'email-already-in-use') msg = "Cet email est déjà utilisé.";
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const violet = Color(0xFF6C63FF);
    const lavande = Color(0xFFF3EEFF);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: violet,
        elevation: 1,
        centerTitle: true,
        title: const Text(
          "Créer un compte",
          style: TextStyle(
            color: lavande,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // --- Header animé style MaMission ---
              Column(
                children: [
                  Hero(
                    tag: 'mamission-logo',
                    child: Icon(Icons.stars_rounded, color: violet, size: 80),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    "Rejoins la communauté MaMission ✨",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
              const SizedBox(height: 40),

              // --- Formulaire ---
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _nameCtrl,
                      decoration: InputDecoration(
                        labelText: "Nom complet",
                        prefixIcon: const Icon(Icons.person_outline),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      validator: (v) =>
                      v == null || v.isEmpty ? "Entrez votre nom" : null,
                    ),
                    const SizedBox(height: 14),

                    TextFormField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        labelText: "Email",
                        prefixIcon: const Icon(Icons.email_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      validator: (v) =>
                      v == null || v.isEmpty ? "Entrez un email valide" : null,
                    ),
                    const SizedBox(height: 14),

                    TextFormField(
                      controller: _phoneCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        labelText: "Téléphone",
                        prefixIcon: const Icon(Icons.phone_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    TextFormField(
                      controller: _passCtrl,
                      obscureText: _obscure,
                      decoration: InputDecoration(
                        labelText: "Mot de passe",
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscure
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                          onPressed: () =>
                              setState(() => _obscure = !_obscure),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      validator: (v) => v != null && v.length < 6
                          ? "6 caractères minimum"
                          : null,
                    ),
                    const SizedBox(height: 28),

                    // --- Bouton principal ---
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: violet,
                          foregroundColor: lavande,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: _loading ? null : _register,
                        child: _loading
                            ? const CircularProgressIndicator(color: Colors.white)
                            : const Text(
                          "Créer mon compte",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // --- Lien vers login ---
              TextButton(
                onPressed: () => context.go('/login'),
                child: const Text(
                  "Déjà un compte ? Se connecter",
                  style: TextStyle(
                    color: violet,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

              const SizedBox(height: 50),

              // --- Illustration douce ---
              Opacity(
                opacity: 0.7,
                child: Image.network(
                  "https://cdn-icons-png.flaticon.com/512/10075/10075850.png",
                  height: 100,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
