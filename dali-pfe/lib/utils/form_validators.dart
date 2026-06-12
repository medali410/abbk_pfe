/// Validation centralisée des formulaires Flutter.
/// Chaque fonction retourne `null` si valide, ou un message d'erreur.

class FormValidators {
  FormValidators._();

  // ---- Regex ----
  static final _emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');
  static final _phoneRegex = RegExp(r'^[+]?[\d\s\-().]{6,20}$');
  static final _urlRegex = RegExp(r'^https?://.+', caseSensitive: false);

  // ---- Primitives ----

  /// Valide un email. Si [required] est vrai, le champ ne peut pas être vide.
  static String? email(String? value, {bool required = false}) {
    final v = (value ?? '').trim().toLowerCase();
    if (v.isEmpty) {
      return required ? 'Email obligatoire' : null;
    }
    if (!_emailRegex.hasMatch(v)) {
      return 'Email invalide (ex: nom@domaine.fr)';
    }
    return null;
  }

  /// Valide un numéro de téléphone.
  static String? phone(String? value, {bool required = false}) {
    final v = (value ?? '').trim();
    if (v.isEmpty) {
      return required ? 'Téléphone obligatoire' : null;
    }
    if (!_phoneRegex.hasMatch(v)) {
      return 'Téléphone invalide (ex: +216 20 000 000)';
    }
    return null;
  }

  /// Valide une URL (http/https).
  static String? url(String? value, {bool required = false, String label = 'URL'}) {
    final v = (value ?? '').trim();
    if (v.isEmpty) {
      return required ? '$label obligatoire' : null;
    }
    if (!_urlRegex.hasMatch(v)) {
      return '$label invalide — doit commencer par http:// ou https://';
    }
    return null;
  }

  /// Valide une URL photo (accepte aussi data:image/).
  static String? photoUrl(String? value, {bool required = false}) {
    final v = (value ?? '').trim();
    if (v.isEmpty) {
      return required ? 'URL photo obligatoire' : null;
    }
    if (!_urlRegex.hasMatch(v) && !v.toLowerCase().startsWith('data:image/')) {
      return 'URL photo invalide — http://, https:// ou image locale';
    }
    return null;
  }

  /// Valide un nom / texte court (min 2 caractères, max 100).
  static String? nom(String? value, {bool required = true, String label = 'Nom'}) {
    final v = (value ?? '').trim();
    if (v.isEmpty) {
      return required ? '$label obligatoire' : null;
    }
    if (v.length < 2) {
      return '$label trop court (min 2 caractères)';
    }
    if (v.length > 100) {
      return '$label trop long (max 100 caractères)';
    }
    return null;
  }

  /// Valide un champ texte générique.
  static String? text(String? value, {
    bool required = false,
    int min = 0,
    int max = 255,
    String label = 'Champ',
  }) {
    final v = (value ?? '').trim();
    if (v.isEmpty) {
      return required ? '$label obligatoire' : null;
    }
    if (min > 0 && v.length < min) {
      return '$label trop court (min $min caractères)';
    }
    if (v.length > max) {
      return '$label trop long (max $max caractères)';
    }
    return null;
  }

  /// Valide un mot de passe.
  static String? password(String? value, {bool required = false}) {
    final v = value ?? '';
    if (v.isEmpty) {
      return required ? 'Mot de passe obligatoire' : null;
    }
    if (v.length < 6) {
      return 'Mot de passe trop court (min 6 caractères)';
    }
    if (v.length > 128) {
      return 'Mot de passe trop long';
    }
    return null;
  }
}
