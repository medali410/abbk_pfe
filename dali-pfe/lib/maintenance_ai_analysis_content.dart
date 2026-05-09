import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'ai_analysis_page.dart';
import 'maintenance_ia_status.dart';
import 'maintenance_telemetry_mini_charts.dart';

/// Onglet « Analyse IA » : vue dédiée au risque et aux scénarios par machine.
class MaintenanceAiAnalysisContent extends StatelessWidget {
  const MaintenanceAiAnalysisContent({
    super.key,
    required this.data,
    required this.onWorkspaceReload,
  });

  final Map<String, dynamic> data;
  final VoidCallback onWorkspaceReload;

  static const _text = Color(0xFFE2DFFF);
  static const _muted = Color(0xFFE2BFB0);
  static const _accent = Color(0xFFFF6E00);

  @override
  Widget build(BuildContext context) {
    final rows =
        (data['machines'] as List? ?? const [])
            .map((e) => (e as Map).cast<String, dynamic>())
            .toList();

    if (rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Aucune machine assignée.',
            style: GoogleFonts.inter(color: _muted),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Synthèse du modèle de panne et des scénarios détectés sur vos machines.',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: _muted.withValues(alpha: 0.9),
                    height: 1.4,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: onWorkspaceReload,
                icon: const Icon(Icons.refresh_rounded, size: 18, color: _accent),
                label: Text(
                  'Actualiser',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    color: _accent,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            itemCount: rows.length,
            separatorBuilder: (_, __) => const SizedBox(height: 14),
            itemBuilder: (context, i) {
              final m = rows[i];
              final id = (m['machineId'] ?? '').toString();
              final name = (m['machineName'] ?? id).toString();
              final motorType =
                  (m['motorType'] ?? m['type_moteur'] ?? 'EL_M').toString();
              final insight = iaInsightMessage(m);

              return Material(
                color: const Color(0xFF1D1D38),
                borderRadius: BorderRadius.circular(14),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => MaintenanceAiAnalysisMachineScreen(
                          machineId: id,
                          machineName: name,
                          motorType: motorType.isNotEmpty ? motorType : 'EL_M',
                        ),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.precision_manufacturing_outlined,
                              color: _accent.withValues(alpha: 0.9),
                              size: 22,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                name,
                                style: GoogleFonts.spaceGrotesk(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: _text,
                                ),
                              ),
                            ),
                            Text(
                              '${iaProbPanne(m).toStringAsFixed(0)} %',
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: iaLevelAccent(m),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        MaintenanceMachineIaStrip(
                          machine: m,
                          compact: false,
                        ),
                        const SizedBox(height: 12),
                        // Les LineChart capturent les taps ; on les ignore pour que le InkWell ouvre la page.
                        IgnorePointer(
                          child: MaintenanceTelemetryMiniCharts(
                            key: ValueKey('telemetry-$id'),
                            machineId: id,
                            compact: false,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          insight,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: _text.withValues(alpha: 0.88),
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
