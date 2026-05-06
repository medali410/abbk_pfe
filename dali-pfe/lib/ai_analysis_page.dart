import 'dart:ui';
import 'dart:math' as math;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:video_player/video_player.dart';
import 'services/api_service.dart';

class AiAnalysisView extends StatefulWidget {
  final String machineId;
  final String machineName;
  final String motorType;

  const AiAnalysisView({
    super.key,
    required this.machineId,
    required this.machineName,
    this.motorType = 'EL_M',
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
  double _diagPressure = 0;
  double _diagHumidity = 0;

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
        _runLivePrediction();
        _loadTelemetryHistory();
      }
    });
    _liveRefreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || widget.machineId.isEmpty || _predictLoading) return;
      _runLivePrediction();
    });
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
    _liveRefreshTimer?.cancel();
    _temperatureVideoController?.dispose();
    _pulseCtrl.dispose();
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 1024;
          if (!isWide) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildMainDashboardArea(),
                const SizedBox(height: 12),
                _diagRightPanel(),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 62, child: _buildMainDashboardArea()),
              const SizedBox(width: 12),
              Expanded(flex: 38, child: _diagRightPanel()),
            ],
          );
        },
      ),
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
                'PRESSION',
                '${_diagPressure.toStringAsFixed(1)} bar',
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
    final p = _gaugePercent;
    if (p >= 70) return 'CRITIQUE';
    if (p >= 40) return 'SURVEILLANCE';
    return 'STABLE';
  }

  Color get _machineStatusColor {
    final p = _gaugePercent;
    if (p >= 70) return _error;
    if (p >= 40) return _primary;
    return _green;
  }

  Widget _buildIaDashboardCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Wrap(
        runSpacing: 10,
        spacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _chipInfo('MACHINE', widget.machineName.toUpperCase(), _secondary),
          _chipInfo('ID', widget.machineId, _onSurfaceVariant),
          _chipInfo('ÉTAT', _machineStatus, _machineStatusColor),
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
      double pressure = 0;
      double power = 0;
      double vibration = 0;
      int presence = 0;
      double magnetic = 0;
      double infrared = 0;
      int rpm = 0;
      int torque = 0;
      int toolWear = 0;

      final diagTemp = (latest?['temperature'] as num?)?.toDouble() ??
          (metrics?['thermal'] as num?)?.toDouble() ??
          0;
      final diagPressure = (latest?['pressure'] as num?)?.toDouble() ??
          (metrics?['pressure'] as num?)?.toDouble() ??
          0;
      final diagHumidity = (latest?['humidity'] as num?)?.toDouble() ??
          (metrics?['humidity'] as num?)?.toDouble() ??
          0;

      if (latest != null) {
        temp = (latest['temperature'] as num?)?.toDouble() ??
            (metrics?['thermal'] as num?)?.toDouble() ??
            temp;
        vibration = (latest['vibration'] as num?)?.toDouble() ??
            (metrics?['vibration'] as num?)?.toDouble() ??
            vibration;
        power = (latest['powerConsumption'] as num?)?.toDouble() ??
            (metrics?['power'] as num?)?.toDouble() ??
            power;
        pressure = (metrics?['pressure'] as num?)?.toDouble() ?? pressure;
        magnetic = (metrics?['magnetic'] as num?)?.toDouble() ?? magnetic;
        infrared = (metrics?['infrared'] as num?)?.toDouble() ?? infrared;
        presence = (metrics?['presence'] as num?)?.round() ?? presence;
      }

      final result = await ApiService.predictMachine(
        {
          'type_moteur': widget.motorType.toUpperCase(),
          'temperature': temp,
          'pressure': pressure,
          'power': power,
          'vibration': vibration,
          'presence': presence,
          'magnetic': magnetic,
          'infrared': infrared,
          'rpm': rpm,
          'torque': torque,
          'tool_wear': toolWear,
        },
        machineId: widget.machineId,
      );
      if (!mounted) return;
      setState(() {
        _predictResult = result;
        _diagTemperature = diagTemp;
        _diagPressure = diagPressure;
        _diagHumidity = diagHumidity;
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
