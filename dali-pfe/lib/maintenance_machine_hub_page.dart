import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'machine_detail_ai_page.dart';
import 'maintenance_ia_status.dart';
import 'maintenance_ml_model_sidebar.dart';
import 'mission_control_page.dart';
import 'services/api_service.dart';

/// Liste des machines du périmètre maintenance → ouverture du détail IA.
class MaintenanceMachineHubPage extends StatefulWidget {
  const MaintenanceMachineHubPage({super.key});

  @override
  State<MaintenanceMachineHubPage> createState() =>
      _MaintenanceMachineHubPageState();
}

class _MaintenanceMachineHubPageState extends State<MaintenanceMachineHubPage> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = ApiService.getMaintenanceWorkspace();
  }

  void _reload() => setState(() {
        _future = ApiService.getMaintenanceWorkspace();
      });

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
          return MaintenanceMachineHubContent(data: data);
        },
      ),
    );
  }
}

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


/// Liste machines pour intégration dans [MaintenanceDashboardPage].
/// Grille 2×n sur écran large (quadrants), une colonne sur mobile.
class MaintenanceMachineHubContent extends StatelessWidget {
  const MaintenanceMachineHubContent({super.key, required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    const muted = Color(0xFFE2BFB0);

    final agent = (data['agent'] as Map?)?.cast<String, dynamic>() ?? {};
    final viewerName = (agent['fullName'] ?? '').toString();
    final maintenanceAgentId =
        (agent['maintenanceAgentId'] ?? agent['id'] ?? '').toString().trim();
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final vw = constraints.maxWidth;
        final rows = (data['machines'] as List? ?? const [])
            .map((e) => (e as Map).cast<String, dynamic>())
            .toList();

        final criticalRows = rows
            .where((m) =>
                (m['level'] ?? '').toString().toUpperCase() != 'NORMAL')
            .toList();
        final normalRows = rows
            .where((m) =>
                (m['level'] ?? '').toString().toUpperCase() == 'NORMAL')
            .toList();

        final featuredMachine =
            criticalRows.isNotEmpty ? criticalRows.first : rows.first;

        final netflixView = SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildFeaturedBanner(
                context,
                featuredMachine,
                viewerName,
                maintenanceAgentId,
              ),
              if (criticalRows.isNotEmpty)
                _NetflixMachineRow(
                  title: 'Diagnostics Critiques & Attention',
                  machines: criticalRows,
                  viewerName: viewerName,
                  maintenanceAgentId: maintenanceAgentId,
                ),
              _NetflixMachineRow(
                title: 'Toutes les Machines du Périmètre',
                machines: rows,
                viewerName: viewerName,
                maintenanceAgentId: maintenanceAgentId,
              ),
              if (normalRows.isNotEmpty && criticalRows.isNotEmpty)
                _NetflixMachineRow(
                  title: 'Fonctionnement Normal',
                  machines: normalRows,
                  viewerName: viewerName,
                  maintenanceAgentId: maintenanceAgentId,
                ),
            ],
          ),
        );

        final sidebarDivider = Colors.white.withValues(alpha: 0.08);
        final wideRail = vw >= 920;
        final maxH = constraints.maxHeight;

        if (wideRail) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 292,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFF131429),
                    border: Border(
                      right: BorderSide(color: sidebarDivider),
                    ),
                  ),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: maxH.isFinite && maxH > 120 ? maxH : 0,
                        ),
                        child: MaintenanceMlModelSidebar(machines: rows),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(child: netflixView),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: sidebarDivider),
                ),
              ),
              child: MaintenanceMlModelSidebar(
                compact: true,
                machines: rows,
              ),
            ),
            Expanded(child: netflixView),
          ],
        );
      },
    );
  }
}

/// Banner for the featured machine at the top (Netflix style).
Widget _buildFeaturedBanner(
  BuildContext context,
  Map<String, dynamic> machine,
  String viewerName,
  String maintenanceAgentId,
) {
  final id = (machine['machineId'] ?? '').toString();
  final name = (machine['machineName'] ?? id).toString();
  final level = (machine['level'] ?? 'NORMAL').toString();
  final imageUrl = (machine['imageUrl'] ?? '').toString();
  final iaMsg = _iaMessageFromRow(machine);

  final isCritical = level.toUpperCase() != 'NORMAL';
  final levelColor =
      isCritical ? const Color(0xFFFFB4AB) : const Color(0xFF75D1FF);

  return Container(
    margin: const EdgeInsets.all(16),
    height: 220,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(16),
      gradient: const LinearGradient(
        colors: [Color(0xFF1F1D40), Color(0xFF13112E)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.3),
          blurRadius: 15,
          offset: const Offset(0, 8),
        ),
      ],
    ),
    clipBehavior: Clip.antiAlias,
    child: Stack(
      children: [
        Positioned(
          right: -50,
          top: -50,
          child: Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFFF6E00).withValues(alpha: 0.15),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: levelColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: levelColor.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Text(
                        'MACHINE VEDETTE · $level',
                        style: GoogleFonts.spaceGrotesk(
                          color: levelColor,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      name,
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      iaMsg,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: const Color(0xFFE2DFFF).withValues(alpha: 0.8),
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => MachineDetailAiPage(
                                  machineId: id,
                                  machineName: name,
                                  viewerRole: 'maintenance',
                                  viewerName: viewerName,
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.info_outline, size: 16),
                          label: const Text('Détails IA'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF10102B),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            textStyle: GoogleFonts.inter(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => MissionControlPage(
                                  initialArgs: <String, dynamic>{
                                    'machineId': id,
                                    'techId': id,
                                    'name': viewerName.isNotEmpty
                                        ? viewerName
                                        : 'Agent maintenance',
                                    'machineName': name,
                                    'viewerRole': 'maintenance',
                                    if (maintenanceAgentId.isNotEmpty)
                                      'technicianId': maintenanceAgentId,
                                  },
                                ),
                              ),
                            );
                          },
                          icon: const Icon(
                            Icons.assignment_turned_in_outlined,
                            size: 16,
                          ),
                          label: const Text('Mission'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white30),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            textStyle: GoogleFonts.inter(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Hero(
                    tag: 'featured_img_$id',
                    child: _buildMachineImageBox(imageUrl, size: 140),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Horizontal Netflix-style machine row with navigation buttons.
class _NetflixMachineRow extends StatefulWidget {
  const _NetflixMachineRow({
    required this.title,
    required this.machines,
    required this.viewerName,
    required this.maintenanceAgentId,
  });

  final String title;
  final List<Map<String, dynamic>> machines;
  final String viewerName;
  final String maintenanceAgentId;

  @override
  State<_NetflixMachineRow> createState() => _NetflixMachineRowState();
}

class _NetflixMachineRowState extends State<_NetflixMachineRow> {
  final ScrollController _scrollController = ScrollController();

  void _scroll(double offset) {
    _scrollController.animateTo(
      (_scrollController.offset + offset).clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      ),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.machines.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            widget.title,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: 0.5,
            ),
          ),
        ),
        SizedBox(
          height: 500,
          child: Stack(
            children: [
              ListView.builder(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: widget.machines.length,
                itemBuilder: (context, idx) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: SizedBox(
                      width: 320,
                      child: _MaintenanceMachineCard(
                        machine: widget.machines[idx],
                        viewerName: widget.viewerName,
                        maintenanceAgentId: widget.maintenanceAgentId,
                        compact: true,
                      ),
                    ),
                  );
                },
              ),
              Positioned(
                left: 8,
                top: 0,
                bottom: 0,
                child: Center(
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withValues(alpha: 0.6),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                    child: IconButton(
                      icon: const Icon(
                        Icons.chevron_left_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                      onPressed: () => _scroll(-600),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 8,
                top: 0,
                bottom: 0,
                child: Center(
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withValues(alpha: 0.6),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                    child: IconButton(
                      icon: const Icon(
                        Icons.chevron_right_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                      onPressed: () => _scroll(600),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}


/// Même grille 3×2 que la vue détail machine IA (thermique, pression, puissance…).
class _MaintenanceSensorSnapshotGrid extends StatelessWidget {
  const _MaintenanceSensorSnapshotGrid({
    required this.metrics,
    required this.compact,
  });

  final Map<String, double> metrics;
  final bool compact;

  static const _panel = Color(0xFF12131F);
  static const _cyan = Color(0xFF75D1FF);
  static const _text = Color(0xFFE2DFFF);
  static const _muted = Color(0xFFE2BFB0);
  static const _red = Color(0xFFFFB4AB);

  double _pick(List<String> keys, [double fallback = 0]) {
    for (final k in keys) {
      final v = metrics[k];
      if (v != null) return v;
    }
    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    final thermal = _pick(['thermal', 'temperature']);
    final pressure = _pick(['pressure']);
    final power = _pick(['power']);
    final vibration = _pick(['vibration']);
    final magnetic = _pick(['magnetic']);
    final infrared = metrics['infrared'];

    final pressureStr = pressure > 0 && pressure < 2
        ? '${pressure.toStringAsFixed(3)} BAR'
        : '${pressure.toStringAsFixed(1)} BAR';

    final irLabel =
        infrared == null || infrared <= 0 ? 'N/A' : '${infrared.toStringAsFixed(1)} °C';

    final thermalAccent = thermal >= 75 ? _red : _cyan;
    final vibAccent = vibration >= 4 ? _red : _cyan;
    const gold = Color(0xFFFFD54F);

    // Ratio largeur/hauteur élevé = tuiles moins hautes (moins d’espace vide).
    final gap = compact ? 4.0 : 8.0;
    final aspect = compact ? 2.05 : 1.68;
    final ih = compact ? 26.0 : 30.0;
    final fsLabel = compact ? 7.5 : 8.5;
    final fsVal = compact ? 11.0 : 13.0;
    final padH = compact ? 6.0 : 10.0;
    final padV = compact ? 4.0 : 6.0;
    final barH = compact ? 2.0 : 2.0;

    Widget tile(String label, String value, IconData icon, Color accent) {
      return Container(
        decoration: BoxDecoration(
          color: _panel,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: ih,
              height: ih,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: compact ? 15 : 16, color: accent),
            ),
            SizedBox(width: compact ? 6 : 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: fsLabel,
                      color: _muted.withValues(alpha: 0.65),
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                  SizedBox(height: compact ? 0 : 1),
                  Text(
                    value,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: fsVal,
                      fontWeight: FontWeight.w800,
                      color: value == 'N/A'
                          ? _muted.withValues(alpha: 0.75)
                          : _text,
                      letterSpacing: -0.2,
                      height: 1.15,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: compact ? 3 : 4),
                  Container(
                    height: barH,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(2),
                      gradient: LinearGradient(
                        colors: [
                          accent.withValues(alpha: 0.35),
                          accent.withValues(alpha: 0.05),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 3,
      crossAxisSpacing: gap,
      mainAxisSpacing: gap,
      childAspectRatio: aspect,
      children: [
        tile(
          'THERMIQUE',
          '${thermal.toStringAsFixed(1)} °C',
          Icons.thermostat_rounded,
          thermalAccent,
        ),
        tile('PRESSION', pressureStr, Icons.speed_rounded, _cyan),
        tile(
          'PUISSANCE',
          '${power.toStringAsFixed(1)} kW',
          Icons.bolt_rounded,
          gold,
        ),
        tile(
          'VIBRATION',
          '${vibration.toStringAsFixed(2)} mm/s',
          Icons.vibration_rounded,
          vibAccent,
        ),
        tile(
          'MAGNÉTIQUE',
          '${magnetic.toStringAsFixed(2)} mT',
          Icons.explore_rounded,
          const Color(0xFF90CAF9),
        ),
        tile(
          'INFRA-ROUGE',
          irLabel,
          Icons.local_fire_department_outlined,
          const Color(0xFFFFAB91),
        ),
      ],
    );
  }
}

class _MaintenanceMachineCard extends StatelessWidget {
  const _MaintenanceMachineCard({
    required this.machine,
    required this.viewerName,
    required this.maintenanceAgentId,
    required this.compact,
  });

  final Map<String, dynamic> machine;
  final String viewerName;
  /// Identifiant agent maintenance (workspace) pour Mission Control.
  final String maintenanceAgentId;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    const surface = Color(0xFF1D1D38);
    const text = Color(0xFFE2DFFF);
    const muted = Color(0xFFE2BFB0);
    const accent = Color(0xFFFF6E00);

    final m = machine;
    final id = (m['machineId'] ?? '').toString();
    final name = (m['machineName'] ?? id).toString();
    final level = (m['level'] ?? 'NORMAL').toString();
    final status = (m['status'] ?? '').toString();
    final imageUrl = (m['imageUrl'] ?? '').toString();
    final metrics = _effectiveMachineMetrics(m);

    final imgSize = compact ? 72.0 : 100.0;
    final titleSize = compact ? 15.0 : 17.0;
    final bodyPad = compact ? 8.0 : 12.0;
    final sectionGap = compact ? 5.0 : 8.0;

    return Material(
      color: surface,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MachineDetailAiPage(
                machineId: id,
                machineName: name,
                viewerRole: 'maintenance',
                viewerName: viewerName,
              ),
            ),
          );
        },
        child: Padding(
          padding: EdgeInsets.all(bodyPad),
          child: Align(
            alignment: Alignment.topCenter,
            child: ListView(
              shrinkWrap: true,
              physics: const ClampingScrollPhysics(),
              padding: EdgeInsets.zero,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _buildMachineImageBox(imageUrl, size: imgSize),
                    SizedBox(height: compact ? 6 : 10),
                    Text(
                      name,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.spaceGrotesk(
                        color: text,
                        fontSize: titleSize,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: compact ? 2 : 3),
                    Text(
                      '$level · $id',
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.spaceGrotesk(
                        color: muted,
                        fontSize: compact ? 10 : 11,
                        letterSpacing: 0.3,
                      ),
                    ),
                    if (status.isNotEmpty) ...[
                      SizedBox(height: compact ? 2 : 2),
                      Text(
                        'Statut: $status',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          color: muted.withValues(alpha: 0.85),
                          fontSize: compact ? 10 : 11,
                        ),
                      ),
                    ],
                  ],
                ),
                SizedBox(height: sectionGap),
                MaintenanceMachineIaStrip(
                  machine: m,
                  compact: compact,
                ),
                SizedBox(height: sectionGap),
                Text(
                  'Capteurs',
                  style: GoogleFonts.inter(
                    color: accent,
                    fontSize: compact ? 10 : 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
                SizedBox(height: compact ? 3 : 6),
                _MaintenanceSensorSnapshotGrid(
                  metrics: metrics,
                  compact: compact,
                ),
                SizedBox(height: compact ? 4 : 6),
                Text(
                  'Message IA',
                  style: GoogleFonts.inter(
                    color: accent,
                    fontSize: compact ? 10 : 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
                SizedBox(height: compact ? 2 : 4),
                Text(
                  _iaMessageFromRow(m),
                  maxLines: compact ? 4 : 8,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: text.withValues(alpha: 0.92),
                    fontSize: compact ? 10 : 12,
                    height: 1.25,
                  ),
                ),
                SizedBox(height: compact ? 3 : 5),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      backgroundColor: accent.withValues(alpha: 0.16),
                      foregroundColor: accent,
                      padding: EdgeInsets.symmetric(
                        horizontal: compact ? 10 : 14,
                        vertical: compact ? 6 : 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(color: accent.withValues(alpha: 0.45)),
                      ),
                    ),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => MissionControlPage(
                            initialArgs: <String, dynamic>{
                              'machineId': id,
                              'techId': id,
                              'name': viewerName.isNotEmpty
                                  ? viewerName
                                  : 'Agent maintenance',
                              'machineName': name,
                              'viewerRole': 'maintenance',
                              if (maintenanceAgentId.isNotEmpty)
                                'technicianId': maintenanceAgentId,
                            },
                          ),
                        ),
                      );
                    },
                    icon: Icon(
                      Icons.assignment_turned_in_outlined,
                      size: compact ? 18 : 20,
                    ),
                    label: Text(
                      'Mission de contrôle',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        fontSize: compact ? 11.5 : 13,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: compact ? 4 : 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      'Voir le détail',
                      style: GoogleFonts.inter(
                        color: accent,
                        fontWeight: FontWeight.w600,
                        fontSize: compact ? 11 : 12,
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: accent,
                      size: compact ? 20 : 22,
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
}
