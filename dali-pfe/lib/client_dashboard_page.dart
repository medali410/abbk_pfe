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
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:video_player/video_player.dart';
import 'machine_detail_pro_page.dart';
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
  // Sidebar nav index: 0=Home, 1=Machines, 2=IA, 3=Team, 4=Docs
  int _navIndex = 0;
  /// Machine choisie pour l’onglet Analyse IA (null = liste de sélection).
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
  final Map<String, double> _realtimeTemps = {};
  final Map<String, double> _realtimeVibrations = {};
  final Map<String, double> _realtimeFrictions = {};
  final Map<String, double> _realtimePressures = {};
  Timer? _controlTicker;
  Timer? _machinesAutoRefreshTimer;

  // Public catalogue (same data as HomePage) shown inside the client dashboard (tab index=0).
  Future<List<Map<String, dynamic>>>? _publicCatalogFuture;
  final TextEditingController _publicCatalogSearchController = TextEditingController();
  String _publicCatalogSearchQuery = '';

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

  Future<void> _openAddTechnicianRequestPage() async {
    final cId =
        (widget.clientId ??
                widget.clientData?['clientId'] ??
                widget.clientData?['id'] ??
                ApiService.savedClientId ??
                '')
            .toString()
            .trim();
    final clientEmail =
        (widget.clientData?['email'] ?? ApiService.savedClientEmail ?? '')
            .toString()
            .trim();
    final clientName =
        (widget.clientData?['name'] ??
                widget.clientName ??
                ApiService.savedClientName ??
                '')
            .toString()
            .trim();

    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController(text: clientEmail);
    final phoneCtrl = TextEditingController();
    final locationCtrl = TextEditingController(text: clientName);
    final specializationCtrl = TextEditingController(text: 'Maintenance terrain');
    final descriptionCtrl = TextEditingController();
    List<Map<String, dynamic>> availableMachines = const [];
    final selectedMachineIds = <String>{};
    bool isSubmitting = false;

    if (cId.isNotEmpty) {
      try {
        availableMachines = await ApiService.getMachinesForClient(cId);
      } catch (_) {
        availableMachines = const [];
      }
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            InputDecoration fieldDecoration(String label, {String? hintText}) {
              return InputDecoration(
                labelText: label,
                hintText: hintText,
                labelStyle: GoogleFonts.inter(
                  color: _onSurfaceVariant.withOpacity(0.9),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                hintStyle: GoogleFonts.inter(
                  color: _onSurfaceVariant.withOpacity(0.5),
                  fontSize: 12,
                ),
                isDense: true,
                contentPadding: const EdgeInsets.only(top: 8, bottom: 8),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: _outlineVariant.withOpacity(0.35)),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: _primary.withOpacity(0.9), width: 1.4),
                ),
              );
            }

            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
              child: Container(
                width: (MediaQuery.of(ctx).size.width - 24).clamp(300.0, 620.0).toDouble(),
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.9,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF171B2A),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF262C46)),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Demande ajout technicien',
                        style: GoogleFonts.inter(
                          color: _onSurface,
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Flexible(
                        fit: FlexFit.loose,
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              TextField(
                                controller: nameCtrl,
                                style: GoogleFonts.inter(color: _onSurface, fontSize: 13),
                                decoration: fieldDecoration('Nom du technicien'),
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: emailCtrl,
                                keyboardType: TextInputType.emailAddress,
                                style: GoogleFonts.inter(color: _onSurface, fontSize: 13),
                                decoration: fieldDecoration('Email', hintText: 'exemple@mail.com'),
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: phoneCtrl,
                                keyboardType: TextInputType.phone,
                                style: GoogleFonts.inter(color: _onSurface, fontSize: 13),
                                decoration: fieldDecoration('Téléphone'),
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: specializationCtrl,
                                style: GoogleFonts.inter(color: _onSurface, fontSize: 13),
                                decoration: fieldDecoration('Spécialité'),
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: locationCtrl,
                                style: GoogleFonts.inter(color: _onSurface, fontSize: 13),
                                decoration: fieldDecoration('Localisation'),
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: descriptionCtrl,
                                minLines: 2,
                                maxLines: 3,
                                style: GoogleFonts.inter(color: _onSurface, fontSize: 13),
                                decoration: fieldDecoration('Description technique'),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'MACHINES À CONTRÔLER',
                                style: GoogleFonts.inter(
                                  color: _onSurface,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              const SizedBox(height: 8),
                              if (availableMachines.isEmpty)
                                Text(
                                  'Aucune machine disponible pour ce client.',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: _onSurfaceVariant,
                                  ),
                                )
                              else
                                ...availableMachines.map((m) {
                                  final machineId =
                                      (m['id'] ?? m['machineId'] ?? m['_id'] ?? '')
                                          .toString()
                                          .trim();
                                  final machineName =
                                      (m['name'] ?? machineId).toString().trim();
                                  if (machineId.isEmpty) return const SizedBox.shrink();
                                  return CheckboxListTile(
                                    value: selectedMachineIds.contains(machineId),
                                    controlAffinity: ListTileControlAffinity.leading,
                                    contentPadding: EdgeInsets.zero,
                                    checkboxShape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                    visualDensity: const VisualDensity(
                                      horizontal: -4,
                                      vertical: -3,
                                    ),
                                    onChanged: (checked) {
                                      setDialogState(() {
                                        if (checked == true) {
                                          selectedMachineIds.add(machineId);
                                        } else {
                                          selectedMachineIds.remove(machineId);
                                        }
                                      });
                                    },
                                    activeColor: _primary,
                                    checkColor: _surfaceContainerHighest,
                                    title: Text(
                                      machineName,
                                      style: GoogleFonts.inter(
                                        color: _onSurface,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    subtitle: Text(
                                      machineId,
                                      style: GoogleFonts.inter(
                                        color: _onSurfaceVariant,
                                        fontSize: 11,
                                      ),
                                    ),
                                  );
                                }),
                              if (clientName.isNotEmpty || cId.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  'Client: ${clientName.isEmpty ? cId : clientName}',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color: _onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        alignment: WrapAlignment.end,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          TextButton(
                            onPressed: isSubmitting
                                ? null
                                : () {
                                    Navigator.pop(ctx);
                                  },
                            child: Text(
                              'Annuler',
                              style: GoogleFonts.inter(
                                color: _primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          ElevatedButton.icon(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          final name = nameCtrl.text.trim();
                          final email = emailCtrl.text.trim();
                          final phone = phoneCtrl.text.trim();
                          final specialization = specializationCtrl.text.trim();
                          final location = locationCtrl.text.trim();
                          final description = descriptionCtrl.text.trim();
                          if (name.isEmpty || email.isEmpty || !email.contains('@')) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Veuillez remplir Nom et Email valide.'),
                                backgroundColor: Colors.red,
                              ),
                            );
                            return;
                          }
                          setDialogState(() => isSubmitting = true);
                          try {
                            // Le client n'a pas le droit de créer un technicien directement.
                            // On envoie donc une "demande" que le concepteur validera.
                            await ApiService.createPurchaseRequest({
                              'machineId': 'TECH-REQUEST',
                              'machineName': 'Demande ajout technicien',
                              if (cId.isNotEmpty) 'linkedClientId': cId,
                              'requesterName': name,
                              'requesterEmail': email.toLowerCase(),
                              'requesterPhone': phone,
                              'location': location.isEmpty
                                  ? (clientName.isEmpty ? 'Client dashboard' : clientName)
                                  : location,
                              'note': [
                                'Demande client: ajout technicien (validation requise par concepteur).',
                                if (specialization.isNotEmpty) 'Specialite: $specialization',
                                if (description.isNotEmpty) 'Description: $description',
                                if (selectedMachineIds.isNotEmpty)
                                  'Machines a controler: ${selectedMachineIds.join(', ')}',
                              ].join('\n'),
                              'requestType': 'TECHNICIAN_ADD',
                              'metadata': {
                                'specialization': specialization,
                                'description': description,
                                'machineIds': selectedMachineIds.toList(),
                              },
                            });

                            if (!mounted) return;
                            Navigator.pop(ctx);
                            _refreshMachines();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Demande envoyée. Validation en attente du concepteur.'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          } catch (e) {
                            if (!mounted) return;
                            setDialogState(() => isSubmitting = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Échec envoi demande: $e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        },
                            icon: const Icon(Icons.person_add_alt_1_rounded, size: 16),
                            label: Text(isSubmitting ? 'Envoi...' : 'Envoyer'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.black.withOpacity(0.35),
                              foregroundColor: _primary,
                              disabledBackgroundColor: Colors.black.withOpacity(0.2),
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                                side: BorderSide(color: _outlineVariant.withOpacity(0.4)),
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

    nameCtrl.dispose();
    emailCtrl.dispose();
    phoneCtrl.dispose();
    locationCtrl.dispose();
    specializationCtrl.dispose();
    descriptionCtrl.dispose();
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
        _machineSelectedMachine = machines.isNotEmpty ? machines.first : null;
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
        _iaSelectedMachine = machines.isNotEmpty ? machines.first : null;
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
      final msg = (qp['error'] ?? 'Connexion Google refusée').trim();
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

  // ── Colour tokens (mirror Tailwind config) ──
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
          // ── Sidebar ──
          if (isDesktop) _buildSidebar(),
          // ── Main area ──
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
              "Choisissez une machine pour consulter sa fiche, l'historique télémétrique et les fiches associées.",
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

  Widget _buildProfileSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'PROFIL CLIENT',
          style: GoogleFonts.spaceGrotesk(
            fontSize: 9,
            fontWeight: FontWeight.w900,
            color: _secondary,
            letterSpacing: 2.5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Informations de votre compte',
          style: GoogleFonts.inter(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: _onSurface,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 20),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF171A36),
                const Color(0xFF11142B),
              ],
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.28),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _buildClientProfileAvatar(),
                const SizedBox(height: 12),
                Text(
                  _currentClientName,
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: _onSurface,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  _currentClientEmail.isEmpty
                      ? 'Email non renseigné'
                      : _currentClientEmail,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: _onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  _currentClientLocation,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: _onSurfaceVariant.withOpacity(0.9),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: _openProfileSettingsDialog,
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Modifier le profil'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _primaryLight,
                    side: BorderSide(
                      color: _outlineVariant.withOpacity(0.45),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _buildProfileStatsSection(),
        const SizedBox(height: 16),
        _buildProfileClientMachinesSection(),
        const SizedBox(height: 16),
        _buildProfileTechniciansSection(),
      ],
    );
  }

  Widget _buildProfileStatsSection() {
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
            'STATISTIQUES',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 10,
              letterSpacing: 1.6,
              fontWeight: FontWeight.w700,
              color: _onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          _buildSidebarStats(),
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
                  'Aucune machine assignée à ce client.',
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
                  final brand = (m['brand'] ?? m['marque'] ?? '—').toString();
                  final model = (m['model'] ?? m['name'] ?? '—').toString();
                  final type = (m['type'] ?? m['category'] ?? '—').toString();
                  final location = (m['location'] ?? m['site'] ?? '—').toString();
                  final serial = (m['serialNumber'] ?? m['serial'] ?? m['sn'] ?? '—')
                      .toString();
                  final maintBy =
                      (m['maintenanceControlBy'] ?? m['maintainedBy'] ?? '—')
                          .toString();
                  final maintActive = m['maintenanceControlActive'] == true
                      ? 'Oui'
                      : 'Non';
                  final temp = (m['temperature'] ?? m['temp'] ?? '—').toString();
                  final vibration =
                      (m['vibration'] ?? m['vibrationLevel'] ?? '—').toString();
                  final pressure =
                      (m['pressure'] ?? m['pressureLevel'] ?? '—').toString();
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
                                  _miniInfo('Pression', pressure),
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
            text: value.isEmpty ? '—' : value,
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
                  'Aucun technicien assigné à ce client.',
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
          subtitle: '$name · $mid',
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
                "Aucune machine n'est assignée à votre client pour le moment. Contactez l'administrateur pour activer l'analyse IA.",
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
                subtitle: '$mname · $mid',
                onBack: () {},
              ),
              const SizedBox(height: 16),
              if (isDesktop)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _surfaceContainerLow.withOpacity(0.45),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withOpacity(0.08)),
                      ),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: machines.map((m) {
                          final id = _clientMachineId(m);
                          final name = _clientMachineName(m);
                          final active = id == mid;
                          return ChoiceChip(
                            label: Text(
                              '$name · $id',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: active ? _secondary : _onSurface,
                                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                              ),
                            ),
                            selected: active,
                            onSelected: (_) => setState(() => _iaSelectedMachine = m),
                            selectedColor: _primaryContainer.withOpacity(0.15),
                            backgroundColor: _surfaceContainerHighest.withOpacity(0.25),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(
                                color: active
                                    ? _primaryContainer.withOpacity(0.8)
                                    : Colors.white.withOpacity(0.10),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    iaPanel,
                  ],
                )
              else ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _surfaceContainerLow,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _outlineVariant.withOpacity(0.2)),
                  ),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: machines.map((m) {
                      final id = _clientMachineId(m);
                      final name = _clientMachineName(m);
                      final active = id == mid;
                      return ChoiceChip(
                        label: Text(
                          '$name · $id',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: active ? _secondary : _onSurface,
                            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                        selected: active,
                        onSelected: (_) => setState(() => _iaSelectedMachine = m),
                        selectedColor: _secondary.withOpacity(0.18),
                        backgroundColor: _surfaceContainerHighest.withOpacity(0.3),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(
                            color: active
                                ? _secondary.withOpacity(0.8)
                                : Colors.white.withOpacity(0.08),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 16),
                iaPanel,
              ],
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
            final q = _publicCatalogSearchQuery.toLowerCase().trim();
            final filtered = allMachines.where((m) {
              if (q.isEmpty) return true;
              final machineId = (m['machineId'] ?? m['_id'] ?? m['id'] ?? '').toString().toLowerCase();
              final name = (m['name'] ?? m['model'] ?? '').toString().toLowerCase();
              final brand = (m['brand'] ?? m['marque'] ?? '').toString().toLowerCase();
              return machineId.contains(q) || name.contains(q) || brand.contains(q);
            }).toList();

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
                childAspectRatio: crossAxisCount == 1 ? 1.18 : 1.02,
              ),
              itemBuilder: (context, i) {
                final machine = filtered[i];
                final machineId = (machine['machineId'] ?? machine['_id'] ?? machine['id'] ?? '').toString();
                return _ClientPublicMachineCard(
                  machine: machine,
                  canBuy: true,
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        height: isDesktop ? 280 : 240,
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
              padding: EdgeInsets.all(isDesktop ? 24 : 18),
              child: SizedBox(
                width: isDesktop ? 560 : double.infinity,
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
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'L\'efficacite predite par l\'IA',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: isDesktop ? 38 : 28,
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Visualisez les equipements critiques en temps reel et accedez aux machines disponibles depuis la base.',
                      style: GoogleFonts.inter(
                        color: const Color(0xFFD5DCEE),
                        fontSize: 14,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 14),
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
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClientHeroVisual() {
    return const _ClientHeroVideoSlides(
      fallbackImageUrl:
          'https://images.unsplash.com/photo-1565043589221-1a6fd9ae45c7?auto=format&fit=crop&w=1400&q=80',
    );
  }

  Widget _buildClientCatalogToolbar(bool isDesktop) {
    return ClipRRect(
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
                  onChanged: (v) => setState(() => _publicCatalogSearchQuery = v),
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
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
              if (isDesktop) ...[
                _buildClientCatalogChip(Icons.filter_alt_outlined, 'Filtre'),
                const SizedBox(width: 8),
                _buildClientCatalogChip(Icons.tune, 'Tri'),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildClientCatalogSectionHeader({
    required String title,
    required String subtitle,
    required Widget trailing,
  }) {
    return Row(
      children: [
        Expanded(
          child: Column(
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
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  height: 1.08,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        trailing,
      ],
    );
  }

  Widget _buildClientCatalogChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0x1FFFFFFF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x33FFFFFF)),
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
          subtitle: '$name · $mid',
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
                'Aucune panne terminée archivée pour cette machine.',
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
                  width: 170,
                  height: 46,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Image.asset(
                    'assets/images/abbk_logo.png',
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                  ),
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
                    const SizedBox.shrink(),
                  ],
                ),
              ],
            ),
          ),
          // Nav items
          _navItem(Icons.dashboard, 'Home', 0),
          _navItem(Icons.person_outline, 'Profil', 5),
          _navItem(Icons.precision_manufacturing, 'Mes Machines', 1),
          _navItem(Icons.auto_awesome, 'Analyse IA', 2),
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
                const Spacer(),
                // Icons
                _iconBtn(Icons.notifications_outlined),
                const SizedBox(width: 8),
                _iconBtn(Icons.settings_outlined),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _logoutClient,
                  icon: const Icon(Icons.logout, size: 16),
                  label: const Text('Déconnexion'),
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
        const SnackBar(content: Text('Photo de profil mise à jour.')),
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
      const SnackBar(content: Text('Background profil mis à jour.')),
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
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _openNotificationsPopover(),
              icon: const Icon(Icons.notifications_outlined, size: 18),
              label: const Text('Notifications'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _onSurfaceVariant,
                side: BorderSide(color: _outlineVariant.withOpacity(0.45)),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _openProfileSettingsDialog,
              icon: const Icon(Icons.settings_outlined, size: 18),
              label: const Text('Paramètres'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _onSurfaceVariant,
                side: BorderSide(color: _outlineVariant.withOpacity(0.45)),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _logoutClient,
              icon: const Icon(Icons.logout, size: 18),
              label: const Text('Déconnexion'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _error,
                side: BorderSide(color: _error.withOpacity(0.45)),
                padding: const EdgeInsets.symmetric(vertical: 10),
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
        title: const Text('Déconnexion'),
        content: const Text('Voulez-vous vraiment vous déconnecter ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Se déconnecter'),
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
                    'Paramètres du profil',
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
        const SnackBar(content: Text('Profil mis à jour.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Mise à jour impossible: $e')),
      );
    }
  }

  Future<void> _openNotificationsPopover({Offset? anchor}) async {
    final alerts = (widget.clientData?['alerts'] ?? 0).toString();
    final rows = <Map<String, String>>[
      {
        'title': 'Santé du site',
        'body': 'Le site est opérationnel. Alertes actives: $alerts.',
      },
      {
        'title': 'Machines',
        'body': 'Ouvrez "Mes Machines" pour voir les dernières mises à jour.',
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
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
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
            OutlinedButton.icon(
              onPressed: _openAddTechnicianRequestPage,
              icon: const Icon(Icons.person_add_alt_1_rounded, size: 16),
              label: const Text('Demande de add technicien'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _secondary,
                side: BorderSide(color: _secondary.withOpacity(0.45)),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                textStyle: GoogleFonts.inter(
                  fontSize: 11,
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
                        onPressed: () => _openMessageEquipeDialog(t),
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

  String _formatChatTime(dynamic raw) {
    final dt = DateTime.tryParse((raw ?? '').toString());
    if (dt == null) return '--:--';
    final local = dt.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _openMessageEquipeDialog(Map<String, dynamic> technician) async {
    final techId = (technician['technicianId'] ?? technician['_id'] ?? 'tech').toString();
    final clientKey = (widget.clientId ?? widget.clientData?['clientId'] ?? widget.clientData?['id'] ?? 'client').toString();
    final roomId = 'chat_${clientKey}_$techId';
    final techName = (technician['name'] ?? 'Technicien').toString();
    final input = TextEditingController();

    _socket.emit('join_chat_room', {'roomId': roomId});

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final messages = List<Map<String, dynamic>>.from(_chatMessages[roomId] ?? const []);
            return Dialog(
              backgroundColor: _surfaceContainerHigh,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: SizedBox(
                width: (MediaQuery.of(ctx).size.width - 32).clamp(300.0, 560.0).toDouble(),
                height: 520,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: _surfaceContainerHighest,
                            child: const Icon(Icons.engineering, size: 16, color: _onSurfaceVariant),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Message · $techName',
                              style: GoogleFonts.inter(
                                color: _onSurface,
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            icon: const Icon(Icons.close_rounded),
                            tooltip: 'Fermer',
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: messages.isEmpty
                          ? Center(
                              child: Text(
                                'Aucun message pour le moment.',
                                style: GoogleFonts.inter(color: _onSurfaceVariant),
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.all(12),
                              itemCount: messages.length,
                              itemBuilder: (_, i) {
                                final msg = messages[i];
                                final isMine = (msg['from'] ?? '').toString() == 'client';
                                return Align(
                                  alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
                                  child: Container(
                                    margin: const EdgeInsets.symmetric(vertical: 5),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    constraints: const BoxConstraints(maxWidth: 360),
                                    decoration: BoxDecoration(
                                      color: isMine ? _primaryContainer.withOpacity(0.22) : _surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: _outlineVariant.withOpacity(0.25)),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          (msg['text'] ?? '').toString(),
                                          style: GoogleFonts.inter(color: _onSurface, fontSize: 13),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          _formatChatTime(msg['createdAt']),
                                          style: GoogleFonts.inter(
                                            color: _onSurfaceVariant,
                                            fontSize: 10,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: input,
                              minLines: 1,
                              maxLines: 3,
                              decoration: const InputDecoration(
                                hintText: 'Ecrire un message...',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              onSubmitted: (_) {
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
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            onPressed: () {
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
                            },
                            icon: const Icon(Icons.send_rounded, size: 16),
                            label: const Text('Envoyer'),
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
              _actionBtn(Icons.arrow_forward, _secondary, () {
                setState(() {
                  _machineSelectedMachine = m;
                  _navIndex = 1;
                });
              }),
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

class _ClientPublicMachineCard extends StatelessWidget {
  const _ClientPublicMachineCard({
    required this.machine,
    required this.canBuy,
    required this.onBuy,
  });

  final Map<String, dynamic> machine;
  final bool canBuy;
  final VoidCallback onBuy;

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
    final name =
        (machine['name'] ?? machine['model'] ?? machineId).toString();
    final brand = (machine['brand'] ?? machine['marque'] ?? '').toString();
    final description = (machine['description'] ?? machine['type'] ?? 'Machine industrielle')
        .toString();
    final price = (machine['price'] ?? machine['prix'] ?? '').toString();
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
          const SizedBox(height: 8),
          Text(
            name.isEmpty ? 'Machine' : name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            machineId.isEmpty ? 'ID: -' : 'ID: $machineId',
            style: GoogleFonts.inter(
              color: const Color(0xFFA7B1C6),
              fontSize: 12,
            ),
          ),
          if (brand.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              'Marque: $brand',
              style: GoogleFonts.inter(
                color: const Color(0xFFA7B1C6),
                fontSize: 12,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            description,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              color: const Color(0xFFD5DDF0),
              fontSize: 13,
              height: 1.35,
            ),
          ),
          const Spacer(),
          if (price.isNotEmpty)
            Text(
              'Prix: $price',
              style: GoogleFonts.inter(
                color: const Color(0xFFFFBE86),
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => MachineDetailProPage(machine: machine),
                      ),
                    );
                  },
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
                  onPressed:
                      canBuy
                          ? onBuy
                          : () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Veuillez vous connecter pour acheter.',
                                ),
                              ),
                            );
                          },
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

// ─────────────────────────────────────────────────────────────
// Simple data class for sensor readings
// ─────────────────────────────────────────────────────────────
class _SensorData {
  final String label;
  final String value;
  const _SensorData(this.label, this.value);
}

class _ClientHeroVideoSlides extends StatefulWidget {
  const _ClientHeroVideoSlides({
    required this.fallbackImageUrl,
  });

  final String fallbackImageUrl;

  @override
  State<_ClientHeroVideoSlides> createState() => _ClientHeroVideoSlidesState();
}

class _ClientHeroVideoSlidesState extends State<_ClientHeroVideoSlides> {
  final Duration _endThreshold = const Duration(milliseconds: 250);

  List<String> _videoAssets = const [];
  int _index = 0;
  VideoPlayerController? _controller;
  bool _initializing = false;
  bool _advancing = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    if (_initializing) return;
    _initializing = true;
    try {
      final assets = await _loadVideoAssetsFromManifest();
      if (!mounted) return;
      if (assets.isEmpty) return;
      setState(() => _videoAssets = assets);
      await _switchToIndex(0);
    } finally {
      _initializing = false;
    }
  }

  Future<List<String>> _loadVideoAssetsFromManifest() async {
    try {
      final raw = await rootBundle.loadString('AssetManifest.json');
      final decoded = json.decode(raw);
      if (decoded is! Map<String, dynamic>) return const [];
      final keys = decoded.keys.toList();
      keys.sort();

      const okExt = ['.mp4', '.webm'];
      return keys
          .where((k) => k.startsWith('assets/videos/'))
          .where((k) => okExt.any((ext) => k.toLowerCase().endsWith(ext)))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  void _handleTick() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;

    final d = c.value.duration;
    final p = c.value.position;
    if (d > Duration.zero && d - p <= _endThreshold) {
      _next();
      return;
    }

    if (d > Duration.zero && !c.value.isPlaying && p >= d - _endThreshold) {
      _next();
      return;
    }
  }

  Future<void> _switchToIndex(int idx, {int attempts = 0}) async {
    final c = _controller;
    c?.removeListener(_handleTick);
    await c?.dispose();

    if (_videoAssets.isEmpty) return;
    if (attempts >= _videoAssets.length) {
      _controller = null;
      if (mounted) setState(() {});
      return;
    }

    _index = idx % _videoAssets.length;
    final assetPath = _videoAssets[_index];
    final next = VideoPlayerController.asset(assetPath);
    try {
      next.addListener(_handleTick);
      _controller = next;
      await next.initialize();
      await next.setVolume(0.0);
      await next.setLooping(false);
      await next.play();
      if (mounted) setState(() {});
    } catch (_) {
      next.removeListener(_handleTick);
      await next.dispose();
      final nextIndex = (_index + 1) % _videoAssets.length;
      return _switchToIndex(nextIndex, attempts: attempts + 1);
    }
  }

  void _next() {
    if (_advancing || _videoAssets.isEmpty) return;
    _advancing = true;
    final nextIndex = (_index + 1) % _videoAssets.length;
    _switchToIndex(nextIndex).whenComplete(() => _advancing = false);
  }

  @override
  void dispose() {
    _controller?.removeListener(_handleTick);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (c == null || !c.value.isInitialized || c.value.hasError) {
      return SizedBox.expand(
        child: Image.network(widget.fallbackImageUrl, fit: BoxFit.cover),
      );
    }

    final w = c.value.size.width;
    final h = c.value.size.height;
    if (w <= 0 || h <= 0) {
      return SizedBox.expand(
        child: Image.network(widget.fallbackImageUrl, fit: BoxFit.cover),
      );
    }

    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: w,
        height: h,
        child: VideoPlayer(c),
      ),
    );
  }
}
