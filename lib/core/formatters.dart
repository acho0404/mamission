import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

// Formate le nom en "Prénom N."
String formatUserName(String fullName) {
  if (fullName.trim().isEmpty) return 'Utilisateur';
  final parts = fullName.trim().split(RegExp(r'\s+'));
  if (parts.length == 1) return _capitalize(parts.first);

  // Vérifie si la première partie est en MAJUSCULES (ex: MOUSSEHIL Achraf)
  if (parts.first == parts.first.toUpperCase() && parts.first.length > 1) {
    // Format "NOM prénom" -> "Prénom N."
    final nom = parts.first;
    final prenom = parts.last;
    return "${_capitalize(prenom)} ${nom[0].toUpperCase()}."; // Ex: Achraf M.
  } else {
    // Format "Prénom nom" -> "Prénom N."
    final prenom = parts.first;
    final nom = parts.last;
    return "${_capitalize(prenom)} ${nom[0].toUpperCase()}."; // Ex: Achraf M.
  }
}

String _capitalize(String s) {
  if (s.isEmpty) return s;
  return s[0].toUpperCase() + s.substring(1).toLowerCase();
}

// Formate le temps écoulé
String formatTimeAgo(Timestamp? timestamp) {
  if (timestamp == null) return '';
  final date = timestamp.toDate();
  final now = DateTime.now();
  final difference = now.difference(date);

  if (difference.inSeconds < 60) {
    return 'il y a ${difference.inSeconds} s';
  } else if (difference.inMinutes < 60) {
    return 'il y a ${difference.inMinutes} min';
  } else if (difference.inHours < 24) {
    return 'il y a ${difference.inHours} h';
  } else if (difference.inDays == 1) {
    return 'hier';
  } else if (difference.inDays < 7) {
    return 'il y a ${difference.inDays} j';
  } else {
    // Fallback pour les dates plus anciennes
    return DateFormat('d MMM y', 'fr_FR').format(date);
  }
}

// Helper pour String (pour le fallback du statut)
extension StringExtension on String {
  String capitalize() {
    if (isEmpty) return this;
    return "${this[0].toUpperCase()}${substring(1).toLowerCase()}";
  }
}