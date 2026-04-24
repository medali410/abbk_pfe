import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'add_concepteur_page.dart';
import 'add_maintenance_agent_page.dart';
import 'concepteur_detail_page.dart';
import 'services/api_service.dart';

class TechnicianListPage extends StatefulWidget {
  final VoidCallback? onAddTechnician;
  /// Rôle choisi : `technician`, `concepteur`, `maintenance` (préféré si non null).
  final void Function(String role)? onAddTeamMember;

  /// Édition embarquée dashboard : charge [AddConcepteurPage] avec `initialData`.
  final void Function(Map<String, dynamic> initialData)? onEditConcepteurFromTeam;

  /// Édition embarquée dashboard : charge [AddMaintenanceAgentPage] avec `initialData`.
  final void Function(Map<String, dynamic> initialData)? onEditMaintenanceFromTeam;

  const TechnicianListPage({
    super.key,
    this.onAddTechnician,
    this.onAddTeamMember,
    this.onEditConcepteurFromTeam,
    this.onEditMaintenanceFromTeam,
  });

  @override
  State<TechnicianListPage> createState() => _TechnicianListPageState();
}

class _TechnicianListPageState extends State<TechnicianListPage> {
  late Future<List<Map<String, dynamic>>> _teamFuture;

  static const String _defaultAvatar =
      'https://lh3.googleusercontent.com/aida-public/AB6AXuDq_QvtTILBr0s70Z4lnkl6m0t5NMHe-lrWV2_qTKFsUB-MSdx8vlQvV2aBjsrwMO7eDUnyYprosueyoyBirza-p_ZJK5XwhtN7GIUlmqpnmUb9bBXJC6bkHQnTTAvoZ2GSPwncbwALPQpQvfDSe36HaWWVegGnz712Vk5F3rCdRulUQt8__Psz2vk3QuFX54_dg64q0uQ5i7LGNNkHe7ShW2ecKfuhsg-rTlEp8OB2JPGUr9rjNL8Hu3v7vp6f1iET3gyIZvOetQ8';

  static const _bg = Color(0xFF10102B);
  static const _surfaceContainerLow = Color(0xFF191934);
  static const _surfaceContainer = Color(0xFF1D1D38);
  static const _surfaceContainerHighest = Color(0xFF32324E);
  static const _primary = Color(0xFFFFB692);
  static const _primaryContainer = Color(0xFFFF6E00);
  static const _secondary = Color(0xFF75D1FF);
  static const _onSurface = Color(0xFFE2DFFF);
  static const _onSurfaceVariant = Color(0xFFE2BFB0);
  static const _outlineVariant = Color(0xFF594136);
  static const _green = Color(0xFF66BB6A);
  static const _error = Color(0xFFFFB4AB);

  @override
  void initState() {
    super.initState();
    _reloadTeam();
  }

  void _reloadTeam() {
    if (ApiService.canManageFleet) {
      _teamFuture = ApiService.getTeamDirectory();
    } else {
      _teamFuture = _techniciansAsTeamRows();
    }
  }

  Future<List<Map<String, dynamic>>> _techniciansAsTeamRows() async {
    final techs = await ApiService.getTechnicians();
    return techs.map((t) {
      final id = _technicianApiId(t);
      return <String, dynamic>{
        'directoryKind': 'technician',
        'roleLabel': 'TECHNICIEN',
        'name': t['name'] ?? 'Inconnu',
        'displayId': id.isEmpty ? (t['technicianId']?.toString() ?? '—') : id,
        'id': id.isEmpty ? (t['technicianId']?.toString() ?? '') : id,
        'specialization': t['specialization'] ?? 'Général',
        'status': t['status'] ?? 'Disponible',
        'phone': t['phone'] ?? 'N/A',
        'companyId': t['companyId'] ?? '—',
        'companyLine': t['companyId'] ?? '—',
        'imageUrl': t['imageUrl'],
        'raw': t,
      };
    }).toList();
  }

  /// Identifiant API (technicianId métier, jamais le fallback d’affichage TECH-000).
  String _technicianApiId(Map<String, dynamic> t) {
    final tid = (t['technicianId'] ?? '').toString().trim();
    if (tid.isNotEmpty && tid != 'TECH-000') return tid;
    final oid = (t['id'] ?? '').toString().trim();
    if (oid.isNotEmpty) return oid;
    return tid;
  }

  Future<void> _confirmDeleteTechnician(
    BuildContext context, {
    required String technicianId,
    required String technicianName,
  }) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surfaceContainerLow,
        title: Text(
          'Supprimer $technicianName ?',
          style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Cette action est irréversible.',
          style: GoogleFonts.spaceGrotesk(color: _onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Annuler', style: GoogleFonts.inter(color: _onSurfaceVariant)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: _error),
            child: Text('Supprimer', style: GoogleFonts.inter(color: Colors.black87, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (shouldDelete != true) return;

    try {
      await ApiService.deleteTechnician(technicianId);
      if (!mounted) return;
      setState(_reloadTeam); // refresh in place immediately
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$technicianName supprimé', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
          backgroundColor: _green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur suppression: $e', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _confirmDeleteConcepteur(
    BuildContext context, {
    required String concepteurId,
    required String name,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surfaceContainerLow,
        title: Text('Supprimer le concepteur $name ?', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text('Le compte sera définitivement retiré de la base.', style: GoogleFonts.spaceGrotesk(color: _onSurfaceVariant)),
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
      await ApiService.deleteConcepteur(concepteurId);
      if (!mounted) return;
      setState(_reloadTeam);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$name supprimé', style: GoogleFonts.inter(fontWeight: FontWeight.bold)), backgroundColor: _green, behavior: SnackBarBehavior.floating),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $e', style: GoogleFonts.inter(fontWeight: FontWeight.bold)), backgroundColor: Colors.redAccent, behavior: SnackBarBehavior.floating),
      );
    }
  }

  Future<void> _confirmDeleteMaintenanceAgent(
    BuildContext context, {
    required String agentId,
    required String name,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surfaceContainerLow,
        title: Text('Supprimer $name ?', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text('Fiche personnel maintenance supprimée définitivement.', style: GoogleFonts.spaceGrotesk(color: _onSurfaceVariant)),
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
      await ApiService.deleteMaintenanceAgent(agentId);
      if (!mounted) return;
      setState(_reloadTeam);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$name supprimé', style: GoogleFonts.inter(fontWeight: FontWeight.bold)), backgroundColor: _green, behavior: SnackBarBehavior.floating),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $e', style: GoogleFonts.inter(fontWeight: FontWeight.bold)), backgroundColor: Colors.redAccent, behavior: SnackBarBehavior.floating),
      );
    }
  }

  void _openEditConcepteur(Map<String, dynamic> payload) {
    if (widget.onEditConcepteurFromTeam != null) {
      widget.onEditConcepteurFromTeam!(payload);
      return;
    }
    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => AddConcepteurPage(initialData: payload),
      ),
    ).then((_) {
      if (mounted) setState(_reloadTeam);
    });
  }

  void _openEditMaintenance(Map<String, dynamic> payload) {
    if (widget.onEditMaintenanceFromTeam != null) {
      widget.onEditMaintenanceFromTeam!(payload);
      return;
    }
    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => AddMaintenanceAgentPage(initialData: payload),
      ),
    ).then((_) {
      if (mounted) setState(_reloadTeam);
    });
  }

  Future<String?> _pickNewProfileRole(BuildContext context) {
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surfaceContainerLow,
        title: Text(
          'Type de profil',
          style: GoogleFonts.inter(color: _onSurface, fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Choisissez le rôle en premier ; le formulaire s’ouvrira ensuite.',
                style: GoogleFonts.spaceGrotesk(color: _onSurfaceVariant, fontSize: 13, height: 1.35),
              ),
              const SizedBox(height: 16),
              _roleChoiceTile(
                ctx,
                value: 'technician',
                title: 'Technicien',
                subtitle: 'Terrain, machines, arrêt moteur, maintenance',
                icon: Icons.engineering_outlined,
              ),
              const SizedBox(height: 8),
              _roleChoiceTile(
                ctx,
                value: 'concepteur',
                title: 'Concepteur',
                subtitle: 'CAO, schémas, liaison client',
                icon: Icons.architecture_outlined,
              ),
              const SizedBox(height: 8),
              _roleChoiceTile(
                ctx,
                value: 'maintenance',
                title: 'Personnel maintenance',
                subtitle: ApiService.isSuperAdmin
                    ? 'Fiche métier Mongo (super-admin)'
                    : 'Réservé au super-administrateur',
                icon: Icons.build_circle_outlined,
                enabled: ApiService.isSuperAdmin,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Annuler', style: GoogleFonts.inter(color: _onSurfaceVariant)),
          ),
        ],
      ),
    );
  }

  Widget _roleChoiceTile(
    BuildContext ctx, {
    required String value,
    required String title,
    required String subtitle,
    required IconData icon,
    bool enabled = true,
  }) {
    return Material(
      color: enabled ? _surfaceContainer : _surfaceContainer.withOpacity(0.5),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: enabled
            ? () => Navigator.pop(ctx, value)
            : () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Profil maintenance : connectez-vous en super-admin.',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                    ),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(icon, color: enabled ? _primaryContainer : _onSurfaceVariant.withOpacity(0.5), size: 28),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.inter(
                        color: enabled ? _onSurface : _onSurfaceVariant,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: GoogleFonts.spaceGrotesk(
                        color: _onSurfaceVariant.withOpacity(enabled ? 1 : 0.6),
                        fontSize: 11,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: _onSurfaceVariant.withOpacity(enabled ? 1 : 0.4)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openAddTechnician(BuildContext context) async {
    final role = await _pickNewProfileRole(context);
    if (!mounted || role == null) return;

    if (widget.onAddTeamMember != null) {
      widget.onAddTeamMember!(role);
      return;
    }

    if (widget.onAddTechnician != null && role == 'technician') {
      widget.onAddTechnician!();
      return;
    }

    switch (role) {
      case 'technician':
        await Navigator.of(context).pushNamed('/add-technician');
        break;
      case 'concepteur':
        await Navigator.push<bool>(
          context,
          MaterialPageRoute(builder: (_) => const AddConcepteurPage()),
        );
        break;
      case 'maintenance':
        if (!ApiService.isSuperAdmin) return;
        await Navigator.push<bool>(
          context,
          MaterialPageRoute(builder: (_) => const AddMaintenanceAgentPage()),
        );
        break;
    }
    if (!mounted) return;
    setState(_reloadTeam);
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 992;
    final isTablet = screenWidth > 600 && screenWidth <= 992;

    int crossAxisCount = 1;
    if (isDesktop) crossAxisCount = 3;
    else if (isTablet) crossAxisCount = 2;

    return Scaffold(
      backgroundColor: _bg,
      body: CustomScrollView(
        slivers: [
          _buildSliverAppBar(),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                Builder(builder: (context) => Column(
                  children: [
                    _buildHeader(context),
                    const SizedBox(height: 32),
                      FutureBuilder<List<Map<String, dynamic>>>(
                        future: _teamFuture,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Center(child: Padding(
                              padding: EdgeInsets.all(32.0),
                              child: CircularProgressIndicator(color: _primary),
                            ));
                          }
                          if (snapshot.hasError) {
                            return Center(child: Text('Erreur: ${snapshot.error}', style: const TextStyle(color: Colors.white)));
                          }
                          final members = snapshot.data ?? [];
                          
                          if (members.isEmpty) {
                            return const Center(child: Padding(
                              padding: EdgeInsets.all(32.0),
                              child: Text('Aucun membre dans le répertoire.', style: TextStyle(color: Colors.white)),
                            ));
                          }

                          List<Widget> cards = members.map((m) => Padding(
                            padding: const EdgeInsets.only(bottom: 24),
                            child: _buildMemberCard(context: context, member: m),
                          )).toList();

                          if (isDesktop) {
                            List<Widget> col1 = [];
                            List<Widget> col2 = [];
                            List<Widget> col3 = [];
                            for (int i = 0; i < cards.length; i++) {
                              if (i % 3 == 0) col1.add(cards[i]);
                              else if (i % 3 == 1) col2.add(cards[i]);
                              else col3.add(cards[i]);
                            }
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: Column(children: col1)),
                                const SizedBox(width: 24),
                                Expanded(child: Column(children: col2)),
                                const SizedBox(width: 24),
                                Expanded(child: Column(children: col3)),
                              ],
                            );
                          } else {
                            return Column(children: cards);
                          }
                        }
                      )
                  ],
                )),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSliverAppBar() {
    return SliverAppBar(
      pinned: true,
      backgroundColor: _bg.withOpacity(0.6),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      expandedHeight: 0,
      collapsedHeight: 64,
      toolbarHeight: 64,
      flexibleSpace: ClipRRect(
        child: BackdropFilter(
          filter: _buildBlur(),
          child: Container(
            color: Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(
                      'Technician Registry',
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: _primary,
                      ),
                    ),
                    const SizedBox(width: 32),
                    // Search bar
                    Container(
                      width: 256,
                      height: 36,
                      decoration: BoxDecoration(
                        color: _surfaceContainerLow,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: TextField(
                        style: GoogleFonts.spaceGrotesk(color: _onSurface, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Rechercher un technicien...',
                          hintStyle: GoogleFonts.spaceGrotesk(color: _onSurfaceVariant.withOpacity(0.5), fontSize: 14),
                          prefixIcon: Icon(Icons.search, color: _onSurfaceVariant, size: 18),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.only(bottom: 12),
                        ),
                      ),
                    ),
                  ],
                ),
                // Tabs
                Row(
                  children: [
                    _buildTopTab('ALL TECHS', active: true),
                    const SizedBox(width: 24),
                    _buildTopTab('ON-SITE', active: false),
                    const SizedBox(width: 24),
                    _buildTopTab('OFFLINE', active: false),
                  ],
                ),
                // Icons
                Row(
                  children: [
                    Icon(Icons.notifications_outlined, color: _onSurfaceVariant, size: 24),
                    const SizedBox(width: 16),
                    Icon(Icons.grid_view, color: _onSurfaceVariant, size: 24),
                    const SizedBox(width: 16),
                    Icon(Icons.filter_list, color: _onSurfaceVariant, size: 24),
                    const SizedBox(width: 16),
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: _primary.withOpacity(0.2)),
                        image: const DecorationImage(
                          image: NetworkImage('https://lh3.googleusercontent.com/aida-public/AB6AXuAAwj2JFtAmbFtHysEDuXmgapv3eSn-TthXnLcoZyh3aUg5KFoJubOJg8hDuoElXe0huD4zBtX8TaqthCvj2DjjXicohCs2kwpKIVjqalfC4xWSmCTVpWACTRLAff_vA7E2PQjfNcp6ut_P6nqLy7rkKYGj6oK0nf2EtDTqHsjmfJRaHi6xvyooEdKFKgxZdJMaqGLNJkbPJKvuK0b6RohrhXrZsdoJo3wIrmBQCyORG_fF5ui49QMgB4MnEUXLH-pvlOr_9ao8SFY'),
                          fit: BoxFit.cover,
                        ),
                      ),
                    )
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopTab(String text, {required bool active}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: active ? const Border(bottom: BorderSide(color: _primaryContainer, width: 2)) : null,
      ),
      child: Text(
        text,
        style: GoogleFonts.spaceGrotesk(
          fontSize: 14,
          fontWeight: active ? FontWeight.bold : FontWeight.w500,
          color: active ? _primaryContainer : _onSurfaceVariant,
          letterSpacing: 2.0,
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Répertoire de l’équipe',
              style: GoogleFonts.inter(
                fontSize: 36,
                fontWeight: FontWeight.w900,
                color: _onSurface,
                letterSpacing: -1.0,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "TECHNICIENS · CONCEPTEURS · PERSONNEL MAINTENANCE — DISPONIBILITÉ & CONTACTS",
              style: GoogleFonts.spaceGrotesk(
                fontSize: 12,
                color: _onSurfaceVariant,
                letterSpacing: 1.0,
              ),
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_primaryContainer, _primary],
            ),
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: _primaryContainer.withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: InkWell(
            onTap: () => _openAddTechnician(context),
            borderRadius: BorderRadius.circular(8),
            child: Row(
              children: [
                const Icon(Icons.person_add, color: _onSurface, size: 18),
                const SizedBox(width: 8),
                Text(
                  'NOUVEAU PROFIL',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: _onSurface,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMemberCard({
    required BuildContext context,
    required Map<String, dynamic> member,
  }) {
    final kind = (member['directoryKind'] ?? 'technician').toString();
    final roleLabel = (member['roleLabel'] ?? 'TECHNICIEN').toString().toUpperCase();
    final name = (member['name'] ?? '—').toString();
    final displayId = (member['displayId'] ?? member['id'] ?? '—').toString();
    final specialization = (member['specialization'] ?? '—').toString();
    final status = (member['status'] ?? '—').toString();
    final statusColor = _getStatusColor(status);
    final statusBgColor = statusColor.withOpacity(0.1);
    final phone = (member['phone'] ?? '—').toString();
    final location = (member['companyLine'] ?? member['companyId'] ?? '—').toString();
    final rawMap = member['raw'];
    final Map<String, dynamic> raw =
        rawMap is Map ? Map<String, dynamic>.from(rawMap) : <String, dynamic>{};

    final imageUrl = (member['imageUrl'] != null && member['imageUrl'].toString().isNotEmpty)
        ? member['imageUrl'].toString()
        : _defaultAvatar;

    final locIcon = kind == 'maintenance' ? Icons.business_outlined : Icons.location_on;

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

    Future<void> openDetail() async {
      if (kind == 'technician') {
        final args = Map<String, dynamic>.from(raw);
        args['id'] = displayId;
        args['technicianId'] = displayId;
        args['viewerRole'] =
            ApiService.isSuperAdmin ? 'superadmin' : (ApiService.canManageFleet ? 'admin' : 'technician');
        final changed = await Navigator.pushNamed(
          context,
          '/technician-profile',
          arguments: args,
        );
        if (changed == true && context.mounted) setState(_reloadTeam);
        return;
      }
      if (kind == 'concepteur') {
        final cid = (member['id'] ?? '').toString();
        if (cid.isEmpty) return;
        await Navigator.push<void>(
          context,
          MaterialPageRoute<void>(
            builder: (_) => ConcepteurDetailPage(concepteurId: cid),
          ),
        );
        if (context.mounted) setState(_reloadTeam);
        return;
      }
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: _surfaceContainerLow,
          title: Text(name, style: GoogleFonts.inter(color: _onSurface, fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Personnel maintenance (fiche MongoDB)', style: GoogleFonts.spaceGrotesk(color: _primary, fontSize: 12)),
                const SizedBox(height: 12),
                Text('ID: $displayId', style: GoogleFonts.spaceGrotesk(color: _onSurfaceVariant, fontSize: 13)),
                if (member['email'] != null) ...[
                  const SizedBox(height: 8),
                  Text('Email: ${member['email']}', style: GoogleFonts.spaceGrotesk(color: _onSurfaceVariant, fontSize: 13)),
                ],
                const SizedBox(height: 8),
                Text('Client: $location', style: GoogleFonts.spaceGrotesk(color: _onSurfaceVariant, fontSize: 13)),
              ],
            ),
          ),
          actions: [
            if (ApiService.isSuperAdmin) ...[
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _openEditMaintenance(maintenanceEditPayload);
                },
                child: Text('Modifier', style: GoogleFonts.inter(color: _primaryContainer, fontWeight: FontWeight.bold)),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _confirmDeleteMaintenanceAgent(context, agentId: displayId, name: name);
                },
                child: Text('Supprimer', style: GoogleFonts.inter(color: _error, fontWeight: FontWeight.bold)),
              ),
            ],
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Fermer', style: GoogleFonts.inter(color: _primaryContainer)),
            ),
          ],
        ),
      );
    }

    final canDeleteTechnician = kind == 'technician' &&
        ApiService.canManageFleet &&
        displayId.trim().isNotEmpty &&
        displayId != '—';

    final concepteurId = (member['id'] ?? '').toString();
    final canEditConcepteur = kind == 'concepteur' && ApiService.isSuperAdmin && concepteurId.isNotEmpty;
    final canDeleteConcepteur = canEditConcepteur;

    final canEditMaintenance = kind == 'maintenance' && ApiService.isSuperAdmin && displayId.isNotEmpty && displayId != '—';
    final canDeleteMaintenance = canEditMaintenance;

    return Material(
      color: _surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  roleLabel,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: _primaryContainer,
                    letterSpacing: 1.8,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: openDetail,
                      borderRadius: BorderRadius.circular(12),
                      child: Stack(
                        children: [
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              image: DecorationImage(
                                image: NetworkImage(imageUrl),
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: -4,
                            right: -4,
                            child: Container(
                              width: 24,
                              height: 24,
                              decoration: const BoxDecoration(
                                color: _surfaceContainer,
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: statusColor,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: statusColor.withOpacity(0.4),
                                        blurRadius: 4,
                                        spreadRadius: 2,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: statusBgColor,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            status.toUpperCase(),
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: statusColor,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'ID: $displayId',
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 12,
                            color: _onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (canEditConcepteur) ...[
                          TextButton.icon(
                            onPressed: () => _openEditConcepteur(concepteurEditPayload),
                            icon: Icon(Icons.edit_outlined, size: 16, color: _primaryContainer),
                            label: Text(
                              'MODIFIER',
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 9,
                                color: _primaryContainer,
                                letterSpacing: 1.2,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: TextButton.styleFrom(
                              foregroundColor: _primaryContainer,
                              backgroundColor: _primaryContainer.withOpacity(0.12),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                                side: BorderSide(color: _primaryContainer.withOpacity(0.4)),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                        ],
                        if (canEditMaintenance) ...[
                          TextButton.icon(
                            onPressed: () => _openEditMaintenance(maintenanceEditPayload),
                            icon: Icon(Icons.edit_outlined, size: 16, color: _primaryContainer),
                            label: Text(
                              'MODIFIER',
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 9,
                                color: _primaryContainer,
                                letterSpacing: 1.2,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: TextButton.styleFrom(
                              foregroundColor: _primaryContainer,
                              backgroundColor: _primaryContainer.withOpacity(0.12),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                                side: BorderSide(color: _primaryContainer.withOpacity(0.4)),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                        ],
                        TextButton.icon(
                          onPressed: canDeleteTechnician
                              ? () => _confirmDeleteTechnician(
                                    context,
                                    technicianId: displayId,
                                    technicianName: name,
                                  )
                              : canDeleteConcepteur
                                  ? () => _confirmDeleteConcepteur(context, concepteurId: concepteurId, name: name)
                                  : canDeleteMaintenance
                                      ? () => _confirmDeleteMaintenanceAgent(context, agentId: displayId, name: name)
                                      : null,
                          icon: const Icon(Icons.delete_outline, size: 16, color: _error),
                          label: Text(
                            'SUPPRIMER',
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 9,
                              color: _error,
                              letterSpacing: 1.2,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: TextButton.styleFrom(
                            foregroundColor: _error,
                            backgroundColor: _error.withOpacity(0.1),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                              side: BorderSide(color: _error.withOpacity(0.35)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          InkWell(
            onTap: openDetail,
            hoverColor: _surfaceContainerHighest.withOpacity(0.25),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: GoogleFonts.inter(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: _onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'SPÉCIALISATION: $specialization',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 10,
                      color: _primary,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Divider(color: _surfaceContainerHighest),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Icon(kind == 'concepteur' && phone.contains('@') ? Icons.email_outlined : Icons.call,
                          color: _onSurfaceVariant, size: 18),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          phone,
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 14,
                            color: _onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(locIcon, color: _onSurfaceVariant, size: 18),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          location,
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 14,
                            color: _onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: OutlinedButton(
              onPressed: openDetail,
              style: OutlinedButton.styleFrom(
                foregroundColor: _primaryContainer,
                side: BorderSide(color: _primaryContainer.withOpacity(0.4)),
                backgroundColor: _primaryContainer.withOpacity(0.1),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: Text(
                kind == 'technician' ? 'VOIR PROFIL COMPLET →' : 'VOIR LA FICHE →',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 10,
                  color: _primaryContainer,
                  letterSpacing: 2.0,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String? status) {
    if (status == 'Disponible' || status == 'Actif') return _green;
    if (status == 'En mission') return _secondary;
    return _error;
  }
}

// Ignore warning: used exclusively in this file
ui.ImageFilter _buildBlur() {
  return ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10);
}
