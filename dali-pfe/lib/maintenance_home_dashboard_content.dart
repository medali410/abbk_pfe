import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'machine_detail_ai_page.dart';
import 'maintenance_ai_chat_page.dart';
import 'services/api_service.dart';
import 'services/theme_service.dart';

class MaintenanceHomeDashboardContent extends StatefulWidget {
  const MaintenanceHomeDashboardContent({
    super.key,
    required this.data,
    required this.liveStates,
    required this.onTabSelect,
    required this.onWorkspaceReload,
  });

  final Map<String, dynamic> data;
  final Map<String, String> liveStates;
  final ValueChanged<String> onTabSelect;
  final VoidCallback onWorkspaceReload;

  @override
  State<MaintenanceHomeDashboardContent> createState() => _MaintenanceHomeDashboardContentState();
}

class _MaintenanceHomeDashboardContentState extends State<MaintenanceHomeDashboardContent> {
  bool _showChat = false;

  bool get _isDarkMode => ThemeService().isDarkMode;
  Color get _surface => _isDarkMode ? const Color(0xFF1D1D38) : Colors.white;
  Color get _textColor => _isDarkMode ? const Color(0xFFE2DFFF) : const Color(0xFF1E1E2D);
  Color get _mutedColor => _isDarkMode ? const Color(0xFFE2BFB0) : const Color(0xFF64748B);
  static const _accent = Color(0xFFFF6E00);
  static const _aiColor = Color(0xFFB388FF);

  @override
  Widget build(BuildContext context) {
    final agent = (widget.data['agent'] as Map?)?.cast<String, dynamic>() ?? {};
    final String agentName = (agent['fullName'] ?? agent['name'] ?? 'Agent').toString();

    final machines = (widget.data['machines'] as List? ?? const [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();

    final totalMachines = machines.length;
    final criticalMachines = machines.where((m) {
      final state = widget.liveStates[(m['machineId'] ?? m['id'] ?? '').toString()];
      final level = state ?? (m['level'] ?? 'NORMAL').toString().toUpperCase();
      return level == 'CRITICAL' || level == 'DANGER';
    }).length;
    final warningMachines = machines.where((m) {
      final state = widget.liveStates[(m['machineId'] ?? m['id'] ?? '').toString()];
      final level = state ?? (m['level'] ?? 'NORMAL').toString().toUpperCase();
      return level == 'WARNING' || level == 'RISQUE';
    }).length;
    final normalMachines = totalMachines - criticalMachines - warningMachines;

    return LayoutBuilder(builder: (context, constraints) {
      final isWide = constraints.maxWidth > 900;

      return Row(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => widget.onWorkspaceReload(),
              color: _accent,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
                children: [
                  Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: _isDarkMode
                            ? [const Color(0xFF2E1B4E), const Color(0xFF13112E)]
                            : [const Color(0xFFFFECE0), const Color(0xFFFFF6F0)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: _isDarkMode
                            ? Colors.white.withValues(alpha: 0.08)
                            : const Color(0xFFFF6E00).withValues(alpha: 0.15),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Bonjour, $agentName 👋',
                                style: GoogleFonts.spaceGrotesk(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: _isDarkMode ? Colors.white : const Color(0xFF7A4B29),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Voici l\'état actuel de votre parc de $totalMachines machine(s).',
                                style: GoogleFonts.inter(
                                  fontSize: 15,
                                  color: _isDarkMode
                                      ? const Color(0xFFE2DFFF).withValues(alpha: 0.75)
                                      : const Color(0xFF8C5A3C),
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Chat toggle button
                        GestureDetector(
                          onTap: () => setState(() => _showChat = !_showChat),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: _showChat
                                  ? _aiColor.withOpacity(0.25)
                                  : _aiColor.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(30),
                              border: Border.all(
                                color: _aiColor.withOpacity(_showChat ? 0.7 : 0.3),
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _showChat ? Icons.close_rounded : Icons.psychology_rounded,
                                  color: _aiColor,
                                  size: 18,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _showChat ? 'Fermer' : 'Coach IA',
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: _aiColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── KPI Cards ─────────────────────────────────────────────
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: constraints.maxWidth > 800 ? 4 : 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: constraints.maxWidth > 800 ? 1.3 : 1.5,
                    children: [
                      _KpiCard(
                        title: 'Machines',
                        value: '$totalMachines',
                        icon: Icons.precision_manufacturing_outlined,
                        color: const Color(0xFF75D1FF),
                      ),
                      _KpiCard(
                        title: 'Critiques',
                        value: '$criticalMachines',
                        icon: Icons.error_outline_rounded,
                        color: const Color(0xFFFFB4AB),
                        pulse: criticalMachines > 0,
                      ),
                      _KpiCard(
                        title: 'Avertissements',
                        value: '$warningMachines',
                        icon: Icons.warning_amber_rounded,
                        color: const Color(0xFFFFD54F),
                      ),
                      _KpiCard(
                        title: 'Normales',
                        value: '$normalMachines',
                        icon: Icons.check_circle_outline_rounded,
                        color: const Color(0xFF81C784),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // ── Health bar ────────────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: _surface,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: _isDarkMode ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05)),
                      boxShadow: [
                        BoxShadow(
                          color: _isDarkMode ? Colors.transparent : Colors.black.withValues(alpha: 0.02),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Répartition de l\'état de santé',
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                            color: _textColor,
                          ),
                        ),
                        const SizedBox(height: 24),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: SizedBox(
                            height: 16,
                            child: Row(
                              children: [
                                if (criticalMachines > 0)
                                  Expanded(flex: criticalMachines, child: Container(color: const Color(0xFFFFB4AB))),
                                if (warningMachines > 0)
                                  Expanded(flex: warningMachines, child: Container(color: const Color(0xFFFFD54F))),
                                if (normalMachines > 0)
                                  Expanded(flex: normalMachines > 0 ? normalMachines : 1, child: Container(color: const Color(0xFF81C784))),
                                if (totalMachines == 0)
                                  Expanded(child: Container(color: Colors.grey.withOpacity(0.3))),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _StatusDot('Normal', const Color(0xFF81C784), normalMachines, totalMachines),
                            _StatusDot('Warning', const Color(0xFFFFD54F), warningMachines, totalMachines),
                            _StatusDot('Critique', const Color(0xFFFFB4AB), criticalMachines, totalMachines),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Machines list ─────────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: _surface,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: _isDarkMode ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05)),
                      boxShadow: [
                        BoxShadow(
                          color: _isDarkMode ? Colors.transparent : Colors.black.withValues(alpha: 0.02),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'État de Toutes les Machines',
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: _textColor,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFF75D1FF).withOpacity(0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '${machines.length} Machine(s)',
                                style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF75D1FF), fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        if (machines.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: Center(
                              child: Text('Aucune machine assignée', style: GoogleFonts.inter(color: _mutedColor, fontSize: 13)),
                            ),
                          )
                        else
                          ...machines.asMap().entries.map((entry) {
                            final i = entry.key;
                            final m = entry.value;
                            final mId = (m['machineId'] ?? m['id'] ?? '').toString();
                            final name = (m['machineName'] ?? m['name'] ?? mId).toString();
                            String clientName = 'Client Inconnu';
                            if (m['client'] is Map) {
                              clientName = (m['client']['name'] ?? m['client']['companyName'] ?? 'Client Inconnu').toString();
                            } else if (m['clientName'] != null) {
                              clientName = m['clientName'].toString();
                            }
                            final dbLevel = (m['level'] ?? 'NORMAL').toString().toUpperCase();
                            final activeState = widget.liveStates[mId] ?? dbLevel;
                            Color stateColor;
                            IconData stateIcon;
                            if (activeState == 'CRITICAL' || activeState == 'DANGER') {
                              stateColor = const Color(0xFFFFB4AB);
                              stateIcon = Icons.error_outline_rounded;
                            } else if (activeState == 'WARNING' || activeState == 'RISQUE') {
                              stateColor = const Color(0xFFFFD54F);
                              stateIcon = Icons.warning_amber_rounded;
                            } else {
                              stateColor = const Color(0xFF81C784);
                              stateIcon = Icons.check_circle_outline_rounded;
                            }
                            return Column(
                              children: [
                                 if (i > 0) Divider(height: 1, color: _isDarkMode ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05)),
                                InkWell(
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => MachineDetailAiPage(
                                        machineId: mId,
                                        machineName: name,
                                        viewerRole: 'maintenance',
                                        viewerName: agentName,
                                      ),
                                    ),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: stateColor.withOpacity(0.12),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(stateIcon, color: stateColor, size: 18),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                name,
                                                style: GoogleFonts.spaceGrotesk(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.bold,
                                                  color: _textColor,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                'Client : $clientName',
                                                style: GoogleFonts.inter(fontSize: 11, color: _mutedColor),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: stateColor.withOpacity(0.15),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            activeState,
                                            style: GoogleFonts.inter(fontSize: 10, color: stateColor, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Icon(Icons.chevron_right_rounded, color: _isDarkMode ? Colors.white30 : Colors.black38, size: 18),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            );
                          }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Quick shortcuts ───────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: _surface,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: _isDarkMode ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05)),
                      boxShadow: [
                        BoxShadow(
                          color: _isDarkMode ? Colors.transparent : Colors.black.withValues(alpha: 0.02),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Raccourcis Rapides',
                          style: GoogleFonts.spaceGrotesk(fontSize: 14, fontWeight: FontWeight.bold, color: _textColor),
                        ),
                        const SizedBox(height: 12),
                        _Shortcut(
                          icon: Icons.history_rounded,
                          title: 'Historique des Missions',
                          subtitle: 'Interventions avec les techniciens',
                          color: const Color(0xFF75D1FF),
                          onTap: () => widget.onTabSelect('missionHistory'),
                        ),
                        Divider(color: _isDarkMode ? Colors.white10 : Colors.black12, height: 12),
                        _Shortcut(
                          icon: Icons.analytics_outlined,
                          title: 'Analyses Prédictives IA',
                          subtitle: 'Résultats des diagnostics par IA',
                          color: _aiColor,
                          onTap: () => widget.onTabSelect('aiAnalysis'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── RIGHT: Chat IA panel (collapsible) ────────────────────────────
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            width: _showChat ? (isWide ? 380 : constraints.maxWidth * 0.95) : 0,
            child: _showChat
                ? Container(
                    decoration: BoxDecoration(
                      color: _isDarkMode ? const Color(0xFF0D0D1F) : const Color(0xFFF8FAFC),
                      border: Border(
                        left: BorderSide(color: _aiColor.withOpacity(0.2), width: 1.5),
                      ),
                    ),
                    child: MaintenanceAiChatPage(data: widget.data),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      );
    });
  }
}

// ── KPI Card ──────────────────────────────────────────────────────────────────

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.pulse = false,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final bool pulse;

  @override
  Widget build(BuildContext context) {
    final isDarkMode = ThemeService().isDarkMode;
    final cardBg = isDarkMode ? const Color(0xFF1D1D38) : Colors.white;
    final cardBorder = isDarkMode ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.06);
    final titleColor = isDarkMode ? Colors.white54 : const Color(0xFF64748B);
    final valueColor = pulse ? color : (isDarkMode ? Colors.white : const Color(0xFF1E1E2D));

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: pulse ? color.withValues(alpha: 0.5) : cardBorder,
          width: pulse ? 1.5 : 1,
        ),
        boxShadow: pulse
            ? [BoxShadow(color: color.withValues(alpha: 0.15), blurRadius: 18, offset: const Offset(0, 4))]
            : [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4))],
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
                  fontSize: 12,
                  color: titleColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 22),
              ),
            ],
          ),
          Text(
            value,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 34,
              fontWeight: FontWeight.w800,
              letterSpacing: -1,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Status Dot ────────────────────────────────────────────────────────────────

class _StatusDot extends StatelessWidget {
  const _StatusDot(this.label, this.color, this.count, this.total);

  final String label;
  final Color color;
  final int count;
  final int total;

  @override
  Widget build(BuildContext context) {
    final isDarkMode = ThemeService().isDarkMode;
    final textColor = isDarkMode ? Colors.white70 : const Color(0xFF1E1E2D);
    final pct = total > 0 ? (count / total * 100).toStringAsFixed(0) : '0';
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 5),
            Text(label, style: GoogleFonts.inter(fontSize: 11, color: textColor)),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          '$count ($pct%)',
          style: GoogleFonts.spaceGrotesk(fontSize: 12, fontWeight: FontWeight.bold, color: color),
        ),
      ],
    );
  }
}

// ── Shortcut Row ──────────────────────────────────────────────────────────────

class _Shortcut extends StatelessWidget {
  const _Shortcut({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDarkMode = ThemeService().isDarkMode;
    final titleColor = isDarkMode ? Colors.white : const Color(0xFF1E1E2D);
    final subtitleColor = isDarkMode ? Colors.white54 : const Color(0xFF64748B);
    final chevronColor = isDarkMode ? Colors.white30 : Colors.black38;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: GoogleFonts.spaceGrotesk(fontSize: 13, fontWeight: FontWeight.bold, color: titleColor)),
                  Text(subtitle, style: GoogleFonts.inter(fontSize: 11, color: subtitleColor)),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, color: chevronColor, size: 14),
          ],
        ),
      ),
    );
  }
}
