import 'dart:ui'; // Pour le flou (Glassmorphism)
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import 'package:mamission/shared/services/push_token_service.dart';

// -----------------------------------------------------------------------------
// THEME & ANIMATIONS (Pour garder la cohérence)
// -----------------------------------------------------------------------------
class AppTheme {
  static const Color bgLight = Color(0xFFF3F6FF);
  static const Color neonPrimary = Color(0xFF6C63FF);
  static const Color neonCyan = Color(0xFF00B8D4);
  static const Color textDark = Color(0xFF1A1F36);
  static const Color textGrey = Color(0xFF6E7787);

  static BoxDecoration glassBox() {
    return BoxDecoration(
      color: Colors.white.withOpacity(0.7),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: Colors.white),
      boxShadow: [
        BoxShadow(
          color: neonPrimary.withOpacity(0.1),
          blurRadius: 20,
          offset: const Offset(0, 10),
        ),
      ],
    );
  }
}

class FadeInSlide extends StatefulWidget {
  final Widget child;
  final double delay;
  const FadeInSlide({super.key, required this.child, this.delay = 0});

  @override
  State<FadeInSlide> createState() => _FadeInSlideState();
}

class _FadeInSlideState extends State<FadeInSlide> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _fadeAnim = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutQuart));

    Future.delayed(Duration(milliseconds: (widget.delay * 1000).round()), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnim,
      child: SlideTransition(position: _slideAnim, child: widget.child),
    );
  }
}

// -----------------------------------------------------------------------------
// PAGE LOGIN FUTURISTE
// -----------------------------------------------------------------------------
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;

  // --- LOGIQUE FIREBASE (Inchangée) ---
  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text.trim(),
      );

      // ✅ Enregistre le token FCM du device
      await PushTokenService.saveDeviceToken();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Connexion réussie 🚀"),
            backgroundColor: AppTheme.neonPrimary,
            behavior: SnackBarBehavior.floating,
          ),
        );
        context.go('/explore');
      }
    } on FirebaseAuthException catch (e) {
      String msg = "Erreur de connexion";
      if (e.code == 'user-not-found') msg = "Aucun compte trouvé avec cet email.";
      if (e.code == 'wrong-password') msg = "Mot de passe incorrect.";

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgLight,
      // IMPORTANT : On laisse le clavier pousser le contenu
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          // 1. BACKGROUND ORBS (ANIMÉS OU FIXES)
          Positioned(
            top: -80,
            left: -80,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.neonPrimary.withOpacity(0.15),
              ),
            ),
          ),
          Positioned(
            bottom: 100,
            right: -100,
            child: Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.neonCyan.withOpacity(0.1),
              ),
            ),
          ),
          // FLOU GÉNÉRAL
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
              child: Container(color: Colors.transparent),
            ),
          ),

          // 2. CONTENU SCROLLABLE
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // --- LOGO ANIMÉ ---
                    FadeInSlide(
                      delay: 0.1,
                      child: Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [AppTheme.neonPrimary, AppTheme.neonCyan],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.neonPrimary.withOpacity(0.4),
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.lock_open_rounded, size: 48, color: Colors.white),
                      ),
                    ),

                    const SizedBox(height: 30),

                    // --- TITRE ---
                    const FadeInSlide(
                      delay: 0.2,
                      child: Text(
                        "Bienvenue !",
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.textDark,
                          letterSpacing: -1,
                        ),
                      ),
                    ),
                    const FadeInSlide(
                      delay: 0.3,
                      child: Text(
                        "Connectez-vous pour continuer",
                        style: TextStyle(fontSize: 16, color: AppTheme.textGrey),
                      ),
                    ),

                    const SizedBox(height: 40),

                    // --- CARTE FORMULAIRE ---
                    FadeInSlide(
                      delay: 0.4,
                      child: Container(
                        padding: const EdgeInsets.all(24),
                        decoration: AppTheme.glassBox(), // La fameuse boîte en verre
                        child: Form(
                          key: _formKey,
                          child: Column(
                            children: [
                              _buildNeonInput(
                                controller: _emailCtrl,
                                icon: Icons.alternate_email_rounded,
                                label: "Email",
                                type: TextInputType.emailAddress,
                              ),

                              const SizedBox(height: 20),

                              _buildNeonInput(
                                controller: _passCtrl,
                                icon: Icons.lock_outline_rounded,
                                label: "Mot de passe",
                                isPassword: true,
                                obscure: _obscure,
                                onToggleObscure: () => setState(() => _obscure = !_obscure),
                              ),

                              const SizedBox(height: 12),

                              // --- Mot de passe oublié (AJOUT) ---
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: () => context.push('/reset'),
                                  style: TextButton.styleFrom(
                                    foregroundColor: AppTheme.neonPrimary,
                                  ),
                                  child: const Text(
                                    "Mot de passe oublié ?",
                                    style: TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ),

                              const SizedBox(height: 20),

                              // --- BOUTON CONNECTER ---
                              SizedBox(
                                width: double.infinity,
                                height: 55,
                                child: ElevatedButton(
                                  onPressed: _loading ? null : _login,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    shadowColor: Colors.transparent,
                                    padding: EdgeInsets.zero,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  child: Ink(
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [AppTheme.neonPrimary, Color(0xFF4F46E5)],
                                      ),
                                      borderRadius: BorderRadius.circular(16),
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppTheme.neonPrimary.withOpacity(0.4),
                                          blurRadius: 12,
                                          offset: const Offset(0, 4),
                                        )
                                      ],
                                    ),
                                    child: Container(
                                      alignment: Alignment.center,
                                      child: _loading
                                          ? const SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                      )
                                          : const Text(
                                        "Se connecter",
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 30),

                    // --- FOOTER INSCRIPTION ---
                    FadeInSlide(
                      delay: 0.5,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            "Pas encore de compte ? ",
                            style: TextStyle(color: AppTheme.textGrey),
                          ),
                          GestureDetector(
                            onTap: () => context.go('/register'),
                            child: const Text(
                              "Créer un compte",
                              style: TextStyle(
                                color: AppTheme.neonPrimary,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- WIDGET INPUT NÉON ADAPTÉ ---
  Widget _buildNeonInput({
    required TextEditingController controller,
    required IconData icon,
    required String label,
    TextInputType type = TextInputType.text,
    bool isPassword = false,
    bool obscure = false,
    VoidCallback? onToggleObscure,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: AppTheme.textGrey,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: TextFormField(
            controller: controller,
            keyboardType: type,
            obscureText: isPassword ? obscure : false,
            style: const TextStyle(color: AppTheme.textDark, fontWeight: FontWeight.w600),
            cursorColor: AppTheme.neonPrimary,
            validator: (v) => v == null || v.isEmpty ? "Requis" : null,
            decoration: InputDecoration(
              prefixIcon: Icon(icon, color: AppTheme.neonPrimary),
              suffixIcon: isPassword
                  ? IconButton(
                icon: Icon(
                  obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  color: AppTheme.textGrey,
                ),
                onPressed: onToggleObscure,
              )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              hintText: label,
              hintStyle: TextStyle(color: Colors.grey.shade400),
            ),
          ),
        ),
      ],
    );
  }
}