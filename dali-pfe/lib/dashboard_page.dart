import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'client_list_view.dart';
import 'admin_machines_hub_page.dart';
import 'add_technician_page.dart';
import 'add_conception_page.dart';
import 'add_concepteur_page.dart';
import 'conception_list_page.dart';
import 'add_maintenance_agent_page.dart';
import 'maintenance_module_page.dart';
import 'add_machine_page.dart';
import 'widgets/message_equipe_view.dart';
import 'services/api_service.dart';
import 'mvc/controllers/dashboard_controller.dart';

// ─────────────────────────────────────────────────────────────
// Shell page that holds sidebar + topbar and swaps content area
// ─────────────────────────────────────────────────────────────
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  // 0 = overview | 1 = add client | 2 = clients | 3 = machines | 4 = équipe projet | 5 = add tech
  // 6 = conception hub | 8 = add document conception | 9 = (libre) | 10 = add concepteur | 11 = add maintenance agent | 12 = diagnostic panne | 13 = add machine
  int _currentPage = 0;
  /// Cible du retour depuis [AddConcepteurPage] (6 = hub conception).
  int _concepteurEmbeddedReturnPage = 6;
  Map<String, dynamic>? _pendingConcepteurEdit;
  Map<String, dynamic>? _pendingMaintenanceEdit;
  Map<String, dynamic>? _pendingTechnicianEdit;
  /// Onglet ConceptionListPage : 0 = concepteurs, 1 = documents
  int _conceptionInitialTab = 0;

  final DashboardController _mvc = DashboardController();

  @override
  void initState() {
    super.initState();
    _mvc.addListener(_onMvcUpdate);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final ok = await _mvc.ensureAuthSession();
      if (!mounted) return;
      if (!ok) {
        Navigator.pushReplacementNamed(context, '/');
        return;
      }
      await _mvc.loadGlobalStats();
    });
  }

  void _onMvcUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _mvc.removeListener(_onMvcUpdate);
    _mvc.dispose();
    super.dispose();
  }

  void _goTo(int page, {int conceptionTab = 0}) {
    if (page == 6) _conceptionInitialTab = conceptionTab.clamp(0, 1);
    if (page == 7) {
      setState(() => _currentPage = 7);
      return;
    }
    if (page == 0) _mvc.loadGlobalStats();
    if (page == 13) {
      final role = (ApiService.savedUserRole ?? '').toLowerCase();
      final canAddMachine = role == 'concepteur' || role == 'conception';
      if (!canAddMachine) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Accès refusé : seul le rôle Concepteur peut ajouter une machine.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AddMachinePage()),
      ).then((result) {
        if (result == true) _mvc.loadGlobalStats();
      });
      return;
    }
    setState(() => _currentPage = page);
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 992;

    return Scaffold(
      bottomNavigationBar: isDesktop ? null : _buildMobileBottomNav(),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0B1020), Color(0xFF141D34), Color(0xFF1A1730)],
          ),
        ),
        child: Column(
          children: [
            _buildTopBar(isDesktop),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: _currentPage == 1
                      ? _EmbeddedAddClientView(onBack: () => _goTo(2))
                      : _currentPage == 2
                          ? EmbeddedClientListView(
                              onAddClient: () => _goTo(1),
                            )
                          : _currentPage == 3
                              ? const AdminMachinesHubPage()
                              : _currentPage == 5
                                      ? AddTechnicianPage(
                                          key: ValueKey(
                                            'technician-${_pendingTechnicianEdit?['technicianId'] ?? _pendingTechnicianEdit?['id'] ?? 'new'}',
                                          ),
                                          initialData: _pendingTechnicianEdit,
                                          onBack: () {
                                            setState(() => _pendingTechnicianEdit = null);
                                            _goTo(0);
                                          },
                                        )
                                      : _currentPage == 6
                                          ? ConceptionListPage(
                                              key: ValueKey('conception-tab-$_conceptionInitialTab'),
                                              initialTabIndex: _conceptionInitialTab,
                                              onAddConception: () => _goTo(8),
                                              onAddConcepteur: () {
                                                setState(() {
                                                  _pendingConcepteurEdit = null;
                                                  _concepteurEmbeddedReturnPage = 6;
                                                });
                                                _goTo(10);
                                              },
                                              onEditConcepteur: (data) {
                                                setState(() {
                                                  _pendingConcepteurEdit = Map<String, dynamic>.from(data);
                                                  _concepteurEmbeddedReturnPage = 6;
                                                });
                                                _goTo(10);
                                              },
                                            )
                                          : _currentPage == 8
                                              ? AddConceptionPage(onEmbeddedBack: () => _goTo(6))
                                              : _currentPage == 10
                                                  ? AddConcepteurPage(
                                                      key: ValueKey(
                                                        'concepteur-${_pendingConcepteurEdit?['id'] ?? 'create'}',
                                                      ),
                                                      initialData: _pendingConcepteurEdit,
                                                      onEmbeddedBack: () {
                                                        final back = _concepteurEmbeddedReturnPage;
                                                        setState(() => _pendingConcepteurEdit = null);
                                                        _goTo(back);
                                                      },
                                                    )
                                                  : _currentPage == 11
                                                      ? AddMaintenanceAgentPage(
                                                          key: ValueKey(
                                                            'maint-${_pendingMaintenanceEdit?['maintenanceAgentId'] ?? _pendingMaintenanceEdit?['id'] ?? 'create'}',
                                                          ),
                                                          initialData: _pendingMaintenanceEdit,
                                                          onEmbeddedBack: () {
                                                            setState(() => _pendingMaintenanceEdit = null);
                                                            _goTo(0);
                                                          },
                                                        )
                                                      : _currentPage == 12
                                                          ? const MaintenanceModulePage()
                                                          : _currentPage == 7
                                                              ? const MessageEquipeView(embedded: true)
                                                              : RefreshIndicator(
                                                          color: const Color(0xFFFF8F3F),
                                                          onRefresh: _mvc.loadGlobalStats,
                                                          child: SingleChildScrollView(
                                                            physics: const AlwaysScrollableScrollPhysics(),
                                                            padding: const EdgeInsets.symmetric(
                                                              horizontal: 24.0,
                                                              vertical: 24.0,
                                                            ),
                                                            child: Column(
                                                              crossAxisAlignment: CrossAxisAlignment.start,
                                                              children: [
                                                                const SizedBox(height: 16),
                                                                _buildHeaderSection(),
                                                                const SizedBox(height: 32),
                                                                _buildKPIGrid(context, isDesktop),
                                                                const SizedBox(height: 24),
                                                                _buildMiddleSection(isDesktop),
                                                                const SizedBox(height: 48),
                                                              ],
                                                            ),
                                                          ),
                                                        ),
                  ),
                  if ((_currentPage == 0 || _currentPage == 2) &&
                      ApiService.canAddMachineAsConcepteur)
                    Positioned(
                      right: 24,
                      bottom: isDesktop ? 24 : 100,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          FloatingActionButton.extended(
                            onPressed: () async {
                              final result = await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const AddMachinePage(),
                                ),
                              );
                              if (result == true) _mvc.loadGlobalStats();
                            },
                            backgroundColor: const Color(0xFF75D1FF),
                            elevation: 8,
                            icon: const Icon(
                              Icons.precision_manufacturing,
                              color: Colors.white,
                              size: 22,
                            ),
                            label: Text(
                              'Ajouter Machine',
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          FloatingActionButton.extended(
                            onPressed: () => _goTo(1),
                            backgroundColor: const Color(0xFFFF6E00),
                            elevation: 8,
                            icon: const Icon(Icons.add, color: Colors.white, size: 22),
                            label: Text(
                              'Nouveau Client',
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Sub-widgets components ---

  Widget _buildTopBar(bool isDesktop) {
    final logo = GestureDetector(
      onTap: () => Navigator.pushReplacementNamed(context, '/'),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 180),
        height: 44,
        margin: const EdgeInsets.only(left: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF6E00).withOpacity(0.12),
              blurRadius: 12,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Image.asset(
          'assets/images/abbk_logo.png',
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            height: 75,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF15193B).withOpacity(0.85),
                  const Color(0xFF1C224D).withOpacity(0.75),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(0.12), width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 15,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                const SizedBox(width: 12),
                logo,
                const SizedBox(width: 20),
                if (isDesktop)
                  Expanded(
                    child: _DashboardTopNavMenu(
                      currentPage: _currentPage,
                      conceptionInitialTab: _conceptionInitialTab,
                      onNavigate: _goTo,
                    ),
                  )
                else
                  const Spacer(),
                _buildLogoutButton(),
                const SizedBox(width: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogoutButton() {
    return Tooltip(
      message: 'Déconnexion',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _logout,
          borderRadius: BorderRadius.circular(12),
          hoverColor: Colors.redAccent.withOpacity(0.1),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: Colors.redAccent.withOpacity(0.05),
              border: Border.all(
                color: Colors.redAccent.withOpacity(0.3),
                width: 1.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.logout_rounded, color: Colors.redAccent, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Quitter',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Colors.redAccent,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Déconnexion'),
            content: const Text('Voulez-vous vraiment vous déconnecter ?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Annuler'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Se déconnecter'),
              ),
            ],
          ),
    );
    if (confirm != true || !mounted) return;
    await ApiService.clearAuth();
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/');
  }

  Widget _buildHeaderSection() {
    final canAddMachine = ApiService.canAddMachineAsConcepteur;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Supervision Globale',
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.0,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'État opérationnel du parc industriel',
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 12,
                  color: const Color(0xFFA98A7C),
                  fontWeight: FontWeight.w500,
                  letterSpacing: 2.0,
                ),
              ),
              if (!canAddMachine) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6E00).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFFF6E00).withOpacity(0.45)),
                  ),
                  child: Text(
                    'Ajout machine reserve au role Concepteur',
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFFFB692),
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF191934),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFF66BB6A),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    'Système en ligne',
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildKPIGrid(BuildContext context, bool isDesktop) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: isDesktop ? 4 : 2,
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      childAspectRatio: isDesktop ? 1.55 : 1.12,
      children: [
        GestureDetector(
          onTap: () => _goTo(2),
          child: _KPICard(
              icon: Icons.corporate_fare,
              label: 'Flux Actif',
              value: _mvc.state.isLoadingCounts ? '...' : _mvc.state.clientCount.toString(),
              title: 'Clients',
              color: const Color(0xFF75D1FF)),
        ),
        GestureDetector(
          onTap: () => _goTo(3), // Navigate to active machines page
          child: _KPICard(
              icon: Icons.precision_manufacturing,
              label: _mvc.state.isLoadingCounts
                  ? '…'
                  : '${_mvc.state.machinesEnLigneCount} en ligne',
              value: _mvc.state.isLoadingCounts ? '...' : _mvc.state.machineCount.toString(),
              title: 'Machines',
              color: const Color(0xFF66BB6A)),
        ),
        GestureDetector(
          onTap: () {
            _concepteurEmbeddedReturnPage = 6;
            _goTo(6);
          },
          child: _KPICard(
            icon: Icons.engineering_outlined,
            label: 'Conception',
            value: _mvc.state.isLoadingCounts ? '...' : _mvc.state.concepteurCount.toString(),
            title: 'Concepteur',
            color: const Color(0xFFFFB692),
            hasIndicator: true,
          ),
        ),
        _KPICard(
            icon: Icons.badge,
            label: 'Déployés',
            value: _mvc.state.isLoadingCounts ? '...' : _mvc.state.techCount.toString(),
            title: 'Techniciens',
            color: const Color(0xFFEFB1F9)),
      ],
    );
  }

  Widget _buildMiddleSection(bool isDesktop) {
    return LayoutBuilder(builder: (context, constraints) {
      if (isDesktop) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 8, child: _buildMapSection()),
            const SizedBox(width: 24),
            Expanded(flex: 4, child: _buildSecondaryMetrics()),
          ],
        );
      } else {
        return Column(
          children: [
            _buildMapSection(),
            const SizedBox(height: 24),
            _buildSecondaryMetrics(),
          ],
        );
      }
    });
  }

  Widget _buildMapSection() {
    final runningLabel = _mvc.state.isLoadingCounts
        ? '...'
        : '${_mvc.state.machinesRunningOnMap} EN TRAVAIL';

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1E2243).withOpacity(0.95),
            const Color(0xFF131730).withOpacity(0.85),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Colors.white.withOpacity(0.08),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'LOCALISATION DES SITES',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2.0,
                  ),
                ),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _mvc.state.machinesRunningOnMap > 0
                            ? const Color(0xFF66BB6A)
                            : const Color(0xFFFFB692),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      runningLabel,
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 10,
                        color: Colors.white.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(
            height: 400,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                final h = constraints.maxHeight;
                return Stack(
                  children: [
                    Positioned.fill(
                      child: Opacity(
                        opacity: 0.4,
                        child: Image.network(
                          'https://lh3.googleusercontent.com/aida-public/AB6AXuCA4fhjZmz_T0lo0lRhkkAerVw7HjTZgUmjqedY7xpGs1QAqRJjJn1qm5lLHjJLbS-_SPnef2wTl2PUQglmp89dVmZIcUY81G0clLaqDBOFoIxsXUtSZMoAHQGs9zwVXbON68J3MjHYGjrDumNqWuyospM0OTMrolz44qcC5OKqx8X9Of2KBdFiBsQFQVgRHnSdr4G5Tsdmnnk7j7V2RB7OW0M2HVURfKnNrqPlKfoTc2PoV3M7DpPaQQxsDMx4r1pK63YJOHnpHTs',
                          fit: BoxFit.cover,
                          color: Colors.white,
                          colorBlendMode: BlendMode.saturation,
                          errorBuilder: (_, __, ___) => const ColoredBox(
                            color: Color(0xFF131730),
                          ),
                        ),
                      ),
                    ),
                    if (_mvc.state.isLoadingCounts)
                      const Center(child: CircularProgressIndicator())
                    else if (_mvc.state.fleetMapMarkers.isEmpty)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            _mvc.state.machinesTracked == 0
                                ? 'Aucune machine en base'
                                : '${_mvc.state.machinesTracked} machine(s) en base · 0 en marche (statut RUNNING)\n'
                                    'Passez une machine en RUNNING pour l’afficher sur la carte.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: Colors.white.withOpacity(0.55),
                            ),
                          ),
                        ),
                      )
                    else
                      ..._mvc.state.fleetMapMarkers.map(
                        (m) => _buildFleetMapMarker(
                          marker: m,
                          mapWidth: w,
                          mapHeight: h,
                        ),
                      ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 12,
                      child: Text(
                        'Tunisie · ${_mvc.state.machinesRunningOnMap} machine(s) en marche',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.35),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  double _toDouble(dynamic v, [double fallback = 0]) {
    if (v == null) return fallback;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? fallback;
  }

  Widget _buildFleetMapMarker({
    required Map<String, dynamic> marker,
    required double mapWidth,
    required double mapHeight,
  }) {
    final top = (_toDouble(marker['top'], 0.35)).clamp(0.05, 0.92);
    final left = (_toDouble(marker['left'], 0.45)).clamp(0.05, 0.92);
    final name = (marker['name'] ?? 'Machine').toString();
    final location = (marker['location'] ?? '').toString();
    final risk = (_toDouble(marker['riskPct'], 0)).round();
    final pinColor = risk >= 70
        ? const Color(0xFFFFB4AB)
        : (risk >= 40 ? const Color(0xFFFF6E00) : const Color(0xFF66BB6A));

    return Positioned(
      top: top * mapHeight - 16,
      left: left * mapWidth - 14,
      child: Tooltip(
        message: location.isEmpty
            ? '$name · Risque $risk%'
            : '$name · $location · Risque $risk%',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.location_on, color: pinColor, size: 32),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xDD121A30),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: pinColor.withOpacity(0.6)),
              ),
              child: Text(
                name.length > 14 ? '${name.substring(0, 12)}…' : name,
                style: GoogleFonts.inter(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSecondaryMetrics() {
    return Column(
      children: [
        _MetricRow(
            label: 'RISQUE MOYEN DE PANNE',
            value: _mvc.state.isLoadingCounts ? '...' : '${_mvc.state.riskPct} %',
            icon: Icons.check_circle,
            color: _mvc.state.riskPct >= 70 ? const Color(0xFFFFB4AB) : (_mvc.state.riskPct >= 40 ? const Color(0xFFFFB692) : const Color(0xFF66BB6A))),
        const SizedBox(height: 16),
        _MetricRow(
            label: 'MACHINES STABLES',
            value: _mvc.state.isLoadingCounts ? '...' : '${_mvc.state.stablePct} %',
            icon: Icons.monitor_heart_outlined,
            color: _mvc.state.stablePct >= 70 ? const Color(0xFF66BB6A) : (_mvc.state.stablePct >= 40 ? const Color(0xFFFFB692) : const Color(0xFFFFB4AB))),
        const SizedBox(height: 16),
        _MetricRow(
            label: 'MODE DE RISQUE DOMINANT',
            value: _mvc.state.isLoadingCounts
                ? '...'
                : (_mvc.state.riskMode.length > 28
                    ? '${_mvc.state.riskMode.substring(0, 26)}…'
                    : _mvc.state.riskMode),
            icon: Icons.warning_amber_rounded,
            color: const Color(0xFF75D1FF)),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: () => _goTo(6, conceptionTab: 1),
          child: _MetricRow(
            label: 'DOCUMENTATION',
            value: _mvc.state.isLoadingCounts
                ? '...'
                : '${_mvc.state.documentCount} Doc${_mvc.state.documentCount > 1 ? 's' : ''}',
            icon: Icons.description,
            color: const Color(0xFFEFB1F9),
          ),
        ),
      ],
    );
  }

  Widget _buildMobileBottomNav() {
    return Container(
      height: 72,
      decoration: BoxDecoration(
        color: const Color(0xFF10102B).withOpacity(0.95),
        border: const Border(top: BorderSide(color: Color(0xFF32324e), width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _BottomNavItem(
            icon: Icons.dashboard_outlined,
            label: 'Accueil',
            active: _currentPage == 0,
            onTap: () => _goTo(0),
          ),
          _BottomNavItem(
            icon: Icons.precision_manufacturing_outlined,
            label: 'Machines',
            active: _currentPage == 3,
            onTap: () => _goTo(3),
          ),
          _BottomNavItem(
            icon: Icons.groups_outlined,
            label: 'Clients',
            active: _currentPage == 1 || _currentPage == 2,
            onTap: () => _goTo(2),
          ),
          _BottomNavItem(
            icon: Icons.engineering_outlined,
            label: 'Concepteurs',
            active: _currentPage == 6 || _currentPage == 10 || _currentPage == 5,
            onTap: () => _goTo(6),
          ),
          _BottomNavItem(
            icon: Icons.chat_bubble_outline,
            label: 'Messagerie',
            active: _currentPage == 7,
            onTap: () => _goTo(7),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Menu principal horizontal (ex-sidebar)
// ─────────────────────────────────────────────────────────────
class _DashboardTopNavMenu extends StatelessWidget {
  final int currentPage;
  final int conceptionInitialTab;
  final void Function(int page, {int conceptionTab}) onNavigate;

  const _DashboardTopNavMenu({
    required this.currentPage,
    required this.conceptionInitialTab,
    required this.onNavigate,
  });

  bool get _onConceptionHub =>
      currentPage == 6 && conceptionInitialTab == 0;

  bool get _onDocumentsHub =>
      currentPage == 6 && conceptionInitialTab == 1;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          _SidebarMenuTile(
            icon: Icons.dashboard_outlined,
            activeIcon: Icons.dashboard_rounded,
            label: 'Vue d\'ensemble',
            active: currentPage == 0,
            onTap: () => onNavigate(0),
          ),
          _navDivider(),
          _SidebarMenuTile(
            icon: Icons.precision_manufacturing_outlined,
            activeIcon: Icons.precision_manufacturing,
            label: 'Machines',
            active: currentPage == 3,
            onTap: () => onNavigate(3),
          ),
          _SidebarMenuTile(
            icon: Icons.groups_outlined,
            activeIcon: Icons.groups_rounded,
            label: 'Clients',
            active: currentPage == 1 || currentPage == 2,
            onTap: () => onNavigate(2),
          ),
          _navDivider(),
          _SidebarMenuTile(
            icon: Icons.engineering_outlined,
            activeIcon: Icons.engineering,
            label: 'Concepteurs',
            active: _onConceptionHub || currentPage == 10 || currentPage == 5,
            onTap: () => onNavigate(6, conceptionTab: 0),
          ),
          if (ApiService.canAddMachineAsConcepteur) ...[
            _navDivider(),
            _SidebarMenuTile(
              icon: Icons.add_circle_outline,
              activeIcon: Icons.add_circle,
              label: 'Nouvelle machine',
              accent: const Color(0xFF75D1FF),
              onTap: () => onNavigate(13),
            ),
          ],
          _navDivider(),
          _SidebarMenuTile(
            icon: Icons.chat_bubble_outline,
            activeIcon: Icons.chat_bubble_rounded,
            label: 'Messagerie',
            active: currentPage == 7,
            onTap: () => onNavigate(7),
          ),
        ],
      ),
    );
  }

  Widget _navDivider() => Container(
        width: 1,
        height: 22,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white.withOpacity(0.0),
              Colors.white.withOpacity(0.12),
              Colors.white.withOpacity(0.0),
            ],
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────
// Embedded Add Client — shows the form without its own topbar/sidebar
// ─────────────────────────────────────────────────────────────
class _EmbeddedAddClientView extends StatefulWidget {
  final VoidCallback onBack;
  const _EmbeddedAddClientView({required this.onBack});

  @override
  State<_EmbeddedAddClientView> createState() => _EmbeddedAddClientViewState();
}

class _EmbeddedAddClientViewState extends State<_EmbeddedAddClientView> {
  String? _selectedMotorType;
  bool _obscurePassword = true;
  final _companyController = TextEditingController();
  final _locationController = TextEditingController();
  final _addressController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  static const _inputBg = Color(0xFF1A1A35);
  static const _onSurface = Color(0xFFE2DFFF);
  static const _onSurfaceVariant = Color(0xFFE2BFB0);
  static const _outline = Color(0xFF594136);
  static const _primary = Color(0xFFFFB692);
  static const _primaryContainer = Color(0xFFFF6E00);
  static const _secondary = Color(0xFF75D1FF);
  static const _surface = Color(0xFF191934);
  static const _surfaceContainer = Color(0xFF1D1D38);
  static const _surfaceHigh = Color(0xFF272743);

  @override
  void dispose() {
    _companyController.dispose();
    _locationController.dispose();
    _addressController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 768),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Breadcrumb back button
              Row(
                children: [
                  InkWell(
                    onTap: widget.onBack,
                    borderRadius: BorderRadius.circular(8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.arrow_back_ios,
                            color: Color(0xFFE2BFB0), size: 14),
                        const SizedBox(width: 4),
                        Text('Dashboard',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: const Color(0xFFE2BFB0),
                              letterSpacing: 1,
                            )),
                      ],
                    ),
                  ),
                  Text(' / ',
                      style: GoogleFonts.inter(
                          fontSize: 12,
                          color: const Color(0xFFE2BFB0).withOpacity(0.4))),
                  Text('Nouveau Client',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: _primaryContainer,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      )),
                ],
              ),
              const SizedBox(height: 24),

              // Main card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(40),
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: _outline.withOpacity(0.1)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.4),
                      blurRadius: 40,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Text(
                      'Ajouter un Nouveau Client',
                      style: GoogleFonts.inter(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: _onSurface,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'INITIALISATION DU PROTOCOLE D\'ENREGISTREMENT',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 10,
                        color: _onSurfaceVariant,
                        letterSpacing: 2.5,
                      ),
                    ),
                    const SizedBox(height: 40),

                    // Company name
                    _label('Nom de l\'entreprise'),
                    const SizedBox(height: 8),
                    _inputField(
                        controller: _companyController,
                        hint: 'EX: KINETIC CORP'),
                    const SizedBox(height: 32),

                    // Motor type
                    _label('Type de Moteur Industriel'),
                    const SizedBox(height: 12),
                    _buildMotorGrid(),
                    const SizedBox(height: 32),

                    // Location
                    _buildLocationRow(),
                    const SizedBox(height: 32),

                    // Address
                    _label('Adresse Complète'),
                    const SizedBox(height: 8),
                    _addressField(),
                    const SizedBox(height: 32),

                    // Credentials divider
                    Container(
                      padding: const EdgeInsets.only(top: 24),
                      decoration: const BoxDecoration(
                        border: Border(
                            top: BorderSide(
                                color: Color(0x1A594136))),
                      ),
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Identifiants de Connexion',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: _secondary,
                              letterSpacing: 3,
                            ),
                          ),
                          const SizedBox(height: 24),
                          _label('Adresse Email Professionnelle'),
                          const SizedBox(height: 8),
                          _emailRow(),
                          const SizedBox(height: 24),
                          _label('Mot de Passe de Sécurité'),
                          const SizedBox(height: 8),
                          _passwordRow(),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Actions
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: widget.onBack,
                          child: Text(
                            'Annuler',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: _onSurfaceVariant,
                              letterSpacing: 2,
                            ),
                          ),
                        ),
                        const SizedBox(width: 24),
                        InkWell(
                          onTap: _onSubmit,
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 32, vertical: 16),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  _primaryContainer,
                                  _primary
                                ],
                              ),
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: [
                                BoxShadow(
                                  color: _primaryContainer
                                      .withOpacity(0.25),
                                  blurRadius: 20,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Text(
                              'CRÉER LE CLIENT',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: 2,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Status bento
              Row(
                children: [
                  Expanded(
                      child: _bentoCard('SYS_AUTH',
                          'Encryption Active', _secondary)),
                  const SizedBox(width: 12),
                  Expanded(
                      child: _bentoCard(
                          'INSTANCE_LOC', 'Global Node', _onSurface)),
                  const SizedBox(width: 12),
                  Expanded(
                      child: _bentoCard(
                          'PROTO_VER', 'v4.2.0-STABLE', _onSurface)),
                ],
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMotorGrid() {
    final motors = [
      (id: 'ac', icon: Icons.electrical_services, label: 'Moteur à Induction AC'),
      (id: 'pm', icon: Icons.filter_tilt_shift, label: 'Synchrone Aimants Permanents'),
      (id: 'dc', icon: Icons.bolt, label: 'Courant Continu (DC)'),
      (id: 'sv', icon: Icons.settings_input_component, label: 'Servomoteur Haute Précision'),
    ];
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 4,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 0.85,
      children: motors
          .map((m) => GestureDetector(
                onTap: () =>
                    setState(() => _selectedMotorType = m.id),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _selectedMotorType == m.id
                        ? _primaryContainer.withOpacity(0.05)
                        : _inputBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _selectedMotorType == m.id
                          ? _primaryContainer
                          : _outline.withOpacity(0.2),
                      width: _selectedMotorType == m.id ? 1.5 : 1,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(m.icon,
                          color: _selectedMotorType == m.id
                              ? _primary
                              : _onSurfaceVariant.withOpacity(0.5),
                          size: 26),
                      const SizedBox(height: 8),
                      Text(
                        m.label,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 9,
                          color: _selectedMotorType == m.id
                              ? _onSurface
                              : _onSurfaceVariant.withOpacity(0.6),
                          fontWeight:
                              _selectedMotorType == m.id
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
              ))
          .toList(),
    );
  }

  Widget _buildLocationRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _label('Localisation'),
              const SizedBox(height: 8),
              _inputField(
                  controller: _locationController,
                  hint: 'City, Country'),
            ],
          ),
        ),
        const SizedBox(width: 24),
        Expanded(
          child: Container(
            height: 90,
            decoration: BoxDecoration(
              color: _surfaceHigh,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: _outline.withOpacity(0.1)),
            ),
            child: Center(
              child: Icon(
                Icons.location_on_outlined,
                color: _secondary.withOpacity(0.4),
                size: 32,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _emailRow() {
    return Container(
      decoration: BoxDecoration(
          border: Border(
              bottom: BorderSide(
                  color: _outline.withOpacity(0.3)))),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              style: GoogleFonts.spaceGrotesk(
                  color: _onSurface, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'name@company.com',
                hintStyle: GoogleFonts.spaceGrotesk(
                  color: _onSurfaceVariant.withOpacity(0.3),
                ),
                border: InputBorder.none,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          Icon(Icons.alternate_email,
              color: _onSurfaceVariant.withOpacity(0.4),
              size: 18),
        ],
      ),
    );
  }

  Widget _passwordRow() {
    return Container(
      decoration: BoxDecoration(
          border: Border(
              bottom: BorderSide(
                  color: _outline.withOpacity(0.3)))),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              style: GoogleFonts.spaceGrotesk(
                color: _onSurface,
                fontSize: 14,
                letterSpacing: _obscurePassword ? 4 : 0,
              ),
              decoration: InputDecoration(
                hintText: '••••••••••••',
                hintStyle: GoogleFonts.spaceGrotesk(
                  color: _onSurfaceVariant.withOpacity(0.3),
                  letterSpacing: 4,
                ),
                border: InputBorder.none,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          InkWell(
            onTap: () =>
                setState(() => _obscurePassword = !_obscurePassword),
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                _obscurePassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: _onSurfaceVariant.withOpacity(0.5),
                size: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _addressField() {
    return Container(
      decoration: BoxDecoration(
          border: Border(
              bottom: BorderSide(
                  color: _outline.withOpacity(0.3)))),
      child: TextField(
        controller: _addressController,
        maxLines: 2,
        style: GoogleFonts.spaceGrotesk(
            color: _onSurface, fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Saisir l\'adresse de siège social...',
          hintStyle: GoogleFonts.spaceGrotesk(
            color: _onSurfaceVariant.withOpacity(0.3),
          ),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  Widget _inputField(
      {required TextEditingController controller,
      required String hint}) {
    return Container(
      decoration: BoxDecoration(
          border: Border(
              bottom: BorderSide(
                  color: _outline.withOpacity(0.3)))),
      child: TextField(
        controller: controller,
        style: GoogleFonts.spaceGrotesk(
            color: _onSurface, fontSize: 15),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: GoogleFonts.spaceGrotesk(
            color: _onSurfaceVariant.withOpacity(0.3),
            fontSize: 15,
          ),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 0),
        child: Text(
          text.toUpperCase(),
          style: GoogleFonts.inter(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: _onSurfaceVariant,
            letterSpacing: 2,
          ),
        ),
      );

  Widget _bentoCard(
      String label, String value, Color valueColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surfaceContainer,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
            color: _outline.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 9,
                color: _onSurfaceVariant.withOpacity(0.6),
              )),
          const SizedBox(height: 4),
          Text(
            value.toUpperCase(),
            style: GoogleFonts.spaceGrotesk(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onSubmit() async {
    if (_companyController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez renseigner le nom de l\'entreprise')),
      );
      return;
    }
    
    final payload = {
      'name': _companyController.text,
      'location': _locationController.text,
      'address': _addressController.text,
      'email': _emailController.text,
      'password': _passwordController.text,
      'motorType': _selectedMotorType ?? 'ac-induction',
    };

    try {
      await ApiService.addClient(payload);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Client ajouté avec succès !', style: TextStyle(color: Colors.white)), backgroundColor: Colors.green),
        );
        widget.onBack();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur API: $e', style: const TextStyle(color: Colors.white)), backgroundColor: Colors.red),
        );
      }
    }
  }
}


class _SidebarMenuTile extends StatefulWidget {
  final IconData icon;
  final IconData? activeIcon;
  final String label;
  final bool active;
  final Color? accent;
  final VoidCallback onTap;

  const _SidebarMenuTile({
    required this.icon,
    this.activeIcon,
    required this.label,
    this.active = false,
    this.accent,
    required this.onTap,
  });

  @override
  State<_SidebarMenuTile> createState() => _SidebarMenuTileState();
}

class _SidebarMenuTileState extends State<_SidebarMenuTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final highlight = widget.accent ?? const Color(0xFFFF6E00);
    final iconData = widget.active && widget.activeIcon != null
        ? widget.activeIcon!
        : widget.icon;
    final isActive = widget.active;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOutExpo,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: isActive
                  ? LinearGradient(
                      colors: [
                        highlight.withOpacity(0.25),
                        highlight.withOpacity(0.08),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : _hovered
                      ? LinearGradient(
                          colors: [
                            Colors.white.withOpacity(0.08),
                            Colors.white.withOpacity(0.02),
                          ],
                        )
                      : null,
              border: Border.all(
                color: isActive
                    ? highlight.withOpacity(0.5)
                    : _hovered
                        ? Colors.white.withOpacity(0.15)
                        : Colors.transparent,
                width: 1.5,
              ),
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: highlight.withOpacity(0.2),
                        blurRadius: 15,
                        spreadRadius: -2,
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isActive)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(right: 10),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: highlight,
                      boxShadow: [
                        BoxShadow(
                          color: highlight,
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                Icon(
                  iconData,
                  color: isActive
                      ? highlight
                      : _hovered
                          ? Colors.white
                          : const Color(0xFF9AA3B8),
                  size: 20,
                ),
                const SizedBox(width: 10),
                Text(
                  widget.label,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                    color: isActive
                        ? Colors.white
                        : _hovered
                            ? Colors.white
                            : const Color(0xFF9AA3B8),
                    letterSpacing: isActive ? 0.2 : 0,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// KPI Card Widget
class _KPICard extends StatefulWidget {
  final IconData icon;
  final String label;
  final String value;
  final String title;
  final Color color;
  final bool hasIndicator;

  const _KPICard({
    required this.icon,
    required this.label,
    required this.value,
    required this.title,
    required this.color,
    this.hasIndicator = false,
  });

  @override
  State<_KPICard> createState() => _KPICardState();
}

class _KPICardState extends State<_KPICard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        transform: _isHovered ? (Matrix4.identity()..translate(0, -6, 0)) : Matrix4.identity(),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFF1E2243).withOpacity(0.95),
              const Color(0xFF131730).withOpacity(0.85),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _isHovered ? widget.color.withOpacity(0.6) : (widget.hasIndicator ? const Color(0xFFFF6E00) : widget.color.withOpacity(0.18)),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: _isHovered ? widget.color.withOpacity(0.2) : Colors.black.withOpacity(0.3),
              blurRadius: _isHovered ? 24 : 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: widget.color.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(widget.icon, color: widget.color, size: 22),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: widget.color.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: widget.color.withOpacity(0.25), width: 1),
                    ),
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: widget.color,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                widget.value,
                style: GoogleFonts.inter(
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: -1,
                  shadows: [
                    Shadow(
                      color: widget.color.withOpacity(0.4),
                      blurRadius: 10,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.title.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 10,
                color: const Color(0xFFA98A7C).withOpacity(0.85),
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Simple Metric Row
class _MetricRow extends StatefulWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _MetricRow({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  State<_MetricRow> createState() => _MetricRowState();
}

class _MetricRowState extends State<_MetricRow> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        transform: _isHovered ? (Matrix4.identity()..translate(4, 0, 0)) : Matrix4.identity(),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFF1E2243).withOpacity(0.95),
              const Color(0xFF131730).withOpacity(0.85),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _isHovered ? widget.color.withOpacity(0.5) : widget.color.withOpacity(0.18),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: _isHovered ? widget.color.withOpacity(0.1) : Colors.black.withOpacity(0.2),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.label.toUpperCase(),
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 10,
                      color: const Color(0xFFA98A7C),
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.value,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: widget.color,
                      shadows: [
                        Shadow(
                          color: widget.color.withOpacity(0.3),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: widget.color.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(widget.icon, color: widget.color, size: 26),
            ),
          ],
        ),
      ),
    );
  }
}

// Bottom Nav Item Widget
class _BottomNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _BottomNavItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: active ? const Color(0xFFFF6E00) : const Color(0xFFE2BFB0).withOpacity(0.6), size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 10,
                fontWeight: active ? FontWeight.bold : FontWeight.normal,
                color: active ? const Color(0xFFFF6E00) : const Color(0xFFE2BFB0).withOpacity(0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
