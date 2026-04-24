import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dashboard_page.dart';
import 'client_dashboard_page.dart';
import 'services/api_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

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
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0xFFFF6E00), Color(0xFFFF8F3F)],
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Icon(Icons.analytics_outlined, color: Colors.white, size: 20), // query_stats approx
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'PREDICTIVE CLOUD',
                            style: GoogleFonts.inter(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.8,
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
                                    'Super admin / équipe : vos identifiants internes. Client : email et mot de passe fournis par l\'administrateur.',
                                    style: GoogleFonts.inter(
                                      fontSize: 10,
                                      color: const Color(0xFFA0A0B0),
                                      fontWeight: FontWeight.w500,
                                      letterSpacing: 1.2,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 48),

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
                                                // Observatory = même UI que la maquette Tailwind « Predictive IoT - Détail Machine »
                                                Navigator.pushReplacementNamed(
                                                  context,
                                                  '/conception-observatory',
                                                  arguments: args,
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
