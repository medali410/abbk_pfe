import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'add_conception_page.dart';
import 'client_dashboard_page.dart';
import 'package:dali_pfe/services/api_service.dart' as api;

class ClientDetailPage extends StatefulWidget {
  final String clientName;
  final String logoUrl;
  final Map<String, dynamic>? rawMap;

  const ClientDetailPage({
    super.key,
    this.clientName = 'Enterprise Corp',
    this.logoUrl = 'https://lh3.googleusercontent.com/aida-public/AB6AXuAC78OPMt_an7mPJmtM60IxdM_eZaPk7I85lMuYPG4UOCggmrViweZNyf5SB44WrcoFcUbT-gPmwED_py_D7gXsiT1MNqAxGoZK7_LFMN7KaUWr2dD0eA870cVcoPCAKAga3QahI4DaEX7Nbj2DC-UqCvoyazf7FEk_3TF4_eqdHRZkEYzLBUTH-oHhtVlM21tgwPbz9QQUgg0pTd4rECwEdiRNrmzJjffuUqZ5QGUvLiotc3x4Zhs9NnOhWSxg366qNdGNCatP9Q0',
    this.rawMap,
  });

  @override
  State<ClientDetailPage> createState() => _ClientDetailPageState();
}

class _ClientDetailPageState extends State<ClientDetailPage> {
  int _currentNav = 0; // 0 = Capteurs, 1 = Techniciens, 2 = Conception
  
  int _machineCount = 0;
  int _techCount = 0;
  bool _isLoadingStats = true;

  @override
  void initState() {
    super.initState();
    _fetchStats();
  }

  Future<void> _fetchStats() async {
    final cId = widget.rawMap?['clientId'] ?? widget.rawMap?['id'] ?? widget.rawMap?['_id'] ?? '';
    if (cId.isEmpty) {
      if (mounted) setState(() => _isLoadingStats = false);
      return;
    }
    
    try {
      final machines = await api.ApiService.getMachinesForClient(cId);
      final allTechs = await api.ApiService.getTechnicians();
      final clientTechs = allTechs.where((t) => t['companyId'] == cId || t['companyId'] == widget.clientName).toList();
      
      if (mounted) {
        setState(() {
          _machineCount = machines.length;
          _techCount = clientTechs.length;
          _isLoadingStats = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingStats = false);
    }
  }

  // Colors based on tailwind config
  static const _bg = Color(0xFF10102B);
  static const _surface = Color(0xFF1D1D38);
  static const _surfaceLow = Color(0xFF191934);
  static const _surfaceLowest = Color(0xFF0B0B26);
  static const _onSurface = Color(0xFFE2DFFF);
  static const _onSurfaceVariant = Color(0xFFE2BFB0);
  static const _primary = Color(0xFFFFB692);
  static const _primaryContainer = Color(0xFFFF6E00);
  static const _secondary = Color(0xFF75D1FF);
  static const _tertiary = Color(0xFFEFB1F9);
  static const _error = Color(0xFFFFB4AB);
  static const _outline = Color(0xFF594136);

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 992;

    return Scaffold(
      backgroundColor: _bg,
      bottomNavigationBar: isDesktop ? null : _buildMobileBottomNav(),
      body: Stack(
        children: [
          if (isDesktop)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 272,
              child: _buildSidebar(),
            ),
          Positioned.fill(
            left: isDesktop ? 272 : 0,
            child: Column(
              children: [
                _buildTopBar(isDesktop),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 48),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHeader(),
                        const SizedBox(height: 32),
                        _buildMainGrid(isDesktop),
                        const SizedBox(height: 24),
                        _buildBottomRow(isDesktop),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Top Bar ──────────────────────────────────────────────────
  Widget _buildTopBar(bool isDesktop) {
    return Container(
      height: 64,
      color: _bg,
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              if (!isDesktop)
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: _onSurfaceVariant),
                  onPressed: () => Navigator.pop(context),
                ),
              Text(
                'Predictive Cloud',
                style: GoogleFonts.inter(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                  color: _onSurface,
                ),
              ),
            ],
          ),
          Row(
            children: [
              if (isDesktop) ...[
                _buildTopNavLink('Tableau de Bord', active: true),
                const SizedBox(width: 8),
                _buildTopNavLink('Analytiques'),
                const SizedBox(width: 8),
                _buildTopNavLink('Rapports'),
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
                  border: Border.all(color: _outline.withOpacity(0.3), width: 1),
                  image: const DecorationImage(
                    image: NetworkImage(
                        'https://lh3.googleusercontent.com/aida-public/AB6AXuB4-e7iXTyF81kyLTE_qEOCnRB3l5b84YkfKLMyuAKPzW8_YJNBjKEW5dRIrXzJYzKNPv0sZjY9Q_m5-eVBxWmncOjTHPNWZFbNGdhx0XSn2Py5sm37WORSUZ3m76KJTMIo942tq2HP_ZqKALeJwaNqdUUr2VzkAZ6PzD9sSIAYiF2h-fSNjA2YdZLNp7l6S1XhRSsLJDJ2KQOoAXNWmz8HT6kb3BHYLqIfyc-MFJtqncqtx-MPx3Cl_egMaYY7--_dCsyuxJBnxlc'),
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
    return InkWell(
      onTap: () {},
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
        decoration: BoxDecoration(
          color: active ? Colors.transparent : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          text,
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: active ? FontWeight.bold : FontWeight.normal,
            color: active ? _primaryContainer : _onSurfaceVariant,
          ),
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
        child: Icon(icon, color: _onSurfaceVariant, size: 24),
      ),
    );
  }

  // ─── Sidebar ──────────────────────────────────────────────────
  Widget _buildSidebar() {
    return Container(
      color: const Color(0xFF131429),
      padding: const EdgeInsets.only(top: 64),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Back Button + Header
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: () => Navigator.pop(context),
                  child: Row(
                    children: [
                      const Icon(Icons.arrow_back_ios, color: _onSurfaceVariant, size: 12),
                      const SizedBox(width: 4),
                      Text('RETOUR', style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _onSurfaceVariant, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFF272743),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.factory_outlined, color: _primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Clients',
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: _onSurface,
                              )),
                          Text(widget.clientName,
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 10,
                                color: _onSurfaceVariant.withOpacity(0.7),
                              )),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // Nav items
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _buildSidebarTile(0, Icons.sensors, 'Capteurs'),
                _buildSidebarTile(1, Icons.engineering, 'Techniciens'),
                _buildSidebarTile(2, Icons.architecture, 'Conception'),
              ],
            ),
          ),

          // Bottom actions
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [_primaryContainer, _primary],
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.search, color: Colors.white, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        'RECHERCHE CAPTEURS',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _buildSidebarBottomTile(Icons.settings, 'Paramètres'),
                _buildSidebarBottomTile(Icons.help, 'Support'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarTile(int index, IconData icon, String label) {
    final active = _currentNav == index;
    return InkWell(
      onTap: () {
        if (index == 2) {
          Navigator.push<void>(
            context,
            MaterialPageRoute<void>(
              builder: (context) => AddConceptionPage(
                onEmbeddedBack: () => Navigator.of(context).pop(),
              ),
            ),
          );
        } else {
          setState(() => _currentNav = index);
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: active ? _surface : Colors.transparent,
          border: active ? const Border(left: BorderSide(color: _primaryContainer, width: 2)) : null,
        ),
        child: Row(
          children: [
            Icon(icon, color: active ? _primaryContainer : _onSurfaceVariant.withOpacity(0.7), size: 20),
            const SizedBox(width: 12),
            Text(
              label.toUpperCase(),
              style: GoogleFonts.spaceGrotesk(
                fontSize: 12,
                color: active ? _primaryContainer : _onSurfaceVariant.withOpacity(0.7),
                fontWeight: active ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebarBottomTile(IconData icon, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: _onSurfaceVariant.withOpacity(0.7), size: 16),
          const SizedBox(width: 12),
          Text(
            label,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 12,
              color: _onSurfaceVariant.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileBottomNav() {
    return Container(
      height: 72,
      decoration: BoxDecoration(
        color: _bg.withOpacity(0.95),
        border: Border(top: BorderSide(color: _outline.withOpacity(0.15), width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _BottomNavItem(icon: Icons.account_tree, label: 'Assets', active: true),
          _BottomNavItem(icon: Icons.warning, label: 'Alerts'),
          _BottomNavItem(icon: Icons.groups, label: 'Team'),
          _BottomNavItem(icon: Icons.precision_manufacturing, label: 'Design'),
        ],
      ),
    );
  }

  // ─── Dashboard Body ───────────────────────────────────────────
  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('🏭', style: TextStyle(fontSize: 32)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                widget.clientName,
                style: GoogleFonts.inter(
                  fontSize: 36,
                  fontWeight: FontWeight.w800,
                  color: _onSurface,
                  letterSpacing: -1,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 16),
            if (api.ApiService.isSuperAdmin) ...[
              ElevatedButton.icon(
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      backgroundColor: const Color(0xFF1D1D38),
                      title: Text('Supprimer ${widget.clientName}?', style: GoogleFonts.inter(color: Colors.white)),
                      content: const Text('Voulez-vous vraiment supprimer ce client ? Cette action est irréversible.', style: TextStyle(color: Colors.white70)),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('ANNULER')),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('SUPPRIMER', style: TextStyle(color: Color(0xFFFFB4AB))),
                        ),
                      ],
                    ),
                  );

                  if (confirm == true) {
                    try {
                      final id = widget.rawMap?['clientId'] ?? widget.rawMap?['id'] ?? widget.rawMap?['_id'] ?? '';
                      if (id.isNotEmpty) {
                        await api.ApiService.deleteClient(id);
                        if (mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Client supprimé avec succès'), backgroundColor: Colors.green),
                          );
                        }
                      } else {
                        throw 'ID du client manquant pour la suppression';
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red));
                      }
                    }
                  }
                },
                icon: const Icon(Icons.delete_outline, size: 18),
                label: Text('SUPPRIMER', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.withOpacity(0.15),
                  foregroundColor: const Color(0xFFFFB4AB),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
              ),
              const SizedBox(width: 12),
            ],
            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ClientDashboardPage(
                      clientName: widget.clientName,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.dashboard_outlined, size: 18),
              label: Text('DASHBOARD', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryContainer,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: MediaQuery.of(context).size.width > 1200 ? 3 : (MediaQuery.of(context).size.width > 800 ? 2 : 1),
          crossAxisSpacing: 24,
          mainAxisSpacing: 24,
          childAspectRatio: 2.2,
          children: [
            _buildHeaderKPI(
              Icons.precision_manufacturing,
              'Machines Actives',
              _isLoadingStats ? '..' : _machineCount.toString().padLeft(2, '0'),
              Icons.check_circle,
              'Toutes opérationnelles',
              _primary,
            ),
            _buildHeaderKPI(
              Icons.engineering,
              'Techniciens',
              _isLoadingStats ? '..' : _techCount.toString().padLeft(2, '0'),
              Icons.group,
              'En service aujourd\'hui',
              _onSurface,
              subtitleColor: const Color(0xFF4E1D5A),
            ),
            _buildHeaderKPI(
              Icons.description,
              'Documents',
              '04',
              Icons.update,
              'Mis à jour: 2h',
              _onSurface,
              subtitleColor: _onSurfaceVariant,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildHeaderKPI(IconData bgIcon, String title, String value, IconData subIcon, String subtitle, Color valueColor, {Color? subtitleColor}) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _surfaceLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -10,
            top: -10,
            child: Icon(bgIcon, size: 80, color: _onSurfaceVariant.withOpacity(0.05)),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title.toUpperCase(),
                style: GoogleFonts.spaceGrotesk(fontSize: 12, letterSpacing: 2, color: _onSurfaceVariant),
              ),
              Text(
                value,
                style: GoogleFonts.spaceGrotesk(fontSize: 40, fontWeight: FontWeight.bold, color: valueColor),
              ),
              Row(
                children: [
                  Icon(subIcon, size: 14, color: subtitleColor ?? _secondary),
                  const SizedBox(width: 8),
                  Text(
                    subtitle,
                    style: GoogleFonts.spaceGrotesk(fontSize: 10, color: subtitleColor ?? _secondary),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMainGrid(bool isDesktop) {
    if (isDesktop) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 7, child: _buildMapSection()),
          const SizedBox(width: 24),
          Expanded(
            flex: 5,
            child: Column(
              children: [
                _buildEnergySection(),
                const SizedBox(height: 24),
                _buildHealthSection(),
              ],
            ),
          ),
        ],
      );
    } else {
      return Column(
        children: [
          _buildMapSection(),
          const SizedBox(height: 24),
          _buildEnergySection(),
          const SizedBox(height: 24),
          _buildHealthSection(),
        ],
      );
    }
  }

  Widget _buildMapSection() {
    return Container(
      height: 480,
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.location_on, color: _primary, size: 24),
                    const SizedBox(width: 8),
                    Text(
                      'GÉOLOCALISATION DES ACTIFS',
                      style: GoogleFonts.spaceGrotesk(fontSize: 14, fontWeight: FontWeight.bold, color: _onSurface),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: const Color(0xFF32324e), borderRadius: BorderRadius.circular(4)),
                  child: Text('TUNISIA / SIDI BOUZID', style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _onSurfaceVariant)),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0x1A594136)),
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColorFiltered(
                  colorFilter: const ColorFilter.matrix([
                    0.2126, 0.7152, 0.0722, 0, 0,
                    0.2126, 0.7152, 0.0722, 0, 0,
                    0.2126, 0.7152, 0.0722, 0, 0,
                    0, 0, 0, 0.4, 0,
                  ]),
                  child: Image.network(
                    'https://lh3.googleusercontent.com/aida-public/AB6AXuBiU96oB4FgQJvVk4f1HPjdX15nQ59SrK0_dRlQiDZrus7tAxL5vDxz-JfoW-IzuTPD21B9MXysdf4sJUROxiMs-mjxgyXRIshWq4quanxyNYj8nQWVdYdvSbh2YTuFaNNy9zwpowjelIXn3g_4NconofzAIszk6mqLjSrkIdMwTiNJZQXd0T9z0aAzUiI7gI9gaukv9RK5FPwnK5l9UKKlYK4-ulwfylTLeXdZ88kHz4Ju2K6DDrlny-Q6bxC1XoAmdKVa-AW8ods',
                    fit: BoxFit.cover,
                  ),
                ),
                // Machine A
                Positioned(
                  top: 100,
                  left: 150,
                  child: _MapPin(color: _primary, label: 'Machine A - Nord'),
                ),
                // Machine B
                Positioned(
                  bottom: 120,
                  right: 150,
                  child: _MapPin(color: _primary, label: 'Machine B - Sud'),
                ),
                // Machine C
                Positioned(
                  top: 200,
                  right: 250,
                  child: _MapPin(color: _error, label: 'Machine C - Alerte'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEnergySection() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF272743),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bolt, color: _secondary, size: 24),
              const SizedBox(width: 8),
              Text(
                'CONSOMMATION ÉNERGÉTIQUE',
                style: GoogleFonts.spaceGrotesk(fontSize: 14, fontWeight: FontWeight.bold, color: _onSurface),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('AUJOURD\'HUI', style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _onSurfaceVariant)),
                    RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(text: '89.4 ', style: GoogleFonts.spaceGrotesk(fontSize: 24, fontWeight: FontWeight.bold, color: _onSurface)),
                          TextSpan(text: 'kWh', style: GoogleFonts.spaceGrotesk(fontSize: 12, color: _onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('MENSUEL', style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _onSurfaceVariant)),
                    RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(text: '2,847 ', style: GoogleFonts.spaceGrotesk(fontSize: 24, fontWeight: FontWeight.bold, color: _onSurface)),
                          TextSpan(text: 'kWh', style: GoogleFonts.spaceGrotesk(fontSize: 12, color: _onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: Color(0x1A594136)),
          const SizedBox(height: 16),
          Text('COÛT ESTIMÉ', style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _onSurfaceVariant)),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(text: '42.8 DT ', style: GoogleFonts.spaceGrotesk(fontSize: 20, fontWeight: FontWeight.bold, color: _primary)),
                TextSpan(text: '/ jour', style: GoogleFonts.spaceGrotesk(fontSize: 12, color: _onSurface)),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Mini Chart concept
          SizedBox(
            height: 80,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _buildBar(0.4),
                _buildBar(0.75),
                _buildBar(0.9),
                _buildBar(0.6),
                _buildBar(0.85),
                _buildBar(0.3),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Center(child: Text('RÉPARTITION PAR UNITÉ (24H)', style: GoogleFonts.spaceGrotesk(fontSize: 9, letterSpacing: 2, color: _onSurfaceVariant.withOpacity(0.5)))),
        ],
      ),
    );
  }

  Widget _buildBar(double heightFactor) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        height: 80 * heightFactor,
        decoration: const BoxDecoration(
          color: Color(0x33FFB692),
          borderRadius: BorderRadius.vertical(top: Radius.circular(2)),
        ),
      ),
    );
  }

  Widget _buildHealthSection() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _surfaceLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.health_and_safety, color: _tertiary, size: 24),
              const SizedBox(width: 8),
              Text(
                'ÉTAT DE SANTÉ MACHINES',
                style: GoogleFonts.spaceGrotesk(fontSize: 14, fontWeight: FontWeight.bold, color: _onSurface),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildHealthBar('Machine A', 0.94, _secondary),
          const SizedBox(height: 16),
          _buildHealthBar('Machine B', 0.87, _primary),
          const SizedBox(height: 16),
          _buildHealthBar('Machine C', 0.72, _error),
        ],
      ),
    );
  }

  Widget _buildHealthBar(String name, double value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(name, style: GoogleFonts.spaceGrotesk(fontSize: 12, fontWeight: FontWeight.bold, color: _onSurface)),
            Text('${(value * 100).round()}%', style: GoogleFonts.spaceGrotesk(fontSize: 12, color: color)),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: value,
            minHeight: 6,
            backgroundColor: const Color(0xFF32324e),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomRow(bool isDesktop) {
    final children = [
      Expanded(child: _buildEquipmentCard()),
      const SizedBox(width: 24, height: 24),
      Expanded(child: _buildTeamCard()),
      const SizedBox(width: 24, height: 24),
      Expanded(child: _buildDocsCard()),
    ];

    if (isDesktop) {
      return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
    } else {
      return Column(children: [
        _buildEquipmentCard(),
        const SizedBox(height: 24),
        _buildTeamCard(),
        const SizedBox(height: 24),
        _buildDocsCard(),
      ]);
    }
  }

  Widget _buildEquipmentCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ÉQUIPEMENTS', style: GoogleFonts.spaceGrotesk(fontSize: 12, fontWeight: FontWeight.bold, color: _onSurfaceVariant, letterSpacing: 2)),
          const SizedBox(height: 16),
          _buildItemRow('Broyeur Industriel X1', 'Actif', _primary),
          const SizedBox(height: 12),
          _buildItemRow('Convoyeur Central', 'Actif', _primary),
        ],
      ),
    );
  }

  Widget _buildItemRow(String name, String status, Color statusColor) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: _surfaceLowest, borderRadius: BorderRadius.circular(4)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(name, style: GoogleFonts.spaceGrotesk(fontSize: 12, color: _onSurface)),
          Text(status, style: GoogleFonts.spaceGrotesk(fontSize: 10, color: statusColor)),
        ],
      ),
    );
  }

  Widget _buildTeamCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ÉQUIPE ASSIGNÉE', style: GoogleFonts.spaceGrotesk(fontSize: 12, fontWeight: FontWeight.bold, color: _onSurfaceVariant, letterSpacing: 2)),
          const SizedBox(height: 16),
          if (_techCount == 0)
            Text('Aucun membre assigné', style: GoogleFonts.spaceGrotesk(fontSize: 12, color: _onSurfaceVariant.withOpacity(0.5)))
          else
            Row(
              children: [
                _buildAvatar('https://lh3.googleusercontent.com/aida-public/AB6AXuDX-tST0DXqSDPAZsjr7jwA4fQHNCetcWJfMtS8PUKByJJmII8xp_dqkAQtwQ0d-XinuaBd_b9vvQxbs5cLaf2WGXHQsfeJcE89RUPetRwC3KtqimVOiA4LMrsiXq1PJO704XX7uiufwu0ZHy-4VZkSC2MIF5ZxxtyPOkqdZImNEpw6Twx8wIhW4_zvds1Kp57i1m0lh79zmik6XqhTKBDodEOP1Cx9JxPZVwr0K1Zrxkz4RGcwCH4O7paAnLG-MlkAVI4cJ8cQm2E'),
                // Only show more if count > 1 (simplification for now)
              ],
            ),
          const SizedBox(height: 16),
          Text('Intervention prévue: Demain 08:00', style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _buildAvatar(String url, {double offset = 0}) {
    return Transform.translate(
      offset: Offset(offset, 0),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: _surface, width: 2),
          image: DecorationImage(image: NetworkImage(url), fit: BoxFit.cover),
        ),
      ),
    );
  }

  Widget _buildDocsCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('DOCUMENTATION', style: GoogleFonts.spaceGrotesk(fontSize: 12, fontWeight: FontWeight.bold, color: _onSurfaceVariant, letterSpacing: 2)),
          const SizedBox(height: 16),
          _buildDocRow(Icons.description, 'Manuel_Operateur.pdf'),
          const SizedBox(height: 12),
          _buildDocRow(Icons.history, 'Maintenance_Log_2023.csv'),
        ],
      ),
    );
  }

  Widget _buildDocRow(IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, size: 20, color: _onSurfaceVariant),
        const SizedBox(width: 12),
        Text(title, style: GoogleFonts.spaceGrotesk(fontSize: 12, color: _onSurface)),
      ],
    );
  }
}

class _MapPin extends StatelessWidget {
  final Color color;
  final String label;

  const _MapPin({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: const Color(0x9932324e), borderRadius: BorderRadius.circular(4)),
              child: Text(label, style: GoogleFonts.spaceGrotesk(fontSize: 10, color: color == const Color(0xFFFFB4AB) ? color : Colors.white)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.5),
                blurRadius: 12,
                spreadRadius: 4,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BottomNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;

  const _BottomNavItem({
    required this.icon,
    required this.label,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          color: active ? const Color(0xFFFF6E00) : const Color(0xFFE2BFB0).withOpacity(0.6),
          size: active ? 28 : 24,
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: GoogleFonts.spaceGrotesk(
            fontSize: 10,
            color: active ? const Color(0xFFFF6E00) : const Color(0xFFE2BFB0).withOpacity(0.6),
            fontWeight: active ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }
}
