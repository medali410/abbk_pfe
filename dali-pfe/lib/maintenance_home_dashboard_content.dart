import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'machine_detail_ai_page.dart';

class MaintenanceHomeDashboardContent extends StatelessWidget {
  const MaintenanceHomeDashboardContent({
    super.key,
    required this.data,
    required this.onTabSelect,
    required this.onWorkspaceReload,
  });

  final Map<String, dynamic> data;
  final ValueChanged<String> onTabSelect;
  final VoidCallback onWorkspaceReload;

  @override
  Widget build(BuildContext context) {
    const surface = Color(0xFF1D1D38);
    const textColor = Color(0xFFE2DFFF);
    const mutedColor = Color(0xFFE2BFB0);
    const accent = Color(0xFFFF6E00);

    final agent = (data['agent'] as Map?)?.cast<String, dynamic>() ?? {};
    final String agentName = (agent['fullName'] ?? agent['name'] ?? 'Agent').toString();
    
    final machines = (data['machines'] as List? ?? const [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();

    final totalMachines = machines.length;
    final criticalMachines = machines
        .where((m) => (m['level'] ?? '').toString().toUpperCase() == 'CRITICAL')
        .length;
    final warningMachines = machines
        .where((m) => (m['level'] ?? '').toString().toUpperCase() == 'WARNING')
        .length;
    final normalMachines = totalMachines - criticalMachines - warningMachines;

    final alerts = machines
        .where((m) => (m['level'] ?? '').toString().toUpperCase() != 'NORMAL')
        .toList();

    return RefreshIndicator(
      onRefresh: () async => onWorkspaceReload(),
      color: accent,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        children: [
          // --- Welcome Header Banner ---
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF2E1B4E), Color(0xFF13112E)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.25),
                  blurRadius: 15,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Bonjour, $agentName',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Bienvenue sur votre espace de pilotage. Voici l\'état actuel de votre parc de machines.',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: textColor.withOpacity(0.8),
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // --- KPI Stats Row ---
          LayoutBuilder(
            builder: (context, constraints) {
              final cols = constraints.maxWidth > 700 ? 4 : 2;
              return GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: cols,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: cols == 4 ? 1.4 : 1.5,
                children: [
                  _buildKpiCard(
                    title: 'Machines Totales',
                    value: '$totalMachines',
                    icon: Icons.precision_manufacturing_outlined,
                    iconColor: const Color(0xFF75D1FF),
                    bgColor: surface,
                  ),
                  _buildKpiCard(
                    title: 'Alertes Critiques',
                    value: '$criticalMachines',
                    icon: Icons.error_outline_rounded,
                    iconColor: const Color(0xFFFFB4AB),
                    bgColor: surface,
                    hasAlert: criticalMachines > 0,
                  ),
                  _buildKpiCard(
                    title: 'Avertissements',
                    value: '$warningMachines',
                    icon: Icons.warning_amber_rounded,
                    iconColor: const Color(0xFFFFD54F),
                    bgColor: surface,
                  ),
                  _buildKpiCard(
                    title: 'Normales / Actives',
                    value: '$normalMachines',
                    icon: Icons.check_circle_outline_rounded,
                    iconColor: const Color(0xFF81C784),
                    bgColor: surface,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),

          // --- Two Column Layout: Machine Health Breakdown & Quick Access ---
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 800;
              final content = [
                // Column 1: Health Breakdown & Quick Navigation
                Expanded(
                  flex: isWide ? 4 : 0,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Machine Distribution Bar
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withOpacity(0.06)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Répartition de l\'état de santé',
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 16),
                            // Custom segment bar
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: SizedBox(
                                height: 16,
                                child: Row(
                                  children: [
                                    if (criticalMachines > 0)
                                      Expanded(
                                        flex: criticalMachines,
                                        child: Container(
                                          color: const Color(0xFFFFB4AB),
                                        ),
                                      ),
                                    if (warningMachines > 0)
                                      Expanded(
                                        flex: warningMachines,
                                        child: Container(
                                          color: const Color(0xFFFFD54F),
                                        ),
                                      ),
                                    if (normalMachines > 0)
                                      Expanded(
                                        flex: normalMachines,
                                        child: Container(
                                          color: const Color(0xFF81C784),
                                        ),
                                      ),
                                    if (totalMachines == 0)
                                      Expanded(
                                        child: Container(
                                          color: Colors.grey.withOpacity(0.3),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                _buildStatusIndicator('Normal', const Color(0xFF81C784), normalMachines, totalMachines),
                                _buildStatusIndicator('Warning', const Color(0xFFFFD54F), warningMachines, totalMachines),
                                _buildStatusIndicator('Critique', const Color(0xFFFFB4AB), criticalMachines, totalMachines),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Quick Shortcuts Box
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withOpacity(0.06)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Raccourcis & Actions Rapides',
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _buildShortcutRow(
                              context,
                              title: 'Consulter le Hub Machine',
                              subtitle: 'Vue Netflix des diagnostics thermiques & vibratoires',
                              icon: Icons.precision_manufacturing_outlined,
                              color: const Color(0xFFFF6E00),
                              onTap: () => onTabSelect('machineDetail'),
                            ),
                            const Divider(color: Colors.white10, height: 16),
                            _buildShortcutRow(
                              context,
                              title: 'Consulter l\'Historique des Missions',
                              subtitle: 'Suivi des interventions avec les techniciens',
                              icon: Icons.history_rounded,
                              color: const Color(0xFF75D1FF),
                              onTap: () => onTabSelect('missionHistory'),
                            ),
                            const Divider(color: Colors.white10, height: 16),
                            _buildShortcutRow(
                              context,
                              title: 'Analyses Prédicitives IA',
                              subtitle: 'Résultats des diagnostics générés par IA',
                              icon: Icons.analytics_outlined,
                              color: const Color(0xFF81C784),
                              onTap: () => onTabSelect('aiAnalysis'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (isWide) const SizedBox(width: 20),
                // Column 2: Alarms & Alerts Panel
                Expanded(
                  flex: isWide ? 5 : 0,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!isWide) const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withOpacity(0.06)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Alertes Actives & Diagnostics',
                                  style: GoogleFonts.spaceGrotesk(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                if (alerts.isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFB4AB).withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      '${alerts.length} Machine(s)',
                                      style: GoogleFonts.spaceGrotesk(
                                        fontSize: 10,
                                        color: const Color(0xFFFFB4AB),
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            if (alerts.isEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 32),
                                child: Center(
                                  child: Column(
                                    children: [
                                      const Icon(
                                        Icons.check_circle_outline_rounded,
                                        color: Color(0xFF81C784),
                                        size: 40,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Toutes les machines sont opérationnelles',
                                        style: GoogleFonts.inter(
                                          color: mutedColor,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            else
                              ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: alerts.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 10),
                                itemBuilder: (context, idx) {
                                  final m = alerts[idx];
                                  final String name = (m['machineName'] ?? m['machineId'] ?? 'Machine').toString();
                                  final level = (m['level'] ?? 'WARNING').toString().toUpperCase();
                                  final color = level == 'CRITICAL' ? const Color(0xFFFFB4AB) : const Color(0xFFFFD54F);
                                  
                                  return InkWell(
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => MachineDetailAiPage(
                                            machineId: (m['machineId'] ?? '').toString(),
                                            machineName: name,
                                            viewerRole: 'maintenance',
                                            viewerName: agentName,
                                          ),
                                        ),
                                      );
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF131429),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: color.withOpacity(0.2)),
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color: color.withOpacity(0.1),
                                              shape: BoxShape.circle,
                                            ),
                                            child: Icon(
                                              Icons.warning_amber_rounded,
                                              color: color,
                                              size: 20,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  name,
                                                  style: GoogleFonts.spaceGrotesk(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                                const SizedBox(height: 3),
                                                Text(
                                                  'Niveau : $level · ID: ${m['machineId']}',
                                                  style: GoogleFonts.inter(
                                                    fontSize: 11,
                                                    color: mutedColor,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          const Icon(
                                            Icons.chevron_right_rounded,
                                            color: Colors.white30,
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ];

              if (isWide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: content,
                );
              } else {
                return Column(
                  children: content,
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
    bool hasAlert = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasAlert
              ? const Color(0xFFFFB4AB).withOpacity(0.4)
              : Colors.white.withOpacity(0.06),
          width: hasAlert ? 1.5 : 1.0,
        ),
        boxShadow: hasAlert
            ? [
                BoxShadow(
                  color: const Color(0xFFFFB4AB).withOpacity(0.1),
                  blurRadius: 10,
                  spreadRadius: 1,
                )
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: const Color(0xFFE2BFB0).withOpacity(0.7),
                  fontWeight: FontWeight.w500,
                ),
              ),
              Icon(icon, color: iconColor, size: 20),
            ],
          ),
          Text(
            value,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusIndicator(String label, Color color, int count, int total) {
    final double pct = total > 0 ? (count / total) * 100 : 0.0;
    return Column(
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.inter(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '$count (${pct.toStringAsFixed(0)}%)',
          style: GoogleFonts.spaceGrotesk(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildShortcutRow(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: const Color(0xFFE2BFB0).withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              color: Colors.white30,
              size: 14,
            ),
          ],
        ),
      ),
    );
  }
}
