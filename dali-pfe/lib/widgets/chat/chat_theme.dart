import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class ChatTheme {
  final BuildContext _context;
  
  ChatTheme._(this._context);

  static ChatTheme of(BuildContext context) => ChatTheme._(context);

  bool get _isDark => Theme.of(_context).brightness == Brightness.dark;

  // Couleurs principales
  Color get bg => _isDark ? const Color(0xFF080D14) : const Color(0xFFF9FAFB);
  Color get sidebar => _isDark ? const Color(0xFF0D1526) : const Color(0xFFFFFFFF);
  Color get header => _isDark ? const Color(0xFF0F1C31) : const Color(0xFFFFFFFF);
  Color get panel => _isDark ? const Color(0xFF131D32) : const Color(0xFFF1F5F9);
  Color get activeItem => _isDark ? const Color(0xFF1A2B4C) : const Color(0xFFFFEDD5);
  
  // Couleurs des bulles
  Color get myBubble => const Color(0xFF3B82F6); 
  Color get otherBubble => _isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0);

  // Couleurs de texte
  Color get text => _isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1F2937);
  Color get muted => _isDark ? const Color(0xFF94A3B8) : const Color(0xFF6B7280);
  Color get accent => const Color(0xFFF97316); 
  
  // Couleurs d'état / rôles
  Color get online => const Color(0xFF22C55E); 
  Color get offline => const Color(0xFF64748B); 
  Color get unread => const Color(0xFFEF4444); 

  Color get roleAdmin => const Color(0xFFEF4444);
  Color get roleConcepteur => const Color(0xFFA855F7);
  Color get roleTechnicien => const Color(0xFF3B82F6);
  Color get roleMaintenance => const Color(0xFFF97316);
  Color get roleClient => const Color(0xFF22C55E);

  // Styles de texte
  TextStyle get titleStyle => GoogleFonts.inter(color: text, fontSize: 24, fontWeight: FontWeight.bold);
  TextStyle get subtitleStyle => GoogleFonts.inter(color: muted, fontSize: 13, fontWeight: FontWeight.w500);
  TextStyle get nameStyle => GoogleFonts.inter(color: text, fontSize: 15, fontWeight: FontWeight.w600);
  TextStyle get messageStyle => GoogleFonts.inter(color: text, fontSize: 14);
  TextStyle get timeStyle => GoogleFonts.inter(color: muted, fontSize: 11);
  TextStyle get roleBadgeStyle => GoogleFonts.inter(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold);

  // Effets Glassmorphism et décorations
  BoxDecoration get glassDecoration => BoxDecoration(
    color: header.withOpacity(_isDark ? 0.7 : 0.9), 
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: _isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05)),
    boxShadow: [
      BoxShadow(color: Colors.black.withOpacity(_isDark ? 0.2 : 0.05), blurRadius: 10, spreadRadius: 1),
    ],
  );

  BoxDecoration get inputDecoration => BoxDecoration(
    color: bg.withOpacity(_isDark ? 0.5 : 0.8),
    borderRadius: BorderRadius.circular(24),
    border: Border.all(color: _isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.1)),
  );
}
