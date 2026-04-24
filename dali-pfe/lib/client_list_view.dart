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

  const EmbeddedClientListView({super.key, required this.onAddClient});

  @override
  State<EmbeddedClientListView> createState() =>
      _EmbeddedClientListViewState();
}

class _EmbeddedClientListViewState
    extends State<EmbeddedClientListView> {
  String _search = '';

  static const List<_Client> _clients = [];

  // ─── Colors ───────────────────────────────────────────────
  static const _bg = Color(0xFF10102B);
  static const _surface = Color(0xFF1D1D38);
  static const _surfaceLow = Color(0xFF191934);
  static const _surfaceLowest = Color(0xFF0B0B26);
  static const _onSurface = Color(0xFFE2DFFF);
  static const _onSurfaceVariant = Color(0xFFE2BFB0);
  static const _secondary = Color(0xFF75D1FF);
  static const _tertiary = Color(0xFFEFB1F9);
  static const _orange = Color(0xFFFF6E00);
  static const _green = Color(0xFF66BB6A);
  static const _red = Color(0xFFFFB4AB);
  static const _outline = Color(0xFF594136);

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
          return const Center(child: Padding(
            padding: EdgeInsets.all(48.0),
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
              _buildKPIRow(isDesktop, allClients),
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
          '🏢 Clients',
          style: GoogleFonts.inter(
            fontSize: 40,
            fontWeight: FontWeight.w800,
            color: _onSurface,
            letterSpacing: -1.5,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: _secondary,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$totalClients client(s) enregistré(s) dans le cloud prédictif',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 13,
                color: _onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return SizedBox(
      width: 280,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: _outline.withOpacity(0.3)),
          ),
        ),
        child: TextField(
          onChanged: (v) => setState(() => _search = v),
          style: GoogleFonts.spaceGrotesk(color: _onSurface, fontSize: 13),
          decoration: InputDecoration(
            prefixIcon: Icon(Icons.search,
                color: _onSurfaceVariant.withOpacity(0.6), size: 20),
            hintText: 'Rechercher un client...',
            hintStyle: GoogleFonts.spaceGrotesk(
              color: _onSurfaceVariant.withOpacity(0.3),
              fontSize: 13,
            ),
            border: InputBorder.none,
            contentPadding:
                const EdgeInsets.symmetric(vertical: 12),
          ),
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
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isDesktop ? 2 : 1,
        mainAxisSpacing: 20,
        crossAxisSpacing: 20,
        childAspectRatio: isDesktop ? 1.55 : 1.4,
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

  const _ClientCard({
    required this.client,
    required this.rawMap,
    required this.statusColor,
    required this.statusLabel,
    required this.healthColor,
    required this.alertColor,
    required this.onRefresh,
  });

  @override
  State<_ClientCard> createState() => _ClientCardState();
}

class _ClientCardState extends State<_ClientCard> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.client;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ClientPositionPage(
                clientName: c.name,
                clientData: widget.rawMap,
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
          color: _hovering
              ? const Color(0xFF272743)
              : const Color(0xFF1D1D38),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: const Color(0xFF594136).withOpacity(0.15)),
          boxShadow: _hovering
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  )
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Top row: logo + info + status
            Row(
              children: [
                // Logo
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 52,
                    height: 52,
                    child: Image.network(
                      c.imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: const Color(0xFF272743),
                        child: const Icon(Icons.business,
                            color: Color(0xFF594136), size: 28),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // Name + location
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.name,
                        style: GoogleFonts.inter(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFE2DFFF),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.location_on_outlined,
                              size: 13,
                              color: const Color(0xFFE2BFB0)
                                  .withOpacity(0.6)),
                          const SizedBox(width: 2),
                          Text(
                            c.location,
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 11,
                              color: const Color(0xFFE2BFB0)
                                  .withOpacity(0.7),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                // Actions: Edit/Delete
                Column(
                  children: [
                    if (api.ApiService.canManageFleet)
                      ElevatedButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => AddClientPage(
                                onBack: () {
                                  Navigator.pop(context);
                                  widget.onRefresh();
                                },
                                initialData: widget.rawMap,
                              ),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1D1D38),
                          foregroundColor: const Color(0xFFE2BFB0),
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.edit, size: 14),
                            const SizedBox(width: 8),
                            const Text('MODIFIER', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    if (api.ApiService.canManageFleet) const SizedBox(height: 8),
                    if (api.ApiService.isSuperAdmin)
                      ElevatedButton(
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              backgroundColor: const Color(0xFF1D1D38),
                              title: Text('Supprimer ${c.name}?', style: GoogleFonts.inter(color: Colors.white)),
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
                              final id = widget.rawMap['clientId'] ?? widget.rawMap['id'] ?? widget.rawMap['_id'] ?? '';
                              await api.ApiService.deleteClient(id);
                              widget.onRefresh();
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red));
                              }
                            }
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFFB4AB).withOpacity(0.1),
                          foregroundColor: const Color(0xFFFFB4AB),
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.delete_outline, size: 14),
                            const SizedBox(width: 8),
                            const Text('EFFACER', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 16),
                // Status badge
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: widget.statusColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          widget.statusLabel,
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: widget.statusColor,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      c.status == 'critical'
                          ? c.lastSync
                          : 'Dernière synchro: ${c.lastSync}',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 9,
                        color: const Color(0xFFE2BFB0).withOpacity(0.5),
                      ),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 20),

            // ── Stats row
            Row(
              children: [
                Expanded(
                    child: _StatBox(
                  label: 'Machines',
                  value: c.machines.toString().padLeft(2, '0'),
                  color: const Color(0xFFE2DFFF),
                )),
                const SizedBox(width: 8),
                Expanded(
                    child: _StatBox(
                  label: 'Techs',
                  value: c.techs.toString().padLeft(2, '0'),
                  color: const Color(0xFFE2DFFF),
                )),
                const SizedBox(width: 8),
                Expanded(
                    child: _StatBox(
                  label: 'Alertes',
                  value: c.alerts.toString().padLeft(2, '0'),
                  color: widget.alertColor,
                )),
              ],
            ),

            const Spacer(),

            // ── Health bar
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'SANTÉ DU SYSTÈME',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 9,
                        letterSpacing: 1.5,
                        color: const Color(0xFFE2BFB0).withOpacity(0.6),
                      ),
                    ),
                    Text(
                      '${(c.health * 100).round()}%',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFFE2DFFF),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: c.health,
                    minHeight: 6,
                    backgroundColor:
                        const Color(0xFF0B0B26),
                    valueColor: AlwaysStoppedAnimation<Color>(
                        widget.healthColor),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      ),
    );
  }
}

// ─── Stat Box ─────────────────────────────────────────────────
class _StatBox extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatBox(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0B26),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(
            label.toUpperCase(),
            style: GoogleFonts.spaceGrotesk(
              fontSize: 8,
              letterSpacing: 1,
              color: const Color(0xFFE2BFB0).withOpacity(0.5),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
