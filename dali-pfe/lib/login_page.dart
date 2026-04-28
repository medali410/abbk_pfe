import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dashboard_page.dart';
import 'client_dashboard_page.dart';
import 'services/api_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, this.returnToHomeAfterClientLogin = false});

  final bool returnToHomeAfterClientLogin;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _obscurePassword = true;
  bool _rememberMe = false;
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

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
                      // Status (Hidden on mobile)
                      if (isDesktop)
                        Row(
                          children: [
                            Text(
                              'STATUT DU SYSTÈME : OPÉRATIONNEL',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                color: const Color(0xFFA0A0B0),
                                fontWeight: FontWeight.w500,
                                letterSpacing: 2.0,
                              ),
                            ),
                            const SizedBox(width: 16),
                            // Blinking dot simulation
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Colors.green,
                                shape: BoxShape.circle,
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
                                    'CONNEXION',
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
                                  const SizedBox(height: 16),
                                  Text(
                                    'Super admin / équipe : identifiants internes. Client : connexion avec email / mot de passe, ou première inscription via « Inscription client » ou les boutons ci-dessous.',
                                    style: GoogleFonts.inter(
                                      fontSize: 10,
                                      color: const Color(0xFFA0A0B0),
                                      fontWeight: FontWeight.w500,
                                      letterSpacing: 1.2,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 28),

                                  _buildClientSocialSection(context),

                                  const SizedBox(height: 28),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Divider(color: Colors.white.withOpacity(0.15)),
                                      ),
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
                                      Expanded(
                                        child: Divider(color: Colors.white.withOpacity(0.15)),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 28),

                                  // Email Input
                                  _buildTextField(
                                    label: 'EMAIL PROFESSIONNEL',
                                    icon: Icons.alternate_email,
                                    hintText: 'utilisateur@entreprise.fr',
                                    controller: _emailController,
                                  ),
                                  const SizedBox(height: 32),

                                  // Password Input
                                  _buildTextField(
                                    label: 'MOT DE PASSE',
                                    icon: Icons.lock_open,
                                    hintText: '••••••••••••',
                                    isPassword: true,
                                    controller: _passwordController,
                                    rightAction: TextButton(
                                      onPressed: () {},
                                      child: Text(
                                        'OUBLIÉ ?',
                                        style: GoogleFonts.inter(
                                          fontSize: 9,
                                          letterSpacing: 2.0,
                                          color: const Color(0xFFA0A0B0),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 32),

                                  // Submit Button
                                  Container(
                                    width: double.infinity,
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [Color(0xFFFF6E00), Color(0xFFFF8F3F)],
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xFFFF6E00).withOpacity(0.4),
                                          blurRadius: 24,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(8),
                                          onTap: () async {
                                            final email = _emailController.text.trim();
                                            final password = _passwordController.text.trim();

                                            if (email.isEmpty || password.isEmpty) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(content: Text('Veuillez remplir tous les champs')),
                                              );
                                              return;
                                            }

                                            // Show loading indicator
                                            showDialog(
                                              context: context,
                                              barrierDismissible: false,
                                              builder: (context) => const Center(child: CircularProgressIndicator()),
                                            );

                                            try {
                                              final response = await ApiService.login(email, password);
                                              Navigator.pop(context); // Close loading

                                              var role = (response['role'] ?? 'client').toString().toLowerCase();
                                              if (role == 'super_admin') role = 'superadmin';
                                              if (role == 'company_admin') role = 'admin';
                                              final token = response['token']?.toString() ??
                                                  response['accessToken']?.toString() ??
                                                  response['access_token']?.toString();
                                              await ApiService.saveAuth(
                                                (token != null && token.isNotEmpty) ? token : null,
                                                role,
                                              );

                                              final isFleetDashboard =
                                                  role == 'superadmin' || role == 'admin' || role == 'company_admin';
                                              if (isFleetDashboard) {
                                                if ((ApiService.authToken ?? '').isEmpty) {
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    const SnackBar(
                                                      content: Text(
                                                        'Réponse serveur sans jeton de session. Vérifiez l’URL de l’API et reconnectez-vous.',
                                                      ),
                                                      backgroundColor: Colors.red,
                                                    ),
                                                  );
                                                  return;
                                                }
                                                Navigator.pushReplacement(
                                                  context,
                                                  MaterialPageRoute(builder: (context) => const DashboardPage()),
                                                );
                                              } else if (role == 'conception' || role == 'concepteur') {
                                                final args = Map<String, dynamic>.from(response);
                                                args['id'] = response['conceptionId'] ?? response['id'] ?? '';
                                                args['specialization'] =
                                                    (response['specialization'] ?? 'Conception').toString();
                                                args['status'] = (response['status'] ?? 'Actif').toString();
                                                args['phone'] = (response['phone'] ?? '').toString();
                                                args['companyId'] = (response['companyId'] ?? '').toString();
                                                args['location'] = (response['location'] ?? '').toString();
                                                args['email'] = email;
                                                args['username'] = (response['username'] ?? '').toString();
                                                args['loginPassword'] = '*' * password.length;
                                                args['imageUrl'] = (response['imageUrl'] ?? '').toString();
                                                args['viewerRole'] = 'conception';
                                                if ((ApiService.authToken ?? '').isEmpty) {
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    const SnackBar(
                                                      content: Text(
                                                        'Réponse serveur sans jeton de session. Vérifiez l’URL de l’API et reconnectez-vous.',
                                                      ),
                                                      backgroundColor: Colors.red,
                                                    ),
                                                  );
                                                  return;
                                                }
                                                // Redirect to the new Concepteur Dashboard
                                                Navigator.pushReplacementNamed(
                                                  context,
                                                  '/concepteur-dashboard',
                                                );
                                              } else if (role == 'technician') {
                                                final args = Map<String, dynamic>.from(response);
                                                args['id'] = response['technicianId'] ?? response['id'] ?? '';
                                                args['specialization'] =
                                                    (response['specialization'] ?? 'Technicien').toString();
                                                args['status'] = (response['status'] ?? 'Disponible').toString();
                                                args['phone'] = (response['phone'] ?? '').toString();
                                                args['location'] = (response['companyId'] ?? '').toString();
                                                args['email'] = email;
                                                args['loginPassword'] = '*' * password.length;
                                                args['imageUrl'] = (response['imageUrl'] ?? '').toString();
                                                args['viewerRole'] = role;
                                                Navigator.pushReplacementNamed(
                                                  context,
                                                  '/technician-profile',
                                                  arguments: args,
                                                );
                                              } else if (role == 'maintenance') {
                                                Navigator.pushReplacementNamed(
                                                  context,
                                                  '/maintenance-dashboard',
                                                );
                                              } else {
                                                final clientName = response['name'] ?? 'Enterprise Corp';
                                                final clientId = response['clientId'] ?? response['id'] ?? '';
                                                await ApiService.saveClientSession(
                                                  clientId: clientId.toString(),
                                                  clientName: clientName.toString(),
                                                  clientEmail: (response['email'] ?? email).toString(),
                                                  clientLocation: (response['location'] ?? '').toString(),
                                                );
                                                if (widget.returnToHomeAfterClientLogin) {
                                                  Navigator.pop(context, true);
                                                  return;
                                                }
                                                Navigator.pushReplacement(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (context) => ClientDashboardPage(
                                                      clientName: clientName,
                                                      clientId: clientId,
                                                      clientData: response,
                                                    ),
                                                  ),
                                                );
                                              }
                                            } catch (e) {
                                              Navigator.pop(context); // Close loading

                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(
                                                  content: Text('Erreur: ${e.toString().replaceAll('Exception: ', '')}'),
                                                  backgroundColor: Colors.red,
                                                ),
                                              );
                                            }
                                          },
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 20),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Text(
                                                'ACCÉDER AU DASHBOARD',
                                                style: GoogleFonts.inter(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.white,
                                                  letterSpacing: 3.0,
                                                ),
                                              ),
                                              const SizedBox(width: 16),
                                              const Icon(Icons.arrow_right_alt, color: Colors.white),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 24),

                                  // Remember Me
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      InkWell(
                                        onTap: () {
                                          setState(() {
                                            _rememberMe = !_rememberMe;
                                          });
                                        },
                                        borderRadius: BorderRadius.circular(20),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withOpacity(0.05),
                                            borderRadius: BorderRadius.circular(20),
                                            border: Border.all(color: Colors.white.withOpacity(0.05)),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                _rememberMe ? Icons.check_box : Icons.check_box_outline_blank,
                                                size: 14,
                                                color: _rememberMe ? const Color(0xFFFF6E00) : const Color(0xFF4A4A5A),
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                'RESTER CONNECTÉ',
                                                style: GoogleFonts.inter(
                                                  fontSize: 9,
                                                  color: const Color(0xFFA0A0B0),
                                                  fontWeight: FontWeight.w500,
                                                  letterSpacing: 2.0,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  TextButton.icon(
                                    onPressed: () {
                                      Navigator.pushReplacementNamed(
                                        context,
                                        '/maintenance-login',
                                      );
                                    },
                                    icon: const Icon(Icons.engineering_rounded, size: 16),
                                    label: Text(
                                      'ACCÈS MAINTENANCE',
                                      style: GoogleFonts.inter(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 1.1,
                                      ),
                                    ),
                                  ),

                                  const SizedBox(height: 48),

                                  // Trust Badges
                                  Opacity(
                                    opacity: 0.5,
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        _buildTrustBadge(Icons.verified_user_outlined, 'SSL 256-BIT'),
                                        const SizedBox(width: 32),
                                        _buildTrustBadge(Icons.security_outlined, 'ISO 27001'),
                                        const SizedBox(width: 32),
                                        _buildTrustBadge(Icons.gpp_maybe_outlined, 'GDPR READY'),
                                      ],
                                    ),
                                  )
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

  /// Boutons type « Continuer avec Google / Apple / téléphone » (OAuth à brancher : Firebase, backend).
  Widget _buildClientSocialSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'CLIENT — CONNEXION RAPIDE',
          style: GoogleFonts.inter(
            fontSize: 10,
            color: const Color(0xFFA0A0B0),
            fontWeight: FontWeight.w600,
            letterSpacing: 2.4,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        _socialConnectPill(
          context: context,
          leading: _googleGLogo(),
          label: 'Continuer avec Google',
          onTap: () => _onSocialLoginTap(context, 'google'),
        ),
        const SizedBox(height: 12),
        _socialConnectPill(
          context: context,
          leading: const Icon(Icons.tablet_mac, color: Color(0xFF000000), size: 22),
          label: 'Continuer avec Apple',
          onTap: () => _onSocialLoginTap(context, 'apple'),
        ),
        const SizedBox(height: 12),
        _socialConnectPill(
          context: context,
          leading: const Icon(Icons.phone_outlined, color: Color(0xFF1a1a1a), size: 22),
          label: 'Continuer avec un numéro de téléphone',
          twoLines: true,
          onTap: () => _onSocialLoginTap(context, 'phone'),
        ),
        const SizedBox(height: 16),
        TextButton.icon(
          onPressed: () => _onSocialLoginTap(context, 'email'),
          icon: const Icon(Icons.person_add_alt_1, color: Color(0xFFFF8F3F), size: 18),
          label: Text(
            'Inscription client — première connexion (email & adresse)',
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: const Color(0xFFFF8F3F),
              letterSpacing: 0.3,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
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

  Widget _buildTrustBadge(IconData icon, String text) {
    return Column(
      children: [
        Icon(icon, color: const Color(0xFFF4F4F9), size: 20),
        const SizedBox(height: 4),
        Text(
          text,
          style: GoogleFonts.inter(
            fontSize: 8,
            fontWeight: FontWeight.bold,
            color: const Color(0xFFF4F4F9),
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
