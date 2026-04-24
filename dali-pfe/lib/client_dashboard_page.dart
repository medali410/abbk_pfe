import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:ui';
import 'dart:convert';
import 'login_page.dart';
import 'machine_detail_ai_page.dart';
import 'ai_analysis_page.dart';
import 'services/api_service.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'dart:async';

// ─────────────────────────────────────────────────────────────
// ClientDashboardPage — shown after a client logs in
// Mirrors the HTML "Predictive Cloud - Liste des Machines" page
// ─────────────────────────────────────────────────────────────
class ClientDashboardPage extends StatefulWidget {
  final String? clientName;
  final String? clientId;
  final Map<String, dynamic>? clientData;

  const ClientDashboardPage({
    super.key, 
    this.clientName, 
    this.clientId,
    this.clientData,
  });

  @override
  State<ClientDashboardPage> createState() => _ClientDashboardPageState();
}

class _ClientDashboardPageState extends State<ClientDashboardPage>
    with SingleTickerProviderStateMixin {
  // Sidebar nav index: 0=Dashboard, 1=Machines, 2=IA, 3=Team, 4=Docs
  int _navIndex = 1;
  /// Machine choisie pour l’onglet Analyse IA (null = liste de sélection).
  Map<String, dynamic>? _iaSelectedMachine;
  /// Machine choisie pour Documents techniques.
  Map<String, dynamic>? _docSelectedMachine;

  // Shimmer animation controller
  late final AnimationController _shimmerController;

  // pulse animation value
  late final Animation<double> _pulseAnimation;

  Future<List<Map<String, dynamic>>>? _machinesFuture;
  Future<List<Map<String, dynamic>>>? _techniciansFuture;
  final Map<String, List<Map<String, dynamic>>> _chatMessages = {};
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  String? _activeCallRoomId;
  bool _isCallUiOpen = false;
  int _techCount = 0;
  bool _isLoadingStats = true;

  // Real-time telemetry
  late IO.Socket _socket;
  final Map<String, double> _realtimeTemps = {};
  final Map<String, double> _realtimeVibrations = {};
  final Map<String, double> _realtimeFrictions = {};
  final Map<String, double> _realtimePressures = {};
  Timer? _controlTicker;

  double _toDouble(dynamic value, [double fallback = 0.0]) {
    if (value == null) return fallback;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? fallback;
    return fallback;
  }

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _shimmerController, curve: Curves.easeInOut),
    );

    _refreshMachines();
    _initSocket();
    _initRenderers();
    _controlTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
  }

  void _refreshMachines() async {
    final cId = widget.clientId ?? widget.clientData?['clientId'] ?? widget.clientData?['id'] ?? '';
    if (cId.isNotEmpty) {
      setState(() {
        _machinesFuture = ApiService.getMachinesForClient(cId);
        _techniciansFuture = ApiService.getTechniciansForClient(cId);
        _isLoadingStats = true;
      });
      
      try {
        final clientTechs = await ApiService.getTechniciansForClient(cId);
        if (mounted) {
          setState(() {
            _techCount = clientTechs.length;
            _isLoadingStats = false;
          });
        }
      } catch (e) {
        if (mounted) setState(() => _isLoadingStats = false);
      }
    }
  }

  @override
  void dispose() {
    _controlTicker?.cancel();
    _shimmerController.dispose();
    _endCallLocally();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    _socket.dispose();
    super.dispose();
  }

  String _formatElapsed(Duration d) {
    final total = d.inSeconds < 0 ? 0 : d.inSeconds;
    final hh = (total ~/ 3600).toString().padLeft(2, '0');
    final mm = ((total % 3600) ~/ 60).toString().padLeft(2, '0');
    final ss = (total % 60).toString().padLeft(2, '0');
    return '$hh:$mm:$ss';
  }

  void _initSocket() {
    debugPrint('🔌 ClientDashboard: Initialisation Socket.io');
    _socket = IO.io(ApiService.socketBaseUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': true,
    });

    _socket.onConnect((_) => debugPrint('✅ ClientDashboard: Connecté au serveur Socket.io'));
    _socket.onDisconnect((_) => debugPrint('❌ ClientDashboard: Déconnecté du serveur'));

    _socket.on('nouvelle_prediction', (raw) {
      try {
        final dynamic decoded = raw is String ? jsonDecode(raw) : raw;
        if (decoded is! Map) return;
        final data = Map<String, dynamic>.from(decoded as Map);
        final String mId = (data['machineId'] ?? data['id'] ?? '').toString();
        if (mId.isEmpty || !mounted) return;

        final metrics = data['metrics'] as Map<String, dynamic>?;
        final temp = _toDouble(data['temperature'] ?? metrics?['thermal'], 0.0);
        final vibration = _toDouble(data['vibration'] ?? metrics?['vibration'], 0.0);
        final friction = _toDouble(data['friction'] ?? metrics?['friction'], 0.0);
        final pressure = _toDouble(data['pressure'] ?? metrics?['pressure'], 0.0);

        setState(() {
          _realtimeTemps[mId] = temp;
          _realtimeVibrations[mId] = vibration;
          _realtimeFrictions[mId] = friction;
          _realtimePressures[mId] = pressure;
        });
      } catch (_) {
        // ignore malformed payloads
      }
    });

    _socket.on('chat_message', (data) {
      if (data is Map && mounted) {
        final roomId = (data['roomId'] ?? '').toString();
        if (roomId.isEmpty) return;
        setState(() {
          final list = _chatMessages.putIfAbsent(roomId, () => []);
          list.add(Map<String, dynamic>.from(data));
        });
      }
    });

    _socket.on('call_request', (data) {
      if (!mounted || data is! Map) return;
      final caller = (data['callerName'] ?? 'Technicien').toString();
      final roomId = (data['roomId'] ?? '').toString();
      if (roomId.isEmpty) return;
      _showIncomingCallDialog(roomId, caller);
    });

    _socket.on('call_response', (data) {
      if (!mounted || data is! Map) return;
      final accepted = data['accepted'] == true;
      final who = (data['responderName'] ?? 'Technicien').toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(accepted ? '$who a accepté l\'appel' : '$who a refusé l\'appel')),
      );
      if (accepted && _activeCallRoomId != null) {
        _createOffer(_activeCallRoomId!);
      }
    });

    _socket.on('webrtc_offer', (data) async {
      if (data is! Map) return;
      final roomId = (data['roomId'] ?? '').toString();
      final offer = data['offer'];
      if (roomId.isEmpty || offer == null) return;
      await _preparePeerConnection(roomId);
      await _peerConnection!.setRemoteDescription(
        RTCSessionDescription(offer['sdp'], offer['type']),
      );
      final answer = await _peerConnection!.createAnswer();
      await _peerConnection!.setLocalDescription(answer);
      _socket.emit('webrtc_answer', {
        'roomId': roomId,
        'answer': {'sdp': answer.sdp, 'type': answer.type},
        'from': 'client',
        'senderName': widget.clientName ?? 'Client',
      });
      _openCallUi(roomId);
    });

    _socket.on('webrtc_answer', (data) async {
      if (data is! Map) return;
      final answer = data['answer'];
      if (answer == null || _peerConnection == null) return;
      await _peerConnection!.setRemoteDescription(
        RTCSessionDescription(answer['sdp'], answer['type']),
      );
      if (_activeCallRoomId != null) _openCallUi(_activeCallRoomId!);
    });

    _socket.on('webrtc_ice_candidate', (data) async {
      if (data is! Map) return;
      final candidate = data['candidate'];
      if (candidate == null || _peerConnection == null) return;
      await _peerConnection!.addCandidate(
        RTCIceCandidate(
          candidate['candidate'],
          candidate['sdpMid'],
          candidate['sdpMLineIndex'],
        ),
      );
    });

    _socket.on('call_end', (_) {
      _endCallLocally();
      if (mounted && _isCallUiOpen) {
        Navigator.of(context, rootNavigator: true).pop();
        _isCallUiOpen = false;
      }
    });
  }

  // ── Colour tokens (mirror Tailwind config) ──
  static const _bg = Color(0xFF0F0F1E);
  static const _surfaceContainerLowest = Color(0xFF0B0B1A);
  static const _surfaceContainerLow = Color(0xFF161626);
  static const _surfaceContainer = Color(0xFF1D1D38);
  static const _surfaceContainerHigh = Color(0xFF272743);
  static const _surfaceContainerHighest = Color(0xFF32324E);
  static const _primary = Color(0xFFFF6E00);
  static const _primaryLight = Color(0xFFFFB692);
  static const _secondary = Color(0xFF75D1FF);
  static const _error = Color(0xFFFFB4AB);
  static const _onSurface = Color(0xFFE2DFFF);
  static const _onSurfaceVariant = Color(0xFFE2BFB0);
  static const _outlineVariant = Color(0xFF594136);
  static const _green = Color(0xFF66BB6A);

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final isDesktop = w > 992;

    return Scaffold(
      backgroundColor: _bg,
      body: Row(
        children: [
          // ── Sidebar ──
          if (isDesktop) _buildSidebar(),
          // ── Main area ──
          Expanded(
            child: Column(
              children: [
                _buildTopBar(isDesktop),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(32),
                    child: _buildNavMainContent(isDesktop),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),

    );
  }

  String _clientMachineId(Map<String, dynamic> m) =>
      (m['machineId'] ?? m['id'] ?? m['_id'] ?? '').toString();

  String _clientMachineName(Map<String, dynamic> m) =>
      (m['name'] ?? 'Machine').toString();

  Widget _buildNavMainContent(bool isDesktop) {
    if (_navIndex == 2) {
      if (_iaSelectedMachine == null) {
        return _buildMachinePickerCard(
          isDesktop: isDesktop,
          title: 'Choisir une machine',
          subtitle:
              "Sélectionnez l'équipement pour afficher l'analyse IA (graphiques, probabilité, recommandations).",
          onPick: (m) => setState(() => _iaSelectedMachine = m),
        );
      }
      final mid = _clientMachineId(_iaSelectedMachine!);
      final mname = _clientMachineName(_iaSelectedMachine!);
      final motor = (_iaSelectedMachine!['motorType'] ?? 'EL_M').toString();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSubpageHeader(
            title: 'Analyse IA',
            subtitle: '$mname · $mid',
            onBack: () => setState(() => _iaSelectedMachine = null),
          ),
          const SizedBox(height: 20),
          AiAnalysisView(
            machineId: mid,
            machineName: mname,
            motorType: motor,
          ),
        ],
      );
    }
    if (_navIndex == 3) {
      return _buildTeamSection();
    }
    if (_navIndex == 4) {
      if (_docSelectedMachine == null) {
        return _buildMachinePickerCard(
          isDesktop: isDesktop,
          title: 'Documents techniques',
          subtitle:
              "Choisissez une machine pour consulter sa fiche, l'historique télémétrique et les fiches associées.",
          onPick: (m) => setState(() => _docSelectedMachine = m),
        );
      }
      return _buildDocumentsTechnicalSection(isDesktop);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildAIHeader(),
        const SizedBox(height: 24),
        _buildKPIRow(isDesktop),
        const SizedBox(height: 32),
        _buildMachineListSection(isDesktop),
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _buildSubpageHeader({
    required String title,
    required String subtitle,
    required VoidCallback onBack,
  }) {
    return Row(
      children: [
        IconButton(
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back, color: _secondary),
          tooltip: 'Retour',
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: _onSurface,
                ),
              ),
              Text(
                subtitle,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 12,
                  color: _onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMachinePickerCard({
    required bool isDesktop,
    required String title,
    required String subtitle,
    required void Function(Map<String, dynamic> m) onPick,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.inter(
            fontSize: 28,
            fontWeight: FontWeight.w900,
            color: _onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: GoogleFonts.inter(
            fontSize: 14,
            color: _onSurfaceVariant,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 28),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _machinesFuture,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(48),
                  child: CircularProgressIndicator(),
                ),
              );
            }
            if (snap.hasError) {
              return Text(
                'Impossible de charger les machines.',
                style: GoogleFonts.inter(color: _error),
              );
            }
            final machines = snap.data ?? [];
            if (machines.isEmpty) return _buildEmptyState();
            return ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: machines.length,
              separatorBuilder: (_, __) => const SizedBox(height: 14),
              itemBuilder: (context, index) {
                final m = machines[index];
                final id = _clientMachineId(m);
                final name = _clientMachineName(m);
                return Material(
                  color: _surfaceContainerLow,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: _outlineVariant.withOpacity(0.12),
                    ),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => onPick(m),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 18,
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: _secondary.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.precision_manufacturing,
                              color: _secondary,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: GoogleFonts.inter(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: _onSurface,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  id,
                                  style: GoogleFonts.spaceGrotesk(
                                    fontSize: 11,
                                    color: _secondary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if ((m['location'] ?? '').toString().isNotEmpty)
                                  Text(
                                    m['location'].toString(),
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: _onSurfaceVariant,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right,
                            color: _onSurfaceVariant.withOpacity(0.6),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildDocumentsTechnicalSection(bool isDesktop) {
    final m = _docSelectedMachine!;
    final mid = _clientMachineId(m);
    final name = _clientMachineName(m);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSubpageHeader(
          title: 'Documents techniques',
          subtitle: '$name · $mid',
          onBack: () => setState(() => _docSelectedMachine = null),
        ),
        const SizedBox(height: 24),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: _surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _outlineVariant.withOpacity(0.12)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Fiche équipement',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: _secondary,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 12),
              _docInfoRow('Identifiant', mid),
              _docInfoRow('Nom', name),
              _docInfoRow('Type moteur', (m['motorType'] ?? '—').toString()),
              _docInfoRow('Statut', (m['status'] ?? '—').toString()),
              _docInfoRow('Emplacement', (m['location'] ?? '—').toString()),
              _docInfoRow('Puissance', (m['power'] ?? '—').toString()),
              _docInfoRow('Tension', (m['voltage'] ?? '—').toString()),
              _docInfoRow('Vitesse', (m['speed'] ?? '—').toString()),
              _docInfoRow('Installation', (m['installDate'] ?? '—').toString()),
            ],
          ),
        ),
        const SizedBox(height: 28),
        Text(
          'Historique télémétrie (MongoDB)',
          style: GoogleFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: _onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Derniers enregistrements pour cette machine (température, vibrations, etc.).',
          style: GoogleFonts.inter(fontSize: 12, color: _onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: ApiService.getTelemetryHistory(mid, limit: 30),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snap.hasError) {
              return Text(
                'Historique indisponible : ${snap.error}',
                style: GoogleFonts.inter(color: _onSurfaceVariant),
              );
            }
            final rows = snap.data ?? [];
            if (rows.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _surfaceContainer.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Aucune télémétrie enregistrée pour cette machine.',
                  style: GoogleFonts.inter(color: _onSurfaceVariant),
                ),
              );
            }
            return Container(
              decoration: BoxDecoration(
                color: _surfaceContainer,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white10),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: rows.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, color: Colors.white10),
                itemBuilder: (context, i) {
                  final r = rows[i];
                  final ts = (r['createdAt'] ?? r['updatedAt'] ?? '').toString();
                  final temp = (r['temperature'] ?? '—').toString();
                  final vib = (r['vibration'] ?? '—').toString();
                  final pow = (r['powerConsumption'] ?? '—').toString();
                  return ListTile(
                    dense: true,
                    title: Text(
                      ts,
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 11,
                        color: _secondary,
                      ),
                    ),
                    subtitle: Text(
                      'T° $temp  ·  Vib $vib  ·  P $pow',
                      style: GoogleFonts.inter(fontSize: 12, color: _onSurface),
                    ),
                  );
                },
              ),
            );
          },
        ),
        const SizedBox(height: 28),
        Text(
          'Fichiers & rapports (démonstration)',
          style: GoogleFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: _onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Liens fictifs — à remplacer par de vrais PDF lorsque le serveur les exposera.',
          style: GoogleFonts.inter(fontSize: 12, color: _onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        _docFileRow(
          'Fiche identité équipement — $name',
          'PDF · Synthèse technique et repères',
        ),
        _docFileRow(
          "Carnet d'entretien & historique interventions",
          'PDF · Consignes et jalons de maintenance',
        ),
        _docFileRow(
          'Schéma électrique / borne moteur',
          'PDF · Repères câblage et capteurs',
        ),
        _docFileRow(
          'Rapport vibratoire — baseline',
          'PDF · Signature FFT référence',
        ),
        const SizedBox(height: 48),
      ],
    );
  }

  Widget _docInfoRow(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              k,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 11,
                color: _onSurfaceVariant,
                letterSpacing: 0.5,
              ),
            ),
          ),
          Expanded(
            child: Text(
              v,
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: _onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _docFileRow(String title, String meta) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: _surfaceContainerHigh.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Démo : ajoutez des URLs de fichiers côté API pour activer le téléchargement.',
                  style: GoogleFonts.inter(),
                ),
              ),
            );
          },
          child: ListTile(
            leading:
                const Icon(Icons.picture_as_pdf, color: Color(0xFFFFB4AB)),
            title: Text(
              title,
              style: GoogleFonts.inter(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              meta,
              style: GoogleFonts.inter(fontSize: 12, color: _onSurfaceVariant),
            ),
            trailing: const Icon(Icons.download_outlined),
          ),
        ),
      ),
    );
  }

  // ══════════════════════════ SIDEBAR ════════════════════════════
  Widget _buildSidebar() {
    return Container(
      width: 256,
      color: _surfaceContainerLowest,
      child: Column(
        children: [
          // Brand
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.precision_manufacturing,
                      color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.clientName ?? 'Enterprise Corp',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: _onSurface,
                      ),
                    ),
                    Text(
                      'PREDICTIVE CLOUD',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 9,
                        color: _primary,
                        letterSpacing: 2.0,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Nav items
          _navItem(Icons.dashboard, 'Tableau de bord', 0),
          _navItem(Icons.precision_manufacturing, 'Mes Machines', 1),
          _navItem(Icons.auto_awesome, 'Analyse IA', 2),
          _navItem(Icons.groups, 'Équipe Assignée', 3),
          _navItem(Icons.description, 'Documents Techniques', 4),
          const Spacer(),
          // System version
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _surfaceContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SYSTÈME',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 9,
                      color: _onSurfaceVariant,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: _green,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'V.2.4.0 Stable',
                        style: GoogleFonts.spaceGrotesk(
                            fontSize: 12, color: _onSurface),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _navItem(IconData icon, String label, int index) {
    final active = _navIndex == index;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() {
          _navIndex = index;
          if (index == 2) _iaSelectedMachine = null;
          if (index == 4) _docSelectedMachine = null;
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          decoration: active
              ? BoxDecoration(
                  color: _surfaceContainerHigh.withOpacity(0.5),
                  border: const Border(
                    right: BorderSide(color: _primary, width: 2),
                  ),
                )
              : null,
          child: Row(
            children: [
              Icon(
                icon,
                color: active ? _primary : _onSurfaceVariant.withOpacity(0.7),
                size: 22,
              ),
              const SizedBox(width: 16),
              Text(
                label,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 13,
                  fontWeight:
                      active ? FontWeight.bold : FontWeight.normal,
                  color:
                      active ? _primary : _onSurfaceVariant.withOpacity(0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ══════════════════════════ TOP BAR ════════════════════════════
  Widget _buildTopBar(bool isDesktop) {
    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: _bg.withOpacity(0.8),
        border: Border(
          bottom: BorderSide(color: _outlineVariant.withOpacity(0.1)),
        ),
      ),
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                // Search
                Container(
                  width: 260,
                  height: 36,
                  decoration: BoxDecoration(
                    color: _surfaceContainerLow,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 12),
                      Icon(Icons.search,
                          color: _onSurfaceVariant.withOpacity(0.5), size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          style: GoogleFonts.inter(
                              fontSize: 13, color: _onSurface),
                          decoration: InputDecoration(
                            hintText: 'Rechercher une machine...',
                            hintStyle: GoogleFonts.inter(
                                fontSize: 13,
                                color: _onSurfaceVariant.withOpacity(0.5)),
                            border: InputBorder.none,
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                // Status
                AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (_, __) => Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _primaryLight.withOpacity(_pulseAnimation.value),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Site Status: Nominal',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 11,
                          color: _primaryLight,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                // Icons
                _iconBtn(Icons.notifications_outlined),
                const SizedBox(width: 8),
                _iconBtn(Icons.settings_outlined),
                const SizedBox(width: 16),
                Container(
                  width: 1,
                  height: 28,
                  color: _outlineVariant.withOpacity(0.2),
                ),
                const SizedBox(width: 16),
                // User info
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      widget.clientName ?? 'Enterprise Corp',
                      style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: _onSurface),
                    ),
                    Text(
                      'Site de ${widget.clientData?['location'] ?? 'Tunis'}',
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 10, color: _onSurfaceVariant),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: () => Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginPage()),
                  ),
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: _surfaceContainerHighest,
                    child: const Icon(Icons.person, size: 18, color: _onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _iconBtn(IconData icon) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {},
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(icon, color: _onSurfaceVariant, size: 22),
              if (icon == Icons.notifications_outlined)
                Positioned(
                  top: -2,
                  right: -2,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: _bg, width: 1.5),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ══════════════════════ AI PREDICTIVE HEADER ═══════════════════
  Widget _buildAIHeader() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 700;
        if (isWide) {
          return Row(
            children: [
              Expanded(flex: 2, child: _buildHealthCard()),
              const SizedBox(width: 24),
              Expanded(flex: 1, child: _buildMaintenanceCard()),
            ],
          );
        }
        return Column(children: [
          _buildHealthCard(),
          const SizedBox(height: 16),
          _buildMaintenanceCard(),
        ]);
      },
    );
  }

  Widget _buildHealthCard() {
    return AnimatedBuilder(
      animation: _shimmerController,
      builder: (_, child) {
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: _surfaceContainerLow,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _secondary.withOpacity(0.2)),
          ),
          child: child,
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: _secondary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.psychology, color: _secondary, size: 26),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Score de Santé Global (IA)',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: _onSurface,
                        ),
                      ),
                      Text(
                        'Basé sur 1.2M de points de données/heure',
                        style: GoogleFonts.spaceGrotesk(
                            fontSize: 11, color: _onSurfaceVariant),
                      ),
                    ],
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${(widget.clientData?['health'] ?? 100).toString()}%',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 40,
                      fontWeight: FontWeight.w900,
                      color: _secondary,
                    ),
                  ),
                  Text(
                    'OPTIMISÉ',
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 9,
                        color: _onSurfaceVariant,
                        letterSpacing: 1.5),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              const Icon(Icons.info_outline, color: _secondary, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: GoogleFonts.inter(fontSize: 13, color: _onSurface.withOpacity(0.8)),
                    children: [
                      TextSpan(
                        text:
                            'Le site de ${widget.clientData?['location'] ?? 'Tunis'} présente une stabilité supérieure à la moyenne régionale. Risque d\'arrêt critique : ',
                      ),
                      TextSpan(
                        text: 'Faible (${widget.clientData?['alerts'] ?? 0} Alertes)',
                        style: GoogleFonts.inter(
                            fontWeight: FontWeight.bold,
                            color: _green),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: (widget.clientData?['health']?.toDouble() ?? 100.0) / 100.0,
              minHeight: 8,
              backgroundColor: _surfaceContainer,
              valueColor: AlwaysStoppedAnimation<Color>(_secondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMaintenanceCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _primaryLight.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.event_repeat, color: _primaryLight, size: 16),
              const SizedBox(width: 8),
              Text(
                'MAINTENANCE PRÉDICTIVE',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 9,
                  color: _onSurfaceVariant,
                  letterSpacing: 2.0,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
              border: Border(left: BorderSide(color: _primaryLight, width: 4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Recommandation IA',
                  style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: _primaryLight),
                ),
                const SizedBox(height: 6),
                Text(
                  'Remplacement du roulement (PR-001) suggéré dans 15 jours.',
                  style: GoogleFonts.inter(fontSize: 13, color: _onSurface),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () {},
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: _primaryLight.withOpacity(0.3)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: Text(
                'PLANIFIER MAINTENANT',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: _primaryLight,
                  letterSpacing: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════ KPI ROW ═══════════════════════════
  Widget _buildKPIRow(bool isDesktop) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth > 700 ? 4 : 2;
        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: cols,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: cols == 4 ? 1.8 : 1.5,
          children: [
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _machinesFuture,
              builder: (context, snapshot) {
                final count = snapshot.hasData ? snapshot.data!.length : 0;
                return _kpiCard(Icons.precision_manufacturing, 'Total Machines', count.toString().padLeft(2, '0'),
                    _primary, const Color(0xFF161626));
              }
            ),
            _kpiCard(Icons.groups, 'Techniciens Connectés', _isLoadingStats ? '..' : _techCount.toString().padLeft(2, '0'), _secondary,
                const Color(0xFF161626)),
            _kpiCard(Icons.warning, 'Alertes Actives', '01', _error,
                const Color(0xFF161626)),
            _kpiCard(Icons.check_circle, 'Disponibilité Site', '100%', _green,
                const Color(0xFF161626)),
          ],
        );
      },
    );
  }

  Widget _kpiCard(IconData icon, String label, String value, Color accent,
      Color bg) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: bg,
        border: Border(bottom: BorderSide(color: accent, width: 2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: accent, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 9,
                    color: _onSurfaceVariant,
                    letterSpacing: 1.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            value,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 32,
              fontWeight: FontWeight.w900,
              color: _onSurface,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════ MACHINE LIST ════════════════════════



  // ══════════════════════ MACHINE LIST SECTION ═══════════════════
  Widget _buildMachineListSection(bool isDesktop) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ÉTAT DE LA FLOTTE',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    color: _secondary,
                    letterSpacing: 2.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Machines Connectées',
                  style: GoogleFonts.inter(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: _onSurface,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
            _actionBtn(Icons.refresh, _onSurfaceVariant, _refreshMachines),
          ],
        ),
        const SizedBox(height: 24),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _machinesFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: Padding(padding: EdgeInsets.symmetric(vertical: 40), child: CircularProgressIndicator(color: _secondary)));
            }
            if (snapshot.hasError) {
              return Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: _error.withOpacity(0.1), borderRadius: BorderRadius.circular(12)), child: Text('Erreur reseau: ${snapshot.error}', style: TextStyle(color: _error)));
            }
            final machines = snapshot.data ?? [];
            if (machines.isEmpty) {
              return _buildEmptyState();
            }

            return ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: machines.length,
              separatorBuilder: (_, __) => const SizedBox(height: 16),
              itemBuilder: (context, index) => _buildMachineDashboardItem(machines[index], isDesktop),
            );
          },
        ),
      ],
    );
  }

  Widget _buildTeamSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ÉQUIPE ASSIGNÉE',
          style: GoogleFonts.spaceGrotesk(
            fontSize: 9,
            fontWeight: FontWeight.w900,
            color: _secondary,
            letterSpacing: 2.5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Techniciens disponibles pour votre site',
          style: GoogleFonts.inter(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: _onSurface,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 20),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _techniciansFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: CircularProgressIndicator(color: _secondary),
                ),
              );
            }
            if (snapshot.hasError) {
              return Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: _error.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Erreur chargement équipe: ${snapshot.error}',
                  style: const TextStyle(color: _error),
                ),
              );
            }

            final techs = snapshot.data ?? [];
            if (techs.isEmpty) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _outlineVariant.withOpacity(0.2)),
                ),
                child: Text(
                  'Aucun technicien assigné à ce client pour le moment.',
                  style: GoogleFonts.inter(fontSize: 14, color: _onSurfaceVariant),
                ),
              );
            }

            return ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: techs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) {
                final t = techs[i];
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _outlineVariant.withOpacity(0.2)),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: _surfaceContainerHighest,
                        child: const Icon(Icons.engineering, color: _onSurfaceVariant),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              (t['name'] ?? 'Technicien').toString(),
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: _onSurface,
                              ),
                            ),
                            Text(
                              '${t['specialization'] ?? 'Support Machine'} • ${t['status'] ?? 'Disponible'}',
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 11,
                                color: _onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => _openMessageEquipePage(t),
                        icon: const Icon(Icons.message_outlined, size: 16),
                        label: const Text('Message'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: () => _startCall(t),
                        icon: const Icon(Icons.call_outlined, size: 16),
                        label: const Text('Appel'),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }

  Future<void> _openMessageEquipePage(Map<String, dynamic> technician) async {
    final techId = (technician['technicianId'] ?? technician['_id'] ?? 'tech').toString();
    final clientKey = (widget.clientId ?? widget.clientData?['clientId'] ?? widget.clientData?['id'] ?? 'client').toString();
    if (!mounted) return;
    Navigator.of(context).pushNamed(
      '/message-equipe',
      arguments: {
        'role': 'client',
        'companyId': clientKey,
        'clientId': clientKey,
        'technicianId': techId,
        'name': widget.clientName ?? 'Client',
      },
    );
  }

  void _startCall(Map<String, dynamic> technician) {
    final techId = (technician['technicianId'] ?? technician['_id'] ?? 'tech').toString();
    final clientKey = (widget.clientId ?? widget.clientData?['clientId'] ?? widget.clientData?['id'] ?? 'client').toString();
    final roomId = 'chat_${clientKey}_$techId';
    _socket.emit('join_chat_room', {'roomId': roomId});
    _socket.emit('call_request', {
      'roomId': roomId,
      'from': 'client',
      'callerName': widget.clientName ?? 'Client',
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Demande d\'appel envoyée à ${(technician['name'] ?? 'Technicien')}')),
    );
  }

  Future<void> _preparePeerConnection(String roomId) async {
    _activeCallRoomId = roomId;
    _localStream ??= await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': true,
    });
    _localRenderer.srcObject = _localStream;
    _peerConnection ??= await createPeerConnection({
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'}
      ]
    });
    for (final track in _localStream!.getTracks()) {
      await _peerConnection!.addTrack(track, _localStream!);
    }
    _peerConnection!.onTrack = (RTCTrackEvent e) {
      if (e.streams.isNotEmpty) {
        _remoteRenderer.srcObject = e.streams.first;
      }
    };
    _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
      if (_activeCallRoomId == null) return;
      _socket.emit('webrtc_ice_candidate', {
        'roomId': _activeCallRoomId,
        'candidate': {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        }
      });
    };
  }

  Future<void> _createOffer(String roomId) async {
    await _preparePeerConnection(roomId);
    final offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);
    _socket.emit('webrtc_offer', {
      'roomId': roomId,
      'offer': {'sdp': offer.sdp, 'type': offer.type},
      'from': 'client',
      'senderName': widget.clientName ?? 'Client',
    });
  }

  void _showIncomingCallDialog(String roomId, String caller) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Appel entrant', style: GoogleFonts.inter()),
        content: Text('$caller vous appelle. Accepter ?'),
        actions: [
          TextButton(
            onPressed: () {
              _socket.emit('call_response', {
                'roomId': roomId,
                'accepted': false,
                'responderName': widget.clientName ?? 'Client',
              });
              Navigator.pop(context);
            },
            child: const Text('Refuser'),
          ),
          ElevatedButton(
            onPressed: () async {
              _socket.emit('call_response', {
                'roomId': roomId,
                'accepted': true,
                'responderName': widget.clientName ?? 'Client',
              });
              Navigator.pop(context);
              await _preparePeerConnection(roomId);
            },
            child: const Text('Accepter'),
          ),
        ],
      ),
    );
  }

  void _openCallUi(String roomId) {
    if (_isCallUiOpen) return;
    _isCallUiOpen = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: _surfaceContainerLow,
        title: Text('Appel en cours', style: GoogleFonts.inter(color: _onSurface)),
        content: SizedBox(
          width: 640,
          height: 380,
          child: Column(
            children: [
              Expanded(child: RTCVideoView(_remoteRenderer)),
              const SizedBox(height: 8),
              SizedBox(height: 100, width: 160, child: RTCVideoView(_localRenderer, mirror: true)),
            ],
          ),
        ),
        actions: [
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              _socket.emit('call_end', {'roomId': roomId});
              _endCallLocally();
              Navigator.pop(context);
              _isCallUiOpen = false;
            },
            icon: const Icon(Icons.call_end),
            label: const Text('Raccrocher'),
          ),
        ],
      ),
    ).then((_) => _isCallUiOpen = false);
  }

  Future<void> _endCallLocally() async {
    _activeCallRoomId = null;
    await _peerConnection?.close();
    _peerConnection = null;
    for (final track in _localStream?.getTracks() ?? <MediaStreamTrack>[]) {
      await track.stop();
    }
    _localStream = null;
    _localRenderer.srcObject = null;
    _remoteRenderer.srcObject = null;
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(color: _surfaceContainerLow.withOpacity(0.5), borderRadius: BorderRadius.circular(24), border: Border.all(color: _outlineVariant.withOpacity(0.1))),
      child: Column(
        children: [
          Icon(Icons.precision_manufacturing_outlined, size: 48, color: _onSurfaceVariant.withOpacity(0.3)),
          const SizedBox(height: 24),
          Text('BIENVENUE', style: GoogleFonts.spaceGrotesk(fontSize: 10, fontWeight: FontWeight.bold, color: _secondary, letterSpacing: 2)),
          const SizedBox(height: 8),
          Text('Aucune machine n\'est encore assignée.', style: GoogleFonts.inter(fontSize: 16, color: _onSurface, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text('Le Super Admin doit enregistrer vos équipements pour activer la surveillance.', style: GoogleFonts.inter(fontSize: 13, color: _onSurfaceVariant), textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildMachineDashboardItem(Map<String, dynamic> m, bool isDesktop) {
    final isAlert = (m['alerts'] ?? 0) > 0;
    final machineRealtimeId = (m['machineId'] ?? m['id'] ?? m['_id'] ?? '').toString();
    final controlBy = (m['maintenanceControlBy'] ?? '').toString().trim();
    final controlActive = m['maintenanceControlActive'] == true;
    final controlStartedAt = DateTime.tryParse((m['maintenanceControlStartedAt'] ?? '').toString());
    final isUnderControl = controlActive && controlStartedAt != null;
    final elapsed = isUnderControl ? DateTime.now().difference(controlStartedAt!) : Duration.zero;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isAlert ? _error.withOpacity(0.3) : _outlineVariant.withOpacity(0.1)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: (isAlert ? _error : _green).withOpacity(0.1), borderRadius: BorderRadius.circular(14)), child: Icon(Icons.precision_manufacturing, color: isAlert ? _error : _green, size: 28)),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m['name'] ?? 'Machine', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: _onSurface)),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: _secondary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: _secondary.withOpacity(0.3)),
                          ),
                          child: SelectableText(
                            machineRealtimeId.isEmpty ? '??' : machineRealtimeId,
                            style: GoogleFonts.spaceGrotesk(fontSize: 10, fontWeight: FontWeight.w600, color: _secondary),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          m['motorType'] ?? m['type'] ?? 'Standard',
                          style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _onSurfaceVariant),
                        ),
                        if (_realtimeTemps.containsKey(machineRealtimeId)) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: _primary.withOpacity(0.2), borderRadius: BorderRadius.circular(4)),
                            child: Text(
                              '${_realtimeTemps[machineRealtimeId]!.toStringAsFixed(1)}°C',
                              style: GoogleFonts.spaceGrotesk(fontSize: 10, fontWeight: FontWeight.bold, color: _primary),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (_realtimeVibrations.containsKey(machineRealtimeId) ||
                        _realtimeFrictions.containsKey(machineRealtimeId) ||
                        _realtimePressures.containsKey(machineRealtimeId)) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Vib: ${(_realtimeVibrations[machineRealtimeId] ?? 0).toStringAsFixed(1)} mm/s  •  Fric: ${(_realtimeFrictions[machineRealtimeId] ?? 0).toStringAsFixed(2)}  •  Pres: ${(_realtimePressures[machineRealtimeId] ?? 0).toStringAsFixed(1)} bar',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 10,
                          color: _secondary.withOpacity(0.9),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              _scoreBox('ALERTS', '${m['alerts'] ?? 0}', isAlert ? _error : _green),
              const SizedBox(width: 12),
              _actionBtn(Icons.arrow_forward, _secondary, () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => MachineDetailAiPage(
                    machineId: machineRealtimeId,
                    machineName: m['name']?.toString(),
                    viewerRole: 'client',
                    viewerName: (widget.clientName ?? 'Client').toString(),
                  ),
                ),
              )),
            ],
          ),
          if (isAlert) ...[
            const SizedBox(height: 16),
            _buildDiagnosticBanner(),
          ],
          if (isUnderControl) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _secondary.withOpacity(0.09),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _secondary.withOpacity(0.35)),
              ),
              child: Row(
                children: [
                  Icon(Icons.engineering_rounded, color: _secondary, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Maintenance en contrôle${controlBy.isNotEmpty ? ' · $controlBy' : ''}',
                      style: GoogleFonts.inter(
                        color: _onSurface,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Text(
                    'Temps contrôle: ${_formatElapsed(elapsed)}',
                    style: GoogleFonts.spaceGrotesk(
                      color: _secondary,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDiagnosticBanner() {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (_, child) => Opacity(opacity: _pulseAnimation.value, child: child),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _error.withOpacity(0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _error.withOpacity(0.3)),
        ),
        child: LayoutBuilder(builder: (context, constraints) {
          final isWide = constraints.maxWidth > 500;
          if (isWide) {
            return Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _error,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.query_stats,
                      color: Colors.white, size: 26),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'DIAGNOSTIC DE PANNE (IA)',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 9,
                          color: _error,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      RichText(
                        text: TextSpan(
                          style: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: _onSurface),
                          children: [
                            const TextSpan(text: 'Type de Panne : '),
                            TextSpan(
                              text: 'Surchauffe Moteur Détectée',
                              style: TextStyle(color: _error),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 20),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'CONFIANCE IA',
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 9, color: _onSurfaceVariant),
                    ),
                    Text(
                      '92.4%',
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: _onSurface),
                    ),
                  ],
                ),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed: () {},
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _error,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text(
                    "INTERVENIR D'URGENCE",
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ],
            );
          }
          // narrow
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                        color: _error,
                        borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.query_stats,
                        color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('DIAGNOSTIC DE PANNE (IA)',
                            style: GoogleFonts.spaceGrotesk(
                                fontSize: 9,
                                color: _error,
                                letterSpacing: 1.5,
                                fontWeight: FontWeight.bold)),
                        RichText(
                            text: TextSpan(
                                style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: _onSurface),
                                children: [
                              const TextSpan(text: 'Surchauffe Moteur '),
                              TextSpan(
                                  text: 'Détectée',
                                  style: TextStyle(color: _error)),
                            ]))
                      ],
                    ),
                  )
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('CONFIANCE IA',
                        style: GoogleFonts.spaceGrotesk(
                            fontSize: 9, color: _onSurfaceVariant)),
                    Text('92.4%',
                        style: GoogleFonts.spaceGrotesk(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: _onSurface)),
                  ]),
                  ElevatedButton(
                    onPressed: () {},
                    style: ElevatedButton.styleFrom(
                        backgroundColor: _error,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8))),
                    child: Text("INTERVENIR",
                        style: GoogleFonts.spaceGrotesk(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.white)),
                  ),
                ],
              )
            ],
          );
        }),
      ),
    );
  }

  // ════════════════════════ HELPERS ══════════════════════════════
  Widget _scoreBox(String label, String value, Color color,
      {bool isRisk = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isRisk) ...[
              const Icon(Icons.psychology, size: 12, color: _secondary),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 9, color: _onSurfaceVariant, letterSpacing: 1),
            ),
          ],
        ),
        Text(
          value,
          style: GoogleFonts.spaceGrotesk(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _sensorTile(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _surfaceContainer.withOpacity(0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _outlineVariant.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label.toUpperCase(),
            style: GoogleFonts.spaceGrotesk(
                fontSize: 8, color: _onSurfaceVariant, letterSpacing: 1),
          ),
          Text(
            value,
            style: GoogleFonts.spaceGrotesk(
                fontSize: 13, fontWeight: FontWeight.bold, color: _onSurface),
          ),
        ],
      ),
    );
  }

  Widget _sensorTileWarning(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _error.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _error.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label.toUpperCase(),
            style: GoogleFonts.spaceGrotesk(
                fontSize: 8,
                color: _error,
                fontWeight: FontWeight.bold,
                letterSpacing: 1),
          ),
          Row(
            children: [
              Text(
                value,
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: _error),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.trending_up, size: 14, color: _error),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionBtn(IconData icon, Color hoverColor, VoidCallback onTap) {
    return Material(
      color: _surfaceContainerHighest,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        hoverColor: hoverColor.withOpacity(0.1),
        child: Container(
          padding: const EdgeInsets.all(12),
          child: Icon(icon, size: 20, color: _onSurface),
        ),
      ),
    );
  }

  Widget _actionBtnError(VoidCallback onTap) {
    return Material(
      color: _error.withOpacity(0.2),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(12),
          child: const Icon(Icons.warning, size: 20, color: _error),
        ),
      ),
    );
  }

  Widget _buildFAB() {
    return FloatingActionButton.extended(
      onPressed: () {},
      backgroundColor: _primary,
      elevation: 8,
      icon: const Icon(Icons.add, color: Colors.white),
      label: Text(
        'Ajouter une machine',
        style: GoogleFonts.spaceGrotesk(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 12,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Simple data class for sensor readings
// ─────────────────────────────────────────────────────────────
class _SensorData {
  final String label;
  final String value;
  const _SensorData(this.label, this.value);
}
