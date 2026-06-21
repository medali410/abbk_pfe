import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import 'services/api_service.dart';

enum _HistoryType { all, missions, consultations }

class ControlReportsHistoryPage extends StatefulWidget {
  const ControlReportsHistoryPage({
    super.key,
    this.initialArguments,
    this.onClose,
  });

  final Map<String, dynamic>? initialArguments;
  final VoidCallback? onClose;

  @override
  State<ControlReportsHistoryPage> createState() => _ControlReportsHistoryPageState();
}

class _ControlReportsHistoryPageState extends State<ControlReportsHistoryPage>
    with SingleTickerProviderStateMixin {
  // ── Palette ──────────────────────────────────────────────────────────
  static const _bg            = Color(0xFF0D0D1E);
  static const _surface       = Color(0xFF1A1A2E);
  static const _surfaceHigh   = Color(0xFF232340);
  static const _accent        = Color(0xFFFF6E00);
  static const _accentBlue    = Color(0xFF75D1FF);
  static const _muted         = Color(0xFF8888AA);
  static const _ok            = Color(0xFF43A047);
  static const _warn          = Color(0xFFFB8C00);

  // ── State ─────────────────────────────────────────────────────────────
  bool _argsLoaded = false;
  bool _loading    = true;
  String? _error;

  String _technicianName = 'TECHNICIEN';
  // ignore: unused_field
  String _technicianId   = '';

  List<Map<String, dynamic>> _allItems = [];
  _HistoryType _typeFilter = _HistoryType.all;

  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  // ── Lifecycle ─────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_argsLoaded) return;
    _argsLoaded = true;
    final routeArgs = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    final args = widget.initialArguments ?? routeArgs;
    _technicianName = (args?['technicianName'] ?? 'TECHNICIEN').toString();
    _technicianId   = (args?['technicianId']   ?? '').toString().trim();
    _loadHistory();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  // ── Data loading ───────────────────────────────────────────────────────
  DateTime? _parseDate(dynamic v) {
    if (v is DateTime) return v;
    if (v is String && v.trim().isNotEmpty) return DateTime.tryParse(v.trim());
    return null;
  }

  Future<void> _loadHistory() async {
    setState(() { _loading = true; _error = null; });
    try {
      // Load missions and consultations in parallel
      final results = await Future.wait([
        _fetchMissions(),
        _fetchConsultations(),
      ]);

      final missions      = results[0];
      final consultations = results[1];

      // Merge into a unified list with a 'kind' tag
      final all = <Map<String, dynamic>>[
        ...missions.map((m) => {...m, '_kind': 'mission'}),
        ...consultations.map((c) => {...c, '_kind': 'consultation'}),
      ];

      // Sort by date descending (most recent first)
      all.sort((a, b) {
        final da = _parseDate(_dateOf(a));
        final db = _parseDate(_dateOf(b));
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        return db.compareTo(da);
      });

      if (!mounted) return;
      setState(() { _allItems = all; _loading = false; });
      _fadeCtrl.forward(from: 0);
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = e.toString().replaceFirst('Exception: ', ''); });
    }
  }

  Future<List<Map<String, dynamic>>> _fetchMissions() async {
    try {
      // Fetch directly from /missions/me — reads the Mission table for the logged-in technician (_technicianId: $_technicianId)
      return await ApiService.getMyMissions();
    } catch (_) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _fetchConsultations() async {
    try {
      return await ApiService.getConsultations();
    } catch (_) {
      return [];
    }
  }

  dynamic _dateOf(Map<String, dynamic> item) {
    if (item['_kind'] == 'mission') {
      // Mission table fields: scheduledAt, completedAt, createdAt
      return item['scheduledAt'] ?? item['completedAt'] ?? item['createdAt'] ?? item['updatedAt'];
    }
    return item['scheduledDate'] ?? item['createdAt'] ?? item['updatedAt'];
  }

  // ── Filter ────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> get _filtered {
    if (_typeFilter == _HistoryType.all) return _allItems;
    final kind = _typeFilter == _HistoryType.missions ? 'mission' : 'consultation';
    return _allItems.where((i) => i['_kind'] == kind).toList();
  }

  // ── Helpers ───────────────────────────────────────────────────────────
  String _formatDate(dynamic raw) {
    final dt = _parseDate(raw);
    if (dt == null) return 'Date inconnue';
    return DateFormat('dd MMM yyyy à HH:mm', 'fr_FR').format(dt.toLocal());
  }

  Color _missionStatusColor(String status) {
    switch (status.toUpperCase()) {
      case 'COMPLETED': return _ok;
      case 'CONFIRMED':
      case 'STARTED':   return _accentBlue;
      case 'SENT':      return _warn;
      default:          return _muted;
    }
  }

  String _missionStatusLabel(String status) {
    switch (status.toUpperCase()) {
      case 'COMPLETED': return 'Terminée';
      case 'CONFIRMED': return 'Confirmée';
      case 'STARTED':   return 'En cours';
      case 'SENT':      return 'En attente';
      default:          return status;
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final missionCount = _allItems.where((i) => i['_kind'] == 'mission').length;
    final consultCount  = _allItems.where((i) => i['_kind'] == 'consultation').length;

    return Scaffold(
      backgroundColor: _bg,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _accent))
          : _error != null
              ? _buildError()
              : RefreshIndicator(
                  color: _accent,
                  backgroundColor: _surface,
                  onRefresh: _loadHistory,
                  child: CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(child: _buildHeader(missionCount, consultCount)),
                      SliverToBoxAdapter(child: _buildFilterBar()),
                      if (filtered.isEmpty)
                        SliverFillRemaining(child: _buildEmpty())
                      else
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (ctx, i) => FadeTransition(
                                opacity: _fadeAnim,
                                child: filtered[i]['_kind'] == 'mission'
                                    ? _buildMissionCard(filtered[i])
                                    : _buildConsultationCard(filtered[i]),
                              ),
                              childCount: filtered.length,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }

  // ── Sub-widgets ────────────────────────────────────────────────────────
  Widget _buildHeader(int missionCount, int consultCount) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_accent.withValues(alpha: 0.15), _accentBlue.withValues(alpha: 0.08)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _accent.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.history, color: _accent, size: 26),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Historique d\'activité',
                  style: GoogleFonts.spaceGrotesk(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _technicianName.toUpperCase(),
                  style: GoogleFonts.inter(color: _muted, fontSize: 12, letterSpacing: 1.2),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _statPill(Icons.rocket_launch_outlined, '$missionCount missions', _accent),
              const SizedBox(height: 6),
              _statPill(Icons.event_outlined, '$consultCount consultations', _accentBlue),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statPill(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 12),
          const SizedBox(width: 5),
          Text(label, style: GoogleFonts.inter(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: _surfaceHigh.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                _filterBtn(_HistoryType.all,          Icons.list_alt,             'Tout'),
                _filterBtn(_HistoryType.missions,     Icons.rocket_launch_outlined, 'Missions'),
                _filterBtn(_HistoryType.consultations, Icons.event_outlined,       'Consultations'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _filterBtn(_HistoryType type, IconData icon, String label) {
    final active = _typeFilter == type;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _typeFilter = type),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? _accent : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: active ? Colors.white : _muted, size: 15),
              const SizedBox(width: 5),
              Text(
                label,
                style: GoogleFonts.inter(
                  color: active ? Colors.white : _muted,
                  fontWeight: active ? FontWeight.w700 : FontWeight.normal,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMissionCard(Map<String, dynamic> m) {
    final rawStatus  = (m['missionStatus'] ?? m['status'] ?? 'SENT').toString().toUpperCase();
    final statusColor = _missionStatusColor(rawStatus);
    final machineName = (m['machineName'] ?? m['machineId'] ?? 'Machine inconnue').toString();
    final agentName   = (m['senderName'] ?? m['agentName'] ?? m['maintenanceAgentName'] ?? '').toString().trim();
    final description = (m['description'] ?? m['title'] ?? '').toString().trim();
    final date        = _dateOf(m);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColor.withValues(alpha: 0.4), width: 1.2),
        boxShadow: [BoxShadow(color: statusColor.withValues(alpha: 0.06), blurRadius: 10)],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Row(
          children: [
            // Left color bar
            Container(
              width: 4,
              height: double.infinity,
              color: statusColor,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: _accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.rocket_launch_outlined, color: _accent, size: 16),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            machineName,
                            style: GoogleFonts.spaceGrotesk(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        _statusBadge(_missionStatusLabel(rawStatus), statusColor),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (agentName.isNotEmpty) _infoRow(Icons.engineering, 'Agent : $agentName', _accent),
                    if (description.isNotEmpty) _infoRow(Icons.notes, description, _muted),
                    const SizedBox(height: 4),
                    _infoRow(Icons.access_time, _formatDate(date), _muted),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConsultationCard(Map<String, dynamic> c) {
    final machineName = (c['machineName'] ?? c['machineId'] ?? 'Machine inconnue').toString();
    final date        = c['scheduledDate'] ?? c['createdAt'];
    final type        = (c['consultationType'] ?? c['type'] ?? '').toString().trim();
    final note        = (c['note'] ?? c['description'] ?? '').toString().trim();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _accentBlue.withValues(alpha: 0.35), width: 1.2),
        boxShadow: [BoxShadow(color: _accentBlue.withValues(alpha: 0.05), blurRadius: 10)],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Row(
          children: [
            Container(width: 4, height: double.infinity, color: _accentBlue),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: _accentBlue.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.event_outlined, color: _accentBlue, size: 16),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            machineName,
                            style: GoogleFonts.spaceGrotesk(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        _statusBadge('Consultation', _accentBlue),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (type.isNotEmpty) _infoRow(Icons.category_outlined, type, _accentBlue),
                    if (note.isNotEmpty) _infoRow(Icons.notes, note, _muted),
                    const SizedBox(height: 4),
                    _infoRow(Icons.calendar_today_outlined, _formatDate(date), _muted),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(color: color, fontWeight: FontWeight.w700, fontSize: 10),
      ),
    );
  }

  Widget _infoRow(IconData icon, String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(color: color, fontSize: 12),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.history_toggle_off, size: 72, color: _muted.withValues(alpha: 0.4)),
          const SizedBox(height: 16),
          Text(
            'Aucune activité trouvée',
            style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Les missions et consultations apparaîtront ici.',
            style: GoogleFonts.inter(color: _muted, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
            const SizedBox(height: 12),
            Text(_error!, style: GoogleFonts.inter(color: Colors.white), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _loadHistory,
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
              style: FilledButton.styleFrom(backgroundColor: _accent),
            ),
          ],
        ),
      ),
    );
  }
}
