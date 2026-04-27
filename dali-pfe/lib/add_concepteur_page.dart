import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'services/api_service.dart';

class AddConcepteurPage extends StatefulWidget {
  /// Si renseigné : édition (PUT `/api/concepteurs/:id`). Sinon création.
  final Map<String, dynamic>? initialData;

  /// Intégré au dashboard (sans pile de navigation) : retour vers la liste conception.
  final VoidCallback? onEmbeddedBack;

  const AddConcepteurPage({super.key, this.initialData, this.onEmbeddedBack});

  @override
  State<AddConcepteurPage> createState() => _AddConcepteurPageState();
}


class _AddConcepteurPageState extends State<AddConcepteurPage> {
  static const _bg = Color(0xFF10102B);
  static const _surface = Color(0xFF1D1D38);
  static const _onSurface = Color(0xFFE2DFFF);
  static const _onVariant = Color(0xFFE2BFB0);
  static const _primary = Color(0xFFFF6E00);

  final _fullName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  final _location = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  bool _obscureConfirm = true;

  bool _machinesLoading = false;
  String? _machinesError;

  bool get _isEdit {
    final id = widget.initialData?['id']?.toString();
    return id != null && id.isNotEmpty;
  }

  @override
  void initState() {
    super.initState();
    final init = widget.initialData;
    if (init != null) {
      _fullName.text = (init['username'] ?? init['name'] ?? '').toString();
      _email.text = (init['email'] ?? '').toString();
      _location.text = (init['location'] ?? '').toString();
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

  Future<void> _submit() async {
    final fullName = _fullName.text.trim();
    final email = _email.text.trim();
    final password = _password.text.trim();
    final confirmPassword = _confirmPassword.text.trim();
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

      if (_isEdit) {
        final id = widget.initialData!['id']!.toString();
        if (password.isNotEmpty) body['password'] = password;
        await ApiService.updateConcepteur(id, body);
      } else {
        body['password'] = password;
        await ApiService.addConcepteur(body);
      }
      if (!context.mounted) return;
      // Navigate to the concepteur dashboard after adding/editing
      Navigator.of(context).pushReplacementNamed('/concepteur-dashboard');
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red),
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
      body: SingleChildScrollView(
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
                    fontSize: 14,
                    color: _primary,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _isEdit
                      ? 'Mise à jour des informations d\'accès et de localisation.'
                      : 'Créez un accès pour un nouveau membre de l\'équipe de conception.',
                  style: GoogleFonts.inter(fontSize: 12, color: _onVariant, height: 1.4),
                ),
                if (!_isEdit) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Rôle : concepteur',
                    style: GoogleFonts.spaceGrotesk(
                      color: _primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                _field('👤 NOM COMPLET', _fullName, icon: Icons.person_outline),
                _field('📧 ADRESSE EMAIL', _email, keyboard: TextInputType.emailAddress, icon: Icons.email_outlined),
                _field(
                  '🔒 MOT DE PASSE',
                  _password,
                  obscure: _obscure,
                  icon: Icons.lock_outline,
                  suffix: IconButton(
                    icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: _onVariant, size: 20),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                _field(
                  '🔒 CONFIRMER LE MOT DE PASSE',
                  _confirmPassword,
                  obscure: _obscureConfirm,
                  icon: Icons.lock_reset_outlined,
                  suffix: IconButton(
                    icon: Icon(_obscureConfirm ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: _onVariant, size: 20),
                    onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                ),
                _field('📍 LOCALISATION / SITE', _location, icon: Icons.location_on_outlined),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _loading ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: _primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _loading
                      ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(
                          _isEdit ? 'ENREGISTRER' : 'CRÉER LE COMPTE',
                          style: GoogleFonts.inter(fontWeight: FontWeight.bold, letterSpacing: 1),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }


  Widget _field(String label, TextEditingController c, {TextInputType? keyboard, bool obscure = false, Widget? suffix, IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _onVariant, letterSpacing: 1.5, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: c,
            keyboardType: keyboard,
            obscureText: obscure,
            style: GoogleFonts.inter(color: _onSurface, fontSize: 14),
            decoration: InputDecoration(
              filled: true,
              fillColor: _surface,
              prefixIcon: icon != null ? Icon(icon, color: _primary.withOpacity(0.7), size: 18) : null,
              suffixIcon: suffix,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _onVariant.withOpacity(0.1))),
              enabledBorder:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _onVariant.withOpacity(0.1))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _primary, width: 1.5)),
            ),
          ),
        ],
      ),
    );
  }
}
