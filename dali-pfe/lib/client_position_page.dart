import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'machine_detail_ai_page.dart';

import 'add_client_page.dart';
import 'add_machine_page.dart';
import 'services/api_service.dart';

class ClientPositionPage extends StatefulWidget {
  final String clientName;
  final Map<String, dynamic>? clientData;

  const ClientPositionPage({
    super.key,
    this.clientName = 'Enterprise Corp',
    this.clientData,
  });

  @override
  State<ClientPositionPage> createState() => _ClientPositionPageState();
}

class _ClientPositionPageState extends State<ClientPositionPage> {
  int _currentNav = 0; // 0 = Fleet, 1 = Map, 2 = Health, 3 = Alerts
  Future<List<Map<String, dynamic>>>? _machinesFuture;

  String _resolveRealtimeMachineId(Map<String, dynamic> machine) {
    final name = (machine['name'] ?? '').toString().toLowerCase().trim();
    if (name == 'hatha') return 'MAC_HATHA';
    if (name == 'expresse') return 'MAC_EXP';
    return (machine['machineId'] ?? machine['id'] ?? machine['_id'] ?? 'ID Inconnu').toString();
  }

  @override
  void initState() {
    super.initState();
    _refreshMachines();
  }

  void _refreshMachines() {
    final clientId = widget.clientData?['clientId'] ?? widget.clientData?['id'] ?? '';
    if (clientId.isNotEmpty) {
      setState(() {
        _machinesFuture = ApiService.getMachinesForClient(clientId);
      });
    }
  }

  // Colors based on Tailwind config
  static const _bg = Color(0xFF10102B);
  static const _surfaceContainerLowest = Color(0xFF0B0B26);
  static const _surfaceContainerLow = Color(0xFF191934);
  static const _surfaceContainer = Color(0xFF1D1D38);
  static const _surfaceContainerHigh = Color(0xFF272743);
  static const _primary = Color(0xFFFFB692);
  static const _primaryContainer = Color(0xFFFF6E00);
  static const _onSurface = Color(0xFFE2DFFF);
  static const _onSurfaceVariant = Color(0xFFE2BFB0);
  static const _outlineVariant = Color(0xFF594136);
  static const _green = Color(0xFF4ADE80);
  static const _error = Color(0xFFFFB4AB);

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 992;

    return Scaffold(
      backgroundColor: _bg,
      body: Column(
        children: [
          _buildTopBar(isDesktop),
          Expanded(
            child: Row(
              children: [
                if (isDesktop) _buildSidebar(),
                Expanded(
                  child: Row(
                    children: [
                      if (isDesktop || _currentNav == 0) _buildAssetList(isDesktop),
                      if (isDesktop || _currentNav == 1) Expanded(child: _buildMapView()),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: !isDesktop ? _buildMobileBottomNav() : null,
    );
  }

  // ─── Top Bar ──────────────────────────────────────────────
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
              if (!isDesktop) ...[
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: _onSurfaceVariant),
                  onPressed: () => Navigator.pop(context),
                ),
                const SizedBox(width: 8),
              ],
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
          Expanded(
            child: Row(
              children: [
                  Expanded(
                    child: Container(
                      height: 36,
                      decoration: BoxDecoration(
                        color: _surfaceContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: TextField(
                        style: GoogleFonts.spaceGrotesk(fontSize: 14, color: _onSurface),
                        decoration: InputDecoration(
                          hintText: 'Rechercher un actif...',
                          hintStyle: GoogleFonts.spaceGrotesk(fontSize: 14, color: _onSurfaceVariant.withOpacity(0.5)),
                          prefixIcon: Icon(Icons.search, color: _onSurfaceVariant, size: 18),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 24),
                  if (widget.clientData != null) ...[
                    if (ApiService.canManageFleet) ...[
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => AddClientPage(initialData: widget.clientData),
                            ),
                          );
                        },
                        icon: const Icon(Icons.edit, size: 16),
                        label: const Text('Modifier'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _surfaceContainerHigh,
                          foregroundColor: _onSurface,
                          elevation: 0,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (ApiService.isSuperAdmin) ...[
                      ElevatedButton.icon(
                        onPressed: _confirmDelete,
                        icon: const Icon(Icons.delete, size: 16),
                        label: const Text('Supprimer'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.withOpacity(0.2),
                          foregroundColor: Colors.redAccent,
                          elevation: 0,
                        ),
                      ),
                      const SizedBox(width: 24),
                    ],
                  ],
              ],
            ),
          ),
              _buildIconButton(Icons.notifications_outlined),
              const SizedBox(width: 8),
              _buildIconButton(Icons.settings_outlined),
              const SizedBox(width: 16),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _surfaceContainerHigh,
                  image: const DecorationImage(
                    image: NetworkImage(
                        'https://lh3.googleusercontent.com/aida-public/AB6AXuDarih3tlNNOw8solw6qUujFr49zO9Z6xjLcLKtSsN0TZuruhvOo5W1Yk8Px7CV_T3gwx3s7408fNf28ZThmo82VN1co81Ryjw_sH5x0o4jpiWk18_2OSzbMfccm80ziHSUbLFcuui5RUkrs8DoZNj1UJF9f2GIIR9obucPHIijv7cNgitBIiX2IGbND7HceFw0gaeAWTPxtK_xeIzD2hSoD6POPLwLQpw9aTO_8oNePjuK6fm-CKGxMdSZm8b0-8r3prAT-WaCokc'),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ],
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

  // ─── Sidebar ────────────────────────────────────────────────
  Widget _buildSidebar() {
    return Container(
      width: 256,
      decoration: BoxDecoration(
        color: _surfaceContainerLow,
        border: Border(
          right: BorderSide(color: _outlineVariant.withOpacity(0.15), width: 1),
        ),
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _primaryContainer.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.factory_outlined, color: _primaryContainer),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.clientName,
                        style: GoogleFonts.spaceGrotesk(fontSize: 16, fontWeight: FontWeight.w900, color: _primaryContainer, height: 1.1),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'INDUSTRIAL INTELLIGENCE',
                        style: GoogleFonts.spaceGrotesk(fontSize: 9, color: _onSurfaceVariant, fontWeight: FontWeight.bold, letterSpacing: 1),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // Navigation
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _buildSidebarItem(0, Icons.dashboard_outlined, 'Fleet Overview'),
                _buildSidebarItem(1, Icons.map_outlined, 'Map View'),
              ],
            ),
          ),

          // Bottom Status
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ÉTAT DU SYSTÈME',
                        style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _onSurfaceVariant, letterSpacing: 0.5),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Container(width: 8, height: 8, decoration: const BoxDecoration(color: _green, shape: BoxShape.circle)),
                          const SizedBox(width: 8),
                          Text('Nominal', style: GoogleFonts.spaceGrotesk(fontSize: 12, color: _onSurface)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _buildSidebarBottomLink(Icons.help_outline, 'Support'),
                const SizedBox(height: 12),
                _buildSidebarBottomLink(Icons.history, 'Logs'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarItem(int index, IconData icon, String label) {
    final active = _currentNav == index;
    return InkWell(
      onTap: () => setState(() => _currentNav = index),
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        decoration: BoxDecoration(
          color: active ? _surfaceContainerHigh : Colors.transparent,
          border: active ? const Border(left: BorderSide(color: _primaryContainer, width: 4)) : null,
        ),
        child: Row(
          children: [
            Icon(icon, color: active ? _onSurface : _onSurfaceVariant, size: 20),
            const SizedBox(width: 16),
            Text(
              label.toUpperCase(),
              style: GoogleFonts.spaceGrotesk(
                fontSize: 12,
                color: active ? _onSurface : _onSurfaceVariant,
                fontWeight: active ? FontWeight.bold : FontWeight.w500,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebarBottomLink(IconData icon, String label) {
    return InkWell(
      onTap: () {},
      child: Row(
        children: [
          Icon(icon, color: _onSurfaceVariant, size: 16),
          const SizedBox(width: 12),
          Text(
            label.toUpperCase(),
            style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _onSurfaceVariant, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  // ─── Asset List ─────────────────────────────────────────────
  Widget _buildAssetList(bool isDesktop) {
    return Container(
      width: isDesktop ? 384 : double.infinity,
      color: _surfaceContainerLow,
      child: Column(
        children: [
          // List Header
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: _outlineVariant.withOpacity(0.1))),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Liste des Machines',
                  style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.bold, color: _onSurface, letterSpacing: -0.5),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    FutureBuilder<List<Map<String, dynamic>>>(
                      future: _machinesFuture,
                      builder: (context, snapshot) {
                        final count = snapshot.data?.length ?? 0;
                        return Text('$count ACTIFS DÉTECTÉS', 
                          style: GoogleFonts.spaceGrotesk(fontSize: 10, letterSpacing: 1.5, color: _onSurfaceVariant));
                      }
                    ),
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed: () async {
                            final clientId = widget.clientData?['clientId'] ?? widget.clientData?['id'] ?? '';
                            final result = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => AddMachinePage(
                                  clientId: clientId,
                                  clientName: widget.clientName,
                                ),
                              ),
                            );
                            if (result == true) _refreshMachines();
                          },
                          icon: const Icon(Icons.add, size: 14, color: _primary),
                          label: Text('AJOUTER MACHINE', 
                            style: GoogleFonts.spaceGrotesk(fontSize: 12, fontWeight: FontWeight.bold, color: _primary)),
                        ),
                        const SizedBox(width: 8),
                        Text('Filtrer', 
                          style: GoogleFonts.spaceGrotesk(fontSize: 12, fontWeight: FontWeight.bold, color: _onSurfaceVariant)),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // List Items
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _machinesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Erreur: ${snapshot.error}', style: const TextStyle(color: Colors.red)));
                }
                final machines = snapshot.data ?? [];
                if (machines.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.precision_manufacturing_outlined, size: 48, color: _onSurfaceVariant.withOpacity(0.3)),
                        const SizedBox(height: 16),
                        Text('AUCUNE MACHINE DÉTECTÉE', 
                          style: GoogleFonts.spaceGrotesk(color: _onSurfaceVariant.withOpacity(0.5), letterSpacing: 2)),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: machines.length,
                  itemBuilder: (context, index) {
                    final m = machines[index];
                    final realtimeId = _resolveRealtimeMachineId(m);
                    return _buildMachineCard(
                      name: m['name'] ?? 'Machine Sans Nom',
                      id: realtimeId,
                      status: m['status'] ?? 'HORS LIGNE',
                      statusColor: (m['status'] == 'RUNNING' || m['status'] == 'normal') ? _green : _onSurfaceVariant,
                      location: m['location'] ?? 'Position non définie',
                      detailLabel: m['type'] ?? 'Équipement Industriel',
                      detailValue: m['power'] ?? '',
                      detailIcon: Icons.settings_power,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMachineCard({
    required String name,
    required String id,
    required String status,
    required Color statusColor,
    required String location,
    required String detailLabel,
    required String detailValue,
    required IconData detailIcon,
    Color? detailLabelColor,
    bool bgHighlight = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: bgHighlight ? _surfaceContainer.withOpacity(0.5) : Colors.transparent,
        border: Border(
          top: bgHighlight ? BorderSide(color: _outlineVariant.withOpacity(0.1)) : BorderSide.none,
          bottom: bgHighlight ? BorderSide(color: _outlineVariant.withOpacity(0.1)) : BorderSide.none,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => MachineDetailPage(
                  machineId: id,
                  machineName: name,
                  viewerRole: 'conception',
                  viewerName: 'Conception',
                ),
              ),
            );
          },
          hoverColor: _surfaceContainer,
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: _onSurface)),
                        const SizedBox(height: 4),
                        Text('ID: $id', style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _onSurfaceVariant, letterSpacing: 1.0)),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 6),
                          Text(status, style: GoogleFonts.spaceGrotesk(fontSize: 9, fontWeight: FontWeight.bold, color: statusColor, letterSpacing: 0.5)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                
                // Details
                Row(
                  children: [
                    Icon(Icons.location_on_outlined, size: 14, color: _onSurfaceVariant),
                    const SizedBox(width: 12),
                    Text(location, style: GoogleFonts.spaceGrotesk(fontSize: 11, color: _onSurfaceVariant)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(detailIcon, size: 14, color: detailLabelColor ?? _onSurfaceVariant),
                    const SizedBox(width: 12),
                    RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(text: '$detailLabel: ', style: GoogleFonts.spaceGrotesk(fontSize: 11, color: detailLabelColor ?? _onSurfaceVariant)),
                          TextSpan(text: detailValue, style: GoogleFonts.spaceGrotesk(fontSize: 11, color: _onSurface, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 24),
                // Footer
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text('VOIR DÉTAILS', style: GoogleFonts.spaceGrotesk(fontSize: 10, fontWeight: FontWeight.bold, color: _onSurface, letterSpacing: 1.0)),
                    const SizedBox(width: 4),
                    const Icon(Icons.arrow_forward, size: 12, color: _onSurface),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Map View ───────────────────────────────────────────────
  Widget _buildMapView() {
    return Container(
      color: _surfaceContainerLowest,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Background Image
          Opacity(
            opacity: 0.6,
            child: ColorFiltered(
              colorFilter: const ColorFilter.matrix([
                0.2126, 0.7152, 0.0722, 0, 0,
                0.2126, 0.7152, 0.0722, 0, 0,
                0.2126, 0.7152, 0.0722, 0, 0,
                0, 0, 0, 1, 0,
              ]),
              child: Image.network(
                'https://lh3.googleusercontent.com/aida-public/AB6AXuB1jsddVm5K6S1vCFyYt9V8VFaHrx3nUPAwGvOeFLQVJv9Yn38Fv2qO_ffiNIpVtweY2h6FfvuMRfOSFWiEUzRHYnBvVRpKPeOM-o2Zi4ixsoK00MHmn5qWpj6u2CbZPVI6XrRGTlC6POmgvmrb4WCL5wJcV8Nz1GNOwZ0tqYf45H-CuappEvQ1TKaFrPu14DCMWLUs7J0NVpT4dy7RJjn5OUfHwkQc_fFP__UeBjG0tji2-5imX9mmZ0d6DD-gjIlGY7I5GrcimNk',
                fit: BoxFit.cover,
              ),
            ),
          ),
          
          // Legend
          Positioned(
            top: 24,
            left: 24,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _surfaceContainer.withOpacity(0.9),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _outlineVariant.withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('LÉGENDE', style: GoogleFonts.spaceGrotesk(fontSize: 10, fontWeight: FontWeight.bold, color: _primary, letterSpacing: 1.5)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Container(width: 8, height: 8, decoration: const BoxDecoration(color: _green, shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                      Text('OPTIMAL', style: GoogleFonts.spaceGrotesk(fontSize: 9, color: _onSurface, letterSpacing: 0.5)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(width: 8, height: 8, decoration: const BoxDecoration(color: _primary, shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                      Text('ATTENTION', style: GoogleFonts.spaceGrotesk(fontSize: 9, color: _onSurface, letterSpacing: 0.5)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          
          // Pins
          Positioned(
            top: MediaQuery.of(context).size.height * 0.3,
            left: MediaQuery.of(context).size.width * 0.25,
            child: _buildMapPin('A', _green),
          ),
          Positioned(
            top: MediaQuery.of(context).size.height * 0.5,
            left: MediaQuery.of(context).size.width * 0.45,
            child: _buildMapPin('B', _primaryContainer),
          ),
          Positioned(
            bottom: MediaQuery.of(context).size.height * 0.25,
            right: MediaQuery.of(context).size.width * 0.2,
            child: _buildMapPin('C', _green),
          ),

          // Zoom Controls
          Positioned(
            bottom: 24,
            right: 24,
            child: Container(
              decoration: BoxDecoration(
                color: _surfaceContainer.withOpacity(0.8),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _outlineVariant.withOpacity(0.2)),
              ),
              child: Column(
                children: [
                  IconButton(icon: const Icon(Icons.add, color: _onSurface, size: 20), onPressed: () {}),
                  Container(height: 1, width: 40, color: _outlineVariant.withOpacity(0.2)),
                  IconButton(icon: const Icon(Icons.remove, color: _onSurface, size: 20), onPressed: () {}),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapPin(String label, Color color) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: _surfaceContainer,
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 2),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.4),
            blurRadius: 16,
            spreadRadius: 4,
          ),
        ],
      ),
      child: Center(
        child: Text(
          label,
          style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: _onSurface),
        ),
      ),
    );
  }

  // ─── Mobile Bottom Nav ──────────────────────────────────────
  Widget _buildMobileBottomNav() {
    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: _surfaceContainerLow,
        border: Border(top: BorderSide(color: _outlineVariant.withOpacity(0.1))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _BottomNavItem(icon: Icons.dashboard, label: 'FLEET', active: _currentNav == 0, onTap: () => setState(() => _currentNav = 0)),
          _BottomNavItem(icon: Icons.map, label: 'MAP', active: _currentNav == 1, onTap: () => setState(() => _currentNav = 1)),
        ],
      ),
    );
  }
  void _confirmDelete() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _bg,
        title: Text('Supprimer Client ?', style: GoogleFonts.inter(color: Colors.white)),
        content: Text(
          'Voulez-vous vraiment supprimer ce client ? Cette action est définitive.',
          style: GoogleFonts.spaceGrotesk(color: _onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              try {
                final id = widget.clientData?['clientId'] ?? widget.clientData?['id'] ?? widget.clientData?['_id'] ?? '';
                if (id.isNotEmpty) {
                  await ApiService.deleteClient(id);
                }
                if (mounted) {
                  Navigator.pop(context); // Close Dialog
                  Navigator.pop(context); // Go back to list page
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Client supprimé avec succès'), backgroundColor: Colors.green),
                  );
                }
              } catch (e) {
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Erreur: $e')),
                  );
                }
              }
            },
            child: const Text('SUPPRIMER', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

class _BottomNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _BottomNavItem({required this.icon, required this.label, this.active = false, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = active ? const Color(0xFFFF6E00) : const Color(0xFFE2BFB0).withOpacity(0.6);
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 10,
              color: color,
              fontWeight: active ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}
