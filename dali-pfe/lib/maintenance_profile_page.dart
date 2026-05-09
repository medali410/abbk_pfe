import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'services/api_service.dart';

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

  @override
  void initState() {
    super.initState();
    _future = ApiService.getMaintenanceWorkspace();
  }

  void _reload() => setState(() {
    _future = ApiService.getMaintenanceWorkspace();
  });

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF10102B);
    const text = Color(0xFFE2DFFF);
    const muted = Color(0xFFE2BFB0);
    const accent = Color(0xFFFF6E00);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: Text(
          'Profil',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
        backgroundColor: bg,
        foregroundColor: text,
        actions: [
          IconButton(
            onPressed: _reload,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: accent),
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
                      style: GoogleFonts.inter(color: muted),
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
                            color: accent,
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
    const surface = Color(0xFF1D1D38);
    const text = Color(0xFFE2DFFF);
    const muted = Color(0xFFE2BFB0);
    const accent = Color(0xFFFF6E00);
    final agent = (data['agent'] as Map?)?.cast<String, dynamic>() ?? {};
    final machineCount = (data['machines'] as List? ?? const []).length;
    String v(dynamic x) => (x ?? '').toString().trim();

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.06)),
          ),
          child: Row(
            children: [
              _MaintenanceProfileAvatar(agent: agent, radius: 28, accent: accent),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      v(agent['fullName']).isEmpty ? 'Agent maintenance' : v(agent['fullName']),
                      style: GoogleFonts.inter(color: text, fontWeight: FontWeight.w700, fontSize: 18),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      v(agent['email']).isEmpty ? '—' : v(agent['email']),
                      style: GoogleFonts.inter(color: muted, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => _openMaintenanceProfileEditor(
              context,
              workspaceData: data,
              onSaved: onWorkspaceReload,
            ),
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.edit_outlined, size: 20),
            label: Text(
              'Modifier le profil',
              style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 15),
            ),
          ),
        ),
        const SizedBox(height: 14),
        _maintenanceProfileInfoTile(surface, text, muted, Icons.badge_outlined, 'Identifiant agent', v(agent['maintenanceAgentId'])),
        _maintenanceProfileInfoTile(surface, text, muted, Icons.corporate_fare, 'Client / société', v(agent['clientId'])),
        _maintenanceProfileInfoTile(
          surface,
          text,
          muted,
          Icons.precision_manufacturing_outlined,
          'Machines suivies',
          '$machineCount',
        ),
        _maintenanceProfileInfoTile(
          surface,
          text,
          muted,
          Icons.home_work_outlined,
          'Adresse',
          v(agent['address']).isEmpty ? '—' : v(agent['address']),
        ),
        _maintenanceProfileInfoTile(
          surface,
          text,
          muted,
          Icons.place_outlined,
          'Lieu / site d’intervention',
          v(agent['location']).isEmpty ? '—' : v(agent['location']),
        ),
      ],
    );
  }
}

bool _isValidMaintenancePhotoField(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return true;
  if (s.startsWith('data:image/')) return s.length <= 2400000;
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

  Future<void> pickPhoto() async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      withData: true,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;
    if (bytes.length > 900000) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Image trop volumineuse (max. ~900 Ko).'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    final ext = (file.extension ?? '').toLowerCase();
    var mime = 'image/jpeg';
    if (ext == 'png') mime = 'image/png';
    if (ext == 'gif') mime = 'image/gif';
    if (ext == 'webp') mime = 'image/webp';
    photoCtrl.text = 'data:$mime;base64,${base64Encode(bytes)}';
  }

  try {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1D1D38),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Text(
                'Modifier le profil',
                style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w700),
              ),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: 420,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Photo (URL https ou image importée)',
                        style: GoogleFonts.inter(color: const Color(0xFFE2BFB0), fontSize: 12),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: photoCtrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'https://…',
                          hintStyle: TextStyle(color: Colors.white.withOpacity(0.35)),
                          filled: true,
                          fillColor: const Color(0xFF10102B),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () async {
                            await pickPhoto();
                            setLocal(() {});
                          },
                          icon: const Icon(Icons.upload_rounded, color: Color(0xFFFF6E00)),
                          label: Text(
                            'Importer une image',
                            style: GoogleFonts.inter(color: const Color(0xFFFF6E00)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: firstCtrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: _maintenanceDialogFieldDeco('Prénom'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: lastCtrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: _maintenanceDialogFieldDeco('Nom'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: emailCtrl,
                        style: const TextStyle(color: Colors.white),
                        keyboardType: TextInputType.emailAddress,
                        decoration: _maintenanceDialogFieldDeco('Email'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: addressCtrl,
                        style: const TextStyle(color: Colors.white),
                        maxLines: 2,
                        decoration: _maintenanceDialogFieldDeco('Adresse'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: locationCtrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: _maintenanceDialogFieldDeco('Lieu / site d’intervention'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: passwordCtrl,
                        obscureText: obscurePwd,
                        style: const TextStyle(color: Colors.white),
                        decoration: _maintenanceDialogFieldDeco('Nouveau mot de passe (optionnel)').copyWith(
                          suffixIcon: IconButton(
                            icon: Icon(obscurePwd ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: Colors.white54),
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
                  child: Text('Annuler', style: GoogleFonts.inter(color: const Color(0xFFE2BFB0))),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
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
  return InputDecoration(
    labelText: label,
    labelStyle: GoogleFonts.inter(color: const Color(0xFFE2BFB0)),
    filled: true,
    fillColor: const Color(0xFF10102B),
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
      border: Border.all(color: Colors.white.withOpacity(0.06)),
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
