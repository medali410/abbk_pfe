import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'services/api_service.dart';

class TechnicianDashboardPage extends StatefulWidget {
  const TechnicianDashboardPage({super.key});

  @override
  State<TechnicianDashboardPage> createState() => _TechnicianDashboardPageState();
}

class _TechnicianDashboardPageState extends State<TechnicianDashboardPage> {
  bool _isLoading = true;
  Map<String, dynamic>? _missionsSidebarData;
  List<Map<String, dynamic>> _consultations = [];

  static const _surface = Color(0xFF1D1D38);
  static const _surfaceHighlight = Color(0xFF272743);
  static const _primary = Color(0xFFFF6E00);
  static const _secondary = Color(0xFF75D1FF);

  @override
  void initState() {
    super.initState();
    _loadData();
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
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3), width: 1),
          boxShadow: [
            BoxShadow(color: color.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 5)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 12),
            Text(value, style: GoogleFonts.inter(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(title, style: GoogleFonts.inter(color: Colors.white70, fontSize: 14)),
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
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Missions En Attente', style: GoogleFonts.inter(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: _primary.withOpacity(0.2), borderRadius: BorderRadius.circular(10)),
                child: Text('${counts['pending'] ?? 0}', style: GoogleFonts.inter(color: _primary, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (pending.isEmpty)
            Text('Aucune mission en attente', style: GoogleFonts.inter(color: Colors.white54, fontStyle: FontStyle.italic))
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
        color: _surfaceHighlight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: _primary.withOpacity(0.1),
            child: const Icon(Icons.assignment, color: _primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(mission['title'] ?? 'Mission sans titre', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600)),
                Text('Machine: ${mission['machineName'] ?? mission['machineId']}', style: GoogleFonts.inter(color: Colors.white60, fontSize: 13)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.play_circle_fill, color: Colors.greenAccent),
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
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Mes Consultations', style: GoogleFonts.inter(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              IconButton(
                icon: const Icon(Icons.add_circle, color: _secondary),
                onPressed: () => Navigator.pushNamed(context, '/machine-consultation'),
              )
            ],
          ),
          const SizedBox(height: 16),
          if (_consultations.isEmpty)
            Text('Aucune consultation prévue', style: GoogleFonts.inter(color: Colors.white54, fontStyle: FontStyle.italic))
          else
            ..._consultations.take(5).map((c) {
              final dt = DateTime.tryParse(c['scheduledDate'] ?? '');
              final formattedDate = dt != null ? DateFormat('dd MMM yyyy à HH:mm').format(dt) : 'Date inconnue';
              
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: _surfaceHighlight, borderRadius: BorderRadius.circular(12)),
                child: Row(
                  children: [
                    const Icon(Icons.event, color: _secondary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Consultation Machine ${c['machineId']}', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600)),
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
      return const Scaffold(
        backgroundColor: Color(0xFF0F0F1E),
        body: Center(child: CircularProgressIndicator(color: _primary)),
      );
    }

    final counts = _missionsSidebarData?['counts'] ?? {};

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1E),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Tableau de Bord Technicien', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Aperçu de l\'activité',
              style: GoogleFonts.inter(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                _buildStatCard('Missions en cours', '${counts['inProgress'] ?? 0}', Icons.engineering, _primary),
                const SizedBox(width: 16),
                _buildStatCard('Total Missions', '${counts['total'] ?? 0}', Icons.analytics, _secondary),
                const SizedBox(width: 16),
                _buildStatCard('Consultations', '${_consultations.length}', Icons.event_note, Colors.purpleAccent),
              ],
            ),
            const SizedBox(height: 32),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 2, child: _buildMissionsList()),
                const SizedBox(width: 20),
                Expanded(flex: 1, child: _buildConsultationsList()),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
