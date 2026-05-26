import 'package:flutter/material.dart';

import '../services/api_service.dart';

bool isClientLoggedIn() {
  final token = (ApiService.authToken ?? '').trim();
  final role = (ApiService.savedUserRole ?? '').toLowerCase().trim();
  return token.isNotEmpty && role == 'client';
}

/// Retourne `true` si le client est connecté (après login/inscription si besoin).
Future<bool> ensureClientLoggedIn(
  BuildContext context, {
  Future<void> Function()? openLogin,
}) async {
  await ApiService.loadSavedAuth();
  if (isClientLoggedIn()) return true;

  if (!context.mounted) return false;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text(
        'Connectez-vous ou créez un compte pour voir le détail ou acheter.',
      ),
      backgroundColor: Color(0xFF1D88E5),
      duration: Duration(seconds: 4),
    ),
  );

  if (openLogin != null) {
    await openLogin();
  }

  if (!context.mounted) return false;
  await ApiService.loadSavedAuth();
  return isClientLoggedIn();
}
