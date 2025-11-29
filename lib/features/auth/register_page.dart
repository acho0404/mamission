import 'dart:ui'; // Pour le flou
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mamission/shared/services/push_token_service.dart';

// -----------------------------------------------------------------------------
// LOGO VECTORIEL (Ton Logo Pin Violet)
// -----------------------------------------------------------------------------
class MaMissionLogo extends StatelessWidget {
  final double size;
  const MaMissionLogo({super.key, this.size = 100});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size * 1.2,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size * 1.2),
            painter: _PinPainter(),
          ),
          Positioned(
            top: size * 0.28,
            child: Icon(
              Icons.work_rounded,
              color: Colors.white.withOpacity(0.9),
              size: size * 0.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _PinPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final paint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF8A84FF), Color(0xFF564AF2)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Rect.fromLTWH(0, 0, w, h))
      ..style = PaintingStyle.fill;

    final path = Path();
    path.moveTo(w / 2, h);
    path.cubicTo(w * 0.1, h * 0.6, 0, h * 0.4, 0, w / 2);
    path.arcToPoint(Offset(w, w / 2), radius: Radius.circular(w / 2), clockwise: true);
    path.cubicTo(w, h * 0.4, w * 0.9, h * 0.6, w / 2, h);
    path.close();

    canvas.drawShadow(path, const Color(0xFF6C63FF).withOpacity(0.5), 12, true);
    canvas.drawPath(path, paint);

    final borderPaint = Paint()..color = Colors.white.withOpacity(0.3)..style = PaintingStyle.stroke..strokeWidth = 2.0;
    canvas.drawCircle(Offset(w/2, w/2), (w/2) - 6, borderPaint);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// -----------------------------------------------------------------------------
// THEME & ANIMATIONS
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
    Future.delayed(Duration(milliseconds: (widget.delay * 1000).round()), () { if (mounted) _controller.forward(); });
  }
  @override
  void dispose() { _controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return FadeTransition(opacity: _fadeAnim, child: SlideTransition(position: _slideAnim, child: widget.child));
  }
}

// -----------------------------------------------------------------------------
// PAGE INSCRIPTION MULTI-ÉTAPES (WIZARD)
// -----------------------------------------------------------------------------
class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final PageController _pageController = PageController();

  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();

  int _currentStep = 0;
  final int _totalSteps = 3;
  bool _loading = false;
  bool _obscurePass = true;
  bool _obscureConfirm = true;

  void _nextStep() {
    if (_currentStep == 0) {
      if (_firstNameCtrl.text.trim().isEmpty || _lastNameCtrl.text.trim().isEmpty) {
        _showError("Merci de remplir votre nom et prénom.");
        return;
      }
    } else if (_currentStep == 1) {
      if (!_emailCtrl.text.contains('@') || _phoneCtrl.text.trim().isEmpty) {
        _showError("Email ou téléphone invalide.");
        return;
      }
    } else if (_currentStep == 2) {
      if (_passCtrl.text.length < 6) {
        _showError("Le mot de passe doit faire 6 caractères min.");
        return;
      }
      if (_passCtrl.text != _confirmPassCtrl.text) {
        _showError("Les mots de passe ne correspondent pas.");
        return;
      }
      _register();
      return;
    }

    _pageController.nextPage(duration: const Duration(milliseconds: 500), curve: Curves.easeOutQuart);
    setState(() => _currentStep++);
  }

  void _prevStep() {
    if (_currentStep > 0) {
      _pageController.previousPage(duration: const Duration(milliseconds: 500), curve: Curves.easeOutQuart);
      setState(() => _currentStep--);
    } else {
      context.go('/login');
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.redAccent));
  }

  Future<void> _register() async {
    setState(() => _loading = true);
    try {
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text.trim(),
      );
      final uid = cred.user!.uid;
      final fullName = "${_firstNameCtrl.text.trim()} ${_lastNameCtrl.text.trim()}";

      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        "firstName": _firstNameCtrl.text.trim(),
        "lastName": _lastNameCtrl.text.trim(),
        "name": fullName,
        "email": _emailCtrl.text.trim(),
        "phone": _phoneCtrl.text.trim(),
        "photoUrl":
        "https://ui-avatars.com/api/?name=${_firstNameCtrl.text}+${_lastNameCtrl.text}&background=6C63FF&color=fff",
        "bio": "Je suis nouveau ici !",
        "rating": 5.0,
        "reviewsCount": 0,
        "createdAt": FieldValue.serverTimestamp(),
        "updatedAt": FieldValue.serverTimestamp(),
      });

      // ✅ Enregistre le token FCM du nouveau compte
      await PushTokenService.saveDeviceToken();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Bienvenue à bord ! 🚀"),
            backgroundColor: AppTheme.neonPrimary,
          ),
        );
        context.go('/explore');
      }
    } on FirebaseAuthException catch (e) {
      String msg = "Erreur d'inscription";
      if (e.code == 'email-already-in-use') msg = "Cet email est déjà utilisé.";
      if (e.code == 'weak-password') msg = "Mot de passe trop faible.";
      _showError(msg);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final double progress = (_currentStep + 1) / _totalSteps;

    return Scaffold(
      backgroundColor: AppTheme.bgLight,
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          // DÉCOR
          Positioned(top: -80, right: -50, child: Container(width: 300, height: 300, decoration: BoxDecoration(shape: BoxShape.circle, color: AppTheme.neonPrimary.withOpacity(0.15)))),
          Positioned(bottom: 100, left: -100, child: Container(width: 400, height: 400, decoration: BoxDecoration(shape: BoxShape.circle, color: AppTheme.neonCyan.withOpacity(0.1)))),
          Positioned.fill(child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40), child: Container(color: Colors.transparent))),

          // CONTENU
          SafeArea(
            child: Column(
              children: [
                // HEADER NAV
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      GestureDetector(
                        onTap: _prevStep,
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white, boxShadow: [BoxShadow(color: Colors.grey.shade200, blurRadius: 10)]),
                          child: const Icon(Icons.arrow_back, color: AppTheme.textDark, size: 20),
                        ),
                      ),
                      Text("ÉTAPE ${_currentStep + 1} / $_totalSteps", style: const TextStyle(color: AppTheme.textGrey, fontWeight: FontWeight.bold, letterSpacing: 2)),
                      const SizedBox(width: 44),
                    ],
                  ),
                ),

                // PROGRESS BAR
                Container(
                  height: 6, width: double.infinity,
                  margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(3)),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: progress,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [AppTheme.neonPrimary, AppTheme.neonCyan]),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // PAGES (WIZARD)
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      _buildStep1Identity(),
                      _buildStep2Contact(),
                      _buildStep3Security(),
                    ],
                  ),
                ),

                // BOUTON ACTION
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.8), border: Border(top: BorderSide(color: Colors.grey.shade100))),
                  child: SizedBox(
                    width: double.infinity, height: 55,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _nextStep,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent, shadowColor: Colors.transparent, padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                      child: Ink(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [AppTheme.neonPrimary, Color(0xFF4F46E5)]),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [BoxShadow(color: AppTheme.neonPrimary.withOpacity(0.4), blurRadius: 12)],
                        ),
                        child: Container(
                          alignment: Alignment.center,
                          child: _loading
                              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(_currentStep == _totalSteps - 1 ? "CRÉER MON COMPTE" : "CONTINUER", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 1)),
                              const SizedBox(width: 8),
                              const Icon(Icons.arrow_forward_rounded, color: Colors.white),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- ÉTAPES WIDGETS ---

  Widget _buildStep1Identity() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          const SizedBox(height: 20),
          FadeInSlide(delay: 0.1, child: const MaMissionLogo(size: 100)), // TON LOGO ICI
          const SizedBox(height: 20),
          const FadeInSlide(delay: 0.2, child: Text("Faisons connaissance", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: AppTheme.textDark))),
          const FadeInSlide(delay: 0.3, child: Text("Comment vous appelez-vous ?", style: TextStyle(color: AppTheme.textGrey))),
          const SizedBox(height: 40),
          FadeInSlide(
            delay: 0.4,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: AppTheme.glassBox(),
              child: Column(
                children: [
                  _buildNeonInput(controller: _firstNameCtrl, icon: Icons.badge_outlined, label: "Prénom"),
                  const SizedBox(height: 20),
                  _buildNeonInput(controller: _lastNameCtrl, icon: Icons.person_outline_rounded, label: "Nom"),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep2Contact() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          const SizedBox(height: 20),
          FadeInSlide(delay: 0.1, child: _headerIcon(Icons.contact_phone_rounded)),
          const SizedBox(height: 20),
          const FadeInSlide(delay: 0.2, child: Text("Vos coordonnées", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: AppTheme.textDark))),
          const FadeInSlide(delay: 0.3, child: Text("Pour sécuriser votre compte.", style: TextStyle(color: AppTheme.textGrey))),
          const SizedBox(height: 40),
          FadeInSlide(
            delay: 0.4,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: AppTheme.glassBox(),
              child: Column(
                children: [
                  _buildNeonInput(controller: _emailCtrl, icon: Icons.alternate_email_rounded, label: "Email", type: TextInputType.emailAddress),
                  const SizedBox(height: 20),
                  _buildNeonInput(controller: _phoneCtrl, icon: Icons.phone_iphone_rounded, label: "Téléphone", type: TextInputType.phone),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep3Security() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          const SizedBox(height: 20),
          FadeInSlide(delay: 0.1, child: _headerIcon(Icons.lock_person_rounded)),
          const SizedBox(height: 20),
          const FadeInSlide(delay: 0.2, child: Text("Sécurisez le tout", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: AppTheme.textDark))),
          const FadeInSlide(delay: 0.3, child: Text("Un mot de passe solide.", style: TextStyle(color: AppTheme.textGrey))),
          const SizedBox(height: 40),
          FadeInSlide(
            delay: 0.4,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: AppTheme.glassBox(),
              child: Column(
                children: [
                  _buildNeonInput(
                      controller: _passCtrl,
                      icon: Icons.lock_outline_rounded,
                      label: "Mot de passe",
                      isPassword: true,
                      obscure: _obscurePass,
                      onToggleObscure: () => setState(() => _obscurePass = !_obscurePass)
                  ),
                  const SizedBox(height: 20),
                  _buildNeonInput(
                      controller: _confirmPassCtrl,
                      icon: Icons.check_circle_outline_rounded,
                      label: "Confirmer mot de passe",
                      isPassword: true,
                      obscure: _obscureConfirm,
                      onToggleObscure: () => setState(() => _obscureConfirm = !_obscureConfirm)
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- HELPERS ---
  Widget _headerIcon(IconData icon) {
    return Container(
      width: 80, height: 80,
      decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white, boxShadow: [BoxShadow(color: AppTheme.neonPrimary.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 5))]),
      child: Icon(icon, size: 36, color: AppTheme.neonPrimary),
    );
  }

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
        Text(label.toUpperCase(), style: const TextStyle(color: AppTheme.textGrey, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: TextFormField(
            controller: controller, keyboardType: type, obscureText: isPassword ? obscure : false,
            style: const TextStyle(color: AppTheme.textDark, fontWeight: FontWeight.w600),
            cursorColor: AppTheme.neonPrimary,
            decoration: InputDecoration(
              prefixIcon: Icon(icon, color: AppTheme.neonPrimary),
              suffixIcon: isPassword
                  ? IconButton(icon: Icon(obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: AppTheme.textGrey), onPressed: onToggleObscure)
                  : null,
              border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              hintText: "Entrez votre $label", hintStyle: TextStyle(color: Colors.grey.shade400),
            ),
          ),
        ),
      ],
    );
  }
}