import 'dart:ui';
import 'dart:math' as math;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:video_player/video_player.dart';
import 'services/api_service.dart';
import 'services/global_notification_service.dart';
import 'mission_control_page.dart';
import 'send_mission_page.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class AiAnalysisView extends StatefulWidget {
  final String machineId;
  final String machineName;
  final String motorType;
  /// Si true, le bouton MISSION est masqué (vue client uniquement)
  final bool isClientView;
  final String viewerRole;

  const AiAnalysisView({
    super.key,
    required this.machineId,
    required this.machineName,
    this.motorType = 'EL_M',
    this.isClientView = false,
    this.viewerRole = 'maintenance',
  });

  @override
  State<AiAnalysisView> createState() => _AiAnalysisViewState();
}

class _AiAnalysisViewState extends State<AiAnalysisView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;
  VideoPlayerController? _temperatureVideoController;
  String? _temperatureVideoError;
  bool _predictLoading = false;
  String? _predictError;
  Map<String, dynamic>? _predictResult;
  bool _historyLoading = false;
  String? _historyError;
  List<Map<String, dynamic>> _history5Days = <Map<String, dynamic>>[];
  int _historyDays = 5;
  Timer? _liveRefreshTimer;
  double _diagTemperature = 0;
  double _diagVoltage = 0;
  double _diagHumidity = 0;
  double _diagPower = 0;
  double _diagVibration = 0;
  double _diagMagnetic = 0;
  double _diagInfrared = 0;
  
  bool _isLoadingState = false;
  String _actualMachineStatus = 'UNKNOWN';
  StreamSubscription? _machineStatusSub;
  StreamSubscription? _dangerAlertSub;
  Map<String, dynamic>? _lastDangerInfo;

  // ── Colors from Tailwind config ──
  static const _bg = Color(0xFF10102B);
  static const _surfaceContainerLowest = Color(0xFF0B0B26);
  static const _surfaceContainerLow = Color(0xFF191934);
  static const _surfaceContainer = Color(0xFF1D1D38);
  static const _surfaceContainerHigh = Color(0xFF272743);
  static const _surfaceContainerHighest = Color(0xFF32324E);
  static const _primary = Color(0xFFFF6E00);
  static const _primaryLight = Color(0xFFFFB692);
  static const _secondary = Color(0xFF75D1FF);
  static const _error = Color(0xFFFFB4AB);
  static const _errorContainer = Color(0xFF93000A);
  static const _onError = Color(0xFF690005);
  static const _onSurface = Color(0xFFE2DFFF);
  static const _onSurfaceVariant = Color(0xFFE2BFB0);
  static const _green = Color(0xFF66BB6A);

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.2, end: 1.0).animate(_pulseCtrl);
    _initTemperatureVideo();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.machineId.isNotEmpty) {
        _fetchMachineStatus();
        _runLivePrediction();
        _loadTelemetryHistory();
      }
    });
    _liveRefreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || widget.machineId.isEmpty || _predictLoading) return;
      _runLivePrediction();
    });

    _machineStatusSub = GlobalNotificationService().machineStatusStream.listen((data) {
      if (data['machineId'] == widget.machineId) {
        if (mounted) {
          setState(() {
            final st = data['status']?.toString().toUpperCase();
            if (st == 'ON' || st == 'RUNNING') _actualMachineStatus = 'RUNNING';
            else if (st == 'OFF' || st == 'STOPPED') _actualMachineStatus = 'STOPPED';
            else _actualMachineStatus = st ?? 'UNKNOWN';
          });
        }
      }
    });

    _dangerAlertSub = GlobalNotificationService().dangerAlertStream.listen((data) {
      if (data['machineId'] == widget.machineId) {
        if (mounted) {
          setState(() {
            _actualMachineStatus = 'STOPPED_DANGER';
            _lastDangerInfo = data;
          });
        }
      }
    });
  }

  Future<void> _fetchMachineStatus() async {
    if (!mounted) return;
    try {
      final info = await ApiService.getMachineInfo(widget.machineId);
      if (mounted) {
        setState(() {
          _actualMachineStatus = info['status'] ?? 'UNKNOWN';
        });
      }
    } catch (_) {}
  }

  Future<void> _resetDanger() async {
    if (!mounted || _isLoadingState) return;
    setState(() => _isLoadingState = true);
    try {
      await ApiService.resetMachineDanger(widget.machineId);
      if (mounted) {
        setState(() {
          _actualMachineStatus = 'STOPPED';
          _lastDangerInfo = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sécurité réinitialisée', style: TextStyle(color: Colors.white)), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e', style: const TextStyle(color: Colors.white)), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isLoadingState = false);
    }
  }

  Future<void> _stopMachine() async {
    if (!mounted || _isLoadingState) return;
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surfaceContainerHigh,
        title: Text("Confirmer l'arrêt", style: GoogleFonts.spaceGrotesk(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text("Êtes-vous sûr de vouloir arrêter physiquement cette machine ?", style: GoogleFonts.inter(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Annuler", style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text("Oui, Arrêter", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _isLoadingState = true);
    try {
      await ApiService.stopMachine(widget.machineId, reason: "Arrêt manuel depuis Analyse IA");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Commande d\'arrêt envoyée', style: TextStyle(color: Colors.white)), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e', style: const TextStyle(color: Colors.white)), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isLoadingState = false);
    }
  }

  Future<void> _startMachine() async {
    if (!mounted || _isLoadingState) return;
    setState(() => _isLoadingState = true);
    try {
      await ApiService.startMachine(widget.machineId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Commande de démarrage envoyée', style: TextStyle(color: Colors.white)), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e', style: const TextStyle(color: Colors.white)), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isLoadingState = false);
    }
  }

  @override
  void didUpdateWidget(covariant AiAnalysisView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.machineId != widget.machineId) {
      _runLivePrediction();
      _loadTelemetryHistory();
    }
  }

  int get _gaugePercent {
    final p = _predictResult?['prob_panne'];
    if (p is num) return p.round().clamp(0, 100);
    if (p is String) return int.tryParse(p)?.clamp(0, 100) ?? 0;
    return 0;
  }

  String _shortScenario(String s) {
    if (s.length <= 24) return s;
    return '${s.substring(0, 24)}…';
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _temperatureVideoController?.dispose();
    _liveRefreshTimer?.cancel();
    _machineStatusSub?.cancel();
    _dangerAlertSub?.cancel();
    super.dispose();
  }

  Future<void> _initTemperatureVideo() async {
    const path = 'assets/videos/temp_motor.mp4';
    String? initError;
    final controller = VideoPlayerController.asset(path)
      ..setLooping(true)
      ..setVolume(0);
    try {
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      await _temperatureVideoController?.dispose();
      _temperatureVideoController = controller;
      controller.play();
      setState(() => _temperatureVideoError = null);
      return;
    } catch (e) {
      initError = e.toString();
      await controller.dispose();
    }
    if (!mounted) return;
    setState(() {
      _temperatureVideoError = initError == null
          ? 'temp_motor.mp4 illisible'
          : 'temp_motor.mp4 illisible ($initError)';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildIaDashboardCard(),
        const SizedBox(height: 12),
        _buildDiagnosticsWindowLikeCapture(),
        const SizedBox(height: 24),
        _buildTelemetry5DaysCard(),
      ],
    );
  }

  Widget _buildDiagnosticsWindowLikeCapture() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildAdvancedHeader(),
          const SizedBox(height: 16),
          _buildSensorsGrid(),
          const SizedBox(height: 16),
          _buildRisksGrid(),
        ],
      ),
    );
  }

  Widget _buildAdvancedHeader() {
    final statusColor = _machineStatusColor;
    final statusText = _machineStatus == 'CRITIQUE' ? 'Mode CRITIQUE' : 'Mode ${_machineStatus}';
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 16,
      runSpacing: 12,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: statusColor.withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: statusColor.withOpacity(0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: _pulseCtrl,
                builder: (_, __) => Opacity(
                  opacity: 0.3 + 0.7 * _pulseCtrl.value,
                  child: Container(
                    width: 10, height: 10,
                    decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                statusText,
                style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w800, color: statusColor),
              ),
            ],
          ),
        ),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 6,
          children: [
            Container(width: 8, height: 8, decoration: const BoxDecoration(color: _green, shape: BoxShape.circle)),
            Text('MQTT Live', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: _green)),
            const SizedBox(width: 10),
            Text(
              'Risque IA : $_gaugePercent%',
              style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w800, color: statusColor),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSensorsGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Toujours 2 colonnes sur mobile, 3 sur grand écran
        final crossAxisCount = constraints.maxWidth > 900 ? 3 : 2;
        // Ratio plus compact pour afficher 2 cartes côte à côte
        final aspectRatio = constraints.maxWidth > 900 ? 2.0 : 1.55;
        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: aspectRatio,
          children: [
            _sensorTile(
              'THERMIQUE', 
              _actualMachineStatus == 'STOPPED' ? '0.0 °C' : '${_diagTemperature.toStringAsFixed(1)} °C', 
              Icons.thermostat, 
              _actualMachineStatus == 'STOPPED' ? Colors.grey : (_diagTemperature > 50 ? _error : (_diagTemperature >= 35 ? _primary : _green))
            ),
            _sensorTile(
              'VOLTAGE', 
              _actualMachineStatus == 'STOPPED' ? '0.0 V' : '${_diagVoltage.toStringAsFixed(1)} V', 
              Icons.flash_on, 
              _actualMachineStatus == 'STOPPED' ? Colors.grey : (_diagVoltage > 250 ? _error : _green)
            ),
            _sensorTile(
              'VIBRATION', 
              _actualMachineStatus == 'STOPPED' ? '0.00 mm/s' : '${_diagVibration.toStringAsFixed(2)} mm/s', 
              Icons.vibration, 
              _actualMachineStatus == 'STOPPED' ? Colors.grey : (_diagVibration > 20 ? _error : (_diagVibration >= 14 ? _primary : _green))
            ),
            _sensorTile(
              'MAGNÉTIQUE', 
              _actualMachineStatus == 'STOPPED' ? '0.00 mT' : '${_diagMagnetic.toStringAsFixed(2)} mT', 
              Icons.explore, 
              _actualMachineStatus == 'STOPPED' ? Colors.grey : _green
            ),
            _sensorTile(
              'INFRA-ROUGE', 
              _actualMachineStatus == 'STOPPED' ? 'INACTIF' : (_diagInfrared <= 0 ? 'N/A' : 'ACTIF'), 
              Icons.wb_sunny, 
              _actualMachineStatus == 'STOPPED' ? Colors.grey : _green
            ),
          ],
        );
      }
    );
  }

  Widget _buildRisksGrid() {
    // Use AI model values if available, fallback to local calculation
    final double heatRisk = (_predictResult?['heat_risk'] is num)
        ? (_predictResult!['heat_risk'] as num).toDouble()
        : (_diagTemperature / 100.0).clamp(0.0, 1.0) * 100;
    final double vibRisk = (_predictResult?['vibration_risk'] is num)
        ? (_predictResult!['vibration_risk'] as num).toDouble()
        : (_diagVibration / 20.0).clamp(0.0, 1.0) * 100;
    
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 900 ? 3 : 1;
        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 2.1,
          children: [
            _riskTile('RISQUE CHAUFFAGE', heatRisk, 'Thermique - ${_diagTemperature.toStringAsFixed(1)} °C', [
              _riskSegment('0-35 °C', _green),
              _riskSegment('35-50 °C', _primary),
              _riskSegment('> 50 °C', _error),
            ]),
            _riskTile('RISQUE VIBRATION', vibRisk, 'Mécanique - ${_diagVibration.toStringAsFixed(2)} mm/s', [
              _riskSegment('0-14 mm/s', _green),
              _riskSegment('14-20 mm/s', _primary),
              _riskSegment('> 20 mm/s', _error),
            ]),
            _riskTile('RISQUE GLOBAL IA', _gaugePercent.toDouble(), _gaugePercent >= 70 ? 'État critique' : (_gaugePercent >= 40 ? 'Surveillance requise' : 'Fonctionnement optimal'), [
              _riskSegment('Normal', _green),
              _riskSegment('Surveillance', _primary),
              _riskSegment('Panne', _error),
            ], isGlobal: true),
          ],
        );
      }
    );
  }

  Widget _sensorTile(String label, String value, IconData icon, Color statusColor) {
    final String statusLabel = statusColor == _error
        ? 'DANGER'
        : (statusColor == _primary ? 'RISQUE' : 'NORMAL');
    return Container(
      decoration: BoxDecoration(
        color: _surfaceContainer.withOpacity(0.85),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusColor.withOpacity(0.18), width: 1),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // En-tête : icône + label + badge statut
          Row(
            children: [
              Icon(icon, size: 14, color: statusColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 9,
                    color: _onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  statusLabel,
                  style: GoogleFonts.inter(
                    fontSize: 7,
                    fontWeight: FontWeight.w800,
                    color: statusColor,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Valeur principale
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: statusColor == _error ? _error : _onSurface,
            ),
          ),
          const SizedBox(height: 6),
          // Barre de statut colorée
          Container(
            height: 3,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              gradient: LinearGradient(
                colors: [statusColor, statusColor.withOpacity(0.08)],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _riskTile(String label, double percentage, String subtitle, List<Widget> segments, {bool isGlobal = false}) {
    final color = percentage >= 70 ? _error : (percentage >= 40 ? _primary : _green);
    final isDanger = percentage >= 70;
    return Container(
      decoration: BoxDecoration(
        color: isGlobal ? _surfaceContainer : _surfaceContainer.withOpacity(0.8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isGlobal ? color.withOpacity(0.3) : Colors.white.withOpacity(0.06)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(isGlobal ? Icons.warning_rounded : Icons.local_fire_department, size: 16, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _onSurfaceVariant, fontWeight: FontWeight.w700, letterSpacing: 1.0),
                ),
              ),
              if (!isGlobal)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    isDanger ? 'CRITIQUE' : 'NORMAL',
                    style: GoogleFonts.inter(fontSize: 8, fontWeight: FontWeight.w800, color: color),
                  ),
                ),
              if (isGlobal)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    isDanger ? 'CRITIQUE' : (percentage >= 40 ? 'SURVEILLANCE' : 'NORMAL'),
                    style: GoogleFonts.inter(fontSize: 8, fontWeight: FontWeight.w800, color: color),
                  ),
                ),
            ],
          ),
          const Spacer(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${percentage.toStringAsFixed(0)}%',
                style: GoogleFonts.inter(fontSize: 30, fontWeight: FontWeight.w800, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    subtitle,
                    style: GoogleFonts.inter(fontSize: 10, color: _onSurfaceVariant),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: segments.map((s) => Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 2), child: s))).toList(),
          ),
        ],
      ),
    );
  }

  Widget _riskSegment(String label, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 6,
          decoration: BoxDecoration(
            color: color.withOpacity(0.8),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: GoogleFonts.spaceGrotesk(fontSize: 8, color: _onSurfaceVariant, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _buildMainDashboardArea() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Etat de machine',
          style: GoogleFonts.inter(
            fontSize: 40,
            fontWeight: FontWeight.w900,
            color: _onSurface,
            height: 0.95,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _tinyHeaderChip('OPERATIONAL', _green),
            const SizedBox(width: 8),
            _tinyHeaderChip('INITIATE_SYNC', _secondary),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _diagMiniCard(
                'TEMPERATURE',
                '${_diagTemperature.toStringAsFixed(1)} °C',
                showTemperatureVideo: false,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _diagMiniCard(
                'VOLTAGE',
                '${_diagVoltage.toStringAsFixed(1)} V',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _diagMiniCard(
                'HUMIDITE',
                '${_diagHumidity.toStringAsFixed(0)} %',
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(flex: 58, child: _diagBarsCard()),
            const SizedBox(width: 8),
            Expanded(flex: 42, child: _diagIntegrityCard()),
          ],
        ),
        const SizedBox(height: 10),
        _diagLogCard(),
      ],
    );
  }

  Widget _tinyHeaderChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _surfaceContainerHighest.withOpacity(0.35),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _onSurfaceVariant, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _diagMiniCard(
    String title,
    String value, {
    bool showTemperatureVideo = false,
  }) {
    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: _surfaceContainer.withOpacity(0.55),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          if (showTemperatureVideo)
            Positioned.fill(
              child: (_temperatureVideoController != null &&
                      _temperatureVideoController!.value.isInitialized)
                  ? Builder(
                      builder: (context) {
                        final controllerValue = _temperatureVideoController!.value;
                        if (!controllerValue.isPlaying) {
                          _temperatureVideoController!.play();
                        }
                        final safeWidth =
                            controllerValue.size.width <= 1 ? 1280.0 : controllerValue.size.width;
                        final safeHeight =
                            controllerValue.size.height <= 1 ? 720.0 : controllerValue.size.height;
                        return FittedBox(
                          fit: BoxFit.cover,
                          child: SizedBox(
                            width: safeWidth,
                            height: safeHeight,
                            child: VideoPlayer(_temperatureVideoController!),
                          ),
                        );
                      },
                    )
                  : Container(
                      color: Colors.black26,
                      alignment: Alignment.center,
                      child: _temperatureVideoError == null
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: Text(
                                _temperatureVideoError!,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  color: Colors.white.withOpacity(0.8),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                    ),
            ),
          if (showTemperatureVideo)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.20),
                      Colors.black.withOpacity(0.08),
                      Colors.black.withOpacity(0.28),
                    ],
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                title,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 9,
                  color: _onSurfaceVariant,
                  letterSpacing: 1.0,
                ),
              ),
              const Spacer(),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  maxLines: 1,
                  softWrap: false,
                  style: GoogleFonts.inter(
                    fontSize: 34,
                    color: _onSurface,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _diagLogCard() {
    return Container(
      height: 86,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _surfaceContainer.withOpacity(0.55),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Text(
        '14:22:01  Hydraulique pression calibree\n13:45:19  Optimisation chemin neural complete\n11:02:44  Variance vibration detectee',
        style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _onSurfaceVariant, height: 1.45),
      ),
    );
  }

  Widget _diagBarsCard() {
    final res = _predictResult;
    final prob = _gaugePercent;
    final bool hasError = (_predictError ?? '').isNotEmpty;
    final scenario = (res?['panne_type'] ?? '').toString().trim();
    final hasValidIa = res != null &&
        !hasError &&
        scenario.isNotEmpty &&
        scenario != '-' &&
        !scenario.toLowerCase().contains('erreur');
    final String state = hasError
        ? 'A CONTROLER'
        : (prob >= 70 ? 'EN PANNE' : (prob >= 40 ? 'A CONTROLER' : 'EN MARCHE'));
    final String detail = hasError
        ? 'Analyse IA indisponible. Verification capteurs/MQTT recommandee.'
        : (_predictResult == null
            ? 'En attente des donnees IA pour evaluer l etat de machine.'
            : 'Probabilite panne: $prob%${_predictResult?['panne_type'] != null ? ' · Scenario: ${_predictResult!['panne_type']}' : ''}.');

    return Container(
      height: 170,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _surfaceContainer.withOpacity(0.55),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: !hasValidIa
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ETAT MACHINE', style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _onSurfaceVariant)),
                const SizedBox(height: 8),
                Text(
                  '------------',
                  style: GoogleFonts.inter(
                    fontSize: 22,
                    color: _onSurfaceVariant.withOpacity(0.55),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            )
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('ETAT MACHINE (IA)', style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _onSurfaceVariant)),
              const SizedBox(height: 10),
              Text(
                state,
                style: GoogleFonts.inter(
                  fontSize: 28,
                  color: state == 'EN PANNE' ? _error : (state == 'A CONTROLER' ? _primaryLight : _green),
                  fontWeight: FontWeight.w900,
                  height: 0.95,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                detail,
                style: GoogleFonts.inter(fontSize: 11, color: _onSurfaceVariant, height: 1.35),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ]),
    );
  }

  Widget _diagIntegrityCard() {
    return Container(
      height: 170,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _surfaceContainer.withOpacity(0.55),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('RISQUE IA', style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _secondary)),
        const SizedBox(height: 8),
        Text(
          'Risque de panne',
          style: GoogleFonts.inter(
            fontSize: 16,
            color: _onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
        const Spacer(),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            '${_gaugePercent}%',
            maxLines: 1,
            softWrap: false,
            style: GoogleFonts.inter(
              fontSize: 56,
              color: _onSurface,
              fontWeight: FontWeight.w900,
              height: 0.9,
            ),
          ),
        ),
        const Spacer(),
        Text('Niveau de risque machine', style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _onSurfaceVariant)),
      ]),
    );
  }

  Widget _diagRightPanel() {
    final hasIa = _predictResult != null && (_predictError ?? '').isEmpty;
    final risk = _gaugePercent;
    final iaState = risk >= 70 ? 'EN PANNE' : (risk >= 40 ? 'A CONTROLER' : 'EN MARCHE');
    final iaMessage = hasIa
        ? 'Etat detecte: $iaState.\nRisque estime: $risk%.\nSouhaitez-vous un plan d action maintenance ?'
        : 'Bonjour, je suis le chatbot IA.\nJe suis en attente des donnees machine pour lancer le diagnostic.';

    return Container(
      height: 310,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _surfaceContainer.withOpacity(0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('CHATBOT IA', style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _onSurfaceVariant)),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _bg.withOpacity(0.55),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withOpacity(0.06)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: _secondary.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.smart_toy_outlined, size: 14, color: _secondary),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    iaMessage,
                    style: GoogleFonts.inter(fontSize: 11, color: _onSurfaceVariant, height: 1.35),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Spacer(),
          Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: _bg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Ecrire un message au chatbot...',
                    style: GoogleFonts.inter(fontSize: 11, color: _onSurfaceVariant.withOpacity(0.7)),
                  ),
                ),
                const Icon(Icons.send_rounded, size: 16, color: _secondary),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadTelemetryHistory() async {
    setState(() {
      _historyLoading = true;
      _historyError = null;
    });
    try {
      final history = await ApiService.getTelemetryHistory(widget.machineId, limit: 500);
      final now = DateTime.now();
      final cutoff = now.subtract(Duration(days: _historyDays));
      var filtered = history.where((item) {
        final dt = _readItemDate(item);
        if (dt == null) return false;
        return dt.isAfter(cutoff);
      }).toList();
      // Fallback: si le backend ne renvoie pas de date parsable, on garde
      // les N derniers points au lieu d'afficher "Aucune donnée".
      if (filtered.isEmpty && history.isNotEmpty) {
        final fallbackCount = _historyDays == 1 ? 48 : (_historyDays == 7 ? 200 : 400);
        filtered = history.take(fallbackCount).toList();
      }
      filtered.sort((a, b) {
        final da = _readItemDate(a) ?? DateTime.fromMillisecondsSinceEpoch(0);
        final db = _readItemDate(b) ?? DateTime.fromMillisecondsSinceEpoch(0);
        return da.compareTo(db);
      });
      if (!mounted) return;
      setState(() => _history5Days = filtered);
    } catch (e) {
      if (!mounted) return;
      setState(() => _historyError = e.toString());
    } finally {
      if (mounted) setState(() => _historyLoading = false);
    }
  }

  DateTime? _readItemDate(Map<String, dynamic> item) {
    final raw =
        item['createdAt'] ??
        item['created_at'] ??
        item['timestamp'] ??
        item['ts'] ??
        item['date'] ??
        item['time'];
    if (raw == null) return null;
    if (raw is DateTime) return raw;
    if (raw is int) {
      // gère timestamp sec/ms
      if (raw > 1000000000000) return DateTime.fromMillisecondsSinceEpoch(raw);
      return DateTime.fromMillisecondsSinceEpoch(raw * 1000);
    }
    if (raw is double) {
      final v = raw.toInt();
      if (v > 1000000000000) return DateTime.fromMillisecondsSinceEpoch(v);
      return DateTime.fromMillisecondsSinceEpoch(v * 1000);
    }
    final s = raw.toString().trim();
    final parsed = DateTime.tryParse(s);
    if (parsed != null) return parsed;
    final asInt = int.tryParse(s);
    if (asInt != null) {
      if (asInt > 1000000000000) return DateTime.fromMillisecondsSinceEpoch(asInt);
      return DateTime.fromMillisecondsSinceEpoch(asInt * 1000);
    }
    return null;
  }

  double _metricOf(Map<String, dynamic> item, String metric) {
    final metrics = item['metrics'];
    if (metric == 'temperature') {
      final v = item['temperature'] ?? (metrics is Map ? metrics['thermal'] : null);
      return (v is num) ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;
    }
    if (metric == 'vibration') {
      final v = item['vibration'] ?? (metrics is Map ? metrics['vibration'] : null);
      return (v is num) ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;
    }
    final v = item['powerConsumption'] ?? item['power'] ?? (metrics is Map ? metrics['power'] : null);
    return (v is num) ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;
  }

  String get _machineStatus {
    final status = _predictResult?['status']?.toString().toUpperCase() ?? '';
    if (status.isNotEmpty && status != 'UNKNOWN') {
      if (status == 'CRITICAL') return 'CRITIQUE';
      if (status == 'WARNING') return 'SURVEILLANCE';
      if (status == 'NORMAL') return 'STABLE';
      return status;
    }
    final p = _gaugePercent;
    if (p >= 70) return 'CRITIQUE';
    if (p >= 40) return 'SURVEILLANCE';
    return 'STABLE';
  }

  Color get _machineStatusColor {
    final status = _predictResult?['status']?.toString().toUpperCase() ?? '';
    if (status.isNotEmpty && status != 'UNKNOWN') {
      if (status == 'CRITICAL') return _error;
      if (status == 'WARNING') return _primary;
      if (status == 'NORMAL') return _green;
    }
    final p = _gaugePercent;
    if (p >= 70) return _error;
    if (p >= 40) return _primary;
    return _green;
  }

  Widget _buildDangerBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF3B0000).withOpacity(0.8), // Dark red background
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.redAccent, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.red.withOpacity(0.4),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 36),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  '🚨 ARRÊT DANGER ACTIVÉ',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('⚠️ Machine arrêtée automatiquement', style: GoogleFonts.inter(fontSize: 16, color: Colors.white)),
          const SizedBox(height: 8),
          if (_lastDangerInfo != null) ...[
            Text('Cause : ${_lastDangerInfo!['reason']} (${_lastDangerInfo!['value']})', style: GoogleFonts.inter(fontSize: 16, color: Colors.white70)),
            const SizedBox(height: 4),
            Text('Heure : ${_lastDangerInfo!['timestamp'] != null ? DateTime.parse(_lastDangerInfo!['timestamp']).toLocal().toString().split('.')[0] : 'Inconnue'}', style: GoogleFonts.inter(fontSize: 16, color: Colors.white70)),
          ],
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              ElevatedButton.icon(
                onPressed: _isLoadingState ? null : _resetDanger,
                icon: _isLoadingState ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.lock_open, size: 20),
                label: Text('🔓 RÉINITIALISER', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold, fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.red[900],
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: _surfaceContainerHigh,
                      title: Text("📋 Rapport d'Incident", style: GoogleFonts.spaceGrotesk(color: Colors.white, fontWeight: FontWeight.bold)),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Détails de l'arrêt de sécurité automatique.", style: GoogleFonts.inter(color: Colors.white70)),
                          const SizedBox(height: 16),
                          if (_lastDangerInfo != null) ...[
                            Text("Capteur : ${_lastDangerInfo!['sensor']?.toString().toUpperCase()}", style: const TextStyle(color: Colors.white)),
                            const SizedBox(height: 8),
                            Text("Valeur mesurée : ${_lastDangerInfo!['value']}", style: const TextStyle(color: Colors.white)),
                            const SizedBox(height: 8),
                            Text("Seuil critique : ${_lastDangerInfo!['threshold']}", style: const TextStyle(color: Colors.white)),
                          ] else
                            const Text("Aucun détail disponible.", style: TextStyle(color: Colors.white54)),
                        ],
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text("Fermer", style: TextStyle(color: Colors.white70)),
                        ),
                      ],
                    ),
                  );
                },
                icon: const Icon(Icons.content_paste_search, size: 20),
                label: Text('📋 VOIR RAPPORT', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold, fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _surfaceContainerHighest,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildIaDashboardCard() {
    if (_actualMachineStatus == 'STOPPED_DANGER') {
      return _buildDangerBanner();
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 16,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          Wrap(
            runSpacing: 10,
            spacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _chipInfo('MACHINE', widget.machineName.toUpperCase(), _secondary),
              _chipInfo('ID', widget.machineId, _onSurfaceVariant),
              _chipInfo('ÉTAT', _machineStatus, _machineStatusColor),
              _chipInfo('RELAIS', _actualMachineStatus == 'RUNNING' ? 'EN MARCHE' : (_actualMachineStatus == 'STOPPED' ? 'ARRÊTÉ' : _actualMachineStatus), _actualMachineStatus == 'RUNNING' ? _green : (_actualMachineStatus == 'STOPPED' ? Colors.red : _onSurfaceVariant)),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              // Bouton MISSION : visible uniquement pour les agents de maintenance
              if (!widget.isClientView && widget.viewerRole == 'maintenance')
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => SendMissionPage(
                          machineId: widget.machineId,
                          machineName: widget.machineName,
                          agentName: 'Agent maintenance',
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.assignment, size: 18),
                  label: Text('MISSION', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold, fontSize: 14)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurpleAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                  ElevatedButton.icon(
                    onPressed: _isLoadingState || _actualMachineStatus == 'STOPPED' ? null : _stopMachine,
                    icon: _isLoadingState && _actualMachineStatus == 'RUNNING' ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.stop_circle, size: 18),
                    label: Text('ARRÊT', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold, fontSize: 14)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.redAccent.withOpacity(0.3),
                      disabledForegroundColor: Colors.white54,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _isLoadingState || _actualMachineStatus == 'RUNNING' ? null : _startMachine,
                    icon: _isLoadingState && _actualMachineStatus == 'STOPPED' ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.play_circle, size: 18),
                    label: Text('MARCHE', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold, fontSize: 14)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.green.withOpacity(0.3),
                      disabledForegroundColor: Colors.white54,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
              ElevatedButton.icon(
                onPressed: () {
                  _showIaDetailsDialog();
                },
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: Text('IA', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold, fontSize: 14)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              ElevatedButton.icon(
                onPressed: _downloadPdf,
                icon: const Icon(Icons.download_rounded, size: 18),
                label: Text('PDF', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold, fontSize: 14)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D32),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chipInfo(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _surfaceContainerHighest.withOpacity(0.35),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 9,
                  letterSpacing: 1.4,
                  color: _onSurfaceVariant.withOpacity(0.9))),
          const SizedBox(height: 3),
          Text(value,
              style: GoogleFonts.inter(
                  fontSize: 12, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }

  // Diagnostics locaux basés sur le type de panne (miroir du backend Python)
  static const Map<String, Map<String, String>> _localDiagnostics = {
    'NORMAL': {
      'message': '✅ Machine en bon état de fonctionnement.',
      'recommandation': 'Aucune action requise. Continuer la surveillance.',
    },
    'SURCHAUFFE': {
      'message': '🌡️ Température anormalement élevée détectée.',
      'recommandation': 'Vérifier le système de refroidissement. Réduire la charge si possible.',
    },
    'SURCHARGE': {
      'message': '⚡ Surcharge électrique détectée — courant et puissance hors limites.',
      'recommandation': "Réduire immédiatement la charge machine. Vérifier l'alimentation électrique.",
    },
    'ELECTRIQUE': {
      'message': '🔌 Anomalie électrique détectée — variation de tension ou de fréquence.',
      'recommandation': 'Inspecter le câblage et les connexions. Contacter un électricien.',
    },
    'ROULEMENT': {
      'message': '🔧 Vibrations anormales — usure probable des roulements.',
      'recommandation': "Planifier une inspection mécanique. Vérifier les roulements et l'alignement.",
    },
    'USURE_GENERALE': {
      'message': '📉 Dégradation progressive détectée — usure générale de la machine.',
      'recommandation': 'Programmer une maintenance préventive dans les prochains jours.',
    },
  };
  Future<void> _downloadPdf() async {
    final pdf = pw.Document();
    final panneType = (_predictResult?['panne_type'] ?? _predictResult?['type_panne'] ?? 'NORMAL').toString().toUpperCase();
    final localDiag = _localDiagnostics[panneType] ?? _localDiagnostics['NORMAL']!;
    final diag = (_predictResult?['diagnostic'] != null && _predictResult!['diagnostic'].toString().isNotEmpty)
        ? _predictResult!['diagnostic'].toString()
        : localDiag['message']!;
    final rec = (_predictResult?['recommandation'] != null && _predictResult!['recommandation'].toString().isNotEmpty)
        ? _predictResult!['recommandation'].toString()
        : localDiag['recommandation']!;
    final risk = _predictResult?['prob_panne'] ?? _predictResult?['risk_percentage'] ?? 0;
    final rul = (_predictResult?['rul_estime'] ?? _predictResult?['details']?['rul_cycles'])?.toString() ?? 'N/A';
    final now = DateTime.now();
    final dateStr = '${now.day.toString().padLeft(2,'0')}/${now.month.toString().padLeft(2,'0')}/${now.year} ${now.hour.toString().padLeft(2,'0')}:${now.minute.toString().padLeft(2,'0')}';

    List<Map<String, dynamic>> missions = [];
    try {
      final result = await ApiService.getMissionsByMachineId(widget.machineId);
      if (result is List) missions = result.cast<Map<String, dynamic>>();
    } catch (_) {}

    final historyRows = _history5Days.reversed.take(50).map((item) {
      final dt = _readItemDate(item);
      final temp = (item['temperature'] as num?)?.toDouble() ?? (item['metrics']?['thermal'] as num?)?.toDouble() ?? 0.0;
      final vib = (item['vibration'] as num?)?.toDouble() ?? (item['metrics']?['vibration'] as num?)?.toDouble() ?? 0.0;
      final volt = (item['voltage'] as num?)?.toDouble() ?? 0.0;
      final state = (item['machineState'] ?? item['status'] ?? item['etat'] ?? 'N/A').toString();
      final dateLabel = dt != null
          ? '${dt.day.toString().padLeft(2,'0')}/${dt.month.toString().padLeft(2,'0')} ${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}'
          : '--';
      return [dateLabel, '${temp.toStringAsFixed(1)} °C', '${vib.toStringAsFixed(2)} mm/s', '${volt.toStringAsFixed(1)} V', state];
    }).toList();

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      header: (ctx) => pw.Container(
        decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF1A1A2E)),
        padding: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text('ABBK PhysicsWorks', style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold, color: PdfColor.fromInt(0xFFFF9F64))),
          pw.Text('Rapport IA — $dateStr', style: pw.TextStyle(fontSize: 9, color: PdfColor.fromInt(0xFF9E9EAE))),
        ]),
      ),
      build: (ctx) => [
        pw.SizedBox(height: 16),
        pw.Text('Rapport d\'analyse IA — ${widget.machineName}',
            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
        pw.Text('Machine ID : ${widget.machineId}',
            style: pw.TextStyle(fontSize: 10, color: PdfColor.fromInt(0xFF666666))),
        pw.SizedBox(height: 20),

        // IA Summary
        pw.Container(
          padding: const pw.EdgeInsets.all(14),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColor.fromInt(0xFFFF9F64), width: 1.5),
            borderRadius: pw.BorderRadius.circular(8),
          ),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('ANALYSE IA', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),
            pw.Row(children: [pw.Text('Risque global : ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)), pw.Text('$risk%')]),
            pw.Row(children: [pw.Text('Type de panne : ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)), pw.Text(panneType)]),
            pw.Row(children: [pw.Text('RUL : ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)), pw.Text(rul)]),
            pw.SizedBox(height: 6),
            pw.Text('Diagnostic :', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.Text(diag),
            pw.SizedBox(height: 4),
            pw.Text('Recommandation :', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.Text(rec),
          ]),
        ),
        pw.SizedBox(height: 16),

        // Sensors
        pw.Text('CAPTEURS EN TEMPS RÉEL', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColor.fromInt(0xFFCCCCCC)),
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF444444)),
              children: ['Capteur', 'Valeur'].map((h) => pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text(h, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 10)))).toList(),
            ),
            pw.TableRow(children: [pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Température')), pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('${_diagTemperature.toStringAsFixed(1)} °C'))]),
            pw.TableRow(children: [pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Vibration')), pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('${_diagVibration.toStringAsFixed(2)} mm/s'))]),
            pw.TableRow(children: [pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Voltage')), pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('${_diagVoltage.toStringAsFixed(1)} V'))]),
            pw.TableRow(children: [pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Magnétique')), pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('${_diagMagnetic.toStringAsFixed(2)} mT'))]),
            pw.TableRow(children: [pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Puissance')), pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('${_diagPower.toStringAsFixed(1)} W'))]),
          ],
        ),
        pw.SizedBox(height: 16),

        // History
        if (historyRows.isNotEmpty) ...[
          pw.Text('HISTORIQUE TÉLÉMÉTRIE (${historyRows.length} enregistrements)', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColor.fromInt(0xFFCCCCCC)),
            columnWidths: {0: const pw.FlexColumnWidth(2), 1: const pw.FlexColumnWidth(1.5), 2: const pw.FlexColumnWidth(1.5), 3: const pw.FlexColumnWidth(1.5), 4: const pw.FlexColumnWidth(1.5)},
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF444444)),
                children: ['Date', 'Temp.', 'Vibration', 'Voltage', 'État'].map((h) => pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(h, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 8)))).toList(),
              ),
              ...historyRows.map((row) => pw.TableRow(children: row.map((cell) => pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(cell, style: const pw.TextStyle(fontSize: 8)))).toList())),
            ],
          ),
          pw.SizedBox(height: 16),
        ],

        // Missions
        pw.Text('MISSIONS', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        if (missions.isEmpty)
          pw.Text('Aucune mission trouvée pour cette machine.', style: pw.TextStyle(fontSize: 10, color: PdfColor.fromInt(0xFF888888)))
        else
          pw.Table(
            border: pw.TableBorder.all(color: PdfColor.fromInt(0xFFCCCCCC)),
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF444444)),
                children: ['Titre', 'Statut', 'Priorité', 'Date'].map((h) => pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text(h, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 9)))).toList(),
              ),
              ...missions.map((m) {
                final mdt = m['createdAt']?.toString() ?? '--';
                return pw.TableRow(children: [
                  pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text((m['title'] ?? '').toString(), style: const pw.TextStyle(fontSize: 8))),
                  pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text((m['status'] ?? '').toString(), style: const pw.TextStyle(fontSize: 8))),
                  pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text((m['priority'] ?? '').toString(), style: const pw.TextStyle(fontSize: 8))),
                  pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(mdt.length > 10 ? mdt.substring(0, 10) : mdt, style: const pw.TextStyle(fontSize: 8))),
                ]);
              }),
            ],
          ),
      ],
    ));

    await Printing.layoutPdf(
      onLayout: (format) async => pdf.save(),
      name: 'Rapport_IA_${widget.machineName.replaceAll(' ', '_')}.pdf',
    );
  }

  void _showIaDetailsDialog() {
    if (_predictResult == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucune donnée IA disponible pour le moment.')),
      );
      return;
    }

    // Vraies clés retournées par l'API
    final panneType = (_predictResult?['panne_type'] ?? _predictResult?['type_panne'] ?? 'NORMAL').toString().toUpperCase();
    final localDiag = _localDiagnostics[panneType] ?? _localDiagnostics['NORMAL']!;

    // Diagnostic : essai clé directe, sinon génération locale depuis panne_type
    final diag = (_predictResult?['diagnostic'] != null && _predictResult!['diagnostic'].toString().isNotEmpty)
        ? _predictResult!['diagnostic'].toString()
        : localDiag['message']!;

    // Recommandation : essai clé directe, sinon génération locale
    final rec = (_predictResult?['recommandation'] != null && _predictResult!['recommandation'].toString().isNotEmpty)
        ? _predictResult!['recommandation'].toString()
        : localDiag['recommandation']!;

    // RUL : clé directe rul_estime ou dans details.rul_cycles
    final rulRaw = _predictResult?['rul_estime'] ?? _predictResult?['details']?['rul_cycles'];
    final rul = rulRaw != null ? rulRaw.toString() : 'N/A';

    // Risque global : prob_panne (0-100 int) ou risk_percentage
    final risk = _predictResult?['prob_panne'] ?? _predictResult?['risk_percentage'] ?? 0;

    // Scénarios : directement dans scenario_scores ou dans details.scenario_scores
    final scenarios = (_predictResult?['scenario_scores'] ??
        _predictResult?['details']?['scenario_scores']) as Map<String, dynamic>? ?? {};

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: _surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.white.withOpacity(0.08)),
          ),
          child: Container(
            width: 600,
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    Text(
                      'DÉTAILS DU MODÈLE IA',
                      style: GoogleFonts.spaceGrotesk(fontSize: 16, fontWeight: FontWeight.bold, color: _onSurfaceVariant, letterSpacing: 1.2),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _primaryLight.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Anomalie Globale: $risk%',
                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: _primaryLight),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text('Diagnostic:', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: _secondary)),
                const SizedBox(height: 6),
                Text(diag, style: GoogleFonts.inter(fontSize: 15, color: _onSurface)),
                const SizedBox(height: 16),
                Text('Recommandation:', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: _secondary)),
                const SizedBox(height: 6),
                Text(rec, style: GoogleFonts.inter(fontSize: 15, color: _onSurface)),
                const SizedBox(height: 16),
                Text('Vie utile restante (RUL):', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: _secondary)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.timer_outlined, size: 18, color: _error),
                    const SizedBox(width: 8),
                    Text('~$rul heures', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: _error)),
                  ],
                ),
                const SizedBox(height: 24),
                Text('Répartition des Scénarios:', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: _onSurface)),
                const SizedBox(height: 16),
                ...scenarios.entries.map((e) {
                  final sName = e.key;
                  final sVal = (e.value as num).toDouble() * 100;
                  Color barColor = _primaryLight;
                  if (sName == 'NORMAL') barColor = _green;
                  else if (sVal > 50) barColor = _error;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 140,
                          child: Text(
                            sName,
                            style: GoogleFonts.spaceGrotesk(fontSize: 12, color: _onSurfaceVariant, letterSpacing: 1.0, fontWeight: FontWeight.bold),
                          ),
                        ),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: sVal / 100,
                              backgroundColor: Colors.white.withOpacity(0.05),
                              color: barColor,
                              minHeight: 8,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        SizedBox(
                          width: 50,
                          child: Text(
                            '${sVal.toStringAsFixed(1)}%',
                            textAlign: TextAlign.right,
                            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: _onSurface),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
                const SizedBox(height: 24),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      foregroundColor: _onSurface,
                      backgroundColor: Colors.white.withOpacity(0.05),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                    child: Text('Fermer', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTelemetry5DaysCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Etat de machine',
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 11,
                        color: _onSurfaceVariant,
                        letterSpacing: 1.4,
                        fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 8),
              _rangeChip(1, '24H'),
              const SizedBox(width: 6),
              _rangeChip(7, '7J'),
              const SizedBox(width: 6),
              _rangeChip(30, '30J'),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _legendItem(_primary, 'Température'),
              const SizedBox(width: 12),
              _legendItem(_secondary, 'Vibration'),
              const SizedBox(width: 12),
              _legendItem(_green, 'Puissance'),
            ],
          ),
          const SizedBox(height: 12),
          Text('Fenêtre: ${_historyDays == 1 ? '24 heures' : '$_historyDays jours'}',
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 10, color: _onSurfaceVariant.withOpacity(0.85))),
          const SizedBox(height: 12),
          if (_historyLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (_historyError != null)
            Text('Erreur chargement historique: $_historyError',
                style: GoogleFonts.inter(color: _error, fontSize: 12))
          else ...[
            _combinedMetricChart(),
            _historyDataTable(),
          ],
          if (!_historyLoading && _historyError == null && _history5Days.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Mode par défaut: axes affichés en attente de données.',
                style: GoogleFonts.inter(color: _onSurfaceVariant, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }

  Widget _historyDataTable() {
    if (_history5Days.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 24),
      width: double.infinity,
      decoration: BoxDecoration(
        color: _surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Tableau Historique',
              style: GoogleFonts.spaceGrotesk(fontSize: 14, fontWeight: FontWeight.w700, color: _onSurface),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: MaterialStateProperty.all(_surfaceContainerHighest.withOpacity(0.5)),
              columns: [
                DataColumn(label: Text('Date', style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: _onSurface))),
                DataColumn(label: Text('Température', style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: _onSurface))),
                DataColumn(label: Text('Vibration', style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: _onSurface))),
                DataColumn(label: Text('Puissance', style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: _onSurface))),
                DataColumn(label: Text('Etat Machine', style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: _onSurface))),
              ],
              rows: _history5Days.reversed.take(10).map((item) {
                final dt = _readItemDate(item);
                final temp = (item['temperature'] as num?)?.toDouble() ?? (item['metrics']?['thermal'] as num?)?.toDouble() ?? 0.0;
                final vib = (item['vibration'] as num?)?.toDouble() ?? (item['metrics']?['vibration'] as num?)?.toDouble() ?? 0.0;
                final pow = (item['powerConsumption'] as num?)?.toDouble() ?? (item['metrics']?['power'] as num?)?.toDouble() ?? 0.0;
                
                String etat = 'NORMAL';
                Color etatColor = _green;
                
                 if (temp > 50 || vib > 20) {
                  etat = 'DANGER';
                  etatColor = _error;
                } else if ((temp >= 35 && temp <= 50) || (vib >= 14 && vib <= 20)) {
                  etat = 'RISQUE';
                  etatColor = _primary;
                }
                
                final dateStr = dt != null ? "${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}" : "-";
                
                return DataRow(cells: [
                  DataCell(Text(dateStr, style: GoogleFonts.inter(fontSize: 12, color: _onSurfaceVariant))),
                  DataCell(Text('${temp.toStringAsFixed(1)} °C', style: GoogleFonts.inter(fontSize: 12, color: _onSurface))),
                  DataCell(Text('${vib.toStringAsFixed(2)} mm/s', style: GoogleFonts.inter(fontSize: 12, color: _onSurface))),
                  DataCell(Text('${pow.toStringAsFixed(1)} kW', style: GoogleFonts.inter(fontSize: 12, color: _onSurface))),
                  DataCell(
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: etatColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(etat, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w800, color: etatColor)),
                    ),
                  ),
                ]);
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _combinedMetricChart() {
    final hasData = _history5Days.isNotEmpty;
    final tempSpots = hasData ? _normalizedSpots('temperature') : _defaultSpots(0);
    final vibrationSpots = hasData ? _normalizedSpots('vibration') : _defaultSpots(1);
    final powerSpots = hasData ? _normalizedSpots('power') : _defaultSpots(2);
    final count = hasData ? _history5Days.length : 8;
    final step = count > 2 ? ((count - 1) / 2).round() : 1;

    return SizedBox(
      height: 220,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Graphe multi-lignes (échelle normalisée)',
            style: GoogleFonts.inter(fontSize: 12, color: _onSurface),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: 100,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: true,
                  verticalInterval: count > 1 ? (count - 1) / 4 : 1,
                  horizontalInterval: 25,
                  getDrawingHorizontalLine: (_) =>
                      FlLine(color: Colors.white.withOpacity(0.08), strokeWidth: 1),
                  getDrawingVerticalLine: (_) =>
                      FlLine(color: Colors.white.withOpacity(0.05), strokeWidth: 1),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      interval: 25,
                      getTitlesWidget: (value, meta) => Text(
                        value.toInt().toString(),
                        style: GoogleFonts.inter(
                          fontSize: 9,
                          color: _onSurfaceVariant.withOpacity(0.8),
                        ),
                      ),
                    ),
                  ),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 20,
                      interval: step.toDouble(),
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt().clamp(0, count - 1);
                        return Text(
                          _historyLabelAt(idx),
                          style: GoogleFonts.inter(
                            fontSize: 9,
                            color: _onSurfaceVariant.withOpacity(0.85),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => _surfaceContainerHighest.withOpacity(0.9),
                    getTooltipItems: (spotsTouched) => spotsTouched.map((s) {
                      final idx = s.x.toInt().clamp(0, _history5Days.length - 1);
                      final m = _history5Days[idx];
                      final t = _metricOf(m, 'temperature');
                      final v = _metricOf(m, 'vibration');
                      final p = _metricOf(m, 'power');
                      return LineTooltipItem(
                        'T ${t.toStringAsFixed(1)}°C\nV ${v.toStringAsFixed(2)}\nP ${p.toStringAsFixed(0)}W',
                        GoogleFonts.inter(
                          color: _onSurface,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      );
                    }).toList(),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: tempSpots,
                    isCurved: true,
                    color: _primary,
                    barWidth: 2.3,
                    dotData: const FlDotData(show: false),
                    dashArray: hasData ? null : [5, 4],
                  ),
                  LineChartBarData(
                    spots: vibrationSpots,
                    isCurved: true,
                    color: _secondary,
                    barWidth: 2.3,
                    dotData: const FlDotData(show: false),
                    dashArray: hasData ? null : [5, 4],
                  ),
                  LineChartBarData(
                    spots: powerSpots,
                    isCurved: true,
                    color: _green,
                    barWidth: 2.3,
                    dotData: const FlDotData(show: false),
                    dashArray: hasData ? null : [5, 4],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<FlSpot> _defaultSpots(int variant) {
    final base = [22.0, 42.0, 30.0, 55.0, 40.0, 63.0, 48.0, 58.0];
    return List<FlSpot>.generate(base.length, (i) {
      final v = base[i] + (variant * 6.0);
      return FlSpot(i.toDouble(), v.clamp(0, 100));
    });
  }

  List<FlSpot> _normalizedSpots(String metric) {
    final raw = <double>[];
    for (var i = 0; i < _history5Days.length; i++) {
      raw.add(_metricOf(_history5Days[i], metric));
    }
    if (raw.isEmpty) return const <FlSpot>[];
    final min = raw.reduce(math.min);
    final max = raw.reduce(math.max);
    final range = (max - min).abs();
    if (range < 0.00001) {
      return List<FlSpot>.generate(raw.length, (i) => FlSpot(i.toDouble(), 50));
    }
    return List<FlSpot>.generate(raw.length, (i) {
      final n = ((raw[i] - min) / range) * 100.0;
      return FlSpot(i.toDouble(), n.clamp(0, 100));
    });
  }

  Widget _rangeChip(int days, String label) {
    final active = _historyDays == days;
    return InkWell(
      onTap: () {
        if (_historyDays == days) return;
        setState(() => _historyDays = days);
        _loadTelemetryHistory();
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? _primary.withOpacity(0.18) : _surfaceContainerHighest.withOpacity(0.35),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: active ? _primary : Colors.white.withOpacity(0.09)),
        ),
        child: Text(
          label,
          style: GoogleFonts.spaceGrotesk(
            fontSize: 10,
            color: active ? _primaryLight : _onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _legendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 6),
        Text(label, style: GoogleFonts.inter(fontSize: 11, color: _onSurfaceVariant)),
      ],
    );
  }

  String _historyLabelAt(int index) {
    if (_history5Days.isEmpty) {
      if (_historyDays == 1) {
        final labels = ['-24h', '-20h', '-16h', '-12h', '-8h', '-4h', '-2h', 'now'];
        final i = index.clamp(0, labels.length - 1);
        return labels[i];
      }
      final labels = _historyDays == 7
          ? ['J-7', 'J-6', 'J-5', 'J-4', 'J-3', 'J-2', 'J-1', 'J']
          : ['J-30', 'J-24', 'J-18', 'J-12', 'J-6', 'J-3', 'J-1', 'J'];
      final i = index.clamp(0, labels.length - 1);
      return labels[i];
    }
    final i = index.clamp(0, _history5Days.length - 1);
    final dt = _readItemDate(_history5Days[i]);
    if (dt == null) return '--';
    final dd = dt.day.toString().padLeft(2, '0');
    final mm = dt.month.toString().padLeft(2, '0');
    if (_historyDays == 1) {
      final hh = dt.hour.toString().padLeft(2, '0');
      final min = dt.minute.toString().padLeft(2, '0');
      return '$hh:$min';
    }
    return '$dd/$mm';
  }

  Future<void> _runLivePrediction() async {
    setState(() {
      _predictLoading = true;
      _predictError = null;
    });
    try {
      Map<String, dynamic>? metrics;
      Map<String, dynamic>? latest;
      try {
        latest = await ApiService.getLatestTelemetry(widget.machineId);
        final raw = latest?['metrics'];
        if (raw is Map) {
          final rm = raw;
          metrics = Map<String, dynamic>.from(
            rm.map((k, v) => MapEntry(k.toString(), v)),
          );
        }
      } catch (_) {}

      double temp = 0;
      double voltage = 0;
      double power = 0;
      double vibration = 0;
      int presence = 0;
      double magnetic = 0;
      double infrared = 0;
      double courant = 0;
      int rpm = 0;
      int torque = 0;
      int toolWear = 0;

      final diagTemp = (latest?['temperature'] as num?)?.toDouble() ??
          (latest?['temp'] as num?)?.toDouble() ??
          (metrics?['thermal'] as num?)?.toDouble() ??
          0;
      final diagVoltage = (latest?['voltage'] as num?)?.toDouble() ??
          (latest?['tension'] as num?)?.toDouble() ??
          (latest?['pressure'] as num?)?.toDouble() ??
          (latest?['pression'] as num?)?.toDouble() ??
          (metrics?['voltage'] as num?)?.toDouble() ??
          (metrics?['tension'] as num?)?.toDouble() ??
          (metrics?['pressure'] as num?)?.toDouble() ??
          (metrics?['pression'] as num?)?.toDouble() ??
          0;
      final diagHumidity = (latest?['humidity'] as num?)?.toDouble() ??
          (metrics?['humidity'] as num?)?.toDouble() ??
          0;

      if (latest != null) {
        temp = (latest['temperature'] as num?)?.toDouble() ??
            (latest['temp'] as num?)?.toDouble() ??
            (metrics?['thermal'] as num?)?.toDouble() ??
            temp;
        vibration = (latest['vibration'] as num?)?.toDouble() ??
            (metrics?['vibration'] as num?)?.toDouble() ??
            vibration;
        power = (latest['puissance'] as num?)?.toDouble() ??
            (latest['power'] as num?)?.toDouble() ??
            (latest['powerConsumption'] as num?)?.toDouble() ??
            (metrics?['puissance'] as num?)?.toDouble() ??
            (metrics?['power'] as num?)?.toDouble() ??
            (metrics?['powerConsumption'] as num?)?.toDouble() ??
            power;
        voltage = (latest['voltage'] as num?)?.toDouble() ??
            (latest['tension'] as num?)?.toDouble() ??
            (latest['pressure'] as num?)?.toDouble() ??
            (latest['pression'] as num?)?.toDouble() ??
            (metrics?['voltage'] as num?)?.toDouble() ??
            (metrics?['tension'] as num?)?.toDouble() ??
            (metrics?['pressure'] as num?)?.toDouble() ??
            (metrics?['pression'] as num?)?.toDouble() ??
            voltage;
        courant = (latest['courant'] as num?)?.toDouble() ??
            (latest['current'] as num?)?.toDouble() ??
            (metrics?['courant'] as num?)?.toDouble() ??
            (metrics?['current'] as num?)?.toDouble() ??
            courant;
        magnetic = (latest['magnetic'] as num?)?.toDouble() ??
            (latest['magnet'] as num?)?.toDouble() ??
            (metrics?['magnetic'] as num?)?.toDouble() ??
            (metrics?['magnet'] as num?)?.toDouble() ??
            magnetic;
        infrared = (latest['infrared'] as num?)?.toDouble() ??
            (latest['infrarouge'] as num?)?.toDouble() ??
            (metrics?['infrared'] as num?)?.toDouble() ??
            (metrics?['infrarouge'] as num?)?.toDouble() ??
            infrared;
        presence = (latest['presence'] as num?)?.round() ??
            (metrics?['presence'] as num?)?.round() ??
            presence;
      }

      final recentHistory = _history5Days.length > 10
          ? _history5Days.sublist(_history5Days.length - 10)
          : _history5Days;

      final historyPayload = recentHistory.map((h) => {
            'temperature': _metricOf(h, 'temperature'),
            'vibration': _metricOf(h, 'vibration'),
            'power': _metricOf(h, 'powerConsumption'),
          }).toList();

      final result = await ApiService.predictMachine(
        {
          'type_moteur': widget.motorType.toUpperCase(),
          'temperature': temp,
          'pressure': voltage, // send voltage as pressure for backward compatibility
          'voltage': voltage,
          'tension': voltage,
          'power': power,
          'puissance': power,
          'vibration': vibration,
          'presence': presence,
          'magnetic': magnetic,
          'infrared': infrared,
          'courant': courant,
          'current': courant,
          'rpm': rpm,
          'torque': torque,
          'tool_wear': toolWear,
          'history': historyPayload,
        },
        machineId: widget.machineId,
      );
      if (!mounted) return;
      final newHistoryItem = {
        'createdAt': DateTime.now().toIso8601String(),
        'temperature': temp,
        'vibration': vibration,
        'powerConsumption': power,
        'metrics': {
          'thermal': temp,
          'vibration': vibration,
          'power': power,
        },
      };

      setState(() {
        _history5Days.add(newHistoryItem);
        if (_history5Days.length > 500) _history5Days.removeAt(0);

        _predictResult = result;
        _diagTemperature = diagTemp;
        _diagVoltage = diagVoltage;
        _diagHumidity = diagHumidity;
        _diagPower = power;
        _diagVibration = vibration;
        _diagMagnetic = magnetic;
        _diagInfrared = infrared;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _predictError = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _predictLoading = false;
        });
      }
    }
  }

  Widget _buildLiveIaCard() {
    final res = _predictResult;
    final prob = res?["prob_panne"];
    final niveau = res?["niveau"] ?? "-";
    final scenario = res?["panne_type"] ?? "-";
    final rul = res?["rul_estime"];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          ElevatedButton.icon(
            onPressed: _predictLoading ? null : _runLivePrediction,
            icon: _predictLoading
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.bolt),
            label: Text(
              _predictLoading ? "Analyse..." : "Tester IA Live",
              style: GoogleFonts.inter(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              _predictError != null
                  ? "Erreur IA: $_predictError"
                  : "Prob: ${prob ?? '-'}% | Niveau: $niveau | Scenario: $scenario | RUL: ${rul ?? '-'}",
              style: GoogleFonts.inter(
                color: _predictError != null ? _error : _onSurface,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════ PAGE HEADER ══════════════════════════
  Widget _buildPageHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Analyse de Données',
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 12,
                        color: _onSurfaceVariant,
                        letterSpacing: 1.5)),
                const SizedBox(width: 8),
                Text('/',
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 12, color: _onSurfaceVariant)),
                const SizedBox(width: 8),
                Text(
                  widget.machineId,
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 12, color: _secondary),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Analyse Prédictive IA — ${widget.machineName}',
              style: GoogleFonts.inter(
                  fontSize: 36, fontWeight: FontWeight.w900, color: _onSurface),
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            color: _surfaceContainerHigh,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              AnimatedBuilder(
                animation: _pulseAnim,
                builder: (_, __) => Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: _error.withOpacity(_pulseAnim.value),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                          color: _error.withOpacity(0.4), blurRadius: 8)
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                _predictResult == null
                    ? 'CHARGEMENT ANALYSE…'
                    : 'NIVEAU : ${(_predictResult?['niveau'] ?? '—').toString().toUpperCase()}',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: _error,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ═══════════════════════ TOP GRID ══════════════════════════════
  Widget _buildTopGrid(bool isDesktop) {
    if (isDesktop) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 8, child: _buildChartCard()),
          const SizedBox(width: 32),
          Expanded(flex: 4, child: _buildGaugeCard()),
        ],
      );
    }
    return Column(
      children: [
        _buildGaugeCard(),
        const SizedBox(height: 32),
        _buildChartCard(),
      ],
    );
  }

  Widget _buildGaugeCard() {
    return Container(
      height: 460,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: _surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('PROBABILITÉ DE PANNE',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: _onSurfaceVariant,
                      letterSpacing: 2.0)),
              Center(
                child: SizedBox(
                  width: 220,
                  height: 220,
                  child: CustomPaint(
                    painter: _GaugePainter(_gaugePercent.toDouble()),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('$_gaugePercent%',
                              style: GoogleFonts.spaceGrotesk(
                                  fontSize: 64,
                                  fontWeight: FontWeight.bold,
                                  color: _onSurface)),
                          Text(
                            _predictResult == null
                                ? 'EN ATTENTE IA'
                                : ((_predictResult?['niveau'] ?? 'RISQUE') as String)
                                    .toString()
                                    .toUpperCase(),
                            style: GoogleFonts.spaceGrotesk(
                                fontSize: 10,
                                color: _onSurfaceVariant,
                                letterSpacing: 1.5),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(color: Colors.white10),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('TYPE DE PANNE',
                          style: GoogleFonts.spaceGrotesk(
                              fontSize: 10,
                              color: _onSurfaceVariant,
                              letterSpacing: 1.5)),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                            color: _error.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4)),
                        child: Text('CRITIQUE',
                            style: GoogleFonts.spaceGrotesk(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: _error)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    (_predictResult?['panne_type'] ?? 'Analyse en cours')
                        .toString(),
                    style: GoogleFonts.inter(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: _error,
                        shadows: [
                          Shadow(
                              color: _error.withOpacity(0.4), blurRadius: 10)
                        ]),
                  ),
                ],
              ),
            ],
          ),
          Positioned(
            bottom: -80,
            right: -80,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                color: _primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
                child: const SizedBox(),
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildChartCard() {
    return Container(
      height: 460,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: _surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('TRAJECTOIRE DE RISQUE',
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _onSurfaceVariant,
                          letterSpacing: 2.0)),
                  const SizedBox(height: 4),
                  Text('Projection calculée par moteur neuronal xV4',
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 11, color: _onSurfaceVariant.withOpacity(0.6))),
                ],
              ),
              Row(
                children: [
                  Container(
                      width: 12, height: 4, decoration: BoxDecoration(color: _secondary, borderRadius: BorderRadius.circular(2))),
                  const SizedBox(width: 8),
                  Text('HISTORIQUE',
                      style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _onSurfaceVariant)),
                  const SizedBox(width: 16),
                  Container(
                      width: 12, height: 4, decoration: BoxDecoration(color: _primary, borderRadius: BorderRadius.circular(2))),
                  const SizedBox(width: 8),
                  Text('IA PRÉDICTION',
                      style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _onSurfaceVariant)),
                ],
              )
            ],
          ),
          const SizedBox(height: 32),
          SizedBox(
            height: 250,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return CustomPaint(
                  size: Size(constraints.maxWidth, constraints.maxHeight),
                  painter: _ChartPainter(),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _chartLabel('T-24H'),
              _chartLabel('T-12H'),
              Text('PRÉSENT (ALERTE)',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 10, fontWeight: FontWeight.bold, color: _primary)),
              _chartLabel('+6H'),
              _chartLabel('+12H (PANNE)'),
            ],
          )
        ],
      ),
    );
  }

  Widget _chartLabel(String text) {
    return Text(text,
        style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _onSurfaceVariant));
  }

  // ══════════════════════ MIDDLE GRID ════════════════════════════
  Widget _buildMiddleGrid(bool isDesktop) {
    if (isDesktop) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 8, child: _buildLocalizationCard()),
          const SizedBox(width: 32),
          Expanded(flex: 4, child: _buildIndicatorsColumn()),
        ],
      );
    }
    return Column(
      children: [
        _buildLocalizationCard(),
        const SizedBox(height: 32),
        _buildIndicatorsColumn(),
      ],
    );
  }

  Widget _buildLocalizationCard() {
    return Container(
      height: 460,
      decoration: BoxDecoration(
        color: _surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Background Image
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.only(top: 40.0),
              child: Opacity(
                opacity: 0.7,
                child: Image.network(
                  'https://lh3.googleusercontent.com/aida-public/AB6AXuDy1pZ1dQ4VoQaAnsCXoRxVlRzMcrTD8Asf8YYN9WuSuswdg7weYEOeeFi6mLExxRZSTTGgwP09MhND8ayU5UOtVN87wNzBp5x_fG6QiafhorI3KIp7_GR4KJpb1zbwL5Ne3rJBfK0CevTcR1kc4IIxw_o1-EzVYjmJw3TbiYrQdwr1x_34pAYd7VygTOZ-Wokv8tglE_jSIzB39b2GpQeVsDe2dWo2M8rTMzcPbd4rSudvrQHp36ZoJ6_zHeviD5hBfT3Dlf1OSd8',
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
          // Top Labels
          Padding(
            padding: const EdgeInsets.all(32),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('LOCALISATION DE LA PANNE',
                        style: GoogleFonts.spaceGrotesk(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: _onSurfaceVariant,
                            letterSpacing: 2.0)),
                    const SizedBox(height: 4),
                    Text('Visualisation topographique 3D du système',
                        style: GoogleFonts.spaceGrotesk(
                            fontSize: 11, color: _onSurfaceVariant.withOpacity(0.6))),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _surfaceContainerHighest.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Text('ASSET: ${widget.machineId}',
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 10, color: _onSurfaceVariant)),
                ),
              ],
            ),
          ),
          // Failure Callout
          Positioned(
            top: 180,
            left: 220, // Simplified positioning
            child: Column(
              children: [
                AnimatedBuilder(
                  animation: _pulseAnim,
                  builder: (_, __) => Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: _primaryLight,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white30, width: 2),
                      boxShadow: [
                        BoxShadow(
                            color: _primary.withOpacity(0.8),
                            blurRadius: 15 * _pulseAnim.value,
                            spreadRadius: 2)
                      ],
                    ),
                  ),
                ),
                Container(
                  width: 2,
                  height: 60,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                        colors: [_primary, Colors.transparent],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  color: _primaryLight,
                  child: Text('PALIER Z-4',
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: _onSurface)),
                )
              ],
            ),
          ),
          // Bottom Alert Bar
          Positioned(
            bottom: 24,
            left: 24,
            right: 24,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _surfaceContainer.withOpacity(0.6),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                            color: _bg, borderRadius: BorderRadius.circular(6)),
                        child: const Icon(Icons.location_on, color: _primary),
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (_predictResult?['notification_message'] ??
                                    'Analyse basée sur la dernière télémétrie disponible.')
                                .toString(),
                            style: GoogleFonts.inter(
                                fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'Machine ${widget.machineId} · modèle ${widget.motorType}',
                            style: GoogleFonts.spaceGrotesk(
                                fontSize: 10, color: _onSurfaceVariant),
                          ),
                        ],
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

  Widget _buildIndicatorsColumn() {
    final conf = _predictResult?['confiance'];
    final confPct = conf is num
        ? (conf * 100).clamp(0, 100).toStringAsFixed(1)
        : (_predictResult?['scenario_confidence'] is num
            ? (((_predictResult!['scenario_confidence']) as num) * 100)
                .clamp(0, 100)
                .toStringAsFixed(1)
            : '--');
    final prob = _predictResult?['prob_panne'];
    final probStr =
        prob is num ? prob.toStringAsFixed(1) : (prob?.toString() ?? '--');
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        _buildIndicatorCard(
          Icons.thermostat,
          'Probabilité panne',
          probStr,
          '%',
          _error,
          ((prob is num ? prob : 0) / 100).clamp(0.0, 1.0),
        ),
        const SizedBox(height: 24),
        _buildIndicatorCard(
          Icons.vibration,
          'Scénario IA',
          _shortScenario(
              (_predictResult?['scenario_label'] ?? '—').toString()),
          '',
          _primary,
          0.65,
        ),
        const SizedBox(height: 24),
        _buildIndicatorCard(
          Icons.verified_user,
          'Confiance modèle',
          confPct,
          '%',
          _secondary,
          ((double.tryParse(confPct) ?? 50) / 100).clamp(0.0, 1.0),
        ),
      ],
    );
  }

  Widget _buildIndicatorCard(IconData icon, String title, String value, String unit, Color color, double progress) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: _secondary),
              Text(title.toUpperCase(),
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 10, color: _onSurfaceVariant, letterSpacing: 1.5)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value,
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 32, fontWeight: FontWeight.bold, color: _onSurface)),
              const SizedBox(width: 8),
              Text(unit,
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 14, color: _onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 4,
              backgroundColor: _surfaceContainerLowest,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════ STRATEGIC RECOMMENDATIONS ══════════════════
  Widget _buildRecommendations() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: _surfaceContainer.withOpacity(0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 800;
          final leftPanel = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                    color: _primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.bolt, color: _primary, size: 16),
                    const SizedBox(width: 8),
                    Text('ACTION RECOMMANDÉE',
                        style: GoogleFonts.spaceGrotesk(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: _primary)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                (_predictResult?['action_recommandee'] ?? 'Surveillance')
                    .toString()
                    .replaceAll('_', ' '),
                style: GoogleFonts.inter(
                    fontSize: 24, fontWeight: FontWeight.bold, color: _onSurface),
              ),
              const SizedBox(height: 16),
              Text(
                _predictResult == null
                    ? 'Lancez « Tester IA Live » ou attendez le chargement automatique.'
                    : [
                        if ((_predictResult?['notification_message'] ?? '')
                            .toString()
                            .trim()
                            .isNotEmpty)
                          _predictResult!['notification_message'].toString(),
                        if (_predictResult?['rul_estime'] != null)
                          'RUL estimée : ${_predictResult!['rul_estime']}',
                      ].join('\n'),
                style: GoogleFonts.inter(
                    fontSize: 14, color: _onSurfaceVariant, height: 1.5),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {},
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
                  backgroundColor: _primaryLight,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: Text('PLANIFIER L\'INTERVENTION',
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF341100),
                        letterSpacing: 1.5)),
              ),
            ],
          );

          final rightPanel = Column(
            children: [
              Row(
                children: [
                  Expanded(
                      child: _recTile(Icons.warning_amber, 'Aviser l\'équipe de nuit',
                          'L\'alerte a été transmise au superviseur de zone.')),
                  const SizedBox(width: 16),
                  Expanded(
                      child: _recTile(Icons.inventory_2, 'Vérification Stock Pièces',
                          '2 paliers de rechange disponibles en stock local.')),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                      child: _recTile(Icons.history_edu, 'Historique Similaire',
                          'Événement similaire sur Node 04 (Mai 2023).')),
                  const SizedBox(width: 16),
                  Expanded(
                      child: _recTile(Icons.engineering, 'Équipe assignée',
                          'Équipe Alpha disponible pour 14:00.')),
                ],
              ),
            ],
          );

          if (isWide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(flex: 1, child: leftPanel),
                const SizedBox(width: 48),
                Expanded(flex: 2, child: rightPanel),
              ],
            );
          }
          return Column(
            children: [
              leftPanel,
              const SizedBox(height: 32),
              rightPanel,
            ],
          );
        },
      ),
    );
  }

  Widget _recTile(IconData icon, String title, String subtitle) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _surfaceContainerHighest.withOpacity(0.4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: _primary),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: GoogleFonts.inter(
                        fontSize: 14, fontWeight: FontWeight.bold, color: _onSurface)),
                const SizedBox(height: 4),
                Text(subtitle,
                    style: GoogleFonts.inter(
                        fontSize: 11, color: _onSurfaceVariant)),
              ],
            ),
          )
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// PAINTERS
// ─────────────────────────────────────────────────────────────────

class _GaugePainter extends CustomPainter {
  final double percentage; // 0 to 100
  _GaugePainter(this.percentage);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    const startAngle = math.pi * 0.75;
    const sweepAngle = math.pi * 1.5;

    // Background track
    final bgPaint = Paint()
      ..color = const Color(0xFF32324E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius), startAngle, sweepAngle, false, bgPaint);

    // Foreground track
    final Shader gradient = const LinearGradient(
      colors: [Color(0xFFFF6E00), Color(0xFFFFB692)],
    ).createShader(Rect.fromCircle(center: center, radius: radius));
    
    final fgPaint = Paint()
      ..shader = gradient
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round;
    
    final fillSweep = sweepAngle * (percentage / 100.0);
    canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius), startAngle, fillSweep, false, fgPaint);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) =>
      oldDelegate.percentage != percentage;
}

class _ChartPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Draw horizontal grid lines
    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.05)
      ..strokeWidth = 1;

    for (int i = 0; i <= 4; i++) {
      final y = size.height * (i / 4.0);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final hPath = Path();
    hPath.moveTo(0, size.height * 0.875);
    hPath.quadraticBezierTo(size.width * 0.1, size.height * 0.85, size.width * 0.2, size.height * 0.75);
    hPath.quadraticBezierTo(size.width * 0.4, size.height * 0.7, size.width * 0.6, size.height * 0.55);

    final pPath = Path();
    pPath.moveTo(size.width * 0.6, size.height * 0.55);
    pPath.quadraticBezierTo(size.width * 0.7, size.height * 0.45, size.width * 0.8, size.height * 0.2);
    pPath.quadraticBezierTo(size.width * 1.0, size.height * 0.05, size.width, size.height * 0.1); // Slightly curving back like in the image

    // History curve
    final hPaint = Paint()
      ..color = const Color(0xFF75D1FF)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3;
    canvas.drawPath(hPath, hPaint);

    // Predictive curve (Dashed effect simulated by overlapping paths or use package, manually we use PathMetrics if needed, 
    // but just a solid different color works fine for a mockup or simple path if dashed is complex.
    // We'll use simple Solid path for now)
    final pPaint = Paint()
      ..color = const Color(0xFFFF6E00)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 4;
    
    // Simple custom dash
    _drawDashedLine(canvas, pPath, pPaint);

    // Fill under predictive
    final fillPath = Path.from(pPath);
    fillPath.lineTo(size.width, size.height);
    fillPath.lineTo(size.width * 0.6, size.height);
    fillPath.close();

    final fillPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x33FF6E00), Colors.transparent],
      ).createShader(Rect.fromLTWH(size.width*0.6, 0, size.width*0.4, size.height));
    canvas.drawPath(fillPath, fillPaint);

    // Dot at current
    final dotPaint = Paint()..color = const Color(0xFFFF6E00);
    canvas.drawCircle(Offset(size.width * 0.6, size.height * 0.55), 6, dotPaint);
    canvas.drawCircle(Offset(size.width * 0.6, size.height * 0.55), 16, 
        Paint()..color = const Color(0xFFFF6E00).withOpacity(0.2));
  }

  void _drawDashedLine(Canvas canvas, Path path, Paint paint) {
    const dashWidth = 8.0;
    const dashSpace = 4.0;
    var distance = 0.0;
    for (var pathMetric in path.computeMetrics()) {
      while (distance < pathMetric.length) {
        final drawLength = math.min(dashWidth, pathMetric.length - distance);
        final extractPath = pathMetric.extractPath(distance, distance + drawLength);
        canvas.drawPath(extractPath, paint);
        distance += dashWidth + dashSpace;
      }
      distance = 0.0;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Plein écran : vue **État de machine** + panneau chatbot ([AiAnalysisView]), alignée sur le dashboard client.
class MaintenanceAiAnalysisMachineScreen extends StatelessWidget {
  const MaintenanceAiAnalysisMachineScreen({
    super.key,
    required this.machineId,
    required this.machineName,
    this.motorType = 'EL_M',
    this.viewerRole = 'maintenance',
  });

  final String machineId;
  final String machineName;
  final String motorType;
  final String viewerRole;

  static const _bg = Color(0xFF10102B);
  static const _text = Color(0xFFE2DFFF);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: _text,
        title: Text(
          'Analyse IA',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: AiAnalysisView(
            machineId: machineId,
            machineName: machineName,
            motorType: motorType,
            viewerRole: viewerRole,
          ),
        ),
      ),
    );
  }
}
