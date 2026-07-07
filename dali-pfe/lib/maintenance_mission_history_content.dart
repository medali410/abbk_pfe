import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'services/api_service.dart';
import 'services/theme_service.dart';

class _HistoryEntry {
  _HistoryEntry({
    required this.machineId,
    required this.machineLabel,
    required this.interventionId,
    required this.content,
    required this.completedAt,
    this.technicianName = '',
    this.noteKey = '',
  });

  final String machineId;
  final String machineLabel;
  final String interventionId;
  final String content;
  final DateTime? completedAt;
  final String technicianName;
  final String noteKey;
}

class _MachineData {
  _MachineData({
    required this.machineId,
    required this.machineLabel,
    required this.missions,
    required this.telemetryHistory,
  });

  final String machineId;
  final String machineLabel;
  final List<_HistoryEntry> missions;
  final List<Map<String, dynamic>> telemetryHistory;
}

class MaintenanceMissionHistoryContent extends StatefulWidget {
  const MaintenanceMissionHistoryContent({
    super.key,
    required this.data,
    required this.onWorkspaceReload,
  });

  final Map<String, dynamic> data;
  final VoidCallback onWorkspaceReload;

  @override
  State<MaintenanceMissionHistoryContent> createState() =>
      _MaintenanceMissionHistoryContentState();
}

class _MaintenanceMissionHistoryContentState extends State<MaintenanceMissionHistoryContent> {
  late Future<List<_MachineData>> _future;
  final Set<String> _expandedMachineKeys = {};

  bool get _isDarkMode => ThemeService().isDarkMode;
  Color get _text => _isDarkMode ? const Color(0xFFE2DFFF) : const Color(0xFF1E1E2D);
  Color get _muted => _isDarkMode ? const Color(0xFFE2BFB0) : const Color(0xFF64748B);
  static const _accent = Color(0xFFFF6E00);

  @override
  void initState() {
    super.initState();
    _future = _loadEntries(widget.data);
  }

  DateTime? _parseDt(dynamic raw) {
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString());
  }

  bool _missionCompleted(Map<String, dynamic> m) {
    final s = (m['missionStatus'] ?? '').toString().toUpperCase().trim();
    return s == 'COMPLETED';
  }

  bool _isMissionNote(Map<String, dynamic> m) {
    if (m['isMission'] == true) return true;
    final ms = (m['missionStatus'] ?? '').toString().trim();
    return ms.isNotEmpty;
  }

  Future<List<_MachineData>> _loadEntries(Map<String, dynamic> workspace) async {
    final machines = (workspace['machines'] as List? ?? []).map((e) => e as Map<String, dynamic>).toList();
    final machineNames = <String, String>{};
    final allowedIds = <String>{};
    
    for (final m in machines) {
      final id = (m['machineId'] ?? m['id'] ?? m['_id'] ?? '').toString();
      if (id.isEmpty) continue;
      allowedIds.add(id);
      machineNames[id] = (m['machineName'] ?? m['name'] ?? id).toString();
    }

    final agent = workspace['agent'];
    final clientId = agent is Map<String, dynamic> ? (agent['clientId'] ?? '').toString().trim() : '';

    final interventions = await ApiService.getDiagnosticInterventions();
    List<Map<String, dynamic>> archives = [];
    try {
      if (clientId.isNotEmpty) {
        archives = await ApiService.getInterventionArchives(companyId: clientId);
      }
    } catch (_) {
      archives = [];
    }

    bool machineOk(String mid) {
      if (allowedIds.isEmpty) return true;
      return allowedIds.contains(mid);
    }

    final seen = <String>{};
    final allMissions = <_HistoryEntry>[];

    void push({
      required String machineId,
      required String interventionId,
      required String content,
      DateTime? completedAt,
      String technicianName = '',
      String noteKey = '',
    }) {
      if (!machineOk(machineId)) return;
      final nid = noteKey.isNotEmpty ? noteKey : content.hashCode.toString();
      final dedupe = '$interventionId|$nid|${completedAt?.millisecondsSinceEpoch ?? 0}';
      if (seen.contains(dedupe)) return;
      seen.add(dedupe);
      allMissions.add(
        _HistoryEntry(
          machineId: machineId,
          machineLabel: machineNames[machineId] ?? machineId,
          interventionId: interventionId,
          content: content.trim().isEmpty ? '—' : content.trim(),
          completedAt: completedAt,
          technicianName: technicianName,
          noteKey: nid,
        ),
      );
    }

    for (final inv in interventions) {
      final mid = (inv['machineId'] ?? '').toString();
      final iid = (inv['id'] ?? '').toString();
      final tech = (inv['technicianName'] ?? '').toString();

      void scanNote(Map<String, dynamic> n) {
        if (!_isMissionNote(n) || !_missionCompleted(n)) return;
        final content = (n['content'] ?? '').toString();
        final completed = _parseDt(n['missionCompletedAt']) ?? _parseDt(n['updatedAt']) ?? _parseDt(n['createdAt']);
        final nid = (n['id'] ?? n['_id'] ?? '').toString();
        push(machineId: mid, interventionId: iid, content: content, completedAt: completed, technicianName: tech, noteKey: nid);
      }

      for (final raw in inv['coordinationNotes'] as List? ?? []) {
        if (raw is Map<String, dynamic>) scanNote(raw);
      }
      for (final raw in inv['messages'] as List? ?? []) {
        if (raw is Map<String, dynamic>) scanNote(raw);
      }
    }

    for (final arch in archives) {
      final mid = (arch['machineId'] ?? '').toString();
      if (!machineOk(mid)) continue;
      final iid = (arch['interventionId'] ?? '').toString();
      final tech = (arch['technicianName'] ?? '').toString();

      for (final raw in arch['missions'] as List? ?? []) {
        if (raw is! Map) continue;
        final m = Map<String, dynamic>.from(raw);
        if (!_missionCompleted(m)) continue;
        final content = (m['content'] ?? '').toString();
        final completed = _parseDt(m['updatedAt']) ?? _parseDt(m['missionCompletedAt']) ?? _parseDt(arch['finishedAt']);
        final nid = (m['_id'] ?? m['id'] ?? '').toString();
        push(machineId: mid, interventionId: iid.isNotEmpty ? iid : 'archive', content: content, completedAt: completed, technicianName: tech, noteKey: nid.isNotEmpty ? nid : 'm_${content.hashCode}');
      }

      for (final raw in arch['coordinationNotes'] as List? ?? []) {
        if (raw is! Map) continue;
        final n = Map<String, dynamic>.from(raw);
        if (!_isMissionNote(n) || !_missionCompleted(n)) continue;
        final content = (n['content'] ?? '').toString();
        final completed = _parseDt(n['missionCompletedAt']) ?? _parseDt(n['updatedAt']) ?? _parseDt(n['createdAt']) ?? _parseDt(arch['finishedAt']);
        final nid = (n['id'] ?? n['_id'] ?? '').toString();
        push(machineId: mid, interventionId: iid.isNotEmpty ? iid : 'archive', content: content, completedAt: completed, technicianName: tech, noteKey: nid.isNotEmpty ? nid : 'cn_${content.hashCode}');
      }
    }

    final result = <_MachineData>[];
    for (final id in allowedIds) {
      List<Map<String, dynamic>> telemetry = [];
      try {
        telemetry = await ApiService.getTelemetryHistory(id, limit: 10);
      } catch (_) {
      }
      
      final machineMissions = allMissions.where((e) => e.machineId == id).toList();
      machineMissions.sort((a, b) {
        final ta = a.completedAt?.millisecondsSinceEpoch ?? 0;
        final tb = b.completedAt?.millisecondsSinceEpoch ?? 0;
        return tb.compareTo(ta);
      });

      result.add(_MachineData(
        machineId: id,
        machineLabel: machineNames[id] ?? id,
        missions: machineMissions,
        telemetryHistory: telemetry,
      ));
    }
    
    return result;
  }

  String _fmtDate(DateTime? d) {
    if (d == null) return '—';
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final yyyy = d.year.toString();
    final hh = d.hour.toString().padLeft(2, '0');
    final min = d.minute.toString().padLeft(2, '0');
    return '$dd/$mm/$yyyy $hh:$min';
  }

  Future<void> _exportPdf() async {
    final data = await _future;
    final pdf = pw.Document();

    for (final machine in data) {
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) => [
            pw.Header(
              level: 0,
              child: pw.Text('Historique : ${machine.machineLabel}', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
            ),
            pw.SizedBox(height: 10),
            pw.Text('10 Dernieres Valeurs Capteurs', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 5),
            if (machine.telemetryHistory.isEmpty)
              pw.Text('Aucune valeur capteur.')
            else
              pw.TableHelper.fromTextArray(
                context: context,
                headers: ['Date', 'Temp', 'Vib', 'Pres'],
                data: machine.telemetryHistory.map((t) {
                   final dt = _parseDt(t['timestamp']);
                   final m = t['metrics'] is Map ? t['metrics'] as Map : t;
                   double? getD(String k1, [String? k2, String? k3]) {
                     final v = m[k1] ?? (k2 != null ? m[k2] : null) ?? (k3 != null ? m[k3] : null);
                     if (v is num) return v.toDouble();
                     if (v != null) return double.tryParse(v.toString());
                     return null;
                   }
                   final temp = getD('thermal', 'temperature', 'temp');
                   final vib = getD('vibration', 'vibration_x', 'vibration_y');
                   final pres = getD('pressure', 'pression');
                   return [
                     _fmtDate(dt),
                     temp != null ? temp.toStringAsFixed(1) : 'N/A',
                     vib != null ? vib.toStringAsFixed(2) : 'N/A',
                     pres != null ? pres.toStringAsFixed(3) : 'N/A',
                   ];
                }).toList(),
              ),
            pw.SizedBox(height: 20),
            pw.Text('Historique des Missions', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 5),
            if (machine.missions.isEmpty)
              pw.Text('Aucune mission.')
            else
              pw.ListView.builder(
                itemCount: machine.missions.length,
                itemBuilder: (context, i) {
                  final m = machine.missions[i];
                  return pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 8),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('- ${m.content}'),
                        pw.Text('  Date: ${_fmtDate(m.completedAt)} | Tech: ${m.technicianName} | ID: ${m.interventionId}', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                      ]
                    )
                  );
                }
              ),
          ],
        )
      );
    }

    await Printing.sharePdf(bytes: await pdf.save(), filename: 'historique_maintenance.pdf');
  }

  Future<void> _refresh() async {
    widget.onWorkspaceReload();
    setState(() {
      _future = _loadEntries(widget.data);
    });
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Historique des machines, capteurs et missions',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: _muted.withOpacity(0.85),
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _exportPdf,
                icon: const Icon(Icons.picture_as_pdf_rounded, size: 18, color: Color(0xFF75D1FF)),
                label: Text(
                  'Exporter PDF',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF75D1FF),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh_rounded, size: 18, color: _accent),
                label: Text(
                  'Actualiser',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _accent,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<_MachineData>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: _accent));
              }
              if (snap.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${snap.error}',
                          style: GoogleFonts.inter(color: _muted),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: _refresh,
                          child: const Text('Réessayer'),
                        ),
                      ],
                    ),
                  ),
                );
              }
              final machinesData = snap.data ?? [];
              if (machinesData.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      'Aucune machine assignée au tableau de bord.',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: _muted,
                        height: 1.45,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                itemCount: machinesData.length,
                itemBuilder: (context, gi) {
                  final mData = machinesData[gi];
                  final key = mData.machineId;
                  final expanded = _expandedMachineKeys.contains(key);
                  return Padding(
                    padding: EdgeInsets.only(bottom: gi < machinesData.length - 1 ? 18 : 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: EdgeInsets.only(bottom: expanded ? 10 : 4, top: gi == 0 ? 0 : 2),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () {
                                setState(() {
                                  if (expanded) {
                                    _expandedMachineKeys.remove(key);
                                  } else {
                                    _expandedMachineKeys.add(key);
                                  }
                                });
                              },
                              borderRadius: BorderRadius.circular(10),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 10,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.precision_manufacturing_outlined,
                                      size: 20,
                                      color: _accent.withOpacity(0.9),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        mData.machineLabel.toUpperCase(),
                                        style: GoogleFonts.spaceGrotesk(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.9,
                                          color: _text,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      '${mData.missions.length} mission(s) passée(s)',
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        color: _muted.withOpacity(0.75),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Icon(
                                      expanded
                                          ? Icons.expand_less_rounded
                                          : Icons.expand_more_rounded,
                                      size: 22,
                                      color: _accent.withOpacity(0.85),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        AnimatedSize(
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.fastOutSlowIn,
                          alignment: Alignment.topCenter,
                          child: expanded
                              ? Container(
                                  decoration: BoxDecoration(
                                    color: _isDarkMode ? const Color(0xFF131429) : Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: _isDarkMode
                                          ? Colors.white.withOpacity(0.07)
                                          : Colors.black.withOpacity(0.06),
                                    ),
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      // 10 Last Sensor Values
                                      if (mData.telemetryHistory.isNotEmpty) ...[
                                        Container(
                                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                                          color: _isDarkMode ? Colors.white.withOpacity(0.02) : Colors.black.withOpacity(0.02),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                '10 DERNIÈRES VALEURS CAPTEURS',
                                                style: GoogleFonts.spaceGrotesk(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: _accent,
                                                  letterSpacing: 0.8,
                                                ),
                                              ),
                                              TextButton.icon(
                                                onPressed: () async {
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    const SnackBar(content: Text("Envoi des données à l'IA pour analyse..."), duration: Duration(seconds: 2)),
                                                  );
                                                  try {
                                                    await ApiService.sendHistoryToAi(mData.machineId);
                                                    if (!context.mounted) return;
                                                    ScaffoldMessenger.of(context).showSnackBar(
                                                      const SnackBar(content: Text("Données analysées avec succès ! Le modèle a été mis à jour."), backgroundColor: Color(0xFF81C784)),
                                                    );
                                                  } catch (e) {
                                                    if (!context.mounted) return;
                                                    ScaffoldMessenger.of(context).showSnackBar(
                                                      SnackBar(content: Text("Erreur: $e"), backgroundColor: Colors.redAccent),
                                                    );
                                                  }
                                                },
                                                icon: const Icon(Icons.psychology_outlined, size: 16, color: Color(0xFFB388FF)),
                                                label: Text(
                                                  'Analyser (IA)',
                                                  style: GoogleFonts.inter(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w600,
                                                    color: const Color(0xFFB388FF),
                                                  ),
                                                ),
                                                style: TextButton.styleFrom(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                  minimumSize: Size.zero,
                                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        SingleChildScrollView(
                                          scrollDirection: Axis.horizontal,
                                          child: DataTable(
                                            headingTextStyle: GoogleFonts.inter(
                                              fontSize: 11,
                                              color: _muted,
                                              fontWeight: FontWeight.w600,
                                            ),
                                            dataTextStyle: GoogleFonts.inter(
                                              fontSize: 12,
                                              color: _isDarkMode ? Colors.white70 : const Color(0xFF1E1E2D),
                                            ),
                                            columnSpacing: 24,
                                            columns: const [
                                              DataColumn(label: Text('Date & Heure')),
                                              DataColumn(label: Text('Température (°C)')),
                                              DataColumn(label: Text('Vibration (mm/s)')),
                                              DataColumn(label: Text('Pression (Bar)')),
                                              DataColumn(label: Text('Tension (V)')),
                                            ],
                                            rows: mData.telemetryHistory.map((t) {
                                              final dt = _parseDt(t['timestamp']);
                                              final m = t['metrics'] is Map ? t['metrics'] as Map : t;
                                              
                                              double? getD(String k1, [String? k2, String? k3]) {
                                                final v = m[k1] ?? (k2 != null ? m[k2] : null) ?? (k3 != null ? m[k3] : null);
                                                if (v is num) return v.toDouble();
                                                if (v != null) return double.tryParse(v.toString());
                                                return null;
                                              }
                                              
                                              final temp = getD('thermal', 'temperature', 'temp');
                                              final vib = getD('vibration', 'vibration_x', 'vibration_y');
                                              final pres = getD('pressure', 'pression');
                                              final volt = getD('voltage', 'tension');
                                              
                                              return DataRow(cells: [
                                                DataCell(Text(_fmtDate(dt))),
                                                DataCell(Text(temp != null ? temp.toStringAsFixed(1) : 'N/A')),
                                                DataCell(Text(vib != null ? vib.toStringAsFixed(2) : 'N/A')),
                                                DataCell(Text(pres != null ? pres.toStringAsFixed(3) : 'N/A')),
                                                DataCell(Text(volt != null ? volt.toStringAsFixed(1) : 'N/A')),
                                              ]);
                                            }).toList(),
                                          ),
                                        ),
                                        Divider(
                                          height: 1,
                                          thickness: 1,
                                          color: _isDarkMode ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.06),
                                        ),
                                      ],
                                      
                                      // Past Missions
                                      Container(
                                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                                        color: _isDarkMode ? Colors.white.withOpacity(0.02) : Colors.black.withOpacity(0.02),
                                        child: Text(
                                          'HISTORIQUE DES MISSIONS (${mData.missions.length})',
                                          style: GoogleFonts.spaceGrotesk(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: _accent,
                                            letterSpacing: 0.8,
                                          ),
                                        ),
                                      ),
                                      if (mData.missions.isEmpty)
                                        Padding(
                                          padding: const EdgeInsets.all(16),
                                          child: Text(
                                            'Aucune mission terminée pour cette machine.',
                                            style: GoogleFonts.inter(
                                              fontSize: 12,
                                              color: _muted.withOpacity(0.6),
                                              fontStyle: FontStyle.italic,
                                            ),
                                          ),
                                        )
                                      else
                                        for (var mi = 0; mi < mData.missions.length; mi++) ...[
                                          if (mi > 0)
                                            Divider(
                                              height: 1,
                                              thickness: 1,
                                              color: _isDarkMode ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.06),
                                            ),
                                          _MissionHistoryRow(
                                            entry: mData.missions[mi],
                                            fmtDate: _fmtDate,
                                            accent: _accent,
                                            text: _text,
                                            muted: _muted,
                                          ),
                                        ],
                                    ],
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _MissionHistoryRow extends StatelessWidget {
  const _MissionHistoryRow({
    required this.entry,
    required this.fmtDate,
    required this.accent,
    required this.text,
    required this.muted,
  });

  final _HistoryEntry entry;
  final String Function(DateTime?) fmtDate;
  final Color accent;
  final Color text;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.check_circle_outline_rounded,
                size: 18,
                color: accent.withOpacity(0.95),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  entry.content,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: text.withOpacity(0.92),
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                fmtDate(entry.completedAt),
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: muted.withOpacity(0.9),
                ),
              ),
            ],
          ),
          if (entry.technicianName.isNotEmpty) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 26),
              child: Text(
                'Technicien : ${entry.technicianName}',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: const Color(0xFF75D1FF),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 26),
            child: Text(
              'Intervention ${entry.interventionId}',
              style: GoogleFonts.inter(
                fontSize: 10,
                color: muted.withOpacity(0.55),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
