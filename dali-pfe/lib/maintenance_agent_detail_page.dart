import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'add_maintenance_agent_page.dart';
import 'services/api_service.dart';

class MaintenanceAgentDetailPage extends StatefulWidget {
  final Map<String, dynamic> member;

  const MaintenanceAgentDetailPage({
    super.key,
    required this.member,
  });

  @override
  State<MaintenanceAgentDetailPage> createState() => _MaintenanceAgentDetailPageState();
}

class _MaintenanceAgentDetailPageState extends State<MaintenanceAgentDetailPage> {
  static const _bg = Color(0xFF10102B);
  static const _surface = Color(0xFF1D1D38);
  static const _surfaceHigh = Color(0xFF272743);
  static const _onSurface = Color(0xFFE2DFFF);
  static const _onVariant = Color(0xFFE2BFB0);
  static const _primary = Color(0xFFFF6E00);
  static const _error = Color(0xFFFFB4AB);
  static const _green = Color(0xFF66BB6A);

  Map<String, dynamic> get _raw {
    final raw = widget.member['raw'];
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return <String, dynamic>{};
  }

  String _val(dynamic v, {String fallback = '—'}) {
    final s = (v ?? '').toString().trim();
    return s.isEmpty ? fallback : s;
  }

  String get _displayId => _val(widget.member['displayId'] ?? widget.member['id']);

  String get _name => _val(widget.member['name']);

  String get _email => _val(widget.member['email'] ?? _raw['email']);

  String get _client => _val(widget.member['companyLine'] ?? _raw['clientDisplay'] ?? _raw['clientId']);

  String get _firstName => _val(_raw['firstName']);

  String get _lastName => _val(_raw['lastName']);

  String get _address => _val(_raw['address']);

  String get _location => _val(_raw['location']);

  String get _imageUrl =>
      _val(widget.member['imageUrl'] ?? _raw['imageUrl'], fallback: '');

  String get _machines {
    final labels = _raw['machineLabels'];
    if (labels is List && labels.isNotEmpty) {
      final names = labels.map((e) {
        if (e is Map) return (e['name'] ?? e['id'] ?? '').toString().trim();
        return e.toString().trim();
      }).where((s) => s.isNotEmpty).toList();
      if (names.isNotEmpty) return names.join(', ');
    }
    final mids = _raw['machineIds'];
    if (mids is List && mids.isNotEmpty) {
      return mids.map((e) => e.toString()).join(', ');
    }
    return '—';
  }

  Future<void> _deleteAgent() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surface,
        title: Text('Supprimer $_name ?', style: GoogleFonts.inter(color: _onSurface, fontWeight: FontWeight.w700)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: _error, foregroundColor: Colors.black),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ApiService.deleteMaintenanceAgent(_displayId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$_name supprimé'), backgroundColor: _green),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _editAgent() async {
    final payload = Map<String, dynamic>.from(_raw);
    payload['maintenanceAgentId'] = _displayId;
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => AddMaintenanceAgentPage(initialData: payload)),
    );
    if (ok == true && mounted) {
      Navigator.pop(context, true);
    }
  }

  Widget _infoTile(IconData icon, String label, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _surfaceHigh,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: _onVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _onVariant)),
                const SizedBox(height: 2),
                Text(value, style: GoogleFonts.inter(fontSize: 13, color: _onSurface, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatarWidget() {
    final url = _imageUrl.trim();
    if (url.isNotEmpty && (url.startsWith('http://') || url.startsWith('https://'))) {
      return ClipOval(
        child: Image.network(
          url,
          width: 68,
          height: 68,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            width: 68,
            height: 68,
            color: _surfaceHigh,
            child: const Icon(Icons.engineering_rounded, size: 34, color: _onVariant),
          ),
        ),
      );
    }
    return Container(
      width: 68,
      height: 68,
      decoration: const BoxDecoration(
        color: _surfaceHigh,
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.engineering_rounded, size: 34, color: _onVariant),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 980;
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: _onSurface,
        title: Text('Détail maintenance', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withOpacity(0.05)),
                ),
                child: Row(
                  children: [
                    _avatarWidget(),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_name, style: GoogleFonts.inter(fontSize: 34, color: _onSurface, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 4),
                          Text('ID: $_displayId', style: GoogleFonts.spaceGrotesk(color: _onVariant, letterSpacing: 1.0)),
                          const SizedBox(height: 4),
                          Text('Personnel maintenance', style: GoogleFonts.spaceGrotesk(color: _primary, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _editAgent,
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Modifier'),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: _deleteAgent,
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: const Text('Supprimer'),
                      style: TextButton.styleFrom(foregroundColor: _error),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (isWide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 4,
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: _surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white.withOpacity(0.05)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('COORDONNÉES', style: GoogleFonts.spaceGrotesk(color: _primary, fontSize: 11, letterSpacing: 1.3)),
                            const SizedBox(height: 10),
                            _infoTile(Icons.person_outline_rounded, 'Prénom', _firstName),
                            _infoTile(Icons.person_2_outlined, 'Nom', _lastName),
                            _infoTile(Icons.alternate_email_rounded, 'Email', _email),
                            _infoTile(Icons.location_city_outlined, 'Localisation', _location),
                            _infoTile(Icons.home_outlined, 'Adresse', _address),
                            _infoTile(Icons.lock_outline_rounded, 'Mot de passe', 'Non affiché (stockage sécurisé hashé)'),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      flex: 6,
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: _surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white.withOpacity(0.05)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('UNITÉS SOUS SUPERVISION', style: GoogleFonts.spaceGrotesk(color: _onSurface, fontSize: 11, letterSpacing: 1.2)),
                            const SizedBox(height: 4),
                            Text('Machines assignées à cet agent maintenance', style: GoogleFonts.inter(color: _onVariant, fontSize: 12)),
                            const SizedBox(height: 12),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: _surfaceHigh,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.precision_manufacturing_outlined, color: _onVariant.withOpacity(0.9)),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _machines,
                                          style: GoogleFonts.inter(color: _onSurface, fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    'Client: $_client',
                                    style: GoogleFonts.spaceGrotesk(color: _onVariant, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            _infoTile(Icons.badge_outlined, 'Rôle', 'Personnel maintenance'),
                            _infoTile(Icons.tag_rounded, 'Identifiant technique', _displayId),
                          ],
                        ),
                      ),
                    ),
                  ],
                )
              else ...[
                _infoTile(Icons.person_outline_rounded, 'Prénom', _firstName),
                _infoTile(Icons.person_2_outlined, 'Nom', _lastName),
                _infoTile(Icons.alternate_email_rounded, 'Email', _email),
                _infoTile(Icons.business_center_outlined, 'Client', _client),
                _infoTile(Icons.precision_manufacturing_outlined, 'Machines assignées', _machines),
                _infoTile(Icons.location_city_outlined, 'Localisation', _location),
                _infoTile(Icons.home_outlined, 'Adresse', _address),
                _infoTile(Icons.lock_outline_rounded, 'Mot de passe', 'Non affiché (stockage sécurisé hashé)'),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

