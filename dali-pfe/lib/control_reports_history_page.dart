import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'services/api_service.dart';

enum _ReportStatusFilter { all, valide, anomalie }

class ControlReportsHistoryPage extends StatefulWidget {
  const ControlReportsHistoryPage({
    super.key,
    this.initialArguments,
    this.onClose,
  });

  /// Depuis le profil technicien (sans route nommée).
  final Map<String, dynamic>? initialArguments;

  /// Fermer le panneau embarqué (profil + sidebar visibles).
  final VoidCallback? onClose;

  @override
  State<ControlReportsHistoryPage> createState() => _ControlReportsHistoryPageState();
}

class _ControlReportsHistoryPageState extends State<ControlReportsHistoryPage> {
  static const _bg = Color(0xFF10102B);
  static const _surface = Color(0xFF1D1D38);
  static const _surfaceHeader = Color(0xFF131422);
  static const _accent = Color(0xFFFF6E00);
  static const _muted = Color(0xFFA0A0B0);
  static const _ok = Color(0xFF43A047);
  static const _warn2 = Color(0xFFFB8C00);
  static const _danger = Color(0xFFE53935);

  bool _argsLoaded = false;
  bool _loading = true;
  String? _error;

  String _technicianName = 'TECHNICIEN';
  String _technicianId = '';
  /// `all_controls` = tous les contrôles terminés en base · `reports` = avec compte-rendu / notes saisis.
  String _historyMode = 'all_controls';
  List<Map<String, dynamic>> _reports = <Map<String, dynamic>>[];

  String _machineFilter = 'Toutes';
  _ReportStatusFilter _statusFilter = _ReportStatusFilter.all;
  DateTime? _selectedWeekStart;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_argsLoaded) return;
    _argsLoaded = true;
    final routeArgs = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    final args = widget.initialArguments ?? routeArgs;
    _technicianName = (args?['technicianName'] ?? 'TECHNICIEN').toString();
    _technicianId = (args?['technicianId'] ?? '').toString().trim();
    _historyMode = (args?['historyMode'] ?? 'all_controls').toString().trim();
    if (_historyMode != 'reports') _historyMode = 'all_controls';
    _loadReports();
  }

  DateTime? _asDate(dynamic value) {
    if (value is DateTime) return value;
    if (value is String && value.trim().isNotEmpty) return DateTime.tryParse(value.trim());
    return null;
  }

  DateTime _startOfWeek(DateTime d) {
    final delta = d.weekday - DateTime.monday;
    return DateTime(d.year, d.month, d.day).subtract(Duration(days: delta));
  }

  String _statusLabel(_ReportStatusFilter s) {
    switch (s) {
      case _ReportStatusFilter.all:
        return 'Tous';
      case _ReportStatusFilter.valide:
        return 'Valide';
      case _ReportStatusFilter.anomalie:
        return 'Anomalie';
    }
  }

  String _displayDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';

  Future<void> _loadReports() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_technicianId.isEmpty) {
        throw Exception('Technicien non identifié.');
      }
      final controls = await ApiService.getControlesForTechnician(_technicianId, days: 180);
      final reports = controls.where((c) {
        final isDone = (c['statut'] ?? '').toString().toLowerCase().contains('termin');
        if (!isDone) return false;
        if (_historyMode == 'reports') {
          final hasReport =
              c['rapportControle'] is Map || (c['notes'] ?? '').toString().trim().isNotEmpty;
          return hasReport;
        }
        return true;
      }).map((c) => Map<String, dynamic>.from(c)).toList();

      reports.sort((a, b) {
        final da = _asDate(a['updatedAt'] ?? a['dateControle'] ?? a['createdAt']);
        final db = _asDate(b['updatedAt'] ?? b['dateControle'] ?? b['createdAt']);
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        return db.compareTo(da);
      });

      DateTime? defaultWeek;
      if (reports.isNotEmpty) {
        final firstDate = _asDate(reports.first['updatedAt'] ?? reports.first['dateControle'] ?? reports.first['createdAt']);
        if (firstDate != null) defaultWeek = _startOfWeek(firstDate);
      }
      if (!mounted) return;
      setState(() {
        _reports = reports;
        _selectedWeekStart = defaultWeek;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  List<String> _machines() {
    final names = _reports
        .map((r) => (r['machineName'] ?? r['machineId'] ?? 'Machine').toString())
        .where((v) => v.trim().isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return ['Toutes', ...names];
  }

  bool _hasAnomaly(Map<String, dynamic> report) {
    final nested = report['rapportControle'];
    if (nested is Map && nested['hasAnomaly'] == true) return true;
    final items = (nested is Map) ? nested['items'] : null;
    if (items is List) {
      for (final i in items) {
        if (i is Map) {
          final decision = (i['decision'] ?? '').toString().toLowerCase();
          if (decision.contains('changer')) return true;
        }
      }
    }
    final notes = (report['notes'] ?? '').toString().toLowerCase();
    return notes.contains('à changer') || notes.contains('a changer') || notes.contains('anomal');
  }

  List<Map<String, dynamic>> _filteredReports() {
    return _reports.where((r) {
      final machine = (r['machineName'] ?? r['machineId'] ?? 'Machine').toString();
      if (_machineFilter != 'Toutes' && machine != _machineFilter) return false;

      final hasAnomaly = _hasAnomaly(r);
      if (_statusFilter == _ReportStatusFilter.valide && hasAnomaly) return false;
      if (_statusFilter == _ReportStatusFilter.anomalie && !hasAnomaly) return false;

      if (_selectedWeekStart != null) {
        final date = _asDate(r['updatedAt'] ?? r['dateControle'] ?? r['createdAt']);
        if (date == null) return false;
        final start = _startOfWeek(date);
        if (start != _selectedWeekStart) return false;
      }
      return true;
    }).toList();
  }

  List<DateTime> _weeks() {
    final set = <DateTime>{};
    for (final r in _reports) {
      final date = _asDate(r['updatedAt'] ?? r['dateControle'] ?? r['createdAt']);
      if (date != null) set.add(_startOfWeek(date));
    }
    final list = set.toList()..sort((a, b) => b.compareTo(a));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredReports();
    final machines = _machines();
    final weeks = _weeks();

    return Scaffold(
      backgroundColor: _bg,
      appBar: widget.onClose != null ? null : AppBar(
        backgroundColor: _surfaceHeader,
        title: Text(
          _historyMode == 'reports' ? 'Historique des rapports' : 'Historique des contrôles',
          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _accent))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, color: _danger, size: 38),
                        const SizedBox(height: 10),
                        Text(_error!, style: GoogleFonts.inter(color: Colors.white), textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(onPressed: _loadReports, child: const Text('Réessayer')),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadReports,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: _surfaceHeader,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const CircleAvatar(
                              backgroundColor: _accent,
                              child: Icon(Icons.person, color: Colors.white),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'TECHNICIEN',
                                    style: GoogleFonts.inter(color: _muted, fontSize: 10, letterSpacing: 1.2),
                                  ),
                                  Text(
                                    _technicianName.toUpperCase(),
                                    style: GoogleFonts.spaceGrotesk(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: _accent.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: _accent.withOpacity(0.5)),
                              ),
                              child: Text(
                                _historyMode == 'reports'
                                    ? '${_reports.length} rapports'
                                    : '${_reports.length} contrôles',
                                style: GoogleFonts.inter(color: _accent, fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: _surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: _accent.withOpacity(0.3), width: 1.5),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 4))],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.tune, color: _accent, size: 20),
                                const SizedBox(width: 8),
                                Text('Filtres de recherche', style: GoogleFonts.spaceGrotesk(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Container(
                              decoration: BoxDecoration(color: const Color(0xFF272743), borderRadius: BorderRadius.circular(8)),
                              child: DropdownButtonFormField<String>(
                                value: machines.contains(_machineFilter) ? _machineFilter : 'Toutes',
                                dropdownColor: const Color(0xFF272743),
                                items: machines.map((m) => DropdownMenuItem(value: m, child: Text(m, style: const TextStyle(color: Colors.white)))).toList(),
                                onChanged: (v) => setState(() => _machineFilter = v ?? 'Toutes'),
                                decoration: InputDecoration(labelText: 'Machine', labelStyle: TextStyle(color: Colors.white.withOpacity(0.6)), border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8)),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: Container(
                                    decoration: BoxDecoration(color: const Color(0xFF272743), borderRadius: BorderRadius.circular(8)),
                                    child: DropdownButtonFormField<_ReportStatusFilter>(
                                      value: _statusFilter,
                                      dropdownColor: const Color(0xFF272743),
                                      items: _ReportStatusFilter.values
                                          .map((s) => DropdownMenuItem(value: s, child: Text(_statusLabel(s), style: const TextStyle(color: Colors.white))))
                                          .toList(),
                                      onChanged: (v) => setState(() => _statusFilter = v ?? _ReportStatusFilter.all),
                                      decoration: InputDecoration(labelText: 'Statut', labelStyle: TextStyle(color: Colors.white.withOpacity(0.6)), border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Container(
                                    decoration: BoxDecoration(color: const Color(0xFF272743), borderRadius: BorderRadius.circular(8)),
                                    child: DropdownButtonFormField<DateTime?>(
                                      value: _selectedWeekStart,
                                      dropdownColor: const Color(0xFF272743),
                                      items: [
                                        const DropdownMenuItem<DateTime?>(value: null, child: Text('Toutes semaines', style: TextStyle(color: Colors.white))),
                                        ...weeks.map(
                                          (w) => DropdownMenuItem<DateTime?>(
                                            value: w,
                                            child: Text('Semaine ${_displayDate(w)}', style: const TextStyle(color: Colors.white)),
                                          ),
                                        ),
                                      ],
                                      onChanged: (v) => setState(() => _selectedWeekStart = v),
                                      decoration: InputDecoration(labelText: 'Semaine', labelStyle: TextStyle(color: Colors.white.withOpacity(0.6)), border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8)),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (filtered.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 40),
                          child: Center(
                            child: Column(
                              children: [
                                Icon(Icons.history_toggle_off, size: 64, color: _muted.withOpacity(0.5)),
                                const SizedBox(height: 16),
                                Text('Aucun rapport trouvé', style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 8),
                                Text('Essayez de modifier vos filtres de recherche.', style: GoogleFonts.inter(color: _muted)),
                              ],
                            ),
                          ),
                        )
                      else
                        ...filtered.map(_buildReportCard),
                    ],
                  ),
                ),
    );
  }

  Widget _buildReportCard(Map<String, dynamic> r) {
    final machine = (r['machineName'] ?? r['machineId'] ?? 'Machine').toString();
    final typeMission = (r['typeControle'] ?? '').toString().trim();
    final techNom = (r['technicienNom'] ?? r['technicianName'] ?? '').toString().trim();
    final date = _asDate(
      r['dateRealisation'] ??
          r['completedAt'] ??
          r['updatedAt'] ??
          r['dateControle'] ??
          r['createdAt'],
    );
    final hasAnomaly = _hasAnomaly(r);
    final statusText = hasAnomaly ? 'ANOMALIE' : 'VALIDE';
    final color = hasAnomaly ? _warn2 : _ok;

    final nested = r['rapportControle'];
    final items = (nested is Map && nested['items'] is List) ? (nested['items'] as List) : const [];
    var note = '';
    if (nested is Map) {
      note = (nested['generalNote'] ?? '').toString().trim();
    }
    if (note.isEmpty) note = (r['notes'] ?? '').toString().trim();

    return Card(
      color: _surface,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withOpacity(0.8), width: 1.2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(machine, style: GoogleFonts.spaceGrotesk(color: Colors.white, fontWeight: FontWeight.w700)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: color.withOpacity(0.9)),
                  ),
                  child: Text(statusText, style: GoogleFonts.inter(color: color, fontWeight: FontWeight.w700, fontSize: 11)),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              date != null ? 'Date: ${_displayDate(date)}' : 'Date: non définie',
              style: GoogleFonts.inter(color: Colors.white70),
            ),
            if (techNom.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Technicien : $techNom',
                style: GoogleFonts.inter(color: Colors.white70, fontSize: 12),
              ),
            ],
            if (typeMission.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Mission : $typeMission',
                style: GoogleFonts.inter(color: _muted, fontSize: 12),
              ),
            ],
            if (items.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Checklist:', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              ...items.take(4).map((i) {
                if (i is! Map) return const SizedBox.shrink();
                final element = (i['element'] ?? '-').toString();
                final decision = (i['decision'] ?? '-').toString();
                final anomaly = (i['anomalie'] ?? '').toString();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    '- $element: $decision${anomaly.isNotEmpty ? ' ($anomaly)' : ''}',
                    style: GoogleFonts.inter(color: Colors.white70, fontSize: 12),
                  ),
                );
              }),
              if (items.length > 4)
                Text('... ${items.length - 4} élément(s) supplémentaire(s)', style: GoogleFonts.inter(color: _muted, fontSize: 11)),
            ],
            if (note.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Notes: $note', style: GoogleFonts.inter(color: Colors.white70)),
            ],
          ],
        ),
      ),
    );
  }
}
