import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'machine_detail_ai_page.dart';
import 'services/api_service.dart';

class ActiveMachinesPage extends StatefulWidget {
  const ActiveMachinesPage({super.key});

  @override
  State<ActiveMachinesPage> createState() => _ActiveMachinesPageState();
}

class _MachineListItem {
  final Map<String, dynamic> raw;
  final String id;
  final String displayName;
  final String clientName;
  final String statusLabel;
  final Color statusColor;
  final String location;
  final String lastUpdateLabel;
  final int health;
  final DateTime sortDate;
  final Color progressColorTop;
  final Color progressColorBottom;

  _MachineListItem({
    required this.raw,
    required this.id,
    required this.displayName,
    required this.clientName,
    required this.statusLabel,
    required this.statusColor,
    required this.location,
    required this.lastUpdateLabel,
    required this.health,
    required this.sortDate,
    required this.progressColorTop,
    required this.progressColorBottom,
  });
}

class _ActiveMachinesPageState extends State<ActiveMachinesPage> {
  static const _bg = Color(0xFF10102B);
  static const _surfaceContainerLow = Color(0xFF191934);
  static const _surfaceContainer = Color(0xFF1D1D38);
  static const _surfaceContainerHighest = Color(0xFF32324E);
  static const _primary = Color(0xFFFFB692);
  static const _secondary = Color(0xFF75D1FF);
  static const _onSurface = Color(0xFFE2DFFF);
  static const _onSurfaceVariant = Color(0xFFE2BFB0);
  static const _outlineVariant = Color(0xFF594136);
  static const _green = Color(0xFF66BB6A);
  static const _errorColor = Color(0xFFFFB4AB);
  static const _orange = Color(0xFFFF6E00);

  bool _loading = true;
  String? _loadError;
  List<Map<String, dynamic>> _clients = [];
  List<_MachineListItem> _items = [];
  String? _filterClientId;
  String _sortKey = 'health_desc';

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _clientApiId(Map<String, dynamic> c) {
    final v = c['clientId'] ?? c['id'] ?? c['_id'];
    return v?.toString() ?? '';
  }

  String _clientNameForCompanyId(
    String? companyId,
    List<Map<String, dynamic>> clients,
  ) {
    if (companyId == null || companyId.isEmpty) return 'Client';
    for (final c in clients) {
      final id = _clientApiId(c);
      final oid = c['_id']?.toString();
      if (id == companyId || oid == companyId || (c['name']?.toString() == companyId)) {
        return (c['name'] ?? 'Client').toString();
      }
    }
    return companyId;
  }

  String _machineIdOf(Map<String, dynamic> m) {
    return (m['id'] ?? m['_id'] ?? m['machineId'] ?? '').toString().trim();
  }

  /// Uniquement des lignes cohérentes avec la collection Mongo (id + companyId), sans doublon.
  List<Map<String, dynamic>> _onlyDbMachines(List<Map<String, dynamic>> raw) {
    final seen = <String>{};
    final out = <Map<String, dynamic>>[];
    for (final m in raw) {
      final id = _machineIdOf(m);
      if (id.isEmpty) continue;
      if (seen.contains(id)) continue;
      final cid = m['companyId']?.toString().trim() ?? '';
      if (cid.isEmpty) continue;
      seen.add(id);
      out.add(m);
    }
    return out;
  }

  int _healthFromStatus(String? status) {
    final s = (status ?? '').toUpperCase();
    if (s == 'RUNNING' || s == 'NORMAL') return 92;
    if (s == 'STOPPED') return 58;
    if (s == 'MAINTENANCE') return 72;
    return 75;
  }

  int _healthFromTelemetry(Map<String, dynamic>? latest, Map<String, dynamic> machine) {
    if (latest == null) return _healthFromStatus(machine['status']?.toString());
    final riskRaw = latest['prob_panne'] ??
        latest['panne_probability'] ??
        latest['scenarioProbPanne'];
    final num? riskNum = riskRaw is num ? riskRaw : num.tryParse(riskRaw?.toString() ?? '');
    if (riskNum == null) return _healthFromStatus(machine['status']?.toString());
    final riskPct = (riskNum <= 1 ? riskNum * 100 : riskNum).round().clamp(0, 100);
    return (100 - riskPct).clamp(0, 100);
  }

  (Color, Color) _progressColors(int health) {
    if (health >= 85) return (_secondary, _green);
    if (health >= 60) return (_secondary, _primary);
    return (_primary, _errorColor);
  }

  String _statusUi(String? status) {
    final s = (status ?? '').toUpperCase();
    if (s == 'RUNNING' || s == 'NORMAL') return 'ACTIVE (EN LIGNE)';
    if (s == 'STOPPED') return 'ARRETEE';
    if (s == 'MAINTENANCE') return 'MAINTENANCE';
    return s.isEmpty ? 'STATUT INCONNU' : s;
  }

  Color _statusColor(String? status) {
    final s = (status ?? '').toUpperCase();
    if (s == 'RUNNING' || s == 'NORMAL') return _green;
    if (s == 'STOPPED') return _orange;
    if (s == 'MAINTENANCE') return _primary;
    return _onSurfaceVariant;
  }

  String _relativeTime(dynamic raw) {
    if (raw == null) return '—';
    final dt = DateTime.tryParse(raw.toString());
    if (dt == null) return '—';
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Il y a ${diff.inSeconds} sec';
    if (diff.inMinutes < 60) return 'Il y a ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Il y a ${diff.inHours} h';
    if (diff.inDays < 7) return 'Il y a ${diff.inDays} j';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  DateTime _parseDate(dynamic raw) {
    if (raw == null) return DateTime.fromMillisecondsSinceEpoch(0);
    return DateTime.tryParse(raw.toString()) ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  void _applySort(List<_MachineListItem> rows) {
    switch (_sortKey) {
      case 'health_asc':
        rows.sort((a, b) => a.health.compareTo(b.health));
        break;
      case 'updated_desc':
        rows.sort((a, b) => b.sortDate.compareTo(a.sortDate));
        break;
      case 'health_desc':
      default:
        rows.sort((a, b) => b.health.compareTo(a.health));
        break;
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final clients = await ApiService.getClients();
      final machinesRaw = _filterClientId == null || _filterClientId!.isEmpty
          ? await ApiService.getMachines()
          : await ApiService.getMachinesForClient(_filterClientId!);
      final machines = _onlyDbMachines(machinesRaw);

      final enriched = await Future.wait(
        machines.map((m) async {
          final id = _machineIdOf(m);
          final name = (m['name'] ?? 'Machine').toString();
          final type = (m['type'] ?? '').toString().trim();
          final displayName = type.isNotEmpty ? '$name ($type)' : name;
          final companyId = m['companyId']?.toString();
          final clientName = _clientNameForCompanyId(companyId, clients);
          final status = m['status']?.toString();
          final loc = (m['location'] ?? '—').toString();
          final updatedRaw = m['updatedAt'] ?? m['createdAt'];
          Map<String, dynamic>? latest;
          if (id.isNotEmpty) {
            try {
              latest = await ApiService.getLatestTelemetry(id);
            } catch (_) {
              latest = null;
            }
          }
          final health = _healthFromTelemetry(latest, m);
          final prog = _progressColors(health);
          return _MachineListItem(
            raw: m,
            id: id.isNotEmpty ? id : '—',
            displayName: displayName,
            clientName: clientName,
            statusLabel: _statusUi(status),
            statusColor: _statusColor(status),
            location: loc.isEmpty ? '—' : loc,
            lastUpdateLabel: _relativeTime(updatedRaw),
            health: health,
            sortDate: _parseDate(updatedRaw),
            progressColorTop: prog.$1,
            progressColorBottom: prog.$2,
          );
        }),
      );

      _applySort(enriched);

      if (!mounted) return;
      setState(() {
        _clients = clients;
        _items = enriched;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString();
        _loading = false;
      });
    }
  }

  bool _canDeleteMachineId(String id) {
    final s = id.trim();
    return s.isNotEmpty && s != '—';
  }

  Future<void> _confirmDeleteMachine(BuildContext context, String id, String name) async {
    if (!_canDeleteMachineId(id)) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surfaceContainerLow,
        title: Text(
          'Supprimer cette machine ?',
          style: GoogleFonts.inter(color: _onSurface, fontWeight: FontWeight.w700),
        ),
        content: Text(
          'La machine $id (${name.length > 40 ? '${name.substring(0, 40)}…' : name}) sera retirée de la base de données. Action irréversible.',
          style: GoogleFonts.spaceGrotesk(color: _onSurfaceVariant, fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Annuler', style: GoogleFonts.spaceGrotesk(color: _secondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Supprimer', style: GoogleFonts.spaceGrotesk(color: _errorColor, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ApiService.deleteMachine(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Machine supprimée', style: GoogleFonts.inter()),
          backgroundColor: _green,
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', ''), style: GoogleFonts.inter()),
          backgroundColor: _errorColor,
        ),
      );
    }
  }

  Widget _buildClientFilter(bool isDesktop) {
    final items = <DropdownMenuItem<String?>>[
      DropdownMenuItem<String?>(
        value: null,
        child: Text('Tous les clients', style: GoogleFonts.spaceGrotesk(color: _onSurface, fontSize: 14)),
      ),
      ..._clients.map((c) {
        final id = _clientApiId(c);
        if (id.isEmpty) return null;
        return DropdownMenuItem<String?>(
          value: id,
          child: Text(
            (c['name'] ?? id).toString(),
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.spaceGrotesk(color: _onSurface, fontSize: 14),
          ),
        );
      }).whereType<DropdownMenuItem<String?>>(),
    ];

    return Container(
      width: isDesktop ? 220 : double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: const BoxDecoration(
        color: _surfaceContainer,
        border: Border(bottom: BorderSide(color: _outlineVariant)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          isExpanded: true,
          value: _filterClientId,
          icon: Icon(Icons.keyboard_arrow_down, color: _onSurfaceVariant, size: 18),
          dropdownColor: _surfaceContainerLow,
          style: GoogleFonts.spaceGrotesk(color: _onSurface, fontSize: 14),
          items: items,
          onChanged: (v) {
            setState(() => _filterClientId = v);
            _load();
          },
        ),
      ),
    );
  }

  Widget _buildSortFilter(bool isDesktop) {
    return Container(
      width: isDesktop ? 220 : double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: const BoxDecoration(
        color: _surfaceContainer,
        border: Border(bottom: BorderSide(color: _outlineVariant)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: _sortKey,
          icon: Icon(Icons.keyboard_arrow_down, color: _onSurfaceVariant, size: 18),
          dropdownColor: _surfaceContainerLow,
          style: GoogleFonts.spaceGrotesk(color: _onSurface, fontSize: 14),
          items: [
            DropdownMenuItem(value: 'health_desc', child: Text('Santé (décroissant)', style: GoogleFonts.spaceGrotesk(fontSize: 14))),
            DropdownMenuItem(value: 'health_asc', child: Text('Santé (croissant)', style: GoogleFonts.spaceGrotesk(fontSize: 14))),
            DropdownMenuItem(value: 'updated_desc', child: Text('Dernière mise à jour', style: GoogleFonts.spaceGrotesk(fontSize: 14))),
          ],
          onChanged: (v) {
            if (v == null) return;
            setState(() => _sortKey = v);
            final copy = List<_MachineListItem>.from(_items);
            _applySort(copy);
            setState(() => _items = copy);
          },
        ),
      ),
    );
  }

  Widget _buildFiltersRow(bool isDesktop) {
    if (isDesktop) {
      return Wrap(
        alignment: WrapAlignment.end,
        spacing: 16,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.filter_list, color: _secondary.withOpacity(0.6), size: 18),
              const SizedBox(width: 8),
              _buildClientFilter(true),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.sort, color: _secondary.withOpacity(0.6), size: 18),
              const SizedBox(width: 8),
              _buildSortFilter(true),
            ],
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.filter_list, color: _secondary.withOpacity(0.6), size: 18),
            const SizedBox(width: 8),
            Expanded(child: _buildClientFilter(false)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Icon(Icons.sort, color: _secondary.withOpacity(0.6), size: 18),
            const SizedBox(width: 8),
            Expanded(child: _buildSortFilter(false)),
          ],
        ),
      ],
    );
  }

  List<Widget> _columnChildren(List<_MachineListItem> slice) {
    final out = <Widget>[];
    for (var i = 0; i < slice.length; i++) {
      out.add(_buildMachineCardFromItem(slice[i]));
      if (i < slice.length - 1) out.add(const SizedBox(height: 24));
    }
    return out;
  }

  Widget _desktopLayout(List<_MachineListItem> items) {
    final col0 = <_MachineListItem>[];
    final col1 = <_MachineListItem>[];
    final col2 = <_MachineListItem>[];
    for (var i = 0; i < items.length; i++) {
      if (i % 3 == 0) {
        col0.add(items[i]);
      } else if (i % 3 == 1) {
        col1.add(items[i]);
      } else {
        col2.add(items[i]);
      }
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Column(children: _columnChildren(col0))),
        const SizedBox(width: 24),
        Expanded(
          child: Column(
            children: [
              ..._columnChildren(col1),
              if (col1.isNotEmpty) const SizedBox(height: 24),
              _buildMapCard(context, items),
            ],
          ),
        ),
        const SizedBox(width: 24),
        Expanded(child: Column(children: _columnChildren(col2))),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 992;

    return Scaffold(
      backgroundColor: _bg,
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Liste des Machines Actives',
                        style: GoogleFonts.inter(
                          fontSize: isDesktop ? 36 : 24,
                          fontWeight: FontWeight.w800,
                          color: _onSurface,
                          letterSpacing: -1.0,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Machines enregistrées en base (filtrables par client)',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 14,
                          color: _onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isDesktop)
                  Expanded(
                    flex: 2,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: _buildFiltersRow(true),
                    ),
                  ),
              ],
            ),
            if (!isDesktop) ...[
              const SizedBox(height: 24),
              _buildFiltersRow(false),
            ],
            const SizedBox(height: 32),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator(color: _secondary)),
              )
            else if (_loadError != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Impossible de charger les machines.',
                      style: GoogleFonts.inter(color: _errorColor, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Text(_loadError!, style: GoogleFonts.spaceGrotesk(color: _onSurfaceVariant, fontSize: 12)),
                    const SizedBox(height: 16),
                    TextButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh, color: _secondary),
                      label: Text('Réessayer', style: GoogleFonts.spaceGrotesk(color: _secondary)),
                    ),
                  ],
                ),
              )
            else if (_items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 48),
                child: Text(
                  _filterClientId == null
                      ? 'Aucune machine en base de données.'
                      : 'Aucune machine pour ce client.',
                  style: GoogleFonts.inter(color: _onSurfaceVariant, fontSize: 16),
                ),
              )
            else if (isDesktop)
              _desktopLayout(_items)
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ..._items.map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: 24),
                        child: _buildMachineCardFromItem(e),
                      )),
                  _buildMapCard(context, _items),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMachineCardFromItem(_MachineListItem e) {
    return _buildMachineCard(
      context: context,
      id: e.id,
      name: e.displayName,
      client: e.clientName,
      status: e.statusLabel,
      statusColor: e.statusColor,
      location: e.location,
      time: e.lastUpdateLabel,
      health: e.health,
      progressColorTop: e.progressColorTop,
      progressColorBottom: e.progressColorBottom,
    );
  }

  Widget _buildMachineCard({
    required BuildContext context,
    required String id,
    required String name,
    required String client,
    required String status,
    required Color statusColor,
    required String location,
    required String time,
    required int health,
    required Color progressColorTop,
    required Color progressColorBottom,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: _surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _outlineVariant.withOpacity(0.15)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
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
              hoverColor: _surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ID: $id',
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 10,
                              color: _secondary,
                              letterSpacing: 2.0,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            name,
                            style: GoogleFonts.inter(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: _onSurface,
                              letterSpacing: -0.5,
                            ),
                          ),
                          Text(
                            client,
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 12,
                              color: _onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: statusColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            status,
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: statusColor,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildIconLabelRow(Icons.location_on, 'LOCALISATION', location),
                          const SizedBox(height: 16),
                          _buildIconLabelRow(Icons.schedule, 'DERNIERE MISE A JOUR', time),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'SANTÉ',
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 10,
                            color: _onSurfaceVariant.withOpacity(0.6),
                          ),
                        ),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              health.toString(),
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 36,
                                fontWeight: FontWeight.w900,
                                color: _onSurface,
                              ),
                            ),
                            Text(
                              '%',
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: _onSurfaceVariant.withOpacity(0.6),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Container(
                  height: 6,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: _surfaceContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: (health.clamp(0, 100)) / 100,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [progressColorTop, progressColorBottom],
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  InkWell(
                    onTap: () {
                      Navigator.pushNamed(context, '/machine-team');
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: _secondary.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: _secondary.withOpacity(0.2)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.groups_outlined, size: 16, color: _secondary),
                          const SizedBox(width: 8),
                          Text(
                            'GESTION ÉQUIPE',
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: _secondary,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (ApiService.canManageFleet)
                    OutlinedButton.icon(
                      onPressed: _canDeleteMachineId(id)
                          ? () => _confirmDeleteMachine(context, id, name)
                          : null,
                      icon: Icon(Icons.delete_outline, size: 18, color: _errorColor),
                      label: Text(
                        'EFFACER',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: _errorColor,
                          letterSpacing: 1.5,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _errorColor,
                        side: BorderSide(color: _errorColor.withOpacity(0.45)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
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

  Widget _buildIconLabelRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: _onSurfaceVariant.withOpacity(0.4)),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 9,
                color: _onSurfaceVariant.withOpacity(0.6),
              ),
            ),
            Text(
              value,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: _onSurface,
              ),
            ),
          ],
        )
      ],
    );
  }

  Widget _buildMapCard(BuildContext context, List<_MachineListItem> items) {
    final uniqueSites = items.map((e) => e.location).where((s) => s != '—').toSet().length;
    final total = items.length;
    return Container(
      height: 480,
      decoration: BoxDecoration(
        color: _surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _outlineVariant.withOpacity(0.15)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Opacity(
            opacity: 0.4,
            child: Image.network(
              'https://lh3.googleusercontent.com/aida-public/AB6AXuB0OPmTJCulFXNoAxqsKwv_9VrZ2n7honPKGBblTl1fznnrXUJnbEvG6nUtcNx1gA__fDNrrQSWGQy2ZOhMRXJ0c4e3D2Wo7G3SGHTgMbZd6wvnIh57MDbJTLOPyi_pmONDjlenm5fmpglB47Y2-pPUTGrRLDIZBa2FTsTvpkos_XbnNDXN9oWxs9GOpmBNXwTojMxS-Gf18GFTkEYx2YpIVx8JV4pBQNTdjm08WjPIJpzjb6zn-1xDq-WVBjkxIFaanPccbeaDPRY',
              fit: BoxFit.cover,
            ),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  _bg.withOpacity(0.8),
                  Colors.transparent,
                  Colors.transparent,
                ],
              ),
            ),
          ),
          Positioned(
            top: 24,
            left: 24,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Couverture Géographique',
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _onSurface,
                  ),
                ),
                Text(
                  'Basé sur les machines affichées',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 10,
                    color: _onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            bottom: 24,
            left: 24,
            right: 24,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  children: [
                    _buildMapStatBox('Sites (filtre)', '$uniqueSites', _secondary),
                    const SizedBox(width: 16),
                    _buildMapStatBox('Machines', '$total', _primary),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _surfaceContainerHighest.withOpacity(0.8),
                    shape: BoxShape.circle,
                    border: Border.all(color: _outlineVariant.withOpacity(0.3)),
                  ),
                  child: const Icon(Icons.map, color: _onSurface, size: 20),
                )
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildMapStatBox(String label, String value, Color valueColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: _surfaceContainer.withOpacity(0.6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _outlineVariant.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: GoogleFonts.spaceGrotesk(
              fontSize: 9,
              color: _onSurfaceVariant,
            ),
          ),
          Text(
            value,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}
