import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'services/api_service.dart';

class AddConcepteurPage extends StatefulWidget {
  /// Si renseigné : édition (PUT `/api/concepteurs/:id`). Sinon création.
  final Map<String, dynamic>? initialData;

  /// Intégré au dashboard (sans pile de navigation) : retour vers la liste conception.
  final VoidCallback? onEmbeddedBack;

  final bool isDarkMode;

  const AddConcepteurPage({super.key, this.initialData, this.onEmbeddedBack, this.isDarkMode = false});

  @override
  State<AddConcepteurPage> createState() => _AddConcepteurPageState();
}


class _AddConcepteurPageState extends State<AddConcepteurPage> {
  // ── Theme-aware color getters ──
  Color get _bg        => widget.isDarkMode ? const Color(0xFF10102B) : const Color(0xFFFCFAF7);
  Color get _surface   => widget.isDarkMode ? const Color(0xFF1D1D38) : const Color(0xFFFFFFFF);
  Color get _onSurface => widget.isDarkMode ? const Color(0xFFE2DFFF) : const Color(0xFF332A21);
  Color get _onVariant => widget.isDarkMode ? const Color(0xFFE2BFB0) : const Color(0xFF8B5E3C);
  static const _primary = Color(0xFFFF6E00);

  final _fullName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  final _location = TextEditingController();
  bool _loading = false;
  bool _loadingProfile = false;
  bool _obscure = true;
  bool _obscureConfirm = true;
  bool _sendCredentialsEmail = true;

  bool get _isEdit {
    final id = widget.initialData?['id']?.toString();
    return id != null && id.isNotEmpty;
  }

  @override
  void initState() {
    super.initState();
    _applyInitial(widget.initialData);
    if (_isEdit) _loadProfileFromApi();
  }

  @override
  void didUpdateWidget(AddConcepteurPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialData != oldWidget.initialData) {
      _applyInitial(widget.initialData);
      if (_isEdit) _loadProfileFromApi();
    }
  }

  void _applyInitial(Map<String, dynamic>? init) {
    if (init == null) return;
    _fullName.text = (init['username'] ?? init['nom'] ?? init['name'] ?? '').toString();
    _email.text = (init['email'] ?? '').toString();
    _location.text = (init['location'] ?? init['adresse'] ?? '').toString();
  }

  Future<void> _loadProfileFromApi() async {
    final id = widget.initialData?['id']?.toString().trim();
    if (id == null || id.isEmpty) return;
    setState(() => _loadingProfile = true);
    try {
      final data = await ApiService.getConcepteur(id);
      if (!mounted) return;
      _applyInitial(data);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Chargement du profil : $e'),
          backgroundColor: Colors.orange,
        ),
      );
    } finally {
      if (mounted) setState(() => _loadingProfile = false);
    }
  }

  @override
  void dispose() {
    _fullName.dispose();
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    _location.dispose();
    super.dispose();
  }

  String _credentialsEmailSnackMessage(Map<String, dynamic>? mail) {
    if (mail == null) return '';
    if (mail['sent'] == true) {
      return 'Un e-mail avec le mot de passe a été envoyé à ${mail['to'] ?? 'l\'adresse indiquée'}.';
    }
    final reason = (mail['reason'] ?? '').toString();
    final detail = (mail['detail'] ?? '').toString().trim();
    switch (reason) {
      case 'smtp_not_configured':
        return 'Compte enregistré. Configurez SMTP_HOST dans iot-backend/.env pour l\'e-mail automatique.';
      case 'smtp_credentials_missing':
        return 'Compte enregistré. SMTP_USER / SMTP_PASS manquants dans .env.';
      case 'synthetic_email_skip':
        return 'Compte enregistré. Adresse e-mail non valide pour l\'envoi.';
      case 'send_failed':
        if (detail.isNotEmpty) {
          return 'E-mail non envoyé : $detail (Gmail : utilisez un mot de passe d\'application).';
        }
        return 'E-mail non envoyé. Vérifiez SMTP dans .env (mot de passe d\'application Gmail).';
      default:
        return '';
    }
  }

  Future<void> _submit() async {
    final fullName = _fullName.text.trim();
    final email = _email.text.trim().toLowerCase();
    final password = _password.text;
    final confirmPassword = _confirmPassword.text;
    final location = _location.text.trim();

    if (fullName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Le nom complet est obligatoire'), backgroundColor: Colors.red),
      );
      return;
    }

    if (!email.contains('@') || email.length < 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez entrer une adresse email valide'), backgroundColor: Colors.red),
      );
      return;
    }

    if (!_isEdit && password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Le mot de passe est obligatoire à la création'), backgroundColor: Colors.red),
      );
      return;
    }

    if (password.isNotEmpty && password.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Le mot de passe doit contenir au moins 6 caractères'), backgroundColor: Colors.red),
      );
      return;
    }

    if (password != confirmPassword) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Les mots de passe ne correspondent pas'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final body = <String, dynamic>{
        'email': email,
        'username': fullName,
        'location': location,
      };

      Map<String, dynamic> result;
      if (_isEdit) {
        final id = widget.initialData!['id']!.toString();
        if (password.isNotEmpty) body['password'] = password;
        result = await ApiService.updateConcepteur(id, body);
      } else {
        body['password'] = password;
        body['sendEmail'] = _sendCredentialsEmail;
        result = await ApiService.addConcepteur(body);
      }
      if (!context.mounted) return;

      final mailInfo = result['credentialsEmail'];
      final mailMap = mailInfo is Map ? Map<String, dynamic>.from(mailInfo) : null;
      final mailMsg = _credentialsEmailSnackMessage(mailMap);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isEdit
                ? (mailMsg.isNotEmpty
                    ? 'Concepteur mis à jour. $mailMsg'
                    : 'Concepteur mis à jour avec succès')
                : (mailMsg.isNotEmpty
                    ? 'Concepteur créé. $mailMsg'
                    : 'Concepteur créé avec succès'),
          ),
          backgroundColor: mailMap?['sent'] == true ? Colors.green : const Color(0xFF32324E),
          duration: const Duration(seconds: 6),
        ),
      );

      if (widget.onEmbeddedBack != null) {
        widget.onEmbeddedBack!();
      } else {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (!context.mounted) return;
      final msg = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red, duration: const Duration(seconds: 6)),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: _onSurface,
        automaticallyImplyLeading: widget.onEmbeddedBack == null,
        leading: widget.onEmbeddedBack != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onEmbeddedBack,
              )
            : null,
        title: Text(
          _isEdit ? 'Modifier le concepteur' : 'Nouveau concepteur',
          style: GoogleFonts.inter(fontWeight: FontWeight.bold),
        ),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _isEdit
                          ? 'ÉDITION DU PROFIL CONCEPTEUR'
                          : 'NOUVEAU COMPTE CONCEPTEUR',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 16,
                        color: _primary,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 3,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      height: 2,
                      width: 40,
                      decoration: BoxDecoration(
                        color: _primary,
                        boxShadow: [
                          BoxShadow(
                            color: _primary.withOpacity(0.5),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      _isEdit
                          ? 'Modifiez les informations essentielles ci-dessous.'
                          : 'Remplissez les informations pour créer un nouvel accès conception.',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: _onSurface.withOpacity(0.7),
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isEdit
                          ? 'Modifiez le nom, l\'e-mail ou la localisation. Laissez le mot de passe vide pour ne pas le changer.'
                          : 'Créez un accès conception (indépendant des clients).',
                      style: GoogleFonts.inter(fontSize: 12, color: _onVariant, height: 1.4),
                    ),
                    if (!_isEdit) ...[
                      const SizedBox(height: 10),
                      CheckboxListTile(
                        value: _sendCredentialsEmail,
                        onChanged: (v) => setState(() => _sendCredentialsEmail = v ?? true),
                        activeColor: _primary,
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          'Envoyer les identifiants par e-mail',
                          style: GoogleFonts.inter(color: _onSurface, fontSize: 14),
                        ),
                        subtitle: Text(
                          'Un e-mail contenant l\'adresse et le mot de passe sera envoyé au concepteur.',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: _onVariant.withValues(alpha: 0.85),
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    _field('NOM COMPLET', _fullName, icon: Icons.person_outline),
                    _field('ADRESSE EMAIL', _email, keyboard: TextInputType.emailAddress, icon: Icons.email_outlined),
                    _field(
                      _isEdit ? 'NOUVEAU MOT DE PASSE (optionnel)' : 'MOT DE PASSE',
                      _password,
                      obscure: _obscure,
                      icon: Icons.lock_outline,
                      suffix: IconButton(
                        icon: Icon(
                          _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                          color: _onVariant,
                          size: 20,
                        ),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    _field(
                      'CONFIRMER LE MOT DE PASSE',
                      _confirmPassword,
                      obscure: _obscureConfirm,
                      icon: Icons.lock_reset_outlined,
                      suffix: IconButton(
                        icon: Icon(
                          _obscureConfirm ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                          color: _onVariant,
                          size: 20,
                        ),
                        onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                      ),
                    ),
                    _field('LOCALISATION / SITE', _location, icon: Icons.location_on_outlined),
                    const SizedBox(height: 24),
                    const SizedBox(height: 32),
                    InkWell(
                      onTap: _loading || _loadingProfile ? null : _submit,
                      borderRadius: BorderRadius.circular(16),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: LinearGradient(
                            colors: [
                              _primary,
                              const Color(0xFFFF8A65),
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: _primary.withOpacity(0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Center(
                          child: _loading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                            )
                          : Text(
                              _isEdit ? 'METTRE À JOUR LE PROFIL' : 'CONFIRMER LA CRÉATION',
                              style: GoogleFonts.spaceGrotesk(
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.5,
                                color: Colors.white,
                                fontSize: 14,
                              ),
                            ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_loadingProfile)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: const LinearProgressIndicator(color: _primary, minHeight: 2),
            ),
        ],
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController c, {
    TextInputType? keyboard,
    bool obscure = false,
    Widget? suffix,
    IconData? icon,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 10,
              color: _onVariant,
              letterSpacing: 1.5,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: c,
            keyboardType: keyboard,
            obscureText: obscure,
            style: GoogleFonts.inter(color: _onSurface, fontSize: 14, fontWeight: FontWeight.w500),
            decoration: InputDecoration(
              filled: true,
              fillColor: widget.isDarkMode ? Colors.white.withOpacity(0.03) : _surface,
              prefixIcon: icon != null ? Icon(icon, color: _primary.withOpacity(0.7), size: 20) : null,
              suffixIcon: suffix,
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: widget.isDarkMode ? Colors.white.withOpacity(0.1) : const Color(0xFFCD7F32).withOpacity(0.3)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: widget.isDarkMode ? Colors.white.withOpacity(0.08) : const Color(0xFFCD7F32).withOpacity(0.2)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: _primary, width: 2),
              ),
              hintText: label.toUpperCase(),
              hintStyle: GoogleFonts.spaceGrotesk(
                fontSize: 10,
                color: _onVariant.withOpacity(widget.isDarkMode ? 0.2 : 0.4),
                letterSpacing: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
