import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class ChatTheme {
  // Couleurs principales (Thème sombre industriel ABBK)
  static const Color bg = Color(0xFF080D14);
  static const Color sidebar = Color(0xFF0D1526);
  static const Color header = Color(0xFF0F1C31);
  static const Color panel = Color(0xFF131D32); // Info panel droit
  static const Color activeItem = Color(0xFF1A2B4C);
  
  // Couleurs des bulles
  static const Color myBubble = Color(0xFF3B82F6); // Bleu vif pour nos messages
  static const Color otherBubble = Color(0xFF1E293B); // Gris sombre pour les autres

  // Couleurs de texte
  static const Color text = Color(0xFFF8FAFC);
  static const Color muted = Color(0xFF94A3B8);
  static const Color accent = Color(0xFFF97316); // Orange ABBK
  
  // Couleurs d'état / rôles
  static const Color online = Color(0xFF22C55E); // Vert
  static const Color offline = Color(0xFF64748B); // Gris
  static const Color unread = Color(0xFFEF4444); // Rouge

  static const Color roleAdmin = Color(0xFFEF4444);
  static const Color roleConcepteur = Color(0xFFA855F7);
  static const Color roleTechnicien = Color(0xFF3B82F6);
  static const Color roleMaintenance = Color(0xFFF97316);
  static const Color roleClient = Color(0xFF22C55E);

  // Styles de texte (Typographie moderne)
  static TextStyle titleStyle = GoogleFonts.inter(color: text, fontSize: 24, fontWeight: FontWeight.bold);
  static TextStyle subtitleStyle = GoogleFonts.inter(color: muted, fontSize: 13, fontWeight: FontWeight.w500);
  static TextStyle nameStyle = GoogleFonts.inter(color: text, fontSize: 15, fontWeight: FontWeight.w600);
  static TextStyle messageStyle = GoogleFonts.inter(color: text, fontSize: 14);
  static TextStyle timeStyle = GoogleFonts.inter(color: muted, fontSize: 11);
  static TextStyle roleBadgeStyle = GoogleFonts.inter(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold);

  // Effets Glassmorphism et décorations
  static BoxDecoration glassDecoration = BoxDecoration(
    color: header.withOpacity(0.7), // Using withOpacity to be compatible with older Flutter if withValues isn't available everywhere
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: Colors.white.withOpacity(0.05)),
    boxShadow: [
      BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 10, spreadRadius: 1),
    ],
  );

  static BoxDecoration inputDecoration = BoxDecoration(
    color: bg.withOpacity(0.5),
    borderRadius: BorderRadius.circular(24),
    border: Border.all(color: Colors.white.withOpacity(0.1)),
  );
}
