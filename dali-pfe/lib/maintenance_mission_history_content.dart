import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'services/api_service.dart';

/// Groupe machine → missions terminées.
class _MachineMissionGroup {
  _MachineMissionGroup({
    required this.machineId,
    required this.machineLabel,
    required this.missions,
  });

  final String machineId;
  final String machineLabel;
  final List<_HistoryEntry> missions;
}

/// Entrée d’historique : mission terrain terminée par le technicien (Mission Control).
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

/// Liste des missions terminées (coordination `COMPLETED` + archives).
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

class _MaintenanceMissionHistoryContentState
    extends State<MaintenanceMissionHistoryContent> {
  late Future<List<_HistoryEntry>> _future;

  /// Machines dont l’historique est déplié (`machineId` du groupe).
  final Set<String> _expandedMachineKeys = {};

  static const _text = Color(0xFFE2DFFF);
  static const _muted = Color(0xFFE2BFB0);
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

  Future<List<_HistoryEntry>> _loadEntries(Map<String, dynamic> workspace) async {
    final machines =
        (workspace['machines'] as List? ?? []).map((e) => e as Map<String, dynamic>).toList();
    final machineNames = <String, String>{};
    final allowedIds = <String>{};
    for (final m in machines) {
      final id = (m['machineId'] ?? '').toString();
      if (id.isEmpty) continue;
      allowedIds.add(id);
      machineNames[id] = (m['machineName'] ?? id).toString();
    }

    final agent = workspace['agent'];
    final clientId =
        agent is Map<String, dynamic> ? (agent['clientId'] ?? '').toString().trim() : '';

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
    final out = <_HistoryEntry>[];

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
      final dedupe =
          '$interventionId|$nid|${completedAt?.millisecondsSinceEpoch ?? 0}';
      if (seen.contains(dedupe)) return;
      seen.add(dedupe);
      out.add(
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
        final completed =
            _parseDt(n['missionCompletedAt']) ??
            _parseDt(n['updatedAt']) ??
            _parseDt(n['createdAt']);
        final nid = (n['id'] ?? n['_id'] ?? '').toString();
        push(
          machineId: mid,
          interventionId: iid,
          content: content,
          completedAt: completed,
          technicianName: tech,
          noteKey: nid,
        );
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
        final completed =
            _parseDt(m['updatedAt']) ??
            _parseDt(m['missionCompletedAt']) ??
            _parseDt(arch['finishedAt']);
        final nid = (m['_id'] ?? m['id'] ?? '').toString();
        push(
          machineId: mid,
          interventionId: iid.isNotEmpty ? iid : 'archive',
          content: content,
          completedAt: completed,
          technicianName: tech,
          noteKey: nid.isNotEmpty ? nid : 'm_${content.hashCode}',
        );
      }

      for (final raw in arch['coordinationNotes'] as List? ?? []) {
        if (raw is! Map) continue;
        final n = Map<String, dynamic>.from(raw);
        if (!_isMissionNote(n) || !_missionCompleted(n)) continue;
        final content = (n['content'] ?? '').toString();
        final completed =
            _parseDt(n['missionCompletedAt']) ??
            _parseDt(n['updatedAt']) ??
            _parseDt(n['createdAt']) ??
            _parseDt(arch['finishedAt']);
        final nid = (n['id'] ?? n['_id'] ?? '').toString();
        push(
          machineId: mid,
          interventionId: iid.isNotEmpty ? iid : 'archive',
          content: content,
          completedAt: completed,
          technicianName: tech,
          noteKey: nid.isNotEmpty ? nid : 'cn_${content.hashCode}',
        );
      }
    }

    out.sort((a, b) {
      final ta = a.completedAt?.millisecondsSinceEpoch ?? 0;
      final tb = b.completedAt?.millisecondsSinceEpoch ?? 0;
      return tb.compareTo(ta);
    });

    return out;
  }

  /// Regroupe les entrées par machine ; ordre des groupes = mission la plus récente en premier.
  List<_MachineMissionGroup> _groupEntries(List<_HistoryEntry> rows) {
    final byMachine = <String, List<_HistoryEntry>>{};
    for (final e in rows) {
      final key = e.machineId.isNotEmpty ? e.machineId : e.machineLabel;
      byMachine.putIfAbsent(key, () => []).add(e);
    }
    for (final list in byMachine.values) {
      list.sort((a, b) {
        final ta = a.completedAt?.millisecondsSinceEpoch ?? 0;
        final tb = b.completedAt?.millisecondsSinceEpoch ?? 0;
        return tb.compareTo(ta);
      });
    }
    int newestMs(List<_HistoryEntry> list) {
      var m = 0;
      for (final e in list) {
        final t = e.completedAt?.millisecondsSinceEpoch ?? 0;
        if (t > m) m = t;
      }
      return m;
    }

    final groups =
        byMachine.entries.map((e) {
          final label =
              e.value.isNotEmpty ? e.value.first.machineLabel : e.key;
          return _MachineMissionGroup(
            machineId: e.key,
            machineLabel: label,
            missions: e.value,
          );
        }).toList()
          ..sort((a, b) => newestMs(b.missions).compareTo(newestMs(a.missions)));

    return groups;
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
                  'Missions terminées par le technicien (Mission Control).',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: _muted.withOpacity(0.85),
                  ),
                ),
              ),
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
          child: FutureBuilder<List<_HistoryEntry>>(
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
              final rows = snap.data ?? [];
              if (rows.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      'Aucune mission terminée pour le moment.\n'
                      'Les missions apparaissent ici lorsque le technicien appuie sur « Terminer » dans Mission Control.',
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
              final groups = _groupEntries(rows);
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                itemCount: groups.length,
                itemBuilder: (context, gi) {
                  final g = groups[gi];
                  final key = g.machineId;
                  final expanded = _expandedMachineKeys.contains(key);
                  return Padding(
                    padding: EdgeInsets.only(bottom: gi < groups.length - 1 ? 18 : 0),
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
                                        g.machineLabel.toUpperCase(),
                                        style: GoogleFonts.spaceGrotesk(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.9,
                                          color: _text,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      '${g.missions.length} mission${g.missions.length > 1 ? 's' : ''}',
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
                                    color: const Color(0xFF131429),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.white.withOpacity(0.07),
                                    ),
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: Column(
                                    children: [
                                      for (var mi = 0; mi < g.missions.length; mi++) ...[
                                        if (mi > 0)
                                          Divider(
                                            height: 1,
                                            thickness: 1,
                                            color: Colors.white.withOpacity(0.06),
                                          ),
                                        _MissionHistoryRow(
                                          entry: g.missions[mi],
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

/// Une ligne de mission dans un groupe machine (sans répéter le nom de la machine).
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
                  color: muted.withOpacity(0.75),
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
