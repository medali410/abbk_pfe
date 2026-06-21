import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'machine_detail_ai_page.dart';
import 'machine_detail_page.dart';
import 'maintenance_ia_status.dart';
import 'mission_control_page.dart';
import 'send_mission_page.dart';
import 'services/api_service.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'dart:async';

/// Page principale maintenance : sidebar machines + détail inline avec capteurs temps réel.
class MaintenanceMachineHubPage extends StatefulWidget {
  const MaintenanceMachineHubPage({super.key});

  @override
  State<MaintenanceMachineHubPage> createState() =>
      _MaintenanceMachineHubPageState();
}

class _MaintenanceMachineHubPageState extends State<MaintenanceMachineHubPage> {
  late Future<Map<String, dynamic>> _future;
  Map<String, dynamic>? _currentData;
  late io.Socket _socket;
  Timer? _pollTimer;
  String? _selectedMachineId;

  @override
  void initState() {
    super.initState();
    _loadData();
    _initSocket();

    _pollTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        _pollTelemetryForAllMachines();
      }
    });
  }

  Future<void> _loadData({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _future = ApiService.getMaintenanceWorkspace();
      });
    }
    try {
      final data = await ApiService.getMaintenanceWorkspace();
      if (mounted) {
        setState(() {
          _currentData = data;
          _future = Future.value(data);
          // Auto-select first machine if none selected
          if (_selectedMachineId == null) {
            final machines = (data['machines'] as List? ?? const []);
            if (machines.isNotEmpty) {
              final first = machines.first as Map;
              _selectedMachineId = (first['machineId'] ?? first['id'] ?? first['_id'] ?? '').toString();
            }
          }
        });
        _setupSocketListeners();
        _pollTelemetryForAllMachines();
      }
    } catch (e) {
      // Ignore errors on silent poll
    }
  }

  Future<void> _pollTelemetryForAllMachines() async {
    if (_currentData == null || !mounted) return;
    final machines = List<Map<String, dynamic>>.from(_currentData!['machines'] ?? []);
    bool updated = false;
    for (int i = 0; i < machines.length; i++) {
      final m = machines[i];
      final mId = (m['machineId'] ?? m['id'] ?? m['_id'] ?? '').toString();
      if (mId.isNotEmpty) {
        try {
          final tel = await ApiService.getLatestTelemetry(mId);
          if (tel != null && mounted) {
            final newM = Map<String, dynamic>.from(m);
            if (newM['metrics'] == null || newM['metrics'] is! Map) {
              newM['metrics'] = <String, dynamic>{};
            }
            final metrics = Map<String, dynamic>.from(newM['metrics'] as Map);

            final rawMetrics = tel['metrics'];
            final telMetrics = rawMetrics is Map ? Map<String, dynamic>.from(rawMetrics) : null;

            metrics['thermal'] = tel['temperature'] ?? tel['temp'] ?? telMetrics?['thermal'] ?? telMetrics?['temp'] ?? metrics['thermal'];
            metrics['vibration'] = tel['vibration'] ?? telMetrics?['vibration'] ?? metrics['vibration'];
            metrics['pressure'] = tel['pressure'] ?? tel['pression'] ?? telMetrics?['pressure'] ?? telMetrics?['pression'] ?? metrics['pressure'];
            metrics['magnetic'] = tel['magnetic'] ?? tel['magnet'] ?? telMetrics?['magnetic'] ?? telMetrics?['magnet'] ?? metrics['magnetic'];
            metrics['power'] = tel['power'] ?? telMetrics?['power'] ?? metrics['power'];
            metrics['infrared'] = tel['infrared'] ?? telMetrics?['infrared'] ?? metrics['infrared'];

            newM['metrics'] = metrics;
            machines[i] = newM;
            updated = true;
          }
        } catch (_) {}
      }
    }
    if (updated && mounted) {
      setState(() {
        _currentData!['machines'] = machines;
        _future = Future.value(_currentData);
      });
    }
  }

  void _setupSocketListeners() {
    if (_currentData == null) return;
    final machines = _currentData!['machines'] as List? ?? [];
    for (final m in machines) {
      if (m is Map) {
        final mId = (m['machineId'] ?? m['id'] ?? m['_id'] ?? '').toString();
        final mName = (m['machineName'] ?? m['name'] ?? mId).toString();
        if (mId.isNotEmpty) {
          _socket.on('ai:$mId', (data) => _updateMachineData(mId, data));
        }
        if (mName.isNotEmpty && mName != mId) {
          _socket.on('ai:$mName', (data) => _updateMachineData(mId, data));
        }
      }
    }
  }

  void _updateMachineData(String machineId, Map data) {
    if (_currentData == null) return;
    setState(() {
      final machines = List<Map<String, dynamic>>.from(_currentData!['machines'] ?? []);
      for (int i = 0; i < machines.length; i++) {
        final m = machines[i];
        final id = (m['machineId'] ?? m['id'] ?? m['_id'] ?? '').toString();
        final name = (m['machineName'] ?? m['name'] ?? id).toString();
        if (id == machineId || name == machineId) {
          final newM = Map<String, dynamic>.from(m);

          if (newM['metrics'] == null || newM['metrics'] is! Map) {
            newM['metrics'] = <String, dynamic>{};
          }
          final metrics = Map<String, dynamic>.from(newM['metrics'] as Map);

          final sourceData = data.containsKey('metrics') && data['metrics'] is Map ? data['metrics'] as Map : data;

          double? _getDouble(String k1, [String? k2, String? k3]) {
            final val = sourceData[k1] ?? (k2 != null ? sourceData[k2] : null) ?? (k3 != null ? sourceData[k3] : null);
            if (val == null) return null;
            return double.tryParse(val.toString());
          }

          final th = _getDouble('thermal', 'temperature', 'temperature_contact') ?? _getDouble('temp');
          if (th != null) metrics['thermal'] = th;

          final pr = _getDouble('pressure', 'pression');
          if (pr != null) metrics['pressure'] = pr;

          final vi = _getDouble('vibration', 'vibration_x', 'vibration_y');
          if (vi != null) metrics['vibration'] = vi;

          final po = _getDouble('power', 'puissance', 'powerConsumption');
          if (po != null) metrics['power'] = po;

          final ma = _getDouble('magnetic');
          if (ma != null) metrics['magnetic'] = ma;

          final ir = _getDouble('infrared', 'temperature_infrarouge');
          if (ir != null) metrics['infrared'] = ir;

          newM['metrics'] = metrics;

          if (data.containsKey('level')) newM['level'] = data['level'];
          if (data.containsKey('status')) newM['status'] = data['status'];
          if (data.containsKey('probPanne')) newM['probPanne'] = data['probPanne'];
          if (data.containsKey('riskPercentage')) newM['probPanne'] = data['riskPercentage'];
          if (data.containsKey('typePanne')) newM['failureScenario'] = data['typePanne'];
          if (data.containsKey('failureScenario')) newM['failureScenario'] = data['failureScenario'];

          machines[i] = newM;
          break;
        }
      }
      _currentData!['machines'] = machines;
      _future = Future.value(_currentData);
    });
  }

  void _initSocket() {
    _socket = io.io(ApiService.socketBaseUrl, <String, dynamic>{
      'transports': <String>['polling', 'websocket'],
      'autoConnect': true,
    });

    _socket.onConnect((_) {
      if (mounted) setState(() {});
    });

    _socket.on('nouvelle_prediction', (raw) {
      try {
        final dynamic decoded = raw is String ? jsonDecode(raw) : raw;
        if (decoded is Map) {
          final machineId = (decoded['machineId'] ?? '').toString();
          _updateMachineData(machineId, decoded);
        }
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _socket.dispose();
    super.dispose();
  }

  void _reload() => _loadData();

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF10102B);
    const text = Color(0xFFE2DFFF);
    const accent = Color(0xFFFF6E00);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: Text(
          'Détail machine',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
        backgroundColor: bg,
        foregroundColor: text,
        actions: [
          IconButton(
            onPressed: _reload,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: accent),
            );
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
                      style: GoogleFonts.inter(color: const Color(0xFFE2BFB0)),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _reload,
                      child: const Text('Réessayer'),
                    ),
                  ],
                ),
              ),
            );
          }
          final data = snap.data ?? {};
          return _MaintenanceHubBody(
            data: data,
            selectedMachineId: _selectedMachineId,
            onSelectMachine: (id) {
              setState(() => _selectedMachineId = id);
            },
          );
        },
      ),
    );
  }
}

// ─────────────────────────── Helpers ───────────────────────────

bool _looksLikeNetworkImage(String value) {
  final v = value.trim().toLowerCase();
  return v.startsWith('http://') || v.startsWith('https://');
}

bool _looksLikeDataImage(String value) {
  final v = value.trim().toLowerCase();
  return v.startsWith('data:image/');
}

String _normalizeMachineImageValue(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '';
  if (_looksLikeNetworkImage(trimmed) || _looksLikeDataImage(trimmed)) {
    return trimmed;
  }
  final hasExtension = RegExp(r'\.[a-z0-9]{2,5}$', caseSensitive: false)
      .hasMatch(trimmed);
  return hasExtension ? trimmed : '$trimmed.png';
}

Widget _buildMachineImageBox(
  String rawImageValue, {
  required double size,
}) {
  const surface = Color(0xFF252540);
  final normalized = _normalizeMachineImageValue(rawImageValue);
  final fallback = Container(
    height: size,
    width: size,
    decoration: BoxDecoration(
      color: surface,
      borderRadius: BorderRadius.circular(12),
    ),
    alignment: Alignment.center,
    child: Icon(
      Icons.precision_manufacturing_rounded,
      color: Colors.white.withValues(alpha: 0.45),
      size: size * 0.38,
    ),
  );

  if (normalized.isEmpty) return fallback;

  if (_looksLikeDataImage(normalized)) {
    try {
      final bytes = base64Decode(normalized.split(',').last);
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.memory(
          bytes,
          height: size,
          width: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => fallback,
        ),
      );
    } catch (_) {
      return fallback;
    }
  }

  if (_looksLikeNetworkImage(normalized)) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(
        normalized,
        height: size,
        width: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }

  return fallback;
}

Map<String, double> _metricsAsDoubles(Map<String, dynamic>? raw) {
  if (raw == null || raw.isEmpty) return {};
  final out = <String, double>{};
  raw.forEach((k, v) {
    final n = num.tryParse(v.toString());
    if (n != null) out[k] = n.toDouble();
  });
  return out;
}

Map<String, double> _effectiveMachineMetrics(Map<String, dynamic> machine) {
  final rawMetrics = machine['metrics'];
  final metricsMap = rawMetrics is Map ? Map<String, dynamic>.from(rawMetrics) : null;
  final out = _metricsAsDoubles(metricsMap);
  void merge(String metricKey, Object? legacyVal) {
    if (out.containsKey(metricKey)) return;
    final n = num.tryParse(legacyVal?.toString() ?? '');
    if (n != null) out[metricKey] = n.toDouble();
  }

  merge('thermal', machine['temperature']);
  merge('vibration', machine['vibration']);
  merge('power', machine['powerConsumption']);
  merge('presence', machine['proximity']);
  return out;
}

String _iaMessageFromRow(Map<String, dynamic> m) {
  final fs = m['failureScenario'];
  if (fs is Map) {
    final exp = (fs['scenarioExplanation'] ?? '').toString().trim();
    if (exp.isNotEmpty) return exp;
    final lab = (fs['scenarioLabel'] ?? '').toString().trim();
    if (lab.isNotEmpty) return lab;
  }
  final rec = (m['recommendation'] ?? '').toString().trim();
  if (rec.isNotEmpty) return rec;
  return 'En attente de données IA…';
}

String _machineIdOf(Map<String, dynamic> m) =>
    (m['machineId'] ?? m['id'] ?? m['_id'] ?? '').toString();

// ─────────────────────── Main Body Layout ──────────────────────

class _MaintenanceHubBody extends StatelessWidget {
  const _MaintenanceHubBody({
    required this.data,
    required this.selectedMachineId,
    required this.onSelectMachine,
  });

  final Map<String, dynamic> data;
  final String? selectedMachineId;
  final ValueChanged<String> onSelectMachine;

  @override
  Widget build(BuildContext context) {
    const muted = Color(0xFFE2BFB0);

    final agent = (data['agent'] as Map?)?.cast<String, dynamic>() ?? {};
    final viewerName = (agent['fullName'] ?? '').toString();
    final rows = (data['machines'] as List? ?? const [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();

    if (rows.isEmpty) {
      return Center(
        child: Text(
          'Aucune machine assignée.',
          style: GoogleFonts.inter(color: muted),
        ),
      );
    }

    final selectedId = selectedMachineId ?? _machineIdOf(rows.first);
    final selectedMachine = rows.firstWhere(
      (m) => _machineIdOf(m) == selectedId,
      orElse: () => rows.first,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final vw = constraints.maxWidth;
        final isWide = vw >= 800;

        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Sidebar ──
              SizedBox(
                width: 280,
                child: _MachineSidebar(
                  machines: rows,
                  selectedId: selectedId,
                  onSelect: onSelectMachine,
                ),
              ),
              // ── Main content ──
              Expanded(
                child: _MachineDetailPanel(
                  machine: selectedMachine,
                  allMachines: rows,
                  viewerName: viewerName,
                ),
              ),
            ],
          );
        }

        // Mobile: vertical layout
        return Column(
          children: [
            // Compact horizontal machine list
            SizedBox(
              height: 60,
              child: _MobileTabBar(
                machines: rows,
                selectedId: selectedId,
                onSelect: onSelectMachine,
              ),
            ),
            Expanded(
              child: _MachineDetailPanel(
                machine: selectedMachine,
                allMachines: rows,
                viewerName: viewerName,
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────── Sidebar ───────────────────────────

class _MachineSidebar extends StatelessWidget {
  const _MachineSidebar({
    required this.machines,
    required this.selectedId,
    required this.onSelect,
  });

  final List<Map<String, dynamic>> machines;
  final String selectedId;
  final ValueChanged<String> onSelect;

  static const _bg = Color(0xFF131429);
  static const _text = Color(0xFFE2DFFF);
  static const _muted = Color(0xFFE2BFB0);
  static const _accent = Color(0xFFFF6E00);

  @override
  Widget build(BuildContext context) {
    final dangerMachines = machines.where((m) => iaLevelKey(m) == 'DANGER').toList();
    final risqueMachines = machines.where((m) => iaLevelKey(m) == 'RISQUE').toList();
    final normalMachines = machines.where((m) => iaLevelKey(m) == 'NORMAL').toList();

    return Container(
      decoration: BoxDecoration(
        color: _bg,
        border: Border(
          right: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Icon(Icons.precision_manufacturing_rounded, color: _accent, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'MACHINES',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      color: _text,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${machines.length}',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: _accent,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Cliquez sur une machine pour voir ses détails',
              style: GoogleFonts.inter(
                fontSize: 10,
                color: _muted.withValues(alpha: 0.6),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Stats bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _buildStatusBadge('Normal', normalMachines.length, const Color(0xFF66BB6A)),
                const SizedBox(width: 6),
                _buildStatusBadge('Risque', risqueMachines.length, const Color(0xFFFF9800)),
                const SizedBox(width: 6),
                _buildStatusBadge('Danger', dangerMachines.length, const Color(0xFFFF6B6B)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Divider(color: Colors.white.withValues(alpha: 0.06), height: 1),
          // Machine list
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                if (dangerMachines.isNotEmpty) ...[
                  _buildSectionHeader('DANGER', const Color(0xFFFF6B6B)),
                  for (final m in dangerMachines) _buildMachineItem(m),
                ],
                if (risqueMachines.isNotEmpty) ...[
                  _buildSectionHeader('RISQUE', const Color(0xFFFF9800)),
                  for (final m in risqueMachines) _buildMachineItem(m),
                ],
                if (normalMachines.isNotEmpty) ...[
                  _buildSectionHeader('NORMAL', const Color(0xFF66BB6A)),
                  for (final m in normalMachines) _buildMachineItem(m),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String label, int count, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          children: [
            Text(
              '$count',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 8,
                fontWeight: FontWeight.w600,
                color: color.withValues(alpha: 0.8),
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, Color color) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Row(
        children: [
          Container(width: 3, height: 14, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 8),
          Text(
            title,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.0,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMachineItem(Map<String, dynamic> machine) {
    final mId = _machineIdOf(machine);
    final name = (machine['machineName'] ?? mId).toString();
    final status = (machine['status'] ?? '').toString();
    final isSelected = mId == selectedId;
    final accent = iaLevelAccent(machine);
    final prob = iaProbPanne(machine);
    final levelFr = iaLevelFr(machine);
    final metrics = _effectiveMachineMetrics(machine);
    final thermal = metrics['thermal'] ?? metrics['temperature'] ?? metrics['temp'] ?? 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: isSelected
            ? _accent.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => onSelect(mId),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: isSelected
                  ? Border.all(color: _accent.withValues(alpha: 0.5))
                  : null,
            ),
            child: Row(
              children: [
                // Status dot
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent,
                    boxShadow: [
                      BoxShadow(color: accent.withValues(alpha: 0.4), blurRadius: 6),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                          color: isSelected ? Colors.white : _text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            levelFr,
                            style: GoogleFonts.inter(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: accent,
                            ),
                          ),
                          Text(
                            ' · ${prob.toStringAsFixed(0)}%',
                            style: GoogleFonts.inter(
                              fontSize: 9,
                              color: _muted.withValues(alpha: 0.8),
                            ),
                          ),
                          if (status.isNotEmpty) ...[
                            Text(
                              ' · $status',
                              style: GoogleFonts.inter(
                                fontSize: 9,
                                color: _muted.withValues(alpha: 0.6),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                // Temperature badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: (thermal >= 75 ? const Color(0xFFFFB4AB) : const Color(0xFF75D1FF)).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.thermostat_rounded,
                        size: 11,
                        color: thermal >= 75 ? const Color(0xFFFFB4AB) : const Color(0xFF75D1FF),
                      ),
                      const SizedBox(width: 2),
                      Text(
                        '${thermal.toStringAsFixed(1)}°',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: thermal >= 75 ? const Color(0xFFFFB4AB) : const Color(0xFF75D1FF),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ────────────────────── Mobile Tab Bar ──────────────────────

class _MobileTabBar extends StatelessWidget {
  const _MobileTabBar({
    required this.machines,
    required this.selectedId,
    required this.onSelect,
  });

  final List<Map<String, dynamic>> machines;
  final String selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFFF6E00);
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF131429),
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: machines.length,
        itemBuilder: (context, i) {
          final m = machines[i];
          final mId = _machineIdOf(m);
          final name = (m['machineName'] ?? mId).toString();
          final isSel = mId == selectedId;
          final color = iaLevelAccent(m);

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => onSelect(mId),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isSel ? accent.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSel ? accent : Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7, height: 7,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      name,
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 11,
                        fontWeight: isSel ? FontWeight.w800 : FontWeight.w600,
                        color: isSel ? Colors.white : const Color(0xFFE2DFFF),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────── Machine Detail Panel ───────────────────

class _MachineDetailPanel extends StatelessWidget {
  const _MachineDetailPanel({
    required this.machine,
    required this.allMachines,
    required this.viewerName,
  });

  final Map<String, dynamic> machine;
  final List<Map<String, dynamic>> allMachines;
  final String viewerName;

  static const _bg = Color(0xFF10102B);
  static const _text = Color(0xFFE2DFFF);
  static const _muted = Color(0xFFE2BFB0);
  static const _accent = Color(0xFFFF6E00);

  @override
  Widget build(BuildContext context) {
    final id = _machineIdOf(machine);
    final name = (machine['machineName'] ?? id).toString();
    final level = (machine['level'] ?? 'NORMAL').toString();
    final status = (machine['status'] ?? '').toString();
    final imageUrl = (machine['imageUrl'] ?? '').toString();
    final metrics = _effectiveMachineMetrics(machine);
    final iaMsg = _iaMessageFromRow(machine);
    final accent = iaLevelAccent(machine);
    final levelFr = iaLevelFr(machine);
    final prob = iaProbPanne(machine);

    return Container(
      color: _bg,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header Card ──
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(
                  colors: [Color(0xFF1B1A3A), Color(0xFF141230)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  _buildMachineImageBox(imageUrl, size: 80),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                name,
                                style: GoogleFonts.spaceGrotesk(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 12),
                            _StatusBadge(level: level, accent: accent, label: levelFr),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'ID: $id${status.isNotEmpty ? '  ·  Statut: $status' : ''}',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: _muted.withValues(alpha: 0.8),
                          ),
                        ),
                        const SizedBox(height: 12),
                        // IA probability bar
                        Row(
                          children: [
                            Icon(Icons.auto_awesome_outlined, size: 14, color: accent),
                            const SizedBox(width: 6),
                            Text(
                              'Probabilité panne:',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: _muted.withValues(alpha: 0.8),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: (prob / 100).clamp(0.0, 1.0),
                                  minHeight: 6,
                                  backgroundColor: Colors.white.withValues(alpha: 0.08),
                                  color: accent,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${prob.toStringAsFixed(0)}%',
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: accent,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Info Cards ──
            _InfoCardsRow(machine: machine),
            const SizedBox(height: 20),

            // ── Technician Sensor Grid ──
            _TechnicianStyleSensorGrid(machine: machine),
            const SizedBox(height: 20),

            // ── IA Analysis & Actions ──
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // IA Message
                Expanded(
                  flex: 3,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF161826),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.psychology_rounded, size: 18, color: _accent),
                            const SizedBox(width: 8),
                            Text(
                              'MESSAGE IA',
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                                color: _accent,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          iaMsg,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: _text.withValues(alpha: 0.92),
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // Actions
                Expanded(
                  flex: 2,
                  child: Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => MachineDetailAiPage(
                                  machineId: id,
                                  machineName: name,
                                  viewerRole: 'maintenance',
                                  viewerName: viewerName,
                                  machines: allMachines,
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.analytics_outlined, size: 18),
                          label: Text('Détails IA', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF10102B),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.tonalIcon(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => SendMissionPage(
                                  machineId: id,
                                  machineName: name,
                                  agentName: viewerName.isNotEmpty ? viewerName : 'Agent maintenance',
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.send_rounded, size: 18),
                          label: Text('Envoyer une mission', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13)),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFFF6E00).withOpacity(0.16),
                            foregroundColor: const Color(0xFFFF6E00),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: const Color(0xFFFF6E00).withOpacity(0.45)),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => MachineDetailAiPage(
                                  machineId: id,
                                  machineName: name,
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.info_outline_rounded, size: 18),
                          label: Text('Détails machine', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF252540),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ── IA Status Strip ──
            MaintenanceMachineIaStrip(machine: machine, compact: false),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────── Status Badge ──────────────────────────

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.level,
    required this.accent,
    required this.label,
  });
  final String level;
  final Color accent;
  final String label;

  @override
  Widget build(BuildContext context) {
    IconData icon;
    switch (level.toUpperCase()) {
      case 'DANGER':
        icon = Icons.error_rounded;
        break;
      case 'RISQUE':
        icon = Icons.warning_rounded;
        break;
      default:
        icon = Icons.check_circle_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: accent),
          const SizedBox(width: 5),
          Text(
            label,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────── Info Cards ──────────────────────────

class _InfoCardsRow extends StatelessWidget {
  const _InfoCardsRow({required this.machine});
  final Map<String, dynamic> machine;

  @override
  Widget build(BuildContext context) {
    final client = machine['client'] is Map ? machine['client'] as Map : {};
    final concepteur = machine['concepteur'] is Map ? machine['concepteur'] as Map : {};
    final maint = machine['maintenanceAgent'] is Map ? machine['maintenanceAgent'] as Map : {};

    Widget buildCard(String title, IconData icon, Map data, String roleDesc) {
      final name = (data['fullName'] ?? data['name'] ?? 'Inconnu').toString();
      final email = (data['email'] ?? '').toString();
      final phone = (data['phone'] ?? '').toString();
      return Expanded(
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF161826),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 14, color: const Color(0xFFB39DDB)),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: GoogleFonts.spaceGrotesk(color: const Color(0xFFB39DDB), fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(name, style: GoogleFonts.inter(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
              Text(roleDesc, style: GoogleFonts.inter(color: Colors.white70, fontSize: 11)),
              const SizedBox(height: 6),
              if (email.isNotEmpty)
                Text(email, style: GoogleFonts.inter(color: Colors.white54, fontSize: 10)),
              if (phone.isNotEmpty)
                Text(phone, style: GoogleFonts.inter(color: Colors.white54, fontSize: 10)),
            ],
          ),
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        buildCard('CLIENT', Icons.business, client, 'Client final'),
        const SizedBox(width: 12),
        buildCard('CONCEPTEUR', Icons.engineering, concepteur, 'Designer'),
        const SizedBox(width: 12),
        buildCard('MAINTENANCE', Icons.build_circle_outlined, maint, 'Agent maintenance'),
      ],
    );
  }
}

// ──────────────────── Technician Sensor Grid ────────────────────

class _TechnicianStyleSensorGrid extends StatelessWidget {
  const _TechnicianStyleSensorGrid({required this.machine});
  final Map<String, dynamic> machine;

  @override
  Widget build(BuildContext context) {
    final telemetry = machine['telemetry'] is Map ? machine['telemetry'] as Map : {};
    final metrics = machine['metrics'] is Map ? machine['metrics'] as Map : {};

    double? parseVal(dynamic v1, [dynamic v2, dynamic v3]) {
      final v = v1 ?? v2 ?? v3;
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString());
    }

    final tempVal = parseVal(metrics['thermal'], telemetry['temperature'], telemetry['temp']);
    
    late Color tempColor;
    late double tempRisk;
    late String tempState;
    if (tempVal == null) {
      tempColor = Colors.grey;
      tempRisk = 0;
      tempState = '--';
    } else if (tempVal < 55) {
      tempColor = const Color(0xFF4CAF50);
      tempRisk = (tempVal / 55.0 * 40.0).clamp(0, 40);
      tempState = 'NORMAL';
    } else if (tempVal <= 75) {
      tempColor = const Color(0xFFFF9800);
      tempRisk = 40 + ((tempVal - 55) / 20.0 * 30.0);
      tempState = 'RISQUE';
    } else {
      tempColor = const Color(0xFFF44336);
      tempRisk = (70 + ((tempVal - 75) / 25.0 * 30.0)).clamp(70, 100);
      tempState = 'DANGER';
    }

    final vibVal = parseVal(metrics['vibration'], telemetry['vibration']);
    late Color vibColor;
    late double vibRisk;
    late String vibState;
    if (vibVal == null) {
      vibColor = Colors.grey;
      vibRisk = 0;
      vibState = '--';
    } else if (vibVal < 7) {
      vibColor = const Color(0xFF4CAF50);
      vibRisk = (vibVal / 7.0 * 40.0).clamp(0, 40);
      vibState = 'NORMAL';
    } else if (vibVal <= 12) {
      vibColor = const Color(0xFFFF9800);
      vibRisk = 40 + ((vibVal - 7) / 5.0 * 30.0);
      vibState = 'RISQUE';
    } else {
      vibColor = const Color(0xFFF44336);
      vibRisk = (70 + ((vibVal - 12) / 8.0 * 30.0)).clamp(70, 100);
      vibState = 'DANGER';
    }

    final power = parseVal(metrics['power'], telemetry['power']);
    final rpmVal = parseVal(metrics['rpm'], telemetry['rpm'], power != null ? power * 10 : null);
    final pressVal = parseVal(metrics['pressure'], telemetry['pressure'], telemetry['pression']);

    final overallRisk = tempRisk > vibRisk ? tempRisk : vibRisk;
    final overallColor = overallRisk >= 70 ? const Color(0xFFF44336) : overallRisk >= 40 ? const Color(0xFFFF9800) : const Color(0xFF4CAF50);
    final overallState = overallRisk >= 70 ? 'DANGER' : overallRisk >= 40 ? 'RISQUE' : 'NORMAL';

    Widget buildSensorTile({
      required IconData icon,
      required String label,
      required String value,
      required String unit,
      required Color color,
      double? riskPercent,
      String? stateLabel,
    }) {
      return Container(
        width: 140,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(6)),
                  child: Icon(icon, size: 13, color: color),
                ),
                const SizedBox(width: 6),
                Expanded(child: Text(label, style: GoogleFonts.inter(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(value, style: GoogleFonts.spaceGrotesk(color: color, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(width: 3),
                Text(unit, style: GoogleFonts.inter(color: Colors.white70, fontSize: 9)),
              ],
            ),
            if (riskPercent != null) ...[
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: riskPercent / 100.0, backgroundColor: Colors.white.withValues(alpha: 0.06), valueColor: AlwaysStoppedAnimation<Color>(color), minHeight: 3),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (stateLabel != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                      child: Text(stateLabel, style: GoogleFonts.inter(color: color, fontSize: 8, fontWeight: FontWeight.bold)),
                    ),
                  Text('${riskPercent.toStringAsFixed(0)}%', style: GoogleFonts.spaceGrotesk(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [const Color(0xFF161826), overallColor.withValues(alpha: 0.06)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: overallColor.withValues(alpha: 0.25), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'DERNIÈRES VALEURS CAPTEURS',
                style: GoogleFonts.spaceGrotesk(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.0),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: overallColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: overallColor.withValues(alpha: 0.45)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 6, height: 6, decoration: BoxDecoration(color: overallColor, shape: BoxShape.circle)),
                    const SizedBox(width: 5),
                    Text(overallState, style: GoogleFonts.spaceGrotesk(color: overallColor, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              buildSensorTile(icon: Icons.thermostat_outlined, label: 'Température', value: tempVal != null ? tempVal.toStringAsFixed(1) : '--', unit: '°C', color: tempColor, riskPercent: tempRisk, stateLabel: tempState),
              buildSensorTile(icon: Icons.vibration, label: 'Vibration', value: vibVal != null ? vibVal.toStringAsFixed(1) : '--', unit: 'mm/s', color: vibColor, riskPercent: vibRisk, stateLabel: vibState),
              buildSensorTile(icon: Icons.speed, label: 'Vitesse', value: rpmVal != null ? rpmVal.toStringAsFixed(0) : '--', unit: 'tr/min', color: const Color(0xFFB39DDB)),
              buildSensorTile(icon: Icons.flash_on, label: 'Voltage', value: pressVal != null ? pressVal.toStringAsFixed(1) : '--', unit: 'V', color: const Color(0xFF4DD0E1)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Text('Risque global :', style: GoogleFonts.inter(color: Colors.white70, fontSize: 10)),
              const SizedBox(width: 8),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(value: overallRisk / 100.0, backgroundColor: Colors.white.withValues(alpha: 0.06), valueColor: AlwaysStoppedAnimation<Color>(overallColor), minHeight: 6),
                ),
              ),
              const SizedBox(width: 8),
              Text('${overallRisk.toStringAsFixed(0)}%', style: GoogleFonts.spaceGrotesk(color: overallColor, fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }
}

// ──────────── Backwards-compatible wrapper ────────────────

/// Used by [MaintenanceDashboardPage] when embedding the machine hub inline.
class MaintenanceMachineHubContent extends StatefulWidget {
  const MaintenanceMachineHubContent({super.key, required this.data});
  final Map<String, dynamic> data;

  @override
  State<MaintenanceMachineHubContent> createState() => _MaintenanceMachineHubContentState();
}

class _MaintenanceMachineHubContentState extends State<MaintenanceMachineHubContent> {
  String? _selectedMachineId;

  @override
  Widget build(BuildContext context) {
    final rows = (widget.data['machines'] as List? ?? const [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
    if (rows.isNotEmpty && _selectedMachineId == null) {
      _selectedMachineId = _machineIdOf(rows.first);
    }
    return _MaintenanceHubBody(
      data: widget.data,
      selectedMachineId: _selectedMachineId,
      onSelectMachine: (id) => setState(() => _selectedMachineId = id),
    );
  }
}
