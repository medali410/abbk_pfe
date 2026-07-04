import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'client_list_view.dart';
import 'admin_machines_hub_page.dart';
import 'active_machines_page.dart';
import 'add_technician_page.dart';
import 'add_conception_page.dart';
import 'add_concepteur_page.dart';
import 'conception_list_page.dart';
import 'add_maintenance_agent_page.dart';
import 'maintenance_module_page.dart';
import 'add_machine_page.dart';
import 'widgets/message_equipe_view.dart';
import 'all_missions_history_page.dart';
import 'services/api_service.dart';
import 'mvc/controllers/dashboard_controller.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  int _currentPage = 0;
  bool _isDarkMode = true;

  // ── Notification badge ────────────────────────────────────────
  int _unreadCount = 0;
  Timer? _notifTimer;

  Color get tc => _isDarkMode ? Colors.white : const Color(0xFF1A1207);
  Color get subTc => _isDarkMode ? const Color(0xFFA7B1C6) : const Color(0xFF9A5B20);
  Color get cardBg => _isDarkMode ? const Color(0x55182236) : const Color(0xFFFFFFFF);
  Color get cardBorder => _isDarkMode ? const Color(0x33FFFFFF) : const Color(0xFFCD7F32);
  Color get headerBg => _isDarkMode ? const Color(0x33121A30) : const Color(0xFFFFFFFF);

  // Additional theme color getters
  Color get _primary => _isDarkMode ? const Color(0xFFFFB692) : const Color(0xFFB8860B);
  Color get _secondary => _isDarkMode ? const Color(0xFF75D1FF) : const Color(0xFF8B5E3C);
  Color get _onSurface => _isDarkMode ? const Color(0xFFE2DFFF) : const Color(0xFF332A21);
  Color get _onSurfaceVariant => _isDarkMode ? const Color(0xFFE2BFB0) : const Color(0xFF9AA3B8);
  Color get _outlineVariant => _isDarkMode ? const Color(0xFF594136) : const Color(0xFFCCCCCC);
  Color get _green => const Color(0xFF66BB6A);
  Color get _errorColor => _isDarkMode ? const Color(0xFFFFB4AB) : const Color(0xFFFF6E00);
  Color get _orange => const Color(0xFFFF6E00);

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
      _startNotifPolling();
    });
  }

  void _startNotifPolling() {
    _notifTimer?.cancel();
    _pollUnreadCount();
    _notifTimer = Timer.periodic(const Duration(seconds: 30), (_) => _pollUnreadCount());
  }

  Future<void> _pollUnreadCount() async {
    try {
      final count = await ApiService.getUnreadMessageCount();
      if (mounted) setState(() => _unreadCount = count);
    } catch (_) {}
  }

  void _onMvcUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _notifTimer?.cancel();
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

  void _openDetail(String id, String name, {String? clientId, String? location}) {}

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 992;

    return Scaffold(
      bottomNavigationBar: isDesktop ? null : _buildMobileBottomNav(),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: _isDarkMode
                ? const [Color(0xFF0B1020), Color(0xFF141D34), Color(0xFF1A1730)]
                : const [Color(0xFFF5EDE0), Color(0xFFEDE3D3), Color(0xFFE5D9C5)],
          ),
        ),
        child: Column(
          children: [
            _buildTopBar(isDesktop),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: _currentPage == 6
                                          ? ConceptionListPage(
                                              key: ValueKey('conception-tab-$_conceptionInitialTab'),
                                              initialTabIndex: _conceptionInitialTab,
                                              isDarkMode: _isDarkMode,
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
                                          : _currentPage == 2
                                              ? EmbeddedClientListView(
                                                  onAddClient: () => _goTo(1),
                                                  isDarkMode: _isDarkMode,
                                                )
                                              : _currentPage == 1
                                                  ? _EmbeddedAddClientView(
                                                      onBack: () => _goTo(2),
                                                      isDarkMode: _isDarkMode,
                                                    )
                                                  : _currentPage == 3
                                                      ? AdminMachinesHubPage(
                                                          isDarkMode: _isDarkMode,
                                                        )
                                                      : _currentPage == 8
                                                          ? AddConceptionPage(onEmbeddedBack: () => _goTo(6))
                                                          : _currentPage == 10
                                                              ? AddConcepteurPage(
                                                                  key: ValueKey(
                                                                    'concepteur-${_pendingConcepteurEdit?['id'] ?? 'create'}',
                                                                  ),
                                                                  initialData: _pendingConcepteurEdit,
                                                                  isDarkMode: _isDarkMode,
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
                                                                      : _currentPage == 14
                                                                          ? AllMissionsHistoryPage(isDarkMode: _isDarkMode)
                                                                          : _currentPage == 7
                                                                              ? MessageEquipeView(embedded: true, isDarkMode: _isDarkMode)
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
                            icon: Icon(Icons.refresh, color: _secondary),
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
                colors: _isDarkMode
                    ? [
                        const Color(0xFF15193B).withOpacity(0.85),
                        const Color(0xFF1C224D).withOpacity(0.75),
                      ]
                    : [
                        const Color(0xFFFFFFFF).withOpacity(0.95),
                        const Color(0xFFFFF8EE).withOpacity(0.90),
                      ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _isDarkMode
                    ? Colors.white.withOpacity(0.12)
                    : const Color(0xFFCD7F32).withOpacity(0.35),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: _isDarkMode
                      ? Colors.black.withOpacity(0.3)
                      : const Color(0xFFB87333).withOpacity(0.15),
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
                      isDarkMode: _isDarkMode,
                    ),
                  )
                else
                  const Spacer(),
                IconButton(
                  icon: Icon(
                    _isDarkMode ? Icons.wb_sunny_rounded : Icons.nightlight_round,
                    color: _isDarkMode ? Colors.amber : const Color(0xFF7A4B29),
                    size: 22,
                  ),
                  tooltip: _isDarkMode ? 'Mode Jour' : 'Mode Nuit',
                  onPressed: () {
                    setState(() {
                      _isDarkMode = !_isDarkMode;
                    });
                  },
                ),
                const SizedBox(width: 8),
                _buildNotifBadge(),
                const SizedBox(width: 4),
                _buildLogoutButton(),
                const SizedBox(width: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNotifBadge() {
    return Tooltip(
      message: 'Nouveaux messages',
      child: GestureDetector(
        onTap: () {
          ApiService.markChatNotificationsAsRead();
          setState(() {
            _currentPage = 7; // 7 = Messagerie
            _unreadCount = 0;
          });
        },
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _isDarkMode
                    ? Colors.white.withOpacity(0.08)
                    : const Color(0xFFCD7F32).withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _isDarkMode
                      ? Colors.white.withOpacity(0.15)
                      : const Color(0xFFCD7F32).withOpacity(0.4),
                ),
              ),
              child: Icon(
                Icons.notifications_outlined,
                color: _isDarkMode ? const Color(0xFFFFB692) : const Color(0xFF8B5E3C),
                size: 20,
              ),
            ),
            if (_unreadCount > 0)
              Positioned(
                top: -4,
                right: -4,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Colors.redAccent,
                    shape: BoxShape.circle,
                  ),
                  constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                  child: Text(
                    _unreadCount > 99 ? '99+' : '$_unreadCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
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
                  color: tc,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'État opérationnel du parc industriel',
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 12,
                  color: subTc,
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
              color: headerBg,
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
                      color: tc,
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
      childAspectRatio: isDesktop ? 1.55 : 1.0,
      children: [
        GestureDetector(
          onTap: () => _goTo(2),
          child: _KPICard(
              isDarkMode: _isDarkMode,
              icon: Icons.corporate_fare,
              label: 'Flux Actif',
              value: _mvc.state.isLoadingCounts ? '...' : _mvc.state.clientCount.toString(),
              title: 'Clients',
              color: const Color(0xFF75D1FF)),
        ),
        GestureDetector(
          onTap: () => _goTo(3), // Navigate to active machines page
          child: _KPICard(
              isDarkMode: _isDarkMode,
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
            isDarkMode: _isDarkMode,
            icon: Icons.engineering_outlined,
            label: 'Conception',
            value: _mvc.state.isLoadingCounts ? '...' : _mvc.state.concepteurCount.toString(),
            title: 'Concepteur',
            color: const Color(0xFFFFB692),
            hasIndicator: true,
          ),
        ),
        _KPICard(
            isDarkMode: _isDarkMode,
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
            colors: _isDarkMode
                ? [
                    const Color(0xFF1E2243).withOpacity(0.95),
                    const Color(0xFF131730).withOpacity(0.85),
                  ]
                : [
                    const Color(0xFFFFF8F0).withOpacity(0.98),
                    const Color(0xFFF5E0C3).withOpacity(0.92),
                  ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _isDarkMode
                ? Colors.white.withOpacity(0.08)
                : const Color(0xFFCD7F32).withOpacity(0.3),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 15,
              offset: const Offset(0, 4),
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
                  color: _isDarkMode
                      ? Colors.white.withOpacity(0.08)
                      : const Color(0xFFCD7F32).withOpacity(0.2),
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
                    color: _isDarkMode ? Colors.white : const Color(0xFF4B3B2A),
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
                        color: _isDarkMode
                            ? Colors.white.withOpacity(0.7)
                            : const Color(0xFFB87333).withOpacity(0.8),
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
                      Center(child: CircularProgressIndicator(color: _secondary))
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
                              color: _isDarkMode
                                  ? Colors.white.withOpacity(0.55)
                                  : const Color(0xFF4B3B2A).withOpacity(0.7),
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
                          color: _isDarkMode
                              ? Colors.white.withOpacity(0.35)
                              : const Color(0xFF4B3B2A).withOpacity(0.55),
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
            isDarkMode: _isDarkMode,
            label: 'RISQUE MOYEN DE PANNE',
            value: _mvc.state.isLoadingCounts ? '...' : '${_mvc.state.riskPct} %',
            icon: Icons.check_circle,
            color: _mvc.state.riskPct >= 70 ? const Color(0xFFFFB4AB) : (_mvc.state.riskPct >= 40 ? const Color(0xFFFFB692) : const Color(0xFF66BB6A))),
        const SizedBox(height: 16),
        _MetricRow(
            isDarkMode: _isDarkMode,
            label: 'MACHINES STABLES',
            value: _mvc.state.isLoadingCounts ? '...' : '${_mvc.state.stablePct} %',
            icon: Icons.monitor_heart_outlined,
            color: _mvc.state.stablePct >= 70 ? const Color(0xFF66BB6A) : (_mvc.state.stablePct >= 40 ? const Color(0xFFFFB692) : const Color(0xFFFFB4AB))),
        const SizedBox(height: 16),
        _MetricRow(
            isDarkMode: _isDarkMode,
            label: 'MODE DE RISQUE DOMINANT',
            value: _mvc.state.isLoadingCounts
                ? '...'
                : (_mvc.state.riskMode.length > 28
                    ? '${_mvc.state.riskMode.substring(0, 26)}…'
                    : _mvc.state.riskMode),
            icon: Icons.warning_amber_rounded,
            color: const Color(0xFF75D1FF)),
      ],
    );
  }

  Widget _buildMobileBottomNav() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(36),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              height: 74,
              decoration: BoxDecoration(
                color: _isDarkMode
                    ? const Color(0xFF1E2243).withOpacity(0.9)
                    : const Color(0xFFFFFFFF).withOpacity(0.95),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _isDarkMode
                      ? Colors.white.withOpacity(0.08)
                      : const Color(0xFFCD7F32).withOpacity(0.3),
                  width: 1.5,
                ),
                boxShadow: _isDarkMode
                    ? null
                    : [
                        BoxShadow(
                          color: const Color(0xFFB87333).withOpacity(0.12),
                          blurRadius: 12,
                          offset: const Offset(0, -2),
                        ),
                      ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _BottomNavItem(
                    icon: Icons.dashboard_rounded,
                    label: 'Accueil',
                    active: _currentPage == 0,
                    onTap: () => _goTo(0),
                  ),
                  _BottomNavItem(
                    icon: Icons.precision_manufacturing_rounded,
                    label: 'Machines',
                    active: _currentPage == 3,
                    onTap: () => _goTo(3),
                  ),
                  _BottomNavItem(
                    icon: Icons.groups_rounded,
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
                    icon: Icons.chat_bubble_rounded,
                    label: 'Messagerie',
                    active: _currentPage == 7,
                    onTap: () => _goTo(7),
                  ),
                ],
              ),
            ),
          ),
        ),
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
  final bool isDarkMode;

  const _DashboardTopNavMenu({
    required this.currentPage,
    required this.conceptionInitialTab,
    required this.onNavigate,
    required this.isDarkMode,
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
            isDarkMode: isDarkMode,
          ),
          _navDivider(),
          _SidebarMenuTile(
            icon: Icons.precision_manufacturing_outlined,
            activeIcon: Icons.precision_manufacturing,
            label: 'Machines',
            active: currentPage == 3,
            onTap: () => onNavigate(3),
            isDarkMode: isDarkMode,
          ),
          _SidebarMenuTile(
            icon: Icons.groups_outlined,
            activeIcon: Icons.groups_rounded,
            label: 'Clients',
            active: currentPage == 1 || currentPage == 2,
            onTap: () => onNavigate(2),
            isDarkMode: isDarkMode,
          ),
          _navDivider(),
          _SidebarMenuTile(
            icon: Icons.engineering_outlined,
            activeIcon: Icons.engineering,
            label: 'Concepteurs',
            active: _onConceptionHub || currentPage == 10 || currentPage == 5,
            onTap: () => onNavigate(6, conceptionTab: 0),
            isDarkMode: isDarkMode,
          ),
          if (ApiService.canAddMachineAsConcepteur) ...[
            _navDivider(),
            _SidebarMenuTile(
              icon: Icons.add_circle_outline,
              activeIcon: Icons.add_circle,
              label: 'Nouvelle machine',
              accent: const Color(0xFF75D1FF),
              onTap: () => onNavigate(13),
              isDarkMode: isDarkMode,
            ),
          ],
          _navDivider(),
          _SidebarMenuTile(
            icon: Icons.history_rounded,
            activeIcon: Icons.history_rounded,
            label: 'Missions',
            active: currentPage == 14,
            onTap: () => onNavigate(14),
            isDarkMode: isDarkMode,
          ),
          _navDivider(),
          _SidebarMenuTile(
            icon: Icons.chat_bubble_outline,
            activeIcon: Icons.chat_bubble_rounded,
            label: 'Messagerie',
            active: currentPage == 7,
            onTap: () => onNavigate(7),
            isDarkMode: isDarkMode,
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
            colors: isDarkMode
                ? [
                    Colors.white.withOpacity(0.0),
                    Colors.white.withOpacity(0.12),
                    Colors.white.withOpacity(0.0),
                  ]
                : [
                    const Color(0xFFCD7F32).withOpacity(0.0),
                    const Color(0xFFCD7F32).withOpacity(0.35),
                    const Color(0xFFCD7F32).withOpacity(0.0),
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
  final bool isDarkMode;
  const _EmbeddedAddClientView({required this.onBack, required this.isDarkMode});

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

  bool get _isDarkMode => widget.isDarkMode;
  Color get _inputBg => _isDarkMode ? Color(0xFF1A1A35) : Color(0xFFFCFAF7);
  Color get _onSurface => _isDarkMode ? Color(0xFFE2DFFF) : Color(0xFF2D1F0E);
  Color get _onSurfaceVariant => _isDarkMode ? Color(0xFFE2BFB0) : Color(0xFF594136);
  Color get _outline => _isDarkMode ? Color(0xFF594136) : Color(0xFFB87333);
  Color get _primary => _isDarkMode ? Color(0xFFFFB692) : Color(0xFFB87333);
  Color get _primaryContainer => _isDarkMode ? Color(0xFFFF6E00) : Color(0xFFFFD700);
  Color get _secondary => _isDarkMode ? Color(0xFF75D1FF) : Color(0xFFB87333);
  Color get _surface => _isDarkMode ? Color(0xFF191934) : Color(0xFFF8F5EF);
  Color get _surfaceContainer => _isDarkMode ? Color(0xFF1D1D38) : Color(0xFFF0E5D8);
  Color get _surfaceHigh => _isDarkMode ? Color(0xFF272743) : Color(0xFFECE4D5);

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
                              gradient: LinearGradient(
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
  final bool isDarkMode;

  const _SidebarMenuTile({
    required this.icon,
    this.activeIcon,
    required this.label,
    this.active = false,
    this.accent,
    required this.onTap,
    required this.isDarkMode,
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
                            widget.isDarkMode ? Colors.white.withOpacity(0.08) : const Color(0xFFB87333).withOpacity(0.12),
                            widget.isDarkMode ? Colors.white.withOpacity(0.02) : const Color(0xFFB87333).withOpacity(0.03),
                          ],
                        )
                      : null,
              border: Border.all(
                color: isActive
                    ? highlight.withOpacity(0.5)
                    : _hovered
                        ? (widget.isDarkMode ? Colors.white.withOpacity(0.15) : const Color(0xFFCD7F32).withOpacity(0.25))
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
                          ? (widget.isDarkMode ? Colors.white : const Color(0xFF4B3B2A))
                          : (widget.isDarkMode ? const Color(0xFF9AA3B8) : const Color(0xFF7A4F2E)),
                  size: 20,
                ),
                const SizedBox(width: 10),
                Text(
                  widget.label,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                    color: isActive
                        ? (widget.isDarkMode ? Colors.white : const Color(0xFF2D1F0E))
                        : _hovered
                            ? (widget.isDarkMode ? Colors.white : const Color(0xFF4B3B2A))
                            : (widget.isDarkMode ? const Color(0xFF9AA3B8) : const Color(0xFF7A4F2E)),
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
  final bool isDarkMode;

  const _KPICard({
    required this.icon,
    required this.label,
    required this.value,
    required this.title,
    required this.color,
    required this.isDarkMode,
    this.hasIndicator = false,
  });

  @override
  State<_KPICard> createState() => _KPICardState();
}

class _KPICardState extends State<_KPICard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final darkGrad = [
      const Color(0xFF1E2243).withOpacity(0.95),
      const Color(0xFF131730).withOpacity(0.85),
    ];
    final lightGrad = [
      const Color(0xFFFFFFFF),
      const Color(0xFFFFF8EE),
    ];
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        transform: _isHovered ? (Matrix4.identity()..translate(0, -6, 0)) : Matrix4.identity(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: widget.isDarkMode ? darkGrad : lightGrad,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _isHovered
                ? widget.color.withOpacity(0.6)
                : widget.isDarkMode
                    ? (widget.hasIndicator ? const Color(0xFFFF6E00) : widget.color.withOpacity(0.18))
                    : (widget.hasIndicator ? const Color(0xFFFF6E00) : const Color(0xFFCD7F32).withOpacity(0.3)),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: _isHovered
                  ? widget.color.withOpacity(0.25)
                  : widget.isDarkMode
                      ? Colors.black.withOpacity(0.3)
                      : const Color(0xFFB87333).withOpacity(0.18),
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
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: widget.color.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(widget.icon, color: widget.color, size: 20),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                widget.value,
                style: GoogleFonts.inter(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  color: widget.isDarkMode ? Colors.white : const Color(0xFF2D1F0E),
                  letterSpacing: -1,
                  shadows: widget.isDarkMode
                      ? [
                          Shadow(
                            color: widget.color.withOpacity(0.4),
                            blurRadius: 10,
                          ),
                        ]
                      : null,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              widget.title.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 10,
                color: widget.isDarkMode
                    ? const Color(0xFFA98A7C).withOpacity(0.85)
                    : const Color(0xFF7A4F2E),
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
  final bool isDarkMode;

  const _MetricRow({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.isDarkMode,
  });

  @override
  State<_MetricRow> createState() => _MetricRowState();
}

class _MetricRowState extends State<_MetricRow> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final darkGrad = [
      const Color(0xFF1E2243).withOpacity(0.95),
      const Color(0xFF131730).withOpacity(0.85),
    ];
    final lightGrad = [
      const Color(0xFFFFFFFF),
      const Color(0xFFFFF8EE),
    ];
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
            colors: widget.isDarkMode ? darkGrad : lightGrad,
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
              color: _isHovered
                  ? widget.color.withOpacity(0.1)
                  : (widget.isDarkMode ? Colors.black.withOpacity(0.2) : const Color(0xFFB87333).withOpacity(0.08)),
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
                      color: widget.isDarkMode
                          ? const Color(0xFFA98A7C)
                          : const Color(0xFF7A4F2E),
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
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          color: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: active
                    ? BoxDecoration(
                        color: const Color(0xFFFF6E00).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                      )
                    : null,
                child: Icon(
                  icon,
                  color: active ? const Color(0xFFFF6E00) : const Color(0xFF8B7355).withOpacity(0.65),
                  size: 24,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 10,
                  fontWeight: active ? FontWeight.bold : FontWeight.normal,
                  color: active ? const Color(0xFFFF6E00) : const Color(0xFF8B7355).withOpacity(0.65),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
