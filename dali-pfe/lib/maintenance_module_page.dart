import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'add_concepteur_page.dart';
import 'add_maintenance_agent_page.dart';
import 'concepteur_detail_page.dart';
import 'services/api_service.dart';

class MaintenanceModulePage extends StatefulWidget {
  final bool standalone;
  final String? initialInterventionId;

  const MaintenanceModulePage({super.key, this.standalone = false, this.initialInterventionId});

  @override
  State<MaintenanceModulePage> createState() => _MaintenanceModulePageState();
}

class _MaintenanceModulePageState extends State<MaintenanceModulePage> {
  static const _bg = Color(0xFF10102B);
  static const _surface = Color(0xFF1D1D38);
  static const _onSurface = Color(0xFFE2DFFF);
  static const _onVariant = Color(0xFFE2BFB0);
  static const _primary = Color(0xFFFF6E00);
  static const _secondary = Color(0xFF75D1FF);

  int get _tabCount => ApiService.isSuperAdmin ? 4 : 3;

  TabBar _tabBar() {
    return TabBar(
      indicatorColor: _primary,
      labelColor: _primary,
      unselectedLabelColor: _onVariant,
      labelStyle: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1),
      tabs: ApiService.isSuperAdmin
          ? const [
              Tab(text: 'ORDRES DE MAINTENANCE'),
              Tab(text: 'CONCEPTEURS'),
              Tab(text: 'DIAGNOSTIC GUIDE'),
              Tab(text: 'PERSONNEL MAINT.'),
            ]
          : const [
              Tab(text: 'ORDRES DE MAINTENANCE'),
              Tab(text: 'CONCEPTEURS'),
              Tab(text: 'DIAGNOSTIC GUIDE'),
            ],
    );
  }

  List<Widget> _tabChildren() {
    final base = <Widget>[
      _MaintenanceOrdersTab(
        bg: _bg,
        surface: _surface,
        onSurface: _onSurface,
        onVariant: _onVariant,
        primary: _primary,
        secondary: _secondary,
      ),
      _ConcepteursTab(
        bg: _bg,
        surface: _surface,
        onSurface: _onSurface,
        onVariant: _onVariant,
        primary: _primary,
        secondary: _secondary,
        onRefresh: () => setState(() {}),
      ),
      _DiagnosticGuidedTab(
        bg: _bg,
        surface: _surface,
        onSurface: _onSurface,
        onVariant: _onVariant,
        primary: _primary,
        secondary: _secondary,
        initialInterventionId: widget.initialInterventionId,
      ),
    ];
    if (ApiService.isSuperAdmin) {
      base.add(
        _MaintenancePersonnelTab(
          bg: _bg,
          surface: _surface,
          onSurface: _onSurface,
          onVariant: _onVariant,
          primary: _primary,
          secondary: _secondary,
        ),
      );
    }
    return base;
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: _tabCount,
      initialIndex: widget.initialInterventionId != null ? 2 : 0,
      key: ValueKey<int>(_tabCount),
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: _surface,
          elevation: 0,
          title: Row(
            children: [
              Text('KINETIC_OBSERVATORY', style: GoogleFonts.spaceGrotesk(fontSize: 14, fontWeight: FontWeight.w900, color: _primary, letterSpacing: 1)),
              const Spacer(),
              Text('MAINTENANCE HUB', style: GoogleFonts.spaceGrotesk(fontSize: 11, fontWeight: FontWeight.bold, color: _primary)),
              const SizedBox(width: 24),
              Text('ARCHIVE', style: GoogleFonts.spaceGrotesk(fontSize: 11, fontWeight: FontWeight.bold, color: _onSurface)),
              const SizedBox(width: 24),
              Text('RAPPORTS', style: GoogleFonts.spaceGrotesk(fontSize: 11, fontWeight: FontWeight.bold, color: _onSurface)),
            ],
          ),
          actions: [
            IconButton(onPressed: () {}, icon: const Icon(Icons.notifications_none, size: 20)),
            IconButton(onPressed: () {}, icon: const Icon(Icons.settings_outlined, size: 20)),
            IconButton(onPressed: () {}, icon: const Icon(Icons.account_circle_outlined, size: 20)),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(48),
            child: Material(color: _surface, child: _tabBar()),
          ),
        ),
        body: TabBarView(children: _tabChildren()),
      ),
    );
  }
}

class _MaintenanceOrdersTab extends StatefulWidget {
  final Color bg;
  final Color surface;
  final Color onSurface;
  final Color onVariant;
  final Color primary;
  final Color secondary;

  const _MaintenanceOrdersTab({
    required this.bg,
    required this.surface,
    required this.onSurface,
    required this.onVariant,
    required this.primary,
    required this.secondary,
  });

  @override
  State<_MaintenanceOrdersTab> createState() => _MaintenanceOrdersTabState();
}

class _MaintenanceOrdersTabState extends State<_MaintenanceOrdersTab> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = ApiService.getMaintenanceOrders();
  }

  String _statusFr(String? s) {
    switch ((s ?? '').toUpperCase()) {
      case 'PENDING': return 'En attente';
      case 'IN_PROGRESS': return 'En cours';
      case 'COMPLETED': return 'Termine';
      default: return s ?? '---';
    }
  }

  Color _priorityColor(String? p) {
    switch ((p ?? '').toUpperCase()) {
      case 'CRITICAL': return const Color(0xFFFFB4AB);
      case 'HIGH': return widget.primary;
      case 'LOW': return widget.secondary;
      default: return widget.onVariant;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: widget.bg,
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFFFF6E00)));
          }
          final rows = snap.data ?? [];
          if (rows.isEmpty) return Center(child: Text('Aucun ordre.', style: GoogleFonts.inter(color: widget.onVariant)));
          return ListView.separated(
            padding: const EdgeInsets.all(24),
            itemCount: rows.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final r = rows[i];
              return Material(
                color: widget.surface,
                borderRadius: BorderRadius.circular(12),
                child: ListTile(
                  title: Text(r['machineId'] ?? '---', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: widget.onSurface)),
                  subtitle: Text(r['description'] ?? '---', style: GoogleFonts.inter(color: widget.onVariant, fontSize: 12)),
                  trailing: Text(_statusFr(r['status']), style: GoogleFonts.inter(color: _priorityColor(r['priority']), fontWeight: FontWeight.bold)),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _ConcepteursTab extends StatefulWidget {
  final Color bg;
  final Color surface;
  final Color onSurface;
  final Color onVariant;
  final Color primary;
  final Color secondary;
  final VoidCallback onRefresh;

  const _ConcepteursTab({
    required this.bg,
    required this.surface,
    required this.onSurface,
    required this.onVariant,
    required this.primary,
    required this.secondary,
    required this.onRefresh,
  });

  @override
  State<_ConcepteursTab> createState() => _ConcepteursTabState();
}

class _ConcepteursTabState extends State<_ConcepteursTab> {
  late Future<List<Map<String, dynamic>>> _future;
  @override
  void initState() {
    super.initState();
    _future = ApiService.getConcepteurs();
  }
  @override
  Widget build(BuildContext context) {
    return Container(
      color: widget.bg,
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          final rows = snap.data ?? [];
          return ListView.builder(
            itemCount: rows.length,
            itemBuilder: (context, i) => ListTile(
              title: Text(rows[i]['username'] ?? '---', style: GoogleFonts.inter(color: widget.onSurface)),
              subtitle: Text(rows[i]['email'] ?? '---', style: GoogleFonts.inter(color: widget.onVariant)),
            ),
          );
        },
      ),
    );
  }
}

class _MaintenancePersonnelTab extends StatefulWidget {
  final Color bg;
  final Color surface;
  final Color onSurface;
  final Color onVariant;
  final Color primary;
  final Color secondary;

  const _MaintenancePersonnelTab({
    required this.bg,
    required this.surface,
    required this.onSurface,
    required this.onVariant,
    required this.primary,
    required this.secondary,
  });

  @override
  State<_MaintenancePersonnelTab> createState() => _MaintenancePersonnelTabState();
}

class _MaintenancePersonnelTabState extends State<_MaintenancePersonnelTab> {
  late Future<List<Map<String, dynamic>>> _future;
  @override
  void initState() {
    super.initState();
    _future = ApiService.getMaintenanceAgents();
  }
  @override
  Widget build(BuildContext context) {
    return Container(
      color: widget.bg,
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          final rows = snap.data ?? [];
          return ListView.builder(
            itemCount: rows.length,
            itemBuilder: (context, i) => ListTile(
              title: Text('${rows[i]['firstName']} ${rows[i]['lastName']}', style: GoogleFonts.inter(color: widget.onSurface)),
              subtitle: Text(rows[i]['email'] ?? '---', style: GoogleFonts.inter(color: widget.onVariant)),
            ),
          );
        },
      ),
    );
  }
}

class _DiagnosticGuidedTab extends StatefulWidget {
  final Color bg;
  final Color surface;
  final Color onSurface;
  final Color onVariant;
  final Color primary;
  final Color secondary;
  final String? initialInterventionId;

  const _DiagnosticGuidedTab({
    required this.bg,
    required this.surface,
    required this.onSurface,
    required this.onVariant,
    required this.primary,
    required this.secondary,
    this.initialInterventionId,
  });

  @override
  State<_DiagnosticGuidedTab> createState() => _DiagnosticGuidedTabState();
}

class _DiagnosticGuidedTabState extends State<_DiagnosticGuidedTab> {
  late Future<List<Map<String, dynamic>>> _future;
  final _messageCtrl = TextEditingController();
  final _clientMsgCtrl = TextEditingController();
  Map<String, dynamic>? _selected;
  Map<String, dynamic>? _machineData;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _future = ApiService.getDiagnosticInterventions();
    _reload(keepId: widget.initialInterventionId);
    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (mounted) {
        final id = (_selected?['id'] ?? '').toString();
        _reload(keepId: id);
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _messageCtrl.dispose();
    _clientMsgCtrl.dispose();
    super.dispose();
  }

  Future<void> _reload({String? keepId}) async {
    setState(() => _future = ApiService.getDiagnosticInterventions());
    final rows = await _future;
    if (!mounted) return;
    final found = rows.where((r) => (r['id'] ?? '').toString() == keepId).toList();
    final newSelected = found.isNotEmpty ? found.first : (rows.isNotEmpty ? rows.first : null);
    if (newSelected != null && (newSelected['id'] != (_selected?['id']))) {
       _loadMachineData(newSelected['machineId']);
    }
    setState(() => _selected = newSelected);
  }

  Future<void> _loadMachineData(String? machineId) async {
    if (machineId == null || machineId.isEmpty) return;
    try {
      final data = await ApiService.getLatestTelemetry(machineId);
      if (mounted) setState(() => _machineData = data);
    } catch (e) {
      debugPrint('Error loading machine data for diag: $e');
    }
  }

  Future<void> _sendMessage() async {
    final id = (_selected?['id'] ?? '').toString();
    final text = _messageCtrl.text.trim();
    if (id.isEmpty || text.isEmpty) return;
    try {
      await ApiService.addDiagnosticMessage(id, text, authorName: 'Maintenance');
      _messageCtrl.clear();
      await _reload(keepId: id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Message refusÃ©: $e')));
    }
  }

  Future<void> _finish() async {
    final id = (_selected?['id'] ?? '').toString();
    if (id.isEmpty) return;
    await ApiService.setDiagnosticStatus(id, 'DONE');
    await _reload(keepId: id);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: widget.bg,
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting && _selected == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final current = _selected;
          if (current == null) return Center(child: Text('Aucune intervention.', style: GoogleFonts.inter(color: widget.onVariant)));
          final messages = ((current['messages'] as List?) ?? const []).cast<dynamic>();
          final machineId = (current['machineId'] ?? '').toString();
          return Row(
            children: [
              _buildTelemetrySidebar(machineId),
              Expanded(flex: 4, child: _buildTechnicalChannel(messages)),
              Expanded(flex: 4, child: _buildClientChannel(current)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTelemetrySidebar(String machineId) {
    final m = _machineData;
    return Container(
      width: 220,
      decoration: BoxDecoration(color: const Color(0xFF0A0A1F), border: Border(right: BorderSide(color: Colors.white.withOpacity(0.05)))),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('MOTOR_TELEMETRY', style: GoogleFonts.spaceGrotesk(fontSize: 10, color: widget.primary, fontWeight: FontWeight.bold)),
          Text('UNIT_$machineId', style: GoogleFonts.inter(fontSize: 12, color: widget.onSurface)),
          const SizedBox(height: 24),
          _telemetryItem('THERMAL', '${m?['temperature'] ?? '---'}Â°C', 'CRITICAL', true),
          _telemetryItem('PRESSURE', '${m?['pressure'] ?? '---'} BAR', 'NOMINAL', false),
          _telemetryItem('POWER', '${m?['power'] ?? '---'} kW', 'LOAD: 72%', false),
          _telemetryItem('VIBRATION', '${m?['vibration'] ?? '---'} mm/s', 'HIGH', false),
          _telemetryItem('PRESENCE', m?['presence'] == 1 ? 'DETECTED' : 'NOT DETECTED', '', false),
          _telemetryItem('MAGNETIC', '${m?['magnetic'] ?? '---'} mT', '', false),
          const Spacer(),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(gradient: LinearGradient(colors: [widget.primary, const Color(0xFFFF9E40)]), borderRadius: BorderRadius.circular(4)),
            child: Text('SYSTEM_OVERRIDE', textAlign: TextAlign.center, style: GoogleFonts.spaceGrotesk(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black)),
          ),
        ],
      ),
    );
  }

  Widget _telemetryItem(String label, String value, String status, bool critical) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: GoogleFonts.spaceGrotesk(fontSize: 9, color: widget.onVariant.withOpacity(0.6), fontWeight: FontWeight.bold)),
              if (status.isNotEmpty)
                Text(status,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 9,
                      color: critical ? const Color(0xFFFFB4AB) : widget.secondary,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    )),
            ],
          ),
          const SizedBox(height: 6),
          Text(value, style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w900, color: widget.onSurface)),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: critical ? 0.9 : 0.4,
              backgroundColor: Colors.white.withOpacity(0.05),
              color: critical ? const Color(0xFFFFB4AB).withOpacity(0.5) : widget.secondary.withOpacity(0.3),
              minHeight: 2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTechnicalChannel(List<dynamic> messages) {
    return Container(
      color: const Color(0xFF12122A),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05)))),
            child: Row(
              children: [
                const Icon(Icons.engineering_outlined, color: Color(0xFFFF9E40), size: 20),
                const SizedBox(width: 12),
                Text('CANAL TECHNIQUE', style: GoogleFonts.spaceGrotesk(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
                const Spacer(),
                Text('INTERNE: AHMED (FIELD)', style: GoogleFonts.spaceGrotesk(fontSize: 9, color: Colors.green)),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(20),
              itemCount: messages.length,
              itemBuilder: (ctx, i) {
                final m = messages[i];
                final isMe = m['authorName'] == 'Maintenance';
                return _chatBubble(m['authorName'] ?? 'Tech', m['content'] ?? '', isMe);
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(child: TextField(controller: _messageCtrl, style: GoogleFonts.inter(color: Colors.white, fontSize: 13), decoration: InputDecoration(hintText: 'Message...', filled: true, fillColor: Colors.white.withOpacity(0.03)))),
                const SizedBox(width: 12),
                IconButton(onPressed: _sendMessage, icon: const Icon(Icons.send, color: Colors.white)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chatBubble(String author, String text, bool isMe) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Text(author.toUpperCase(), style: GoogleFonts.spaceGrotesk(fontSize: 9, color: Colors.white.withOpacity(0.4))),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: isMe ? widget.primary.withOpacity(0.1) : Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(4)),
            child: Text(text, style: GoogleFonts.inter(color: Colors.white.withOpacity(0.9), fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _buildClientChannel(Map<String, dynamic> current) {
    return Container(
      color: const Color(0xFF0D0D25),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05)))),
            child: Text('CANAL CLIENT', style: GoogleFonts.spaceGrotesk(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _statusStep('DIAGNOSTIC', Icons.search, true, false),
                _statusStep('INTERVENTION', Icons.bolt, false, false),
                _statusStep('VALIDATION', Icons.list_alt, false, false),
                _statusStep('FIN', Icons.check_circle_outline, false, true),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white10),
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history, color: Colors.white.withOpacity(0.1), size: 48),
                  const SizedBox(height: 16),
                  Text('HISTORIQUE CLIENT VIDE', style: GoogleFonts.spaceGrotesk(fontSize: 11, color: Colors.white.withOpacity(0.7), fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('Aucun evenement n\'a ete enregistre pour\ncette session.', textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 10, color: Colors.white.withOpacity(0.3))),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: const Color(0xFF0A0A1F).withOpacity(0.5), border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05)))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ENVOYER UNE MISE A JOUR AU CLIENT', style: GoogleFonts.spaceGrotesk(fontSize: 9, color: widget.secondary, fontWeight: FontWeight.bold, letterSpacing: 1)),
                const SizedBox(height: 12),
                TextField(
                  controller: _clientMsgCtrl,
                  maxLines: 3,
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 12),
                  decoration: InputDecoration(
                    hintText: 'Informez le client de l\'avancee des travaux...',
                    hintStyle: GoogleFonts.inter(color: Colors.white.withOpacity(0.2), fontSize: 12),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.03),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: SizedBox(
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _finish,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE57373).withOpacity(0.9),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                            elevation: 0,
                          ),
                          child: Text('TERMINER LA PANNE &\nVALIDER', textAlign: TextAlign.center, style: GoogleFonts.spaceGrotesk(fontSize: 10, fontWeight: FontWeight.w900, height: 1.2)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SizedBox(
                        height: 52,
                        child: ElevatedButton.icon(
                          onPressed: () {},
                          icon: const Icon(Icons.send, size: 16),
                          label: const Text('ENVOYER'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00ACC1),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                            elevation: 0,
                            textStyle: GoogleFonts.spaceGrotesk(fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SizedBox(
                        height: 52,
                        child: OutlinedButton(
                          onPressed: () {},
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: Colors.white.withOpacity(0.1)),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                          ),
                          child: Text('ANNULER', style: GoogleFonts.spaceGrotesk(fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusStep(String label, IconData icon, bool active, bool last) {
    return Row(
      children: [
        Column(
          children: [
            Icon(icon, size: 20, color: active ? Colors.white.withOpacity(0.4) : Colors.white.withOpacity(0.1)),
            const SizedBox(height: 12),
            Container(width: 4, height: 4, decoration: BoxDecoration(color: active ? widget.secondary : Colors.white.withOpacity(0.1), shape: BoxShape.circle)),
            const SizedBox(height: 8),
            Text(label, style: GoogleFonts.spaceGrotesk(fontSize: 7, color: active ? Colors.white.withOpacity(0.5) : Colors.white.withOpacity(0.2), fontWeight: FontWeight.bold, letterSpacing: 0.5)),
          ],
        ),
        if (!last) Container(width: 30, height: 1, color: Colors.white.withOpacity(0.05), margin: const EdgeInsets.only(bottom: 24)),
      ],
    );
  }
}
