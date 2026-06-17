import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:ui';
import 'dart:convert';
import 'login_page.dart';
import 'machine_detail_ai_page.dart';
import 'ai_analysis_page.dart';
import 'services/api_service.dart';
import 'utils/catalog_list_utils.dart';
import 'utils/client_auth_gate.dart';
import 'widgets/hero_looping_video_background.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'machine_detail_pro_page.dart';
import 'widgets/telemetry_history_widget.dart';
import 'dart:async';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// ClientDashboardPage â€” shown after a client logs in
// Mirrors the HTML "Predictive Cloud - Liste des Machines" page
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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
  // Sidebar nav index: 0=Home, 1=Machines, 2=IA, 3=Team, 4=Docs
  int _navIndex = 0;
  /// Machine choisie pour lâ€™onglet Analyse IA (null = liste de sÃ©lection).
  Map<String, dynamic>? _iaSelectedMachine;
  bool _iaNoMachinesAssigned = false;
  /// Machine choisie depuis Mes Machines.
  Map<String, dynamic>? _machineSelectedMachine;
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
  final List<Map<String, String>> _clientNotifications = [];
  int _unreadNotifications = 0;
  final Map<String, double> _realtimeTemps = {};
  final Map<String, double> _realtimeVibrations = {};
  final Map<String, double> _realtimeFrictions = {};
  final Map<String, double> _realtimePressures = {};
  final Map<String, double> _realtimeMagnetics = {};
  final Map<String, double> _realtimeRisks = {};
  final Map<String, DateTime> _lastTelemetryTime = {};
  Timer? _controlTicker;
  Timer? _machinesAutoRefreshTimer;

  final Map<String, String> _lastGlobalAlertMode = {};
  final Set<String> _dangerDialogShownFor = {}; // afficher la fenêtre de panne une seule fois par machine

  void _checkGlobalRisk(String mId, String mName, double temp, double vib, double mag, double iaRisk, Map<String, dynamic> machineData) {
    String newMode = 'normal';
    List<String> risques = [];
    if (temp >= 75.0) {
      newMode = 'danger';
      risques.add("Chauffage critique (>= 75°C)");
    } else if (temp >= 55.0) {
      if (newMode == 'normal') newMode = 'risque';
      risques.add("Surchauffe détectée (>= 55°C)");
    }

    if (vib >= 12.0) {
      newMode = 'danger';
      risques.add("Vibration critique (>= 12 mm/s)");
    } else if (vib >= 7.0) {
      if (newMode == 'normal') newMode = 'risque';
      risques.add("Vibration anormale (>= 7 mm/s)");
    }



    if (iaRisk >= 70) {
      newMode = 'danger';
      risques.add("IA: Probabilité de panne critique");
    } else if (iaRisk >= 40) {
      if (newMode == 'normal') newMode = 'risque';
      risques.add("IA: Anomalie détectée");
    }

    final lastMode = _lastGlobalAlertMode[mId] ?? 'normal';
    if ((newMode == 'danger' || newMode == 'risque') && !_dangerDialogShownFor.contains(mId)) {
      _dangerDialogShownFor.add(mId);
      _lastGlobalAlertMode[mId] = newMode;
      _showGlobalDangerDialog(mId, mName, newMode, risques.join("\n\u2022 "), machineData);
    }
  }

  void _showGlobalDangerDialog(String mId, String mName, String mode, String typeRisque, Map<String, dynamic> machineData) {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final color = mode == 'danger' ? const Color(0xFFFFB4AB) : const Color(0xFFFF6E00);
        final title = mode == 'danger' ? 'ALERTE DANGER' : 'ALERTE RISQUE';
        return AlertDialog(
          backgroundColor: const Color(0xFF272743),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: color, width: 2),
          ),
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: color, size: 32),
              const SizedBox(width: 10),
              Text(title, style: GoogleFonts.spaceGrotesk(color: color, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Machine: ' + mName.toUpperCase(), 
                style: GoogleFonts.inter(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Text('Le système a détecté une anomalie :', 
                style: GoogleFonts.inter(color: const Color(0xFFE2BFB0), fontSize: 13)),
              const SizedBox(height: 8),
              Text('• ' + typeRisque, 
                style: GoogleFonts.inter(color: color, fontSize: 14, fontWeight: FontWeight.w600)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('IGNORER', style: GoogleFonts.spaceGrotesk(color: const Color(0xFFE2BFB0))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: color),
              onPressed: () {
                Navigator.of(context).pop();
                setState(() {
                  _navIndex = 2; // AI Analysis page
                  _iaSelectedMachine = machineData;
                });
              },
              child: Text('AFFICHER', style: GoogleFonts.spaceGrotesk(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      }
    );
  }

  // Public catalogue (same data as HomePage) shown inside the client dashboard (tab index=0).
  Future<List<Map<String, dynamic>>>? _publicCatalogFuture;
  final TextEditingController _publicCatalogSearchController = TextEditingController();
  String _publicCatalogSearchQuery = '';
  String? _publicCatalogStatusFilter;
  String? _publicCatalogBrandFilter;
  CatalogSortOption? _publicCatalogSort;
  CatalogToolbarPanel _publicCatalogPanel = CatalogToolbarPanel.none;

  double _toDouble(dynamic value, [double fallback = 0.0]) {
    if (value == null) return fallback;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? fallback;
    return fallback;
  }

  @override
  void initState() {
    super.initState();
    _consumeGoogleOAuthReturnIfPresent();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _shimmerController, curve: Curves.easeInOut),
    );

    _refreshMachines();
    _publicCatalogFuture = ApiService.getMachinesForHomeCatalog();
    _initSocket();
    _initRenderers();
    _controlTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _machinesAutoRefreshTimer = Timer.periodic(
      const Duration(seconds: 25),
      (_) => _refreshMachines(),
    );
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
  }

  void _refreshMachines() async {
    final cId =
        (widget.clientId ??
                widget.clientData?['clientId'] ??
                widget.clientData?['id'] ??
                ApiService.savedClientId ??
                '')
            .toString()
            .trim();
    if (cId.isNotEmpty) {
      setState(() {
        _machinesFuture = ApiService.getMachinesForClient(cId).then((list) {
          for (final m in list) {
            final mId = (m['machineId'] ?? m['id'] ?? m['_id'] ?? '').toString();
            final mName = (m['name'] ?? m['nom'] ?? 'Machine').toString();
            if (mId.isNotEmpty) {
              _socket.on('ai:$mId', (data) {
                if (!mounted || data is! Map) return;
                setState(() {
                  _realtimeRisks[mId] = _toDouble(data['prob_panne'] ?? data['riskPercentage'], 0.0);
                });
                _checkGlobalRisk(mId, mName, _realtimeTemps[mId] ?? 0.0, _realtimeVibrations[mId] ?? 0.0, _realtimeMagnetics[mId] ?? 0.0, _realtimeRisks[mId] ?? 0.0, m);
              });
              
              ApiService.getLatestTelemetry(mId).then((tel) {
                if (tel != null && mounted) {
                  setState(() {
                    final rawMetrics = tel['metrics'];
                    final metrics = rawMetrics is Map ? Map<String, dynamic>.from(rawMetrics) : null;
                    _realtimeTemps[mId] = _toDouble(tel['temperature'] ?? tel['temp'] ?? metrics?['thermal'] ?? metrics?['temp'], 0.0);
                    _realtimeVibrations[mId] = _toDouble(tel['vibration'] ?? metrics?['vibration'], 0.0);
                    _realtimeFrictions[mId] = _toDouble(tel['friction'] ?? metrics?['friction'], 0.0);
                    _realtimePressures[mId] = _toDouble(tel['pressure'] ?? tel['pression'] ?? metrics?['pressure'] ?? metrics?['pression'], 0.0);
                    _realtimeMagnetics[mId] = _toDouble(tel['magnetic'] ?? tel['magnet'] ?? metrics?['magnetic'] ?? metrics?['magnet'], 0.0);
                    _lastTelemetryTime[mId] = DateTime.tryParse((tel['createdAt'] ?? tel['timestamp'] ?? '').toString()) ?? DateTime.now();
                  });
                  _checkGlobalRisk(mId, mName, _realtimeTemps[mId] ?? 0.0, _realtimeVibrations[mId] ?? 0.0, _realtimeMagnetics[mId] ?? 0.0, _realtimeRisks[mId] ?? 0.0, m);
                }
              }).catchError((_) {});
            }
          }
          return list;
        });
        _techniciansFuture = Future.wait([
          ApiService.getTechniciansForClient(cId),
          ApiService.getMaintenanceAgentsForClient(cId)
        ]).then((results) => [...results[0], ...results[1]]);
        _isLoadingStats = true;
      });
      
      try {
        final clientTechs = await _techniciansFuture!;
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

  Future<void> _openMesMachinesDirectly() async {
    final existing = _machineSelectedMachine;
    if (existing != null) {
      setState(() => _navIndex = 1);
      return;
    }

    final cId =
        (widget.clientId ??
                widget.clientData?['clientId'] ??
                widget.clientData?['id'] ??
                ApiService.savedClientId ??
                '')
            .toString()
            .trim();
    if (cId.isEmpty) {
      setState(() => _navIndex = 1);
      return;
    }

    try {
      final machines = await ApiService.getMachinesForClient(cId);
      if (!mounted) return;
      setState(() {
        _machineSelectedMachine = null; // Let the user see the list first
        _navIndex = 1;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _navIndex = 1);
    }
  }

  Future<void> _openAnalyseIaDirectly() async {
    final existing = _iaSelectedMachine;
    if (existing != null) {
      setState(() => _navIndex = 2);
      return;
    }

    final cId =
        (widget.clientId ??
                widget.clientData?['clientId'] ??
                widget.clientData?['id'] ??
                ApiService.savedClientId ??
                '')
            .toString()
            .trim();
    if (cId.isEmpty) {
      setState(() => _navIndex = 2);
      return;
    }

    try {
      final machines = await ApiService.getMachinesForClient(cId);
      if (!mounted) return;
      setState(() {
        _iaNoMachinesAssigned = machines.isEmpty;
        _iaSelectedMachine = null; // Let the user see the list first
        _navIndex = 2;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _iaNoMachinesAssigned = false;
        _navIndex = 2;
      });
    }
  }

  Future<void> _consumeGoogleOAuthReturnIfPresent() async {
    if (!kIsWeb) return;
    final qp = _readMergedWebQueryParams();
    if (qp['googleAuth'] == null) return;
    if (qp['googleAuth'] != '1') {
      final msg = (qp['error'] ?? 'Connexion Google refusÃ©e').trim();
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
      });
      return;
    }

    final token = (qp['token'] ?? '').trim();
    if (token.isEmpty) return;
    final role = (qp['role'] ?? 'client').trim();

    await ApiService.saveAuth(token, role);
    await ApiService.saveClientSession(
      clientId: (qp['clientId'] ?? '').trim(),
      clientName: (qp['name'] ?? 'Client').trim(),
      clientEmail: (qp['email'] ?? '').trim(),
      clientLocation: (qp['location'] ?? '').trim(),
      clientPhotoUrl:
          (qp['photoUrl'] ??
                  qp['avatarUrl'] ??
                  qp['profilePhotoUrl'] ??
                  qp['imageUrl'] ??
                  qp['image'] ??
                  '')
              .trim(),
    );
  }

  Map<String, String> _readMergedWebQueryParams() {
    final params = <String, String>{...Uri.base.queryParameters};
    final frag = Uri.base.fragment;
    if (frag.contains('?')) {
      final fragQuery = frag.split('?').skip(1).join('?');
      params.addAll(Uri.splitQueryString(fragQuery));
    }
    return params;
  }

  @override
  void dispose() {
    _controlTicker?.cancel();
    _machinesAutoRefreshTimer?.cancel();
    _shimmerController.dispose();
    _publicCatalogSearchController.dispose();
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
    debugPrint('ðŸ”Œ ClientDashboard: Initialisation Socket.io');
    _socket = IO.io(ApiService.socketBaseUrl, <String, dynamic>{
      'transports': <String>['polling', 'websocket'],
      'autoConnect': true,
    });

    _socket.onConnect((_) {
      debugPrint('âœ… ClientDashboard: ConnectÃ© au serveur Socket.io');
      if (mounted) setState(() {});
    });
    _socket.onDisconnect((_) {
      debugPrint('âŒ ClientDashboard: DÃ©connectÃ© du serveur');
      if (mounted) setState(() {});
    });
    _socket.onConnectError((err) => debugPrint('âŒ ClientDashboard: Erreur de connexion Socket.io: $err'));
    _socket.onError((err) => debugPrint('âŒ ClientDashboard: Erreur gÃ©nÃ©rale Socket.io: $err'));

    _socket.on('controle_notification', (data) {
      if (!mounted) return;
      setState(() {
        _clientNotifications.insert(0, {
          'title': data['title']?.toString() ?? 'Nouveau ContrÃ´le',
          'body': data['body']?.toString() ?? 'DÃ©tails du contrÃ´le non disponibles.',
        });
        if (_clientNotifications.length > 50) {
          _clientNotifications.removeLast();
        }
        _unreadNotifications++;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(data['body']?.toString() ?? 'Nouveau contrÃ´le enregistrÃ©.'),
          backgroundColor: _primary,
          duration: const Duration(seconds: 4),
        ),
      );
    });

    _socket.on('nouvelle_prediction', (raw) {
      try {
        final dynamic decoded = raw is String ? jsonDecode(raw) : raw;
        if (decoded is! Map) return;
        final data = Map<String, dynamic>.from(decoded as Map);
        final String mId = (data['machineId'] ?? data['id'] ?? '').toString();
        if (mId.isEmpty || !mounted) return;

        final rawMetrics = data['metrics'];
        final metrics = rawMetrics is Map ? Map<String, dynamic>.from(rawMetrics) : null;
        final temp = _toDouble(data['temperature'] ?? data['temp'] ?? metrics?['thermal'] ?? metrics?['temp'], _realtimeTemps[mId] ?? 0.0);
        final vibration = _toDouble(data['vibration'] ?? metrics?['vibration'], _realtimeVibrations[mId] ?? 0.0);
        final friction = _toDouble(data['friction'] ?? metrics?['friction'], _realtimeFrictions[mId] ?? 0.0);
        final pressure = _toDouble(data['pressure'] ?? data['pression'] ?? metrics?['pressure'] ?? metrics?['pression'], _realtimePressures[mId] ?? 0.0);

        setState(() {
          _realtimeTemps[mId] = temp;
          _realtimeVibrations[mId] = vibration;
          _realtimeFrictions[mId] = friction;
          _realtimePressures[mId] = pressure;
          _lastTelemetryTime[mId] = DateTime.now();
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
        SnackBar(content: Text(accepted ? '$who a acceptÃ© l\'appel' : '$who a refusÃ© l\'appel')),
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

    _socket.on('purchase_request_provisioned', (data) {
      if (!mounted || data is! Map) return;
      final payload = Map<String, dynamic>.from(data);
      final refreshedClientId =
          (payload['clientId'] ?? payload['linkedClientId'] ?? '').toString();
      final currentClientId =
          (widget.clientId ??
                  widget.clientData?['clientId'] ??
                  widget.clientData?['id'] ??
                  '')
              .toString();
      if (refreshedClientId.isNotEmpty && refreshedClientId == currentClientId) {
        _refreshMachines();
      }
    });
  }

  // â”€â”€ Colour tokens (mirror Tailwind config) â”€â”€
  static const _bg = Color(0xFF0F0F1E);
  static const _surfaceContainerLowest = Color(0xFF0B0B1A);
  static const _surfaceContainerLow = Color(0xFF161626);
  static const _surfaceContainer = Color(0xFF1D1D38);
  static const _surfaceContainerHigh = Color(0xFF272743);
  static const _surfaceContainerHighest = Color(0xFF32324E);
  static const _primary = Color(0xFFFF6E00);
  static const _primaryContainer = Color(0xFF4A2A1A);
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
          // â”€â”€ Sidebar â”€â”€
          if (isDesktop) _buildSidebar(),
          // â”€â”€ Main area â”€â”€
          Expanded(
            child: Column(
              children: [
                if (isDesktop) _buildTopBar(isDesktop),
                if (!isDesktop) _buildMobileQuickActions(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(isDesktop ? 32 : 14),
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
    if (_navIndex == 0) {
      return _buildClientPublicCatalog(isDesktop);
    }
    if (_navIndex == 1) {
      if (_machineSelectedMachine != null) {
        return _buildMachineTelemetryDetailSection(
          isDesktop,
        );
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
    if (_navIndex == 2) {
      return _buildAnalyseIaSection(isDesktop);
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
              "Choisissez une machine pour consulter sa fiche, l'historique tÃ©lÃ©mÃ©trique et les fiches associÃ©es.",
          onPick: (m) => setState(() => _docSelectedMachine = m),
        );
      }
      return _buildDocumentsTechnicalSection(
        isDesktop,
        selectedMachine: _docSelectedMachine!,
        title: 'Documents techniques',
        onBack: () => setState(() => _docSelectedMachine = null),
      );
    }
    if (_navIndex == 5) {
      return _buildProfileSection();
    }
    // Fallback.
    return _buildMachineListSection(isDesktop);
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surfaceContainerLow.withOpacity(0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.25), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: _onSurface,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileSection() {
    final isDesktop = MediaQuery.sizeOf(context).width > 900;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'PROFIL CLIENT',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: _secondary,
              letterSpacing: 2.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Informations de votre compte',
            style: GoogleFonts.inter(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: _onSurface,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 24),

          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: _surfaceContainerLow,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _outlineVariant.withOpacity(0.12)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 15,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              children: [
                GestureDetector(
                  onTap: _openProfileBackgroundDialog,
                  child: Container(
                    height: 120,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(20),
                        topRight: Radius.circular(20),
                      ),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          const Color(0xFF1E293B),
                          _secondary.withOpacity(0.8),
                        ],
                      ),
                      image: _profileBackgroundDecorationImage(),
                    ),
                    child: Stack(
                      children: [
                        Positioned(
                          right: 16,
                          top: 16,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.5),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.camera_alt_outlined, color: Colors.white, size: 18),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Transform.translate(
                  offset: const Offset(0, -36),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: _bg,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: _secondary.withOpacity(0.25),
                              blurRadius: 12,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: _buildClientProfileAvatar(),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _currentClientName,
                        style: GoogleFonts.inter(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: _onSurface,
                          letterSpacing: -0.2,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.mail_outline_rounded, color: _onSurfaceVariant.withOpacity(0.7), size: 14),
                          const SizedBox(width: 6),
                          Text(
                            _currentClientEmail.isEmpty ? 'Email non renseignÃ©' : _currentClientEmail,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: _onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Icon(Icons.location_on_outlined, color: _onSurfaceVariant.withOpacity(0.7), size: 14),
                          const SizedBox(width: 6),
                          Text(
                            _currentClientLocation,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: _onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      ElevatedButton.icon(
                        onPressed: _openProfileSettingsDialog,
                        icon: const Icon(Icons.edit_rounded, size: 16),
                        label: Text('Modifier le profil', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _secondary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          FutureBuilder<List<Map<String, dynamic>>>(
            future: _machinesFuture,
            builder: (context, snapshot) {
              final machines = snapshot.data ?? const <Map<String, dynamic>>[];
              final totalMachines = machines.length;
              final maintenanceCount = machines.where((m) {
                final active = m['maintenanceControlActive'] == true;
                final state = (m['state'] ?? m['status'] ?? '').toString().toLowerCase();
                return active || state.contains('maintenance') || state.contains('mainten');
              }).length;

              return isDesktop
                  ? Row(
                      children: [
                        Expanded(child: _buildStatCard('Total Machines', totalMachines.toString(), Icons.precision_manufacturing_rounded, _secondary)),
                        const SizedBox(width: 16),
                        Expanded(child: _buildStatCard('Total Techniciens', _isLoadingStats ? '..' : _techCount.toString(), Icons.groups_rounded, const Color(0xFFA88DFF))),
                        const SizedBox(width: 16),
                        Expanded(child: _buildStatCard('En Maintenance', maintenanceCount.toString(), Icons.build_circle_rounded, const Color(0xFFF15C6D))),
                      ],
                    )
                  : Column(
                      children: [
                        _buildStatCard('Total Machines', totalMachines.toString(), Icons.precision_manufacturing_rounded, _secondary),
                        const SizedBox(height: 12),
                        _buildStatCard('Total Techniciens', _isLoadingStats ? '..' : _techCount.toString(), Icons.groups_rounded, const Color(0xFFA88DFF)),
                        const SizedBox(height: 12),
                        _buildStatCard('En Maintenance', maintenanceCount.toString(), Icons.build_circle_rounded, const Color(0xFFF15C6D)),
                      ],
                    );
            },
          ),
          const SizedBox(height: 24),

          isDesktop
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 6,
                      child: _buildProfileClientMachinesSection(),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      flex: 4,
                      child: _buildProfileTechniciansSection(),
                    ),
                  ],
                )
              : Column(
                  children: [
                    _buildProfileClientMachinesSection(),
                    const SizedBox(height: 24),
                    _buildProfileTechniciansSection(),
                  ],
                ),
          const SizedBox(height: 48),
        ],
      ),
    );
  }

  Widget _buildProfileClientMachinesSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surfaceContainerLow.withOpacity(0.45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _outlineVariant.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'MACHINES DU CLIENT',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 10,
              letterSpacing: 1.6,
              fontWeight: FontWeight.w700,
              color: _onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _machinesFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                );
              }
              final machines = snapshot.data ?? const <Map<String, dynamic>>[];
              if (machines.isEmpty) {
                return Text(
                  'Aucune machine assignÃ©e Ã  ce client.',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: _onSurfaceVariant,
                  ),
                );
              }
              return Column(
                children: machines.take(5).map((m) {
                  final name = _clientMachineName(m);
                  final id = _clientMachineId(m);
                  final status = (m['state'] ?? m['status'] ?? 'Actif').toString();
                  final brand = (m['brand'] ?? m['marque'] ?? 'â€”').toString();
                  final model = (m['model'] ?? m['name'] ?? 'â€”').toString();
                  final type = (m['type'] ?? m['category'] ?? 'â€”').toString();
                  final location = (m['location'] ?? m['site'] ?? 'â€”').toString();
                  final serial = (m['serialNumber'] ?? m['serial'] ?? m['sn'] ?? 'â€”')
                      .toString();
                  final maintBy =
                      (m['maintenanceControlBy'] ?? m['maintainedBy'] ?? 'â€”')
                          .toString();
                  final maintActive = m['maintenanceControlActive'] == true
                      ? 'Oui'
                      : 'Non';
                  final temp = (m['temperature'] ?? m['temp'] ?? 'â€”').toString();
                  final vibration =
                      (m['vibration'] ?? m['vibrationLevel'] ?? 'â€”').toString();
                  final pressure =
                      (m['pressure'] ?? m['pressureLevel'] ?? 'â€”').toString();
                  final imageUrl = (m['imageUrl'] ?? m['image'] ?? m['photo'] ?? '')
                      .toString()
                      .trim();
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _surfaceContainerHigh.withOpacity(0.35),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _outlineVariant.withOpacity(0.18),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: 92,
                            height: 72,
                            child: imageUrl.isEmpty
                                ? Container(
                                    color: _surfaceContainerHighest.withOpacity(0.4),
                                    child: Icon(
                                      Icons.precision_manufacturing_outlined,
                                      color: _primary.withOpacity(0.95),
                                      size: 24,
                                    ),
                                  )
                                : Image.network(
                                    imageUrl,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
                                      color: _surfaceContainerHighest.withOpacity(0.4),
                                      child: Icon(
                                        Icons.image_not_supported_outlined,
                                        color: _onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      name,
                                      style: GoogleFonts.inter(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: _onSurface,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    status.toUpperCase(),
                                    style: GoogleFonts.spaceGrotesk(
                                      fontSize: 10,
                                      color: _primary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                id.isEmpty ? 'ID: indisponible' : 'ID: $id',
                                style: GoogleFonts.spaceGrotesk(
                                  fontSize: 10,
                                  color: _onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Wrap(
                                spacing: 10,
                                runSpacing: 4,
                                children: [
                                  _miniInfo('Marque', brand),
                                  _miniInfo('Modele', model),
                                  _miniInfo('Type', type),
                                  _miniInfo('Serial', serial),
                                  _miniInfo('Emplacement', location),
                                  _miniInfo('Maintenance', maintActive),
                                  _miniInfo('Mainteneur', maintBy),
                                  _miniInfo('Temp', temp),
                                  _miniInfo('Vibration', vibration),
                                  _miniInfo('Voltage', pressure != '—' ? '$pressure V' : '—'),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _miniInfo(String label, String value) {
    return RichText(
      text: TextSpan(
        style: GoogleFonts.inter(
          fontSize: 10,
          color: _onSurfaceVariant,
        ),
        children: [
          TextSpan(
            text: '$label: ',
            style: GoogleFonts.inter(
              fontSize: 10,
              color: _onSurfaceVariant.withOpacity(0.85),
              fontWeight: FontWeight.w600,
            ),
          ),
          TextSpan(
            text: value.isEmpty ? 'â€”' : value,
            style: GoogleFonts.inter(
              fontSize: 10,
              color: _onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileTechniciansSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surfaceContainerLow.withOpacity(0.45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _outlineVariant.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'TECHNICIENS & MAINTENANCE MAN',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 10,
              letterSpacing: 1.6,
              fontWeight: FontWeight.w700,
              color: _onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _techniciansFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                );
              }
              final techs = snapshot.data ?? const <Map<String, dynamic>>[];
              if (techs.isEmpty) {
                return Text(
                  'Aucun technicien assignÃ© Ã  ce client.',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: _onSurfaceVariant,
                  ),
                );
              }
              return Column(
                children: techs.map((t) {
                  final name = (t['name'] ?? t['fullName'] ?? 'Technicien')
                      .toString();
                  final technicianId =
                      (t['technicianId'] ?? t['_id'] ?? t['id'] ?? '')
                          .toString();
                  final specialization =
                      (t['specialization'] ?? t['role'] ?? 'Support Machine')
                          .toString();
                  final status = (t['status'] ?? 'Disponible').toString();
                  final isMaintenanceMan = specialization.toLowerCase().contains('mainten');

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    decoration: BoxDecoration(
                      color: _surfaceContainerHigh.withOpacity(0.35),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _outlineVariant.withOpacity(0.18)),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: _surfaceContainerHighest,
                          child: Icon(
                            isMaintenanceMan
                                ? Icons.engineering_outlined
                                : Icons.person_outline,
                            size: 18,
                            color: _primary,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: _onSurface,
                                ),
                              ),
                              Text(
                                technicianId.isEmpty
                                    ? 'ID indisponible'
                                    : technicianId,
                                style: GoogleFonts.spaceGrotesk(
                                  fontSize: 10,
                                  color: _onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                specialization,
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  color: _onSurfaceVariant.withOpacity(0.9),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              status.toUpperCase(),
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 10,
                                color: _primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: (isMaintenanceMan
                                        ? _secondary
                                        : _outlineVariant)
                                    .withOpacity(0.18),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                isMaintenanceMan ? 'Maintenance man' : 'Technicien',
                                style: GoogleFonts.inter(
                                  fontSize: 9,
                                  color: _onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMachineTelemetryDetailSection(bool isDesktop) {
    final m = _machineSelectedMachine!;
    final mid = _clientMachineId(m);
    final name = _clientMachineName(m);
    final screenHeight = MediaQuery.sizeOf(context).height;
    final detailHeight = screenHeight < 860 ? 820.0 : screenHeight - (isDesktop ? 120.0 : 40.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSubpageHeader(
          title: 'Mes Machines',
          subtitle: '$name Â· $mid',
          onBack: () => setState(() => _machineSelectedMachine = null),
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: detailHeight,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: MachineDetailAiPage(
              machineId: mid,
              machineName: name,
              clientId: widget.clientId ?? widget.clientData?['clientId'] ?? widget.clientData?['id'],
              viewerRole: 'client',
              viewerName: (widget.clientName ?? 'Client').toString(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAnalyseIaSection(bool isDesktop) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _machinesFuture,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.hasError) {
          return _buildNoMachineAssignedCard(
            title: 'Analyse IA indisponible',
            message: "Impossible de charger les machines client pour l'analyse IA.",
          );
        }
        final machines = snap.data ?? const <Map<String, dynamic>>[];
        if (machines.isEmpty || _iaNoMachinesAssigned) {
          return _buildNoMachineAssignedCard(
            title: 'Analyse IA indisponible',
            message:
                "Aucune machine n'est assignÃ©e Ã  votre client pour le moment. Contactez l'administrateur pour activer l'analyse IA.",
          );
        }

        Map<String, dynamic> selected = _iaSelectedMachine ?? machines.first;
        if (_iaSelectedMachine == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() => _iaSelectedMachine = machines.first);
          });
        } else {
          final sid = _clientMachineId(_iaSelectedMachine!);
          final match = machines.where((m) => _clientMachineId(m) == sid).toList();
          if (match.isNotEmpty) selected = match.first;
        }

        final mid = _clientMachineId(selected);
        final mname = _clientMachineName(selected);
        final motor = (selected['motorType'] ?? 'EL_M').toString();

        final iaPanel = AiAnalysisView(
          machineId: mid,
          machineName: mname,
          motorType: motor,
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSubpageHeader(
              title: 'Analyse IA',
              subtitle: '$mname • $mid',
              onBack: () {},
            ),
            const SizedBox(height: 16),
            iaPanel,
          ],
        );
      },
    );
  }

  Widget _buildClientPublicCatalog(bool isDesktop) {
    final width = MediaQuery.of(context).size.width;
    final isTablet = width >= 760;
    final crossAxisCount = isDesktop ? 3 : (isTablet ? 2 : 1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _publicCatalogFuture,
          builder: (context, snapshot) {
            final total = (snapshot.data ?? const <Map<String, dynamic>>[]).length;
            return _buildClientCatalogHero(total: total, isDesktop: isDesktop);
          },
        ),
        const SizedBox(height: 14),
        _buildClientCatalogToolbar(isDesktop),
        const SizedBox(height: 16),
        _buildClientCatalogSectionHeader(
          title: 'CATALOGUE DES SYSTEMES',
          subtitle: 'Unites de surveillance haute precision',
          isDesktop: isDesktop,
          trailing: FutureBuilder<List<Map<String, dynamic>>>(
            future: _publicCatalogFuture,
            builder: (context, snapshot) {
              final total = (snapshot.data ?? const <Map<String, dynamic>>[]).length;
              return Text(
                '$total machine(s) affichee(s)',
                style: GoogleFonts.inter(
                  color: _onSurfaceVariant.withOpacity(0.9),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 14),

        FutureBuilder<List<Map<String, dynamic>>>(
          future: _publicCatalogFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 60),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'Erreur chargement catalogue: ${snapshot.error}',
                  style: GoogleFonts.inter(color: _error),
                ),
              );
            }

            final allMachines = snapshot.data ?? const <Map<String, dynamic>>[];
            final filtered = filterAndSortCatalogMachines(
              allMachines,
              searchQuery: _publicCatalogSearchQuery,
              statusFilter: _publicCatalogStatusFilter,
              brandFilter: _publicCatalogBrandFilter,
              sort: _publicCatalogSort,
            );

            if (filtered.isEmpty) {
              return _buildCatalogEmptyState();
            }

            return GridView.builder(
              itemCount: filtered.length,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                childAspectRatio: crossAxisCount == 1 ? 0.92 : 1.02,
              ),
              itemBuilder: (context, i) {
                final machine = filtered[i];
                final machineId = (machine['machineId'] ?? machine['_id'] ?? machine['id'] ?? '').toString();
                return _ClientPublicMachineCard(
                  machine: machine,
                  onRequireLogin: _openCatalogClientLogin,
                  onBuy: () => _buyMachineFromClientHome(
                    context,
                    machineId: machineId,
                    machine: machine,
                  ),
                );
              },
            );
          },
        ),
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _buildClientCatalogHero({required int total, required bool isDesktop}) {
    final heroHeight = isDesktop ? 280.0 : 250.0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        height: heroHeight,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildClientHeroVisual(),
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Color(0xEE131B32),
                    Color(0xB3161F38),
                    Color(0x66161F38),
                  ],
                  stops: [0.0, 0.48, 1.0],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(isDesktop ? 24 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Catalogue machines',
                    style: GoogleFonts.inter(
                      color: const Color(0xFFFFB87A),
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      fontSize: isDesktop ? 14 : 12,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'L\'efficacite predite par l\'IA',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: isDesktop ? 38 : 22,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Visualisez les equipements critiques en temps reel.',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: const Color(0xFFD5DCEE),
                      fontSize: isDesktop ? 14 : 12,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildClientCatalogChip(Icons.precision_manufacturing_rounded, '$total machines'),
                      _buildClientCatalogChip(Icons.update_rounded, 'Temps reel'),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClientHeroVisual() {
    return const HeroLoopingVideoBackground(
      fallbackImageUrl:
          'https://images.unsplash.com/photo-1565043589221-1a6fd9ae45c7?auto=format&fit=crop&w=1400&q=80',
    );
  }

  bool get _hasPublicCatalogFilters =>
      catalogFilterValueIsActive(_publicCatalogStatusFilter) ||
      catalogFilterValueIsActive(_publicCatalogBrandFilter);

  String _publicCatalogFilterChipLabel() {
    if (!_hasPublicCatalogFilters) return 'Filtre';
    final parts = <String>[];
    final st = catalogStatusFilterLabel(_publicCatalogStatusFilter);
    if (st != null) parts.add(st);
    if (catalogFilterValueIsActive(_publicCatalogBrandFilter)) {
      parts.add(_publicCatalogBrandFilter!);
    }
    return parts.join(' Â· ');
  }

  void _togglePublicCatalogFilterPanel() {
    setState(() {
      _publicCatalogPanel =
          _publicCatalogPanel == CatalogToolbarPanel.filter
              ? CatalogToolbarPanel.none
              : CatalogToolbarPanel.filter;
    });
  }

  void _togglePublicCatalogSortPanel() {
    setState(() {
      _publicCatalogPanel = _publicCatalogPanel == CatalogToolbarPanel.sort
          ? CatalogToolbarPanel.none
          : CatalogToolbarPanel.sort;
    });
  }

  Widget _buildClientCatalogToolbar(bool isDesktop) {
    final width = MediaQuery.of(context).size.width;
    final showCatalogActions = isDesktop || width >= 760;

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _publicCatalogFuture,
      builder: (context, snapshot) {
        final allMachines = snapshot.data ?? const <Map<String, dynamic>>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: const Color(0x55182236),
                    border: Border.all(color: const Color(0x33FFFFFF)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.search_rounded,
                        size: 18,
                        color: Color(0xFFA7B1C6),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _publicCatalogSearchController,
                          onChanged: (v) => setState(
                            () => _publicCatalogSearchQuery = v,
                          ),
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 13,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Rechercher par nom, ID ou marque...',
                            hintStyle: GoogleFonts.inter(
                              color: const Color(0x77A7B1C6),
                              fontSize: 13,
                            ),
                            border: InputBorder.none,
                            isDense: true,
                          ),
                        ),
                      ),
                      if (showCatalogActions) ...[
                        _buildClientCatalogChip(
                          Icons.filter_alt_outlined,
                          _publicCatalogFilterChipLabel(),
                          onTap: _togglePublicCatalogFilterPanel,
                          active:
                              _publicCatalogPanel ==
                                  CatalogToolbarPanel.filter ||
                              _hasPublicCatalogFilters,
                        ),
                        const SizedBox(width: 8),
                        _buildClientCatalogChip(
                          Icons.tune,
                          'Tri',
                          onTap: _togglePublicCatalogSortPanel,
                          active:
                              _publicCatalogPanel ==
                                  CatalogToolbarPanel.sort ||
                              _publicCatalogSort != null,
                        ),
                      ] else ...[
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: Icon(
                            Icons.filter_alt_outlined,
                            color: _hasPublicCatalogFilters ? const Color(0xFFFFB87A) : const Color(0xFFA7B1C6),
                            size: 20,
                          ),
                          onPressed: _togglePublicCatalogFilterPanel,
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: Icon(
                            Icons.tune,
                            color: _publicCatalogSort != null ? const Color(0xFFFFB87A) : const Color(0xFFA7B1C6),
                            size: 20,
                          ),
                          onPressed: _togglePublicCatalogSortPanel,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            CatalogFilterSortPanel(
              panel: _publicCatalogPanel,
              brands: distinctCatalogBrands(allMachines),
              statusFilter: _publicCatalogStatusFilter,
              brandFilter: _publicCatalogBrandFilter,
              sort: _publicCatalogSort,
              onStatusChanged: (status) {
                setState(() => _publicCatalogStatusFilter = status);
              },
              onBrandChanged: (brand) {
                setState(() => _publicCatalogBrandFilter = brand);
              },
              onSortChanged: (sort) {
                setState(() => _publicCatalogSort = sort);
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildClientCatalogSectionHeader({
    required String title,
    required String subtitle,
    required Widget trailing,
    required bool isDesktop,
  }) {
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.inter(
            color: const Color(0xFFFFB87A),
            fontSize: 11,
            letterSpacing: 2.2,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: isDesktop ? 28 : 20,
            fontWeight: FontWeight.w800,
            height: 1.08,
          ),
        ),
      ],
    );

    if (isDesktop) {
      return Row(
        children: [
          Expanded(child: body),
          const SizedBox(width: 16),
          trailing,
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        body,
        const SizedBox(height: 8),
        trailing,
      ],
    );
  }

  Widget _buildClientCatalogChip(
    IconData icon,
    String label, {
    VoidCallback? onTap,
    bool active = false,
  }) {
    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: active ? const Color(0x331D88E5) : const Color(0x1FFFFFFF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: active ? const Color(0xFF1D88E5) : const Color(0x33FFFFFF),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFFD9E0F2)),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.inter(
              color: const Color(0xFFE5EAF8),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return child;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: child,
      ),
    );
  }

  Widget _buildCatalogEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: _surfaceContainerLow.withOpacity(0.6),
        border: Border.all(color: _outlineVariant.withOpacity(0.35)),
      ),
      child: Column(
        children: [
          Icon(Icons.inventory_2_outlined, color: _secondary, size: 34),
          const SizedBox(height: 12),
          Text(
            'Aucune machine disponible pour le moment.',
            style: GoogleFonts.inter(color: _onSurface, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Future<void> _openCatalogClientLogin() async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => const LoginPage(showSignupTitle: false),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _buyMachineFromClientHome(
    BuildContext context, {
    required String machineId,
    required Map<String, dynamic> machine,
  }) async {
    if (machineId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Machine invalide.')),
      );
      return;
    }

    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final locationCtrl = TextEditingController();
    final mapCtrl = TextEditingController();
    final noteCtrl = TextEditingController();

    final linkedClientId = (widget.clientId ?? ApiService.savedClientId ?? '').trim();
    if (linkedClientId.isNotEmpty) {
      nameCtrl.text = (ApiService.savedClientName ?? '').trim();
      emailCtrl.text = (ApiService.savedClientEmail ?? '').trim();
      locationCtrl.text = (ApiService.savedClientLocation ?? '').trim();
    }

    final approved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Demande d\'achat'),
        backgroundColor: _surfaceContainerHigh,
        content: SizedBox(
          width: (MediaQuery.of(ctx).size.width - 32).clamp(280.0, 430.0).toDouble(),
          child: SingleChildScrollView(
            child: Column(
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Nom complet'),
                ),
                TextField(
                  controller: emailCtrl,
                  decoration: const InputDecoration(labelText: 'Email (optionnel)'),
                ),
                TextField(
                  controller: phoneCtrl,
                  decoration: const InputDecoration(labelText: 'Telephone (optionnel)'),
                ),
                TextField(
                  controller: locationCtrl,
                  decoration: const InputDecoration(labelText: 'Localisation'),
                ),
                TextField(
                  controller: mapCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Lien Google Maps (optionnel)',
                  ),
                ),
                TextField(
                  controller: noteCtrl,
                  minLines: 2,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Note'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Envoyer'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (approved != true) return;

    if (nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Le nom est obligatoire.')),
      );
      return;
    }
    if (locationCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La localisation est obligatoire.')),
      );
      return;
    }

    try {
      await ApiService.createPurchaseRequest({
        'machineId': machineId,
        'machineName': (machine['name'] ?? '').toString(),
        if (linkedClientId.isNotEmpty) 'linkedClientId': linkedClientId,
        'requesterName': nameCtrl.text.trim(),
        'requesterEmail': emailCtrl.text.trim(),
        'requesterPhone': phoneCtrl.text.trim(),
        'location': locationCtrl.text.trim(),
        'googleMapsUrl': mapCtrl.text.trim(),
        'note': noteCtrl.text.trim(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Demande envoyee au Concepteur pour validation et creation du client.',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Echec envoi demande: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
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

  Widget _buildNoMachineAssignedCard({
    required String title,
    required String message,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _outlineVariant.withOpacity(0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline, color: _secondary, size: 22),
              const SizedBox(width: 10),
              Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: _onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            message,
            style: GoogleFonts.inter(
              fontSize: 14,
              color: _onSurfaceVariant,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentsTechnicalSection(
    bool isDesktop, {
    required Map<String, dynamic> selectedMachine,
    required String title,
    required VoidCallback onBack,
  }) {
    final m = selectedMachine;
    final mid = _clientMachineId(m);
    final name = _clientMachineName(m);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSubpageHeader(
          title: title,
          subtitle: '$name Â· $mid',
          onBack: onBack,
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
                'Fiche Ã©quipement',
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
              _docInfoRow('Type moteur', (m['motorType'] ?? 'â€”').toString()),
              _docInfoRow('Statut', (m['status'] ?? 'â€”').toString()),
              _docInfoRow('Emplacement', (m['location'] ?? 'â€”').toString()),
              _docInfoRow('Puissance', (m['power'] ?? 'â€”').toString()),
              _docInfoRow('Tension', (m['voltage'] ?? 'â€”').toString()),
              _docInfoRow('Vitesse', (m['speed'] ?? 'â€”').toString()),
              _docInfoRow('Installation', (m['installDate'] ?? 'â€”').toString()),
            ],
          ),
        ),
        const SizedBox(height: 28),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _secondary.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.history_rounded, color: _secondary, size: 20),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Historique de Telemetrie',
                  style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: _onSurface,
                    letterSpacing: -0.5,
                  ),
                ),
                Text(
                  'Derniers releves de capteurs enregistres pour cette machine.',
                  style: GoogleFonts.inter(fontSize: 13, color: _onSurfaceVariant),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 20),
        TelemetryHistoryWidget(machineId: mid),
        const SizedBox(height: 28),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _secondary.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.picture_as_pdf_rounded, color: _secondary, size: 20),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Rapport Machine',
                  style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: _onSurface,
                    letterSpacing: -0.5,
                  ),
                ),
                Text(
                  'Fiche technique PDF avec toutes les informations.',
                  style: GoogleFonts.inter(fontSize: 13, color: _onSurfaceVariant),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        Material(
          color: _surfaceContainerHigh.withOpacity(0.5),
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _generateMachinePDF(m, mid, name),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _outlineVariant.withOpacity(0.15)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFE55A00), Color(0xFFFF8A3D)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.download_rounded, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Fiche technique - $name',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: _onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Nom machine, equipe, etat, semaine, temps de travail, client',
                          style: GoogleFonts.inter(fontSize: 12, color: _onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _secondary.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'PDF',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: _secondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 28),
        Text(
          'Historique des pannes (archives)',
          style: GoogleFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: _onSurface,
          ),
        ),
        const SizedBox(height: 8),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: ApiService.getInterventionArchives(machineId: mid),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(),
              );
            }
            if (snap.hasError) {
              return Text(
                'Archives indisponibles: ${snap.error}',
                style: GoogleFonts.inter(color: _onSurfaceVariant),
              );
            }
            final rows = snap.data ?? const <Map<String, dynamic>>[];
            if (rows.isEmpty) {
              return Text(
                'Aucune panne terminÃ©e archivÃ©e pour cette machine.',
                style: GoogleFonts.inter(color: _onSurfaceVariant),
              );
            }
            return Column(
              children:
                  rows.take(6).map((a) {
                    final iid = (a['interventionId'] ?? '').toString();
                    final lbl = (a['scenarioLabel'] ?? 'Panne').toString();
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        lbl,
                        style: GoogleFonts.inter(
                          color: _onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        iid,
                        style: GoogleFonts.spaceGrotesk(
                          color: _onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                      trailing: TextButton.icon(
                        onPressed: () async {
                          final data = await ApiService.exportInterventionArchive(
                            iid,
                          );
                          if (!mounted) return;
                          showDialog<void>(
                            context: context,
                            builder:
                                (ctx) => AlertDialog(
                                  backgroundColor: _surfaceContainerLow,
                                  title: Text(
                                    'Archive $iid',
                                    style: GoogleFonts.inter(color: _onSurface),
                                  ),
                                  content: SizedBox(
                                    width: (MediaQuery.of(ctx).size.width - 32).clamp(280.0, 560.0).toDouble(),
                                    child: SingleChildScrollView(
                                      child: SelectableText(
                                        const JsonEncoder.withIndent(
                                          '  ',
                                        ).convert(data),
                                        style: GoogleFonts.spaceGrotesk(
                                          color: _onSurface,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx),
                                      child: const Text('Fermer'),
                                    ),
                                  ],
                                ),
                          );
                        },
                        icon: const Icon(Icons.download, size: 16),
                        label: const Text('Exporter'),
                      ),
                    );
                  }).toList(),
            );
          },
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

  Widget _buildMiniMetric(String label, String val, IconData icon, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(height: 4),
        Text(
          val,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _onSurface,
          ),
        ),
        Text(
          label,
          style: GoogleFonts.spaceGrotesk(
            fontSize: 9,
            color: _onSurfaceVariant,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Future<void> _generateMachinePDF(Map<String, dynamic> machine, String machineId, String machineName) async {
    final pdf = pw.Document();
    final now = DateTime.now();
    final weekNumber = ((now.difference(DateTime(now.year, 1, 1)).inDays) / 7).ceil();
    final clientName = widget.clientName ?? widget.clientData?['name'] ?? widget.clientData?['clientName'] ?? 'Client';
    final status = (machine['status'] ?? 'Inconnu').toString();
    final motorType = (machine['motorType'] ?? '-').toString();
    final location = (machine['location'] ?? '-').toString();
    final power = (machine['power'] ?? '-').toString();
    final voltage = (machine['voltage'] ?? '-').toString();
    final speed = (machine['speed'] ?? '-').toString();
    final installDate = (machine['installDate'] ?? '-').toString();

    // Fetch assigned technicians
    List<Map<String, dynamic>> techs = [];
    try {
      final cid = (widget.clientId ?? widget.clientData?['clientId'] ?? widget.clientData?['_id'] ?? '').toString();
      if (cid.isNotEmpty) {
        techs = await ApiService.getTechniciansForClient(cid);
      }
    } catch (_) {}

    // Fetch pannes (archives)
    List<Map<String, dynamic>> pannes = [];
    try {
      pannes = await ApiService.getInterventionArchives(machineId: machineId);
    } catch (_) {}

    // Fetch missions (diagnostic interventions)
    List<Map<String, dynamic>> missions = [];
    try {
      final allMissions = await ApiService.getDiagnosticInterventions();
      missions = allMissions.where((m) =>
        (m['machineId'] ?? '').toString() == machineId
      ).toList();
    } catch (_) {}

    // Fetch latest telemetry for AI message
    String aiMessage = 'Aucune prediction IA disponible.';
    String aiRisk = '-';
    String aiPanneType = '-';
    try {
      final telemetry = await ApiService.getTelemetryHistory(machineId, limit: 1);
      if (telemetry.isNotEmpty) {
        final latest = telemetry.first;
        final risk = (latest['prob_panne'] ?? latest['panne_probability'] ?? latest['scenarioProbPanne'] ?? 0);
        final riskVal = double.tryParse(risk.toString()) ?? 0;
        aiRisk = '${riskVal.toStringAsFixed(1)}%';
        aiPanneType = (latest['panne_type'] ?? latest['scenarioLabel'] ?? '-').toString();
        final niveau = (latest['niveau'] ?? 'Normal').toString();

        if (riskVal < 20) {
          aiMessage = 'La machine fonctionne normalement. Risque de panne tres faible ($aiRisk). Aucune intervention necessaire.';
        } else if (riskVal < 50) {
          aiMessage = 'Attention : risque modere de panne detecte ($aiRisk). Type potentiel : $aiPanneType. Surveillance recommandee.';
        } else if (riskVal < 80) {
          aiMessage = 'ALERTE : risque eleve de panne ($aiRisk). Type : $aiPanneType. Intervention preventive recommandee rapidement.';
        } else {
          aiMessage = 'CRITIQUE : risque tres eleve de panne ($aiRisk). Type : $aiPanneType. Arret et intervention immediate recommandes.';
        }
      }
    } catch (_) {}

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('ABBK - Rapport Machine',
                  style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
                pw.Text('Semaine $weekNumber - ${now.year}',
                  style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
              ],
            ),
            pw.SizedBox(height: 4),
            pw.Text('Genere le ${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year} a ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
            pw.SizedBox(height: 8),
            pw.Divider(thickness: 2, color: PdfColors.orange),
            pw.SizedBox(height: 16),
          ],
        ),
        build: (context) => [
          // Client info
          pw.Container(
            padding: const pw.EdgeInsets.all(16),
            decoration: pw.BoxDecoration(
              color: PdfColors.orange50,
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Row(
              children: [
                pw.Text('Client : ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
                pw.Text(clientName, style: const pw.TextStyle(fontSize: 14)),
              ],
            ),
          ),
          pw.SizedBox(height: 20),

          // Machine info table
          pw.Text('Informations Machine', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 10),
          pw.Table.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 11),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.orange),
            cellStyle: const pw.TextStyle(fontSize: 10),
            cellPadding: const pw.EdgeInsets.all(8),
            headers: ['Propriete', 'Valeur'],
            data: [
              ['Nom Machine', machineName],
              ['Identifiant', machineId],
              ['Etat', status],
              ['Type Moteur', motorType],
              ['Emplacement', location],
              ['Puissance', power],
              ['Tension', voltage],
              ['Vitesse', speed],
              ['Date Installation', installDate],
              ['Semaine', 'S$weekNumber - ${now.year}'],
            ],
          ),
          pw.SizedBox(height: 20),

          // Equipe assignee
          pw.Text('Equipe Assignee', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 10),
          if (techs.isEmpty)
            pw.Text('Aucun technicien assigne.', style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey600))
          else
            pw.Table.fromTextArray(
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 11),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
              cellStyle: const pw.TextStyle(fontSize: 10),
              cellPadding: const pw.EdgeInsets.all(8),
              headers: ['Nom', 'Specialite', 'Email'],
              data: techs.map((t) => [
                (t['name'] ?? t['fullName'] ?? '-').toString(),
                (t['specialty'] ?? t['specialite'] ?? '-').toString(),
                (t['email'] ?? '-').toString(),
              ]).toList(),
            ),
          pw.SizedBox(height: 20),

          // Resume semaine
          pw.Container(
            padding: const pw.EdgeInsets.all(16),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey400),
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Resume Semaine $weekNumber', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 8),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Etat actuel', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
                        pw.SizedBox(height: 4),
                        pw.Text(status, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Temps de travail estime', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
                        pw.SizedBox(height: 4),
                        pw.Text('${weekNumber > 0 ? 40 : 0}h / semaine', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 24),

          // === MESSAGE IA ===
          pw.Container(
            padding: const pw.EdgeInsets.all(16),
            decoration: pw.BoxDecoration(
              color: PdfColors.blue50,
              borderRadius: pw.BorderRadius.circular(8),
              border: pw.Border.all(color: PdfColors.blue200),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Message IA - Prediction Maintenance', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                pw.SizedBox(height: 8),
                pw.Table.fromTextArray(
                  headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 10),
                  headerDecoration: const pw.BoxDecoration(color: PdfColors.blue800),
                  cellStyle: const pw.TextStyle(fontSize: 10),
                  cellPadding: const pw.EdgeInsets.all(6),
                  headers: ['Risque de panne', 'Type de panne'],
                  data: [
                    [aiRisk, aiPanneType],
                  ],
                ),
                pw.SizedBox(height: 8),
                pw.Text(aiMessage, style: const pw.TextStyle(fontSize: 11)),
              ],
            ),
          ),
          pw.SizedBox(height: 24),

          // === MISSIONS (Diagnostic Interventions) ===
          pw.Text('Missions / Interventions Diagnostiques', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 10),
          if (missions.isEmpty)
            pw.Text('Aucune mission enregistree pour cette machine.', style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey600))
          else
            pw.Table.fromTextArray(
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 10),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.green800),
              cellStyle: const pw.TextStyle(fontSize: 9),
              cellPadding: const pw.EdgeInsets.all(6),
              headers: ['ID', 'Scenario', 'Statut', 'Technicien', 'Date'],
              data: missions.take(10).map((m) {
                String dateStr = '-';
                try {
                  final d = DateTime.parse((m['createdAt'] ?? m['date'] ?? '').toString()).toLocal();
                  dateStr = '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
                } catch (_) {}
                return [
                  (m['interventionId'] ?? m['_id'] ?? '-').toString().length > 12
                    ? '${(m['interventionId'] ?? m['_id'] ?? '-').toString().substring(0, 12)}...'
                    : (m['interventionId'] ?? m['_id'] ?? '-').toString(),
                  (m['scenarioLabel'] ?? m['scenario'] ?? '-').toString(),
                  (m['status'] ?? '-').toString(),
                  (m['technicianName'] ?? '-').toString(),
                  dateStr,
                ];
              }).toList(),
            ),
          pw.SizedBox(height: 24),

          // === PANNES (Archives) ===
          pw.Text('Historique des Pannes', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 10),
          if (pannes.isEmpty)
            pw.Text('Aucune panne archivee pour cette machine.', style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey600))
          else
            pw.Table.fromTextArray(
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 10),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.red800),
              cellStyle: const pw.TextStyle(fontSize: 9),
              cellPadding: const pw.EdgeInsets.all(6),
              headers: ['ID', 'Type de panne', 'Statut', 'Date'],
              data: pannes.take(10).map((p) {
                String dateStr = '-';
                try {
                  final d = DateTime.parse((p['resolvedAt'] ?? p['createdAt'] ?? p['date'] ?? '').toString()).toLocal();
                  dateStr = '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
                } catch (_) {}
                return [
                  (p['interventionId'] ?? p['_id'] ?? '-').toString().length > 12
                    ? '${(p['interventionId'] ?? p['_id'] ?? '-').toString().substring(0, 12)}...'
                    : (p['interventionId'] ?? p['_id'] ?? '-').toString(),
                  (p['scenarioLabel'] ?? p['typePanne'] ?? '-').toString(),
                  (p['status'] ?? 'Archive').toString(),
                  dateStr,
                ];
              }).toList(),
            ),
        ],
        footer: (context) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('ABBK - Maintenance Predictive', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey500)),
            pw.Text('Page ${context.pageNumber} / ${context.pagesCount}', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey500)),
          ],
        ),
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Fiche_$machineName.pdf',
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
                  'DÃ©mo : ajoutez des URLs de fichiers cÃ´tÃ© API pour activer le tÃ©lÃ©chargement.',
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

  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â• SIDEBAR â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  Widget _buildSidebar() {
    return Container(
      width: 256,
      color: _surfaceContainerLowest,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 180,
                  height: 46,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Image.asset(
                    'assets/images/abbk_logo.png',
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                  ),
                ),
              ],
            ),
          ),
          // Nav items
          _navItem(Icons.dashboard, 'Home', 0),
          _navItem(Icons.person_outline, 'Profil', 5),
          _navItem(Icons.precision_manufacturing, 'Mes Machines', 1),
          _navItem(Icons.auto_awesome, 'Analyse IA', 2),
          if (_navIndex == 2)
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _machinesFuture,
              builder: (context, snapshot) {
                if (!snapshot.hasData || snapshot.data!.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(left: 48, top: 4, bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: snapshot.data!.map((m) {
                      final id = _clientMachineId(m);
                      final name = _clientMachineName(m);
                      final isActive = _iaSelectedMachine != null && 
                                      (_clientMachineId(_iaSelectedMachine!) == id);
                      return InkWell(
                        onTap: () {
                          setState(() {
                            _iaSelectedMachine = m;
                          });
                        },
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                          child: Text(
                            '$name • $id',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: isActive ? _secondary : _onSurfaceVariant.withOpacity(0.6),
                              fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                );
              },
            ),
          _navItem(Icons.groups, 'Équipe Assignée', 3),
          _navItem(Icons.description, 'Documents Techniques', 4),
          if (MediaQuery.sizeOf(context).width >= 760)
            const Spacer()
          else
            const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _navItem(IconData icon, String label, int index) {
    final active = _navIndex == index;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          if (index == 1) {
            _openMesMachinesDirectly();
            return;
          }
          if (index == 2) {
            _openAnalyseIaDirectly();
            return;
          }
          setState(() {
            _navIndex = index;
            if (index == 2) _iaSelectedMachine = null;
            if (index == 4) _docSelectedMachine = null;
          });
        },
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

  Widget _buildSidebarStats() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _machinesFuture,
      builder: (context, snapshot) {
        final machines = snapshot.data ?? const <Map<String, dynamic>>[];
        final totalMachines = machines.length;
        final maintenanceCount = machines.where((m) {
          final active = m['maintenanceControlActive'] == true;
          final state = (m['state'] ?? m['status'] ?? '').toString().toLowerCase();
          return active ||
              state.contains('maintenance') ||
              state.contains('mainten');
        }).length;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: _surfaceContainerHigh.withOpacity(0.35),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _outlineVariant.withOpacity(0.22)),
          ),
          child: Column(
            children: [
              _sidebarStatItem(
                icon: Icons.precision_manufacturing,
                label: 'Total Machines',
                value: totalMachines.toString(),
              ),
              const SizedBox(height: 8),
              _sidebarStatItem(
                icon: Icons.groups_2_outlined,
                label: 'Total Techniciens',
                value: _isLoadingStats ? '..' : _techCount.toString(),
              ),
              const SizedBox(height: 8),
              _sidebarStatItem(
                icon: Icons.build_circle_outlined,
                label: 'En Maintenance',
                value: maintenanceCount.toString(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _sidebarStatItem({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Icon(icon, size: 16, color: _primary.withOpacity(0.95)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              color: _onSurfaceVariant.withOpacity(0.85),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Text(
          value,
          style: GoogleFonts.spaceGrotesk(
            fontSize: 13,
            color: _onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â• TOP BAR â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
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
                const Spacer(),
                // Icons
                _iconBtn(Icons.notifications_outlined),
                const SizedBox(width: 8),
                _iconBtn(Icons.settings_outlined),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _logoutClient,
                  icon: const Icon(Icons.logout, size: 16),
                  label: const Text('DÃ©connexion'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _error,
                    side: BorderSide(color: _error.withOpacity(0.45)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    textStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String get _currentClientName {
    final v =
        (ApiService.savedClientName ??
                widget.clientName ??
                widget.clientData?['name'] ??
                'Client')
            .toString()
            .trim();
    return v.isEmpty ? 'Client' : v;
  }

  String get _currentClientEmail {
    return (ApiService.savedClientEmail ?? widget.clientData?['email'] ?? '')
        .toString()
        .trim();
  }

  String get _currentClientLocation {
    final v =
        (ApiService.savedClientLocation ?? widget.clientData?['location'] ?? 'Tunis')
            .toString()
            .trim();
    return v.isEmpty ? 'Tunis' : v;
  }

  String get _currentClientPhotoUrl {
    final saved = (ApiService.savedClientPhotoUrl ?? '').toString().trim();
    if (saved.isNotEmpty) return saved;
    final client = widget.clientData ?? const <String, dynamic>{};
    const keys = [
      'photoUrl',
      'avatarUrl',
      'profilePhotoUrl',
      'imageUrl',
      'image',
      'photo',
      'avatar',
      'picture',
    ];
    for (final key in keys) {
      final v = (client[key] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  String get _currentClientBackgroundUrl {
    return (ApiService.savedClientBackgroundUrl ??
            widget.clientData?['backgroundUrl'] ??
            widget.clientData?['profileBackgroundUrl'] ??
            '')
        .toString()
        .trim();
  }

  String _imageMimeFromExtension(String? ext) {
    final e = (ext ?? '').toLowerCase().trim();
    switch (e) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'jpg':
      case 'jpeg':
      default:
        return 'image/jpeg';
    }
  }

  DecorationImage? _profileBackgroundDecorationImage() {
    final raw = _currentClientBackgroundUrl;
    if (raw.isEmpty) return null;
    if (raw.startsWith('data:image/')) {
      try {
        return DecorationImage(
          image: MemoryImage(base64Decode(raw.split(',').last)),
          fit: BoxFit.cover,
        );
      } catch (_) {
        return null;
      }
    }
    return DecorationImage(
      image: NetworkImage(raw),
      fit: BoxFit.cover,
    );
  }

  Widget _buildProfileBackgroundLayer() {
    final raw = _currentClientBackgroundUrl;
    if (raw.isEmpty) return const SizedBox.shrink();
    if (raw.startsWith('data:image/')) {
      try {
        return Image.memory(
          base64Decode(raw.split(',').last),
          fit: BoxFit.cover,
        );
      } catch (_) {
        return const SizedBox.shrink();
      }
    }
    return Image.network(
      raw,
      fit: BoxFit.cover,
      webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
    );
  }

  Future<void> _pickAndSaveClientPhoto() async {
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (picked == null || picked.files.isEmpty || !mounted) return;
      final f = picked.files.first;
      final bytes = f.bytes;
      if (bytes == null || bytes.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossible de lire le fichier image.')),
        );
        return;
      }
      if (bytes.lengthInBytes > 1500000) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Image trop volumineuse. Choisissez une image <= 1.5 MB.'),
          ),
        );
        return;
      }

      final mime = _imageMimeFromExtension(f.extension);
      final dataUrl = 'data:$mime;base64,${base64Encode(bytes)}';
      final clientId =
          (widget.clientId ??
                  widget.clientData?['clientId'] ??
                  widget.clientData?['id'] ??
                  ApiService.savedClientId ??
                  '')
              .toString()
              .trim();

      await ApiService.saveClientSession(
        clientId: clientId,
        clientName: _currentClientName,
        clientEmail: _currentClientEmail,
        clientLocation: _currentClientLocation,
        clientPhotoUrl: dataUrl,
        clientBackgroundUrl: _currentClientBackgroundUrl,
      );

      if (clientId.isNotEmpty) {
        try {
          await ApiService.updateClient(clientId, {
            'photoUrl': dataUrl,
            'avatarUrl': dataUrl,
            'profilePhotoUrl': dataUrl,
            'image': dataUrl,
          });
        } catch (_) {
          // Keep local photo even if backend update fails.
        }
      }

      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Photo de profil mise Ã  jour.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur choix photo: $e')),
      );
    }
  }

  Future<void> _openProfileBackgroundDialog() async {
    final urlCtrl = TextEditingController(text: _currentClientBackgroundUrl);
    final approved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surfaceContainerHigh,
        title: Text(
          'Background du profil',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
        content: TextField(
          controller: urlCtrl,
          decoration: InputDecoration(
            labelText: 'URL image background',
            hintText: 'https://.../background.jpg',
            prefixIcon: const Icon(Icons.wallpaper_outlined),
            filled: true,
            fillColor: _surfaceContainerLow,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    final bgUrl = urlCtrl.text.trim();
    final clientId =
        (widget.clientId ??
                widget.clientData?['clientId'] ??
                widget.clientData?['id'] ??
                ApiService.savedClientId ??
                '')
            .toString()
            .trim();
    await ApiService.saveClientSession(
      clientId: clientId,
      clientName: _currentClientName,
      clientEmail: _currentClientEmail,
      clientLocation: _currentClientLocation,
      clientPhotoUrl: _currentClientPhotoUrl,
      clientBackgroundUrl: bgUrl,
    );
    if (clientId.isNotEmpty) {
      try {
        await ApiService.updateClient(clientId, {
          'backgroundUrl': bgUrl,
          'profileBackgroundUrl': bgUrl,
        });
      } catch (_) {
        // Keep local setting if backend update fails.
      }
    }
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Background profil mis Ã  jour.')),
    );
  }

  Widget _buildClientProfileAvatar() {
    final initial = _currentClientName.isEmpty
        ? 'C'
        : _currentClientName[0].toUpperCase();
    if (_currentClientPhotoUrl.isEmpty) {
      return GestureDetector(
        onTap: _pickAndSaveClientPhoto,
        child: CircleAvatar(
          radius: 34,
          backgroundColor: _surfaceContainerHighest,
          child: Text(
            initial,
            style: GoogleFonts.inter(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: _primary,
            ),
          ),
        ),
      );
    }
    return GestureDetector(
      onTap: _pickAndSaveClientPhoto,
      child: ClipOval(
        child: SizedBox(
          width: 68,
          height: 68,
            child: _currentClientPhotoUrl.startsWith('data:image/')
                ? Image.memory(
                    base64Decode(_currentClientPhotoUrl.split(',').last),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) {
                      return CircleAvatar(
                        radius: 34,
                        backgroundColor: _surfaceContainerHighest,
                        child: Text(
                          initial,
                          style: GoogleFonts.inter(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: _primary,
                          ),
                        ),
                      );
                    },
                  )
                : Image.network(
                    _currentClientPhotoUrl,
                    fit: BoxFit.cover,
                    webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
                    errorBuilder: (_, __, ___) {
                      return CircleAvatar(
                        radius: 34,
                        backgroundColor: _surfaceContainerHighest,
                        child: Text(
                          initial,
                          style: GoogleFonts.inter(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: _primary,
                          ),
                        ),
                      );
                    },
                  ),
        ),
      ),
    );
  }

  Widget _buildMobileQuickActions() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
        color: _bg.withOpacity(0.85),
        border: Border(
          bottom: BorderSide(color: _outlineVariant.withOpacity(0.15)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _openNotificationsPopover(),
              icon: const Icon(Icons.notifications_outlined, size: 16),
              label: const Text('Notifications'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _onSurfaceVariant,
                side: BorderSide(color: _outlineVariant.withOpacity(0.45)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _openProfileSettingsDialog,
              icon: const Icon(Icons.settings_outlined, size: 16),
              label: const Text('ParamÃ¨tres'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _onSurfaceVariant,
                side: BorderSide(color: _outlineVariant.withOpacity(0.45)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _logoutClient,
              icon: const Icon(Icons.logout, size: 16),
              label: const Text('Quitter'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _error,
                side: BorderSide(color: _error.withOpacity(0.45)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _logoutClient() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('DÃ©connexion'),
        content: const Text('Voulez-vous vraiment vous dÃ©connecter ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Se dÃ©connecter'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    await ApiService.clearAuth();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  Future<void> _openProfileSettingsDialog() async {
    final nameCtrl = TextEditingController(text: _currentClientName);
    final emailCtrl = TextEditingController(text: _currentClientEmail);
    final locationCtrl = TextEditingController(text: _currentClientLocation);
    final photoCtrl = TextEditingController(text: _currentClientPhotoUrl);
    final approved = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: _surfaceContainerHigh,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: _outlineVariant.withOpacity(0.35)),
            ),
            titlePadding: const EdgeInsets.fromLTRB(18, 16, 18, 4),
            contentPadding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
            actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            title: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: _surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.manage_accounts_outlined,
                    size: 18,
                    color: _primaryLight,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'ParamÃ¨tres du profil',
                    style: GoogleFonts.inter(
                      color: _onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: (MediaQuery.of(ctx).size.width - 32).clamp(280.0, 420.0).toDouble(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Modifiez vos informations de compte client.',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: _onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: photoCtrl,
                    style: GoogleFonts.inter(color: _onSurface),
                    decoration: InputDecoration(
                      labelText: 'URL photo de profil',
                      hintText: 'https://.../photo.jpg',
                      prefixIcon: const Icon(Icons.image_outlined, size: 18),
                      filled: true,
                      fillColor: _surfaceContainerLow,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: nameCtrl,
                    style: GoogleFonts.inter(color: _onSurface),
                    decoration: InputDecoration(
                      labelText: 'Nom',
                      prefixIcon: const Icon(Icons.person_outline, size: 18),
                      filled: true,
                      fillColor: _surfaceContainerLow,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: emailCtrl,
                    style: GoogleFonts.inter(color: _onSurface),
                    decoration: InputDecoration(
                      labelText: 'Email',
                      prefixIcon: const Icon(Icons.alternate_email, size: 18),
                      filled: true,
                      fillColor: _surfaceContainerLow,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: locationCtrl,
                    style: GoogleFonts.inter(color: _onSurface),
                    decoration: InputDecoration(
                      labelText: 'Localisation',
                      prefixIcon: const Icon(Icons.location_on_outlined, size: 18),
                      filled: true,
                      fillColor: _surfaceContainerLow,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Annuler'),
              ),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(ctx, true),
                icon: const Icon(Icons.save_outlined, size: 18),
                label: const Text('Enregistrer'),
              ),
            ],
          ),
    );
    if (approved != true || !mounted) return;

    final name = nameCtrl.text.trim();
    final email = emailCtrl.text.trim();
    final location = locationCtrl.text.trim();
    final photoUrl = photoCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Le nom est obligatoire.')),
      );
      return;
    }

    try {
      final clientId =
          (widget.clientId ??
                  widget.clientData?['clientId'] ??
                  widget.clientData?['id'] ??
                  ApiService.savedClientId ??
                  '')
              .toString()
              .trim();
      await ApiService.saveClientSession(
        clientId: clientId,
        clientName: name,
        clientEmail: email,
        clientLocation: location,
        clientPhotoUrl: photoUrl,
        clientBackgroundUrl: _currentClientBackgroundUrl,
      );

      if (clientId.isNotEmpty) {
        try {
          await ApiService.updateClient(clientId, {
            'name': name,
            'email': email,
            'location': location,
            'photoUrl': photoUrl,
            'avatarUrl': photoUrl,
            'profilePhotoUrl': photoUrl,
            'image': photoUrl,
          });
        } catch (_) {
          // Keep local update even if remote update is unavailable for this role.
        }
      }

      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profil mis Ã  jour.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Mise Ã  jour impossible: $e')),
      );
    }
  }

  Future<void> _openNotificationsPopover({Offset? anchor}) async {
    setState(() {
      _unreadNotifications = 0;
    });

    final alerts = (widget.clientData?['alerts'] ?? 0).toString();
    final rows = _clientNotifications.isNotEmpty ? _clientNotifications : <Map<String, String>>[
      {
        'title': 'SantÃ© du site',
        'body': 'Le site est opÃ©rationnel. Alertes actives: $alerts.',
      },
      {
        'title': 'Machines',
        'body': 'Ouvrez "Mes Machines" pour voir les derniÃ¨res mises Ã  jour.',
      },
    ];

    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final relative =
        anchor != null
            ? RelativeRect.fromRect(
              Rect.fromLTWH(anchor.dx - 260, anchor.dy + 8, 320, 10),
              Offset.zero & overlay.size,
            )
            : RelativeRect.fromLTRB(
              overlay.size.width - 320,
              78,
              16,
              overlay.size.height - 220,
            );

    await showMenu<void>(
      context: context,
      position: relative,
      color: _surfaceContainerLow,
      elevation: 10,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: _outlineVariant.withOpacity(0.35)),
      ),
      items: [
        PopupMenuItem<void>(
          enabled: false,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: SizedBox(
            width: 300,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Notifications',
                  style: GoogleFonts.inter(
                    color: _onSurface,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 8),
                for (final n in rows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Icon(
                            Icons.notifications_active_outlined,
                            color: _primaryLight,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                n['title'] ?? '',
                                style: GoogleFonts.inter(
                                  color: _onSurface,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                n['body'] ?? '',
                                style: GoogleFonts.inter(
                                  color: _onSurfaceVariant,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _iconBtn(IconData icon) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTapDown: (details) {
          if (icon == Icons.notifications_outlined) {
            _openNotificationsPopover(anchor: details.globalPosition);
            return;
          }
          if (icon == Icons.settings_outlined) {
            _openProfileSettingsDialog();
          }
        },
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(icon, color: _onSurfaceVariant, size: 22),
              if (icon == Icons.notifications_outlined && _unreadNotifications > 0)
                Positioned(
                  top: -2,
                  right: -2,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: _primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: _bg, width: 1.5),
                    ),
                    constraints: const BoxConstraints(minWidth: 12, minHeight: 12),
                    child: Center(
                      child: Text(
                        _unreadNotifications > 9 ? '9+' : '$_unreadNotifications',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â• AI PREDICTIVE HEADER â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
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
                        'Score de SantÃ© Global (IA)',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: _onSurface,
                        ),
                      ),
                      Text(
                        'BasÃ© sur 1.2M de points de donnÃ©es/heure',
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
                    'OPTIMISÃ‰',
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
                            'Le site de ${widget.clientData?['location'] ?? 'Tunis'} prÃ©sente une stabilitÃ© supÃ©rieure Ã  la moyenne rÃ©gionale. Risque d\'arrÃªt critique : ',
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
                'MAINTENANCE PRÃ‰DICTIVE',
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
                  'Remplacement du roulement (PR-001) suggÃ©rÃ© dans 15 jours.',
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

  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â• KPI ROW â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
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
            _kpiCard(Icons.groups, 'Techniciens ConnectÃ©s', _isLoadingStats ? '..' : _techCount.toString().padLeft(2, '0'), _secondary,
                const Color(0xFF161626)),
            _kpiCard(Icons.warning, 'Alertes Actives', '01', _error,
                const Color(0xFF161626)),
            _kpiCard(Icons.check_circle, 'DisponibilitÃ© Site', '100%', _green,
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

  void _showConnectedCardsDialog() {
    final now = DateTime.now();
    final connectedCardIds = _lastTelemetryTime.entries
        .where((entry) => now.difference(entry.value).inSeconds < 60)
        .map((entry) => entry.key)
        .toList();

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: _surfaceContainerHigh,
          title: Row(
            children: [
              const Icon(Icons.developer_board_rounded, color: _primary),
              const SizedBox(width: 10),
              Text(
                'Cartes ESP32 ConnectÃ©es',
                style: GoogleFonts.inter(color: _onSurface, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: SizedBox(
            width: 400,
            height: 330,
            child: Column(
              children: [
                Expanded(
                  child: connectedCardIds.isEmpty
                      ? Center(
                          child: Text(
                            'Aucune carte ESP32 active dÃ©tectÃ©e rÃ©cemment.\n(En attente de rÃ©ception de messages via le Socket)',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(color: _onSurfaceVariant, fontSize: 13),
                          ),
                        )
                      : ListView.separated(
                          itemCount: connectedCardIds.length,
                          separatorBuilder: (_, __) => const Divider(),
                          itemBuilder: (context, index) {
                            final cardId = connectedCardIds[index];
                            return ListTile(
                              leading: const Icon(Icons.wifi_tethering_rounded, color: _green),
                              title: Text(
                                cardId,
                                style: GoogleFonts.spaceGrotesk(
                                  fontWeight: FontWeight.bold,
                                  color: _onSurface,
                                ),
                              ),
                              subtitle: Text(
                                'ActivitÃ© : il y a ${DateTime.now().difference(_lastTelemetryTime[cardId]!).inSeconds}s',
                                style: GoogleFonts.inter(color: _onSurfaceVariant, fontSize: 11),
                              ),
                              trailing: ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  _openWifiConfigDialog(context, cardId, isOnline: true);
                                },
                                icon: const Icon(Icons.settings, size: 14),
                                label: const Text('Config'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _secondary,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                ),
                              ),
                            );
                          },
                        ),
                ),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Statut Socket :',
                        style: GoogleFonts.inter(fontSize: 11, color: _onSurfaceVariant),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _socket.connected ? _green.withOpacity(0.2) : _error.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _socket.connected ? 'CONNECTÃ‰' : 'DÃ‰CONNECTÃ‰',
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: _socket.connected ? _green : _error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'URL : ${ApiService.socketBaseUrl}',
                    style: GoogleFonts.spaceGrotesk(fontSize: 9, color: _onSurfaceVariant.withOpacity(0.7)),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Fermer', style: TextStyle(color: _onSurfaceVariant)),
            ),
          ],
        );
      },
    );
  }

  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â• MACHINE LIST â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•



  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â• MACHINE LIST SECTION â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
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
                  'Ã‰TAT DE LA FLOTTE',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    color: _secondary,
                    letterSpacing: 2.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Machines ConnectÃ©es',
                  style: GoogleFonts.inter(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: _onSurface,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _showConnectedCardsDialog,
                  icon: const Icon(Icons.developer_board_rounded, size: 16),
                  label: const Text('Cartes ConnectÃ©es'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _actionBtn(Icons.refresh, _onSurfaceVariant, _refreshMachines),
              ],
            ),
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
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                'Techniciens disponibles pour votre site',
                style: GoogleFonts.inter(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: _onSurface,
                  letterSpacing: -0.5,
                ),
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: _openAddTechnicianRequestDialog,
              style: ElevatedButton.styleFrom(
                backgroundColor: _primary,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
              label: Text(
                'Demander un technicien',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 10),
            ElevatedButton.icon(
              onPressed: () => _openAddTechnicianRequestDialog(
                requestType: 'MAINTENANCE_ADD',
                roleLabel: 'maintenance man',
                requestedSpecialty: 'Maintenance opÃ©rationnelle',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _secondary,
                foregroundColor: Colors.black,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.build_circle_outlined, size: 18),
              label: Text(
                'Demander maintenance man',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
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
                  'Erreur chargement Ã©quipe: ${snapshot.error}',
                  style: const TextStyle(color: _error),
                ),
              );
            }

            final teamMembers = snapshot.data ?? [];
            if (teamMembers.isEmpty) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _outlineVariant.withOpacity(0.2)),
                ),
                child: Text(
                  'Aucun technicien assignÃ© Ã  ce client pour le moment.',
                  style: GoogleFonts.inter(fontSize: 14, color: _onSurfaceVariant),
                ),
              );
            }

            final technicians = teamMembers.where((member) {
              final role = (member['roleType'] ?? member['role'] ?? '')
                  .toString()
                  .toLowerCase();
              return role != 'maintenance';
            }).toList();
            final maintenanceMen = teamMembers.where((member) {
              final role = (member['roleType'] ?? member['role'] ?? '')
                  .toString()
                  .toLowerCase();
              return role == 'maintenance';
            }).toList();

            Widget buildSectionTitle(String title, IconData icon) {
              return Row(
                children: [
                  Icon(icon, size: 16, color: _secondary),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: _onSurface,
                    ),
                  ),
                ],
              );
            }

            Widget buildTeamCard(Map<String, dynamic> member, {required bool isMaintenance}) {
              final imageUrl = (member['avatarUrl'] ??
                      member['photoUrl'] ??
                      member['profilePicture'] ??
                      '')
                  .toString()
                  .trim();
              final hasAvatar = imageUrl.startsWith('http');
              final name = (member['name'] ?? (isMaintenance ? 'Maintenance man' : 'Technicien'))
                  .toString();
              final specialization =
                  (member['specialization'] ??
                          member['speciality'] ??
                          (isMaintenance ? 'Maintenance operationnelle' : 'Maintenance terrain'))
                      .toString();
              final status = (member['status'] ?? 'Disponible').toString();
              final email = (member['email'] ?? '').toString().trim();

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
                      backgroundImage: hasAvatar ? NetworkImage(imageUrl) : null,
                      child: hasAvatar
                          ? null
                          : Icon(
                              isMaintenance ? Icons.build_circle_outlined : Icons.engineering,
                              color: _onSurfaceVariant,
                            ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: _onSurface,
                            ),
                          ),
                          Text(
                            '$specialization â€¢ $status',
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 11,
                              color: _onSurfaceVariant,
                            ),
                          ),
                          if (email.isNotEmpty)
                            Text(
                              email,
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: _onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _openMessageEquipeDialog(member),
                      icon: const Icon(Icons.message_outlined, size: 16),
                      label: const Text('Message'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () => _startCall(member),
                      icon: const Icon(Icons.call_outlined, size: 16),
                      label: const Text('Appel'),
                    ),
                  ],
                ),
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                buildSectionTitle('Technicien', Icons.engineering),
                const SizedBox(height: 10),
                if (technicians.isEmpty)
                  Text(
                    'Aucun technicien assigne.',
                    style: GoogleFonts.inter(fontSize: 12, color: _onSurfaceVariant),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: technicians.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) => buildTeamCard(technicians[i], isMaintenance: false),
                  ),
                const SizedBox(height: 20),
                buildSectionTitle('Maintenance man', Icons.build_circle_outlined),
                const SizedBox(height: 10),
                if (maintenanceMen.isEmpty)
                  Text(
                    'Aucun maintenance man assigne.',
                    style: GoogleFonts.inter(fontSize: 12, color: _onSurfaceVariant),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: maintenanceMen.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) => buildTeamCard(maintenanceMen[i], isMaintenance: true),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Future<void> _openAddTechnicianRequestDialog({
    String requestType = 'TECHNICIAN_ADD',
    String roleLabel = 'technicien',
    String requestedSpecialty = 'Maintenance terrain',
  }) async {
    final clientId =
        (widget.clientId ??
                widget.clientData?['clientId'] ??
                widget.clientData?['id'] ??
                ApiService.savedClientId ??
                '')
            .toString()
            .trim();

    List<Map<String, dynamic>> clientMachines = const [];
    try {
      if (clientId.isNotEmpty) {
        clientMachines = await ApiService.getMachinesForClient(clientId);
      }
    } catch (_) {}

    if (!mounted) return;

    final lastNameCtrl = TextEditingController();
    final firstNameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final locationCtrl = TextEditingController(text: _currentClientLocation);
    final descriptionCtrl = TextEditingController();
    final selectedMachineIds = <String>{};
    if (clientMachines.isNotEmpty) {
      final firstId = (clientMachines.first['_id'] ??
              clientMachines.first['id'] ??
              clientMachines.first['machineId'] ??
              '')
          .toString();
      if (firstId.isNotEmpty) selectedMachineIds.add(firstId);
    }

    final approved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return Dialog(
              backgroundColor: _surfaceContainerHigh,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 560,
                  maxHeight: MediaQuery.of(ctx).size.height * 0.9,
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: _primary.withOpacity(0.18),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.engineering_rounded,
                              color: _primary,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Demande d\'ajout $roleLabel',
                                  style: GoogleFonts.inter(
                                    color: _onSurface,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 17,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'EnvoyÃ©e au Concepteur pour validation.',
                                  style: GoogleFonts.spaceGrotesk(
                                    color: _onSurfaceVariant,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Fermer',
                            onPressed: () => Navigator.of(ctx).pop(false),
                            icon: const Icon(Icons.close_rounded, color: _onSurfaceVariant),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _buildRequestField(
                              controller: lastNameCtrl,
                              label: 'Nom *',
                              hint: 'Ex: Hemli',
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _buildRequestField(
                              controller: firstNameCtrl,
                              label: 'PrÃ©nom *',
                              hint: 'Ex: Morad',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildRequestField(
                        controller: emailCtrl,
                        label: 'Email *',
                        hint: '$roleLabel@entreprise.com',
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _buildRequestField(
                              controller: phoneCtrl,
                              label: 'TÃ©lÃ©phone (optionnel)',
                              hint: '+216 ...',
                              keyboardType: TextInputType.phone,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _buildRequestField(
                              controller: locationCtrl,
                              label: 'Localisation',
                              hint: 'Ex: Sousse',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildRequestField(
                        controller: descriptionCtrl,
                        label: 'Description technique (optionnel)',
                        hint: 'CompÃ©tences attendues, besoin urgent...',
                        minLines: 2,
                        maxLines: 4,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Text(
                            'Machines concernÃ©es',
                            style: GoogleFonts.inter(
                              color: _onSurface,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: _primary.withOpacity(0.18),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '${selectedMachineIds.length} sÃ©lectionnÃ©e(s)',
                              style: GoogleFonts.spaceGrotesk(
                                color: _primary,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        constraints: const BoxConstraints(maxHeight: 180),
                        decoration: BoxDecoration(
                          color: _surfaceContainerLow,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _outlineVariant.withOpacity(0.25)),
                        ),
                        child: clientMachines.isEmpty
                            ? Padding(
                                padding: const EdgeInsets.all(14),
                                child: Text(
                                  'Aucune machine n\'est encore associÃ©e Ã  votre compte.',
                                  style: GoogleFonts.inter(
                                    color: _onSurfaceVariant,
                                    fontSize: 12,
                                  ),
                                ),
                              )
                            : ListView.separated(
                                shrinkWrap: true,
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                itemCount: clientMachines.length,
                                separatorBuilder: (_, __) => Divider(
                                  height: 1,
                                  color: _outlineVariant.withOpacity(0.18),
                                ),
                                itemBuilder: (_, i) {
                                  final m = clientMachines[i];
                                  final id = (m['_id'] ?? m['id'] ?? m['machineId'] ?? '').toString();
                                  final name = (m['name'] ?? m['title'] ?? id).toString();
                                  final business = (m['machineId'] ?? m['idBusiness'] ?? '').toString();
                                  final isSelected = selectedMachineIds.contains(id);
                                  return CheckboxListTile(
                                    dense: true,
                                    value: isSelected,
                                    onChanged: id.isEmpty
                                        ? null
                                        : (v) {
                                            setDialogState(() {
                                              if (v == true) {
                                                selectedMachineIds.add(id);
                                              } else {
                                                selectedMachineIds.remove(id);
                                              }
                                            });
                                          },
                                    activeColor: _primary,
                                    checkColor: Colors.white,
                                    controlAffinity: ListTileControlAffinity.leading,
                                    title: Text(
                                      name,
                                      style: GoogleFonts.inter(
                                        color: _onSurface,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    subtitle: business.isEmpty
                                        ? null
                                        : Text(
                                            business,
                                            style: GoogleFonts.spaceGrotesk(
                                              color: _onSurfaceVariant,
                                              fontSize: 10,
                                            ),
                                          ),
                                  );
                                },
                              ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(false),
                            child: Text(
                              'Annuler',
                              style: GoogleFonts.inter(
                                color: _onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            onPressed: () => Navigator.of(ctx).pop(true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 22,
                                vertical: 14,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            icon: const Icon(Icons.send_rounded, size: 16),
                            label: Text(
                              'Envoyer la demande',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (!mounted || approved != true) {
      lastNameCtrl.dispose();
      firstNameCtrl.dispose();
      emailCtrl.dispose();
      phoneCtrl.dispose();
      locationCtrl.dispose();
      descriptionCtrl.dispose();
      return;
    }

    final lastName = lastNameCtrl.text.trim();
    final firstName = firstNameCtrl.text.trim();
    final email = emailCtrl.text.trim();
    final phone = phoneCtrl.text.trim();
    final location = locationCtrl.text.trim();
    final description = descriptionCtrl.text.trim();

    lastNameCtrl.dispose();
    firstNameCtrl.dispose();
    emailCtrl.dispose();
    phoneCtrl.dispose();
    locationCtrl.dispose();
    descriptionCtrl.dispose();

    if (lastName.isEmpty || firstName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Le nom et le prÃ©nom sont obligatoires.')),
      );
      return;
    }
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('L\'email est obligatoire.')),
      );
      return;
    }
    if (selectedMachineIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('SÃ©lectionnez au moins une machine concernÃ©e.')),
      );
      return;
    }

    final firstMachineId = selectedMachineIds.first;

    try {
      await ApiService.createPurchaseRequest({
        'machineId': firstMachineId,
        if (clientId.isNotEmpty) 'linkedClientId': clientId,
        'requesterName': '$firstName $lastName',
        'requesterEmail': email,
        'requesterPhone': phone,
        'location': location,
        'note': description,
        'requestType': requestType,
        'requestedSpecialty': requestedSpecialty,
        'requestedMachineIds': selectedMachineIds.toList(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Demande de $roleLabel envoyÃ©e au Concepteur.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ã‰chec de l\'envoi: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildRequestField({
    required TextEditingController controller,
    required String label,
    String? hint,
    int minLines = 1,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            color: _onSurfaceVariant,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          minLines: minLines,
          maxLines: maxLines,
          style: GoogleFonts.inter(color: _onSurface, fontSize: 13),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.inter(
              color: _onSurfaceVariant.withOpacity(0.6),
              fontSize: 12,
            ),
            isDense: true,
            filled: true,
            fillColor: _surfaceContainerLow,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: _outlineVariant.withOpacity(0.3)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: _outlineVariant.withOpacity(0.3)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _primary, width: 1.4),
            ),
          ),
        ),
      ],
    );
  }

  String _formatChatTime(dynamic raw) {
    final dt = DateTime.tryParse((raw ?? '').toString());
    if (dt == null) return '--:--';
    final local = dt.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _openMessageEquipeDialog(Map<String, dynamic> technician) async {
    final techId = (technician['technicianId'] ?? technician['agentId'] ?? technician['_id'] ?? 'tech').toString();
    final clientKey = (widget.clientId ?? widget.clientData?['clientId'] ?? widget.clientData?['id'] ?? 'client').toString();
    final roomId = 'chat_${clientKey}_$techId';
    final techName = (technician['name'] ?? 'Technicien').toString();
    final techSpeciality = (technician['specialization'] ?? technician['specialite'] ?? technician['role'] ?? 'Technicien').toString();
    final techPhotoUrl = (technician['imageUrl'] ?? technician['photoUrl'] ?? '').toString();
    final input = TextEditingController();
    final scrollController = ScrollController();

    void scrollToBottom() {
      Future.delayed(const Duration(milliseconds: 80), () {
        if (scrollController.hasClients) {
          scrollController.animateTo(
            scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }

    _socket.emit('join_chat_room', {'roomId': roomId});

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.65),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final messages = List<Map<String, dynamic>>.from(_chatMessages[roomId] ?? const []);

            void sendMessage() {
              final text = input.text.trim();
              if (text.isEmpty) return;
              final localMessage = <String, dynamic>{
                'roomId': roomId,
                'from': 'client',
                'senderName': widget.clientName ?? 'Client',
                'text': text,
                'createdAt': DateTime.now().toIso8601String(),
              };
              setState(() {
                final list = _chatMessages.putIfAbsent(roomId, () => []);
                list.add(localMessage);
              });
              _socket.emit('chat_message', {
                'roomId': roomId,
                'from': 'client',
                'senderName': widget.clientName ?? 'Client',
                'text': text,
              });
              input.clear();
              setDialogState(() {});
              scrollToBottom();
            }

            // Initial scroll
            if (messages.isNotEmpty) scrollToBottom();

            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Container(
                width: (MediaQuery.of(ctx).size.width - 40).clamp(320.0, 600.0).toDouble(),
                height: (MediaQuery.of(ctx).size.height * 0.80).clamp(480.0, 680.0).toDouble(),
                decoration: BoxDecoration(
                  color: const Color(0xFF13132B),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFF2E2E55), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: _primary.withOpacity(0.15),
                      blurRadius: 40,
                      spreadRadius: -4,
                      offset: const Offset(0, 8),
                    ),
                    BoxShadow(
                      color: Colors.black.withOpacity(0.6),
                      blurRadius: 24,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // â”€â”€ Header â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                    Container(
                      padding: const EdgeInsets.fromLTRB(18, 16, 12, 16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            const Color(0xFF1C1C3A),
                            const Color(0xFF1A1A32),
                          ],
                        ),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(24),
                          topRight: Radius.circular(24),
                        ),
                        border: const Border(
                          bottom: BorderSide(color: Color(0xFF2E2E55), width: 1),
                        ),
                      ),
                      child: Row(
                        children: [
                          // Avatar with online dot
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: _primary.withOpacity(0.5), width: 2),
                                  boxShadow: [
                                    BoxShadow(
                                      color: _primary.withOpacity(0.2),
                                      blurRadius: 10,
                                    ),
                                  ],
                                ),
                                child: CircleAvatar(
                                  radius: 22,
                                  backgroundColor: const Color(0xFF2A2A4A),
                                  backgroundImage: techPhotoUrl.isNotEmpty
                                      ? NetworkImage(techPhotoUrl)
                                      : null,
                                  child: techPhotoUrl.isEmpty
                                      ? Text(
                                          techName.isNotEmpty ? techName[0].toUpperCase() : 'T',
                                          style: GoogleFonts.spaceGrotesk(
                                            color: _primary,
                                            fontWeight: FontWeight.w800,
                                            fontSize: 18,
                                          ),
                                        )
                                      : null,
                                ),
                              ),
                              Positioned(
                                bottom: 1,
                                right: 1,
                                child: Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF4CAF50),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: const Color(0xFF13132B), width: 2),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF4CAF50).withOpacity(0.5),
                                        blurRadius: 6,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  techName,
                                  style: GoogleFonts.spaceGrotesk(
                                    color: _onSurface,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                    letterSpacing: -0.3,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: const BoxDecoration(
                                        color: Color(0xFF4CAF50),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      'En ligne Â· $techSpeciality',
                                      style: GoogleFonts.inter(
                                        color: _onSurfaceVariant,
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          // Close button
                          Material(
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => Navigator.of(ctx).pop(),
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF2E2E55),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.close_rounded,
                                  color: Color(0xFFB0B0D0),
                                  size: 18,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // â”€â”€ Messages area â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                    Expanded(
                      child: messages.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(20),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1C1C3A),
                                      shape: BoxShape.circle,
                                      border: Border.all(color: const Color(0xFF2E2E55)),
                                    ),
                                    child: Icon(
                                      Icons.chat_bubble_outline_rounded,
                                      color: _onSurfaceVariant.withOpacity(0.5),
                                      size: 32,
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  Text(
                                    'DÃ©marrez la conversation',
                                    style: GoogleFonts.spaceGrotesk(
                                      color: _onSurface.withOpacity(0.7),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Envoyez un message Ã  $techName',
                                    style: GoogleFonts.inter(
                                      color: _onSurfaceVariant,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              controller: scrollController,
                              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                              itemCount: messages.length,
                              itemBuilder: (_, i) {
                                final msg = messages[i];
                                final isMine = (msg['from'] ?? '').toString() == 'client';
                                final text = (msg['text'] ?? '').toString();
                                final time = _formatChatTime(msg['createdAt']);

                                // Show date separator if needed
                                final showDate = i == 0;

                                return Column(
                                  children: [
                                    if (showDate)
                                      Padding(
                                        padding: const EdgeInsets.only(bottom: 16),
                                        child: Row(
                                          children: [
                                            Expanded(child: Container(height: 1, color: const Color(0xFF2E2E55))),
                                            Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 10),
                                              child: Text(
                                                'Aujourd\'hui',
                                                style: GoogleFonts.inter(
                                                  color: _onSurfaceVariant,
                                                  fontSize: 10.5,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                            Expanded(child: Container(height: 1, color: const Color(0xFF2E2E55))),
                                          ],
                                        ),
                                      ),
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: Row(
                                        mainAxisAlignment: isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          // Other person avatar
                                          if (!isMine) ...[
                                            CircleAvatar(
                                              radius: 14,
                                              backgroundColor: const Color(0xFF2A2A4A),
                                              backgroundImage: techPhotoUrl.isNotEmpty
                                                  ? NetworkImage(techPhotoUrl)
                                                  : null,
                                              child: techPhotoUrl.isEmpty
                                                  ? Text(
                                                      techName.isNotEmpty ? techName[0].toUpperCase() : 'T',
                                                      style: GoogleFonts.inter(
                                                        color: _primary,
                                                        fontWeight: FontWeight.w700,
                                                        fontSize: 11,
                                                      ),
                                                    )
                                                  : null,
                                            ),
                                            const SizedBox(width: 8),
                                          ],
                                          // Message bubble
                                          Flexible(
                                            child: Container(
                                              constraints: BoxConstraints(
                                                maxWidth: MediaQuery.of(ctx).size.width * 0.55,
                                              ),
                                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                              decoration: BoxDecoration(
                                                gradient: isMine
                                                    ? LinearGradient(
                                                        begin: Alignment.topLeft,
                                                        end: Alignment.bottomRight,
                                                        colors: [
                                                          _primary,
                                                          const Color(0xFFE55A00),
                                                        ],
                                                      )
                                                    : null,
                                                color: isMine ? null : const Color(0xFF1E1E3F),
                                                borderRadius: BorderRadius.only(
                                                  topLeft: const Radius.circular(18),
                                                  topRight: const Radius.circular(18),
                                                  bottomLeft: Radius.circular(isMine ? 18 : 4),
                                                  bottomRight: Radius.circular(isMine ? 4 : 18),
                                                ),
                                                border: isMine
                                                    ? null
                                                    : Border.all(color: const Color(0xFF2E2E55), width: 1),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: (isMine ? _primary : Colors.black).withOpacity(0.2),
                                                    blurRadius: 8,
                                                    offset: const Offset(0, 2),
                                                  ),
                                                ],
                                              ),
                                              child: Column(
                                                crossAxisAlignment: isMine
                                                    ? CrossAxisAlignment.end
                                                    : CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    text,
                                                    style: GoogleFonts.inter(
                                                      color: isMine ? Colors.white : _onSurface,
                                                      fontSize: 13.5,
                                                      height: 1.4,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Text(
                                                        time,
                                                        style: GoogleFonts.inter(
                                                          color: isMine
                                                              ? Colors.white.withOpacity(0.65)
                                                              : _onSurfaceVariant,
                                                          fontSize: 9.5,
                                                        ),
                                                      ),
                                                      if (isMine) ...[
                                                        const SizedBox(width: 4),
                                                        Icon(
                                                          Icons.done_all_rounded,
                                                          size: 12,
                                                          color: Colors.white.withOpacity(0.65),
                                                        ),
                                                      ],
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          // My avatar
                                          if (isMine) ...[
                                            const SizedBox(width: 8),
                                            CircleAvatar(
                                              radius: 14,
                                              backgroundColor: _primaryContainer,
                                              child: Text(
                                                (widget.clientName ?? 'C').isNotEmpty
                                                    ? (widget.clientName ?? 'C')[0].toUpperCase()
                                                    : 'C',
                                                style: GoogleFonts.inter(
                                                  color: _primary,
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                    ),

                    // â”€â”€ Input area â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                    Container(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F0F20),
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(24),
                          bottomRight: Radius.circular(24),
                        ),
                        border: const Border(
                          top: BorderSide(color: Color(0xFF2E2E55), width: 1),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          // Emoji button
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10, right: 6),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: () {},
                                child: Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: Icon(
                                    Icons.emoji_emotions_outlined,
                                    color: _onSurfaceVariant.withOpacity(0.6),
                                    size: 22,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          // Text field
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFF1A1A35),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: const Color(0xFF2E2E55), width: 1),
                              ),
                              child: TextField(
                                controller: input,
                                minLines: 1,
                                maxLines: 4,
                                style: GoogleFonts.inter(
                                  color: _onSurface,
                                  fontSize: 13.5,
                                ),
                                decoration: InputDecoration(
                                  hintText: 'Ã‰crire un message...',
                                  hintStyle: GoogleFonts.inter(
                                    color: _onSurfaceVariant.withOpacity(0.45),
                                    fontSize: 13.5,
                                  ),
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 11,
                                  ),
                                  suffixIcon: Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: Icon(
                                      Icons.attach_file_rounded,
                                      color: _onSurfaceVariant.withOpacity(0.4),
                                      size: 20,
                                    ),
                                  ),
                                ),
                                onSubmitted: (_) => sendMessage(),
                                onChanged: (_) => setDialogState(() {}),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          // Send button
                          ValueListenableBuilder<TextEditingValue>(
                            valueListenable: input,
                            builder: (_, val, __) {
                              final hasText = val.text.trim().isNotEmpty;
                              return AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                curve: Curves.easeInOut,
                                width: 46,
                                height: 46,
                                decoration: BoxDecoration(
                                  gradient: hasText
                                      ? LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: [_primary, const Color(0xFFE55A00)],
                                        )
                                      : null,
                                  color: hasText ? null : const Color(0xFF1E1E3F),
                                  shape: BoxShape.circle,
                                  boxShadow: hasText
                                      ? [
                                          BoxShadow(
                                            color: _primary.withOpacity(0.4),
                                            blurRadius: 12,
                                            spreadRadius: -2,
                                          ),
                                        ]
                                      : null,
                                ),
                                child: Material(
                                  color: Colors.transparent,
                                  shape: const CircleBorder(),
                                  child: InkWell(
                                    customBorder: const CircleBorder(),
                                    onTap: hasText ? sendMessage : null,
                                    child: Center(
                                      child: AnimatedSwitcher(
                                        duration: const Duration(milliseconds: 200),
                                        child: Icon(
                                          Icons.send_rounded,
                                          key: ValueKey(hasText),
                                          color: hasText
                                              ? Colors.white
                                              : _onSurfaceVariant.withOpacity(0.4),
                                          size: 20,
                                        ),
                                      ),
                                    ),
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
            );
          },
        );
      },
    );
    input.dispose();
    scrollController.dispose();
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
      SnackBar(content: Text('Demande d\'appel envoyÃ©e Ã  ${(technician['name'] ?? 'Technicien')}')),
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
          Text('Aucune machine n\'est encore assignÃ©e.', style: GoogleFonts.inter(fontSize: 16, color: _onSurface, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text('Le Super Admin doit enregistrer vos Ã©quipements pour activer la surveillance.', style: GoogleFonts.inter(fontSize: 13, color: _onSurfaceVariant), textAlign: TextAlign.center),
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

    void openMachineDetail() {
      final mid = _clientMachineId(m);
      final name = _clientMachineName(m);
      showGeneralDialog(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'Fermer',
        barrierColor: Colors.black.withOpacity(0.75),
        transitionDuration: const Duration(milliseconds: 320),
        transitionBuilder: (ctx, anim, secondAnim, child) {
          final curve = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
          return SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero).animate(curve),
            child: FadeTransition(opacity: curve, child: child),
          );
        },
        pageBuilder: (ctx, anim, secondAnim) {
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isDesktop ? 48 : 12,
                vertical: isDesktop ? 32 : 16,
              ),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF10102B),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: _secondary.withOpacity(0.25), width: 1.2),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.55), blurRadius: 40, offset: const Offset(0, 12)),
                    ],
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                        decoration: BoxDecoration(
                          color: _surfaceContainerLow,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(22),
                            topRight: Radius.circular(22),
                          ),
                          border: Border(bottom: BorderSide(color: _secondary.withOpacity(0.18))),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: (isAlert ? _error : _green).withOpacity(0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(Icons.precision_manufacturing, color: isAlert ? _error : _green, size: 24),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: _onSurface),
                                  ),
                                  Text(
                                    'ID: $mid',
                                    style: GoogleFonts.spaceGrotesk(fontSize: 11, color: _secondary, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.of(ctx).pop(),
                              icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 22),
                              tooltip: 'Fermer',
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: const BorderRadius.only(
                            bottomLeft: Radius.circular(22),
                            bottomRight: Radius.circular(22),
                          ),
                          child: MachineDetailAiPage(
                            machineId: mid,
                            machineName: name,
                            clientId: widget.clientId ?? widget.clientData?['clientId'] ?? widget.clientData?['id'],
                            viewerRole: 'client',
                            viewerName: (widget.clientName ?? 'Client').toString(),
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
      );
    }

    return InkWell(
      onTap: openMachineDetail,
      borderRadius: BorderRadius.circular(20),
      child: Container(
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
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: _primary.withOpacity(0.2), borderRadius: BorderRadius.circular(4)),
                          child: Text(
                            '${(_realtimeTemps[machineRealtimeId] ?? 0.0).toStringAsFixed(1)}°C',
                            style: GoogleFonts.spaceGrotesk(fontSize: 10, fontWeight: FontWeight.bold, color: _primary),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Vib: ${(_realtimeVibrations[machineRealtimeId] ?? 0.0).toStringAsFixed(1)} mm/s  •  Fric: ${(_realtimeFrictions[machineRealtimeId] ?? 0.0).toStringAsFixed(2)}  •  Volt: ${(_realtimePressures[machineRealtimeId] ?? 0.0).toStringAsFixed(1)} V   •   Risque: ${(_realtimeRisks[machineRealtimeId] ?? 0.0).toStringAsFixed(1)}%',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 10,
                        color: _secondary.withOpacity(0.9),
                      ),
                    ),
                  ],
                ),
              ),
              _scoreBox('ALERTS', '${m['alerts'] ?? 0}', isAlert ? _error : _green),
              const SizedBox(width: 12),
              Builder(
                builder: (context) {
                  final lastTelTime = _lastTelemetryTime[machineRealtimeId];
                  final hasValues = _realtimeVibrations.containsKey(machineRealtimeId) || _realtimeTemps.containsKey(machineRealtimeId);
                  final isOnline = hasValues || (lastTelTime != null &&
                      DateTime.now().difference(lastTelTime).inSeconds < 10);
                  return _actionBtn(
                    Icons.wifi_rounded,
                    isOnline ? _green : _error,
                    () {
                      _openWifiConfigDialog(context, machineRealtimeId, isOnline: isOnline);
                    },
                    iconColor: isOnline ? _green : _error,
                  );
                }
              ),
              const SizedBox(width: 12),
              _actionBtn(Icons.arrow_forward, _secondary, openMachineDetail),
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
                      'Maintenance en contrÃ´le${controlBy.isNotEmpty ? ' Â· $controlBy' : ''}',
                      style: GoogleFonts.inter(
                        color: _onSurface,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Text(
                    'Temps contrÃ´le: ${_formatElapsed(elapsed)}',
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
    ), // end Container
    ); // end InkWell
  }

  Future<void> _openWifiConfigDialog(BuildContext context, String machineId, {required bool isOnline}) async {
    final ssidCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final idCtrl = TextEditingController(text: machineId);

    final success = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: _surfaceContainerHigh,
          title: Row(
            children: [
              Icon(isOnline ? Icons.wifi_rounded : Icons.wifi_lock_rounded, color: isOnline ? _green : _primary),
              const SizedBox(width: 10),
              Text(
                'Configuration WiFi & ID ESP32',
                style: GoogleFonts.inter(color: _onSurface, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isOnline
                    ? 'La machine est actuellement connectÃ©e. Vous pouvez mettre Ã  jour son ID et ses paramÃ¨tres WiFi Ã  distance.'
                    : 'Connectez d\'abord votre appareil au rÃ©seau WiFi "DALI-Config" de l\'ESP32, puis remplissez ce formulaire.',
                style: GoogleFonts.inter(color: _onSurfaceVariant, fontSize: 12),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: idCtrl,
                enabled: true,
                decoration: const InputDecoration(
                  labelText: 'ID de la Machine *',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ssidCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nom du RÃ©seau WiFi (SSID) *',
                  hintText: 'ex: MaBoxInternet',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Mot de passe WiFi *',
                  isDense: true,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Annuler', style: TextStyle(color: _onSurfaceVariant)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: _primary, foregroundColor: Colors.white),
              child: const Text('Envoyer'),
            ),
          ],
        );
      },
    );

    if (success == true) {
      final ssid = ssidCtrl.text.trim();
      final pass = passCtrl.text.trim();
      final newId = idCtrl.text.trim();

      if (ssid.isEmpty || pass.isEmpty || newId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('L\'ID, le SSID et le mot de passe sont obligatoires.'),
            backgroundColor: _error,
          ),
        );
        return;
      }

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const Center(child: CircularProgressIndicator(color: _primary)),
      );

      try {
        await ApiService.configureMachineWifi(machineId, ssid, pass, newMachineId: newId);
        if (!mounted) return;
        Navigator.pop(context); // Close loading indicator
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Configuration envoyÃ©e ! L\'ESP32 va redÃ©marrer avec son nouvel ID.'),
            backgroundColor: _green,
          ),
        );
      } catch (e) {
        if (!mounted) return;
        Navigator.pop(context); // Close loading indicator
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ã‰chec de la configuration : ${e.toString().replaceAll('Exception: ', '')}'),
            backgroundColor: _error,
          ),
        );
      }
    }
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
                              text: 'Surchauffe Moteur DÃ©tectÃ©e',
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
                                  text: 'DÃ©tectÃ©e',
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

  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â• HELPERS â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
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

  Widget _actionBtn(IconData icon, Color hoverColor, VoidCallback onTap, {Color? iconColor}) {
    return Material(
      color: _surfaceContainerHighest,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        hoverColor: hoverColor.withOpacity(0.1),
        child: Container(
          padding: const EdgeInsets.all(12),
          child: Icon(icon, size: 20, color: iconColor ?? _onSurface),
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

class _ClientPublicMachineCard extends StatelessWidget {
  const _ClientPublicMachineCard({
    required this.machine,
    required this.onBuy,
    this.onRequireLogin,
  });

  final Map<String, dynamic> machine;
  final VoidCallback onBuy;
  final Future<void> Function()? onRequireLogin;

  Future<void> _runIfAuthenticated(
    BuildContext context,
    VoidCallback action,
  ) async {
    final ok = await ensureClientLoggedIn(
      context,
      openLogin: onRequireLogin,
    );
    if (ok) action();
  }

  bool _looksLikeNetworkImage(String value) {
    final v = value.trim().toLowerCase();
    return v.startsWith('http://') || v.startsWith('https://');
  }

  bool _looksLikeDataImage(String value) {
    final v = value.trim().toLowerCase();
    return v.startsWith('data:image/');
  }

  String _normalizeMachineImageValue(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';
    if (_looksLikeNetworkImage(trimmed) || _looksLikeDataImage(trimmed)) {
      return trimmed;
    }
    final hasExtension =
        RegExp(r'\.[a-z0-9]{2,5}$', caseSensitive: false).hasMatch(trimmed);
    return hasExtension ? trimmed : '$trimmed.png';
  }

  String _normalizeStatus(String raw) {
    final value = raw.toLowerCase().trim();
    if (value.contains('maintenance')) return 'maintenance';
    if (value.contains('indispo') || value.contains('offline')) {
      return 'indisponible';
    }
    return 'disponible';
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'maintenance':
        return const Color(0xFFFFB74D);
      case 'indisponible':
        return const Color(0xFFE57373);
      default:
        return const Color(0xFF81C784);
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'maintenance':
        return 'EN MAINTENANCE';
      case 'indisponible':
        return 'INDISPONIBLE';
      default:
        return 'DISPONIBLE';
    }
  }

  Widget _fallbackBanner() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2B365A), Color(0xFF222B49)],
        ),
      ),
      child: const Center(
        child: Icon(
          Icons.precision_manufacturing_rounded,
          color: Color(0xFFC7D4F0),
          size: 34,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final machineId =
        (machine['machineId'] ?? machine['_id'] ?? machine['id'] ?? '')
            .toString();
    final name = catalogMachineDisplayName(machine);
    final priceLabel = catalogMachinePriceLabel(machine);
    final imageUrl = _normalizeMachineImageValue(
      (machine['imageUrl'] ?? machine['image'] ?? machine['photo'] ?? '')
          .toString(),
    );
    final status = _normalizeStatus(
      (machine['status'] ?? machine['etat'] ?? machine['state'] ?? 'disponible')
          .toString(),
    );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xE61B2238), Color(0xE6151B2E)],
        ),
        border: Border.all(
          color: const Color(0x3DFFFFFF),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF000000).withOpacity(0.18),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AspectRatio(
              aspectRatio: 16 / 7.2,
              child: imageUrl.isEmpty
                  ? _fallbackBanner()
                  : (_looksLikeDataImage(imageUrl)
                      ? Image.memory(
                          base64Decode(imageUrl.split(',').last),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _fallbackBanner(),
                        )
                      : Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _fallbackBanner(),
                        )),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _statusColor(status),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                _statusLabel(status),
                style: GoogleFonts.inter(
                  color: _statusColor(status),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            priceLabel,
            style: GoogleFonts.inter(
              color: const Color(0xFFFFBE86),
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _runIfAuthenticated(context, () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => MachineDetailProPage(machine: machine),
                      ),
                    );
                  }),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0x557AA7E8)),
                    foregroundColor: const Color(0xFFD7E7FF),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Voir detail'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _runIfAuthenticated(context, onBuy),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6E00),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Acheter'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Simple data class for sensor readings
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _SensorData {
  final String label;
  final String value;
  const _SensorData(this.label, this.value);
}
