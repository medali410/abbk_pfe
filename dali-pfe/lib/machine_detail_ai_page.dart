import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'kinetic_observatory_page.dart';
import 'services/api_service.dart';
import 'utils/panne_display.dart';
import 'add_technician_page.dart';
import 'technician_profile_page.dart';
import 'add_maintenance_agent_page.dart';
import 'maintenance_agent_detail_page.dart';
import 'maintenance_module_page.dart';
import 'dart:async';

class MachineDetailAiPage extends StatefulWidget {
  final String machineId;
  final String? machineName;
  final String? viewerRole;
  final String? viewerName;
  const MachineDetailAiPage({
    super.key,
    required this.machineId,
    this.machineName,
    this.viewerRole,
    this.viewerName,
  });

  @override
  State<MachineDetailAiPage> createState() => _MachineDetailAiPageState();
}

class _MachineDetailAiPageState extends State<MachineDetailAiPage> with TickerProviderStateMixin {
  late io.Socket _socket;
  late String _machineId;
  late Set<String> _acceptedMachineIds;
  final TextEditingController _teamChatController = TextEditingController();
  final List<Map<String, dynamic>> _teamChatMessages = <Map<String, dynamic>>[];
  int _unreadTeamMessages = 0;
  late Future<List<Map<String, dynamic>>> _historyFuture;

  double _thermal = 0;
  double _pressure = 0;
  double _power = 0;
  double _powerRawW = 0;
  double _vibration = 0;
  double _rpm = 0;
  double _torque = 0;
  double _toolWear = 0;
  double _ultrasonic = 0;
  double _presence = 0;
  double _magnetic = 0;
  double _infrared = 0;
  int _wifiRssi = 0;
  String _zone = 'Zone inconnue';
  DateTime? _lastMqttPacketAt;
  int _mqttPacketCount = 0;

  int _iaProbPanne = 0;
  String _iaNiveau = 'INCONNU';
  String _iaPanneType = '—';
  String _scenarioLabel = '';
  String _scenarioExplanation = '';
  double? _iaRulEstime;
  double? _iaRulHeuresIndicatif;
  String _machineIaMotorType = 'EL_M';
  final TextEditingController _adminRulScaleController = TextEditingController();
  String _adminIaMotor = 'EL_M';
  bool _savingIaProfile = false;
  bool _requiresStop = false;
  String _notificationMessage = '';
  late AnimationController _pulseCtrl;

  String _motor3dAsset = 'assets/images/motor_3d_default.png';
  bool _panneAlertSent = false;
  bool _machineStopped = false;
  bool _isStoppingMachine = false;

  String _sideTab = 'dashboard'; // dashboard | history | maintenance | technicians | maintenance_team
  String? _companyId;
  Map<String, dynamic>? _activeIntervention;
  bool _forceShowMaintenanceTeam = false;
  List<Map<String, dynamic>>? _techniciansForMachine;
  bool _loadingTechnicians = false;
  bool _loadingMaintenance = false;
  String? _maintenanceError;
  List<Map<String, dynamic>> _maintenanceOrders = <Map<String, dynamic>>[];
  String _maintenanceFilterStatus = 'ALL';
  String _maintenanceFilterPriority = 'ALL';

  static const _bg = Color(0xFF0D0E1B);
  static const _panel = Color(0xFF12131F);
  static const _panel2 = Color(0xFF161826);
  static const _panel3 = Color(0xFF1E2030);
  static const _orange = Color(0xFFFF7E21);
  static const _cyan = Color(0xFF75D1FF);
  static const _text = Color(0xFFE2DFFF);
  static const _muted = Color(0xFFE2BFB0);
  static const _green = Color(0xFF66BB6A);
  static const _red = Color(0xFFFFB4AB);

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..repeat(reverse: true);
    _machineId = widget.machineId.trim();
    _acceptedMachineIds = _buildAcceptedMachineIds(_machineId, widget.machineName);
    _historyFuture = ApiService.getTelemetryHistory(_machineId, limit: 20);
    _loadInitialTelemetry();
    _loadMaintenanceOrders();
    _checkActiveIntervention();
    _initSocket();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMachineIaProfile());
  }

  Set<String> _buildAcceptedMachineIds(String baseId, String? machineName) {
    final ids = <String>{baseId};
    final n = (machineName ?? '').toLowerCase();
    if (n.contains('dzli')) {
      ids.add('MAC_NEW_01');
      ids.add('MAC-1775750118162');
    }
    if (n.contains('expresse')) {
      ids.add('MAC_EXP');
    }
    // Also accept normalized uppercase of provided ID.
    ids.add(baseId.toUpperCase());
    return ids;
  }

  Future<void> _checkActiveIntervention() async {
    try {
      final interventions = await ApiService.getDiagnosticInterventions();
      final active = interventions.firstWhere(
        (i) => i['machineId'] == _machineId && i['status'] != 'CLOSED',
        orElse: () => <String, dynamic>{},
      );
      if (active.isNotEmpty) {
        setState(() {
          _activeIntervention = active;
        });
      }
    } catch (e) {
      debugPrint('Error checking intervention: $e');
    }
  }

  Future<void> _cancelActiveIntervention() async {
    final id = (_activeIntervention?['id'] ?? '').toString();
    if (id.isEmpty) return;

    try {
      await ApiService.deleteDiagnosticIntervention(id);
      setState(() {
        _activeIntervention = null;
        _forceShowMaintenanceTeam = false;
        _sideTab = 'maintenance_team';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Intervention annulee avec succes.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur lors de l\'annulation: $e')));
      }
    }
  }

  Future<void> _assignTechnician(Map<String, dynamic> tech) async {
    try {
      if (_activeIntervention != null) {
        // Mode REASSIGNATION
        final id = (_activeIntervention?['id'] ?? '').toString();
        await ApiService.reassignDiagnosticTechnician(
          id,
          technicianId: (tech['maintenanceAgentId'] ?? tech['id']).toString(),
          technicianName: (tech['name'] ?? 'Inconnu').toString(),
        );
        setState(() => _forceShowMaintenanceTeam = false);
        await _checkActiveIntervention();
        return;
      }

      if (_companyId == null || _companyId!.isEmpty) {
        final info = await ApiService.getMachineInfo(_machineId);
        _companyId = info['companyId']?.toString();
      }
      if (_companyId == null || _companyId!.isEmpty) {
        throw Exception('machineId et companyId requis');
      }

      final intervention = await ApiService.createDiagnosticIntervention({
        'machineId': _machineId,
        'companyId': _companyId,
        'technicianId': tech['maintenanceAgentId'] ?? tech['id'],
        'technicianName': tech['name'],
        'priority': _iaProbPanne >= 70 ? 'CRITICAL' : 'HIGH',
      });
      setState(() {
        _activeIntervention = intervention;
        _sideTab = 'maintenance_team';
      });
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => KineticObservatoryPage(
              machineId: _machineId,
              interventionId: _activeIntervention!['id'].toString(),
            ),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur d\'assignation : $e')),
      );
    }
  }

  Future<void> _validateDiagnosticIntervention() async {
    final id = (_activeIntervention?['id'] ?? '').toString();
    if (id.isEmpty) return;

    try {
      // 1. Fixer la decision sur "Panne Reelle"
      await ApiService.setDiagnosticDecision(id, finalDecision: 'REAL_FAILURE');
      
      // 2. Passer l'intervention en statut DONE
      await ApiService.setDiagnosticStatus(id, 'DONE');
      
      // 3. Envoyer un message de confirmation
      await ApiService.addDiagnosticMessage(id, 'OK - Diagnostic valide (Panne reelle)', authorName: _senderName);
      
      // 4. Ouvrir le dashboard complet
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MaintenanceModulePage(
              initialInterventionId: id,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur lors de la validation: $e')));
      }
    }
  }

  double _toDouble(dynamic v, [double fb = 0]) {
    if (v == null) return fb;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? fb;
  }

  Future<void> _loadInitialTelemetry() async {
    try {
      final data = await ApiService.getLatestTelemetry(_machineId);
      if (!mounted || data == null) return;
      _applyTelemetry(data, fromLiveStream: false);
    } catch (_) {}
  }

  void _applyTelemetry(Map<String, dynamic> data, {bool fromLiveStream = false}) {
    if (!mounted) return;
    final m = data['metrics'] as Map<String, dynamic>?;
    final fs = data['failureScenario'] as Map<String, dynamic>?;
    setState(() {
      _thermal = _toDouble(data['temperature'] ?? m?['thermal'], _thermal);
      _pressure = _toDouble(data['pressure'] ?? m?['pressure'], _pressure);
      _vibration = _toDouble(data['vibration'] ?? m?['vibration'], _vibration);
      final pw = data['power'] ?? m?['power'];
      if (pw != null) {
        final rp = _toDouble(pw, 0);
        _powerRawW = rp;
        // Le backend envoie souvent couple×rpm en « unités grandes » (> ~3000) : affichage kW.
        _power = rp > 3000 ? rp / 1000.0 : rp;
      }
      _rpm = _toDouble(data['rpm'] ?? m?['rpm'], _rpm);
      _torque = _toDouble(data['torque'] ?? m?['torque'], _torque);
      _toolWear = _toDouble(
          data['tool_wear'] ?? data['toolWear'] ?? m?['tool_wear'] ?? m?['toolWear'], _toolWear);
      _ultrasonic = _toDouble(data['ultrasonic'] ?? m?['ultrasonic'], _ultrasonic);
      _presence = _toDouble(data['presence'] ?? m?['presence'], _presence);
      _magnetic = _toDouble(data['magnetic'] ?? m?['magnetic'], _magnetic);
      _infrared = _toDouble(data['infrared'] ?? m?['infrared'], _infrared);
      _wifiRssi = _toDouble(data['wifiRssi'] ?? m?['wifiRssi'], _wifiRssi.toDouble()).round();
      _zone = (data['zone'] ?? data['locationZone'] ?? _zone).toString();
      if (fromLiveStream) {
        _lastMqttPacketAt = DateTime.now();
        _mqttPacketCount += 1;
      }

      final prob = data['prob_panne'] ?? data['panne_probability'] ?? data['scenarioProbPanne'] ?? fs?['scenarioProbPanne'];
      if (prob != null) {
        final p = _toDouble(prob, 0);
        _iaProbPanne = p <= 1 ? (p * 100).round().clamp(0, 100) : p.round().clamp(0, 100);
      }
      _iaNiveau = (data['niveau'] ??
              (_iaProbPanne >= 70 ? 'CRITIQUE' : _iaProbPanne >= 40 ? 'SURVEILLANCE' : 'NORMAL'))
          .toString();
      _iaPanneType = (data['panne_type'] ?? data['scenarioLabel'] ?? fs?['scenarioLabel'] ?? _iaPanneType).toString();
      final expl = (data['scenarioExplanation'] ?? fs?['scenarioExplanation'])?.toString();
      if (expl != null && expl.isNotEmpty) {
        _scenarioExplanation = expl;
      }
      final sl = (data['scenarioLabel'] ?? fs?['scenarioLabel'])?.toString();
      if (sl != null && sl.isNotEmpty) {
        _scenarioLabel = sl;
      }
      final rul = data['rul_estime'] ?? data['rul'];
      if (rul != null) _iaRulEstime = _toDouble(rul, _iaRulEstime ?? 0);
      final rh = data['rul_heures_indicatif'];
      if (rh != null) {
        _iaRulHeuresIndicatif = _toDouble(rh, 0);
      } else {
        _iaRulHeuresIndicatif = null;
      }
      final tia = data['type_moteur_ia'];
      if (tia != null && tia.toString().trim().isNotEmpty) {
        _machineIaMotorType = tia.toString();
      }
      _requiresStop = (data['requires_stop'] == true) || _iaProbPanne >= 75;
      _notificationMessage = (data['notification_message'] ?? '').toString();
    });
    _checkAutoAlert();
  }

  void _checkAutoAlert() {
    if (_iaProbPanne >= 60 && !_panneAlertSent) {
      _panneAlertSent = true;
      final alertText = _iaProbPanne >= 75
          ? '[ALERTE CRITIQUE] Machine $_machineId : PANNE IMMINENTE (risque $_iaProbPanne%). Arrêt immédiat recommandé.'
          : '[ALERTE CRITIQUE] Machine $_machineId : risque de panne $_iaProbPanne%. Intervention recommandée sous 24h.';

      _socket.emit('panne_alert', {
        'machineId': _machineId,
        'riskPercent': _iaProbPanne,
        'alertText': alertText,
      });

      _socket.emit('chat_message', {
        'roomId': _teamRoomId,
        'from': 'system',
        'senderName': 'Système IA',
        'text': alertText,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF4A0A0A),
            duration: const Duration(seconds: 6),
            content: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Color(0xFFFFDAD6)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    alertText,
                    style: GoogleFonts.inter(color: const Color(0xFFFFDAD6), fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }
    if (_iaProbPanne < 60) {
      _panneAlertSent = false;
    }
  }

  void _initSocket() {
    _socket = io.io(ApiService.socketBaseUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': true,
    });
    _socket.on('nouvelle_prediction', (raw) {
      try {
        final d = raw is String ? jsonDecode(raw) : raw;
        if (d is! Map) return;
        final data = Map<String, dynamic>.from(d);
        final incomingId = (data['machineId'] ?? data['id'] ?? '').toString();
        if (!_acceptedMachineIds.contains(incomingId)) return;
        _applyTelemetry(data, fromLiveStream: true);
      } catch (_) {}
    });
    _socket.onConnect((_) {
      _socket.emit('join_chat_room', {'roomId': _teamRoomId});
    });
    _socket.on('chat_message', (raw) {
      try {
        final data = raw is String ? jsonDecode(raw) : raw;
        if (data is! Map) return;
        final msg = Map<String, dynamic>.from(data);
        if ((msg['roomId'] ?? '').toString() != _teamRoomId) return;
        if (!mounted) return;
        setState(() {
          _teamChatMessages.add(msg);
          final incomingSender = (msg['senderName'] ?? '').toString();
          if (incomingSender != _senderName) {
            _unreadTeamMessages += 1;
          }
          if (_teamChatMessages.length > 200) {
            _teamChatMessages.removeAt(0);
          }
        });
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _teamChatController.dispose();
    _adminRulScaleController.dispose();
    _socket.dispose();
    super.dispose();
  }

  PanneUiHints get _panneHints => computePanneUiHints(
        probPanne: _iaProbPanne,
        panneType: _iaPanneType,
        scenarioLabel: _scenarioLabel,
        scenarioExplanation: _scenarioExplanation,
        thermal: _thermal,
        pressure: _pressure,
        vibration: _vibration,
        power: _powerRawW,
        magnetic: _magnetic,
        infrared: _infrared,
        ultrasonic: _ultrasonic,
      );

  Future<void> _loadMachineIaProfile() async {
    try {
      final info = await ApiService.getMachineInfo(_machineId);
      if (!mounted) return;
      var mt = (info['motorType'] ?? 'EL_M').toString().trim().toUpperCase();
      if (mt != 'EL_S' && mt != 'EL_M' && mt != 'EL_L') mt = 'EL_M';
      final scale = info['rulHoursPerModelUnit'];
      setState(() {
        _companyId = info['companyId']?.toString();
        _machineIaMotorType = mt;
        _adminIaMotor = mt;
        _adminRulScaleController.text =
            scale != null && scale.toString().trim().isNotEmpty ? scale.toString() : '';
      });
    } catch (_) {}
  }

  Future<void> _saveIaMotorProfile() async {
    if (!_canEditIaMotorProfile) return;
    setState(() => _savingIaProfile = true);
    try {
      final raw = _adminRulScaleController.text.trim();
      final scale = raw.isEmpty ? null : double.tryParse(raw);
      await ApiService.updateMachine(_machineId, {
        'motorType': _adminIaMotor,
        'rulHoursPerModelUnit': (scale != null && scale > 0) ? scale : null,
      });
      if (!mounted) return;
      await _loadMachineIaProfile();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Profil IA machine enregistré', style: GoogleFonts.inter()),
            backgroundColor: const Color(0xFF1B5E20),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur: $e', style: GoogleFonts.inter()),
            backgroundColor: const Color(0xFF4A0A0A),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _savingIaProfile = false);
    }
  }

  bool get _canEditIaMotorProfile =>
      ApiService.canManageFleet ||
      _senderRole == 'superadmin' ||
      _senderRole == 'admin' ||
      _senderRole == 'company_admin';

  /// Texte « type de panne + après X jours » (RUL heures → jours si disponible).
  String _iaHorizonJoursLine() {
    if (_iaRulHeuresIndicatif != null && _iaRulHeuresIndicatif! > 0) {
      final j = (_iaRulHeuresIndicatif! / 24.0).ceil().clamp(1, 9999);
      return 'Estimation : incident sous environ $j jour${j > 1 ? 's' : ''}';
    }
    if (_iaRulEstime != null && _iaRulEstime! > 0) {
      final r = _iaRulEstime!;
      if (r >= 48) {
        final j = (r / 24.0).ceil().clamp(1, 9999);
        return 'Horizon modèle : ~$j jour${j > 1 ? 's' : ''}';
      }
      final j = r.ceil().clamp(1, 999);
      return 'Horizon modèle : ~$j jour${j > 1 ? 's' : ''}';
    }
    return 'Délai avant panne : non estimé (données RUL insuffisantes)';
  }

  /// Message d’alerte uniquement si risque ou notification serveur.
  String? _iaMessagePanneSiApplicable() {
    final n = _notificationMessage.trim();
    if (n.isNotEmpty) return n;
    if (_panneHints.summaryLine.isNotEmpty && _iaProbPanne >= kPanneUiProbMin) {
      return _panneHints.summaryLine;
    }
    if (_iaProbPanne >= 28 || _requiresStop) {
      return _iaAdviceMessage;
    }
    return null;
  }

  String get _teamRoomId => 'team_machine_${_machineId.toUpperCase()}';

  String get _senderRole {
    final r = (widget.viewerRole ?? 'user').toLowerCase().trim();
    if (r.isEmpty) return 'user';
    return r;
  }

  String get _senderName {
    final explicit = (widget.viewerName ?? '').trim();
    if (explicit.isNotEmpty) return explicit;
    switch (_senderRole) {
      case 'technician':
        return 'Technicien';
      case 'client':
        return 'Client';
      case 'conception':
        return 'Conception';
      default:
        return 'Utilisateur';
    }
  }

  bool get _canControlMachine =>
      ApiService.canManageFleet ||
      _senderRole == 'superadmin' ||
      _senderRole == 'admin' ||
      _senderRole == 'company_admin' ||
      _senderRole == 'technician' ||
      _senderRole == 'conception';

  Future<void> _emergencyStopMachine() async {
    if (_isStoppingMachine) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _panel2,
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Color(0xFFFFDAD6), size: 24),
            const SizedBox(width: 10),
            Text(
              'ARRÊT D\'URGENCE',
              style: GoogleFonts.inter(color: _text, fontWeight: FontWeight.w900, fontSize: 18),
            ),
          ],
        ),
        content: Text(
          'Voulez-vous vraiment arrêter la machine $_machineId ?\n\n'
          'Cette action enverra un signal d\'arrêt immédiat au moteur. '
          'Seul un technicien sur site pourra redémarrer la machine.',
          style: GoogleFonts.inter(color: _muted, fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Annuler', style: GoogleFonts.inter(color: _muted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD32F2F),
              foregroundColor: Colors.white,
            ),
            child: Text('CONFIRMER L\'ARRÊT', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isStoppingMachine = true);
    try {
      await ApiService.stopMachine(
        _machineId,
        reason: 'Arrêt d\'urgence - Risque panne: $_iaProbPanne%',
        stoppedBy: _senderName,
      );

      _socket.emit('machine_stop', {
        'machineId': _machineId,
        'stoppedBy': _senderName,
        'role': _senderRole,
        'reason': 'Arrêt d\'urgence - Risque panne: $_iaProbPanne%',
      });

      _socket.emit('chat_message', {
        'roomId': _teamRoomId,
        'from': _senderRole,
        'senderName': 'Système',
        'text': '⚠️ ARRÊT D\'URGENCE déclenché par $_senderName ($_senderRole). '
            'Machine $_machineId arrêtée. Risque de panne: $_iaProbPanne%.',
      });

      if (mounted) {
        setState(() {
          _machineStopped = true;
          _isStoppingMachine = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF1B5E20),
            duration: const Duration(seconds: 5),
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Machine $_machineId arrêtée avec succès.',
                    style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isStoppingMachine = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF4A0A0A),
            content: Text(
              'Erreur: ${e.toString().replaceAll('Exception: ', '')}',
              style: GoogleFonts.inter(color: const Color(0xFFFFDAD6)),
            ),
          ),
        );
      }
    }
  }

  Color get _riskColor => _iaProbPanne >= 70 ? _red : (_iaProbPanne >= 40 ? const Color(0xFFFFD166) : _green);

  String get _riskLabelFr {
    if (_iaProbPanne >= 70) return 'RISQUE ÉLEVÉ';
    if (_iaProbPanne >= 40) return 'SURVEILLANCE';
    return 'RISQUE FAIBLE';
  }

  String get _iaAdviceMessage {
    if (_requiresStop) {
      return _notificationMessage.isNotEmpty
          ? _notificationMessage
          : 'ARRET IMMEDIAT RECOMMANDE: risque de panne critique. Controlez la machine tres vite.';
    }
    if (_iaProbPanne >= 70) {
      return 'Risque de panne moteur: ${_iaProbPanne}%. Intervention recommandee sous 24h.';
    }
    if (_iaProbPanne >= 40) {
      return 'Alerte preventive: risque ${_iaProbPanne}%. Controle recommande sous 48h.';
    }
    return 'Machine stable: risque ${_iaProbPanne}%. Continuer la surveillance normale.';
  }

  IconData get _iaAdviceIcon {
    if (_requiresStop) return Icons.stop_circle_outlined;
    if (_iaProbPanne >= 70) return Icons.warning_amber_rounded;
    if (_iaProbPanne >= 40) return Icons.info_outline;
    return Icons.verified;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Row(
          children: [
            _leftNav(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    _topNav(),
                    const SizedBox(height: 16),
                    Expanded(
                      child: _sideTab == 'technicians'
                          ? _technicianListPanel()
                          : _sideTab == 'maintenance'
                              ? _maintenancePanel()
                              : _sideTab == 'maintenance_team'
                                  ? _maintenanceTeamPanel()
                              : _sideTab == 'history'
                                  ? _historyTabBody()
                                  : LayoutBuilder(
                                      builder: (context, outer) {
                                        return SingleChildScrollView(
                                          physics: const AlwaysScrollableScrollPhysics(),
                                          child: ConstrainedBox(
                                            constraints: BoxConstraints(minWidth: outer.maxWidth),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.stretch,
                                              children: [
                                                _motor3dSection(),
                                                const SizedBox(height: 16),
                                                LayoutBuilder(
                                                  builder: (context, c) {
                                                    final wide = c.maxWidth > 1150;
                                                    if (wide) {
                                                      return Row(
                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                        children: [
                                                          Expanded(flex: 58, child: _sensorsPanel()),
                                                          const SizedBox(width: 16),
                                                          Expanded(flex: 42, child: _aiPanel()),
                                                        ],
                                                      );
                                                    }
                                                    return Column(
                                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                                      children: [
                                                        _sensorsPanel(),
                                                        const SizedBox(height: 16),
                                                        _aiPanel(),
                                                      ],
                                                    );
                                                  },
                                                ),
                                                const SizedBox(height: 16),
                                                _historyPanel(),
                                                const SizedBox(height: 24),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                    ),
                    const SizedBox(height: 12),
                    _bottomTicker(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topNav() {
    final unitTitle = (widget.machineName != null && widget.machineName!.trim().isNotEmpty)
        ? widget.machineName!.trim().toUpperCase()
        : 'MACHINE ${_machineId.length > 6 ? _machineId.substring(_machineId.length - 6) : _machineId}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ASSET TERMINAL // $_machineId',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 10,
                      color: _orange,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.35,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    unitTitle,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 22,
                      color: _text,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'S/N: $_machineId · STATUS: ${_machineStopped ? 'ARRÊT' : (_iaProbPanne >= 70 ? 'INSTABLE' : 'OPÉRATIONNEL')}',
                    style: GoogleFonts.inter(fontSize: 10, color: _text.withOpacity(0.45), fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () {},
              icon: Icon(Icons.notifications_none_rounded, color: _text.withOpacity(0.5), size: 22),
              tooltip: 'Notifications',
            ),
            IconButton(
              onPressed: () {},
              icon: Icon(Icons.grid_view_rounded, color: _text.withOpacity(0.5), size: 22),
              tooltip: 'Vues',
            ),
            IconButton(
              onPressed: () {},
              icon: Icon(Icons.person_outline_rounded, color: _text.withOpacity(0.5), size: 24),
              tooltip: 'Profil',
            ),
            const SizedBox(width: 4),
            _messageBellButton(),
            const SizedBox(width: 4),
            TextButton.icon(
              onPressed: _openTeamMessenger,
              icon: const Icon(Icons.forum_outlined, size: 16, color: _cyan),
              label: Text('Messagerie', style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _cyan, fontWeight: FontWeight.w600)),
            ),
            IconButton(
              onPressed: () {},
              icon: const Icon(Icons.settings_outlined, color: _muted, size: 22),
              tooltip: 'Réglages',
            ),
          ],
        ),
        const SizedBox(height: 14),
        Divider(height: 1, color: Colors.white.withOpacity(0.07)),
      ],
    );
  }

  Widget _messageBellButton() {
    return InkWell(
      onTap: _openTeamMessenger,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: _panel,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white12),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            const Center(
              child: Icon(Icons.mark_chat_unread_outlined, color: _cyan, size: 18),
            ),
            if (_unreadTeamMessages > 0)
              Positioned(
                right: -4,
                top: -4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: _red,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _unreadTeamMessages > 99 ? '99+' : '$_unreadTeamMessages',
                    style: GoogleFonts.inter(
                      fontSize: 9,
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _openTeamMessenger() {
    setState(() => _unreadTeamMessages = 0);
    _socket.emit('join_chat_room', {'roomId': _teamRoomId});
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _panel2,
        title: Text(
          'Messagerie machine $_machineId',
          style: GoogleFonts.inter(color: _text, fontWeight: FontWeight.bold),
        ),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 220,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _panel,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white10),
                ),
                child: ListView(
                  children: _teamChatMessages
                      .map(
                        (m) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text(
                            '${m['senderName'] ?? 'User'}: ${m['text'] ?? ''}',
                            style: GoogleFonts.inter(color: _text, fontSize: 12),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _teamChatController,
                style: GoogleFonts.inter(color: _text),
                decoration: InputDecoration(
                  hintText: 'Écrire un message au client/technicien/conception...',
                  hintStyle: GoogleFonts.inter(color: _muted.withOpacity(0.8), fontSize: 12),
                  border: const OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fermer'),
          ),
          ElevatedButton(
            onPressed: () {
              final text = _teamChatController.text.trim();
              if (text.isEmpty) return;
              _socket.emit('chat_message', {
                'roomId': _teamRoomId,
                'from': _senderRole,
                'senderName': _senderName,
                'text': text,
              });
              _teamChatController.clear();
            },
            child: const Text('Envoyer'),
          ),
        ],
      ),
    );
  }

  Widget _leftNav() {
    return Container(
      width: 232,
      color: _panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('KINETIC.OS', style: GoogleFonts.spaceGrotesk(fontSize: 18, fontWeight: FontWeight.w900, color: _orange, letterSpacing: 0.5)),
                const SizedBox(height: 4),
                Text(
                  'PRECISION PREDICTIVE',
                  style: GoogleFonts.spaceGrotesk(fontSize: 8, color: _text.withOpacity(0.55), letterSpacing: 1.6, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          _kineticNavItem(
            label: 'DASHBOARD',
            icon: Icons.dashboard_outlined,
            active: false,
            onTap: () {
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
            },
          ),
          _kineticNavItem(
            label: 'ASSETS',
            icon: Icons.precision_manufacturing_outlined,
            active: _sideTab == 'dashboard',
            onTap: () => setState(() => _sideTab = 'dashboard'),
          ),
          _kineticNavItem(
            label: 'INTELLIGENCE',
            icon: Icons.psychology_outlined,
            active: false,
            onTap: () => setState(() => _sideTab = 'dashboard'),
          ),
          _kineticNavItem(
            label: 'HISTORY',
            icon: Icons.history_rounded,
            active: _sideTab == 'history',
            onTap: () => setState(() => _sideTab = 'history'),
          ),
          _kineticNavItem(
            label: 'CONFIGURATION',
            icon: Icons.tune_rounded,
            active: _sideTab == 'maintenance',
            onTap: () => setState(() => _sideTab = 'maintenance'),
          ),
          _kineticNavItem(
            label: 'ÉQUIPE',
            icon: Icons.groups_outlined,
            active: _sideTab == 'technicians',
            onTap: () {
              setState(() => _sideTab = 'technicians');
              if (_techniciansForMachine == null && !_loadingTechnicians) {
                _loadTechniciansForMachine();
              }
            },
          ),
          _kineticNavItem(
            label: 'ÉQUIPE MAINTENANCE',
            icon: Icons.engineering_outlined,
            active: _sideTab == 'maintenance_team',
            onTap: () {
              setState(() => _sideTab = 'maintenance_team');
              if (_techniciansForMachine == null && !_loadingTechnicians) {
                _loadTechniciansForMachine();
              }
            },
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => setState(() => _sideTab = 'dashboard'),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A0B12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _orange.withOpacity(0.35)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _lastMqttPacketAt != null ? _green : _orange,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: (_lastMqttPacketAt != null ? _green : _orange).withOpacity(0.45),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'SYSTEM LIVE',
                              style: GoogleFonts.spaceGrotesk(fontSize: 11, color: _orange, fontWeight: FontWeight.w800, letterSpacing: 1.4),
                            ),
                            Text(
                              _machineStopped ? 'Arrêt' : (_lastMqttPacketAt != null ? 'Flux MQTT' : 'Veille'),
                              style: GoogleFonts.inter(fontSize: 9, color: _text.withOpacity(0.65)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _kineticNavItem({
    required String label,
    required IconData icon,
    required bool active,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 0),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 3,
                  decoration: BoxDecoration(
                    color: active ? _orange : Colors.transparent,
                    borderRadius: const BorderRadius.horizontal(right: Radius.circular(2)),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 16, 10),
                    child: Row(
                      children: [
                        Icon(icon, size: 18, color: active ? _orange : _muted.withOpacity(0.45)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            label,
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 10,
                              letterSpacing: 1.15,
                              fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                              color: active ? _text : _muted.withOpacity(0.75),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _loadTechniciansForMachine() async {
    setState(() => _loadingTechnicians = true);
    try {
      debugPrint('Chargement techniciens pour machine: $_machineId');
      final List<Map<String, dynamic>> filtered = <Map<String, dynamic>>[];

      // 1. Techniciens terrain (Répertoire équipe) - Afficher TOUT
      try {
        final team = await ApiService.getTeamDirectory();
        debugPrint('Equipe recue de l\'API: ${team.length} membres');
        for (final member in team) {
          final kind = (member['directoryKind'] ?? '').toString();
          // On garde tout le monde du répertoire, on filtrera par machineId dans la vue
          final rawMap = member['raw'];
          final raw = rawMap is Map ? Map<String, dynamic>.from(rawMap) : <String, dynamic>{};
          
          filtered.add({
            ...raw,
            'directoryKind': kind,
            'name': member['name'] ?? raw['name'] ?? '',
            'email': member['email'] ?? raw['email'] ?? '',
            'specialty': member['specialization'] ?? raw['specialization'] ?? 'Generaliste',
            'technicianId': raw['technicianId'] ?? member['id'] ?? '',
          });
        }
      } catch (_) {}

      // 2. Personnel de Maintenance (Maintenance Man) - Afficher TOUT
      try {
        final agents = await ApiService.getMaintenanceAgents();
        debugPrint('Agents maintenance recus de l\'API: ${agents.length} membres');
        for (final agent in agents) {
          filtered.add({
            ...agent,
            'directoryKind': 'maintenance_agent',
            'name': '${agent['firstName']} ${agent['lastName']}',
            'email': agent['email'] ?? '',
            'specialty': 'Maintenance Lead',
            'id': agent['id'] ?? agent['maintenanceAgentId'],
          });
        }
      } catch (e) {
        debugPrint('Erreur chargement agents maintenance: $e');
      }

      debugPrint('Total techniciens filtres: ${filtered.length}');
      if (mounted) setState(() { _techniciansForMachine = filtered; _loadingTechnicians = false; });
    } catch (e) {
      if (mounted) setState(() { _techniciansForMachine = []; _loadingTechnicians = false; });
    }
  }

  Widget _motor3dSection() {
    final rendement = (100 - _iaProbPanne * 0.82).clamp(38.0, 99.2);
    final alerteCritique = _machineStopped || _requiresStop || _iaProbPanne >= 70;
    final motorTitle = (widget.machineName != null && widget.machineName!.trim().isNotEmpty)
        ? widget.machineName!.trim().toUpperCase()
        : 'MOTEUR INDUSTRIEL';
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white.withOpacity(0.06)),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF14162A), Color(0xFF0D0E1B)],
          ),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              right: -40,
              top: -30,
              child: Icon(Icons.blur_circular, size: 180, color: _orange.withOpacity(0.06)),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 260,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                _cyan.withOpacity(0.04),
                                Colors.transparent,
                                Colors.black.withOpacity(0.45),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Image.asset(
                            _motor3dAsset,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => Icon(Icons.precision_manufacturing, size: 100, color: _muted.withOpacity(0.25)),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 16,
                        right: 16,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: _panel2.withOpacity(0.92),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white.withOpacity(0.08)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('RENDEMENT', style: GoogleFonts.spaceGrotesk(fontSize: 8, color: _muted.withOpacity(0.8), letterSpacing: 1.2)),
                              Text(
                                '${rendement.toStringAsFixed(1)}%',
                                style: GoogleFonts.spaceGrotesk(fontSize: 20, color: _cyan, fontWeight: FontWeight.w900),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        left: 18,
                        bottom: 16,
                        right: 18,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        width: 10,
                                        height: 10,
                                        decoration: BoxDecoration(
                                          color: alerteCritique ? const Color(0xFFFF3B3B) : _green,
                                          shape: BoxShape.circle,
                                          boxShadow: [
                                            BoxShadow(
                                              color: (alerteCritique ? const Color(0xFFFF3B3B) : _green).withOpacity(0.55),
                                              blurRadius: 10,
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        alerteCritique ? 'ALERTE CRITIQUE' : 'NOMINAL',
                                        style: GoogleFonts.spaceGrotesk(
                                          fontSize: 10,
                                          color: alerteCritique ? const Color(0xFFFF3B3B) : _green,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 1.1,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    motorTitle,
                                    style: GoogleFonts.spaceGrotesk(fontSize: 20, color: _text, fontWeight: FontWeight.w900, letterSpacing: -0.3),
                                  ),
                                  Text(
                                    'S/N: $_machineId',
                                    style: GoogleFonts.inter(fontSize: 10, color: _text.withOpacity(0.5)),
                                  ),
                                ],
                              ),
                            ),
                            if (_canControlMachine) ...[
                              _emergencyStopButton(),
                              const SizedBox(width: 8),
                            ],
                            ElevatedButton.icon(
                              onPressed: _changeMotorImage,
                              icon: const Icon(Icons.image_outlined, size: 16),
                              label: Text('Image', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _orange,
                                foregroundColor: const Color(0xFF1A0A00),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_machineStopped)
                        Positioned.fill(
                          child: Container(
                            color: Colors.black.withOpacity(0.55),
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.power_off, color: Color(0xFFFF8A80), size: 44),
                                  const SizedBox(height: 8),
                                  Text('MOTEUR ARRÊTÉ', style: GoogleFonts.spaceGrotesk(color: const Color(0xFFFF8A80), fontSize: 14, fontWeight: FontWeight.w800)),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                  decoration: BoxDecoration(
                    color: _panel2.withOpacity(0.65),
                    border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05))),
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _motorInfoChip('Machine', _machineId, _cyan),
                        const SizedBox(width: 8),
                        _motorInfoChip('Zone', _zone, _orange),
                        const SizedBox(width: 8),
                        _motorInfoChip('Temp.', '${_thermal.toStringAsFixed(1)}°C', _thermal >= 75 ? _red : _green, panneKey: 'thermal'),
                        const SizedBox(width: 8),
                        _motorInfoChip('Risque IA', '$_iaProbPanne%', _riskColor),
                        const SizedBox(width: 8),
                        _motorInfoChip('Statut', _machineStopped ? 'ARRÊTÉ' : 'EN MARCHE', _machineStopped ? _red : _green),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _emergencyStopButton() {
    if (_machineStopped) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: _red.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _red.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.power_off, size: 16, color: _red),
            const SizedBox(width: 6),
            Text('ARRÊTÉ', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: _red)),
          ],
        ),
      );
    }

    final isUrgent = _iaProbPanne >= 70;
    return ElevatedButton.icon(
      onPressed: _isStoppingMachine ? null : _emergencyStopMachine,
      icon: _isStoppingMachine
          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : const Icon(Icons.power_settings_new, size: 18),
      label: Text(
        isUrgent ? 'ARRÊT D\'URGENCE' : 'ARRÊTER MACHINE',
        style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: isUrgent ? const Color(0xFFD32F2F) : _green,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        elevation: isUrgent ? 6 : 2,
        shadowColor: isUrgent ? const Color(0xFFD32F2F).withOpacity(0.5) : null,
      ),
    );
  }

  Widget _motorInfoChip(String label, String value, Color accent, {String? panneKey}) {
    final stress = panneKey != null && _panneHints.highlightMetrics.contains(panneKey);
    return AnimatedBuilder(
      animation: _pulseCtrl,
      builder: (_, __) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _panel,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: stress
                  ? const Color(0xFFFF7B7B).withOpacity(0.55 + 0.4 * _pulseCtrl.value)
                  : accent.withOpacity(0.3),
              width: stress ? 2.2 : 1,
            ),
            boxShadow: stress
                ? [BoxShadow(color: const Color(0xFFFF7B7B).withOpacity(0.22 * _pulseCtrl.value), blurRadius: 8)]
                : null,
          ),
          child: Column(
            children: [
              Text(label,
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 9, color: _muted, letterSpacing: 1)),
              const SizedBox(height: 2),
              Text(value,
                  style: GoogleFonts.inter(
                      fontSize: 13,
                      color: stress ? const Color(0xFFFFB4AB) : accent,
                      fontWeight: FontWeight.w800)),
            ],
          ),
        );
      },
    );
  }

  void _changeMotorImage() {
    final images = [
      'assets/images/motor_3d_default.png',
    ];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _panel2,
        title: Text('Changer l\'image 3D du moteur',
            style: GoogleFonts.inter(color: _text, fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: 500,
          height: 280,
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: images.length,
            itemBuilder: (_, i) {
              final selected = _motor3dAsset == images[i];
              return GestureDetector(
                onTap: () {
                  setState(() => _motor3dAsset = images[i]);
                  Navigator.pop(ctx);
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: _panel,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selected ? _orange : Colors.white10,
                      width: selected ? 2 : 1,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: Image.asset(images[i], fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const Center(child: Icon(Icons.broken_image, color: _muted))),
                  ),
                ),
              );
            },
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
  }

  Widget _sensorsPanel() {
    final irLabel = _infrared <= 0 ? 'N/A' : (_infrared < 1.5 ? 'FAIBLE' : 'ACTIF');
    return Container(
      decoration: BoxDecoration(
        color: _panel2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(Icons.sensors_rounded, size: 18, color: _orange.withOpacity(0.9)),
              const SizedBox(width: 10),
              Text(
                'TÉLÉMÉTRIE LIVE',
                style: GoogleFonts.spaceGrotesk(fontSize: 11, fontWeight: FontWeight.w800, color: _text, letterSpacing: 1.4),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: (_lastMqttPacketAt != null ? _green : _red).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: (_lastMqttPacketAt != null ? _green : _red).withOpacity(0.35)),
                ),
                child: Text(
                  _lastMqttPacketAt != null ? 'POLLING' : 'OFFLINE',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: _lastMqttPacketAt != null ? _green : _red,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                '$_wifiRssi dBm · $_zone',
                style: GoogleFonts.inter(fontSize: 9, color: _text.withOpacity(0.4)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _panel,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withOpacity(0.05)),
            ),
            child: Row(
              children: [
                Icon(
                  _lastMqttPacketAt == null ? Icons.sync_disabled_rounded : Icons.hub_rounded,
                  size: 14,
                  color: _lastMqttPacketAt == null ? _red.withOpacity(0.85) : _cyan.withOpacity(0.85),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _lastMqttPacketAt == null
                        ? 'MQTT · attente flux · $_machineId'
                        : 'MQTT · $_mqttPacketCount paquets · ${_lastMqttPacketAt!.hour.toString().padLeft(2, '0')}:${_lastMqttPacketAt!.minute.toString().padLeft(2, '0')}:${_lastMqttPacketAt!.second.toString().padLeft(2, '0')}',
                    style: GoogleFonts.inter(fontSize: 10, color: _text.withOpacity(0.55), height: 1.2),
                  ),
                ),
              ],
            ),
          ),
          if (_lastMqttPacketAt == null) ...[
            const SizedBox(height: 8),
            Text(
              'Valeurs issues de la dernière télémétrie API jusqu’à réception MQTT.',
              style: GoogleFonts.inter(fontSize: 9, height: 1.35, color: _muted.withOpacity(0.75)),
            ),
          ],
          const SizedBox(height: 14),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 3,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.22,
            children: [
              _sensorTile('THERMIQUE', '${_thermal.toStringAsFixed(1)} °C', Icons.thermostat_rounded, _thermal >= 75 ? _red : _cyan, panneKey: 'thermal'),
              _sensorTile(
                'PRESSION',
                _pressure > 0 && _pressure < 2 ? '${_pressure.toStringAsFixed(3)} BAR' : '${_pressure.toStringAsFixed(1)} BAR',
                Icons.speed_rounded,
                _cyan,
                panneKey: 'pressure',
              ),
              _sensorTile('PUISSANCE', '${_power.toStringAsFixed(1)} kW', Icons.bolt_rounded, const Color(0xFFFFD54F), panneKey: 'power'),
              _sensorTile('VIBRATION', '${_vibration.toStringAsFixed(2)} mm/s', Icons.vibration_rounded, _vibration >= 4 ? _red : _cyan, panneKey: 'vibration'),
              _sensorTile('MAGNÉTIQUE', '${_magnetic.toStringAsFixed(2)} mT', Icons.explore_rounded, const Color(0xFF90CAF9)),
              _sensorTile('INFRA-ROUGE', irLabel, Icons.local_fire_department_outlined, const Color(0xFFFFAB91)),
              _sensorTile('RPM', '${_rpm.toStringAsFixed(0)} tr/min', Icons.rotate_right_rounded, _cyan),
              _sensorTile('COUPLE', '${_torque.toStringAsFixed(1)} Nm', Icons.settings_input_component_rounded, const Color(0xFFB39DDB)),
              _sensorTile('PRÉSENCE', _presence >= 0.5 ? 'OK' : '—', _presence >= 0.5 ? Icons.person_rounded : Icons.person_off_rounded, _presence >= 0.5 ? _green : _muted),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sensorTile(String label, String value, IconData icon, Color accent, {String panneKey = ''}) {
    final stress = panneKey.isNotEmpty && _panneHints.highlightMetrics.contains(panneKey);
    return AnimatedBuilder(
      animation: _pulseCtrl,
      builder: (_, __) {
        return Container(
          decoration: BoxDecoration(
            color: stress ? const Color(0xFFFF7B7B).withOpacity(0.07 + 0.1 * _pulseCtrl.value) : _panel,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: stress
                  ? const Color(0xFFFF7B7B).withOpacity(0.5 + 0.45 * _pulseCtrl.value)
                  : Colors.white.withOpacity(0.06),
              width: stress ? 2 : 1,
            ),
            boxShadow: stress
                ? [BoxShadow(color: const Color(0xFFFF7B7B).withOpacity(0.18 * _pulseCtrl.value), blurRadius: 10)]
                : null,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: (stress ? const Color(0xFFFF7B7B) : accent).withOpacity(0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: stress ? const Color(0xFFFFB4AB) : accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(label,
                              style: GoogleFonts.spaceGrotesk(
                                  fontSize: 9, color: _muted.withOpacity(0.65), fontWeight: FontWeight.w700, letterSpacing: 0.8)),
                        ),
                        if (stress)
                          Text('PANNE',
                              style: GoogleFonts.spaceGrotesk(
                                  fontSize: 7, color: const Color(0xFFFF7B7B), fontWeight: FontWeight.w800)),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(value,
                        style: GoogleFonts.spaceGrotesk(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: stress ? const Color(0xFFFFB4AB) : _text,
                            letterSpacing: -0.2),
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 8),
                    Container(
                      height: 3,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        gradient: LinearGradient(
                          colors: [
                            (stress ? const Color(0xFFFF7B7B) : accent).withOpacity(stress ? 0.95 : 0.35),
                            (stress ? const Color(0xFFFF7B7B) : accent).withOpacity(0.05),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _technicianListPanel() {
    if (_loadingTechnicians) {
      return const Center(child: Padding(padding: EdgeInsets.all(60), child: CircularProgressIndicator(color: _orange)));
    }
    final allTechs = _techniciansForMachine ?? [];
    
    // Filtre par machineId
    final techs = allTechs.where((t) {
      final List? assigned = t['machineIds'] is List ? t['machineIds'] as List : null;
      if (assigned == null) return false;
      return assigned.map((e) => e.toString().toUpperCase()).contains(_machineId.toUpperCase());
    }).toList();
    return ListView(
      padding: const EdgeInsets.all(4),
      children: [
        Row(children: [
          Container(width: 3, height: 18, decoration: BoxDecoration(color: _orange, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 8),
          Text('ÉQUIPE MACHINE', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w800, color: _text, letterSpacing: 1.0)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: _panel2, borderRadius: BorderRadius.circular(12)),
            child: Text('${techs.length}', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: _orange)),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => AddTechnicianPage(onBack: () {
                _loadTechniciansForMachine();
                Navigator.pop(context);
              })));
            },
            icon: const Icon(Icons.person_add_rounded, size: 14, color: _orange),
            label: Text('Ajouter', style: GoogleFonts.spaceGrotesk(fontSize: 11, color: _orange, fontWeight: FontWeight.w600)),
          ),
        ]),
        const SizedBox(height: 12),
        if (techs.isEmpty)
          Container(
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white10)),
            child: Column(children: [
              const Icon(Icons.engineering_rounded, size: 40, color: _panel3),
              const SizedBox(height: 12),
              Text('Aucun technicien/maintenance assigné', style: GoogleFonts.inter(fontSize: 13, color: _muted, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('Ajoutez un membre équipe pour cette machine', style: GoogleFonts.spaceGrotesk(fontSize: 11, color: _muted.withOpacity(0.6))),
            ]),
          )
        else
          ...techs.map((t) => _technicianCard(t)),
      ],
    );
  }

  Widget _technicianCard(Map<String, dynamic> tech) {
    final kind = (tech['directoryKind'] ?? 'technician').toString();
    final isMaintenance = kind == 'maintenance';
    final name = tech['name']?.toString() ?? 'Sans nom';
    final email = tech['email']?.toString() ?? '';
    final phone = tech['phone']?.toString() ?? '';
    final specialty = tech['specialty']?.toString() ?? (isMaintenance ? 'Maintenance' : 'Généraliste');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: InkWell(
        onTap: () {
          if (isMaintenance) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => MaintenanceAgentDetailPage(
                  member: {
                    ...tech,
                    'directoryKind': 'maintenance',
                    'displayId': tech['maintenanceAgentId'] ?? tech['id'] ?? '',
                  },
                ),
              ),
            );
            return;
          }
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => const TechnicianProfilePage(),
            settings: RouteSettings(arguments: {
              'viewerRole': 'superadmin',
              'name': tech['name'] ?? '',
              'id': tech['technicianId'] ?? tech['_id'] ?? '',
              'email': tech['email'] ?? '',
              'phone': tech['phone'] ?? '',
              'specialization': tech['specialty'] ?? 'Technicien',
              'status': 'EN SERVICE',
              'machineIds': tech['machineIds'] ?? [],
              'loginPassword': tech['loginPassword'] ?? '********',
              'location': tech['location'] ?? '',
            }),
          ));
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(color: _cyan.withOpacity(0.10), borderRadius: BorderRadius.circular(12)),
              child: Center(child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w800, color: _cyan))),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: _text)),
              const SizedBox(height: 3),
              Row(children: [
                Icon(Icons.work_rounded, size: 11, color: _muted.withOpacity(0.5)),
                const SizedBox(width: 4),
                Text(specialty, style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _muted.withOpacity(0.7))),
                if (email.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  Icon(Icons.email_rounded, size: 11, color: _muted.withOpacity(0.5)),
                  const SizedBox(width: 4),
                  Flexible(child: Text(email, style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _muted.withOpacity(0.7)), overflow: TextOverflow.ellipsis)),
                ],
              ]),
              if (phone.isNotEmpty) ...[
                const SizedBox(height: 2),
                Row(children: [
                  Icon(Icons.phone_rounded, size: 11, color: _muted.withOpacity(0.5)),
                  const SizedBox(width: 4),
                  Text(phone, style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _muted.withOpacity(0.7))),
                ]),
              ],
            ])),
            const Icon(Icons.chevron_right_rounded, size: 20, color: _panel3),
          ]),
        ),
      ),
    );
  }

  String _maintenanceUiStatus(String raw) {
    switch (raw.toUpperCase()) {
      case 'PENDING':
        return 'Planifiée';
      case 'IN_PROGRESS':
        return 'En cours';
      case 'COMPLETED':
        return 'Terminée';
      default:
        return raw.isEmpty ? 'Planifiée' : raw;
    }
  }

  String _maintenanceApiStatus(String uiOrApi) {
    switch (uiOrApi.toUpperCase()) {
      case 'PLANIFIÉE':
      case 'PLANIFIEE':
      case 'PENDING':
        return 'PENDING';
      case 'EN COURS':
      case 'IN_PROGRESS':
        return 'IN_PROGRESS';
      case 'TERMINÉE':
      case 'TERMINEE':
      case 'COMPLETED':
        return 'COMPLETED';
      default:
        return uiOrApi.toUpperCase();
    }
  }

  String _fmtDate(dynamic raw) {
    if (raw == null) return '—';
    final d = DateTime.tryParse(raw.toString());
    if (d == null) return raw.toString();
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final yyyy = d.year.toString();
    return '$dd/$mm/$yyyy';
  }

  Future<void> _loadMaintenanceOrders() async {
    setState(() {
      _loadingMaintenance = true;
      _maintenanceError = null;
    });
    try {
      final all = await ApiService.getMaintenanceOrders();
      final filtered = all.where((o) {
        final mid = (o['machineId'] ?? '').toString();
        return mid == _machineId || _acceptedMachineIds.contains(mid);
      }).toList();
      final mapped = filtered.map((o) {
        final status = _maintenanceUiStatus((o['status'] ?? '').toString());
        final typeRaw = (o['type'] ?? '').toString().trim();
        final type = typeRaw.isEmpty ? 'Corrective' : typeRaw;
        return <String, dynamic>{
          'id': (o['id'] ?? '').toString(),
          'type': type,
          'priority': (o['priority'] ?? 'MEDIUM').toString().toUpperCase(),
          'statusRaw': (o['status'] ?? 'PENDING').toString().toUpperCase(),
          'status': status,
          'date': _fmtDate(o['createdAt']),
          'desc': (o['description'] ?? '').toString(),
          'tech': (o['technicianId'] ?? 'Intervention').toString(),
          'rootCause': (o['rootCause'] ?? '').toString(),
          'actionTaken': (o['actionTaken'] ?? '').toString(),
          'downtimeMinutes': o['downtimeMinutes'],
          'closeNote': (o['closeNote'] ?? '').toString(),
        };
      }).toList();
      if (!mounted) return;
      setState(() {
        _maintenanceOrders = mapped;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _maintenanceError = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _loadingMaintenance = false;
      });
    }
  }

  Future<void> _showCreateCorrectiveDialog() async {
    final descCtrl = TextEditingController();
    final techCtrl = TextEditingController();
    String priority = 'MEDIUM';

    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _panel2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Nouvelle maintenance corrective', style: GoogleFonts.inter(color: _text, fontWeight: FontWeight.w800)),
        content: SizedBox(
          width: 430,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: descCtrl,
                style: GoogleFonts.inter(color: _text),
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Description panne',
                  labelStyle: GoogleFonts.inter(color: _muted),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: techCtrl,
                style: GoogleFonts.inter(color: _text),
                decoration: InputDecoration(
                  labelText: 'Technicien (optionnel)',
                  labelStyle: GoogleFonts.inter(color: _muted),
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: priority,
                dropdownColor: _panel2,
                style: GoogleFonts.inter(color: _text),
                items: const [
                  DropdownMenuItem(value: 'LOW', child: Text('LOW')),
                  DropdownMenuItem(value: 'MEDIUM', child: Text('MEDIUM')),
                  DropdownMenuItem(value: 'HIGH', child: Text('HIGH')),
                  DropdownMenuItem(value: 'CRITICAL', child: Text('CRITICAL')),
                ],
                onChanged: (v) => priority = (v ?? 'MEDIUM'),
                decoration: InputDecoration(
                  labelText: 'Priorité',
                  labelStyle: GoogleFonts.inter(color: _muted),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Annuler', style: GoogleFonts.inter(color: _muted)),
          ),
          ElevatedButton(
            onPressed: () async {
              final desc = descCtrl.text.trim();
              if (desc.isEmpty) return;
              try {
                final info = await ApiService.getMachineInfo(_machineId);
                final companyId = (info['companyId'] ?? info['company_id'] ?? '').toString();
                if (companyId.isEmpty) {
                  throw Exception('CompanyId machine introuvable');
                }
                final payload = <String, dynamic>{
                  'machineId': _machineId,
                  'companyId': companyId,
                  'description': desc,
                  'priority': priority,
                  'type': 'Corrective',
                  if (techCtrl.text.trim().isNotEmpty) 'technicianId': techCtrl.text.trim(),
                };
                await ApiService.createMaintenanceOrder(payload);
                if (!mounted) return;
                Navigator.pop(ctx, true);
              } catch (e) {
                if (!ctx.mounted) return;
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(content: Text('Création impossible: $e')),
                );
              }
            },
            child: const Text('Créer'),
          ),
        ],
      ),
    );
    if (created == true) {
      await _loadMaintenanceOrders();
    }
  }

  Future<void> _showCloseCorrectiveDialog(Map<String, dynamic> order) async {
    final rootCauseCtrl = TextEditingController(text: (order['rootCause'] ?? '').toString());
    final actionCtrl = TextEditingController(text: (order['actionTaken'] ?? '').toString());
    final downtimeCtrl = TextEditingController(
      text: order['downtimeMinutes'] == null ? '' : '${order['downtimeMinutes']}',
    );
    final noteCtrl = TextEditingController(text: (order['closeNote'] ?? '').toString());

    final closed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _panel2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Clôture corrective', style: GoogleFonts.inter(color: _text, fontWeight: FontWeight.w800)),
        content: SizedBox(
          width: 430,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: rootCauseCtrl,
                  style: GoogleFonts.inter(color: _text),
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: 'Cause racine *',
                    labelStyle: GoogleFonts.inter(color: _muted),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: actionCtrl,
                  style: GoogleFonts.inter(color: _text),
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: 'Action réalisée *',
                    labelStyle: GoogleFonts.inter(color: _muted),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: downtimeCtrl,
                  style: GoogleFonts.inter(color: _text),
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Durée arrêt (minutes)',
                    labelStyle: GoogleFonts.inter(color: _muted),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: noteCtrl,
                  style: GoogleFonts.inter(color: _text),
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: 'Note de clôture',
                    labelStyle: GoogleFonts.inter(color: _muted),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Annuler', style: GoogleFonts.inter(color: _muted)),
          ),
          ElevatedButton(
            onPressed: () async {
              final rootCause = rootCauseCtrl.text.trim();
              final actionTaken = actionCtrl.text.trim();
              if (rootCause.isEmpty || actionTaken.isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Cause racine et action sont obligatoires.')),
                );
                return;
              }
              try {
                final extra = <String, dynamic>{
                  'rootCause': rootCause,
                  'actionTaken': actionTaken,
                  'closeNote': noteCtrl.text.trim(),
                };
                final d = int.tryParse(downtimeCtrl.text.trim());
                if (d != null && d >= 0) {
                  extra['downtimeMinutes'] = d;
                }
                await ApiService.updateMaintenanceOrderStatus(
                  (order['id'] ?? '').toString(),
                  'COMPLETED',
                  extraPayload: extra,
                );
                if (!mounted) return;
                Navigator.pop(ctx, true);
              } catch (e) {
                if (!ctx.mounted) return;
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(content: Text('Clôture impossible: $e')),
                );
              }
            },
            child: const Text('Clôturer'),
          ),
        ],
      ),
    );
    if (closed == true) {
      await _loadMaintenanceOrders();
    }
  }

  Future<void> _openConfigureMaintenanceMan() async {
    try {
      final info = await ApiService.getMachineInfo(_machineId);
      final companyId = (info['companyId'] ?? info['company_id'] ?? '').toString();
      if (!mounted) return;
      if (companyId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('CompanyId machine introuvable.')),
        );
        return;
      }
      final ok = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => AddMaintenanceAgentPage(
            initialData: {
              'clientId': companyId,
              'machineIds': [_machineId],
            },
          ),
        ),
      );
      if (ok == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Compte maintenance enregistré.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ouverture configuration impossible: $e')),
      );
    }
  }

  Widget _maintenancePanel() {
    final maintenanceList = _maintenanceOrders.where((m) {
      final s = (m['statusRaw'] ?? '').toString().toUpperCase();
      final p = (m['priority'] ?? '').toString().toUpperCase();
      final matchStatus = _maintenanceFilterStatus == 'ALL' || s == _maintenanceFilterStatus;
      final matchPriority = _maintenanceFilterPriority == 'ALL' || p == _maintenanceFilterPriority;
      return matchStatus && matchPriority;
    }).toList();
    final inProgressCount = maintenanceList
        .where((m) => m['status'] == 'Planifiée' || m['status'] == 'En cours')
        .length;

    return ListView(
      padding: const EdgeInsets.all(4),
      children: [
        Row(children: [
          Container(width: 3, height: 18, decoration: BoxDecoration(color: _orange, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 8),
          Text('MAINTENANCE', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w800, color: _text, letterSpacing: 1.0)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: _panel2, borderRadius: BorderRadius.circular(12)),
            child: Text('${maintenanceList.length}', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: _orange)),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Rafraîchir',
            onPressed: _loadingMaintenance ? null : _loadMaintenanceOrders,
            icon: Icon(Icons.refresh_rounded, color: _muted.withOpacity(0.9)),
          ),
          ElevatedButton.icon(
            onPressed: _showCreateCorrectiveDialog,
            icon: const Icon(Icons.add_task_rounded, size: 16),
            label: Text('Corrective', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(
              backgroundColor: _orange,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
          if (ApiService.isSuperAdmin) ...[
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _openConfigureMaintenanceMan,
              icon: const Icon(Icons.engineering_rounded, size: 16),
              label: Text('Maint. Man', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
            ),
          ],
        ]),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _maintenanceFilterStatus,
                dropdownColor: _panel2,
                style: GoogleFonts.inter(color: _text),
                items: const [
                  DropdownMenuItem(value: 'ALL', child: Text('Tous statuts')),
                  DropdownMenuItem(value: 'PENDING', child: Text('Planifiée')),
                  DropdownMenuItem(value: 'IN_PROGRESS', child: Text('En cours')),
                  DropdownMenuItem(value: 'COMPLETED', child: Text('Terminée')),
                ],
                onChanged: (v) => setState(() => _maintenanceFilterStatus = v ?? 'ALL'),
                decoration: InputDecoration(
                  isDense: true,
                  labelText: 'Filtre statut',
                  labelStyle: GoogleFonts.inter(color: _muted.withOpacity(0.9), fontSize: 11),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _maintenanceFilterPriority,
                dropdownColor: _panel2,
                style: GoogleFonts.inter(color: _text),
                items: const [
                  DropdownMenuItem(value: 'ALL', child: Text('Toutes priorités')),
                  DropdownMenuItem(value: 'LOW', child: Text('LOW')),
                  DropdownMenuItem(value: 'MEDIUM', child: Text('MEDIUM')),
                  DropdownMenuItem(value: 'HIGH', child: Text('HIGH')),
                  DropdownMenuItem(value: 'CRITICAL', child: Text('CRITICAL')),
                ],
                onChanged: (v) => setState(() => _maintenanceFilterPriority = v ?? 'ALL'),
                decoration: InputDecoration(
                  isDense: true,
                  labelText: 'Filtre priorité',
                  labelStyle: GoogleFonts.inter(color: _muted.withOpacity(0.9), fontSize: 11),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_maintenanceError != null && _maintenanceError!.isNotEmpty) ...[
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _red.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _red.withOpacity(0.25)),
            ),
            child: Text(
              'Chargement maintenance: $_maintenanceError',
              style: GoogleFonts.inter(fontSize: 11, color: _red),
            ),
          ),
        ],
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 3,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 2.8,
          children: [
            _maintenanceStat('Total', '${maintenanceList.length}', Icons.assignment_rounded, _cyan),
            _maintenanceStat('En cours', '$inProgressCount', Icons.schedule_rounded, const Color(0xFFFFD54F)),
            _maintenanceStat('Terminées', '${maintenanceList.where((m) => m['status'] == 'Terminée').length}', Icons.check_circle_rounded, _green),
          ],
        ),
        const SizedBox(height: 14),
        if (_loadingMaintenance)
          const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator())),
        if (!_loadingMaintenance && maintenanceList.isEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(12)),
            child: Text(
              'Aucun ordre corrective pour cette machine.',
              style: GoogleFonts.inter(color: _muted),
            ),
          ),
        ...maintenanceList.map((m) => _maintenanceCard(m)),
      ],
    );
  }

  Widget _maintenanceStat(String label, String value, IconData icon, Color accent) {
    return Container(
      decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white.withOpacity(0.06))),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(children: [
        Container(
          width: 34, height: 34,
          decoration: BoxDecoration(color: accent.withOpacity(0.10), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, size: 16, color: accent),
        ),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(label, style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _muted.withOpacity(0.6), fontWeight: FontWeight.w500)),
          Text(value, style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w800, color: _text)),
        ]),
      ]),
    );
  }

  Widget _maintenanceCard(Map<String, dynamic> m) {
    final statusRaw = (m['statusRaw'] ?? '').toString().toUpperCase();
    final isActive = statusRaw == 'PENDING' || statusRaw == 'IN_PROGRESS';
    final typeColor = m['type'] == 'Corrective' ? _red
        : m['type'] == 'Prédictive' ? const Color(0xFFB39DDB)
        : _cyan;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isActive ? _orange.withOpacity(0.3) : Colors.white.withOpacity(0.06)),
      ),
      child: InkWell(
        onTap: () => _showMaintenanceDetail(m),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(color: typeColor.withOpacity(0.10), borderRadius: BorderRadius.circular(12)),
              child: Icon(
                m['type'] == 'Corrective' ? Icons.build_rounded
                    : m['type'] == 'Prédictive' ? Icons.psychology_rounded
                    : Icons.event_rounded,
                size: 20, color: typeColor,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(color: typeColor.withOpacity(0.12), borderRadius: BorderRadius.circular(4)),
                  child: Text((m['type'] ?? '').toString(), style: GoogleFonts.spaceGrotesk(fontSize: 9, color: typeColor, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(color: (isActive ? _orange : _green).withOpacity(0.12), borderRadius: BorderRadius.circular(4)),
                  child: Text((m['status'] ?? '').toString(), style: GoogleFonts.spaceGrotesk(fontSize: 9, color: isActive ? _orange : _green, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(color: _panel3, borderRadius: BorderRadius.circular(4)),
                  child: Text((m['priority'] ?? 'MEDIUM').toString(), style: GoogleFonts.spaceGrotesk(fontSize: 9, color: _muted, fontWeight: FontWeight.w700)),
                ),
              ]),
              const SizedBox(height: 5),
              Text((m['desc'] ?? '').toString(), style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: _text)),
              const SizedBox(height: 3),
              Row(children: [
                Icon(Icons.calendar_today_rounded, size: 10, color: _muted.withOpacity(0.5)),
                const SizedBox(width: 4),
                Text((m['date'] ?? '—').toString(), style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _muted.withOpacity(0.7))),
                const SizedBox(width: 12),
                Icon(Icons.label_rounded, size: 10, color: _muted.withOpacity(0.5)),
                const SizedBox(width: 4),
                Text((m['tech'] ?? '—').toString(), style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _muted.withOpacity(0.7))),
              ]),
            ])),
            const Icon(Icons.chevron_right_rounded, size: 20, color: _panel3),
          ]),
        ),
      ),
    );
  }

  void _showMaintenanceDetail(Map<String, dynamic> m) {
    final statusRaw = (m['statusRaw'] ?? '').toString().toUpperCase();
    final isActive = statusRaw == 'PENDING' || statusRaw == 'IN_PROGRESS';
    final typeColor = m['type'] == 'Corrective' ? _red
        : m['type'] == 'Prédictive' ? const Color(0xFFB39DDB)
        : _cyan;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _panel2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Icon(Icons.build_circle_rounded, color: typeColor, size: 22),
          const SizedBox(width: 10),
          Text('Détail maintenance', style: GoogleFonts.inter(color: _text, fontWeight: FontWeight.w800, fontSize: 16)),
        ]),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            _detailRow('Type', (m['type'] ?? '').toString(), typeColor),
            _detailRow('Statut', (m['status'] ?? '').toString(), isActive ? _orange : _green),
            _detailRow('Date', (m['date'] ?? '—').toString(), _text),
            _detailRow('Description', (m['desc'] ?? '').toString(), _text),
            _detailRow('Source', (m['tech'] ?? '').toString(), _muted),
            _detailRow('Priorité', (m['priority'] ?? 'MEDIUM').toString(), _muted),
            const SizedBox(height: 16),
            if (statusRaw == 'PENDING')
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    try {
                      await ApiService.updateMaintenanceOrderStatus(
                        (m['id'] ?? '').toString(),
                        'IN_PROGRESS',
                      );
                      if (!mounted) return;
                      Navigator.pop(ctx);
                      await _loadMaintenanceOrders();
                    } catch (e) {
                      if (!ctx.mounted) return;
                      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Action impossible: $e')));
                    }
                  },
                  icon: const Icon(Icons.play_arrow_rounded, size: 16),
                  label: Text('Démarrer intervention', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(backgroundColor: _orange, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), padding: const EdgeInsets.symmetric(vertical: 12)),
                ),
              ),
            if (statusRaw == 'IN_PROGRESS') ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await _showCloseCorrectiveDialog(m);
                  },
                  icon: const Icon(Icons.check_circle_rounded, size: 16),
                  label: Text('Clôturer corrective', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(backgroundColor: _green, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), padding: const EdgeInsets.symmetric(vertical: 12)),
                ),
              ),
            ],
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Fermer', style: GoogleFonts.inter(color: _muted)))],
      ),
    );
  }

  Widget _detailRow(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 90, child: Text(label, style: GoogleFonts.spaceGrotesk(fontSize: 11, color: _muted.withOpacity(0.6), fontWeight: FontWeight.w600))),
        Expanded(child: Text(value, style: GoogleFonts.inter(fontSize: 12, color: valueColor, fontWeight: FontWeight.w600))),
      ]),
    );
  }

  Widget _aiPanel() {
    final msg = _iaMessagePanneSiApplicable();
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 240),
      child: Container(
        decoration: BoxDecoration(
          color: _panel2,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
          boxShadow: [
            BoxShadow(
              color: _riskColor.withOpacity(0.1),
              blurRadius: 28,
              spreadRadius: 0.5,
            ),
          ],
        ),
        padding: const EdgeInsets.all(18),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final fillH = constraints.maxHeight;
            final minScrollH = fillH.isFinite && fillH > 0 ? fillH : 0.0;
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: minScrollH),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Icon(Icons.psychology_rounded, color: _orange, size: 24),
                        const SizedBox(width: 10),
                        Text(
                          'ANALYSE I.A.',
                          style: GoogleFonts.spaceGrotesk(fontSize: 12, fontWeight: FontWeight.w900, color: _text, letterSpacing: 1.2),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: _riskColor.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: _riskColor.withOpacity(0.45)),
                          ),
                          child: Text(
                            _iaProbPanne >= 70 ? 'CRITIQUE' : (_iaProbPanne >= 40 ? 'SURVEILLANCE' : 'NOMINAL'),
                            style: GoogleFonts.spaceGrotesk(fontSize: 8, color: _riskColor, fontWeight: FontWeight.w800, letterSpacing: 1),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Probabilité de panne moteur',
                      style: GoogleFonts.inter(fontSize: 10, color: _muted.withOpacity(0.88)),
                    ),
                    const SizedBox(height: 14),
                    Center(
                      child: SizedBox(
                        width: 168,
                        height: 168,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            CircularProgressIndicator(value: 1, strokeWidth: 8, color: _panel3),
                            CircularProgressIndicator(
                              value: (_iaProbPanne / 100).clamp(0.0, 1.0),
                              strokeWidth: 10,
                              color: _riskColor,
                            ),
                            Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '$_iaProbPanne%',
                                    style: GoogleFonts.spaceGrotesk(
                                      fontSize: 40,
                                      fontWeight: FontWeight.w900,
                                      color: _riskColor,
                                      letterSpacing: -1,
                                    ),
                                  ),
                                  Text(
                                    _riskLabelFr,
                                    style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _muted, letterSpacing: 1),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _panel,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withOpacity(0.07)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'TYPE DE PANNE',
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 9,
                              color: _muted.withOpacity(0.8),
                              letterSpacing: 1.1,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _iaPanneType.isEmpty ? '—' : _iaPanneType,
                            style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800, color: _text, height: 1.2),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _iaHorizonJoursLine(),
                            style: GoogleFonts.inter(fontSize: 12, color: _cyan.withOpacity(0.95), fontWeight: FontWeight.w600, height: 1.3),
                          ),
                        ],
                      ),
                    ),
                    if (msg != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _panel,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _riskColor.withOpacity(0.4)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(_iaAdviceIcon, size: 18, color: _riskColor),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                msg,
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  color: _text,
                                  height: 1.35,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (_scenarioExplanation.isNotEmpty && msg != null && _iaProbPanne >= kPanneUiProbMin) ...[
                      const SizedBox(height: 8),
                      Text(
                        _scenarioExplanation,
                        style: GoogleFonts.inter(fontSize: 10, height: 1.3, color: _muted.withOpacity(0.9)),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 12),
                    if (_machineStopped) _machineStoppedBanner(),
                    if (_machineStopped) const SizedBox(height: 8),
                    if (_requiresStop && !_machineStopped) _stopAlertBanner(),
                    if (_canEditIaMotorProfile) ...[
                      const SizedBox(height: 12),
                      _adminIaMotorCard(),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _historyTabBody() {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _sideTab = 'dashboard'),
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 14, color: _orange),
              label: Text(
                'Retour au terminal',
                style: GoogleFonts.spaceGrotesk(color: _orange, fontWeight: FontWeight.w800, fontSize: 11, letterSpacing: 0.6),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              child: _historyPanel(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _historyPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _panel2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                'HISTORIQUE DES VALEURS',
                style: GoogleFonts.spaceGrotesk(
                  color: _orange,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  fontSize: 11,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  setState(() {
                    _historyFuture = ApiService.getTelemetryHistory(_machineId, limit: 20);
                  });
                },
                child: Text('Actualiser', style: GoogleFonts.spaceGrotesk(color: _orange, fontWeight: FontWeight.w700, fontSize: 11)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 240,
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _historyFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(strokeWidth: 2, color: _orange));
                }
                if (snapshot.hasError) {
                  return Text(
                    'Erreur historique',
                    style: GoogleFonts.inter(color: _red),
                  );
                }
                final rows = snapshot.data ?? const <Map<String, dynamic>>[];
                if (rows.isEmpty) {
                  return Center(
                    child: Text(
                      'Aucune donnée historique.',
                      style: GoogleFonts.inter(color: _muted),
                    ),
                  );
                }
                return Scrollbar(
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.vertical,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        headingTextStyle: GoogleFonts.spaceGrotesk(color: _muted, fontSize: 10, fontWeight: FontWeight.w700),
                        dataTextStyle: GoogleFonts.inter(color: _text, fontSize: 11),
                        columns: const [
                          DataColumn(label: Text('Heure')),
                          DataColumn(label: Text('Temp °C')),
                          DataColumn(label: Text('Pression')),
                          DataColumn(label: Text('Puissance')),
                          DataColumn(label: Text('Risque IA %')),
                        ],
                        rows: rows.map((m) {
                          final ts = (m['createdAt'] ?? '').toString();
                          final t = _formatTimestamp(ts);
                          final temp = _toDouble(m['temperature'] ?? m['thermal']);
                          final pressure = _toDouble(m['pressure']);
                          final power = _toDouble(m['power']);
                          final riskRaw = m['prob_panne'] ?? m['panne_probability'] ?? m['scenarioProbPanne'] ?? 0;
                          final riskNum = riskRaw is num ? riskRaw.toDouble() : double.tryParse(riskRaw.toString()) ?? 0;
                          final risk = riskNum <= 1 ? (riskNum * 100) : riskNum;
                          return DataRow(cells: [
                            DataCell(Text(t)),
                            DataCell(Text(temp.toStringAsFixed(1))),
                            DataCell(Text(pressure.toStringAsFixed(2))),
                            DataCell(Text(power.toStringAsFixed(2))),
                            DataCell(Text(risk.toStringAsFixed(0))),
                          ]);
                        }).toList(),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(String raw) {
    if (raw.isEmpty) return '--';
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    final d = dt.toLocal();
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    final ss = d.second.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    final mo = d.month.toString().padLeft(2, '0');
    return '$dd/$mo $hh:$mm:$ss';
  }

  Widget _adminIaMotorCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _panel3,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _cyan.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.admin_panel_settings, size: 16, color: _cyan),
              const SizedBox(width: 8),
              Text(
                'Profil IA machine',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 11,
                  letterSpacing: 0.9,
                  color: _cyan,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Le modèle reçoit ce type (embedding) et la calibration RUL pour l\'affichage en heures.',
            style: GoogleFonts.inter(fontSize: 11, color: _muted, height: 1.35),
          ),
          const SizedBox(height: 6),
          Text(
            'Type actif (télémétrie) : $_machineIaMotorType',
            style: GoogleFonts.inter(fontSize: 10, color: _cyan.withOpacity(0.9), fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          Text('Famille IA', style: GoogleFonts.spaceGrotesk(fontSize: 9, color: _muted)),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: _panel2,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white10),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _adminIaMotor,
                isExpanded: true,
                dropdownColor: _panel2,
                style: GoogleFonts.inter(color: _text, fontSize: 13),
                items: const [
                  DropdownMenuItem(value: 'EL_S', child: Text('EL_S (L)')),
                  DropdownMenuItem(value: 'EL_M', child: Text('EL_M (M)')),
                  DropdownMenuItem(value: 'EL_L', child: Text('EL_L (H)')),
                ],
                onChanged: _savingIaProfile
                    ? null
                    : (v) {
                        if (v == null) return;
                        setState(() => _adminIaMotor = v);
                      },
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Heures par unité RUL modèle (vide = pas de conversion)',
            style: GoogleFonts.spaceGrotesk(fontSize: 9, color: _muted),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _adminRulScaleController,
            enabled: !_savingIaProfile,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: GoogleFonts.inter(color: _text, fontSize: 14),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: _panel2,
              hintText: 'ex: 0.05',
              hintStyle: GoogleFonts.inter(color: _muted.withOpacity(0.5)),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _savingIaProfile ? null : _saveIaMotorProfile,
              style: ElevatedButton.styleFrom(
                backgroundColor: _cyan,
                foregroundColor: const Color(0xFF0A1628),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: _savingIaProfile
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text('Enregistrer profil IA', style: GoogleFonts.inter(fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _machineStoppedBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _green.withOpacity(0.6)),
        boxShadow: [
          BoxShadow(color: _green.withOpacity(0.15), blurRadius: 12, spreadRadius: 1),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MACHINE ARRÊTÉE EN TOUTE SÉCURITÉ',
                  style: GoogleFonts.spaceGrotesk(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Un technicien sur site doit redémarrer la machine manuellement.',
                  style: GoogleFonts.inter(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stopAlertBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF4A0A0A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _red.withOpacity(0.9)),
      ),
      child: Row(
        children: [
          const Icon(Icons.emergency, color: Color(0xFFFFDAD6), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'ARRET MOTEUR RECOMMANDE - Controle immediat requis',
              style: GoogleFonts.spaceGrotesk(
                color: const Color(0xFFFFDAD6),
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomTicker() {
    final logs = <String>[
      '[${_hhmmss(DateTime.now())}] MQTT packets=$_mqttPacketCount',
      '[${_hhmmss(DateTime.now())}] Temp=${_thermal.toStringAsFixed(1)}°C',
      '[${_hhmmss(DateTime.now())}] Pression=${_pressure.toStringAsFixed(1)} bar',
      '[${_hhmmss(DateTime.now())}] IA risque=$_iaProbPanne% ($_iaNiveau)',
      '[${_hhmmss(DateTime.now())}] Type panne=$_iaPanneType',
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Text(
          logs.join('   ·   '),
          style: GoogleFonts.inter(
            fontSize: 12,
            letterSpacing: 0.2,
            color: _text.withOpacity(0.78),
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  String _hhmmss(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}:${d.second.toString().padLeft(2, '0')}';

  Widget _maintenanceTeamPanel() {
    if (_loadingTechnicians) {
      return const Center(child: CircularProgressIndicator(color: _orange));
    }

    if (_activeIntervention != null) {
      return _activeInterventionView();
    }

    final techs = (_techniciansForMachine ?? []).where((t) {
      final kind = (t['directoryKind'] ?? 'technician').toString();
      
      // On accepte tous les types de techniciens/agents
      final isTechProfile = kind == 'maintenance' || kind == 'technician' || kind == 'maintenance_agent';
      if (!isTechProfile) return false;

      // On filtre par ID de machine assigné
      final List? assigned = t['machineIds'] is List ? t['machineIds'] as List : null;
      if (assigned == null) return false;
      
      return assigned.map((e) => e.toString().toUpperCase()).contains(_machineId.toUpperCase());
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Container(width: 3, height: 18, decoration: BoxDecoration(color: _orange, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 8),
          Text('SELECTION TECHNICIEN MAINTENANCE',
              style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w800, color: _text, letterSpacing: 1.0)),
        ]),
        const SizedBox(height: 16),
        if (techs.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Text('Aucun technicien de maintenance assigne a cette machine.',
                  style: GoogleFonts.inter(color: _muted)),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              itemCount: techs.length,
              itemBuilder: (ctx, idx) {
                final t = techs[idx];
                return _maintenanceTechCard(t);
              },
            ),
          ),
      ],
    );
  }

  Widget _maintenanceTechCard(Map<String, dynamic> tech) {
    final isAgent = tech['directoryKind'] == 'maintenance_agent';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isAgent ? _cyan.withOpacity(0.3) : Colors.white.withOpacity(0.06)),
      ),
      child: ListTile(
        onTap: () => _assignTechnician(tech),
        leading: CircleAvatar(
          backgroundColor: (isAgent ? _cyan : _orange).withOpacity(0.2),
          child: Icon(isAgent ? Icons.manage_accounts_rounded : Icons.engineering, color: isAgent ? _cyan : _orange),
        ),
        title: Text(tech['name'] ?? 'Sans nom', style: GoogleFonts.inter(color: _text, fontWeight: FontWeight.bold)),
        subtitle: Text(
          isAgent ? '${tech['email'] ?? ''} • MAINTENANCE LEAD' : (tech['email'] ?? ''),
          style: GoogleFonts.inter(color: isAgent ? _cyan.withOpacity(0.7) : _muted, fontSize: 11, fontWeight: isAgent ? FontWeight.bold : FontWeight.normal),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton(
              onPressed: () => _assignTechnician(tech),
              style: ElevatedButton.styleFrom(
                backgroundColor: _cyan.withOpacity(0.15),
                foregroundColor: _cyan,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: _cyan.withOpacity(0.3))),
              ),
              child: Text('CHAT', style: GoogleFonts.spaceGrotesk(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
            ),
            const SizedBox(width: 12),
            const Icon(Icons.arrow_forward_ios, size: 14, color: _muted),
          ],
        ),
      ),
    );
  }


  Widget _activeInterventionView() {
    final status = _activeIntervention!['status'];
    final decision = _activeIntervention!['finalDecision'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Container(width: 3, height: 18, decoration: BoxDecoration(color: _green, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 8),
          Text('INTERVENTION ACTIVE',
              style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w800, color: _green, letterSpacing: 1.0)),
          const Spacer(),
          Text(status ?? '', style: GoogleFonts.spaceGrotesk(color: _green, fontSize: 12, fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _panel2,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _green.withOpacity(0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('TECHNICIEN ASSIGNE', style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _muted, letterSpacing: 1)),
              const SizedBox(height: 4),
              Text(_activeIntervention!['technicianName'] ?? 'Inconnu',
                  style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: _text)),
              const Divider(height: 32, color: Colors.white12),
              Text('DECISION & VALIDATION', style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _muted, letterSpacing: 1)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    decision == 'REAL_FAILURE' ? Icons.error_outline : (decision == 'FALSE_ALARM' ? Icons.check_circle_outline : Icons.hourglass_empty),
                    color: decision == 'REAL_FAILURE' ? _red : (decision == 'FALSE_ALARM' ? _green : _orange),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    decision == 'REAL_FAILURE'
                        ? 'Confirme : Panne Reelle'
                        : (decision == 'FALSE_ALARM' ? 'Confirme : Fausse Alerte' : 'En attente de diagnostic...'),
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: decision == 'REAL_FAILURE' ? _red : (decision == 'FALSE_ALARM' ? _green : _orange),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        if (_senderRole == 'technician' || _senderRole == 'maintenance') ...[
          SizedBox(
            width: double.infinity,
            height: 52,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: const LinearGradient(
                  colors: [Color(0xFF2E7D32), Color(0xFF43A047)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.green.withOpacity(0.25),
                    blurRadius: 15,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ElevatedButton.icon(
                onPressed: _validateDiagnosticIntervention,
                icon: const Icon(Icons.verified_rounded, color: Colors.white, size: 20),
                label: Text(
                  'VALIDER LE DIAGNOSTIC',
                  style: GoogleFonts.spaceGrotesk(
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    letterSpacing: 1.2,
                    color: Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (_senderRole == 'superadmin' || _senderRole == 'admin') ...[
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => setState(() => _forceShowMaintenanceTeam = true),
                  icon: const Icon(Icons.edit_note, size: 18),
                  label: const Text('REASSIGNER'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _cyan,
                    side: BorderSide(color: _cyan.withOpacity(0.5)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _cancelActiveIntervention,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('ANNULER'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _red,
                    side: BorderSide(color: _red.withOpacity(0.5)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => KineticObservatoryPage(
                    machineId: _machineId,
                    interventionId: _activeIntervention!['id'].toString(),
                  ),
                ),
              );
            },
            icon: const Icon(Icons.analytics_outlined, color: Colors.black),
            label: Text('OUVRIR L\'OBSERVATOIRE', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: _cyan,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () {
              setState(() => _sideTab = 'maintenance');
            },
            icon: const Icon(Icons.open_in_new),
            label: const Text('OUVRIR LE CANAL COMPLET'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _panel3,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
      ],
    );
  }
}
