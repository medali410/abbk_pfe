import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'services/api_service.dart';
import 'services/theme_service.dart';

String _pickMaintenanceAgentPhotoRaw(Map<String, dynamic> agent) {
  const keys = <String>[
    'imageUrl',
    'photoUrl',
    'avatarUrl',
    'profilePhotoUrl',
    'picture',
    'photoURL',
    'photo',
    'avatar',
    'image',
  ];
  for (final k in keys) {
    final s = agent[k]?.toString().trim() ?? '';
    if (s.isNotEmpty) return s;
  }
  return '';
}

bool _maintenanceAvatarHostMatchesApi(String absoluteUrl) {
  try {
    final u = Uri.parse(absoluteUrl);
    final b = Uri.parse(ApiService.baseUrl);
    return u.hasScheme && b.hasScheme && u.host.toLowerCase() == b.host.toLowerCase();
  } catch (_) {
    return false;
  }
}

String _normalizeMaintenanceImageUrl(String rawValue) {
  final value = rawValue.trim();
  if (value.isEmpty) return '';
  if (value.startsWith('data:image/')) return value;
  final parsed = Uri.tryParse(value);
  if (parsed != null && parsed.hasScheme) return value;
  if (value.startsWith('//')) {
    final apiScheme = Uri.tryParse(ApiService.baseUrl)?.scheme ?? 'http';
    return '$apiScheme:$value';
  }
  final origin = ApiService.socketBaseUrl.replaceAll(RegExp(r'/$'), '');
  if (value.startsWith('/')) return '$origin$value';
  return '$origin/${value.replaceFirst(RegExp(r'^/+'), '')}';
}

/// Profil de l’agent maintenance connecté (données `/maintenance/workspace`).
class MaintenanceProfilePage extends StatefulWidget {
  const MaintenanceProfilePage({super.key});

  @override
  State<MaintenanceProfilePage> createState() => _MaintenanceProfilePageState();
}

class _MaintenanceProfilePageState extends State<MaintenanceProfilePage> {
  late Future<Map<String, dynamic>> _future;

  bool get _isDark => ThemeService().isDarkMode;
  Color get _bg => _isDark ? const Color(0xFF10102B) : const Color(0xFFF4F6F8);
  Color get _text => _isDark ? const Color(0xFFE2DFFF) : const Color(0xFF1E1E2D);
  Color get _muted => _isDark ? const Color(0xFFE2BFB0) : const Color(0xFF7A7A8C);
  static const _accent = Color(0xFFFF6E00);

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    ThemeService().addListener(_onThemeChanged);
    _future = ApiService.getMaintenanceWorkspace();
  }

  @override
  void dispose() {
    ThemeService().removeListener(_onThemeChanged);
    super.dispose();
  }

  void _reload() => setState(() {
    _future = ApiService.getMaintenanceWorkspace();
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: Text(
          'Profil',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
        backgroundColor: _bg,
        foregroundColor: _text,
        actions: [
          IconButton(
            onPressed: _reload,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            onPressed: () => ThemeService().toggleTheme(),
            icon: Icon(
              ThemeService().isDarkMode ? Icons.wb_sunny_rounded : Icons.nightlight_round,
              color: ThemeService().isDarkMode ? Colors.amber : const Color(0xFF7A4B29),
            ),
            tooltip: ThemeService().isDarkMode ? 'Mode Jour' : 'Mode Nuit',
          ),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(color: _accent),
            );
          }
          if (snap.hasError) {
            final err = '${snap.error}';
            final looksLikeAuth =
                err.toLowerCase().contains('session') ||
                err.toLowerCase().contains('reconnectez') ||
                err.toLowerCase().contains('authentification');
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      err,
                      style: GoogleFonts.inter(color: _muted),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 14),
                    if (looksLikeAuth)
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).pushReplacementNamed(
                            '/maintenance-login',
                          );
                        },
                        child: Text(
                          'Connexion maintenance',
                          style: GoogleFonts.inter(
                            color: _accent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    TextButton(
                      onPressed: _reload,
                      child: const Text('Réessayer'),
                    ),
                  ],
                ),
              ),
            );
          }
          final data = snap.data ?? {};
          return MaintenanceProfileContent(
            data: data,
            onWorkspaceReload: _reload,
          );
        },
      ),
    );
  }
}

/// Contenu profil (réutilisable dans le shell [MaintenanceDashboardPage]).
class MaintenanceProfileContent extends StatelessWidget {
  const MaintenanceProfileContent({
    super.key,
    required this.data,
    this.onWorkspaceReload,
  });

  final Map<String, dynamic> data;
  final VoidCallback? onWorkspaceReload;

  @override
  Widget build(BuildContext context) {
    final isDark = ThemeService().isDarkMode;
    final surface = isDark ? const Color(0xFF1D1D38) : Colors.white;
    final surfaceHighlight = isDark ? const Color(0xFF272743) : const Color(0xFFF1F5F9);
    final text = isDark ? const Color(0xFFE2DFFF) : const Color(0xFF1E1E2D);
    final muted = isDark ? const Color(0xFFE2BFB0) : const Color(0xFF7A7A8C);
    const accent = Color(0xFFFF6E00);

    // Support both nested 'agent' object (legacy) and flat structure (SQL backend)
    final Map<String, dynamic> agent = data.containsKey('agent')
        ? (data['agent'] as Map).cast<String, dynamic>()
        : data;

    final String name = agent['name']?.toString().trim().isNotEmpty == true
        ? agent['name'].toString().trim()
        : agent['fullName']?.toString().trim().isNotEmpty == true
            ? agent['fullName'].toString().trim()
            : 'Agent de Maintenance';

    final String email = agent['email']?.toString().trim().isNotEmpty == true
        ? agent['email'].toString().trim()
        : '—';

    final int machineCount = (data['machines'] as List? ?? const []).length;
    final int requestCount = (data['recentPurchaseRequests'] as List? ?? const []).length;
    String v(dynamic x) => (x ?? '').toString().trim();

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      children: [
        // --- 1. PREMIUM HEADER BANNER CARD ---
        Container(
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white10),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 15,
                offset: const Offset(0, 8),
              )
            ],
          ),
          child: Column(
            children: [
              // Top Cover Banner Gradient
              Container(
                height: 120,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF31102B), Color(0xFFFF6E00)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                ),
              ),
              // Overlapping Avatar and Info
              Transform.translate(
                offset: const Offset(0, -50),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      // Large Circular Avatar
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: surface, width: 4),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 12,
                              spreadRadius: 2,
                            )
                          ],
                        ),
                        child: _MaintenanceProfileAvatar(
                          agent: agent,
                          radius: 48,
                          accent: accent,
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Agent Name
                      Text(
                        name,
                        style: GoogleFonts.spaceGrotesk(
                          color: text,
                          fontWeight: FontWeight.bold,
                          fontSize: 24,
                          letterSpacing: 0.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      // Email
                      Text(
                        email,
                        style: GoogleFonts.inter(
                          color: muted,
                          fontSize: 14,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 14),
                      // Role Badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: accent.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: accent.withOpacity(0.3)),
                        ),
                        child: Text(
                          'AGENT DE MAINTENANCE',
                          style: GoogleFonts.spaceGrotesk(
                            color: accent,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Quick Edit Profile Button
                      OutlinedButton.icon(
                        onPressed: () => _openMaintenanceProfileEditor(
                          context,
                          workspaceData: data,
                          onSaved: onWorkspaceReload,
                        ),
                        icon: const Icon(Icons.edit_outlined, size: 14),
                        label: Text(
                          'Modifier le profil',
                          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: accent,
                          side: const BorderSide(color: accent),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // --- 2. STATS ROW GRID ---
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                title: 'Machines suivies',
                value: '$machineCount',
                icon: Icons.precision_manufacturing_outlined,
                color: accent,
                surface: surface,
                muted: muted,
                text: text,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildStatCard(
                title: 'Demandes d\'achat',
                value: '$requestCount',
                icon: Icons.shopping_cart_outlined,
                color: const Color(0xFF75D1FF),
                surface: surface,
                muted: muted,
                text: text,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // --- 3. PROFESSIONAL PROFILE FIELDS SECTION ---
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.06)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Informations Professionnelles',
                style: GoogleFonts.spaceGrotesk(
                  color: text,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 16),
              const Divider(color: Colors.white12, height: 1),
              const SizedBox(height: 16),
              _maintenanceProfileInfoTile(surfaceHighlight, text, muted, Icons.badge_outlined, 'Identifiant agent', v(agent['maintenanceAgentId'])),
              _maintenanceProfileInfoTile(surfaceHighlight, text, muted, Icons.corporate_fare, 'Client / société', v(agent['clientId'])),
              _maintenanceProfileInfoTile(
                surfaceHighlight,
                text,
                muted,
                Icons.home_work_outlined,
                'Adresse de rattachement',
                v(agent['address']).isEmpty ? '—' : v(agent['address']),
              ),
              _maintenanceProfileInfoTile(
                surfaceHighlight,
                text,
                muted,
                Icons.place_outlined,
                'Lieu / site d’intervention principal',
                v(agent['location']).isEmpty ? '—' : v(agent['location']),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // --- 4. ACTION BUTTONS ---
        SizedBox(
          width: double.infinity,
          height: 54,
          child: FilledButton.icon(
            onPressed: () => _openMaintenanceProfileEditor(
              context,
              workspaceData: data,
              onSaved: onWorkspaceReload,
            ),
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: Colors.white,
              elevation: 2,
              shadowColor: accent.withOpacity(0.4),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            icon: const Icon(Icons.edit_outlined, size: 20),
            label: Text(
              'Modifier le profil',
              style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required Color surface,
    required Color muted,
    required Color text,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              Text(
                value,
                style: GoogleFonts.spaceGrotesk(
                  color: text,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: GoogleFonts.inter(
              color: muted,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

bool _isValidMaintenancePhotoField(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return true;
  if (s.startsWith('data:image/')) return s.length <= 2400000;
  if (s.startsWith('/uploads/')) return true;
  final u = Uri.tryParse(s);
  return u != null &&
      (u.scheme == 'http' || u.scheme == 'https') &&
      u.host.isNotEmpty;
}

Future<void> _openMaintenanceProfileEditor(
  BuildContext context, {
  required Map<String, dynamic> workspaceData,
  VoidCallback? onSaved,
}) async {
  final agent = (workspaceData['agent'] as Map?)?.cast<String, dynamic>() ?? {};
  final photoCtrl = TextEditingController(text: _pickMaintenanceAgentPhotoRaw(agent));
  final firstCtrl = TextEditingController(text: (agent['firstName'] ?? '').toString());
  final lastCtrl = TextEditingController(text: (agent['lastName'] ?? '').toString());
  final emailCtrl = TextEditingController(text: (agent['email'] ?? '').toString());
  final addressCtrl = TextEditingController(text: (agent['address'] ?? '').toString());
  final locationCtrl = TextEditingController(text: (agent['location'] ?? '').toString());
  final passwordCtrl = TextEditingController();
  var obscurePwd = true;
  var isUploading = false;

  Future<void> pickPhoto(StateSetter setLocal) async {
    setLocal(() => isUploading = true);
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.image,
        withData: true,
        allowMultiple: false,
      );
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        final bytes = file.bytes;
        if (bytes != null) {
          final base64Data = base64Encode(bytes);
          final ext = (file.extension ?? 'png').toLowerCase();
          final mime = ext == 'jpg' || ext == 'jpeg' ? 'image/jpeg' : 'image/png';
          
          final uploadedUrl = await ApiService.uploadFile(
            base64Data: 'data:$mime;base64,$base64Data',
            filename: file.name,
          );
          if (uploadedUrl != null && uploadedUrl.isNotEmpty) {
            photoCtrl.text = uploadedUrl;
          } else {
            photoCtrl.text = 'data:$mime;base64,$base64Data';
          }
        }
      }
    } catch (e) {
      debugPrint('Error picking file: $e');
    } finally {
      setLocal(() => isUploading = false);
    }
  }

  try {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            final previewUrl = photoCtrl.text.trim();
            final isDarkMode = ThemeService().isDarkMode;
            final dialogBg = isDarkMode ? const Color(0xFF1D1D38) : Colors.white;
            final dialogBorder = isDarkMode ? Colors.white10 : Colors.black12;
            final dialogText = isDarkMode ? Colors.white : const Color(0xFF1E1E2D);
            final inputStyle = TextStyle(color: isDarkMode ? Colors.white : const Color(0xFF1E1E2D));

            return AlertDialog(
              backgroundColor: dialogBg,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: dialogBorder)),
              title: Row(
                children: [
                  const Icon(Icons.edit_outlined, color: Color(0xFFFF6E00)),
                  const SizedBox(width: 8),
                  Text(
                    'Modifier le profil',
                    style: GoogleFonts.inter(color: dialogText, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: 420,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Circular Avatar Preview
                      Center(
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              width: 100,
                              height: 100,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: const Color(0xFFFF6E00), width: 2),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.3),
                                    blurRadius: 10,
                                    spreadRadius: 2,
                                  )
                                ],
                              ),
                              child: _MaintenanceProfileAvatar(
                                agent: {'imageUrl': previewUrl.isNotEmpty ? previewUrl : _pickMaintenanceAgentPhotoRaw(agent)},
                                radius: 48,
                                accent: const Color(0xFFFF6E00),
                              ),
                            ),
                            if (isUploading)
                              Container(
                                width: 100,
                                height: 100,
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(50),
                                ),
                                child: const Center(
                                  child: CircularProgressIndicator(color: Color(0xFFFF6E00)),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Image Picker Button
                      OutlinedButton.icon(
                        onPressed: isUploading
                            ? null
                            : () async {
                                await pickPhoto(setLocal);
                                setLocal(() {});
                              },
                        icon: const Icon(Icons.photo_camera_outlined, size: 18),
                        label: Text('Importer une photo', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFFF6E00),
                          side: const BorderSide(color: Color(0xFFFF6E00)),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(height: 24),
                      TextField(
                        controller: photoCtrl,
                        style: inputStyle,
                        onChanged: (_) => setLocal(() {}),
                        decoration: _maintenanceDialogFieldDeco('Ou URL de la photo (Optionnel)'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: firstCtrl,
                        style: inputStyle,
                        decoration: _maintenanceDialogFieldDeco('Prénom'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: lastCtrl,
                        style: inputStyle,
                        decoration: _maintenanceDialogFieldDeco('Nom'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: emailCtrl,
                        style: inputStyle,
                        keyboardType: TextInputType.emailAddress,
                        decoration: _maintenanceDialogFieldDeco('Email'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: addressCtrl,
                        style: inputStyle,
                        maxLines: 2,
                        decoration: _maintenanceDialogFieldDeco('Adresse'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: locationCtrl,
                        style: inputStyle,
                        decoration: _maintenanceDialogFieldDeco('Lieu / site d’intervention'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: passwordCtrl,
                        obscureText: obscurePwd,
                        style: inputStyle,
                        decoration: _maintenanceDialogFieldDeco('Nouveau mot de passe (optionnel)').copyWith(
                          suffixIcon: IconButton(
                            icon: Icon(obscurePwd ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: isDarkMode ? Colors.white54 : Colors.black45),
                            onPressed: () => setLocal(() => obscurePwd = !obscurePwd),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text('Annuler', style: GoogleFonts.inter(color: isDarkMode ? const Color(0xFFE2BFB0) : const Color(0xFF7A7A8C))),
                ),
                FilledButton(
                  onPressed: isUploading ? null : () => Navigator.pop(ctx, true),
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFF6E00)),
                  child: const Text('Enregistrer'),
                ),
              ],
            );
          },
        );
      },
    );

    if (ok != true || !context.mounted) return;

    final firstName = firstCtrl.text.trim();
    final lastName = lastCtrl.text.trim();
    final email = emailCtrl.text.trim().toLowerCase();
    final photo = photoCtrl.text.trim();

    if (firstName.isEmpty || lastName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Prénom et nom sont obligatoires.'), backgroundColor: Colors.redAccent),
      );
      return;
    }
    if (email.isEmpty || !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Email invalide.'), backgroundColor: Colors.redAccent),
      );
      return;
    }
    if (!_isValidMaintenancePhotoField(photo)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Photo invalide : URL https ou image importée uniquement.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    final pw = passwordCtrl.text;
    if (pw.isNotEmpty && pw.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mot de passe : 6 caractères minimum.'), backgroundColor: Colors.redAccent),
      );
      return;
    }

    final body = <String, dynamic>{
      'firstName': firstName,
      'lastName': lastName,
      'email': email,
      'address': addressCtrl.text.trim(),
      'location': locationCtrl.text.trim(),
      'imageUrl': photo,
    };
    if (pw.isNotEmpty) body['password'] = pw;

    try {
      await ApiService.updateMyMaintenanceProfile(body);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profil mis à jour.'), backgroundColor: Colors.green),
      );
      onSaved?.call();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  } finally {
    photoCtrl.dispose();
    firstCtrl.dispose();
    lastCtrl.dispose();
    emailCtrl.dispose();
    addressCtrl.dispose();
    locationCtrl.dispose();
    passwordCtrl.dispose();
  }
}

InputDecoration _maintenanceDialogFieldDeco(String label) {
  final isDarkMode = ThemeService().isDarkMode;
  return InputDecoration(
    labelText: label,
    labelStyle: GoogleFonts.inter(color: isDarkMode ? const Color(0xFFE2BFB0) : const Color(0xFF7A7A8C)),
    filled: true,
    fillColor: isDarkMode ? const Color(0xFF10102B) : const Color(0xFFF1F5F9),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
  );
}

/// Avatar : photo depuis une URL (champs agent) ou icône maintenance par défaut.
class _MaintenanceProfileAvatar extends StatelessWidget {
  const _MaintenanceProfileAvatar({
    required this.agent,
    required this.radius,
    required this.accent,
  });

  final Map<String, dynamic> agent;
  final double radius;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final raw = _pickMaintenanceAgentPhotoRaw(agent);
    final size = radius * 2;

    Widget fallback() {
      return CircleAvatar(
        radius: radius,
        backgroundColor: accent.withOpacity(0.2),
        child: Icon(Icons.engineering_rounded, color: accent, size: radius * 1.05),
      );
    }

    if (raw.isEmpty) return fallback();

    if (raw.startsWith('asset:')) {
      final path = raw.substring('asset:'.length);
      return CircleAvatar(
        radius: radius,
        backgroundColor: accent.withOpacity(0.15),
        child: ClipOval(
          child: Image.asset(
            path,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Icon(Icons.engineering_rounded, color: accent, size: radius * 1.05),
          ),
        ),
      );
    }

    final normalized = _normalizeMaintenanceImageUrl(raw);
    if (normalized.isEmpty) return fallback();

    if (normalized.startsWith('data:image/')) {
      try {
        final bytes = base64Decode(normalized.split(',').last);
        return CircleAvatar(
          radius: radius,
          backgroundColor: accent.withOpacity(0.15),
          child: ClipOval(
            child: Image.memory(
              bytes,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => fallback(),
            ),
          ),
        );
      } catch (_) {
        return fallback();
      }
    }

    final headers =
        _maintenanceAvatarHostMatchesApi(normalized) ? ApiService.bearerHeadersForNetworkImage() : null;

    return CircleAvatar(
      radius: radius,
      backgroundColor: accent.withOpacity(0.15),
      child: ClipOval(
        child: Image.network(
          normalized,
          key: ValueKey<String>(normalized),
          width: size,
          height: size,
          fit: BoxFit.cover,
          headers: headers,
          errorBuilder: (_, __, ___) => fallback(),
        ),
      ),
    );
  }
}

Widget _maintenanceProfileInfoTile(
  Color surface,
  Color text,
  Color muted,
  IconData icon,
  String label,
  String value,
) {
  return Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: ThemeService().isDarkMode ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.06)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: const Color(0xFFFF6E00), size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.inter(color: muted, fontSize: 11, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              SelectableText(value, style: GoogleFonts.inter(color: text, fontSize: 14)),
            ],
          ),
        ),
      ],
    ),
  );
}
