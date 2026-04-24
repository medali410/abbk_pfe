import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'services/api_service.dart';
import 'utils/panne_display.dart';

class MachineDetailPage extends StatefulWidget {
  final String machineId;
  final String? machineName;
  const MachineDetailPage({super.key, required this.machineId, this.machineName});

  @override
  State<MachineDetailPage> createState() => _MachineDetailPageState();
}

class _MachineDetailPageState extends State<MachineDetailPage> with TickerProviderStateMixin {
  late io.Socket _socket;
  late String _machineId;
  late AnimationController _pulseCtrl;

  double _thermal = 0;
  double _pressure = 0;
  double _power = 0;
  double _ultrasonic = 0;
  double _presence = 0;
  double _magnetic = 0;
  double _infrared = 0;
  double _vibration = 0;
  double _friction = 0;
  int _wifiRssi = 0;
  String _zone = 'Zone inconnue';
  double? _lat;
  double? _lng;

  String _scenarioCode = 'LEARNING';
  String _scenarioLabel = '—';
  int _scenarioProbPanne = 0;
  String _scenarioExplanation = 'En attente de données…';
  List<double> _scenarioThermalSeries = const [];
  int _iaProbPanne = 0;
  String _iaNiveau = 'INCONNU';
  String _iaPanneType = '—';
  double? _iaRulEstime;
  double? _modelPanneAccuracy;
  String _iaSource = 'UNKNOWN';

  Future<List<Map<String, dynamic>>>? _techniciansFuture;
  Map<String, dynamic>? _activeIntervention;
  bool _forceShowMaintenance = false;

  static const _bg = Color(0xFF10102B);
  static const _surface = Color(0xFF1D1D38);
  static const _surfaceHigh = Color(0xFF272743);
  static const _surfaceHighest = Color(0xFF32324E);
  static const _primary = Color(0xFFFFB692);
  static const _primaryContainer = Color(0xFFFF6E00);
  static const _secondary = Color(0xFF75D1FF);
  static const _onSurface = Color(0xFFE2DFFF);
  static const _onSurfaceVariant = Color(0xFFE2BFB0);
  static const _outline = Color(0xFF594136);
  static const _green = Color(0xFF66BB6A);
  static const _error = Color(0xFFFFB4AB);
  static const _errorContainer = Color(0xFF93000A);

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..repeat(reverse: true);
    _machineId = _normalizeId(widget.machineId, widget.machineName);
    _zone = _machineId == 'MAC_HATHA'
        ? 'Zone A-01'
        : (_machineId == 'MAC_EXP' ? 'Zone B-02' : 'Zone inconnue');
    _loadInitialTelemetry();
    _initSocket();
    _techniciansFuture = ApiService.getMaintenanceAgents();
    _checkActiveIntervention();
  }

  Future<void> _checkActiveIntervention() async {
    try {
      final interventions = await ApiService.getDiagnosticInterventions();
      final active = interventions.firstWhere(
        (i) => (i['machineId'] ?? '').toString() == _machineId && i['status'] != 'DONE',
        orElse: () => {},
      );
      if (active.isNotEmpty) {
        setState(() => _activeIntervention = active);
      }
    } catch (_) {}
  }

  Future<void> _assignTechnician(Map<String, dynamic> tech) async {
    try {
      final created = await ApiService.createDiagnosticIntervention({
        'machineId': _machineId,
        'companyId': 'COMP_01', // Example
        'scenarioType': _iaProbPanne >= 70 ? 'CRITICAL' : 'MAINTENANCE',
        'summary': 'Intervention corrective assignÃ©e via dashboard.',
        'technicianId': (tech['id'] ?? tech['_id'] ?? '').toString(),
        'technicianName': tech['username'] ?? tech['name'] ?? 'Inconnu',
      });
      setState(() => _activeIntervention = created);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Technicien ${tech['username']} assignÃ© avec succÃ¨s !')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur d\'assignation: $e')),
      );
    }
  }

  String _normalizeId(String id, String? name) {
    final cleaned = id.trim();
    final lowerName = (name ?? '').toLowerCase();
    if (cleaned == 'MAC_HATHA' || cleaned == 'MAC_EXP') return cleaned;
    if (lowerName.contains('hatha')) return 'MAC_HATHA';
    if (lowerName.contains('expresse')) return 'MAC_EXP';
    return cleaned;
  }

  double _toDouble(dynamic value, [double fallback = 0]) {
    if (value == null) return fallback;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? fallback;
    return fallback;
  }

  int _fallbackRiskFromSensors({
    required double thermal,
    required double pressure,
    required double vibration,
    required double power,
  }) {
    var score = 0.0;
    if (thermal >= 85) {
      score += 35;
    } else if (thermal >= 70) {
      score += 22;
    } else if (thermal >= 60) {
      score += 10;
    }

    if (pressure >= 6.0 || pressure <= 0.8) {
      score += 25;
    } else if (pressure >= 4.8 || pressure <= 1.2) {
      score += 12;
    }

    if (vibration >= 8.0) {
      score += 30;
    } else if (vibration >= 4.0) {
      score += 16;
    }

    if (power >= 6500) {
      score += 20;
    } else if (power >= 4500) {
      score += 10;
    }

    return score.round().clamp(0, 100);
  }

  Future<void> _loadInitialTelemetry() async {
    try {
      final data = await ApiService.getLatestTelemetry(_machineId);
      if (!mounted || data == null) return;
      _applyTelemetry(data);
    } catch (_) {}
    try {
      final metrics = await ApiService.getModelMetrics();
      if (!mounted) return;
      final raw = metrics['panne_accuracy'];
      final parsed = raw is num ? raw.toDouble() : double.tryParse(raw?.toString() ?? '');
      if (parsed != null) {
        setState(() {
          _modelPanneAccuracy = parsed;
        });
      }
    } catch (_) {}
  }

  void _applyTelemetry(Map<String, dynamic> data) {
    if (!mounted) return;
    final metrics = data['metrics'] as Map<String, dynamic>?;
    setState(() {
      _thermal = _toDouble(data['temperature'] ?? metrics?['thermal'], _thermal);
      _pressure = _toDouble(data['pressure'] ?? metrics?['pressure'], _pressure);
      _power = _toDouble(data['power'] ?? data['powerConsumption'] ?? metrics?['power'], _power);
      _ultrasonic = _toDouble(data['ultrasonic'] ?? metrics?['ultrasonic'], _ultrasonic);
      _presence = _toDouble(data['presence'] ?? metrics?['presence'], _presence);
      _magnetic = _toDouble(data['magnetic'] ?? metrics?['magnetic'], _magnetic);
      _infrared = _toDouble(data['infrared'] ?? metrics?['infrared'], _infrared);
      _vibration = _toDouble(data['vibration'] ?? metrics?['vibration'], _vibration);
      _friction = _toDouble(data['friction'] ?? metrics?['friction'], _friction);
      _wifiRssi = _toDouble(data['wifiRssi'] ?? metrics?['wifiRssi'], _wifiRssi.toDouble()).round();
      _zone = (data['zone'] ?? data['locationZone'] ?? _zone).toString();
      final lat = _toDouble(data['lat'] ?? data['latitude'] ?? metrics?['lat'], double.nan);
      final lng = _toDouble(data['lng'] ?? data['longitude'] ?? metrics?['lng'], double.nan);
      if (!lat.isNaN && !lng.isNaN) {
        _lat = lat;
        _lng = lng;
      }
      _ingestScenario(data);
      final fs = data['failureScenario'] as Map<String, dynamic>?;
      final hasModelProb = data['prob_panne'] != null || data['panne_probability'] != null;
      final probRaw = data['prob_panne'] ??
          data['panne_probability'] ??
          data['scenarioProbPanne'] ??
          fs?['scenarioProbPanne'];
      if (probRaw != null) {
        final value = _toDouble(probRaw, _iaProbPanne.toDouble());
        _iaProbPanne = value <= 1 ? (value * 100).round().clamp(0, 100) : value.round().clamp(0, 100);
        _iaSource = hasModelProb ? 'IA MODEL' : 'MQTT SCENARIO';
      } else {
        _iaProbPanne = _fallbackRiskFromSensors(
          thermal: _thermal,
          pressure: _pressure,
          vibration: _vibration,
          power: _power,
        );
        _iaSource = 'SENSOR FALLBACK';
      }
      _iaNiveau = (data['niveau'] ??
              (_iaProbPanne >= 70
                  ? 'CRITIQUE'
                  : _iaProbPanne >= 40
                      ? 'SURVEILLANCE'
                      : 'NORMAL'))
          .toString();
      _iaPanneType = (data['panne_type'] ??
              data['scenario_label'] ??
              data['scenarioLabel'] ??
              fs?['scenarioLabel'] ??
              _iaPanneType)
          .toString();
      if (_iaPanneType.toLowerCase().contains('erreur serveur ml') || _iaPanneType.trim().isEmpty || _iaPanneType == '—') {
        if (_iaProbPanne >= 70) {
          _iaPanneType = 'Risque élevé multi-capteurs';
        } else if (_iaProbPanne >= 40) {
          _iaPanneType = 'Anomalie capteurs (fallback)';
        } else {
          _iaPanneType = 'Fonctionnement nominal';
        }
      }
      final rulRaw = data['rul_estime'] ?? data['rul'];
      if (rulRaw != null) _iaRulEstime = _toDouble(rulRaw, _iaRulEstime ?? 0);
    });
  }

  void _ingestScenario(Map<String, dynamic> data) {
    Map<String, dynamic>? fs = data['failureScenario'] as Map<String, dynamic>?;
    final code = (data['scenarioCode'] ?? fs?['scenarioCode'])?.toString();
    final label = (data['scenarioLabel'] ?? fs?['scenarioLabel'])?.toString();
    final expl = (data['scenarioExplanation'] ?? fs?['scenarioExplanation'])?.toString();
    final probRaw = data['scenarioProbPanne'] ?? fs?['scenarioProbPanne'];
    final seriesRaw = data['scenarioThermalSeries'] ?? fs?['scenarioThermalSeries'];

    if (code != null && code.isNotEmpty) _scenarioCode = code;
    if (label != null && label.isNotEmpty) _scenarioLabel = label;
    if (expl != null && expl.isNotEmpty) _scenarioExplanation = expl;
    if (probRaw != null) _scenarioProbPanne = _toDouble(probRaw, 0).round().clamp(0, 100);

    if (seriesRaw is List) {
      _scenarioThermalSeries = seriesRaw.map((e) => _toDouble(e, 0)).toList();
    }
  }

  void _initSocket() {
    _socket = io.io(ApiService.socketBaseUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': true,
    });
    _socket.on('nouvelle_prediction', (raw) {
      try {
        final decoded = raw is String ? jsonDecode(raw) : raw;
        if (decoded is! Map) return;
        final data = Map<String, dynamic>.from(decoded);
        final incomingId = (data['machineId'] ?? data['id'] ?? '').toString();
        if (incomingId != _machineId) return;
        _applyTelemetry(data);
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
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
        power: _power,
        magnetic: _magnetic,
        infrared: _infrared,
        ultrasonic: _ultrasonic,
      );

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 1000;
    return Scaffold(
      backgroundColor: _bg,
      body: Column(
        children: [
          _topBar(),
          Expanded(
            child: Row(
              children: [
                if (isDesktop) _sideBar(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _headerSection(),
                        const SizedBox(height: 20),
                        _metricsGrid(isDesktop),
                        const SizedBox(height: 20),
                        _geoAndLogs(isDesktop),
                      ],
                    ),
                  ),
                ),
                if (isDesktop && (_iaProbPanne >= 30 || _activeIntervention != null || _forceShowMaintenance)) _rightControlSidebar(),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: (!isDesktop && (_iaProbPanne >= 30 || _activeIntervention != null || _forceShowMaintenance))
          ? FloatingActionButton(
              onPressed: () => showModalBottomSheet(
                context: context,
                backgroundColor: Colors.transparent,
                builder: (ctx) => _rightControlSidebar(),
              ),
              backgroundColor: _primaryContainer,
              child: const Icon(Icons.engineering),
            )
          : null,
    );
  }

  Widget _rightControlSidebar() {
    final showIntervention = _activeIntervention != null;

    return Container(
      width: 320,
      decoration: const BoxDecoration(
        color: _surfaceHigh,
        border: Border(left: BorderSide(color: _surfaceHighest, width: 2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            color: _surfaceHighest.withOpacity(0.5),
            child: Row(
              children: [
                Icon(Icons.engineering_outlined, color: _primaryContainer, size: 20),
                const SizedBox(width: 10),
                Text(
                  'ÉQUIPE DE CONTRÔLE',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: _onSurface,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: showIntervention
                ? _buildActiveInterventionView()
                : _buildTechnicianSelector(),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveInterventionView() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _green.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('INTERVENTION ACTIVE',
                    style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _green, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text('Technicien: ${_activeIntervention!['technicianName'] ?? 'AssignÃ©'}',
                    style: GoogleFonts.inter(fontSize: 13, color: _onSurface, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text('Statut: ${_activeIntervention!['status']}',
                    style: GoogleFonts.spaceGrotesk(fontSize: 11, color: _onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text('La communication est ouverte. Le technicien attend vos instructions.',
              style: GoogleFonts.inter(fontSize: 12, color: _onSurfaceVariant)),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _surfaceHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('DÉCISION & VALIDATION',
                    style: GoogleFonts.spaceGrotesk(fontSize: 9, color: _primaryContainer, fontWeight: FontWeight.bold, letterSpacing: 1)),
                const SizedBox(height: 6),
                Text(
                  _activeIntervention!['finalDecision'] == 'REAL_FAILURE' 
                      ? 'ConfirmÃ© : Panne RÃ©elle' 
                      : (_activeIntervention!['finalDecision'] == 'FALSE_ALARM' ? 'ConfirmÃ© : Fausse Alerte' : 'En attente de diagnostic...'),
                  style: GoogleFonts.inter(fontSize: 11, color: _onSurface),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                // Navigate to maintenance module
                Navigator.pushNamed(context, '/maintenance-dashboard');
              },
              icon: const Icon(Icons.chat_bubble_outline, size: 18),
              label: const Text('OUVRIR LE CANAL'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryContainer,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTechnicianSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
          child: Text(
            'SÉLECTIONNEZ UN AGENT SUR SITE',
            style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _onSurfaceVariant, letterSpacing: 1),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _techniciansFuture,
            builder: (ctx, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final techs = snap.data ?? [];
              if (techs.isEmpty) {
                return Center(
                  child: Text('Aucun agent disponible',
                      style: GoogleFonts.inter(fontSize: 12, color: _onSurfaceVariant)),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                itemCount: techs.length,
                itemBuilder: (ctx, i) {
                  final t = techs[i];
                  return Card(
                    color: _surface,
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: _primaryContainer.withOpacity(0.2),
                        child: Text((t['username'] ?? 'T')[0].toUpperCase(),
                            style: const TextStyle(color: _primaryContainer, fontSize: 12)),
                      ),
                      title: Text(t['username'] ?? 'Technicien',
                          style: GoogleFonts.inter(fontSize: 13, color: _onSurface, fontWeight: FontWeight.w600)),
                      subtitle: Text(t['location'] ?? 'Site principal',
                          style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _onSurfaceVariant)),
                      trailing: IconButton(
                        icon: const Icon(Icons.check_circle_outline, color: _primaryContainer),
                        onPressed: () => _assignTechnician(t),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _topBar() {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(color: _bg, border: Border(bottom: BorderSide(color: _outline.withOpacity(0.2)))),
      child: Row(
        children: [
          Text('KINETIC_OBSERVATORY', style: GoogleFonts.inter(color: _onSurface, fontWeight: FontWeight.w900)),
          const SizedBox(width: 24),
          Text('Fleet', style: GoogleFonts.inter(color: _onSurfaceVariant)),
          const SizedBox(width: 16),
          Text('Analytics', style: GoogleFonts.inter(color: _primaryContainer, fontWeight: FontWeight.bold)),
          const Spacer(),
          const Icon(Icons.notifications_active_outlined, color: _onSurfaceVariant),
          const SizedBox(width: 12),
          const Icon(Icons.settings_outlined, color: _onSurfaceVariant),
        ],
      ),
    );
  }

  Widget _sideBar() {
    Widget item(String t, IconData i, {bool active = false, VoidCallback? onTap}) => Container(
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          decoration: BoxDecoration(
            color: active ? _surface : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: active ? Border(left: BorderSide(color: _primaryContainer, width: 2)) : null,
          ),
          child: ListTile(
            dense: true,
            onTap: onTap,
            leading: Icon(i, color: active ? _primaryContainer : _onSurfaceVariant, size: 18),
            title: Text(t, style: GoogleFonts.spaceGrotesk(color: active ? _primaryContainer : _onSurfaceVariant, fontSize: 11)),
          ),
        );

    return Container(
      width: 240,
      color: const Color(0xFF191934),
      child: Column(
        children: [
          const SizedBox(height: 18),
          item('SENSORS', Icons.dashboard_customize_outlined, active: !_forceShowMaintenance, onTap: () {
            setState(() => _forceShowMaintenance = false);
          }),
          item('MAINTENANCE', Icons.engineering_outlined, active: _forceShowMaintenance, onTap: () {
            setState(() => _forceShowMaintenance = true);
          }),
          const Divider(color: _outline, height: 24),
          item('TEMPERATURE', Icons.thermostat),
          item('PRESSURE', Icons.compress),
          item('ENERGY', Icons.bolt),
          item('ULTRASONIC', Icons.waves),
          item('PRESENCE', Icons.sensors),
          item('MAGNETIC', Icons.straighten),
          item('INFRARED', Icons.settings_input_antenna),
        ],
      ),
    );
  }

  Widget _headerSection() {
    final hints = _panneHints;
    final iaColor = _iaProbPanne >= 70
        ? _error
        : (_iaProbPanne >= 40 ? const Color(0xFFFFD166) : _green);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(width: 8, height: 8, decoration: const BoxDecoration(color: _green, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Text('SYSTÈME CRITIQUE OPÉRATIONNEL', style: GoogleFonts.spaceGrotesk(fontSize: 10, letterSpacing: 2, color: _secondary)),
              ]),
              const SizedBox(height: 6),
              Text('Machine ${widget.machineName ?? _machineId}', style: GoogleFonts.inter(fontSize: 42, height: 1, fontWeight: FontWeight.w900, color: _onSurface)),
              const SizedBox(height: 8),
              Text('ID: $_machineId • Zone: $_zone • RSSI: $_wifiRssi dBm', style: GoogleFonts.inter(color: _onSurfaceVariant)),
            ],
          ),
        ),
        AnimatedBuilder(
          animation: _pulseCtrl,
          builder: (context, _) {
            return Container(
              width: 300,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _surfaceHigh.withOpacity(0.8),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: hints.hasStress
                      ? const Color(0xFFFFB4AB).withOpacity(0.45 + 0.4 * _pulseCtrl.value)
                      : iaColor.withOpacity(0.35),
                  width: hints.hasStress ? 2 : 1,
                ),
                boxShadow: hints.hasStress
                    ? [
                        BoxShadow(
                          color: const Color(0xFFFFB4AB).withOpacity(0.2 * _pulseCtrl.value),
                          blurRadius: 14,
                        ),
                      ]
                    : null,
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('RISQUE IA LIVE', style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _onSurfaceVariant, letterSpacing: 2)),
                const SizedBox(height: 8),
                Text('$_iaProbPanne %', style: GoogleFonts.inter(fontSize: 34, color: iaColor, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text('Niveau: $_iaNiveau', style: GoogleFonts.spaceGrotesk(fontSize: 9, color: _onSurfaceVariant)),
                if (hints.typeLine.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      hints.typeLine,
                      style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: _onSurface),
                    ),
                  ),
                if (hints.summaryLine.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      hints.summaryLine,
                      style: GoogleFonts.inter(
                        fontSize: 9.5,
                        height: 1.3,
                        color: hints.hasStress ? const Color(0xFFFFB4AB) : _onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (_scenarioExplanation.isNotEmpty && _scenarioExplanation != 'En attente de données…')
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      _scenarioExplanation,
                      style: GoogleFonts.inter(fontSize: 9, height: 1.25, color: _onSurfaceVariant.withOpacity(0.95)),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (_iaRulEstime != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text('RUL estimée: ${_iaRulEstime!.toStringAsFixed(1)}', style: GoogleFonts.spaceGrotesk(fontSize: 9, color: _onSurfaceVariant)),
                  ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: iaColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'SOURCE: $_iaSource',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 8,
                      letterSpacing: 1.0,
                      fontWeight: FontWeight.w700,
                      color: iaColor,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: (_iaProbPanne / 100).clamp(0.0, 1.0),
                    color: iaColor,
                    backgroundColor: _surfaceHighest,
                    minHeight: 4,
                  ),
                ),
              ]),
            );
          },
        ),
      ],
    );
  }

  Widget _metricsGrid(bool isDesktop) {
    final hints = _panneHints;
    Color thermalColor = _thermal >= 75 ? _error : (_thermal >= 55 ? const Color(0xFFFFD166) : _green);
    Color pressureColor = _pressure >= 150 ? _error : (_pressure >= 130 ? const Color(0xFFFFD166) : _green);
    Color powerColor = _power >= 5500 ? _error : (_power >= 4200 ? const Color(0xFFFFD166) : _green);
    Color ultrasonicColor = _ultrasonic <= 12 ? _error : (_ultrasonic <= 20 ? const Color(0xFFFFD166) : _green);
    Color magneticColor = _magnetic >= 0.85 ? _error : (_magnetic >= 0.7 ? const Color(0xFFFFD166) : _green);
    Color infraredColor = _infrared >= 75 ? _error : (_infrared >= 60 ? const Color(0xFFFFD166) : _green);

    final cards = <Widget>[
      _metricCard('Thermal', 'thermal', '${_thermal.toStringAsFixed(1)} °C', Icons.thermostat, thermalColor, hints),
      _metricCard('Pressure', 'pressure', '${_pressure.toStringAsFixed(1)} bar', Icons.compress, pressureColor, hints),
      _metricCard('Power / Electricity', 'power', '${_power.toStringAsFixed(1)} kWh', Icons.bolt, powerColor, hints),
      _metricCard('Ultrasonic', 'ultrasonic', '${_ultrasonic.toStringAsFixed(1)} cm', Icons.waves, ultrasonicColor, hints),
      _metricCard('Presence', '', _presence >= 0.5 ? 'DETECTED' : 'ABSENT', Icons.sensors, _presence >= 0.5 ? _green : _error, hints),
      _metricCard('Magnetic', 'magnetic', '${_magnetic.toStringAsFixed(1)} mTesla', Icons.straighten, magneticColor, hints),
      _metricCard('Infrared', 'infrared', '${_infrared.toStringAsFixed(1)} W/m²', Icons.settings_input_antenna, infraredColor, hints),
    ];
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: isDesktop ? 4 : 2,
      crossAxisSpacing: 14,
      mainAxisSpacing: 14,
      childAspectRatio: isDesktop ? 1.2 : 1.0,
      children: cards,
    );
  }

  Widget _metricCard(String title, String highlightKey, String value, IconData icon, Color accent, PanneUiHints hints) {
    final isCritical = accent == _error;
    final isWarning = accent == const Color(0xFFFFD166);
    final status = isCritical ? 'CRITIQUE' : (isWarning ? 'SURVEILLANCE' : 'NORMAL');
    final stress = highlightKey.isNotEmpty && hints.highlightMetrics.contains(highlightKey);
    return AnimatedBuilder(
      animation: _pulseCtrl,
      builder: (context, _) {
        final pulseBorder = const Color(0xFFFF7B7B).withOpacity(0.5 + 0.45 * _pulseCtrl.value);
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: stress ? const Color(0xFFFF7B7B).withOpacity(0.08 + 0.1 * _pulseCtrl.value) : _surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: stress ? pulseBorder : accent.withOpacity(0.35), width: stress ? 2.5 : 1),
            boxShadow: stress
                ? [
                    BoxShadow(color: const Color(0xFFFF7B7B).withOpacity(0.2 * _pulseCtrl.value), blurRadius: 10),
                  ]
                : null,
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(
              children: [
                Icon(icon, size: 18, color: stress ? const Color(0xFFFF7B7B) : accent),
                const SizedBox(width: 8),
                Expanded(child: Text(title, style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _onSurfaceVariant, letterSpacing: 1))),
                if (stress)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Text('PANNE', style: GoogleFonts.spaceGrotesk(fontSize: 7, color: pulseBorder, fontWeight: FontWeight.w800)),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    status,
                    style: GoogleFonts.spaceGrotesk(fontSize: 8, color: accent, fontWeight: FontWeight.w700, letterSpacing: 1),
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              value,
              style: GoogleFonts.inter(
                fontSize: 28,
                color: stress ? const Color(0xFFFFB4AB) : _onSurface,
                fontWeight: FontWeight.w900,
              ),
            ),
          ]),
        );
      },
    );
  }

  Widget _geoAndLogs(bool isDesktop) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: isDesktop ? 3 : 1,
      crossAxisSpacing: 14,
      mainAxisSpacing: 14,
      childAspectRatio: isDesktop ? 1.65 : 1.2,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('GÉOLOCALISATION', style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _onSurfaceVariant, letterSpacing: 2)),
            const SizedBox(height: 6),
            Text(_lat != null && _lng != null ? 'LAT: ${_lat!.toStringAsFixed(5)}  LNG: ${_lng!.toStringAsFixed(5)}' : 'Position indoor: $_zone', style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _onSurface)),
            const SizedBox(height: 10),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(
                      'https://lh3.googleusercontent.com/aida-public/AB6AXuBG3lgWMJj_rUtvCDbhl_ga6n53iDs9NdMeBWL8NMV1-EsnoxiEbRz812hyQT1z6BWkYzmjjg8afIvvBlmoIBylkH3UKAPbmhbma3Uksx49jYmooM-2yX7Tw_sKn1GQgJI2vkhaqyTboeaIo_7h-AKjXFRbSCgqD4S1_ybzRGJw2xvnD1lTfKUu4J5XU3uT56JCeh1xfv8zfYmEM1lLKyF28I-mG369_NoRzf5f4yzrQsrejdZshVsweoKwm_2-8o1w8LgYUNNLVK4',
                      fit: BoxFit.cover,
                    ),
                    Container(color: Colors.black.withOpacity(0.35)),
                    const Center(child: Icon(Icons.place, color: _primaryContainer, size: 38)),
                  ],
                ),
              ),
            ),
          ]),
        ),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('LOGS SYSTÈME RÉCENTS', style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _onSurfaceVariant, letterSpacing: 2)),
            const SizedBox(height: 14),
            _logItem('Scénario', _scenarioLabel, _scenarioProbPanne >= 42 ? _error : _primaryContainer),
            _logItem('Modèle', _scenarioExplanation.length > 120 ? '${_scenarioExplanation.substring(0, 117)}…' : _scenarioExplanation, _secondary),
            if (_scenarioThermalSeries.length >= 2)
              _logItem(
                'Série T°',
                _scenarioThermalSeries.map((e) => e.toStringAsFixed(0)).join(' → '),
                _outline,
              ),
          ]),
        ),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(12)),
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('IA PRÉDICTIVE', style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _onSurfaceVariant, letterSpacing: 2)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: _iaProbPanne >= 70 ? _error : (_iaProbPanne >= 40 ? const Color(0xFFFFD166) : _green),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _iaProbPanne >= 70
                        ? 'MENACE DÉTECTÉE'
                        : (_iaProbPanne >= 40 ? 'SURVEILLANCE' : 'SYSTÈME STABLE'),
                    style: GoogleFonts.spaceGrotesk(fontSize: 9, color: _onSurfaceVariant, letterSpacing: 1.4),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '$_iaProbPanne%',
                      style: GoogleFonts.inter(
                        fontSize: 36,
                        fontWeight: FontWeight.w900,
                        color: _iaProbPanne >= 70 ? _error : (_iaProbPanne >= 40 ? const Color(0xFFFFD166) : _green),
                      ),
                    ),
                  ),
                  Icon(
                    Icons.psychology_outlined,
                    color: _iaProbPanne >= 70 ? _error : (_iaProbPanne >= 40 ? const Color(0xFFFFD166) : _primaryContainer),
                    size: 30,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _logItem('Niveau de risque', _iaNiveau, _iaProbPanne >= 70 ? _error : (_iaProbPanne >= 40 ? const Color(0xFFFFD166) : _green)),
              _logItem('Type de panne prédit', _iaPanneType, _primaryContainer),
              _logItem('RUL', _iaRulEstime == null ? 'N/A' : '${_iaRulEstime!.toStringAsFixed(1)} heures', _secondary),
              if (_modelPanneAccuracy != null)
                _logItem('Model accuracy', '${(_modelPanneAccuracy! * 100).toStringAsFixed(2)} %', _onSurfaceVariant),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.build_circle_outlined, size: 18),
                  label: Text(
                    'Planifier Maintenance',
                    style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700, letterSpacing: 1.2),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _iaProbPanne >= 70 ? _errorContainer : _surfaceHigh,
                    foregroundColor: _iaProbPanne >= 70 ? _error : _onSurface,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _logItem(String t, String m, Color c) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(width: 2, height: 28, color: c),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t, style: GoogleFonts.spaceGrotesk(fontSize: 9, color: _onSurfaceVariant)),
              Text(m, style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _onSurface)),
            ]),
          ),
        ],
      ),
    );
  }
}

