import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:intl/intl.dart';
import 'services/api_service.dart';

class KineticObservatoryPage extends StatefulWidget {
  final String machineId;
  final String interventionId;

  const KineticObservatoryPage({
    super.key,
    required this.machineId,
    required this.interventionId,
  });

  @override
  State<KineticObservatoryPage> createState() => _KineticObservatoryPageState();
}

class _KineticObservatoryPageState extends State<KineticObservatoryPage> {
  // Styles & Colors
  static const _bg = Color(0xFF0F0F17);
  static const _panel = Color(0xFF161621);
  static const _accent = Color(0xFFFF8C00); // Orange
  static const _cyan = Color(0xFF00CED1);
  static const _red = Color(0xFFFF4D4D);
  static const _green = Color(0xFF4CAF50);
  static const _text = Colors.white;
  static const _muted = Color(0xFF8A8A9E);

  // Data
  Map<String, dynamic>? _intervention;
  Map<String, dynamic>? _machine;
  Map<String, dynamic> _telemetry = {};
  List<Map<String, dynamic>> _messages = [];
  List<Map<String, dynamic>> _coordinationNotes = [];
  bool _loading = true;

  // Controllers
  final TextEditingController _techController = TextEditingController();
  final TextEditingController _coordController = TextEditingController();
  final ScrollController _techScroll = ScrollController();
  final ScrollController _coordScroll = ScrollController();

  // Socket
  IO.Socket? _socket;

  @override
  void initState() {
    super.initState();
    _loadData();
    _initSocket();
  }

  @override
  void dispose() {
    _socket?.disconnect();
    _techController.dispose();
    _coordController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final interventions = await ApiService.getDiagnosticInterventions();
      final inter = interventions.firstWhere((i) => i['id'] == widget.interventionId);
      final mach = await ApiService.getMachineInfo(widget.machineId);

      setState(() {
        _intervention = inter;
        _machine = mach;
        _messages = List<Map<String, dynamic>>.from(inter['messages'] ?? []);
        _coordinationNotes = List<Map<String, dynamic>>.from(inter['coordinationNotes'] ?? []);
        _loading = false;
      });

      // Load latest telemetry
      final tel = await ApiService.getLatestTelemetry(widget.machineId);
      if (tel != null) {
        setState(() => _telemetry = tel);
      }
    } catch (e) {
      debugPrint('Error loading observatory data: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  void _initSocket() {
    _socket = IO.io(ApiService.socketBaseUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': true,
    });

    _socket!.onConnect((_) => debugPrint('Observatory connected to socket'));

    _socket!.on('nouvelle_prediction', (data) {
      if (data['machineId'] == widget.machineId) {
        if (mounted) setState(() => _telemetry = data);
      }
    });

    _socket!.on('diagnostic_message', (data) {
      if (data['interventionId'] == widget.interventionId) {
        if (mounted) {
          setState(() {
            _messages.add(Map<String, dynamic>.from(data['message']));
          });
          _scrollToBottom(_techScroll);
        }
      }
    });

    _socket!.on('diagnostic_coordination', (data) {
      if (data['interventionId'] == widget.interventionId) {
        if (mounted) {
          setState(() {
            _coordinationNotes.add(Map<String, dynamic>.from(data['note']));
          });
          _scrollToBottom(_coordScroll);
        }
      }
    });
  }

  void _scrollToBottom(ScrollController sc) {
    Timer(const Duration(milliseconds: 300), () {
      if (sc.hasClients) {
        sc.animateTo(sc.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _sendTechMessage() async {
    final text = _techController.text.trim();
    if (text.isEmpty) return;
    try {
      await ApiService.addDiagnosticMessage(widget.interventionId, text);
      _techController.clear();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
    }
  }

  Future<void> _sendCoordNote() async {
    final text = _coordController.text.trim();
    if (text.isEmpty) return;
    try {
      await ApiService.addCoordinationNote(widget.interventionId, text);
      _coordController.clear();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
    }
  }

  Future<void> _finishIntervention() async {
    try {
      await ApiService.setDiagnosticStatus(widget.interventionId, 'DONE');
      if (mounted) Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(backgroundColor: _bg, body: Center(child: CircularProgressIndicator(color: _accent)));
    }

    return Scaffold(
      backgroundColor: _bg,
      appBar: _buildAppBar(),
      body: Row(
        children: [
          _buildTelemetrySidebar(),
          const VerticalDivider(width: 1, color: Colors.white10),
          Expanded(flex: 3, child: _buildTechnicalCanal()),
          const VerticalDivider(width: 1, color: Colors.white10),
          Expanded(flex: 2, child: _buildInternalCoordination()),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: _panel,
      elevation: 0,
      leading: IconButton(icon: const Icon(Icons.arrow_back, color: _text), onPressed: () => Navigator.pop(context)),
      title: Row(
        children: [
          Text('KINETIC_', style: GoogleFonts.spaceGrotesk(color: _text, fontWeight: FontWeight.bold, fontSize: 18)),
          Text('OBSERVATORY', style: GoogleFonts.spaceGrotesk(color: _accent, fontWeight: FontWeight.bold, fontSize: 18)),
        ],
      ),
      actions: [
        _appBarLink('MAINTENANCE HUB'),
        _appBarLink('ARCHIVE'),
        _appBarLink('RAPPORTS'),
        const SizedBox(width: 20),
        const Icon(Icons.notifications_none, color: _muted),
        const SizedBox(width: 16),
        const Icon(Icons.settings_outlined, color: _muted),
        const SizedBox(width: 16),
        const CircleAvatar(radius: 14, backgroundColor: _accent, child: Icon(Icons.person, size: 16, color: Colors.black)),
        const SizedBox(width: 20),
      ],
    );
  }

  Widget _appBarLink(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Center(
        child: Text(text, style: GoogleFonts.inter(color: _muted, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
      ),
    );
  }

  Widget _buildTelemetrySidebar() {
    final metrics = _telemetry['metrics'] ?? {};
    final thermal = metrics['thermal'] ?? _telemetry['temperature'] ?? 0.0;
    final pressure = metrics['pressure'] ?? 0.0;
    final power = metrics['power'] ?? 0.0;
    final vibration = metrics['vibration'] ?? 0.0;
    final magnetic = metrics['magnetic'] ?? 0.0;
    final presence = (metrics['presence'] ?? 0) == 1;

    return Container(
      width: 260,
      color: _bg,
      padding: const EdgeInsets.all(24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('MOTOR_TELEMETRY', style: GoogleFonts.spaceGrotesk(color: _accent, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.circle, color: _green, size: 8),
                const SizedBox(width: 8),
                Text(widget.machineId, style: GoogleFonts.inter(color: _text, fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 40),
            _telemetryItem('THERMAL', '$thermal°C', 'CRITICAL', _red, thermal / 100),
            _telemetryItem('PRESSURE', '$pressure BAR', 'NOMINAL', _cyan, pressure / 10),
            _telemetryItem('POWER', '${power.toStringAsFixed(1)} kW', 'LOAD: 72%', _muted, 0.72),
            _telemetryItem('VIBRATION', '${vibration.toStringAsFixed(1)} mm/s', 'HIGH', _accent, vibration / 20),
            
            const SizedBox(height: 24),
            _telemetryLabel('PRESENCE'),
            Row(
              children: [
                Icon(Icons.check_circle_outline, color: presence ? _green : _muted, size: 16),
                const SizedBox(width: 8),
                Text(presence ? 'DETECTED' : 'NOT DETECTED', style: GoogleFonts.inter(color: presence ? _text : _muted, fontSize: 12, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 24),
            _telemetryLabel('MAGNETIC'),
            Text('$magnetic mT', style: GoogleFonts.inter(color: _text, fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            _telemetryLabel('INFRARED'),
            Text('NORMAL', style: GoogleFonts.inter(color: _text, fontSize: 14, fontWeight: FontWeight.bold)),
            
            const SizedBox(height: 60),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton(
                onPressed: () {},
                style: ElevatedButton.styleFrom(backgroundColor: _accent.withOpacity(0.2), foregroundColor: _accent, elevation: 0),
                child: Text('SYSTEM_OVERRIDE', style: GoogleFonts.spaceGrotesk(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _telemetryLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(label, style: GoogleFonts.spaceGrotesk(color: _muted, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1)),
    );
  }

  Widget _telemetryItem(String label, String value, String status, Color statusColor, double progress) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: GoogleFonts.spaceGrotesk(color: _muted, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1)),
              Text(status, style: GoogleFonts.spaceGrotesk(color: statusColor, fontSize: 9, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          Text(value, style: GoogleFonts.inter(color: _text, fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: progress.clamp(0.0, 1.0),
            backgroundColor: Colors.white.withOpacity(0.05),
            color: statusColor.withOpacity(0.6),
            minHeight: 2,
          ),
        ],
      ),
    );
  }

  Widget _buildTechnicalCanal() {
    return Container(
      color: _bg,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05)))),
            child: Row(
              children: [
                const Icon(Icons.engineering_outlined, color: _muted, size: 20),
                const SizedBox(width: 12),
                Text('CANAL TECHNIQUE', style: GoogleFonts.spaceGrotesk(color: _text, fontWeight: FontWeight.bold, letterSpacing: 1)),
                const Spacer(),
                const Icon(Icons.circle, color: _green, size: 8),
                const SizedBox(width: 8),
                Text('INTERNE: AHMED (FIELD)', style: GoogleFonts.inter(color: _muted, fontSize: 9, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          Expanded(
            child: _messages.isEmpty
                ? _buildEmptyState('EN ATTENTE DE COMMUNICATIONS TECHNIQUES')
                : ListView.builder(
                    controller: _techScroll,
                    padding: const EdgeInsets.all(24),
                    itemCount: _messages.length,
                    itemBuilder: (ctx, idx) => _buildMessageBubble(_messages[idx]),
                  ),
          ),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05)))),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _techController,
                    style: GoogleFonts.inter(color: _text, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Entrez une commande ou un message technique...',
                      hintStyle: GoogleFonts.inter(color: _muted, fontSize: 13),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.03),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    onSubmitted: (_) => _sendTechMessage(),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  onPressed: _sendTechMessage,
                  icon: const Icon(Icons.send, color: _accent),
                  style: IconButton.styleFrom(backgroundColor: _accent.withOpacity(0.1)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInternalCoordination() {
    return Container(
      color: _bg,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05)))),
            child: Row(
              children: [
                const Icon(Icons.group_outlined, color: _muted, size: 20),
                const SizedBox(width: 12),
                Text('COORDINATION INTERNE', style: GoogleFonts.spaceGrotesk(color: _text, fontWeight: FontWeight.bold, letterSpacing: 1)),
                const Spacer(),
                Text('STATUS: CANAL 2 ACTIF', style: GoogleFonts.inter(color: _muted, fontSize: 9, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          Expanded(
            child: _coordinationNotes.isEmpty
                ? _buildEmptyState('ATTENTE DE COORDINATION TECHNIQUE SECONDAIRE', icon: Icons.hub_outlined)
                : ListView.builder(
                    controller: _coordScroll,
                    padding: const EdgeInsets.all(24),
                    itemCount: _coordinationNotes.length,
                    itemBuilder: (ctx, idx) => _buildMessageBubble(_coordinationNotes[idx], isCoord: true),
                  ),
          ),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: _panel.withOpacity(0.5), border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05)))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ENVOYER UNE NOTE DE COORDINATION', style: GoogleFonts.spaceGrotesk(color: _cyan, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                const SizedBox(height: 12),
                TextField(
                  controller: _coordController,
                  maxLines: 3,
                  style: GoogleFonts.inter(color: _text, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Note pour l\'équipe technique interne...',
                    hintStyle: GoogleFonts.inter(color: _muted, fontSize: 13),
                    filled: true,
                    fillColor: Colors.black.withOpacity(0.2),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.white10)),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: SizedBox(
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _finishIntervention,
                          style: ElevatedButton.styleFrom(backgroundColor: _red.withOpacity(0.8), foregroundColor: _text, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                          child: Text('TERMINER LA PANNE &\nVALIDER', textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SizedBox(
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _sendCoordNote,
                          style: ElevatedButton.styleFrom(backgroundColor: _cyan, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                          child: Text('ENVOYER', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SizedBox(
                        height: 52,
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(foregroundColor: _text, side: const BorderSide(color: Colors.white24), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                          child: Text('ANNULER', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold)),
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

  Widget _buildEmptyState(String text, {IconData icon = Icons.chat_bubble_outline}) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.03), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: Colors.white12, size: 32),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(text, textAlign: TextAlign.center, style: GoogleFonts.spaceGrotesk(color: _muted, fontSize: 10, letterSpacing: 1, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> msg, {bool isCoord = false}) {
    final isMe = msg['authorRole'] == ApiService.savedUserRole;
    final time = msg['createdAt'] != null ? DateFormat('HH:mm').format(DateTime.parse(msg['createdAt'])) : '--:--';
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(msg['authorName'] ?? 'Inconnu', style: GoogleFonts.inter(color: isCoord ? _cyan : _accent, fontSize: 10, fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              Text(time, style: GoogleFonts.inter(color: _muted, fontSize: 9)),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: isMe ? (isCoord ? _cyan.withOpacity(0.1) : _accent.withOpacity(0.1)) : _panel,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isMe ? (isCoord ? _cyan : _accent).withOpacity(0.2) : Colors.white.withOpacity(0.05)),
            ),
            child: Text(msg['content'] ?? '', style: GoogleFonts.inter(color: _text, fontSize: 13, height: 1.4)),
          ),
        ],
      ),
    );
  }
}
