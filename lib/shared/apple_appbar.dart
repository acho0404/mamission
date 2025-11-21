import 'package:flutter/material.dart';

PreferredSizeWidget buildAppleMissionAppBar({
  Widget? leading,
  String? title,
  Widget? centerWidget,
  List<Widget>? actions,
}) {
  return AppBar(
    automaticallyImplyLeading: false,
    backgroundColor: const Color(0xFF6C63FF),
    elevation: 0,
    toolbarHeight: 70,
    centerTitle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.only(
        bottomLeft: Radius.circular(22),
        bottomRight: Radius.circular(22),
      ),
    ),

    leading: leading,

    // 👇 LOGIQUE AUTOMATIQUE : si tu mets centerWidget → priorité
    // sinon title → affiché au centre
    // sinon rien
    title: centerWidget ??
        (title != null
            ? Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        )
            : null),

    actions: actions,
  );
}