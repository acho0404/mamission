import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';

class ResetPasswordPage extends StatefulWidget {
  const ResetPasswordPage({super.key});

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final _emailCtrl = TextEditingController();
  bool _loading = false;

  Future<void> _resetPassword() async {
    if (_emailCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Veuillez entrer votre email.")),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(
        email: _emailCtrl.text.trim(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Email de réinitialisation envoyé ✅"),
          ),
        );
        context.go('/login');
      }
    } on FirebaseAuthException catch (e) {
      String msg = "Erreur lors de la réinitialisation";
      if (e.code == 'user-not-found') {
        msg = "Aucun utilisateur trouvé avec cet email.";
      }
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
        centerTitle: true,
        elevation: 1,
        title: const Text(
          "Mot de passe oublié",
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
              const SizedBox(height: 30),
              Icon(Icons.lock_reset_rounded, size: 80, color: violet),
              const SizedBox(height: 20),
              const Text(
                "Réinitialiser mon mot de passe",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              const Text(
                "Entrez votre adresse email et nous vous enverrons un lien de réinitialisation.",
                style: TextStyle(fontSize: 15, color: Colors.black54),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),

              // --- Champ email ---
              TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: "Email",
                  prefixIcon: const Icon(Icons.email_outlined),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              const SizedBox(height: 30),

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
                  onPressed: _loading ? null : _resetPassword,
                  child: _loading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                    "Envoyer le lien",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 25),

              TextButton(
                onPressed: () => context.go('/login'),
                child: const Text(
                  "Retour à la connexion",
                  style: TextStyle(
                    color: violet,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

              const SizedBox(height: 60),
              Opacity(
                opacity: 0.6,
                child: Image.network(
                  "https://cdn-icons-png.flaticon.com/512/822/822243.png",
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
