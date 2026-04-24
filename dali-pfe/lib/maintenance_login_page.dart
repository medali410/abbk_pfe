import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'services/api_service.dart';

class MaintenanceLoginPage extends StatefulWidget {
  const MaintenanceLoginPage({super.key});

  @override
  State<MaintenanceLoginPage> createState() => _MaintenanceLoginPageState();
}

class _MaintenanceLoginPageState extends State<MaintenanceLoginPage> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;
  bool _loading = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez remplir email et mot de passe.')),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final response = await ApiService.maintenanceLogin(email, password);
      final token = response['token']?.toString();
      await ApiService.saveAuth(
        (token != null && token.isNotEmpty) ? token : null,
        'maintenance',
      );
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/maintenance-dashboard');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF0F1022);
    const panel = Color(0xFF151833);
    const text = Color(0xFFE2DFFF);
    const muted = Color(0xFFE2BFB0);
    const accent = Color(0xFFFF7E21);

    return Scaffold(
      backgroundColor: bg,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Container(
            margin: const EdgeInsets.all(20),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: panel,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withOpacity(0.06)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'LOGIN MAINTENANCE',
                  style: GoogleFonts.spaceGrotesk(
                    color: text,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Accès agent maintenance pour suivi des machines.',
                  style: GoogleFonts.inter(color: muted, fontSize: 12),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _emailCtrl,
                  style: GoogleFonts.inter(color: text),
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.alternate_email_rounded),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _passwordCtrl,
                  obscureText: _obscure,
                  style: GoogleFonts.inter(color: text),
                  decoration: InputDecoration(
                    labelText: 'Mot de passe',
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(
                      onPressed: () => setState(() => _obscure = !_obscure),
                      icon: Icon(
                        _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  onSubmitted: (_) => _loading ? null : _submit(),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    TextButton(
                      onPressed: _loading
                          ? null
                          : () => Navigator.pushReplacementNamed(context, '/'),
                      child: const Text('Retour login principal'),
                    ),
                    const Spacer(),
                    ElevatedButton.icon(
                      onPressed: _loading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.black,
                      ),
                      icon: _loading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.login_rounded, size: 16),
                      label: Text(
                        _loading ? 'Connexion...' : 'Se connecter',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

