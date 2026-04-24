import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'add_conception_page.dart';
import 'add_concepteur_page.dart';
import 'client_detail_page.dart';
import 'services/api_service.dart';

/// Fiche concepteur — tableau de bord style « Kinetic Dash » (spécialiste conception).
class ConcepteurDetailPage extends StatefulWidget {
  final String concepteurId;

  const ConcepteurDetailPage({super.key, required this.concepteurId});

  @override
  State<ConcepteurDetailPage> createState() => _ConcepteurDetailPageState();
}

class _DashBundle {
  final Map<String, dynamic> concepteur;
  final List<Map<String, dynamic>> clients;
  final List<Map<String, dynamic>> machines;

  _DashBundle({
    required this.concepteur,
    required this.clients,
    required this.machines,
  });
}

class _ConcepteurDetailPageState extends State<ConcepteurDetailPage> {
  static const _bg = Color(0xFF10102B);
  static const _surface = Color(0xFF1D1D38);
  static const _surfaceLow = Color(0xFF191934);
  static const _surfaceLowest = Color(0xFF0B0B26);
  static const _surfaceHigh = Color(0xFF272743);
  static const _surfaceVariant = Color(0xFF32324E);
  static const _onSurface = Color(0xFFE2DFFF);
  static const _onVariant = Color(0xFFE2BFB0);
  static const _primary = Color(0xFFFFB692);
  static const _primaryContainer = Color(0xFFFF6E00);
  static const _secondary = Color(0xFF75D1FF);
  static const _secondaryContainer = Color(0xFF009CCE);
  static const _outlineVariant = Color(0xFF594136);
  static const _green = Color(0xFF66BB6A);
  static const _error = Color(0xFFFFB4AB);

  static const _defaultAvatar =
      'https://lh3.googleusercontent.com/aida-public/AB6AXuDRzhfMjrMh4cOZNKCt3gEM5va9D24SgcMRdM9AHYH6tqaY_AVsiC8pNi-wc5APZoppN6Kpq1afBcHIr6JxEJB4Lyd8h-vl8oOlfkcyDcBQXU-bQITJ8NkJvtLhFPclPCHg_D1CoO51h-cBfqhJRXwgC0tj5Rovni1I3g8ZytgyTx8n9V27BiewatMfAvBl7ffS8BNiUKbRYDiiwJUnVYPDg0p3b6OIgXYK6tbkuW52acSwnJhVjcyiHYymBJ-v_78srbmYtShsXso';

  late Future<_DashBundle> _future;
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  int _pageIndex = 0;
  static const int _pageSize = 6;

  @override
  void initState() {
    super.initState();
    _future = _load();
    _searchCtrl.addListener(() {
      final q = _searchCtrl.text.trim().toLowerCase();
      if (q != _searchQuery) {
        setState(() {
          _searchQuery = q;
          _pageIndex = 0;
        });
      }
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<_DashBundle> _load() async {
    final conc = await ApiService.getConcepteur(widget.concepteurId);
    final clients = await ApiService.getClients();
    final machines = await ApiService.getMachines();
    return _DashBundle(concepteur: conc, clients: clients, machines: machines);
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  String _clientKey(Map<String, dynamic> c) {
    final v = c['clientId'] ?? c['id'] ?? c['_id'];
    return v == null ? '' : v.toString();
  }

  String _machineKey(Map<String, dynamic> m) {
    return (m['id'] ?? m['machineId'] ?? m['_id'] ?? '').toString();
  }

  Set<String> _portfolioClientKeys(Map<String, dynamic> conc, List<Map<String, dynamic>> machines) {
    final companyId = (conc['companyId'] ?? '').toString().trim();
    final mids = <String>{};
    final raw = conc['machineIds'];
    if (raw is List) {
      for (final e in raw) {
        final s = e.toString().trim();
        if (s.isNotEmpty) mids.add(s);
      }
    }
    final keys = <String>{};
    if (companyId.isNotEmpty) keys.add(companyId);
    for (final m in machines) {
      final mid = _machineKey(m);
      final cid = (m['companyId'] ?? '').toString();
      if (mids.contains(mid) && cid.isNotEmpty) keys.add(cid);
    }
    return keys;
  }

  List<Map<String, dynamic>> _orderedPortfolioClients(_DashBundle bundle) {
    final keys = _portfolioClientKeys(bundle.concepteur, bundle.machines);
    var list = bundle.clients.where((c) => keys.contains(_clientKey(c))).toList();
    if (list.isEmpty && (bundle.concepteur['companyId'] ?? '').toString().isNotEmpty) {
      final ref = (bundle.concepteur['companyId'] ?? '').toString();
      list = bundle.clients.where((c) => _clientKey(c) == ref).toList();
    }
    list.sort((a, b) => ((a['name'] ?? '') as String).toLowerCase().compareTo(((b['name'] ?? '') as String).toLowerCase()));
    return list;
  }

  int _machineCountForClient(String clientKey, List<Map<String, dynamic>> machines) {
    return machines.where((m) => (m['companyId'] ?? '').toString() == clientKey).length;
  }

  String _lastUpdateForClient(String clientKey, Map<String, dynamic> client, List<Map<String, dynamic>> machines) {
    DateTime? best;
    void consider(dynamic v) {
      if (v == null) return;
      try {
        final d = DateTime.parse(v.toString());
        if (best == null || d.isAfter(best!)) best = d;
      } catch (_) {}
    }
    consider(client['updatedAt']);
    consider(client['createdAt']);
    for (final m in machines) {
      if ((m['companyId'] ?? '').toString() != clientKey) continue;
      consider(m['updatedAt']);
      consider(m['createdAt']);
    }
    if (best == null) return '—';
    final d = best!.toLocal();
    const mois = ['janv', 'févr', 'mars', 'avr', 'mai', 'juin', 'juil', 'août', 'sept', 'oct', 'nov', 'déc'];
    return '${d.day} ${mois[d.month - 1]} ${d.year}';
  }

  bool _clientLooksActive(String clientKey, List<Map<String, dynamic>> machines) {
    for (final m in machines) {
      if ((m['companyId'] ?? '').toString() != clientKey) continue;
      final st = (m['status'] ?? '').toString().toUpperCase();
      if (st == 'RUNNING' || st == 'NORMAL') return true;
    }
    return false;
  }

  static const _industryHints = [
    'Manufacturing Hub',
    'Advanced Robotics',
    'Power Distribution',
    'Material Logistics',
    'Process Engineering',
    'Industrial IoT',
  ];

  Future<void> _confirmDelete(Map<String, dynamic> d) async {
    final name = (d['username'] ?? d['email'] ?? '—').toString();
    final id = (d['id'] ?? '').toString();
    if (id.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surfaceLow,
        title: Text('Effacer $name ?', style: GoogleFonts.inter(color: _onSurface, fontWeight: FontWeight.bold)),
        content: Text('Cette action est irréversible.', style: GoogleFonts.spaceGrotesk(color: _onVariant)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Annuler', style: GoogleFonts.inter(color: _onVariant))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: _error.withValues(alpha: 0.35)),
            child: Text('Effacer', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ApiService.deleteConcepteur(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$name supprimé'), backgroundColor: _green));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _openEdit(Map<String, dynamic> d) async {
    final payload = Map<String, dynamic>.from(d);
    payload['id'] = (d['id'] ?? widget.concepteurId).toString();
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(builder: (_) => AddConcepteurPage(initialData: payload)),
    );
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final isDesktop = w >= 900;

    return Scaffold(
      backgroundColor: _bg,
      body: FutureBuilder<_DashBundle>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: _primaryContainer));
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('${snap.error}', style: GoogleFonts.spaceGrotesk(color: _onVariant)),
              ),
            );
          }
          final bundle = snap.data!;
          final conc = bundle.concepteur;
          final portfolio = _orderedPortfolioClients(bundle);
          final filtered = _searchQuery.isEmpty
              ? portfolio
              : portfolio
                  .where((c) {
                    final name = (c['name'] ?? '').toString().toLowerCase();
                    final id = _clientKey(c).toLowerCase();
                    return name.contains(_searchQuery) || id.contains(_searchQuery);
                  })
                  .toList();
          final totalPages = filtered.isEmpty ? 1 : ((filtered.length + _pageSize - 1) ~/ _pageSize);
          final safePage = _pageIndex.clamp(0, totalPages - 1);
          if (safePage != _pageIndex) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _pageIndex = safePage);
            });
          }
          final rangeStart = safePage * _pageSize;
          final pageRows = filtered.skip(rangeStart).take(_pageSize).toList();

          final scopedMachineCount = portfolio.fold<int>(0, (acc, c) => acc + _machineCountForClient(_clientKey(c), bundle.machines));
          final runningInScope = bundle.machines.where((m) {
            final cid = (m['companyId'] ?? '').toString();
            if (!portfolio.any((c) => _clientKey(c) == cid)) return false;
            final st = (m['status'] ?? '').toString().toUpperCase();
            return st == 'RUNNING' || st == 'NORMAL';
          }).length;
          final uptimePct = scopedMachineCount == 0
              ? 99.8
              : ((100 * runningInScope / scopedMachineCount).clamp(0, 100)).toDouble();
          final displayName = (conc['username'] ?? conc['email'] ?? '—').toString();
          final roleLine = ((conc['specialite'] ?? '').toString().trim().isEmpty)
              ? 'Expert conception / maintenance'
              : (conc['specialite'] as String).trim();

          final mainStack = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _KineticTopBar(
                searchController: _searchCtrl,
                onDeployAsset: () {
                  Navigator.push<void>(
                    context,
                    MaterialPageRoute<void>(builder: (_) => const AddConceptionPage()),
                  );
                },
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 100),
                  child: isDesktop
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 4,
                              child: _profileColumn(
                                conc: conc,
                                displayName: displayName,
                                roleLine: roleLine,
                                assetsValidated: scopedMachineCount,
                                uptimePct: uptimePct,
                                onEdit: ApiService.isSuperAdmin ? () => _openEdit(conc) : null,
                                onDelete: ApiService.isSuperAdmin ? () => _confirmDelete(conc) : null,
                              ),
                            ),
                            const SizedBox(width: 32),
                            Expanded(
                              flex: 8,
                              child: _workspaceColumn(
                                portfolio: pageRows,
                                bundle: bundle,
                                filteredLen: filtered.length,
                                rangeStart: rangeStart,
                                onPrev: safePage > 0 ? () => setState(() => _pageIndex--) : null,
                                onNext: safePage < totalPages - 1 ? () => setState(() => _pageIndex++) : null,
                                onOpenClient: (c) {
                                  Navigator.push<void>(
                                    context,
                                    MaterialPageRoute<void>(
                                      builder: (_) => ClientDetailPage(
                                        clientName: (c['name'] ?? _clientKey(c)).toString(),
                                        rawMap: c,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _profileColumn(
                              conc: conc,
                              displayName: displayName,
                              roleLine: roleLine,
                              assetsValidated: scopedMachineCount,
                              uptimePct: uptimePct,
                              onEdit: ApiService.isSuperAdmin ? () => _openEdit(conc) : null,
                              onDelete: ApiService.isSuperAdmin ? () => _confirmDelete(conc) : null,
                            ),
                            const SizedBox(height: 24),
                            _workspaceColumn(
                              portfolio: pageRows,
                              bundle: bundle,
                              filteredLen: filtered.length,
                              rangeStart: rangeStart,
                              onPrev: safePage > 0 ? () => setState(() => _pageIndex--) : null,
                              onNext: safePage < totalPages - 1 ? () => setState(() => _pageIndex++) : null,
                              onOpenClient: (c) {
                                Navigator.push<void>(
                                  context,
                                  MaterialPageRoute<void>(
                                    builder: (_) => ClientDetailPage(
                                      clientName: (c['name'] ?? _clientKey(c)).toString(),
                                      rawMap: c,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                ),
              ),
            ],
          );

          return mainStack;
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push<void>(
            context,
            MaterialPageRoute<void>(builder: (_) => const AddConceptionPage()),
          );
        },
        backgroundColor: _primaryContainer,
        foregroundColor: const Color(0xFF582100),
        icon: const Icon(Icons.add),
        label: Text('Nouvelle conception', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700, fontSize: 11, letterSpacing: 1)),
      ),
    );
  }

  Widget _profileColumn({
    required Map<String, dynamic> conc,
    required String displayName,
    required String roleLine,
    required int assetsValidated,
    required double uptimePct,
    required VoidCallback? onEdit,
    required VoidCallback? onDelete,
  }) {
    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: _surfaceLow,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, 12))],
          ),
          child: Stack(
            children: [
              Positioned(
                top: -40,
                right: -40,
                child: Container(
                  width: 160,
                  height: 160,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: _primary.withValues(alpha: 0.06)),
                ),
              ),
              Column(
                children: [
                  Container(
                    width: 128,
                    height: 128,
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(colors: [_primary, _secondary], begin: Alignment.topLeft, end: Alignment.bottomRight),
                    ),
                    child: Container(
                      decoration: const BoxDecoration(shape: BoxShape.circle, color: _surfaceLow),
                      clipBehavior: Clip.antiAlias,
                      child: Image.network(_defaultAvatar, fit: BoxFit.cover, errorBuilder: (_, __, ___) {
                        return Center(
                          child: Text(initial, style: GoogleFonts.inter(fontSize: 40, fontWeight: FontWeight.bold, color: _primaryContainer)),
                        );
                      }),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(displayName, textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 26, fontWeight: FontWeight.w800, color: _onSurface)),
                  const SizedBox(height: 6),
                  Text(
                    roleLine.toUpperCase(),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.spaceGrotesk(fontSize: 10, fontWeight: FontWeight.w700, color: _primary, letterSpacing: 2),
                  ),
                  const SizedBox(height: 24),
                  Divider(color: _outlineVariant.withValues(alpha: 0.15)),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _metaBlock('System Identifier', (conc['id'] ?? '').toString(), mono: true),
                        const SizedBox(height: 14),
                        _metaBlock('Terminal Location', (conc['location'] ?? '—').toString()),
                        const SizedBox(height: 14),
                        _metaBlock('Communication', (conc['email'] ?? '—').toString()),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: _miniStat('$assetsValidated', 'Assets Validated', _primary),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _miniStat('${uptimePct.toStringAsFixed(1)}%', 'Uptime Score', _secondary),
                      ),
                    ],
                  ),
                  if (onEdit != null || onDelete != null) ...[
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        if (onEdit != null)
                          Expanded(
                            child: OutlinedButton(
                              onPressed: onEdit,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: _primary,
                                side: BorderSide(color: _primary.withValues(alpha: 0.45)),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                              child: Text('Modifier', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                            ),
                          ),
                        if (onEdit != null && onDelete != null) const SizedBox(width: 12),
                        if (onDelete != null)
                          Expanded(
                            child: TextButton(
                              onPressed: onDelete,
                              style: TextButton.styleFrom(foregroundColor: _error, padding: const EdgeInsets.symmetric(vertical: 12)),
                              child: Text('Effacer', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _outlineVariant.withValues(alpha: 0.1)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('REAL-TIME CONNECTION', style: GoogleFonts.spaceGrotesk(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 2, color: _onSurface)),
                  Row(
                    children: [
                      Container(width: 8, height: 8, decoration: const BoxDecoration(color: _green, shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                      Text('ENCRYPTED', style: GoogleFonts.spaceGrotesk(fontSize: 9, fontWeight: FontWeight.w800, color: _green, letterSpacing: 1.5)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: 0.85,
                  minHeight: 4,
                  backgroundColor: _surfaceVariant,
                  color: _secondary,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Signal Stability', style: GoogleFonts.spaceGrotesk(fontSize: 9, color: _onVariant.withValues(alpha: 0.7))),
                  Text('85%', style: GoogleFonts.spaceGrotesk(fontSize: 9, color: _onVariant.withValues(alpha: 0.7))),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _metaBlock(String label, String value, {bool mono = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: GoogleFonts.spaceGrotesk(fontSize: 9, color: _onVariant.withValues(alpha: 0.55), letterSpacing: 2),
        ),
        const SizedBox(height: 4),
        Text(
          value.isEmpty ? '—' : value,
          style: mono
              ? GoogleFonts.spaceGrotesk(fontSize: 13, color: _secondary, letterSpacing: 0.5)
              : GoogleFonts.inter(fontSize: 14, color: _onSurface, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  Widget _miniStat(String value, String label, Color accent) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: _surfaceLowest, borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: GoogleFonts.spaceGrotesk(fontSize: 22, fontWeight: FontWeight.bold, color: accent)),
          const SizedBox(height: 4),
          Text(
            label.toUpperCase(),
            style: GoogleFonts.spaceGrotesk(fontSize: 8, color: _onVariant.withValues(alpha: 0.55), letterSpacing: 1.8),
          ),
        ],
      ),
    );
  }

  Widget _workspaceColumn({
    required List<Map<String, dynamic>> portfolio,
    required _DashBundle bundle,
    required int filteredLen,
    required int rangeStart,
    required VoidCallback? onPrev,
    required VoidCallback? onNext,
    required void Function(Map<String, dynamic>) onOpenClient,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Liste des Clients Contrôlés', style: GoogleFonts.inter(fontSize: 28, fontWeight: FontWeight.w900, color: _onSurface, height: 1.1)),
                  const SizedBox(height: 8),
                  Text(
                    'Surveillance active du portefeuille technologique',
                    style: GoogleFonts.spaceGrotesk(fontSize: 13, color: _onVariant),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () {},
              style: IconButton.styleFrom(backgroundColor: _surfaceHigh, foregroundColor: _onSurface),
              icon: const Icon(Icons.filter_list),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: () {},
              style: IconButton.styleFrom(backgroundColor: _surfaceHigh, foregroundColor: _onSurface),
              icon: const Icon(Icons.download_outlined),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Container(
          decoration: BoxDecoration(
            color: _surfaceLow,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _outlineVariant.withValues(alpha: 0.08)),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 20)],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(_surfaceHigh.withValues(alpha: 0.5)),
                  dataRowMinHeight: 64,
                  columns: [
                    DataColumn(label: _th('Client Entity')),
                    DataColumn(label: _th('Asset Volume')),
                    DataColumn(label: _th('Terminal Update')),
                    DataColumn(label: _th('Status')),
                    DataColumn(label: _th('Action', right: true)),
                  ],
                  rows: List.generate(portfolio.length, (i) {
                    final c = portfolio[i];
                    final ck = _clientKey(c);
                    final n = _machineCountForClient(ck, bundle.machines);
                    final active = _clientLooksActive(ck, bundle.machines);
                    final hint = _industryHints[i % _industryHints.length];
                    final icons = [Icons.factory_outlined, Icons.precision_manufacturing_outlined, Icons.bolt_outlined, Icons.foundation_outlined];
                    final iconColors = [_secondary, _primary, _onVariant, _secondaryContainer];
                    return DataRow(
                      cells: [
                        DataCell(
                          Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: _surfaceLowest,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: _outlineVariant.withValues(alpha: 0.12)),
                                ),
                                child: Icon(icons[i % icons.length], color: iconColors[i % iconColors.length], size: 22),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text((c['name'] ?? ck).toString(), style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: _onSurface, fontSize: 13)),
                                  Text(hint.toUpperCase(), style: GoogleFonts.spaceGrotesk(fontSize: 9, color: _onVariant.withValues(alpha: 0.55))),
                                ],
                              ),
                            ],
                          ),
                        ),
                        DataCell(Text('$n Units', style: GoogleFonts.spaceGrotesk(color: _onSurface))),
                        DataCell(Text(_lastUpdateForClient(ck, c, bundle.machines), style: GoogleFonts.spaceGrotesk(color: _onVariant))),
                        DataCell(_statusChip(active)),
                        DataCell(
                          IconButton(
                            onPressed: () => onOpenClient(c),
                            icon: Icon(Icons.arrow_forward_ios_rounded, size: 16, color: _onVariant.withValues(alpha: 0.7)),
                          ),
                        ),
                      ],
                    );
                  }),
                ),
              ),
              if (portfolio.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    'Aucun client lié à ce compte (vérifiez entreprise / machines assignées).',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.spaceGrotesk(color: _onVariant),
                  ),
                ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                color: _surfaceHigh.withValues(alpha: 0.3),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Vue ${filteredLen == 0 ? 0 : rangeStart + 1}-${rangeStart + portfolio.length} sur $filteredLen entités',
                      style: GoogleFonts.spaceGrotesk(fontSize: 9, color: _onVariant.withValues(alpha: 0.45), letterSpacing: 1),
                    ),
                    Row(
                      children: [
                        TextButton(
                          onPressed: onPrev,
                          child: Text('PRÉC.', style: GoogleFonts.spaceGrotesk(fontSize: 9, letterSpacing: 1)),
                        ),
                        TextButton(
                          onPressed: onNext,
                          child: Text('SUIV.', style: GoogleFonts.spaceGrotesk(fontSize: 9, letterSpacing: 1)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        LayoutBuilder(
          builder: (context, c) {
            final twoCol = c.maxWidth >= 520;
            final charts = [
              _inspectionVelocityCard(),
              _systemAlertsCard(),
            ];
            if (twoCol) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: charts[0]),
                  const SizedBox(width: 28),
                  Expanded(child: charts[1]),
                ],
              );
            }
            return Column(children: [charts[0], const SizedBox(height: 24), charts[1]]);
          },
        ),
      ],
    );
  }

  Widget _th(String s, {bool right = false}) {
    return Align(
      alignment: right ? Alignment.centerRight : Alignment.centerLeft,
      child: Text(
        s.toUpperCase(),
        style: GoogleFonts.spaceGrotesk(fontSize: 9, letterSpacing: 2, color: _onVariant.withValues(alpha: 0.65)),
      ),
    );
  }

  Widget _statusChip(bool active) {
    final color = active ? _green : _onVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: (active ? _green : _outlineVariant).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(
            active ? 'ACTIVE' : 'IDLE',
            style: GoogleFonts.spaceGrotesk(fontSize: 9, fontWeight: FontWeight.w800, color: color, letterSpacing: 1),
          ),
        ],
      ),
    );
  }

  Widget _inspectionVelocityCard() {
    final heights = <double>[0.6, 0.45, 0.85, 0.55, 0.7, 0.95, 0.4];
    const days = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _surfaceLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _outlineVariant.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('INSPECTION VELOCITY', style: GoogleFonts.spaceGrotesk(fontSize: 10, letterSpacing: 2, fontWeight: FontWeight.w700, color: _onSurface)),
          const SizedBox(height: 20),
          SizedBox(
            height: 120,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(7, (i) {
                final h = heights[i];
                final highlight = i == 5;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      height: 120 * h,
                      decoration: BoxDecoration(
                        color: highlight ? _secondary : _secondary.withValues(alpha: 0.22),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                        boxShadow: highlight
                            ? [BoxShadow(color: _secondary.withValues(alpha: 0.35), blurRadius: 12)]
                            : null,
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: days.map((d) => Text(d, style: GoogleFonts.spaceGrotesk(fontSize: 8, color: _onVariant.withValues(alpha: 0.35)))).toList(),
          ),
        ],
      ),
    );
  }

  Widget _systemAlertsCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _surfaceLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _outlineVariant.withValues(alpha: 0.08)),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -12,
            bottom: -12,
            child: Icon(Icons.analytics_outlined, size: 100, color: _onSurface.withValues(alpha: 0.06)),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('SYSTEM ALERTS', style: GoogleFonts.spaceGrotesk(fontSize: 10, letterSpacing: 2, fontWeight: FontWeight.w700, color: _onSurface)),
              const SizedBox(height: 16),
              _alertRow(Icons.warning_amber_rounded, _primary, 'Calibration Drift', 'Vérifiez les capteurs du parc assigné'),
              const SizedBox(height: 10),
              _alertRow(Icons.check_circle_outline, _green, 'Maintenance Success', 'Dernières interventions synchronisées'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _alertRow(IconData icon, Color accent, String title, String sub) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _surfaceLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: accent, width: 2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: accent, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: _onSurface)),
                Text(sub, style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _onVariant.withValues(alpha: 0.55))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _KineticTopBar extends StatelessWidget {
  final TextEditingController searchController;
  final VoidCallback onDeployAsset;

  const _KineticTopBar({required this.searchController, required this.onDeployAsset});

  @override
  Widget build(BuildContext context) {
    const onVar = Color(0xFFE2BFB0);
    const outlineV = Color(0xFF594136);
    const surfaceLowest = Color(0xFF0B0B26);
    const secondary = Color(0xFF75D1FF);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF10102B).withValues(alpha: 0.88),
        border: Border(bottom: BorderSide(color: outlineV.withValues(alpha: 0.15))),
      ),
      child: Row(
        children: [
          if (MediaQuery.sizeOf(context).width < 900)
            IconButton(
              onPressed: () => Navigator.maybePop(context),
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFFE2DFFF)),
            ),
          ShaderMask(
            shaderCallback: (b) => const LinearGradient(colors: [Color(0xFFFF6E00), Color(0xFFFFB692)]).createShader(b),
            child: Text(
              'KINETIC OBSV',
              style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white),
            ),
          ),
          const SizedBox(width: 24),
          if (MediaQuery.sizeOf(context).width >= 600) ...[
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 280),
                child: TextField(
                  controller: searchController,
                  style: GoogleFonts.spaceGrotesk(fontSize: 11, letterSpacing: 2, color: const Color(0xFFE2DFFF)),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: surfaceLowest,
                    hintText: 'QUERY SYSTEM…',
                    hintStyle: GoogleFonts.spaceGrotesk(color: onVar.withValues(alpha: 0.35), fontSize: 10, letterSpacing: 2),
                    prefixIcon: Icon(Icons.search, size: 18, color: onVar.withValues(alpha: 0.6)),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: secondary.withValues(alpha: 0.6)),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
              ),
            ),
          ],
          const Spacer(),
          IconButton(onPressed: () {}, icon: Icon(Icons.notifications_outlined, color: onVar.withValues(alpha: 0.8))),
          IconButton(onPressed: () {}, icon: Icon(Icons.tune, color: onVar.withValues(alpha: 0.8))),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: onDeployAsset,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFF6E00),
              foregroundColor: const Color(0xFF341100),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            ),
            child: Text('DÉPLOYER ACTIF', style: GoogleFonts.spaceGrotesk(fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 1.5)),
          ),
          const SizedBox(width: 16),
          CircleAvatar(
            radius: 20,
            backgroundColor: const Color(0xFF32324E),
            backgroundImage: const NetworkImage(
              'https://lh3.googleusercontent.com/aida-public/AB6AXuBpx_ZsyyTzYuLSBjvykCU9WW3Tz4_slGvRzprETxRIoGemtS7WqBfpcjvKlNcyPMO7nBPoHdlQQOF9O-UEqsRzoYVk-m-CBBV9uLtPy8L4yrVg4yOs0B0DEZ71UdGUb3WOAR6Ax9pf7mXmYWMSvLAy5DAZk7RQ9KC1VgR4ZJLjBIvhECumatYBwN9Qf9Hfu9aTrKMgxK3_66YGDKxpS-65Y2DJdB3HdKEJwqHOG1ddnelVM0l2nXZGXp7iULlD0r5zUdQYeKMKCzQ',
            ),
          ),
        ],
      ),
    );
  }
}
