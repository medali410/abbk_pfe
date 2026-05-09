import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'maintenance_ia_status.dart';

/// Panneau latéral « Modèle IA » : état par machine (données workspace / télémétrie).
class MaintenanceMlModelSidebar extends StatelessWidget {
  const MaintenanceMlModelSidebar({
    super.key,
    this.compact = false,
    this.machines,
  });

  final bool compact;

  /// Machines du workspace (`/maintenance/workspace`).
  final List<Map<String, dynamic>>? machines;

  static const _text = Color(0xFFE2DFFF);
  static const _muted = Color(0xFFE2BFB0);
  static const _accent = Color(0xFFFF6E00);
  static const _panel = Color(0xFF131429);

  @override
  Widget build(BuildContext context) {
    final pad = compact ? 12.0 : 16.0;
    final list = machines ?? const <Map<String, dynamic>>[];

    return Material(
      color: _panel,
      child: Padding(
        padding: EdgeInsets.all(pad),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  Icons.psychology_outlined,
                  color: _accent.withValues(alpha: 0.95),
                  size: compact ? 22 : 24,
                ),
                SizedBox(width: compact ? 8 : 10),
                Expanded(
                  child: Text(
                    'MODÈLE IA',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: compact ? 11 : 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                      color: _text,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: compact ? 10 : 12),
            Text(
              'Synthèse du risque et du scénario issus des dernières données.',
              style: GoogleFonts.inter(
                fontSize: compact ? 9.5 : 10,
                color: _muted.withValues(alpha: 0.85),
                height: 1.35,
              ),
            ),
            SizedBox(height: compact ? 12 : 14),
            Text(
              'ÉTAT PAR MACHINE',
              style: GoogleFonts.spaceGrotesk(
                fontSize: compact ? 10.5 : 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.9,
                color: _text,
              ),
            ),
            SizedBox(height: compact ? 8 : 10),
            if (list.isEmpty)
              Text(
                'Aucune machine dans le périmètre.',
                style: GoogleFonts.inter(
                  fontSize: compact ? 10 : 11,
                  color: _muted.withValues(alpha: 0.75),
                ),
              )
            else
              for (final mach in list)
                MaintenanceIaSidebarMachineRow(
                  machine: mach,
                  compact: compact,
                ),
          ],
        ),
      ),
    );
  }
}
