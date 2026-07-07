import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class ChatTheme {
  final BuildContext _context;
  
  ChatTheme._(this._context);

  static ChatTheme of(BuildContext context) => ChatTheme._(context);

  bool get _isDark => Theme.of(_context).brightness == Brightness.dark;

  // Couleurs principales
  Color get bg => _isDark ? const Color(0xFF0A0F18) : const Color(0xFFF3F6FA);
  Color get sidebar => _isDark ? const Color(0xFF101726) : const Color(0xFFFFFFFF);
  Color get header => _isDark ? const Color(0xFF0F1C31) : const Color(0xFFFFFFFF);
  Color get panel => _isDark ? const Color(0xFF131D32) : const Color(0xFFF8FAFC);
  Color get activeItem => _isDark ? const Color(0xFF263C65).withValues(alpha: 0.6) : const Color(0xFFE0E7FF).withValues(alpha: 0.7);
  
  // Couleurs des bulles
  Color get myBubble => const Color(0xFF2563EB); // Vibrant Blue
  Color get otherBubble => _isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0);

  // Couleurs de texte
  Color get text => _isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1E293B);
  Color get muted => _isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
  Color get accent => const Color(0xFFF97316); 
  
  // Couleurs d'état / rôles
  Color get online => const Color(0xFF10B981); 
  Color get offline => const Color(0xFF64748B); 
  Color get unread => const Color(0xFFEF4444); 

  Color get roleAdmin => const Color(0xFFEF4444);
  Color get roleConcepteur => const Color(0xFFA855F7);
  Color get roleTechnicien => const Color(0xFF3B82F6);
  Color get roleMaintenance => const Color(0xFFF97316);
  Color get roleClient => const Color(0xFF10B981);

  // Styles de texte
  TextStyle get titleStyle => GoogleFonts.inter(color: text, fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.5);
  TextStyle get subtitleStyle => GoogleFonts.inter(color: muted, fontSize: 13, fontWeight: FontWeight.w500);
  TextStyle get nameStyle => GoogleFonts.inter(color: text, fontSize: 15, fontWeight: FontWeight.w700);
  TextStyle get messageStyle => GoogleFonts.inter(color: text, fontSize: 14);
  TextStyle get timeStyle => GoogleFonts.inter(color: muted, fontSize: 11);
  TextStyle get roleBadgeStyle => GoogleFonts.inter(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5);

  // Effets Glassmorphism et décorations
  BoxDecoration get glassDecoration => BoxDecoration(
    color: header.withValues(alpha: _isDark ? 0.7 : 0.95), 
    borderRadius: BorderRadius.circular(20),
    border: Border.all(color: _isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05)),
    boxShadow: [
      BoxShadow(color: Colors.black.withValues(alpha: _isDark ? 0.3 : 0.04), blurRadius: 16, spreadRadius: -2, offset: const Offset(0, 8)),
    ],
  );

  BoxDecoration get inputDecoration => BoxDecoration(
    color: bg.withValues(alpha: _isDark ? 0.5 : 0.8),
    borderRadius: BorderRadius.circular(28),
    border: Border.all(color: _isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.08)),
  );
}
