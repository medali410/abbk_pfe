import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'add_concepteur_page.dart';
import 'maintenance_agent_detail_page.dart';
import 'add_maintenance_agent_page.dart';
import 'add_technician_page.dart';
import 'concepteur_detail_page.dart';
import 'services/api_service.dart';

/// « Équipe de Projet » — gestion des ressources (techniciens, concepteurs, maintenance).
/// Design aligné sur la maquette Kinetic / Industrial Intelligence.
class ProjectTeamPage extends StatefulWidget {
  final VoidCallback? onAddTechnician;
  final void Function(String role)? onAddTeamMember;
  final void Function(Map<String, dynamic> initialData)? onEditConcepteurFromTeam;
  final void Function(Map<String, dynamic> initialData)? onEditMaintenanceFromTeam;
  final void Function(Map<String, dynamic> initialData)? onEditTechnicianFromTeam;

  const ProjectTeamPage({
    super.key,
    this.onAddTechnician,
    this.onAddTeamMember,
    this.onEditConcepteurFromTeam,
    this.onEditMaintenanceFromTeam,
    this.onEditTechnicianFromTeam,
  });

  @override
  State<ProjectTeamPage> createState() => _ProjectTeamPageState();
}

class _ProjectTeamPageState extends State<ProjectTeamPage> {
  late Future<List<Map<String, dynamic>>> _teamFuture;
  late Future<int> _machineCountFuture;

  static const String _defaultAvatar =
      'https://lh3.googleusercontent.com/aida-public/AB6AXuDq_QvtTILBr0s70Z4lnkl6m0t5NMHe-lrWV2_qTKFsUB-MSdx8vlQvV2aBjsrwMO7eDUnyYprosueyoyBirza-p_ZJK5XwhtN7GIUlmqpnmUb9bBXJC6bkHQnTTAvoZ2GSPwncbwALPQpQvfDSe36HaWWVegGnz712Vk5F3rCdRulUQt8__Psz2vk3QuFX54_dg64q0uQ5i7LGNNkHe7ShW2ecKfuhsg-rTlEp8OB2JPGUr9rjNL8Hu3v7vp6f1iET3gyIZvOetQ8';

  static const Color _canvas = Color(0xFF0F0F1E);
  static const Color _surfaceLow = Color(0xFF191934);
  static const Color _primary = Color(0xFFFFB692);
  static const Color _primaryContainer = Color(0xFFFF6E00);
  static const Color _secondary = Color(0xFF75D1FF);
  static const Color _tertiary = Color(0xFFEFB1F9);
  static const Color _onSurface = Color(0xFFE2DFFF);
  static const Color _onSurfaceVariant = Color(0xFFE2BFB0);
  static const Color _outlineVariant = Color(0xFF594136);
  static const Color _green = Color(0xFF66BB6A);
  static const Color _error = Color(0xFFFFB4AB);
  static const Color _slate = Color(0xFF64748B);

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    if (ApiService.canManageFleet) {
      _teamFuture = ApiService.getTeamDirectory();
    } else {
      _teamFuture = _techniciansAsTeamRows();
    }
    _machineCountFuture = _fetchMachineCount();
  }

  Future<int> _fetchMachineCount() async {
    try {
      final m = await ApiService.getMachines();
      return m.length;
    } catch (_) {
      return 0;
    }
  }

  Future<List<Map<String, dynamic>>> _techniciansAsTeamRows() async {
    final techs = await ApiService.getTechnicians();
    return techs.map((t) {
      final tid = (t['technicianId'] ?? '').toString().trim();
      final id = (tid.isNotEmpty && tid != 'TECH-000')
          ? tid
          : ((t['id'] ?? '').toString().trim().isNotEmpty ? (t['id'] ?? '').toString() : tid);
      return <String, dynamic>{
        'directoryKind': 'technician',
        'roleLabel': 'TECHNICIEN',
        'name': t['name'] ?? 'Inconnu',
        'displayId': id.isEmpty ? (t['technicianId']?.toString() ?? '—') : id,
        'id': id,
        'specialization': t['specialization'] ?? 'Général',
        'status': t['status'] ?? 'Disponible',
        'phone': t['phone'] ?? 'N/A',
        'companyLine': t['companyId'] ?? '—',
        'imageUrl': t['imageUrl'],
        'raw': t,
      };
    }).toList();
  }

  String _footerLine(Map<String, dynamic> m, String kind) {
    if (kind == 'technician') {
      final s = (m['status'] ?? '').toString();
      if (s == 'Disponible') return 'Disponibilité: 98%';
      if (s == 'En mission') return 'Disponibilité: 72%';
      return 'Statut: $s';
    }
    return (m['specialization'] ?? '—').toString();
  }

  _RoleVisual _roleVisual(String kind) {
    switch (kind) {
      case 'concepteur':
        return _RoleVisual(
          label: 'Concepteur',
          accent: _secondary,
          border: _secondary.withValues(alpha: 0.35),
          badgeBg: const Color(0xFF009CCE).withValues(alpha: 0.12),
        );
      case 'maintenance':
        return _RoleVisual(
          label: 'Maintenance',
          accent: _primary,
          border: _primary.withValues(alpha: 0.35),
          badgeBg: _primaryContainer.withValues(alpha: 0.15),
        );
      default:
        return _RoleVisual(
          label: 'Technicien',
          accent: _tertiary,
          border: _tertiary.withValues(alpha: 0.35),
          badgeBg: const Color(0xFFC086CA).withValues(alpha: 0.15),
        );
    }
  }

  Future<void> _confirmDeleteTechnician(BuildContext context, String id, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surfaceLow,
        title: Text('Supprimer $name ?', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text('Cette action est irréversible.', style: GoogleFonts.spaceGrotesk(color: _onSurfaceVariant)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Annuler', style: GoogleFonts.inter(color: _onSurfaceVariant))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: _error),
            child: Text('Supprimer', style: GoogleFonts.inter(color: Colors.black87, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ApiService.deleteTechnician(id);
      if (!context.mounted) return;
      setState(_reload);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$name supprimé'), backgroundColor: _green));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _confirmDeleteConcepteur(BuildContext context, String id, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surfaceLow,
        title: Text('Supprimer $name ?', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Supprimer')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ApiService.deleteConcepteur(id);
      if (!context.mounted) return;
      setState(_reload);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$name supprimé'), backgroundColor: _green));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _confirmDeleteMaintenance(BuildContext context, String id, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surfaceLow,
        title: Text('Supprimer $name ?', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Supprimer')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ApiService.deleteMaintenanceAgent(id);
      if (!context.mounted) return;
      setState(_reload);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$name supprimé'), backgroundColor: _green));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: Colors.red));
    }
  }

  void _openEditConcepteur(Map<String, dynamic> payload) {
    if (widget.onEditConcepteurFromTeam != null) {
      widget.onEditConcepteurFromTeam!(payload);
    } else {
      Navigator.push<void>(context, MaterialPageRoute<void>(builder: (_) => AddConcepteurPage(initialData: payload))).then((_) {
        if (mounted) setState(_reload);
      });
    }
  }

  void _openEditMaintenance(Map<String, dynamic> payload) {
    if (widget.onEditMaintenanceFromTeam != null) {
      widget.onEditMaintenanceFromTeam!(payload);
    } else {
      Navigator.push<void>(context, MaterialPageRoute<void>(builder: (_) => AddMaintenanceAgentPage(initialData: payload))).then((_) {
        if (mounted) setState(_reload);
      });
    }
  }

  void _openEditTechnician(Map<String, dynamic> payload) {
    if (widget.onEditTechnicianFromTeam != null) {
      widget.onEditTechnicianFromTeam!(payload);
    } else {
      Navigator.push<void>(context, MaterialPageRoute<void>(builder: (_) => AddTechnicianPage(initialData: payload))).then((_) {
        if (mounted) setState(_reload);
      });
    }
  }

  VoidCallback? _editActionFor(Map<String, dynamic> member) {
    final kind = (member['directoryKind'] ?? 'technician').toString();
    final displayId = (member['displayId'] ?? member['id'] ?? '').toString();
    final canSuper = ApiService.isSuperAdmin;
    if (kind == 'technician' &&
        ApiService.canManageFleet &&
        displayId.isNotEmpty &&
        displayId != '—') {
      return () => _handleMenu('edit_t', member);
    }
    if (kind == 'concepteur' && canSuper && (member['id']?.toString().isNotEmpty ?? false)) {
      return () => _handleMenu('edit_c', member);
    }
    if (kind == 'maintenance' && canSuper && displayId.isNotEmpty && displayId != '—') {
      return () => _handleMenu('edit_m', member);
    }
    return null;
  }

  VoidCallback? _deleteActionFor(Map<String, dynamic> member) {
    final kind = (member['directoryKind'] ?? 'technician').toString();
    final displayId = (member['displayId'] ?? member['id'] ?? '').toString();
    final canSuper = ApiService.isSuperAdmin;
    final canDelT = kind == 'technician' && ApiService.canManageFleet && displayId.isNotEmpty && displayId != '—';
    final canDelC = kind == 'concepteur' && canSuper && (member['id']?.toString().isNotEmpty ?? false);
    final canDelM = kind == 'maintenance' && canSuper && displayId.isNotEmpty && displayId != '—';
    if (canDelT) return () => _handleMenu('del_t', member);
    if (canDelC) return () => _handleMenu('del_c', member);
    if (canDelM) return () => _handleMenu('del_m', member);
    return null;
  }

  Future<void> _openMember(Map<String, dynamic> member) async {
    final kind = (member['directoryKind'] ?? 'technician').toString();
    final displayId = (member['displayId'] ?? member['id'] ?? '').toString();
    final rawMap = member['raw'];
    final raw = rawMap is Map ? Map<String, dynamic>.from(rawMap) : <String, dynamic>{};

    if (kind == 'technician') {
      final args = Map<String, dynamic>.from(raw);
      args['id'] = displayId;
      args['technicianId'] = displayId;
      args['viewerRole'] = ApiService.isSuperAdmin ? 'superadmin' : (ApiService.canManageFleet ? 'admin' : 'technician');
      final changed = await Navigator.pushNamed(context, '/technician-profile', arguments: args);
      if (changed == true && mounted) setState(_reload);
      return;
    }
    if (kind == 'concepteur') {
      final cid = (member['id'] ?? '').toString();
      if (cid.isEmpty) return;
      await Navigator.push<void>(context, MaterialPageRoute<void>(builder: (_) => ConcepteurDetailPage(concepteurId: cid)));
      if (mounted) setState(_reload);
      return;
    }
    if (!mounted) return;
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => MaintenanceAgentDetailPage(member: member),
      ),
    );
    if (changed == true && mounted) {
      setState(_reload);
    }
  }

  void _onAddMemberRole(String role) {
    if (widget.onAddTeamMember != null) {
      widget.onAddTeamMember!(role);
      return;
    }
    switch (role) {
      case 'technician':
        widget.onAddTechnician?.call();
        break;
      default:
        break;
    }
  }

  void _showRolePicker() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _surfaceLow,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Nouveau membre', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: _onSurface)),
            const SizedBox(height: 16),
            _sheetRole(ctx, 'technician', 'Technicien', _tertiary, Icons.engineering_outlined),
            const SizedBox(height: 8),
            _sheetRole(ctx, 'concepteur', 'Concepteur', _secondary, Icons.architecture_outlined),
            const SizedBox(height: 8),
            _sheetRole(ctx, 'maintenance', 'Personnel maintenance', _primary, Icons.build_circle_outlined, enabled: ApiService.isSuperAdmin),
          ],
        ),
      ),
    );
  }

  Widget _sheetRole(BuildContext ctx, String role, String title, Color c, IconData icon, {bool enabled = true}) {
    return Material(
      color: c.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: enabled
            ? () {
                Navigator.pop(ctx);
                _onAddMemberRole(role);
              }
            : () {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Maintenance : compte super-admin requis.')),
                );
              },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: enabled ? c : _slate),
              const SizedBox(width: 12),
              Expanded(child: Text(title, style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: enabled ? _onSurface : _slate))),
              Icon(Icons.chevron_right, color: _slate),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(color: _canvas),
        Positioned(
          right: -120,
          top: -80,
          child: IgnorePointer(
            child: Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(shape: BoxShape.circle, color: _primaryContainer.withValues(alpha: 0.06)),
            ),
          ),
        ),
        Positioned(
          left: -80,
          bottom: -40,
          child: IgnorePointer(
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(shape: BoxShape.circle, color: _secondary.withValues(alpha: 0.06)),
            ),
          ),
        ),
        CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'ÉQUIPE DE PROJET',
                          style: GoogleFonts.inter(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: _primaryContainer,
                            letterSpacing: -0.5,
                          ),
                        ),
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 16),
                          width: 1,
                          height: 18,
                          color: _outlineVariant.withValues(alpha: 0.35),
                        ),
                        Expanded(
                          child: Text(
                            'TELEMETRY / ASSETS / TEAM',
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 11,
                              color: _onSurfaceVariant,
                              letterSpacing: 1.6,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Icon(Icons.notifications_outlined, color: _slate.withValues(alpha: 0.9)),
                        const SizedBox(width: 20),
                        Icon(Icons.settings_outlined, color: _slate.withValues(alpha: 0.9)),
                        const SizedBox(width: 16),
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: _primaryContainer.withValues(alpha: 0.35)),
                            image: const DecorationImage(
                              image: NetworkImage(
                                'https://lh3.googleusercontent.com/aida-public/AB6AXuBKSrSBWRvYnLVDMSURwRs8CkBQd5KpTkg3pUd2VL6mySPSCe35NeERteM4HZT_Y_88EztO9QfIAvi2raEPtvtHjWoNo0_P1mTZozfXyYEugi2ciHdj8dmHhSi2JKs6U97Bc9GyPCWt-PWD12M5uKoNjKIVBLb9CW_3_UX2gKrr6mdVQbRRn5zU9n2IpMoorFIGnVpMH2EltOcIS-OScJWmJzXDrwDsPtlUveUZZ5N8lNnzf9tiQnXW0ERVHpT-Ocn_7VlfIN6xxWw',
                              ),
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    LayoutBuilder(
                      builder: (context, c) {
                        final narrow = c.maxWidth < 720;
                        return Flex(
                          direction: narrow ? Axis.vertical : Axis.horizontal,
                          crossAxisAlignment: narrow ? CrossAxisAlignment.start : CrossAxisAlignment.end,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            ConstrainedBox(
                              constraints: BoxConstraints(maxWidth: narrow ? double.infinity : 520),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Gestion des Ressources',
                                    style: GoogleFonts.inter(
                                      fontSize: narrow ? 28 : 36,
                                      fontWeight: FontWeight.w900,
                                      color: _onSurface,
                                      letterSpacing: -0.8,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    "Supervisez l'allocation des techniciens, concepteurs et agents de maintenance sur le réseau Kinetic.",
                                    style: GoogleFonts.inter(
                                      fontSize: 14,
                                      height: 1.45,
                                      color: _onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (narrow) const SizedBox(height: 20),
                            FutureBuilder<int>(
                              future: _machineCountFuture,
                              builder: (context, snap) {
                                return FutureBuilder<List<Map<String, dynamic>>>(
                                  future: _teamFuture,
                                  builder: (context, teamSnap) {
                                    final n = teamSnap.data?.length ?? 0;
                                    final nodes = snap.data ?? 0;
                                    return Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        _statChip('Membres actifs', '$n', _secondary),
                                        const SizedBox(width: 12),
                                        _statChip('Nodes connectés', '$nodes', _primary),
                                      ],
                                    );
                                  },
                                );
                              },
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _teamFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator(color: _primaryContainer)),
                  );
                }
                if (snapshot.hasError) {
                  return SliverFillRemaining(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Erreur: ${snapshot.error}',
                          style: GoogleFonts.inter(color: Colors.white70),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  );
                }
                final members = snapshot.data ?? [];
                return SliverPadding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 120),
                  sliver: SliverLayoutBuilder(
                    builder: (context, constraints) {
                      final w = constraints.crossAxisExtent;
                      int cols = 1;
                      if (w >= 520) cols = 2;
                      if (w >= 900) cols = 3;
                      if (w >= 1200) cols = 4;
                      final spacing = 20.0;
                      final tileW = (w - spacing * (cols - 1)) / cols;

                      final tiles = <Widget>[
                        ...members.map((m) => SizedBox(
                              width: tileW,
                              child: _MemberTile(
                                member: m,
                                defaultAvatar: _defaultAvatar,
                                roleVisual: _roleVisual((m['directoryKind'] ?? 'technician').toString()),
                                footerLine: _footerLine(m, (m['directoryKind'] ?? 'technician').toString()),
                                onOpen: () => _openMember(m),
                                onEdit: _editActionFor(m),
                                onDelete: _deleteActionFor(m),
                              ),
                            )),
                        SizedBox(
                          width: tileW,
                          child: _NewMemberCard(
                            onPickRole: _showRolePicker,
                            onTechnicien: () => _onAddMemberRole('technician'),
                            onConcepteur: () => _onAddMemberRole('concepteur'),
                            onMaintenance: () => _onAddMemberRole('maintenance'),
                            maintenanceEnabled: ApiService.isSuperAdmin,
                          ),
                        ),
                        SizedBox(width: tileW, child: const _SlotLibreCard()),
                      ];

                      return SliverToBoxAdapter(
                        child: Wrap(
                          spacing: spacing,
                          runSpacing: spacing,
                          children: tiles,
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ],
        ),
        Positioned(
          right: 24,
          bottom: 24,
          child: FloatingActionButton(
            onPressed: () {
              Navigator.pushNamed(context, '/message-equipe', arguments: {
                'role': 'conception',
                'name': 'Admin',
              });
            },
            backgroundColor: _primaryContainer,
            foregroundColor: const Color(0xFF582100),
            child: const Icon(Icons.chat_bubble_outline),
          ),
        ),
      ],
    );
  }

  Widget _statChip(String label, String value, Color accent) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: _surfaceLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _outlineVariant.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: GoogleFonts.spaceGrotesk(
              fontSize: 9,
              color: _slate,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.spaceGrotesk(fontSize: 26, fontWeight: FontWeight.bold, color: accent),
          ),
        ],
      ),
    );
  }

  Future<void> _handleMenu(String? value, Map<String, dynamic> member) async {
    if (value == null) return;
    final name = (member['name'] ?? '—').toString();
    final displayId = (member['displayId'] ?? member['id'] ?? '').toString();
    final concepteurId = (member['id'] ?? '').toString();
    final rawMap = member['raw'];
    final raw = rawMap is Map ? Map<String, dynamic>.from(rawMap) : <String, dynamic>{};
    final concepteurEditPayload = () {
      final r = Map<String, dynamic>.from(raw);
      r['id'] = (member['id'] ?? r['id'] ?? '').toString();
      return r;
    }();
    final maintenanceEditPayload = () {
      final r = Map<String, dynamic>.from(raw);
      final mid = (r['maintenanceAgentId'] ?? displayId).toString();
      if (mid.isNotEmpty) r['maintenanceAgentId'] = mid;
      return r;
    }();

    if (value == 'open') {
      await _openMember(member);
      return;
    }
    if (value == 'edit_c') {
      _openEditConcepteur(concepteurEditPayload);
      return;
    }
    if (value == 'edit_m') {
      _openEditMaintenance(maintenanceEditPayload);
      return;
    }
    if (value == 'edit_t') {
      final techPayload = () {
        final r = Map<String, dynamic>.from(raw);
        final tid = displayId.isNotEmpty ? displayId : (r['technicianId'] ?? r['id'] ?? '').toString();
        if (tid.isNotEmpty) {
          r['id'] = tid;
          r['technicianId'] = tid;
        }
        return r;
      }();
      _openEditTechnician(techPayload);
      return;
    }
    if (value == 'del_t') {
      await _confirmDeleteTechnician(context, displayId, name);
      return;
    }
    if (value == 'del_c') {
      await _confirmDeleteConcepteur(context, concepteurId, name);
      return;
    }
    if (value == 'del_m') {
      await _confirmDeleteMaintenance(context, displayId, name);
    }
  }
}

class _RoleVisual {
  final String label;
  final Color accent;
  final Color border;
  final Color badgeBg;

  _RoleVisual({required this.label, required this.accent, required this.border, required this.badgeBg});
}

class _MemberTile extends StatelessWidget {
  final Map<String, dynamic> member;
  final String defaultAvatar;
  final _RoleVisual roleVisual;
  final String footerLine;
  final VoidCallback onOpen;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _MemberTile({
    required this.member,
    required this.defaultAvatar,
    required this.roleVisual,
    required this.footerLine,
    required this.onOpen,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final name = (member['name'] ?? '—').toString();
    final displayId = (member['displayId'] ?? member['id'] ?? '—').toString();
    final imageUrl = (member['imageUrl'] != null && member['imageUrl'].toString().isNotEmpty)
        ? member['imageUrl'].toString()
        : defaultAvatar;

    const accentBtn = Color(0xFFFFB692);
    const errBtn = Color(0xFFFFB4AB);

    return Material(
      color: const Color(0xFF191934),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(12),
        hoverColor: const Color(0xFF32324E).withValues(alpha: 0.5),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: roleVisual.border, width: 2),
                          image: DecorationImage(image: NetworkImage(imageUrl), fit: BoxFit.cover),
                        ),
                      ),
                      Positioned(
                        right: -6,
                        bottom: -6,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(color: Color(0xFF0B0B26), shape: BoxShape.circle),
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: roleVisual.accent,
                              shape: BoxShape.circle,
                              boxShadow: [BoxShadow(color: roleVisual.accent.withValues(alpha: 0.45), blurRadius: 6)],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: roleVisual.badgeBg,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: roleVisual.accent.withValues(alpha: 0.15)),
                    ),
                    child: Text(
                      roleVisual.label.toUpperCase(),
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: roleVisual.accent,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(name, style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.bold, color: const Color(0xFFE2DFFF))),
              const SizedBox(height: 6),
              Text(
                'ID: $displayId',
                style: GoogleFonts.spaceGrotesk(fontSize: 11, color: const Color(0xFF94A3B8), letterSpacing: 1.1, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 18),
              Container(height: 1, color: const Color(0xFF594136).withValues(alpha: 0.15)),
              const SizedBox(height: 14),
              Text(
                footerLine.toUpperCase(),
                style: GoogleFonts.spaceGrotesk(fontSize: 10, color: const Color(0xFF94A3B8), letterSpacing: 0.6),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (onEdit != null || onDelete != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (onEdit != null)
                      Expanded(
                        child: OutlinedButton(
                          onPressed: onEdit,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: accentBtn,
                            side: BorderSide(color: accentBtn.withValues(alpha: 0.45)),
                            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                            minimumSize: const Size(0, 36),
                          ),
                          child: Text('Modifier', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
                        ),
                      ),
                    if (onEdit != null && onDelete != null) const SizedBox(width: 10),
                    if (onDelete != null)
                      Expanded(
                        child: TextButton(
                          onPressed: onDelete,
                          style: TextButton.styleFrom(
                            foregroundColor: errBtn,
                            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                            minimumSize: const Size(0, 36),
                          ),
                          child: Text('Effacer', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _NewMemberCard extends StatelessWidget {
  final VoidCallback onPickRole;
  final VoidCallback onTechnicien;
  final VoidCallback onConcepteur;
  final VoidCallback onMaintenance;
  final bool maintenanceEnabled;

  const _NewMemberCard({
    required this.onPickRole,
    required this.onTechnicien,
    required this.onConcepteur,
    required this.onMaintenance,
    required this.maintenanceEnabled,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFF191934).withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF594136).withValues(alpha: 0.35)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Material(
            color: const Color(0xFF272743),
            shape: const CircleBorder(),
            child: InkWell(
              onTap: onPickRole,
              customBorder: const CircleBorder(),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Icon(Icons.person_add_alt_1, size: 32, color: const Color(0xFFFFB692)),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text('Nouveau membre', style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.bold, color: const Color(0xFFE2DFFF))),
          const SizedBox(height: 6),
          Text(
            'Sélectionnez le rôle à assigner',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFFE2BFB0)),
          ),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              _roleBtn('Technicien', const Color(0xFFEFB1F9), onTechnicien),
              _roleBtn('Concepteur', const Color(0xFF75D1FF), onConcepteur),
              _roleBtn(
                'Maintenance',
                const Color(0xFFFFB692),
                maintenanceEnabled ? onMaintenance : () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Réservé au super-admin.')),
                  );
                },
                faint: !maintenanceEnabled,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _roleBtn(String label, Color c, VoidCallback onTap, {bool faint = false}) {
    return Material(
      color: c.withValues(alpha: faint ? 0.05 : 0.12),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            label.toUpperCase(),
            style: GoogleFonts.spaceGrotesk(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: faint ? Colors.white38 : c,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }
}

class _SlotLibreCard extends StatelessWidget {
  const _SlotLibreCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF191934),
        borderRadius: BorderRadius.circular(12),
        border: const Border(left: BorderSide(color: Color(0xFFFF6E00), width: 2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SLOT LIBRE',
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: const Color(0xFFE2DFFF).withValues(alpha: 0.5),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            "En attente d'approbation RH pour le segment Alpha-4.",
            style: GoogleFonts.spaceGrotesk(fontSize: 12, color: const Color(0xFF64748B), height: 1.35),
          ),
          const SizedBox(height: 36),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: 0.33,
              minHeight: 4,
              backgroundColor: const Color(0xFF1E293B),
              color: const Color(0xFFFF6E00).withValues(alpha: 0.45),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'RECRUTEMENT EN COURS',
            style: GoogleFonts.spaceGrotesk(fontSize: 9, color: const Color(0xFF64748B), letterSpacing: 1.4, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
