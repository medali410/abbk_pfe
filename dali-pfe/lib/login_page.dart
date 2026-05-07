import 'dart:ui';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'client_dashboard_page.dart';
import 'dashboard_page.dart';
import 'services/api_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    this.returnToHomeAfterClientLogin = false,
    this.showSignupTitle = false,
  });

  final bool returnToHomeAfterClientLogin;
  final bool showSignupTitle;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _obscurePassword = true;
  bool _googleInitDone = false;
  final TextEditingController _loginEmailController = TextEditingController();
  final TextEditingController _loginPasswordController = TextEditingController();
  bool _loginSubmitting = false;
  final TextEditingController _signupNameController = TextEditingController();
  final TextEditingController _signupEmailController = TextEditingController();
  final TextEditingController _signupPasswordController = TextEditingController();
  final TextEditingController _signupConfirmPasswordController =
      TextEditingController();
  final TextEditingController _signupAddressController = TextEditingController();
  bool _signupSubmitting = false;

  @override
  void initState() {
    super.initState();
    _consumeGoogleOAuthReturn();
  }

  @override
  void dispose() {
    _loginEmailController.dispose();
    _loginPasswordController.dispose();
    _signupNameController.dispose();
    _signupEmailController.dispose();
    _signupPasswordController.dispose();
    _signupConfirmPasswordController.dispose();
    _signupAddressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Media queries for responsiveness
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 768;

    return Scaffold(
      body: Stack(
        children: [
          // 1. Atmospheric Background
          Positioned.fill(
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Background image
                Image.network(
                  'https://lh3.googleusercontent.com/aida-public/AB6AXuDBkR4A4dhmPATixlydJx6vZW4s3l-YYIEyC0l5IH_PdZ5mQy2XnMSVEGjbJH0lxfP9urL-LpBMM0J6mUHC26RBdm00Ip_Jz8L7_JuunIZVuGdy9HitrF--mCXdiUhBZqEvkwGmNFLuWrhIcFmJZmUbWrcB-AJMFjkl5N6cLzc5v7OMvAp823lS4zwr54W5xl7RIGslHE4MG113JYhHdxyKS4VEZdGbrJlv9khI1kzoWRY1vpkL6M0oBrz4hRRCFp1Sxp09EaAwpec',
                  fit: BoxFit.cover,
                  color: Colors.black.withOpacity(0.5), // "industrial-bg" brightness simulation
                  colorBlendMode: BlendMode.darken,
                ),
                // Gradient to background
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        const Color(0xFF0F0F1E).withOpacity(0.4),
                        const Color(0xFF0F0F1E).withOpacity(0.9),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 2. Main Scrollable Content
          SafeArea(
            child: Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 24.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Logo
                      Row(
                        children: [
                          Container(
                            width: 190,
                            height: 46,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Image.asset(
                              'assets/images/abbk_logo.png',
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.high,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Center LoginForm Content
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24.0),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 500),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 32.0, sigmaY: 32.0),
                            child: Container(
                              padding: const EdgeInsets.all(48.0),
                              decoration: BoxDecoration(
                                color: const Color(0xFF151525).withOpacity(0.4),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.08),
                                  width: 1,
                                ),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Title
                                  Text(
                                    widget.showSignupTitle
                                        ? 'INSCRIPTION'
                                        : 'CONNEXION',
                                    style: GoogleFonts.inter(
                                      fontSize: 28,
                                      fontWeight: FontWeight.w300,
                                      letterSpacing: 4.0,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Container(
                                    height: 1,
                                    width: 48,
                                    color: const Color(0xFFFF6E00),
                                  ),
                                  const SizedBox(height: 28),

                                  widget.showSignupTitle
                                      ? _buildClientSocialSection(context)
                                      : _buildSignInSection(context),

                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // Footer
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 48.0, vertical: 32.0),
                  color: const Color(0xFF0F0F1E).withOpacity(0.5),
                  child: Row(
                    mainAxisAlignment: isDesktop ? MainAxisAlignment.spaceBetween : MainAxisAlignment.center,
                    children: [
                      if (isDesktop)
                        Text(
                          '© 2024 PREDICTIVE CLOUD. TOUS DROITS RÉSERVÉS.',
                          style: GoogleFonts.inter(
                            fontSize: 9,
                            color: const Color(0xFFA0A0B0).withOpacity(0.6),
                            fontWeight: FontWeight.w500,
                            letterSpacing: 2.0,
                          ),
                        ),
                      Wrap(
                        spacing: 40,
                        alignment: WrapAlignment.center,
                        children: [
                          _buildFooterLink('CONFIDENTIALITÉ'),
                          _buildFooterLink('CONDITIONS'),
                          _buildFooterLink('SUPPORT TECHNIQUE'),
                        ],
                      )
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSignInSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _loginEmailController,
          style: const TextStyle(color: Colors.white),
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Email',
            hintText: 'utilisateur@entreprise.fr',
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _loginPasswordController,
          style: const TextStyle(color: Colors.white),
          obscureText: _obscurePassword,
          decoration: InputDecoration(
            labelText: 'Mot de passe',
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility_off : Icons.visibility,
                color: Colors.white54,
              ),
              onPressed: () {
                setState(() => _obscurePassword = !_obscurePassword);
              },
            ),
          ),
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: _loginSubmitting ? null : () => _submitLogin(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFF6E00),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child:
              _loginSubmitting
                  ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : Text(
                    'Se connecter',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                  ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(child: Divider(color: Colors.white.withOpacity(0.15))),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'OU',
                style: GoogleFonts.inter(
                  fontSize: 10,
                  color: const Color(0xFFA0A0B0),
                  letterSpacing: 3,
                ),
              ),
            ),
            Expanded(child: Divider(color: Colors.white.withOpacity(0.15))),
          ],
        ),
        const SizedBox(height: 14),
        _socialConnectPill(
          context: context,
          leading: _googleGLogo(),
          label: 'Se connecter avec Google',
          onTap: () => _authWithGoogle(context),
        ),
      ],
    );
  }

  Future<void> _submitLogin(BuildContext context) async {
    final email = _loginEmailController.text.trim();
    final password = _loginPasswordController.text;
    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez remplir tous les champs')),
      );
      return;
    }
    if (!email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Indiquez une adresse email valide (avec @).')),
      );
      return;
    }
    setState(() => _loginSubmitting = true);
    try {
      final response = await ApiService.login(email, password);
      if (!context.mounted) return;
      var role = (response['role'] ?? 'client').toString().toLowerCase();
      if (role == 'super_admin') role = 'superadmin';
      if (role == 'company_admin') role = 'admin';
      final token =
          response['token']?.toString() ??
          response['accessToken']?.toString() ??
          response['access_token']?.toString();
      await ApiService.saveAuth(
        (token != null && token.isNotEmpty) ? token : null,
        role,
      );

      if (role == 'superadmin' || role == 'admin') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const DashboardPage()),
        );
        return;
      }
      if (role == 'conception' || role == 'concepteur') {
        Navigator.pushReplacementNamed(context, '/concepteur-dashboard');
        return;
      }
      if (role == 'technician') {
        final args = Map<String, dynamic>.from(response);
        await ApiService.saveTechnicianSession(args);
        Navigator.pushReplacementNamed(
          context,
          '/technician-profile',
          arguments: args,
        );
        return;
      }
      if (role == 'maintenance') {
        Navigator.pushReplacementNamed(context, '/maintenance-dashboard');
        return;
      }

      final clientName = (response['name'] ?? 'Espace client').toString();
      final clientId = (response['clientId'] ?? response['id'] ?? '').toString();
      await ApiService.saveClientSession(
        clientId: clientId,
        clientName: clientName,
        clientEmail: (response['email'] ?? email).toString(),
        clientLocation: (response['location'] ?? '').toString(),
        clientPhotoUrl:
            (response['photoUrl'] ??
                    response['avatarUrl'] ??
                    response['profilePhotoUrl'] ??
                    response['imageUrl'] ??
                    response['image'] ??
                    '')
                .toString(),
      );
      if (widget.returnToHomeAfterClientLogin) {
        Navigator.pop(context, true);
        return;
      }
      Navigator.pushReplacementNamed(context, '/client-dashboard');
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur: ${e.toString().replaceAll('Exception: ', '')}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _loginSubmitting = false);
    }
  }

  /// Boutons type « Continuer avec Google / Apple / téléphone » (OAuth à brancher : Firebase, backend).
  Widget _buildClientSocialSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'CLIENT — INSCRIPTION RAPIDE',
          style: GoogleFonts.inter(
            fontSize: 10,
            color: const Color(0xFFA0A0B0),
            fontWeight: FontWeight.w600,
            letterSpacing: 2.4,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Text(
          'Méthode 1 : inscription rapide',
          style: GoogleFonts.inter(
            fontSize: 11,
            color: const Color(0xFFD0D4E2),
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        _socialConnectPill(
          context: context,
          leading: _googleGLogo(),
          label: 'S\'inscrire avec Google',
          onTap: () => _authWithGoogle(context),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(child: Divider(color: Colors.white.withOpacity(0.15))),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'OU',
                style: GoogleFonts.inter(
                  fontSize: 10,
                  color: const Color(0xFFA0A0B0),
                  letterSpacing: 3,
                ),
              ),
            ),
            Expanded(child: Divider(color: Colors.white.withOpacity(0.15))),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          'Méthode 2 : formulaire complet',
          style: GoogleFonts.inter(
            fontSize: 11,
            color: const Color(0xFFD0D4E2),
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        _buildInlineEmailSignup(context),
      ],
    );
  }

  Widget _buildInlineEmailSignup(BuildContext context) {
    final inputStyle = GoogleFonts.inter(color: Colors.white, fontSize: 14);
    InputDecoration decoration(String label, {String? hint, bool compact = false}) {
      return InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: GoogleFonts.inter(color: Colors.white54),
        labelStyle: GoogleFonts.inter(color: const Color(0xFFC8CFDF)),
        enabledBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Color(0x99D5DBE8)),
        ),
        focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Color(0xFFFF8F3F)),
        ),
        isDense: compact,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _signupNameController,
          style: inputStyle,
          decoration: decoration('Nom ou entreprise'),
        ),
        TextField(
          controller: _signupEmailController,
          style: inputStyle,
          keyboardType: TextInputType.emailAddress,
          decoration: decoration('Email (connexion)'),
        ),
        TextField(
          controller: _signupPasswordController,
          style: inputStyle,
          obscureText: true,
          decoration: decoration('Mot de passe (min 6 caractères)'),
        ),
        TextField(
          controller: _signupConfirmPasswordController,
          style: inputStyle,
          obscureText: true,
          decoration: decoration('Confirmer le mot de passe'),
        ),
        TextField(
          controller: _signupAddressController,
          style: inputStyle,
          keyboardType: TextInputType.streetAddress,
          maxLines: 2,
          decoration: decoration(
            'Adresse (rue, code postal, ville)',
            hint: 'Ex : 12 rue des Artisans, 1000 Tunis',
          ),
        ),
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton(
            onPressed: _signupSubmitting ? null : () => _submitInlineSignup(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF8F3F),
              foregroundColor: const Color(0xFF151525),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            child:
                _signupSubmitting
                    ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : Text(
                      'Créer le compte',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                    ),
          ),
        ),
      ],
    );
  }

  Future<void> _authWithGoogle(BuildContext context) async {
    try {
      if (kIsWeb) {
        final returnUrl = '${Uri.base.origin}/#/login';
        final uri = Uri.parse(
          '${ApiService.baseUrl}/auth/google/start?returnUrl=${Uri.encodeComponent(returnUrl)}',
        );
        final ok = await launchUrl(
          uri,
          mode: LaunchMode.platformDefault,
          webOnlyWindowName: '_self',
        );
        if (!ok && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Impossible d’ouvrir la page Google.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final googleSignIn = GoogleSignIn.instance;
      if (!_googleInitDone) {
        await googleSignIn.initialize();
        _googleInitDone = true;
      }
      final account = await googleSignIn.authenticate(
        scopeHint: const ['email', 'profile'],
      );
      final auth = account.authentication;
      final idToken = auth.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw Exception('Google ID token indisponible');
      }

      final response = await ApiService.clientGoogleAuth(
        idToken: idToken,
        location: _signupAddressController.text.trim(),
      );
      var role = (response['role'] ?? 'client').toString().toLowerCase();
      if (role == 'super_admin') role = 'superadmin';
      if (role == 'company_admin') role = 'admin';
      final token =
          response['token']?.toString() ??
          response['accessToken']?.toString() ??
          response['access_token']?.toString();
      await ApiService.saveAuth(
        (token != null && token.isNotEmpty) ? token : null,
        role,
      );

      if (widget.returnToHomeAfterClientLogin) {
        if (!context.mounted) return;
        Navigator.pop(context, true);
        return;
      }

      if (role == 'technician') {
        final args = Map<String, dynamic>.from(response);
        await ApiService.clearStoredClientSession();
        await ApiService.saveTechnicianSession(args);
        if (!context.mounted) return;
        Navigator.pushReplacementNamed(
          context,
          '/technician-profile',
          arguments: args,
        );
        return;
      }
      if (role == 'maintenance') {
        await ApiService.clearStoredClientSession();
        if (!context.mounted) return;
        Navigator.pushReplacementNamed(context, '/maintenance-dashboard');
        return;
      }
      if (role == 'conception' || role == 'concepteur') {
        await ApiService.clearStoredClientSession();
        if (!context.mounted) return;
        Navigator.pushReplacementNamed(context, '/concepteur-dashboard');
        return;
      }
      if (role == 'superadmin' || role == 'admin') {
        if (!context.mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const DashboardPage()),
        );
        return;
      }

      final clientName = response['name'] ?? account.displayName ?? 'Client';
      final clientId = response['clientId'] ?? response['id'] ?? '';
      await ApiService.saveClientSession(
        clientId: clientId.toString(),
        clientName: clientName.toString(),
        clientEmail: (response['email'] ?? account.email).toString(),
        clientLocation:
            (response['location'] ?? _signupAddressController.text.trim())
                .toString(),
      );
      if (!context.mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder:
              (context) => ClientDashboardPage(
                clientName: clientName,
                clientId: clientId,
                clientData: response,
              ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Connexion Google impossible: ${e.toString().replaceAll('Exception: ', '')}',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _consumeGoogleOAuthReturn() async {
    if (!kIsWeb) return;
    final qp = _readMergedWebQueryParams();
    if (qp['googleAuth'] == null) return;
    final success = qp['googleAuth'] == '1';
    if (!success) {
      final msg = (qp['error'] ?? 'Connexion Google refusée').trim();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
      });
      return;
    }
    final token = (qp['token'] ?? '').trim();
    var role = (qp['role'] ?? 'client').trim().toLowerCase();
    if (role == 'super_admin') role = 'superadmin';
    if (role == 'company_admin') role = 'admin';
    if (token.isEmpty) return;
    await ApiService.saveAuth(token, role);

    if (!mounted) return;
    if (widget.returnToHomeAfterClientLogin) {
      Navigator.pop(context, true);
      return;
    }

    if (role == 'technician') {
      final profile = ApiService.technicianProfileFromOAuthParams(qp);
      await ApiService.clearStoredClientSession();
      await ApiService.saveTechnicianSession(profile);
      if (!mounted) return;
      Navigator.pushReplacementNamed(
        context,
        '/technician-profile',
        arguments: profile,
      );
      return;
    }
    if (role == 'maintenance') {
      await ApiService.clearStoredClientSession();
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/maintenance-dashboard');
      return;
    }
    if (role == 'conception' || role == 'concepteur') {
      await ApiService.clearStoredClientSession();
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/concepteur-dashboard');
      return;
    }
    if (role == 'superadmin' || role == 'admin') {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const DashboardPage()),
      );
      return;
    }

    await ApiService.saveClientSession(
      clientId: (qp['clientId'] ?? '').trim(),
      clientName: (qp['name'] ?? 'Client').trim(),
      clientEmail: (qp['email'] ?? '').trim(),
      clientLocation: (qp['location'] ?? '').trim(),
      clientPhotoUrl:
          (qp['photoUrl'] ??
                  qp['avatarUrl'] ??
                  qp['profilePhotoUrl'] ??
                  qp['imageUrl'] ??
                  qp['image'] ??
                  '')
              .trim(),
    );
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/client-dashboard');
  }

  Map<String, String> _readMergedWebQueryParams() {
    final params = <String, String>{...Uri.base.queryParameters};
    final frag = Uri.base.fragment;
    if (frag.contains('?')) {
      final fragQuery = frag.split('?').skip(1).join('?');
      params.addAll(Uri.splitQueryString(fragQuery));
    }
    return params;
  }

  Future<void> _submitInlineSignup(BuildContext context) async {
    final name = _signupNameController.text.trim();
    final email = _signupEmailController.text.trim();
    final password = _signupPasswordController.text.trim();
    final confirm = _signupConfirmPasswordController.text.trim();
    final address = _signupAddressController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nom requis')),
      );
      return;
    }
    if (!email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Email valide requis')),
      );
      return;
    }
    if (password.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mot de passe minimum 6 caractères')),
      );
      return;
    }
    if (password != confirm) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Les deux mots de passe ne correspondent pas')),
      );
      return;
    }
    if (address.length < 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Adresse trop courte : indiquez au moins rue et ville.')),
      );
      return;
    }
    setState(() => _signupSubmitting = true);
    try {
      final response = await ApiService.clientSelfRegister({
        'provider': 'email',
        'name': name,
        'email': email,
        'password': password,
        'location': address,
        'address': address,
      });
      if (!context.mounted) return;
      final role = (response['role'] ?? 'client').toString().toLowerCase();
      final token = response['token']?.toString();
      await ApiService.saveAuth(
        (token != null && token.isNotEmpty) ? token : null,
        role,
      );
      if (widget.returnToHomeAfterClientLogin) {
        Navigator.pop(context, true);
        return;
      }
      final clientName = response['name'] ?? name;
      final clientId = response['clientId'] ?? response['id'] ?? '';
      await ApiService.saveClientSession(
        clientId: clientId.toString(),
        clientName: clientName.toString(),
        clientEmail: (response['email'] ?? email).toString(),
        clientLocation: (response['location'] ?? address).toString(),
      );
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder:
              (context) => ClientDashboardPage(
                clientName: clientName,
                clientId: clientId,
                clientData: response,
              ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Création compte impossible: ${e.toString().replaceAll('Exception: ', '')}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _signupSubmitting = false);
    }
  }

  Widget _googleGLogo() {
    return SizedBox(
      width: 22,
      height: 22,
      child: Image.network(
        'https://www.google.com/images/branding/googleg/1x/googleg_standard_color_128dp.png',
        errorBuilder: (_, __, ___) => Text(
          'G',
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF4285F4),
          ),
        ),
      ),
    );
  }

  Future<void> _onSocialLoginTap(BuildContext context, String kind) async {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final passConfirmCtrl = TextEditingController();
    final locationCtrl = TextEditingController();
    final codeCtrl = TextEditingController();

    String dialogTitle() {
      if (kind == 'phone') return 'Créer un compte client (Téléphone)';
      if (kind == 'email') return 'Inscription client — première connexion';
      return 'Créer un compte client (${kind == 'google' ? 'Google' : 'Apple'})';
    }

    var codeSentFlag = false;
    var sendingCodeFlag = false;

    final submit = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF171733),
              title: Text(
                dialogTitle(),
                style: GoogleFonts.inter(color: Colors.white),
              ),
              content: SizedBox(
                width: 460,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (kind == 'email')
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            'Renseignez vos informations, cliquez sur « Envoyer le code », puis saisissez les 6 chiffres reçus par email avant « Créer le compte » (envoi réel : SMTP requis dans .env du serveur).',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: Colors.white.withOpacity(0.75),
                              height: 1.35,
                            ),
                          ),
                        ),
                      TextField(
                        controller: nameCtrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: kind == 'email' ? 'Nom ou entreprise' : 'Nom complet',
                        ),
                      ),
                      TextField(
                        controller: emailCtrl,
                        style: const TextStyle(color: Colors.white),
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          labelText:
                              kind == 'phone'
                                  ? 'Email (optionnel)'
                                  : kind == 'email'
                                      ? 'Email (connexion)'
                                      : 'Email (obligatoire)',
                        ),
                      ),
                      if (kind == 'phone')
                        TextField(
                          controller: phoneCtrl,
                          style: const TextStyle(color: Colors.white),
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'Numero téléphone',
                          ),
                        ),
                      TextField(
                        controller: passCtrl,
                        style: const TextStyle(color: Colors.white),
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Mot de passe (min 6 caractères)',
                        ),
                      ),
                      TextField(
                        controller: passConfirmCtrl,
                        style: const TextStyle(color: Colors.white),
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Confirmer le mot de passe',
                        ),
                      ),
                      TextField(
                        controller: locationCtrl,
                        style: const TextStyle(color: Colors.white),
                        keyboardType: kind == 'email' ? TextInputType.streetAddress : TextInputType.text,
                        maxLines: kind == 'email' ? 2 : 1,
                        decoration: InputDecoration(
                          labelText:
                              kind == 'email'
                                  ? 'Adresse (rue, code postal, ville)'
                                  : 'Localisation (optionnel)',
                          hintText:
                              kind == 'email'
                                  ? 'Ex : 12 rue des Artisans, 1000 Tunis'
                                  : null,
                        ),
                      ),
                      if (kind == 'email') ...[
                        const SizedBox(height: 14),
                        OutlinedButton.icon(
                          onPressed:
                              sendingCodeFlag
                                  ? null
                                  : () async {
                                    final name = nameCtrl.text.trim();
                                    final em = emailCtrl.text.trim();
                                    if (name.isEmpty) {
                                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                                        const SnackBar(content: Text('Indiquez d’abord le nom ou l’entreprise.')),
                                      );
                                      return;
                                    }
                                    if (!em.contains('@')) {
                                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                                        const SnackBar(content: Text('Indiquez un email valide pour recevoir le code.')),
                                      );
                                      return;
                                    }
                                    setModalState(() => sendingCodeFlag = true);
                                    try {
                                      await ApiService.sendClientSignupCode(
                                        email: em,
                                        name: name,
                                      );
                                      codeSentFlag = true;
                                      if (dialogContext.mounted) {
                                        ScaffoldMessenger.of(dialogContext).showSnackBar(
                                          const SnackBar(
                                            content: Text('Code envoyé : vérifiez votre boîte mail (et les spams).'),
                                            backgroundColor: Colors.green,
                                          ),
                                        );
                                      }
                                    } catch (e) {
                                      if (dialogContext.mounted) {
                                        ScaffoldMessenger.of(dialogContext).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              e.toString().replaceAll('Exception: ', ''),
                                            ),
                                            backgroundColor: Colors.red,
                                          ),
                                        );
                                      }
                                    } finally {
                                      if (dialogContext.mounted) {
                                        setModalState(() => sendingCodeFlag = false);
                                      }
                                    }
                                  },
                          icon:
                              sendingCodeFlag
                                  ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFF8F3F)),
                                  )
                                  : const Icon(Icons.mark_email_unread_outlined, color: Color(0xFFFF8F3F)),
                          label: Text(
                            sendingCodeFlag ? 'Envoi en cours…' : 'Envoyer le code par email (6 chiffres)',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Color(0xFFFF8F3F)),
                          ),
                        ),
                        if (codeSentFlag)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              'Code envoyé. Saisissez les 6 chiffres ci-dessous.',
                              style: GoogleFonts.inter(fontSize: 11, color: Colors.greenAccent.shade100),
                            ),
                          ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: codeCtrl,
                          style: const TextStyle(color: Colors.white, letterSpacing: 6, fontSize: 22),
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          textAlign: TextAlign.center,
                          decoration: const InputDecoration(
                            counterText: '',
                            labelText: 'Code à 6 chiffres (email)',
                            hintText: '••••••',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Annuler'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (kind == 'email') {
                      final digits = codeCtrl.text.trim();
                      if (digits.length != 6 || int.tryParse(digits) == null) {
                        ScaffoldMessenger.of(dialogContext).showSnackBar(
                          const SnackBar(
                            content: Text('Saisissez le code à 6 chiffres reçu par email.'),
                            backgroundColor: Colors.orange,
                          ),
                        );
                        return;
                      }
                    }
                    Navigator.pop(dialogContext, true);
                  },
                  child: const Text('Créer le compte'),
                ),
              ],
            );
          },
        );
      },
    );

    if (submit != true) return;

    if (nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nom requis')),
      );
      return;
    }
    if (passCtrl.text.trim().length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mot de passe minimum 6 caractères')),
      );
      return;
    }
    if (passCtrl.text.trim() != passConfirmCtrl.text.trim()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Les deux mots de passe ne correspondent pas')),
      );
      return;
    }
    if (kind != 'phone' && !emailCtrl.text.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Email valide requis')),
      );
      return;
    }
    if (kind == 'email' && locationCtrl.text.trim().length < 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Adresse trop courte : indiquez au moins rue et ville.'),
        ),
      );
      return;
    }
    if (kind == 'email') {
      final digits = codeCtrl.text.trim();
      if (digits.length != 6 || int.tryParse(digits) == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Code à 6 chiffres invalide.')),
        );
        return;
      }
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final response = await ApiService.clientSelfRegister({
        'provider': kind,
        'name': nameCtrl.text.trim(),
        'email': emailCtrl.text.trim(),
        'phone': phoneCtrl.text.trim(),
        'password': passCtrl.text.trim(),
        'location': locationCtrl.text.trim(),
        if (kind == 'email') 'address': locationCtrl.text.trim(),
        if (kind == 'email') 'verificationCode': codeCtrl.text.trim(),
      });
      if (!context.mounted) return;
      Navigator.pop(context);
      final role = (response['role'] ?? 'client').toString().toLowerCase();
      final token = response['token']?.toString();
      await ApiService.saveAuth(
        (token != null && token.isNotEmpty) ? token : null,
        role,
      );
      if (widget.returnToHomeAfterClientLogin) {
        Navigator.pop(context, true);
        return;
      }
      final clientName = response['name'] ?? nameCtrl.text.trim();
      final clientId = response['clientId'] ?? response['id'] ?? '';
      await ApiService.saveClientSession(
        clientId: clientId.toString(),
        clientName: clientName.toString(),
        clientEmail: (response['email'] ?? emailCtrl.text.trim()).toString(),
        clientLocation: (response['location'] ?? locationCtrl.text.trim()).toString(),
      );
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder:
              (context) => ClientDashboardPage(
                clientName: clientName,
                clientId: clientId,
                clientData: response,
              ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Création compte impossible: ${e.toString().replaceAll('Exception: ', '')}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _socialConnectPill({
    required BuildContext context,
    required Widget leading,
    required String label,
    required VoidCallback onTap,
    bool twoLines = false,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            horizontal: 18,
            vertical: twoLines ? 12 : 14,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0xFFE0E0E0)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              leading,
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    height: twoLines ? 1.25 : 1.2,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF1a1a1a),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    required IconData icon,
    required String hintText,
    bool isPassword = false,
    Widget? rightAction,
    TextEditingController? controller,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: const Color(0xFFA0A0B0).withOpacity(0.8),
                letterSpacing: 2.0,
              ),
            ),
            if (rightAction != null) rightAction,
          ],
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          obscureText: isPassword && _obscurePassword,
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w300,
            color: const Color(0xFFF4F4F9),
          ),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: TextStyle(
              color: const Color(0xFFA0A0B0).withOpacity(0.2),
            ),
            prefixIcon: Icon(
              icon,
              color: const Color(0xFFA0A0B0).withOpacity(0.4),
            ),
            suffixIcon: isPassword
                ? IconButton(
                    icon: Icon(
                      _obscurePassword ? Icons.visibility_off : Icons.visibility,
                      color: const Color(0xFFA0A0B0).withOpacity(0.4),
                    ),
                    onPressed: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                  )
                : null,
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: const Color(0xFF2E2E3E).withOpacity(0.3)),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFFFF6E00)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFooterLink(String text) {
    return InkWell(
      onTap: () {},
      child: Text(
        text,
        style: GoogleFonts.inter(
          fontSize: 9,
          fontWeight: FontWeight.w600,
          color: const Color(0xFFA0A0B0).withOpacity(0.6),
          letterSpacing: 2.0,
        ),
      ),
    );
  }
}
