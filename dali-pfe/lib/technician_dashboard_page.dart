import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'services/api_service.dart';
import 'services/theme_service.dart';

class TechnicianDashboardPage extends StatefulWidget {
  const TechnicianDashboardPage({super.key});

  @override
  State<TechnicianDashboardPage> createState() => _TechnicianDashboardPageState();
}

class _TechnicianDashboardPageState extends State<TechnicianDashboardPage> {
  bool _isLoading = true;
  Map<String, dynamic>? _missionsSidebarData;
  List<Map<String, dynamic>> _consultations = [];

  bool get _isDark => ThemeService().isDarkMode;
  Color get _pageBg => _isDark ? const Color(0xFF0F0F1E) : const Color(0xFFF3F6FA);
  Color get _surface => _isDark ? const Color(0xFF1D1D38) : Colors.white;
  Color get _primary => const Color(0xFF2563EB); // Vibrant Blue
  Color get _secondary => const Color(0xFF8B5CF6); // Vibrant Purple
  Color get _accent => const Color(0xFF10B981); // Emerald Green
  Color get _onSurface => _isDark ? Colors.white : const Color(0xFF1E293B);
  Color get _onSurfaceMuted => _isDark ? Colors.white70 : const Color(0xFF64748B);

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    ThemeService().addListener(_onThemeChanged);
    _loadData();
  }

  @override
  void dispose() {
    ThemeService().removeListener(_onThemeChanged);
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final missionsFuture = ApiService.getMissionsSidebar();
      final consultationsFuture = ApiService.getConsultations();
      
      final results = await Future.wait([missionsFuture, consultationsFuture]);
      
      _missionsSidebarData = results[0] as Map<String, dynamic>?;
      _consultations = results[1] as List<Map<String, dynamic>>;
      
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _isDark ? Colors.white.withValues(alpha: 0.05) : color.withValues(alpha: 0.1), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.08),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(height: 20),
            Text(value, style: GoogleFonts.spaceGrotesk(color: _onSurface, fontSize: 36, fontWeight: FontWeight.w800, letterSpacing: -1)),
            const SizedBox(height: 4),
            Text(title, style: GoogleFonts.inter(color: _onSurfaceMuted, fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _buildMissionsList() {
    if (_missionsSidebarData == null) return const SizedBox();
    
    final counts = _missionsSidebarData!['counts'] ?? {};
    final grouped = _missionsSidebarData!['grouped'] ?? {};
    final pending = (grouped['PENDING'] as List?) ?? [];
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ]
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text('Missions En Attente', style: GoogleFonts.inter(color: _onSurface, fontSize: 18, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: _primary.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
                child: Text('${counts['pending'] ?? 0}', style: GoogleFonts.inter(color: _primary, fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (pending.isEmpty)
            Text('Aucune mission en attente', style: GoogleFonts.inter(color: _onSurfaceMuted, fontStyle: FontStyle.italic))
          else
            ...pending.take(5).map((m) => _buildMissionTile(m as Map<String, dynamic>)),
        ],
      ),
    );
  }

  Widget _buildMissionTile(Map<String, dynamic> mission) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _isDark ? Colors.white.withValues(alpha: 0.03) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: _primary.withOpacity(0.1),
            child: Icon(Icons.assignment, color: _primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(mission['title'] ?? 'Mission sans titre', style: GoogleFonts.inter(color: _onSurface, fontWeight: FontWeight.w600)),
                Text('Machine: ${mission['machineName'] ?? mission['machineId']}', style: GoogleFonts.inter(color: _onSurfaceMuted, fontSize: 13)),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.play_circle_fill, color: _primary, size: 28),
            onPressed: () {
              Navigator.pushNamed(context, '/mission-control', arguments: {
                'missionId': mission['id'],
                'machineId': mission['machineId'],
                'machineName': mission['machineName'],
              });
            },
          )
        ],
      ),
    );
  }

  Widget _buildConsultationsList() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ]
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text('Mes Consultations', style: GoogleFonts.inter(color: _onSurface, fontSize: 18, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              IconButton(
                icon: Icon(Icons.add_circle, color: _secondary),
                onPressed: () => Navigator.pushNamed(context, '/machine-consultation'),
              )
            ],
          ),
          const SizedBox(height: 16),
          if (_consultations.isEmpty)
            Text('Aucune consultation prévue', style: GoogleFonts.inter(color: _onSurfaceMuted, fontStyle: FontStyle.italic))
          else
            ..._consultations.take(5).map((c) {
              final dt = DateTime.tryParse(c['scheduledDate'] ?? '');
              final formattedDate = dt != null ? DateFormat('dd MMM yyyy à HH:mm').format(dt) : 'Date inconnue';
              
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _isDark ? Colors.white.withValues(alpha: 0.03) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _secondary.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.event, color: _secondary, size: 20),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Consultation Machine ${c['machineId']}', style: GoogleFonts.inter(color: _onSurface, fontWeight: FontWeight.w600)),
                          Text(formattedDate, style: GoogleFonts.inter(color: _secondary, fontSize: 13)),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: _pageBg,
        body: Center(child: CircularProgressIndicator(color: _primary)),
      );
    }

    final counts = _missionsSidebarData?['counts'] ?? {};

    return Scaffold(
      backgroundColor: _pageBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: _onSurface,
        title: Text('Tableau de Bord Technicien', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: _onSurface)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
          IconButton(
            onPressed: () {
              ThemeService().toggleTheme();
              setState(() {});
            },
            icon: Icon(
              ThemeService().isDarkMode ? Icons.wb_sunny_rounded : Icons.nightlight_round,
              color: ThemeService().isDarkMode ? Colors.amber : const Color(0xFF7A4B29),
              size: 22,
            ),
            tooltip: ThemeService().isDarkMode ? 'Mode Jour' : 'Mode Nuit',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: _isDark
                      ? [const Color(0xFF1E3A8A).withValues(alpha: 0.5), const Color(0xFF0F172A)]
                      : [const Color(0xFFEFF6FF), const Color(0xFFF8FAFC)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: _isDark
                      ? Colors.white.withValues(alpha: 0.1)
                      : _primary.withValues(alpha: 0.1),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Bonjour, Équipe Technicienne 👋',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: _onSurface,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Voici votre aperçu d\'activité pour aujourd\'hui. Il vous reste ${counts['pending'] ?? 0} interventions en attente.',
                    style: GoogleFonts.inter(color: _onSurfaceMuted, fontSize: 15, height: 1.4),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            Row(
              children: [
                _buildStatCard('Missions en cours', '${counts['inProgress'] ?? 0}', Icons.engineering_rounded, _primary),
                const SizedBox(width: 24),
                _buildStatCard('Total Missions', '${counts['total'] ?? 0}', Icons.analytics_rounded, _secondary),
                const SizedBox(width: 24),
                _buildStatCard('Consultations', '${_consultations.length}', Icons.event_note_rounded, _accent),
              ],
            ),
            const SizedBox(height: 32),
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 600) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildMissionsList(),
                      const SizedBox(height: 20),
                      _buildConsultationsList(),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 2, child: _buildMissionsList()),
                    const SizedBox(width: 20),
                    Expanded(flex: 1, child: _buildConsultationsList()),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
