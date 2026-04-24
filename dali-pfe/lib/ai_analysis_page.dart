import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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
  bool _predictLoading = false;
  String? _predictError;
  Map<String, dynamic>? _predictResult;

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.machineId.isNotEmpty) _runLivePrediction();
    });
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 992;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPageHeader(),
        const SizedBox(height: 16),
        _buildLiveIaCard(),
        const SizedBox(height: 32),
        // Top Grid: Gauge + Chart
        _buildTopGrid(isDesktop),
        const SizedBox(height: 32),
        // Middle Grid: 3D Visualization + Indicators
        _buildMiddleGrid(isDesktop),
        const SizedBox(height: 32),
        // Bottom: Recommendations
        _buildRecommendations(),
        const SizedBox(height: 48),
      ],
    );
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

      double temp = 62;
      double pressure = 0.03;
      double power = 62000;
      double vibration = 1.2;
      int presence = 1;
      double magnetic = 0.55;
      double infrared = 62;
      int rpm = 1750;
      int torque = 45;
      int toolWear = 80;

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
          Expanded(flex: 4, child: _buildGaugeCard()),
          const SizedBox(width: 32),
          Expanded(flex: 8, child: _buildChartCard()),
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
