import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

PreferredSizeWidget buildAppleMissionAppBar({
  Widget? leading,
  String? title,
  Widget? centerWidget,
  List<Widget>? actions,
}) {
  return AppBar(
    automaticallyImplyLeading: false,

    // ⚠️ IMPORTANT : On doit mettre transparent ici pour voir le dégradé en dessous
    backgroundColor: Colors.transparent,
    elevation: 0,
    toolbarHeight: 70,
    centerTitle: true,
    systemOverlayStyle: SystemUiOverlayStyle.light,

    // 👇 C'EST ICI QUE SE FAIT LE DÉGRADÉ
    flexibleSpace: Container(
      decoration: BoxDecoration(
        // L'arrondi du bas
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
        // Le fameux dégradé Futuriste
        gradient: const LinearGradient(
          colors: [
            Color(0xFF6C63FF), // Violet électrique (Haut Gauche)
            Color(0xFF4F46E5), // Indigo Profond (Bas Droite)
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        // L'effet de "Glow" (Ombre colorée)
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6C63FF).withOpacity(0.5),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
    ),

    // Le reste ne change pas
    leading: leading,
    title: centerWidget ??
        (title != null
            ? Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 19,
            letterSpacing: 0.5,
          ),
        )
            : null),
    actions: actions,
  );
}