import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Données agrégées par la chaîne IoT + modèle (probabilité panne, scénario, niveau).

double iaProbPanne(Map<String, dynamic> m) {
  final v = m['probPanne'];
  if (v is num) return v.clamp(0, 100).toDouble();
  return double.tryParse('$v')?.clamp(0, 100) ?? 0;
}

String iaLevelKey(Map<String, dynamic> m) {
  return (m['level'] ?? 'NORMAL').toString().toUpperCase();
}

Color iaLevelAccent(Map<String, dynamic> m) {
  final colorKey = (m['color'] ?? '').toString().toUpperCase();
  if (colorKey == 'RED') return const Color(0xFFFF6B6B);
  if (colorKey == 'ORANGE') return const Color(0xFFFF9800);
  if (colorKey == 'GREEN') return const Color(0xFF66BB6A);
  final lv = iaLevelKey(m);
  if (lv == 'DANGER') return const Color(0xFFFF6B6B);
  if (lv == 'RISQUE') return const Color(0xFFFF9800);
  return const Color(0xFF66BB6A);
}

String iaLevelFr(Map<String, dynamic> m) {
  switch (iaLevelKey(m)) {
    case 'DANGER':
      return 'Critique';
    case 'RISQUE':
      return 'Risque';
    case 'NORMAL':
    default:
      return 'Normal';
  }
}

String iaScenarioShort(Map<String, dynamic> m) {
  final fs = m['failureScenario'];
  if (fs is Map) {
    final lab = (fs['scenarioLabel'] ?? '').toString().trim();
    if (lab.isNotEmpty) return lab;
  }
  return '';
}

/// Message synthétique (explication scénario, sinon recommandation backend).
String iaInsightMessage(Map<String, dynamic> m) {
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

/// Bandeau « état modèle IA » sur une carte machine.
class MaintenanceMachineIaStrip extends StatelessWidget {
  const MaintenanceMachineIaStrip({
    super.key,
    required this.machine,
    required this.compact,
  });

  final Map<String, dynamic> machine;
  final bool compact;

  static const _text = Color(0xFFE2DFFF);
  static const _muted = Color(0xFFE2BFB0);

  @override
  Widget build(BuildContext context) {
    final accent = iaLevelAccent(machine);
    final levelFr = iaLevelFr(machine);
    final prob = iaProbPanne(machine);
    final scenario = iaScenarioShort(machine);

    return Container(
      padding: EdgeInsets.all(compact ? 8 : 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_outlined, size: compact ? 15 : 16, color: accent),
              SizedBox(width: compact ? 6 : 8),
              Text(
                'ÉTAT IA',
                style: GoogleFonts.inter(
                  fontSize: compact ? 9.5 : 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.7,
                  color: accent,
                ),
              ),
              const Spacer(),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 8 : 10,
                  vertical: compact ? 3 : 4,
                ),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  levelFr,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: compact ? 10 : 11,
                    fontWeight: FontWeight.w800,
                    color: accent,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 6 : 8),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (prob / 100).clamp(0.0, 1.0),
                    minHeight: compact ? 5 : 6,
                    backgroundColor: Colors.white.withValues(alpha: 0.08),
                    color: accent,
                  ),
                ),
              ),
              SizedBox(width: compact ? 8 : 10),
              Text(
                '${prob.toStringAsFixed(0)} %',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: compact ? 11 : 12,
                  fontWeight: FontWeight.w800,
                  color: _text,
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 4 : 5),
          Text(
            'Probabilité de panne (modèle)',
            style: GoogleFonts.inter(
              fontSize: compact ? 9 : 10,
              color: _muted.withValues(alpha: 0.8),
            ),
          ),
          if (scenario.isNotEmpty) ...[
            SizedBox(height: compact ? 4 : 6),
            Text(
              scenario,
              maxLines: compact ? 2 : 3,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: compact ? 10 : 11,
                color: _text.withValues(alpha: 0.9),
                height: 1.25,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Ligne compacte pour la liste dans la barre latérale.
class MaintenanceIaSidebarMachineRow extends StatelessWidget {
  const MaintenanceIaSidebarMachineRow({
    super.key,
    required this.machine,
    required this.compact,
  });

  final Map<String, dynamic> machine;
  final bool compact;

  static const _text = Color(0xFFE2DFFF);
  static const _muted = Color(0xFFE2BFB0);

  @override
  Widget build(BuildContext context) {
    final name = (machine['machineName'] ?? machine['machineId'] ?? '—').toString();
    final accent = iaLevelAccent(machine);
    final prob = iaProbPanne(machine);
    final levelFr = iaLevelFr(machine);
    final scenario = iaScenarioShort(machine);

    return Padding(
      padding: EdgeInsets.only(bottom: compact ? 8 : 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 4,
            height: compact ? 44 : 48,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          SizedBox(width: compact ? 8 : 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: compact ? 11 : 11.5,
                    fontWeight: FontWeight.w700,
                    color: _text,
                  ),
                ),
                SizedBox(height: compact ? 2 : 3),
                Row(
                  children: [
                    Text(
                      levelFr,
                      style: GoogleFonts.inter(
                        fontSize: compact ? 10 : 10.5,
                        fontWeight: FontWeight.w700,
                        color: accent,
                      ),
                    ),
                    Text(
                      ' · ',
                      style: GoogleFonts.inter(
                        fontSize: compact ? 10 : 10.5,
                        color: _muted.withValues(alpha: 0.5),
                      ),
                    ),
                    Text(
                      '${prob.toStringAsFixed(0)} %',
                      style: GoogleFonts.inter(
                        fontSize: compact ? 10 : 10.5,
                        color: _muted.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
                if (scenario.isNotEmpty) ...[
                  SizedBox(height: 2),
                  Text(
                    scenario,
                    maxLines: compact ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: compact ? 9.5 : 10,
                      color: _muted.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
