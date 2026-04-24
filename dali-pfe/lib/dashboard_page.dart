import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'machine_detail_ai_page.dart';
import 'client_list_view.dart';
import 'active_machines_page.dart';
import 'project_team_page.dart';
import 'add_technician_page.dart';
import 'add_conception_page.dart';
import 'add_concepteur_page.dart';
import 'conception_list_page.dart';
import 'add_maintenance_agent_page.dart';
import 'maintenance_module_page.dart';
import 'services/api_service.dart';

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
  // 6 = conception hub | 8 = add document conception | 9 = (libre) | 10 = add concepteur | 11 = add maintenance agent | 12 = diagnostic panne
  int _currentPage = 0;
  /// Cible du retour depuis [AddConcepteurPage] (4 = répertoire équipe, 6 = hub conception).
  int _concepteurEmbeddedReturnPage = 6;
  Map<String, dynamic>? _pendingConcepteurEdit;
  Map<String, dynamic>? _pendingMaintenanceEdit;
  Map<String, dynamic>? _pendingTechnicianEdit;
  
  int _clientCount = 0;
  int _machineCount = 0;
  int _techCount = 0;
  int _riskPct = 0;
  int _stablePct = 100;
  String _riskMode = 'Aucun risque majeur';
  bool _isLoadingCounts = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _requireAuthSession());
    _fetchGlobalStats();
  }

  /// Évite un dashboard « fantôme » (ex. route /dashboard sans login) sans jeton API.
  Future<void> _requireAuthSession() async {
    await ApiService.ensureAuthTokenLoaded();
    if (!mounted) return;
    if ((ApiService.authToken ?? '').isEmpty) {
      Navigator.pushReplacementNamed(context, '/');
    }
  }

  Future<void> _fetchGlobalStats() async {
    try {
      final clients = await ApiService.getClients();
      final machines = await ApiService.getMachines();
      final techs = await ApiService.getTechnicians();
      final riskData = await _computeRiskStats(machines);
      if (mounted) {
        setState(() {
          _clientCount = clients.length;
          _machineCount = machines.length;
          _techCount = techs.length;
          _riskPct = riskData.riskPct;
          _stablePct = riskData.stablePct;
          _riskMode = riskData.riskMode;
          _isLoadingCounts = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingCounts = false);
    }
  }

  String _extractMachineId(Map<String, dynamic> m) {
    return (m['id'] ?? m['machineId'] ?? m['_id'] ?? '').toString();
  }

  double _toDouble(dynamic v, [double fallback = 0]) {
    if (v == null) return fallback;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? fallback;
  }

  int _riskFromTelemetry(Map<String, dynamic>? latest) {
    if (latest == null) return 0;
    final metricsRaw = latest['metrics'];
    Map<String, dynamic>? metrics;
    if (metricsRaw is Map<String, dynamic>) {
      metrics = metricsRaw;
    } else if (metricsRaw is Map) {
      metrics = Map<String, dynamic>.from(metricsRaw);
    }

    final direct = latest['prob_panne'] ?? latest['failureProbability'] ?? latest['panne_probability'] ?? latest['scenarioProbPanne'];
    if (direct != null) {
      final d = _toDouble(direct, 0);
      return d <= 1 ? (d * 100).round().clamp(0, 100) : d.round().clamp(0, 100);
    }

    final t = _toDouble(latest['temperature'] ?? metrics?['thermal'], 0);
    final p = _toDouble(latest['pressure'] ?? metrics?['pressure'], 0);
    final v = _toDouble(latest['vibration'] ?? metrics?['vibration'], 0);
    final power = _toDouble(latest['power'] ?? metrics?['power'], 0);

    var score = 0.0;
    if (t >= 85) {
      score += 35;
    } else if (t >= 70) {
      score += 22;
    } else if (t >= 60) {
      score += 10;
    }
    if (p >= 6.0 || (p > 0 && p <= 0.8)) {
      score += 25;
    } else if (p >= 4.8 || (p > 0 && p <= 1.2)) {
      score += 12;
    }
    if (v >= 8.0) {
      score += 30;
    } else if (v >= 4.0) {
      score += 16;
    }
    if (power >= 6500) {
      score += 20;
    } else if (power >= 4500) {
      score += 10;
    }
    return score.round().clamp(0, 100);
  }

  String _riskModeFromTelemetry(Map<String, dynamic>? latest) {
    if (latest == null) return 'Inconnu';
    final raw = (latest['panne_type'] ?? latest['scenarioLabel'] ?? latest['scenario_label'] ?? latest['ml_scenario'] ?? '').toString().trim();
    if (raw.isNotEmpty && !raw.toLowerCase().contains('erreur serveur ml')) {
      return raw;
    }

    final metricsRaw = latest['metrics'];
    Map<String, dynamic>? metrics;
    if (metricsRaw is Map<String, dynamic>) {
      metrics = metricsRaw;
    } else if (metricsRaw is Map) {
      metrics = Map<String, dynamic>.from(metricsRaw);
    }
    final t = _toDouble(latest['temperature'] ?? metrics?['thermal'], 0);
    final v = _toDouble(latest['vibration'] ?? metrics?['vibration'], 0);
    final p = _toDouble(latest['pressure'] ?? metrics?['pressure'], 0);
    final power = _toDouble(latest['power'] ?? metrics?['power'], 0);

    if (power >= 5500 || p >= 6.0) return 'Risque électrique';
    if (v >= 6.0) return 'Risque mécanique';
    if (t >= 85) return 'Surchauffe';
    return 'Aucun risque majeur';
  }

  Future<({int riskPct, int stablePct, String riskMode})> _computeRiskStats(List<Map<String, dynamic>> machines) async {
    if (machines.isEmpty) return (riskPct: 0, stablePct: 100, riskMode: 'Aucun risque majeur');

    final ids = machines.map(_extractMachineId).where((e) => e.isNotEmpty).toList();
    if (ids.isEmpty) return (riskPct: 0, stablePct: 100, riskMode: 'Aucun risque majeur');

    final latestList = await Future.wait(
      ids.map((id) async {
        try {
          return await ApiService.getLatestTelemetry(id);
        } catch (_) {
          return null;
        }
      }),
    );

    var riskSum = 0;
    var stableCount = 0;
    var worstRisk = -1;
    var worstMode = 'Aucun risque majeur';

    for (final latest in latestList) {
      final r = _riskFromTelemetry(latest);
      riskSum += r;
      if (r < 40) stableCount++;
      if (r > worstRisk) {
        worstRisk = r;
        worstMode = _riskModeFromTelemetry(latest);
      }
    }

    final avgRisk = (riskSum / latestList.length).round().clamp(0, 100);
    final stablePct = ((stableCount * 100) / latestList.length).round().clamp(0, 100);
    return (riskPct: avgRisk, stablePct: stablePct, riskMode: worstMode);
  }

  void _goTo(int page) {
    if (page == 7) {
      Navigator.pushNamed(context, '/message-equipe', arguments: {
        'role': 'conception',
        'name': 'Admin',
      });
      return;
    }
    if (page == 0) _fetchGlobalStats();
    setState(() => _currentPage = page);
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 992;

    return Scaffold(
      backgroundColor: const Color(0xFF10102B),
      bottomNavigationBar: isDesktop ? null : _buildMobileBottomNav(),
      body: Stack(
        children: [
          // 1. Sidebar (Desktop only)
          if (isDesktop)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 272,
              child: _SidebarContent(
                currentPage: _currentPage,
                concepteurEmbeddedReturnPage: _concepteurEmbeddedReturnPage,
                onNavigate: _goTo,
              ),
            ),

          // 2. Main Content Wrapper
          Positioned.fill(
            left: isDesktop ? 272 : 0,
            child: Column(
              children: [
                _buildTopBar(isDesktop),
                Expanded(
                  child: _currentPage == 1
                      ? _EmbeddedAddClientView(onBack: () => _goTo(2))
                      : _currentPage == 2
                          ? EmbeddedClientListView(
                              onAddClient: () => _goTo(1),
                            )
                          : _currentPage == 3
                              ? const ActiveMachinesPage()
                              : _currentPage == 4
                                  ? ProjectTeamPage(
                                      onAddTechnician: () {
                                        setState(() => _pendingTechnicianEdit = null);
                                        _goTo(5);
                                      },
                                      onAddTeamMember: (role) {
                                        switch (role) {
                                          case 'technician':
                                            setState(() => _pendingTechnicianEdit = null);
                                            _goTo(5);
                                            break;
                                          case 'concepteur':
                                            setState(() {
                                              _pendingConcepteurEdit = null;
                                              _concepteurEmbeddedReturnPage = 4;
                                            });
                                            _goTo(10);
                                            break;
                                          case 'maintenance':
                                            setState(() => _pendingMaintenanceEdit = null);
                                            _goTo(11);
                                            break;
                                        }
                                      },
                                      onEditConcepteurFromTeam: (data) {
                                        setState(() {
                                          _pendingConcepteurEdit = Map<String, dynamic>.from(data);
                                          _concepteurEmbeddedReturnPage = 4;
                                          _currentPage = 10;
                                        });
                                      },
                                      onEditMaintenanceFromTeam: (data) {
                                        setState(() {
                                          _pendingMaintenanceEdit = Map<String, dynamic>.from(data);
                                          _currentPage = 11;
                                        });
                                      },
                                      onEditTechnicianFromTeam: (data) {
                                        setState(() {
                                          _pendingTechnicianEdit = Map<String, dynamic>.from(data);
                                          _currentPage = 5;
                                        });
                                      },
                                    )
                                  : _currentPage == 5
                                      ? AddTechnicianPage(
                                          key: ValueKey(
                                            'technician-${_pendingTechnicianEdit?['technicianId'] ?? _pendingTechnicianEdit?['id'] ?? 'new'}',
                                          ),
                                          initialData: _pendingTechnicianEdit,
                                          onBack: () {
                                            setState(() => _pendingTechnicianEdit = null);
                                            _goTo(4);
                                          },
                                        )
                                      : _currentPage == 6
                                          ? ConceptionListPage(
                                              onAddConception: () => _goTo(8),
                                              onAddConcepteur: () {
                                                setState(() {
                                                  _pendingConcepteurEdit = null;
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
                                                            _goTo(4);
                                                          },
                                                        )
                                                      : _currentPage == 12
                                                          ? const MaintenanceModulePage()
                                                  : SingleChildScrollView(
                                                          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
                                                          child: Column(
                                                            crossAxisAlignment: CrossAxisAlignment.start,
                                                            children: [
                                                              const SizedBox(height: 16),
                                                              _buildHeaderSection(),
                                                              const SizedBox(height: 32),
                                                              _buildKPIGrid(context, isDesktop),
                                                              const SizedBox(height: 24),
                                                              _buildMiddleSection(isDesktop),
                                                              const SizedBox(height: 24),
                                                              _buildChartsSection(context, isDesktop),
                                                              const SizedBox(height: 24),
                                                              _buildAlertsFeed(),
                                                              const SizedBox(height: 48),
                                                            ],
                                                          ),
                                                        ),
                ),
              ],
            ),
          ),

          // 3. FAB — visible on dashboard (0) and client list (2)
          if ((_currentPage == 0 || _currentPage == 2) && ApiService.isSuperAdmin)
            Positioned(
              right: 24,
              bottom: isDesktop ? 24 : 100,
              child: FloatingActionButton.extended(
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
            ),
        ],
      ),
    );
  }

  // --- Sub-widgets components ---

  Widget _buildTopBar(bool isDesktop) {
    return Container(
      height: 64,
      color: const Color(0xFF10102B),
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Icon(Icons.hub_outlined, color: Color(0xFFFF6E00), size: 30),
              const SizedBox(width: 16),
              Text(
                'Predictive Cloud',
                style: GoogleFonts.inter(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
          Row(
            children: [
              if (isDesktop) ...[
                _buildTopNavLink('DASHBOARD', active: true),
                const SizedBox(width: 8),
                _buildTopNavLink('ANALYTIQUE'),
                const SizedBox(width: 8),
                _buildTopNavLink('RÉSEAU'),
                const SizedBox(width: 24),
                Container(
                  width: 1,
                  height: 24,
                  color: Colors.white.withOpacity(0.1),
                ),
                const SizedBox(width: 24),
              ],
              _buildIconButton(Icons.notifications_outlined),
              const SizedBox(width: 8),
              _buildIconButton(Icons.settings_outlined),
              const SizedBox(width: 16),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFFF6E00).withOpacity(0.3), width: 1),
                  image: const DecorationImage(
                    image: NetworkImage('https://lh3.googleusercontent.com/aida-public/AB6AXuCLG6x5IUGVH6uCwhdhkvfAFLEbmKCG4vdpxrzSIKwh4Wlzix_mBSn-M6vCkiius3k3QcW22mBYwwTwvxsrnHUKS0TaGbpO258N-QzfPSn0ESrVgLbJpm9l9lm1nRNeslwPt9L3xx2YycjCKK7M2YZPGEdIAhjwjDZTzh4it1Wvlo_XZrCHYLwaLSUVBd8y1o0QNy8YDkrH6qzsjCISGKQjLKgCZ4zi-8IYAKPePWn-1Y5ags_oEtcHd99IB6VrY-23oKPRBHnosPQ'),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTopNavLink(String text, {bool active = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      child: Text(
        text,
        style: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: active ? FontWeight.bold : FontWeight.normal,
          color: active ? const Color(0xFFFF6E00) : const Color(0xFFE2BFB0),
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _buildIconButton(IconData icon) {
    return InkWell(
      onTap: () {},
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(8),
        child: Icon(icon, color: const Color(0xFFE2BFB0), size: 24),
      ),
    );
  }

  Widget _buildHeaderSection() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Supervision Globale',
              style: GoogleFonts.inter(
                fontSize: 32,
                fontWeight: FontWeight.w800,
                letterSpacing: -1.0,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'ÉTAT OPÉRATIONNEL DU PARC INDUSTRIEL',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 12,
                color: const Color(0xFFA98A7C),
                fontWeight: FontWeight.w500,
                letterSpacing: 2.0,
              ),
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF191934),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
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
              Text(
                'SYSTÈME LIVE',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                  color: Colors.white,
                ),
              ),
            ],
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
      childAspectRatio: 1.5,
      children: [
        GestureDetector(
          onTap: () => _goTo(2),
          child: _KPICard(
              icon: Icons.corporate_fare,
              label: 'Flux Actif',
              value: _isLoadingCounts ? '...' : _clientCount.toString(),
              title: 'Clients',
              color: const Color(0xFF75D1FF)),
        ),
        GestureDetector(
          onTap: () => _goTo(3), // Navigate to active machines page
          child: _KPICard(
              icon: Icons.precision_manufacturing,
              label: 'En Ligne',
              value: _isLoadingCounts ? '...' : _machineCount.toString(),
              title: 'Machines',
              color: const Color(0xFF66BB6A)),
        ),
        _KPICard(
            icon: Icons.sensors,
            label: 'Télémétrie',
            value: _isLoadingCounts ? '...' : (_machineCount * 4).toString(), // Dynamic estimate
            title: 'Capteurs',
            color: const Color(0xFFFFB692),
            hasIndicator: true),
        GestureDetector(
          onTap: () => _goTo(4), // Navigate to TechnicianListPage
          child: _KPICard(
              icon: Icons.badge,
              label: 'Déployés',
              value: _isLoadingCounts ? '...' : _techCount.toString(),
              title: 'Techniciens',
              color: const Color(0xFFEFB1F9)),
        ),
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
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1D1D38),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            color: const Color(0xFF272743),
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
                      decoration: const BoxDecoration(color: Color(0xFFFFB692), shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'OPÉRATIONNEL',
                      style: GoogleFonts.spaceGrotesk(fontSize: 10, color: Colors.white.withOpacity(0.7)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(
            height: 400,
            child: Stack(
              children: [
                // Minimalist map image placeholder (Network image from user code)
                Positioned.fill(
                  child: Opacity(
                    opacity: 0.4,
                    child: Image.network(
                      'https://lh3.googleusercontent.com/aida-public/AB6AXuCA4fhjZmz_T0lo0lRhkkAerVw7HjTZgUmjqedY7xpGs1QAqRJjJn1qm5lLHjJLbS-_SPnef2wTl2PUQglmp89dVmZIcUY81G0clLaqDBOFoIxsXUtSZMoAHQGs9zwVXbON68J3MjHYGjrDumNqWuyospM0OTMrolz44qcC5OKqx8X9Of2KBdFiBsQFQVgRHnSdr4G5Tsdmnnk7j7V2RB7OW0M2HVURfKnNrqPlKfoTc2PoV3M7DpPaQQxsDMx4r1pK63YJOHnpHTs',
                      fit: BoxFit.cover,
                      color: Colors.white,
                      colorBlendMode: BlendMode.saturation,
                    ),
                  ),
                ),
                // Decorative markers
                _buildMapMarker(top: 0.2, left: 0.45),
                _buildMapMarker(top: 0.4, left: 0.42),
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        'Map of Tunisia',
                        style: GoogleFonts.inter(fontSize: 14, color: Colors.white.withOpacity(0.3)),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                )
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapMarker({required double top, required double left}) {
    return Positioned(
      top: top * 400,
      left: left * 500, // Roughly based on max width
      child: const Icon(
        Icons.location_on,
        color: Color(0xFFFF6E00),
        size: 32,
      ),
    );
  }

  Widget _buildSecondaryMetrics() {
    return Column(
      children: [
        _MetricRow(
            label: 'RISQUE MOYEN DE PANNE',
            value: _isLoadingCounts ? '...' : '$_riskPct %',
            icon: Icons.check_circle,
            color: _riskPct >= 70 ? const Color(0xFFFFB4AB) : (_riskPct >= 40 ? const Color(0xFFFFB692) : const Color(0xFF66BB6A))),
        const SizedBox(height: 16),
        _MetricRow(
            label: 'MACHINES STABLES',
            value: _isLoadingCounts ? '...' : '$_stablePct %',
            icon: Icons.monitor_heart_outlined,
            color: _stablePct >= 70 ? const Color(0xFF66BB6A) : (_stablePct >= 40 ? const Color(0xFFFFB692) : const Color(0xFFFFB4AB))),
        const SizedBox(height: 16),
        _MetricRow(
            label: 'MODE DE RISQUE DOMINANT',
            value: _isLoadingCounts ? '...' : _riskMode,
            icon: Icons.warning_amber_rounded,
            color: const Color(0xFF75D1FF)),
        const SizedBox(height: 16),
        _MetricRow(
            label: 'DOCUMENTATION',
            value: '18 Docs',
            icon: Icons.description,
            color: const Color(0xFFEFB1F9)),
      ],
    );
  }

  Widget _buildChartsSection(BuildContext context, bool isDesktop) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: isDesktop ? 3 : 1,
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      childAspectRatio: 1.4,
      children: [
        _ChartBox(
          title: 'CONSOMMATION ÉNERGIE (7J)',
          icon: Icons.equalizer,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildBar(0.6),
              _buildBar(0.85),
              _buildBar(0.45),
              _buildBar(0.95),
              _buildBar(0.7),
              _buildBar(0.55),
              _buildBar(0.8, isToday: true),
            ],
          ),
        ),
        _ChartBox(
          title: 'SANTÉ DES MACHINES',
          icon: Icons.monitor_heart,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildProgressRow(context, 'hatha (Presse)', 0.94, const Color(0xFFFF6E00), id: 'MAC_HATHA'),
              const SizedBox(height: 12),
              _buildProgressRow(context, 'expresse (Convoyeur)', 0.91, const Color(0xFF75D1FF), id: 'MAC_EXP'),
              const SizedBox(height: 12),
              _buildProgressRow(context, 'Bras Robot R-04', 0.42, const Color(0xFFFFB4AB), id: 'MAC_R04'),
            ],
          ),
        ),
        _ChartBox(
          title: 'STATUT TECHNICIENS',
          icon: Icons.groups,
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 120,
                      height: 120,
                      child: CircularProgressIndicator(
                        value: 0.6,
                        strokeWidth: 8,
                        color: const Color(0xFFFF6E00),
                        backgroundColor: Colors.white.withOpacity(0.05),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_isLoadingCounts ? '...' : _techCount.toString(), style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.bold)),
                        Text('TOTAL', style: GoogleFonts.inter(fontSize: 8, color: Colors.white.withOpacity(0.5))),
                      ],
                    )
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatItem('Disponible', '60%', const Color(0xFFFF6E00)),
                  _buildStatItem('En Mission', '25%', const Color(0xFF75D1FF)),
                  _buildStatItem('Absent', '15%', const Color(0xFFEFB1F9)),
                ],
              )
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBar(double heightFactor, {bool isToday = false}) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2.0),
        child: Container(
          height: 100 * heightFactor,
          decoration: BoxDecoration(
            color: isToday ? const Color(0xFFFF6E00) : const Color(0xFFFF6E00).withOpacity(0.2),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }

  Widget _buildProgressRow(BuildContext context, String name, double value, Color color, {required String id}) {
    return InkWell(
      onTap: () {
        final role = (ApiService.savedUserRole ?? '').toLowerCase();
        if (name.toUpperCase().contains('DZLI') && role == 'technician') {
          Navigator.pushNamed(context, '/technician-terminal');
          return;
        }
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => MachineDetailAiPage(
              machineId: id,
              machineName: name,
              viewerRole: 'conception',
              viewerName: 'Conception',
            ),
          ),
        );
      },
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(name,
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 10, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () {
                      Navigator.pushNamed(context, '/machine-team');
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: color.withOpacity(0.3)),
                      ),
                      child: Text(
                        'ÉQUIPE',
                        style: GoogleFonts.spaceGrotesk(
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                            color: color),
                      ),
                    ),
                  ),
                ],
              ),
              Text('${(value * 100).toInt()}%',
                  style: GoogleFonts.inter(fontSize: 10, color: color)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: value,
              minHeight: 6,
              backgroundColor: Colors.white.withOpacity(0.05),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: GoogleFonts.inter(fontSize: 8, color: Colors.white.withOpacity(0.6))),
        Text(value, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  Widget _buildAlertsFeed() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0B0B26),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            color: const Color(0xFF272743),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.broadcast_on_home, color: Color(0xFFFFB4AB), size: 20),
                    const SizedBox(width: 12),
                    Text(
                      "FLUX D'ALERTES EN TEMPS RÉEL",
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2.0,
                      ),
                    ),
                  ],
                ),
                _buildActionLabel('VIDER LE LOG'),
              ],
            ),
          ),
          _AlertItem(
            time: '14:52:10',
            icon: Icons.error,
            color: const Color(0xFFFFB4AB),
            title: 'Surchauffe Critique - Enterprise Corp',
            subtitle: 'SENS-482 : Turbine de refroidissement défaillante',
            action: 'INTERVENIR',
          ),
          _AlertItem(
            time: '14:48:35',
            icon: Icons.warning,
            color: const Color(0xFFFFB692),
            title: 'Vibration Anormale Detectée',
            subtitle: 'Auto Solutions : Bras Robot R-04 maintenance requise',
            action: 'VOIR',
          ),
          _AlertItem(
            time: '14:45:02',
            icon: Icons.info,
            color: const Color(0xFF75D1FF),
            title: 'Mise à jour système terminée',
            subtitle: 'Tous les capteurs sont passés à la v2.4.1',
          ),
        ],
      ),
    );
  }

  Widget _buildActionLabel(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFFF6E00).withOpacity(0.3)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: GoogleFonts.spaceGrotesk(fontSize: 8, color: const Color(0xFFFF6E00), fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildMobileBottomNav() {
    final navPage = (_currentPage == 5 ||
            _currentPage == 10 ||
            _currentPage == 11)
        ? 4
        : _currentPage;
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
            icon: Icons.hub_outlined,
            label: 'Accueil',
            active: navPage == 0,
            onTap: () => _goTo(0),
          ),
          _BottomNavItem(
            icon: Icons.analytics_outlined,
            label: 'Machines',
            active: navPage == 3,
            onTap: () => _goTo(3),
          ),
          _BottomNavItem(
            icon: Icons.groups_outlined,
            label: 'Équipe',
            active: navPage == 4,
            onTap: () => _goTo(4),
          ),
          _BottomNavItem(
            icon: Icons.rule_folder_outlined,
            label: 'Panne',
            active: navPage == 12,
            onTap: () => _goTo(12),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Sidebar Widget — now navigation-aware
// ─────────────────────────────────────────────────────────────
class _SidebarContent extends StatelessWidget {
  final int currentPage;
  /// Permet de distinguer la page 10 (concepteur) ouverte depuis l’équipe (4) ou le hub conception (6).
  final int concepteurEmbeddedReturnPage;
  final ValueChanged<int> onNavigate;

  const _SidebarContent({
    required this.currentPage,
    required this.concepteurEmbeddedReturnPage,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF131429),
      padding: const EdgeInsets.only(top: 80),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Brand section
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('SUPERADMIN',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFFE2DFFF),
                    )),
                Text('System Core',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      color: const Color(0xFFE2BFB0).withOpacity(0.5),
                      letterSpacing: 2.0,
                    )),
              ],
            ),
          ),
          const SizedBox(height: 32),
          // Nav items
          _SidebarMenuTile(
            icon: Icons.hub_outlined,
            label: 'FLEET OVERVIEW',
            active: currentPage == 0,
            onTap: () => onNavigate(0),
          ),
          _SidebarMenuTile(
            icon: Icons.analytics_outlined,
            label: 'MACHINES ACTIVES', // Updated from ASSET HEALTH to match required menu
            active: currentPage == 3,
            onTap: () => onNavigate(3),
          ),
          _SidebarMenuTile(
            icon: Icons.groups_outlined,
            label: 'ÉQUIPE DE PROJET',
            active: currentPage == 4 ||
                currentPage == 5 ||
                currentPage == 11 ||
                (currentPage == 10 && concepteurEmbeddedReturnPage == 4),
            onTap: () => onNavigate(4),
          ),
          _SidebarMenuTile(
            icon: Icons.precision_manufacturing,
            label: 'CONCEPTEURS MACHINE',
            active: currentPage == 6 ||
                currentPage == 8 ||
                (currentPage == 10 && concepteurEmbeddedReturnPage == 6),
            onTap: () => onNavigate(6),
          ),
          _SidebarMenuTile(
            icon: Icons.domain,
            label: 'CLIENT MANAGEMENT',
            active: currentPage == 2,
            onTap: () => onNavigate(2),
          ),
          _SidebarMenuTile(
            icon: Icons.message_outlined,
            label: 'MESSAGERIE',
            active: currentPage == 7,
            onTap: () => onNavigate(7),
          ),
          _SidebarMenuTile(
            icon: Icons.rule_folder_outlined,
            label: 'RÉGLAGE DE PANNE',
            active: currentPage == 12,
            onTap: () => onNavigate(12),
          ),
          const Spacer(),
          const Divider(color: Color(0xFF32324e), height: 1),
          _SidebarMenuTile(
            icon: Icons.description_outlined,
            label: 'Documentation',
            isSmall: true,
            onTap: () {},
          ),
          _SidebarMenuTile(
            icon: Icons.contact_support_outlined,
            label: 'Support',
            isSmall: true,
            onTap: () {},
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
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


class _SidebarMenuTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final bool isSmall;
  final VoidCallback onTap;

  const _SidebarMenuTile({
    required this.icon,
    required this.label,
    this.active = false,
    this.isSmall = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
      decoration: BoxDecoration(
        color: active ? const Color(0xFF32324E).withOpacity(0.5) : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        border: active
            ? const Border(
                right: BorderSide(color: Color(0xFFFF6E00), width: 3))
            : null,
      ),
      child: ListTile(
        dense: true,
        leading: Icon(
          icon,
          color: active
              ? const Color(0xFFFF6E00)
              : const Color(0xFFE2BFB0).withOpacity(0.6),
          size: isSmall ? 18 : 20,
        ),
        title: Text(
          label,
          style: GoogleFonts.spaceGrotesk(
            fontSize: isSmall ? 10 : 10,
            fontWeight: active ? FontWeight.bold : FontWeight.normal,
            color: active
                ? const Color(0xFFFF6E00)
                : const Color(0xFFE2BFB0).withOpacity(0.6),
            letterSpacing: 1.5,
          ),
        ),
        onTap: onTap,
      ),
    );
  }
}

// KPI Card Widget
class _KPICard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String title;
  final Color color;
  final bool hasIndicator;

  const _KPICard({required this.icon, required this.label, required this.value, required this.title, required this.color, this.hasIndicator = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF191934),
        borderRadius: BorderRadius.circular(12),
        border: hasIndicator ? const Border(left: BorderSide(color: Color(0xFFFF6E00), width: 4)) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: color, size: 28),
              Text(label, style: GoogleFonts.spaceGrotesk(fontSize: 8, color: color, letterSpacing: -0.5)),
            ],
          ),
          const Spacer(),
          Text(value, style: GoogleFonts.inter(fontSize: 32, fontWeight: FontWeight.bold)),
          Text(title, style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFFA98A7C), fontWeight: FontWeight.w600, letterSpacing: 1.5)),
        ],
      ),
    );
  }
}

// Simple Metric Row
class _MetricRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _MetricRow({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF191934),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFFA98A7C), letterSpacing: 1.5)),
              const SizedBox(height: 4),
              Text(value, style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
            ],
          ),
          Icon(icon, color: color.withOpacity(0.4), size: 36),
        ],
      ),
    );
  }
}

// Chart Box Wrapper
class _ChartBox extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _ChartBox({required this.title, required this.icon, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1D1D38),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: Colors.white.withOpacity(0.7)),
              const SizedBox(width: 8),
              Text(title, style: GoogleFonts.spaceGrotesk(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(child: child),
        ],
      ),
    );
  }
}

// Alert Item Widget
class _AlertItem extends StatelessWidget {
  final String time;
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String? action;

  const _AlertItem({required this.time, required this.icon, required this.color, required this.title, required this.subtitle, this.action});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05))),
      ),
      child: Row(
        children: [
          Text(time, style: GoogleFonts.spaceGrotesk(fontSize: 10, color: Colors.white.withOpacity(0.4))),
          const SizedBox(width: 24),
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600)),
                Text(subtitle, style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFFA98A7C), letterSpacing: 0.5)),
              ],
            ),
          ),
          if (action != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                action!,
                style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: color),
              ),
            )
          else
            const Icon(Icons.more_vert, color: Color(0xFFA98A7C), size: 20),
        ],
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
