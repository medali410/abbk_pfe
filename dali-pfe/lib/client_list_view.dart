import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'client_detail_page.dart';
import 'package:dali_pfe/services/api_service.dart' as api;
import 'add_client_page.dart';

import 'client_position_page.dart';

// ─── Data Model ───────────────────────────────────────────────
class _Client {
  final String name;
  final String location;
  final String status;   // 'operational' | 'optimal' | 'warning' | 'critical'
  final String lastSync;
  final int machines;
  final int techs;
  final int alerts;
  final double health;   // 0.0 – 1.0
  final String imageUrl;

  const _Client({
    required this.name,
    required this.location,
    required this.status,
    required this.lastSync,
    required this.machines,
    required this.techs,
    required this.alerts,
    required this.health,
    required this.imageUrl,
  });
}

// ─── Embedded Client List ─────────────────────────────────────
class EmbeddedClientListView extends StatefulWidget {
  /// Called when user taps "AJOUTER CLIENT" → opens add-client form
  final VoidCallback onAddClient;
  final bool isDarkMode;

  const EmbeddedClientListView({
    super.key,
    required this.onAddClient,
    this.isDarkMode = false,
  });

  @override
  State<EmbeddedClientListView> createState() =>
      _EmbeddedClientListViewState();
}

class _EmbeddedClientListViewState
    extends State<EmbeddedClientListView> {
  String _search = '';

  static const List<_Client> _clients = [];

  // ─── Colors ───────────────────────────────────────────────
  Color get _bg => widget.isDarkMode ? const Color(0xFF10102B) : const Color(0xFFFCFAF7);
  Color get _surface => widget.isDarkMode ? const Color(0xFF1D1D38) : const Color(0xFFFFF8F0);
  Color get _surfaceLow => widget.isDarkMode ? const Color(0xFF191934) : const Color(0xFFF5E0C3);
  Color get _surfaceLowest => widget.isDarkMode ? const Color(0xFF0B0B26) : const Color(0xFFECE4D5);
  Color get _onSurface => widget.isDarkMode ? const Color(0xFFE2DFFF) : const Color(0xFF2D1F0E);
  Color get _onSurfaceVariant => widget.isDarkMode ? const Color(0xFFE2BFB0) : const Color(0xFF7A4F2E);
  Color get _secondary => widget.isDarkMode ? const Color(0xFF75D1FF) : const Color(0xFFB87333);
  Color get _tertiary => widget.isDarkMode ? const Color(0xFFEFB1F9) : const Color(0xFF8B5E3C);
  Color get _orange => widget.isDarkMode ? const Color(0xFFFF6E00) : const Color(0xFFB86000);
  Color get _green => const Color(0xFF66BB6A);
  Color get _red => widget.isDarkMode ? const Color(0xFFFFB4AB) : const Color(0xFFD32F2F);
  Color get _outline => widget.isDarkMode ? const Color(0xFF594136) : const Color(0xFFCD7F32).withOpacity(0.3);

  // ─── Status helpers ────────────────────────────────────────
  Color _statusColor(_Client c) {
    switch (c.status) {
      case 'optimal':
      case 'operational':
        return _green;
      case 'warning':
        return _orange;
      default:
        return _red;
    }
  }

  String _statusLabel(_Client c) {
    switch (c.status) {
      case 'optimal':
        return 'OPTIMAL';
      case 'operational':
        return 'OPÉRATIONNEL';
      case 'warning':
        return 'ATTENTION';
      default:
        return 'CRITIQUE';
    }
  }

  Color _healthColor(double h) {
    if (h >= 0.8) return _green;
    if (h >= 0.5) return _orange;
    return _red;
  }

  Color _alertColor(int a) => a == 0 ? _secondary : (a >= 4 ? _red : _orange);

  List<_Client> get _filtered => _search.isEmpty
      ? _clients
      : _clients
          .where((c) =>
              c.name.toLowerCase().contains(_search.toLowerCase()) ||
              c.location.toLowerCase().contains(_search.toLowerCase()))
          .toList();

  // ─── Build ────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 700;

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: api.ApiService.getClients(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: Padding(
            padding: const EdgeInsets.all(48.0),
            child: CircularProgressIndicator(color: _secondary),
          ));
        }
        if (snapshot.hasError) {
          return Center(child: Text('Erreur: ${snapshot.error}', style: const TextStyle(color: Colors.white)));
        }
        
        final apiClients = snapshot.data ?? [];
        
        // Convert API maps to _Client objects for the UI
        List<_Client> allClients = apiClients.map((c) => _Client(
          name: c['name'] ?? 'Inconnu',
          location: c['location'] ?? 'Inconnu',
          status: c['status'] ?? 'operational',
          lastSync: c['lastSync'] ?? 'Récemment',
          machines: c['machines'] ?? 0,
          techs: c['techs'] ?? 0,
          alerts: c['alerts'] ?? 0,
          health: (c['health'] ?? 1.0).toDouble(),
          imageUrl: c['imageUrl'] ?? 'https://lh3.googleusercontent.com/aida-public/AB6AXuAC78OPMt_an7mPJmtM60IxdM_eZaPk7I85lMuYPG4UOCggmrViweZNyf5SB44WrcoFcUbT-gPmwED_py_D7gXsiT1MNqAxGoZK7_LFMN7KaUWr2dD0eA870cVcoPCAKAga3QahI4DaEX7Nbj2DC-UqCvoyazf7FEk_3TF4_eqdHRZkEYzLBUTH-oHhtVlM21tgwPbz9QQUgg0pTd4rECwEdiRNrmzJjffuUqZ5QGUvLiotc3x4Zhs9NnOhWSxg366qNdGNCatP9Q0',
        )).toList();
        
        // Apply search filter locally
        List<_Client> filtered = _search.isEmpty 
            ? allClients 
            : allClients.where((c) =>
                c.name.toLowerCase().contains(_search.toLowerCase()) ||
                c.location.toLowerCase().contains(_search.toLowerCase())).toList();

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(isDesktop, allClients.length),
              const SizedBox(height: 32),
              _buildGrid(filtered, isDesktop, apiClients),
            ],
          ),
        );
      }
    );
  }

  // ─── Header ───────────────────────────────────────────────
  Widget _buildHeader(bool isDesktop, int totalClients) {
    if (isDesktop) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(child: _buildTitle(totalClients)),
          const SizedBox(width: 24),
          _buildSearchBar(),
          const SizedBox(width: 16),
          if (api.ApiService.isSuperAdmin) _buildAddButton(),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTitle(totalClients),
        const SizedBox(height: 16),
        _buildSearchBar(),
        const SizedBox(height: 12),
        if (api.ApiService.isSuperAdmin) _buildAddButton(),
      ],
    );
  }

  Widget _buildTitle(int totalClients) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Clients',
          style: GoogleFonts.inter(
            fontSize: 40,
            fontWeight: FontWeight.w800,
            color: _onSurface,
            letterSpacing: -1.5,
          ),
        ),
        const SizedBox(height: 6),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Container(
      width: 320,
      height: 48,
      decoration: BoxDecoration(
        color: widget.isDarkMode ? Colors.white.withOpacity(0.03) : const Color(0xFFFFF8F0),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: widget.isDarkMode ? Colors.white.withOpacity(0.08) : const Color(0xFFCD7F32).withOpacity(0.3)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TextField(
        onChanged: (v) => setState(() => _search = v),
        style: GoogleFonts.inter(color: _onSurface, fontSize: 13),
        decoration: InputDecoration(
          prefixIcon: Icon(Icons.search_rounded,
              color: _orange.withOpacity(0.7), size: 20),
          hintText: 'Rechercher un client...',
          hintStyle: GoogleFonts.inter(
            color: _onSurface.withOpacity(0.5),
            fontSize: 13,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  Widget _buildAddButton() {
    return InkWell(
      onTap: widget.onAddClient,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFF6E00), Color(0xFFFFB692)],
          ),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: _orange.withOpacity(0.3),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.add, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(
              'AJOUTER CLIENT',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 12,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── KPI Cards ────────────────────────────────────────────
  Widget _buildKPIRow(bool isDesktop, List<_Client> allClients) {
    int totalMachines = allClients.fold(0, (sum, c) => sum + c.machines);
    int totalTechs = allClients.fold(0, (sum, c) => sum + c.techs);
    
    final kpis = [
      ('Total Clients', allClients.length.toString().padLeft(2, '0'), 'Sync', _secondary),
      ('Machines Actives', totalMachines.toString(), 'Stable', _secondary),
      ('Effectif Tech', totalTechs.toString(), 'Opérationnel', _tertiary),
      ('Disponibilité', '98.4%', 'Global', _secondary),
    ];
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: isDesktop ? 4 : 2,
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      childAspectRatio: isDesktop ? 2.2 : 1.8,
      children: kpis
          .map((k) => _KPICard(
                label: k.$1,
                value: k.$2,
                badge: k.$3,
                badgeColor: k.$4,
              ))
          .toList(),
    );
  }

  // ─── Client Cards Grid ────────────────────────────────────
  Widget _buildGrid(List<_Client> clients, bool isDesktop, List<Map<String, dynamic>> rawApiData) {
    if (clients.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(48),
          child: Text(
            'Aucun client trouvé',
            style: GoogleFonts.spaceGrotesk(
              color: _onSurfaceVariant.withOpacity(0.4),
              fontSize: 16,
            ),
          ),
        ),
      );
    }
    final screenWidth = MediaQuery.of(context).size.width;
    final int crossAxisCount = isDesktop ? 3 : (screenWidth > 600 ? 2 : 1);
    final double aspectRatio = isDesktop ? 3.2 : (screenWidth > 600 ? 2.5 : 3.5);

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: aspectRatio,
      ),
      itemCount: clients.length,
      itemBuilder: (_, i) => _ClientCard(
        client: clients[i],
        rawMap: rawApiData.firstWhere((element) => element['name'] == clients[i].name, orElse: () => {}),
        statusColor: _statusColor(clients[i]),
        statusLabel: _statusLabel(clients[i]),
        healthColor: _healthColor(clients[i].health),
        alertColor: _alertColor(clients[i].alerts),
        onRefresh: () => setState(() {}),
        isDarkMode: widget.isDarkMode,
      ),
    );
  }
}

// ─── KPI Card ─────────────────────────────────────────────────
class _KPICard extends StatelessWidget {
  final String label;
  final String value;
  final String badge;
  final Color badgeColor;

  const _KPICard({
    required this.label,
    required this.value,
    required this.badge,
    required this.badgeColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF191934),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF594136).withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label.toUpperCase(),
            style: GoogleFonts.spaceGrotesk(
              fontSize: 9,
              letterSpacing: 2,
              color: const Color(0xFFE2BFB0).withOpacity(0.7),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFFE2DFFF),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                badge,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 11,
                  color: badgeColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Client Card ──────────────────────────────────────────────
class _ClientCard extends StatefulWidget {
  final _Client client;
  final Map<String, dynamic> rawMap;
  final Color statusColor;
  final String statusLabel;
  final Color healthColor;
  final Color alertColor;
  final VoidCallback onRefresh;
  final bool isDarkMode;

  const _ClientCard({
    required this.client,
    required this.rawMap,
    required this.statusColor,
    required this.statusLabel,
    required this.healthColor,
    required this.alertColor,
    required this.onRefresh,
    this.isDarkMode = false,
  });

  @override
  State<_ClientCard> createState() => _ClientCardState();
}

class _ClientCardState extends State<_ClientCard> {
  bool _hovering = false;

  Color get _secondary => widget.isDarkMode ? const Color(0xFF75D1FF) : const Color(0xFFB87333);
  Color get _tertiary => widget.isDarkMode ? const Color(0xFFEFB1F9) : const Color(0xFF8B5E3C);
  Color get _orange => widget.isDarkMode ? const Color(0xFFFF6E00) : const Color(0xFFB86000);

  @override
  Widget build(BuildContext context) {
    final c = widget.client;
    final id = widget.rawMap['clientId']?.toString() ?? widget.rawMap['id']?.toString() ?? '';

    return Dismissible(
      key: Key('client-$id'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.8),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (direction) async {
        return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: widget.isDarkMode ? const Color(0xFF1D1D38) : const Color(0xFFFFF8F0),
            title: Text('Supprimer ${c.name}?', style: GoogleFonts.inter(color: widget.isDarkMode ? Colors.white : const Color(0xFF2D1F0E))),
            content: Text(
              'Cela supprimera définitivement le client et TOUTES ses machines.',
              style: TextStyle(color: widget.isDarkMode ? Colors.white70 : const Color(0xFF4B3B2A)),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text('ANNULER', style: TextStyle(color: widget.isDarkMode ? Colors.white70 : const Color(0xFF7A4F2E))),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text('SUPPRIMER', style: TextStyle(color: widget.isDarkMode ? const Color(0xFFFFB4AB) : const Color(0xFFD32F2F))),
              ),
            ],
          ),
        );
      },
      onDismissed: (direction) async {
        if (id.isNotEmpty) {
          try {
            await api.ApiService.deleteClient(id);
            widget.onRefresh();
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Erreur suppression: $e'), backgroundColor: Colors.red),
              );
            }
          }
        }
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: InkWell(
          onTap: () {
            showDialog(
              context: context,
              builder: (context) => AddClientPage(
                isDialog: true,
                isDarkMode: widget.isDarkMode,
                onBack: () {
                  Navigator.pop(context);
                  widget.onRefresh();
                },
                initialData: widget.rawMap,
              ),
            );
          },
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _hovering
                ? (widget.isDarkMode ? const Color(0xFF24244A) : const Color(0xFFFFF1E0))
                : (widget.isDarkMode ? const Color(0xFF1D1D38) : const Color(0xFFFFF8F0)),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _hovering
                  ? _secondary.withOpacity(0.5)
                  : (widget.isDarkMode ? Colors.white.withOpacity(0.05) : const Color(0xFFCD7F32).withOpacity(0.2)),
              width: 1.5,
            ),
            boxShadow: [
              if (_hovering)
                BoxShadow(
                  color: _secondary.withOpacity(widget.isDarkMode ? 0.1 : 0.15),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          _secondary.withOpacity(0.2),
                          _tertiary.withOpacity(0.2),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: widget.isDarkMode ? Colors.white.withOpacity(0.1) : const Color(0xFFCD7F32).withOpacity(0.25)),
                    ),
                    child: Center(
                      child: Text(
                        c.name.substring(0, 1).toUpperCase(),
                        style: GoogleFonts.spaceGrotesk(
                          color: _secondary,
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.name,
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: widget.isDarkMode ? Colors.white : const Color(0xFF2D1F0E),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.location_on_rounded, size: 12, color: _orange.withOpacity(0.7)),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                c.location,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: widget.isDarkMode ? Colors.white.withOpacity(0.5) : const Color(0xFF7A4F2E),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: widget.statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: widget.statusColor.withOpacity(0.3)),
                    ),
                    child: Text(
                      widget.statusLabel,
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: widget.statusColor,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: Icon(Icons.arrow_forward_ios_rounded, color: widget.isDarkMode ? Colors.white54 : const Color(0xFF7A4F2E), size: 16),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ClientDetailPage(
                            clientName: c.name,
                            rawMap: widget.rawMap,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }

  Widget _miniStat(String label, String value, IconData icon, {Color? color}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: color ?? Colors.white.withOpacity(0.4)),
            const SizedBox(width: 6),
            Text(
              value,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: color ?? Colors.white,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: GoogleFonts.spaceGrotesk(
            fontSize: 8,
            color: Colors.white.withOpacity(0.3),
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}
