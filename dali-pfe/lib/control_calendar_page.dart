import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:dali_pfe/services/api_service.dart';

class ControlCalendarPage extends StatefulWidget {
  const ControlCalendarPage({super.key});

  @override
  State<ControlCalendarPage> createState() => _ControlCalendarPageState();
}

class _ControlCalendarPageState extends State<ControlCalendarPage> {
  // Theme colors based on the design
  static const _bg = Color(0xFF18192A);
  static const _surface = Color(0xFF212236);
  static const _surfaceHeader = Color(0xFF131422);
  static const _orange = Color(0xFFFF6E00);
  static const _redAlert = Color(0xFFF44336);
  static const _greenAlert = Color(0xFF4CAF50);
  static const _cyanAlert = Color(0xFF00ACC1);
  static const _textMain = Colors.white;
  static const _textMuted = Color(0xFFA0A0B0);

  List<Map<String, dynamic>> _allControles = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchControles();
  }

  Future<void> _fetchControles() async {
    setState(() => _isLoading = true);
    try {
      final data = await ApiService.getControles();
      if (mounted) {
        setState(() {
          _allControles = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur chargement: $e')),
        );
      }
    }
  }

  Future<void> _markAsDone(String id) async {
    try {
      await ApiService.updateControleStatus(id, 'terminé');
      _fetchControles();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $e')),
      );
    }
  }

  List<Map<String, dynamic>> _filterByPriority(String priority) {
    return _allControles.where((c) => 
      c['priorite'] == priority && c['statut'] == 'planifié'
    ).toList();
  }

  List<Map<String, dynamic>> get _termine => 
      _allControles.where((c) => c['statut'] == 'terminé').toList();

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    final technicianName = args?['technicianName']?.toString().toUpperCase() ?? 'PERSONNEL MAINTENANCE';

    return Scaffold(
      backgroundColor: _bg,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator(color: _orange))
              : RefreshIndicator(
                  onRefresh: _fetchControles,
                  color: _orange,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(32.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildTitleSection(technicianName),
                        const SizedBox(height: 32),
                        _buildStatsRow(),
                        const SizedBox(height: 48),
                        
                        _buildPrioritySection('URGENT', 'urgente', _redAlert),
                        _buildPrioritySection('HAUTE PRIORITÉ', 'haute', _orange),
                        _buildPrioritySection('NORMALE', 'normale', _cyanAlert),
                        _buildPrioritySection('BASSE', 'basse', _textMuted),
                        
                        const SizedBox(height: 48),
                        _buildSectionTitle('TERMINÉS', textColor: _greenAlert),
                        const SizedBox(height: 16),
                        if (_termine.isEmpty)
                          _buildEmptyState('Aucun contrôle terminé')
                        else
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _termine.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 12),
                            itemBuilder: (context, index) => _buildControlCard(_termine[index], isDone: true),
                          ),
                      ],
                    ),
                  ),
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrioritySection(String title, String priorityKey, Color color) {
    final list = _filterByPriority(priorityKey);
    if (list.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(title, textColor: color),
        const SizedBox(height: 16),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) => _buildControlCard(list[index]),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildControlCard(Map<String, dynamic> c, {bool isDone = false}) {
    final id = c['id'] ?? c['_id'];
    final machineName = c['machineName'] ?? 'Machine inconnue';
    final typeControle = c['typeControle'] ?? 'Maintenance';
    final motorType = c['motorType'] ?? 'air_cooled';
    final priorite = c['priorite'] ?? 'normale';
    final heures = c['heuresDeClenchement'] ?? 0;
    final date = c['createdAt'] != null ? DateTime.parse(c['createdAt']) : DateTime.now();
    final dateStr = "${date.day}/${date.month}/${date.year}";

    Color prioColor = _cyanAlert;
    if (priorite == 'urgente') prioColor = _redAlert;
    if (priorite == 'haute') prioColor = _orange;
    if (priorite == 'basse') prioColor = _textMuted;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: isDone ? _greenAlert : prioColor, width: 4)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      machineName,
                      style: GoogleFonts.inter(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 12),
                    _buildBadge(motorType.toUpperCase(), _cyanAlert.withOpacity(0.2), _cyanAlert),
                    const SizedBox(width: 8),
                    _buildBadge(priorite.toUpperCase(), prioColor.withOpacity(0.2), prioColor),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.settings, color: _textMuted, size: 14),
                    const SizedBox(width: 6),
                    Text(typeControle, style: GoogleFonts.inter(color: _textMain, fontSize: 14, fontWeight: FontWeight.w500)),
                    const SizedBox(width: 16),
                    const Icon(Icons.timer_outlined, color: _textMuted, size: 14),
                    const SizedBox(width: 6),
                    Text('${heures}h atteints', style: GoogleFonts.inter(color: _textMuted, fontSize: 12)),
                    const SizedBox(width: 16),
                    const Icon(Icons.calendar_today, color: _textMuted, size: 14),
                    const SizedBox(width: 6),
                    Text(dateStr, style: GoogleFonts.inter(color: _textMuted, fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
          if (!isDone)
            ElevatedButton(
              onPressed: () => _markAsDone(id),
              style: ElevatedButton.styleFrom(
                backgroundColor: _greenAlert,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              ),
              child: const Text('MARQUER COMME TERMINÉ'),
            )
          else
            const Icon(Icons.check_circle, color: _greenAlert, size: 32),
        ],
      ),
    );
  }

  Widget _buildBadge(String label, Color bg, Color text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
      child: Text(label, style: GoogleFonts.inter(color: text, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Text(message, style: GoogleFonts.inter(color: _textMuted)),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      color: _surfaceHeader,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'TECH_OS // OBSERVATORY',
            style: GoogleFonts.inter(
              color: _orange,
              fontWeight: FontWeight.w900,
              fontSize: 18,
              letterSpacing: 1.5,
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close, color: _textMuted),
          )
        ],
      ),
    );
  }

  Widget _buildTitleSection(String technicianName) {
    final now = DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'CALENDRIER DE CONTRÔLE',
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: 36,
            fontWeight: FontWeight.w900,
            letterSpacing: -1,
          ),
        ),
        Row(
          children: [
            Container(width: 30, height: 2, color: _cyanAlert),
            const SizedBox(width: 8),
            Text(
              'DATE : ${now.day}/${now.month}/${now.year} • TECHNICIEN : $technicianName',
              style: GoogleFonts.spaceGrotesk(
                color: _cyanAlert,
                fontSize: 14,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatsRow() {
    final aFaire = _allControles.where((c) => c['statut'] == 'planifié').length;
    final urgent = _allControles.where((c) => c['priorite'] == 'urgente' && c['statut'] == 'planifié').length;
    final termine = _allControles.where((c) => c['statut'] == 'terminé').length;

    return Row(
      children: [
        Expanded(child: _buildStatCard('À FAIRE', aFaire.toString(), 'TÂCHES', _orange)),
        const SizedBox(width: 16),
        Expanded(child: _buildStatCard('URGENT', urgent.toString(), 'ACTIONS', _redAlert, isOutlined: urgent > 0)),
        const SizedBox(width: 16),
        Expanded(child: _buildStatCard('TERMINÉS', termine.toString(), 'TOTAL', _greenAlert, isIconCheck: true)),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, String unit, Color color, {bool isOutlined = false, bool isIconCheck = false}) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(8),
        border: isOutlined ? Border.all(color: color.withOpacity(0.5), width: 1.5) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(isIconCheck ? Icons.check_circle : Icons.circle, color: color, size: 12),
              const SizedBox(width: 8),
              Text(
                title,
                style: GoogleFonts.inter(color: color, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: GoogleFonts.inter(color: Colors.white, fontSize: 48, fontWeight: FontWeight.w300),
              ),
              const SizedBox(width: 8),
              Text(
                unit,
                style: GoogleFonts.spaceGrotesk(color: _textMuted, fontSize: 10, letterSpacing: 1),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, {Color textColor = _redAlert}) {
    return Row(
      children: [
        Text(
          title,
          style: GoogleFonts.inter(color: textColor, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 2),
        ),
        const SizedBox(width: 16),
        Expanded(child: Container(height: 1, color: _surface)),
      ],
    );
  }
}

