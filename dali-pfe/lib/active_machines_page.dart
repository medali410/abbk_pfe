 import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'machine_detail_ai_page.dart';
import 'services/api_service.dart';
import 'services/theme_service.dart';

class ActiveMachinesPage extends StatefulWidget {
  final bool embedded;
  final bool isDarkMode;
  final void Function(String machineId, String machineName, {String? clientId, String? location})? onOpenMachine;
  final VoidCallback? onAddTechnician;

  const ActiveMachinesPage({
    super.key,
    this.embedded = false,
    this.isDarkMode = false,
    this.onOpenMachine,
    this.onAddTechnician,
  });

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
  final int pannesCount;
  final String? lastPanneLabel;
  final String lastConsultationLabel;
  final List<String> teamNames;

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
    required this.pannesCount,
    this.lastPanneLabel,
    required this.lastConsultationLabel,
    required this.teamNames,
  });
}

class _ActiveMachinesPageState extends State<ActiveMachinesPage> {
  bool get _dm => ThemeService().isDarkMode;
  Color get _bg => _dm ? const Color(0xFF10102B) : const Color(0xFFF5F0E8);
  Color get _surfaceContainerLow => _dm ? const Color(0xFF191934) : const Color(0xFFF5E0C3);
  Color get _surfaceContainer => _dm ? const Color(0xFF1D1D38) : const Color(0xFFFAEBD7);
  Color get _surfaceContainerHighest => _dm ? const Color(0xFF32324E) : const Color(0xFFFFE4C4);
  Color get _primary => _dm ? const Color(0xFFFFB692) : const Color(0xFFB8860B);
  Color get _secondary => _dm ? const Color(0xFF75D1FF) : const Color(0xFF8B5E3C);
  Color get _onSurface => _dm ? const Color(0xFFE2DFFF) : const Color(0xFF332A21);
  Color get _onSurfaceVariant => _dm ? const Color(0xFFE2BFB0) : const Color(0xFF8B5E3C);
  Color get _outlineVariant => _dm ? const Color(0xFF594136) : const Color(0xFFB87333);
  Color get _green => _dm ? const Color(0xFF66BB6A) : const Color(0xFF2E7D32);
  Color get _errorColor => _dm ? const Color(0xFFFFB4AB) : const Color(0xFFFF6E00);
  Color get _orange => const Color(0xFFFF6E00);

  bool _loading = true;
  String? _loadError;
  List<Map<String, dynamic>> _clients = [];
  List<_MachineListItem> _allItems = [];
  List<_MachineListItem> _items = [];
  String _searchQuery = '';
  String? _filterClientId;
  String _sortKey = 'health_desc';

  @override
  void initState() {
    super.initState();
    ThemeService().addListener(_onThemeChange);
    _load();
  }

  void _onThemeChange() => setState(() {});

  @override
  void dispose() {
    ThemeService().removeListener(_onThemeChange);
    super.dispose();
  }

  String _clientApiId(Map<String, dynamic> c) {
    final v = c['clientId'] ?? c['id'] ?? c['_id'];
    return v?.toString() ?? '';
  }

  String _clientNameForCompanyId(
    String? companyId,
    List<Map<String, dynamic>> clients,
  ) {
    if (companyId == null || companyId.isEmpty) return 'Non assigné';
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

  /// Lignes Mongo valides (id unique), y compris machines non encore assignées à un client.
  List<Map<String, dynamic>> _onlyDbMachines(List<Map<String, dynamic>> raw) {
    final seen = <String>{};
    final out = <Map<String, dynamic>>[];
    for (final m in raw) {
      final id = _machineIdOf(m);
      if (id.isEmpty) continue;
      if (seen.contains(id)) continue;
      seen.add(id);
      out.add(m);
    }
    return out;
  }

  String _normMachineKey(String? id) => (id ?? '').trim().toUpperCase();

  List<String> _machineIdsFromMember(Map<String, dynamic> member) {
    final rawMap = member['raw'];
    final raw = rawMap is Map ? Map<String, dynamic>.from(rawMap) : member;
    final list = raw['machineIds'];
    if (list is! List) return const [];
    return list.map((e) => _normMachineKey(e.toString())).where((s) => s.isNotEmpty).toList();
  }

  String _memberDisplayName(Map<String, dynamic> member) {
    final n = (member['name'] ?? '').toString().trim();
    if (n.isNotEmpty) return n;
    final rawMap = member['raw'];
    if (rawMap is Map) {
      final raw = Map<String, dynamic>.from(rawMap);
      final first = (raw['firstName'] ?? '').toString().trim();
      final last = (raw['lastName'] ?? '').toString().trim();
      final full = '$first $last'.trim();
      if (full.isNotEmpty) return full;
      return (raw['name'] ?? '').toString().trim();
    }
    return '';
  }

  DateTime? _parseOptionalDate(dynamic raw) {
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString());
  }

  DateTime? _controleConsultationDate(Map<String, dynamic> c) {
    return _parseOptionalDate(c['completedAt']) ??
        _parseOptionalDate(c['dateRealisation']) ??
        _parseOptionalDate(c['dateControle']) ??
        _parseOptionalDate(c['updatedAt']);
  }

  ({
    Map<String, List<String>> teamByMachine,
    Map<String, int> pannesCount,
    Map<String, String> lastPanneLabel,
    Map<String, DateTime> lastConsultation,
  }) _buildMachineAggregates({
    required List<Map<String, dynamic>> team,
    required List<Map<String, dynamic>> controles,
    required List<Map<String, dynamic>> archives,
    required List<Map<String, dynamic>> diagnostics,
  }) {
    final teamByMachine = <String, List<String>>{};
    for (final member in team) {
      final name = _memberDisplayName(member);
      if (name.isEmpty) continue;
      for (final mid in _machineIdsFromMember(member)) {
        final list = teamByMachine.putIfAbsent(mid, () => <String>[]);
        if (!list.contains(name)) list.add(name);
      }
    }

    final pannesCount = <String, int>{};
    final lastPanneLabel = <String, String>{};

    void bumpPanne(String? machineId, {String? label}) {
      final key = _normMachineKey(machineId);
      if (key.isEmpty) return;
      pannesCount[key] = (pannesCount[key] ?? 0) + 1;
      if (label != null && label.trim().isNotEmpty) {
        lastPanneLabel[key] = label.trim();
      }
    }

    for (final a in archives) {
      bumpPanne(
        a['machineId']?.toString(),
        label: (a['scenarioLabel'] ?? a['failureType'] ?? 'Panne archivée').toString(),
      );
    }
    for (final d in diagnostics) {
      final st = (d['status'] ?? '').toString().toUpperCase();
      if (st.contains('TERMINE') || st.contains('EN_COURS') || st.contains('NOUVELLE') || st.isEmpty) {
        bumpPanne(
          d['machineId']?.toString(),
          label: (d['scenarioLabel'] ?? d['title'] ?? 'Intervention').toString(),
        );
      }
    }

    final lastConsultation = <String, DateTime>{};
    for (final c in controles) {
      final key = _normMachineKey(c['machineId']?.toString());
      if (key.isEmpty) continue;
      final dt = _controleConsultationDate(c);
      if (dt == null) continue;
      final prev = lastConsultation[key];
      if (prev == null || dt.isAfter(prev)) lastConsultation[key] = dt;
    }

    return (
      teamByMachine: teamByMachine,
      pannesCount: pannesCount,
      lastPanneLabel: lastPanneLabel,
      lastConsultation: lastConsultation,
    );
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
          ? await ApiService.getCatalogMachines(includeAll: true)
          : await ApiService.getMachinesForClient(_filterClientId!);
      final machines = _onlyDbMachines(machinesRaw);

      var team = <Map<String, dynamic>>[];
      var controles = <Map<String, dynamic>>[];
      var archives = <Map<String, dynamic>>[];
      var diagnostics = <Map<String, dynamic>>[];
      await Future.wait([
        ApiService.getTeamDirectory().then((v) => team = v).catchError((_) => <Map<String, dynamic>>[]),
        ApiService.getAllControles(days: 365).then((v) => controles = v).catchError((_) => <Map<String, dynamic>>[]),
        ApiService.getInterventionArchives().then((v) => archives = v).catchError((_) => <Map<String, dynamic>>[]),
        ApiService.getDiagnosticInterventions().then((v) => diagnostics = v).catchError((_) => <Map<String, dynamic>>[]),
      ]);

      final agg = _buildMachineAggregates(
        team: team,
        controles: controles,
        archives: archives,
        diagnostics: diagnostics,
      );

      final enriched = await Future.wait(
        machines.map((m) async {
          final id = _machineIdOf(m);
          final midKey = _normMachineKey(id);
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
          final teamNames = agg.teamByMachine[midKey] ?? const <String>[];
          final pannes = agg.pannesCount[midKey] ?? 0;
          final lastPanne = agg.lastPanneLabel[midKey];
          final consultDt = agg.lastConsultation[midKey];
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
            pannesCount: pannes,
            lastPanneLabel: lastPanne,
            lastConsultationLabel:
                consultDt != null ? _relativeTime(consultDt.toIso8601String()) : 'Aucune consultation',
            teamNames: teamNames,
          );
        }),
      );

      if (!mounted) return;
      setState(() {
        _clients = clients;
        _allItems = enriched;
        _applyFilters();
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

  void _applyFilters() {
    var filtered = _allItems;
    if (_searchQuery.trim().isNotEmpty) {
      final query = _searchQuery.trim().toLowerCase();
      filtered = filtered.where((m) {
        final matchName = m.displayName.toLowerCase().contains(query);
        final matchLocation = m.location.toLowerCase().contains(query);
        return matchName || matchLocation;
      }).toList();
    } else {
      filtered = List.from(filtered);
    }
    _applySort(filtered);
    _items = filtered;
  }

  Widget _buildSearchField(bool isDesktop) {
    return Container(
      width: isDesktop ? 300 : double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: widget.isDarkMode ? const Color(0xFF1E2243).withOpacity(0.9) : const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: widget.isDarkMode ? Colors.white.withOpacity(0.08) : const Color(0xFFCD7F32).withOpacity(0.35),
          width: 1.5,
        ),
      ),
      child: TextField(
        style: GoogleFonts.spaceGrotesk(color: _onSurface, fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Rechercher (nom, localisation)...',
          hintStyle: GoogleFonts.spaceGrotesk(color: _onSurfaceVariant.withOpacity(0.5), fontSize: 14),
          prefixIcon: Icon(Icons.search, color: _onSurfaceVariant.withOpacity(0.8), size: 18),
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
        onChanged: (val) {
          setState(() {
            _searchQuery = val;
            _applyFilters();
          });
        },
      ),
    );
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: widget.isDarkMode ? const Color(0xFF1E2243).withOpacity(0.9) : const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: widget.isDarkMode ? Colors.white.withOpacity(0.08) : const Color(0xFFCD7F32).withOpacity(0.35),
          width: 1.5,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          isExpanded: true,
          value: _filterClientId,
          icon: Icon(Icons.keyboard_arrow_down, color: _onSurfaceVariant, size: 18),
          dropdownColor: widget.isDarkMode ? const Color(0xFF131730) : const Color(0xFFFFFFFF),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: widget.isDarkMode ? const Color(0xFF1E2243).withOpacity(0.9) : const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: widget.isDarkMode ? Colors.white.withOpacity(0.08) : const Color(0xFFCD7F32).withOpacity(0.35),
          width: 1.5,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: _sortKey,
          icon: Icon(Icons.keyboard_arrow_down, color: _onSurfaceVariant, size: 18),
          dropdownColor: widget.isDarkMode ? const Color(0xFF131730) : const Color(0xFFFFFFFF),
          style: GoogleFonts.spaceGrotesk(color: _onSurface, fontSize: 14),
          items: [
            DropdownMenuItem(
              value: 'health_desc',
              child: Text(
                'Santé (décroissant)',
                style: GoogleFonts.spaceGrotesk(
                  color: _onSurface,
                  fontSize: 14,
                ),
              ),
            ),
            DropdownMenuItem(
              value: 'health_asc',
              child: Text(
                'Santé (croissant)',
                style: GoogleFonts.spaceGrotesk(
                  color: _onSurface,
                  fontSize: 14,
                ),
              ),
            ),
            DropdownMenuItem(
              value: 'updated_desc',
              child: Text(
                'Dernière mise à jour',
                style: GoogleFonts.spaceGrotesk(
                  color: _onSurface,
                  fontSize: 14,
                ),
              ),
            ),
          ],
          onChanged: (v) {
            if (v == null) return;
            setState(() {
              _sortKey = v;
              _applyFilters();
            });
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
          _buildSearchField(true),
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
        _buildSearchField(false),
        const SizedBox(height: 12),
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
        Expanded(child: Column(children: _columnChildren(col1))),
        const SizedBox(width: 24),
        Expanded(child: Column(children: _columnChildren(col2))),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 992;

    final body = SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: widget.embedded ? 16 : 24,
          vertical: widget.embedded ? 16 : 32,
        ),
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
                        'Parc machines',
                        style: GoogleFonts.inter(
                          fontSize: isDesktop ? 36 : 24,
                          fontWeight: FontWeight.w800,
                          color: _onSurface,
                          letterSpacing: -1.0,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Sélectionnez une machine pour ouvrir le terminal de supervision.',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 13,
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
                Padding(
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
                      icon: Icon(Icons.refresh, color: _secondary),
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
                ],
              ),
          ],
        ),
      );

    if (widget.embedded) {
      return ColoredBox(color: _bg, child: body);
    }
    return Scaffold(backgroundColor: _bg, body: body);
  }

  Widget _buildMachineCardFromItem(_MachineListItem e) {
    return _buildMachineCard(
      context: context,
      raw: e.raw,
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
      pannesCount: e.pannesCount,
      lastPanneLabel: e.lastPanneLabel,
      lastConsultationLabel: e.lastConsultationLabel,
      teamNames: e.teamNames,
    );
  }

  Widget _buildInsightTile({
    required IconData icon,
    required String label,
    required String value,
    required String? subtitle,
    required Color accent,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: widget.isDarkMode
              ? const Color(0xFF1E2243).withOpacity(0.4)
              : Colors.black.withOpacity(0.04),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: accent.withOpacity(0.18)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: accent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: _onSurfaceVariant.withOpacity(0.75),
                      letterSpacing: 0.8,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: _onSurface,
                height: 1.15,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (subtitle != null && subtitle.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 10,
                  color: _onSurfaceVariant.withOpacity(0.85),
                  height: 1.25,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMachineInsightsRow({
    required int pannesCount,
    required String? lastPanneLabel,
    required String lastConsultationLabel,
    required List<String> teamNames,
  }) {
    final pannesValue = pannesCount == 0 ? '0' : pannesCount.toString();
    final pannesSub = pannesCount == 0
        ? 'Aucune panne archivée'
        : (lastPanneLabel ?? 'Historique disponible');
    final teamValue = teamNames.isEmpty
        ? '—'
        : (teamNames.length == 1 ? teamNames.first : '${teamNames.length} membres');
    final teamSub = teamNames.isEmpty
        ? 'Aucun technicien assigné'
        : teamNames.take(3).join(' · ');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildInsightTile(
          icon: Icons.warning_amber_rounded,
          label: 'PANNES',
          value: pannesValue,
          subtitle: pannesSub,
          accent: pannesCount > 0 ? _errorColor : _onSurfaceVariant,
        ),
        const SizedBox(width: 10),
        _buildInsightTile(
          icon: Icons.event_available_outlined,
          label: 'DERNIÈRE CONSULTATION',
          value: lastConsultationLabel,
          subtitle: 'Contrôle / visite terrain',
          accent: _secondary,
        ),
        const SizedBox(width: 10),
        _buildInsightTile(
          icon: Icons.groups_outlined,
          label: 'ÉQUIPE',
          value: teamValue,
          subtitle: teamSub,
          accent: _primary,
        ),
      ],
    );
  }

  Widget _buildMachineCard({
    required BuildContext context,
    Map<String, dynamic>? raw,
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
    required int pannesCount,
    required String? lastPanneLabel,
    required String lastConsultationLabel,
    required List<String> teamNames,
  }) {
    return _HoverCardWrapper(
      isDarkMode: widget.isDarkMode,
      hoverBorderColor: progressColorBottom,
      child: Material(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: () {
                if (widget.onOpenMachine != null) {
                  final r = raw ?? const <String, dynamic>{};
                  final cid = (r['companyId'] ?? r['clientId'] ?? '').toString();
                  widget.onOpenMachine!(
                    id,
                    name,
                    clientId: cid.isEmpty ? null : cid,
                    location: location,
                  );
                  return;
                }
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
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: statusColor.withOpacity(0.25), width: 1),
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
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: statusColor,
                              letterSpacing: 0.2,
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
                const SizedBox(height: 20),
                _buildMachineInsightsRow(
                  pannesCount: pannesCount,
                  lastPanneLabel: lastPanneLabel,
                  lastConsultationLabel: lastConsultationLabel,
                  teamNames: teamNames,
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
                  if (teamNames.isNotEmpty) ...[
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: teamNames.take(5).map((n) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _primary.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: _primary.withOpacity(0.25)),
                          ),
                          child: Text(
                            n,
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: _primary,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                  ],

                  if (ApiService.canManageFleet || ApiService.canAddMachineAsConcepteur)
                    OutlinedButton.icon(
                      onPressed: _canDeleteMachineId(id)
                          ? () => _confirmDeleteMachine(context, id, name)
                          : null,
                      icon: Icon(Icons.delete_outline_rounded, size: 16, color: _errorColor),
                      label: Text(
                        'SUPPRIMER',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: _errorColor,
                          letterSpacing: 1.5,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _errorColor,
                        side: BorderSide(color: _errorColor.withOpacity(0.25)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        backgroundColor: _errorColor.withOpacity(0.04),
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

}

class _HoverCardWrapper extends StatefulWidget {
  final Widget child;
  final Color hoverBorderColor;
  final bool isDarkMode;
  const _HoverCardWrapper({
    required this.child,
    required this.hoverBorderColor,
    this.isDarkMode = false,
  });

  @override
  State<_HoverCardWrapper> createState() => _HoverCardWrapperState();
}

class _HoverCardWrapperState extends State<_HoverCardWrapper> {
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
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: widget.isDarkMode
                ? [
                    const Color(0xFF1E2243).withOpacity(0.95),
                    const Color(0xFF131730).withOpacity(0.85),
                  ]
                : [
                    const Color(0xFFF5E0C3).withOpacity(0.95),
                    const Color(0xFFFAEBD7).withOpacity(0.85),
                  ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _isHovered 
                ? widget.hoverBorderColor.withOpacity(0.6) 
                : (widget.isDarkMode ? Colors.white.withOpacity(0.08) : const Color(0xFFCD7F32).withOpacity(0.2)),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: _isHovered ? widget.hoverBorderColor.withOpacity(0.2) : Colors.black.withOpacity(0.3),
              blurRadius: _isHovered ? 24 : 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: widget.child,
      ),
    );
  }
}
