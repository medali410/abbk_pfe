import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'ai_analysis_page.dart';
import 'maintenance_ai_chat_page.dart';
import 'maintenance_ia_status.dart';
import 'maintenance_telemetry_mini_charts.dart';

/// Onglet « Analyse IA » : vue dédiée au risque et aux scénarios par machine.
class MaintenanceAiAnalysisContent extends StatefulWidget {
  const MaintenanceAiAnalysisContent({
    super.key,
    required this.data,
    required this.onWorkspaceReload,
    this.viewerRole = 'maintenance',
  });

  final Map<String, dynamic> data;
  final VoidCallback onWorkspaceReload;
  final String viewerRole;

  @override
  State<MaintenanceAiAnalysisContent> createState() => _MaintenanceAiAnalysisContentState();
}

class _MaintenanceAiAnalysisContentState extends State<MaintenanceAiAnalysisContent> {
  static const _text = Color(0xFFE2DFFF);
  static const _muted = Color(0xFFE2BFB0);
  static const _accent = Color(0xFFFF6E00);
  
  final PageController _pageController = PageController(viewportFraction: 0.92);
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rows =
        (widget.data['machines'] as List? ?? const [])
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
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => Scaffold(
                        backgroundColor: const Color(0xFF0D0D1F),
                        appBar: AppBar(
                          backgroundColor: const Color(0xFF1A1A2E),
                          title: Text(
                            'Assistant IA',
                            style: GoogleFonts.spaceGrotesk(
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFFE2DFFF),
                            ),
                          ),
                          iconTheme: const IconThemeData(color: Color(0xFFE2DFFF)),
                        ),
                        body: MaintenanceAiChatPage(data: widget.data),
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18, color: Color(0xFFB388FF)),
                label: Text(
                  'Chat IA',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFFB388FF),
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              TextButton.icon(
                onPressed: widget.onWorkspaceReload,
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
        Container(
          height: 50,
          margin: const EdgeInsets.symmetric(horizontal: 16),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: rows.length,
            itemBuilder: (context, idx) {
              final m = rows[idx];
              final name = (m['machineName'] ?? m['name'] ?? m['machineId'] ?? m['id'] ?? 'Machine').toString();
              final isSelected = _currentPage == idx;
              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: ChoiceChip(
                  label: Text(name),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) {
                      _pageController.animateToPage(
                        idx,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    }
                  },
                  selectedColor: _accent.withOpacity(0.2),
                  backgroundColor: const Color(0xFF1D1D38),
                  labelStyle: GoogleFonts.inter(
                    color: isSelected ? _accent : _text,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 13,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(
                      color: isSelected ? _accent : Colors.transparent,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            onPageChanged: (idx) => setState(() => _currentPage = idx),
            itemCount: rows.length,
            itemBuilder: (context, i) {
              final m = rows[i];
              final id = (m['machineId'] ?? m['id'] ?? '').toString();
              final name = (m['machineName'] ?? m['name'] ?? id).toString();
              final motorType =
                  (m['motorType'] ?? m['type_moteur'] ?? 'EL_M').toString();
              final insight = iaInsightMessage(m);

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 8.0),
                child: Material(
                  color: const Color(0xFF1D1D38),
                  borderRadius: BorderRadius.circular(16),
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
                            viewerRole: widget.viewerRole,
                          ),
                        ),
                      );
                    },
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.precision_manufacturing_outlined,
                                color: _accent.withValues(alpha: 0.9),
                                size: 24,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  name,
                                  style: GoogleFonts.spaceGrotesk(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: _text,
                                  ),
                                ),
                              ),
                              Text(
                                '${iaProbPanne(m).toStringAsFixed(0)} %',
                                style: GoogleFonts.spaceGrotesk(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: iaLevelAccent(m),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          MaintenanceMachineIaStrip(
                            machine: m,
                            compact: false,
                          ),
                          const SizedBox(height: 16),
                          // Les LineChart capturent les taps ; on les ignore pour que le InkWell ouvre la page.
                          IgnorePointer(
                            child: MaintenanceTelemetryMiniCharts(
                              key: ValueKey('telemetry-$id'),
                              machineId: id,
                              compact: false,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              insight,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: _text.withValues(alpha: 0.88),
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        // Indicateur de page
        if (rows.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 24.0, top: 12.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(rows.length, (index) {
                final isSelected = _currentPage == index;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.symmetric(horizontal: 4.0),
                  height: 6,
                  width: isSelected ? 20 : 6,
                  decoration: BoxDecoration(
                    color: isSelected ? _accent : _muted.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(3),
                  ),
                );
              }),
            ),
          ),
      ],
    );
  }
}
