import 'dart:ui'; // Pour le flou
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mamission/shared/services/push_token_service.dart';

// Logo principal
const String kAppLogoPath = 'assets/icons/ic_launcher_fg.png';
// Hauteur réservée pour le bouton CONTINUER (pour ne pas recouvrir les champs)
const double kBottomButtonSpace = 120;

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

class _FadeInSlideState extends State<FadeInSlide>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    _fadeAnim = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slideAnim =
        Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero).animate(
          CurvedAnimation(parent: _controller, curve: Curves.easeOutQuart),
        );
    Future.delayed(
      Duration(milliseconds: (widget.delay * 1000).round()),
          () {
        if (mounted) _controller.forward();
      },
    );
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

  // --- VALIDATION LIVE POUR LE BOUTON ---
  bool get _isStep1Valid =>
      _firstNameCtrl.text.trim().isNotEmpty &&
          _lastNameCtrl.text.trim().isNotEmpty;

  bool get _isStep2Valid =>
      _emailCtrl.text.trim().contains('@') &&
          _phoneCtrl.text.trim().length >= 8;

  bool get _isStep3Valid =>
      _passCtrl.text.length >= 6 &&
          _passCtrl.text == _confirmPassCtrl.text;

  bool get _canContinue {
    switch (_currentStep) {
      case 0:
        return _isStep1Valid;
      case 1:
        return _isStep2Valid;
      case 2:
        return _isStep3Valid;
      default:
        return false;
    }
  }

  // Force du mot de passe (0 → 1)
  double get _passwordStrength {
    final pass = _passCtrl.text;
    if (pass.isEmpty) return 0;
    double s = 0;
    if (pass.length >= 6) s += 0.3;
    if (RegExp(r'[A-Z]').hasMatch(pass)) s += 0.2;
    if (RegExp(r'[0-9]').hasMatch(pass)) s += 0.2;
    if (RegExp(r'[!@#\$%^&*(),.?":{}|<>]').hasMatch(pass)) s += 0.3;
    return s.clamp(0.0, 1.0).toDouble();
  }

  String get _passwordStrengthLabel {
    final s = _passwordStrength;
    if (s == 0) return '';
    if (s < 0.3) return "Très faible";
    if (s < 0.6) return "Moyen";
    return "Solide";
  }

  Color get _passwordStrengthColor {
    final s = _passwordStrength;
    if (s < 0.3) return Colors.redAccent;
    if (s < 0.6) return Colors.orangeAccent;
    return Colors.green;
  }

  @override
  void initState() {
    super.initState();
    for (final c in [
      _firstNameCtrl,
      _lastNameCtrl,
      _emailCtrl,
      _phoneCtrl,
      _passCtrl,
      _confirmPassCtrl,
    ]) {
      c.addListener(_onFormChanged);
    }
  }

  void _onFormChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _pageController.dispose();
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passCtrl.dispose();
    _confirmPassCtrl.dispose();
    super.dispose();
  }

  void _prevStep() {
    if (_currentStep > 0) {
      _pageController.previousPage(
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOutQuart);
      setState(() => _currentStep--);
    } else {
      context.go('/login');
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.redAccent),
    );
  }

  Future<void> _register() async {
    setState(() => _loading = true);
    try {
      final cred = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text.trim(),
      );
      final uid = cred.user!.uid;
      final fullName =
          "${_firstNameCtrl.text.trim()} ${_lastNameCtrl.text.trim()}";

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
      if (e.code == 'email-already-in-use') {
        msg = "Cet email est déjà utilisé.";
      }
      if (e.code == 'weak-password') {
        msg = "Mot de passe trop faible.";
      }
      _showError(msg);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onContinuePressed() {
    FocusScope.of(context).unfocus();
    if (!_canContinue || _loading) return;

    if (_currentStep < _totalSteps - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutQuart,
      );
      setState(() => _currentStep++);
    } else {
      _register();
    }
  }

  @override
  Widget build(BuildContext context) {
    final double progress = (_currentStep + 1) / _totalSteps;
    final bool enabled = _canContinue && !_loading;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: AppTheme.bgLight,
        resizeToAvoidBottomInset: true,
        body: Stack(
          children: [
            // DÉCOR
            Positioned(
              top: -80,
              right: -50,
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
              left: -100,
              child: Container(
                width: 400,
                height: 400,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.neonCyan.withOpacity(0.1),
                ),
              ),
            ),
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                child: Container(color: Colors.transparent),
              ),
            ),

            // CONTENU PRINCIPAL
            SafeArea(
              child: Column(
                children: [
                  // HEADER NAV
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        GestureDetector(
                          onTap: _prevStep,
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.grey.shade200,
                                  blurRadius: 10,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.arrow_back,
                              color: AppTheme.textDark,
                              size: 20,
                            ),
                          ),
                        ),
                        Text(
                          "ÉTAPE ${_currentStep + 1} / $_totalSteps",
                          style: const TextStyle(
                            color: AppTheme.textGrey,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(width: 44),
                      ],
                    ),
                  ),

                  // PROGRESS BAR
                  Container(
                    height: 6,
                    width: double.infinity,
                    margin: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: progress,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [AppTheme.neonPrimary, AppTheme.neonCyan],
                          ),
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
                ],
              ),
            ),
          ],
        ),

        // --- BOUTON CONTINUER / CRÉER MON COMPTE ---
        bottomNavigationBar: AnimatedPadding(
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.fromLTRB(
            24,
            8,
            24,
            16 + bottomInset,
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: enabled ? _onContinuePressed : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: Ink(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppTheme.neonPrimary, Color(0xFF4F46E5)],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.neonPrimary.withOpacity(0.4),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                  child: Opacity(
                    opacity: enabled ? 1 : 0.4,
                    child: Container(
                      alignment: Alignment.center,
                      child: _loading
                          ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                          : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _currentStep == _totalSteps - 1
                                ? "CRÉER MON COMPTE"
                                : "CONTINUER",
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 1,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.arrow_forward_rounded,
                            color: Colors.white,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --- ÉTAPES WIDGETS ---

  Widget _buildStep1Identity() {
    // true si le clavier est ouvert
    final bool isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        24,
        0,
        24,
        isKeyboardOpen ? 16 : kBottomButtonSpace, // moins de marge quand clavier
      ),
      child: Column(
        children: [
          SizedBox(height: isKeyboardOpen ? 8 : 20),

          // 👉 Mode normal : logo + gros titre
          if (!isKeyboardOpen) ...[
            FadeInSlide(
              delay: 0.1,
              child: SizedBox(
                width: 100,
                height: 100,
                child: Image.asset(
                  kAppLogoPath,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                ),
              ),
            ),
            const SizedBox(height: 20),
            const FadeInSlide(
              delay: 0.2,
              child: Text(
                "Faisons connaissance",
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.textDark,
                ),
              ),
            ),
            const FadeInSlide(
              delay: 0.3,
              child: Text(
                "Comment vous appelez-vous ?",
                style: TextStyle(color: AppTheme.textGrey),
              ),
            ),
            const SizedBox(height: 40),
          ] else ...[
            // 👉 Quand le clavier est ouvert : header compact, plus de logo
            const Text(
              "Faisons connaissance",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppTheme.textDark,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "Comment vous appelez-vous ?",
              style: TextStyle(
                fontSize: 13,
                color: AppTheme.textGrey,
              ),
            ),
            const SizedBox(height: 16),
          ],

          // 📋 Carte avec Prénom / Nom (remonte quand clavier ouvert)
          FadeInSlide(
            delay: isKeyboardOpen ? 0.1 : 0.4,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: AppTheme.glassBox(),
              child: Column(
                children: [
                  _buildNeonInput(
                    controller: _firstNameCtrl,
                    icon: Icons.badge_outlined,
                    label: "Prénom",
                  ),
                  const SizedBox(height: 20),
                  _buildNeonInput(
                    controller: _lastNameCtrl,
                    icon: Icons.person_outline_rounded,
                    label: "Nom",
                  ),
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
      padding: const EdgeInsets.fromLTRB(
        24,
        0,
        24,
        kBottomButtonSpace,
      ),
      child: Column(
        children: [
          const SizedBox(height: 20),
          FadeInSlide(
            delay: 0.1,
            child: _headerIcon(Icons.contact_phone_rounded),
          ),
          const SizedBox(height: 20),
          const FadeInSlide(
            delay: 0.2,
            child: Text(
              "Vos coordonnées",
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: AppTheme.textDark,
              ),
            ),
          ),
          const FadeInSlide(
            delay: 0.3,
            child: Text(
              "Pour sécuriser votre compte.",
              style: TextStyle(color: AppTheme.textGrey),
            ),
          ),
          const SizedBox(height: 40),
          FadeInSlide(
            delay: 0.4,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: AppTheme.glassBox(),
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
                    controller: _phoneCtrl,
                    icon: Icons.phone_iphone_rounded,
                    label: "Téléphone",
                    type: TextInputType.phone,
                  ),
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
      padding: const EdgeInsets.fromLTRB(
        24,
        0,
        24,
        kBottomButtonSpace,
      ),
      child: Column(
        children: [
          const SizedBox(height: 20),
          FadeInSlide(
            delay: 0.1,
            child: _headerIcon(Icons.lock_person_rounded),
          ),
          const SizedBox(height: 20),
          const FadeInSlide(
            delay: 0.2,
            child: Text(
              "Sécurisez le tout",
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: AppTheme.textDark,
              ),
            ),
          ),
          const FadeInSlide(
            delay: 0.3,
            child: Text(
              "Un mot de passe solide.",
              style: TextStyle(color: AppTheme.textGrey),
            ),
          ),
          const SizedBox(height: 40),
          FadeInSlide(
            delay: 0.4,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: AppTheme.glassBox(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildNeonInput(
                    controller: _passCtrl,
                    icon: Icons.lock_outline_rounded,
                    label: "Mot de passe",
                    isPassword: true,
                    obscure: _obscurePass,
                    onToggleObscure: () =>
                        setState(() => _obscurePass = !_obscurePass),
                  ),
                  const SizedBox(height: 8),
                  AnimatedOpacity(
                    opacity: _passCtrl.text.isEmpty ? 0 : 1,
                    duration: const Duration(milliseconds: 250),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: _passwordStrength,
                            minHeight: 6,
                            backgroundColor: Colors.grey.shade200,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              _passwordStrengthColor,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        if (_passwordStrengthLabel.isNotEmpty)
                          Text(
                            "Mot de passe $_passwordStrengthLabel",
                            style: TextStyle(
                              fontSize: 12,
                              color: _passwordStrengthColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buildNeonInput(
                    controller: _confirmPassCtrl,
                    icon: Icons.check_circle_outline_rounded,
                    label: "Confirmer mot de passe",
                    isPassword: true,
                    obscure: _obscureConfirm,
                    onToggleObscure: () =>
                        setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    "• Minimum 6 caractères\n"
                        "• Idéalement une majuscule, un chiffre et un symbole",
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textGrey,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- HELPERS UI ---
  Widget _headerIcon(IconData icon) {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: AppTheme.neonPrimary.withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
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
            style: const TextStyle(
              color: AppTheme.textDark,
              fontWeight: FontWeight.w600,
            ),
            cursorColor: AppTheme.neonPrimary,

            // 🔑 IMPORTANT : on laisse de la place pour le bouton CONTINUER
            scrollPadding: const EdgeInsets.only(bottom: 220),

            decoration: InputDecoration(
              prefixIcon: Icon(icon, color: AppTheme.neonPrimary),
              suffixIcon: isPassword
                  ? IconButton(
                icon: Icon(
                  obscure
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: AppTheme.textGrey,
                ),
                onPressed: onToggleObscure,
              )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
              hintText: "Entrez votre $label",
              hintStyle: TextStyle(color: Colors.grey.shade400),
            ),
          ),
        ),
      ],
    );
  }


}
