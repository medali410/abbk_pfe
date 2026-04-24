import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../utils/panne_display.dart';

/// Tableau d’analyse moteur (courbes + KPI) à partir de l’historique API / Mongo.
class MotorAnalyticsPanel extends StatefulWidget {
  const MotorAnalyticsPanel({
    super.key,
    required this.machineId,
    required this.machineLabel,
    required this.history,
    required this.latest,
    required this.loading,
    required this.onRefresh,
    required this.healthPct,
    required this.probPanne,
    this.panneType,
    this.scenarioLabel,
    this.scenarioExplanation,
  });

  final String? machineId;
  final String machineLabel;
  final List<Map<String, dynamic>> history;
  final Map<String, dynamic>? latest;
  final bool loading;
  final VoidCallback onRefresh;
  final int healthPct;
  final int probPanne;
  final String? panneType;
  final String? scenarioLabel;
  final String? scenarioExplanation;

  @override
  State<MotorAnalyticsPanel> createState() => _MotorAnalyticsPanelState();
}

class _MotorAnalyticsPanelState extends State<MotorAnalyticsPanel> with TickerProviderStateMixin {
  late TabController _tab;
  late AnimationController _pulseCtrl;
  double _tempWarn = 65;
  double _tempCrit = 80;
  double _pressureWarn = 4.8;
  double _pressureCrit = 5.8;
  double _vibrationWarn = 4.0;
  double _vibrationCrit = 8.0;
  double _powerWarn = 4200;
  double _powerCrit = 6000;

  static const _surfaceLow = Color(0xFF191934);
  static const _surfaceLowest = Color(0xFF0B0B26);
  static const _onSurface = Color(0xFFE2DFFF);
  static const _onVariant = Color(0xFFE2BFB0);
  static const _primaryContainer = Color(0xFFFF6E00);
  static const _secondary = Color(0xFF75D1FF);
  static const _tertiary = Color(0xFFEFB1F9);
  static const _outlineVariant = Color(0xFF594136);
  static const _green = Color(0xFF66BB6A);
  static const _warn = Color(0xFFFFC15E);
  static const _danger = Color(0xFFFF7B7B);

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _tab.dispose();
    super.dispose();
  }

  static double? _num(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().trim().replaceAll(',', '.'));
  }

  static Map<String, dynamic>? _metrics(Map<String, dynamic> p) {
    final m = p['metrics'];
    if (m is Map<String, dynamic>) return m;
    if (m is Map) return Map<String, dynamic>.from(m);
    return null;
  }

  static double? _thermal(Map<String, dynamic> p) {
    final m = _metrics(p);
    return _num(m?['thermal']) ?? _num(p['temperature']);
  }

  static double? _pressure(Map<String, dynamic> p) {
    final m = _metrics(p);
    return _num(m?['pressure']) ?? _num(p['pressure']);
  }

  static double? _vibration(Map<String, dynamic> p) {
    final m = _metrics(p);
    return _num(m?['vibration']) ?? _num(p['vibration']);
  }

  static double? _powerMap(Map<String, dynamic> p) {
    final m = _metrics(p);
    return _num(m?['power']) ?? _num(p['power']);
  }

  static double? _magneticMap(Map<String, dynamic> p) {
    final m = _metrics(p);
    return _num(m?['magnetic']) ?? _num(p['magnetic']);
  }

  static double? _infraredMap(Map<String, dynamic> p) {
    final m = _metrics(p);
    return _num(m?['infrared']) ?? _num(p['infrared']);
  }

  static double? _ultrasonicMap(Map<String, dynamic> p) {
    final m = _metrics(p);
    return _num(m?['ultrasonic']) ?? _num(p['ultrasonic']);
  }

  PanneUiHints _panneHints(List<Map<String, dynamic>> series) {
    final snap = widget.latest ?? (series.isNotEmpty ? series.last : null);
    if (snap == null) return PanneUiHints.empty;
    return computePanneUiHints(
      probPanne: widget.probPanne,
      panneType: widget.panneType ?? '',
      scenarioLabel: widget.scenarioLabel ?? '',
      scenarioExplanation: widget.scenarioExplanation ?? '',
      thermal: _thermal(snap) ?? 0,
      pressure: _pressure(snap) ?? 0,
      vibration: _vibration(snap) ?? 0,
      power: _powerMap(snap) ?? 0,
      magnetic: _magneticMap(snap) ?? 0,
      infrared: _infraredMap(snap) ?? 0,
      ultrasonic: _ultrasonicMap(snap) ?? 0,
    );
  }

  dynamic _pointValue(Map<String, dynamic> p, String key) {
    final m = _metrics(p);
    return m?[key] ?? p[key];
  }

  dynamic _latestValue(String key) {
    final p = widget.latest;
    if (p == null) return null;
    final m = _metrics(p);
    return m?[key] ?? p[key];
  }

  String _fmtNum(dynamic v, {int decimals = 2}) {
    final n = _num(v);
    if (n == null) return '—';
    return n.toStringAsFixed(decimals);
  }

  List<Map<String, dynamic>> get _chrono {
    final h = List<Map<String, dynamic>>.from(widget.history);
    h.sort((a, b) {
      final ta = DateTime.tryParse((a['createdAt'] ?? '').toString()) ?? DateTime.fromMillisecondsSinceEpoch(0);
      final tb = DateTime.tryParse((b['createdAt'] ?? '').toString()) ?? DateTime.fromMillisecondsSinceEpoch(0);
      return ta.compareTo(tb);
    });
    return h;
  }

  @override
  Widget build(BuildContext context) {
    final mid = (widget.machineId ?? '').trim();
    if (mid.isEmpty) {
      return _emptyCard(
        icon: Icons.precision_manufacturing_outlined,
        title: 'Aucune machine sélectionnée',
        subtitle: 'Choisissez une machine dans l’onglet « Machine », puis revenez ici pour charger l’historique.',
      );
    }

    final series = _chrono;
    if (widget.loading && series.isEmpty) {
      return const Center(child: Padding(padding: EdgeInsets.all(48), child: CircularProgressIndicator(color: _primaryContainer)));
    }
    if (series.isEmpty) {
      return _emptyCard(
        icon: Icons.show_chart,
        title: 'Pas encore de télémétrie',
        subtitle: 'Dès que l’ESP32 / MQTT enverra des points pour « $mid », les courbes et statistiques apparaîtront ici.',
        action: FilledButton.icon(
          onPressed: widget.onRefresh,
          icon: const Icon(Icons.refresh),
          label: const Text('Actualiser'),
          style: FilledButton.styleFrom(backgroundColor: _primaryContainer, foregroundColor: const Color(0xFF582100)),
        ),
      );
    }

    final thermal = series.map(_thermal).whereType<double>().toList();
    final pressure = series.map(_pressure).whereType<double>().toList();
    final vibration = series.map(_vibration).whereType<double>().toList();
    final hints = _panneHints(series);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(mid, hints),
        const SizedBox(height: 16),
        _thresholdConfigCard(),
        const SizedBox(height: 12),
        _priorityBanner(),
        const SizedBox(height: 12),
        _kpiRow(thermal, pressure, vibration, hints),
        const SizedBox(height: 12),
        _sensorAnalysisList(hints),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: _surfaceLow,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _outlineVariant.withValues(alpha: 0.14)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TabBar(
                controller: _tab,
                indicatorColor: _primaryContainer,
                labelColor: _primaryContainer,
                unselectedLabelColor: _onVariant.withValues(alpha: 0.65),
                labelStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700),
                tabs: [
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (hints.highlightMetrics.contains('thermal'))
                          const Padding(
                            padding: EdgeInsets.only(right: 4),
                            child: Icon(Icons.warning_rounded, size: 16, color: _danger),
                          ),
                        const Text('Température'),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (hints.highlightMetrics.contains('pressure'))
                          const Padding(
                            padding: EdgeInsets.only(right: 4),
                            child: Icon(Icons.warning_rounded, size: 16, color: _danger),
                          ),
                        const Text('Pression'),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (hints.highlightMetrics.contains('vibration'))
                          const Padding(
                            padding: EdgeInsets.only(right: 4),
                            child: Icon(Icons.warning_rounded, size: 16, color: _danger),
                          ),
                        const Text('Vibration'),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(
                height: 260,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 12, 16, 12),
                  child: TabBarView(
                    controller: _tab,
                    children: [
                      _lineChart(thermal, _primaryContainer, '°C'),
                      _lineChart(pressure, _secondary, 'bar'),
                      _lineChart(vibration, _tertiary, 'mm/s'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        if (widget.latest != null) ...[
          const SizedBox(height: 16),
          _latestPayloadCard(),
        ],
        const SizedBox(height: 12),
        _recentFramesCard(),
        const SizedBox(height: 12),
        Text(
          '${series.length} échantillons — ordre chronologique (gauche → droite).',
          style: GoogleFonts.inter(fontSize: 11, color: _onVariant.withValues(alpha: 0.8)),
        ),
      ],
    );
  }

  Widget _header(String mid, PanneUiHints hints) {
    final riskColor = widget.probPanne >= 70
        ? _danger
        : (widget.probPanne >= 40 ? _warn : _onVariant);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ANALYSE MOTEUR', style: GoogleFonts.spaceGrotesk(fontSize: 10, letterSpacing: 2, color: _onVariant)),
              const SizedBox(height: 4),
              Text(widget.machineLabel, style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: _onSurface)),
              Text(mid, style: GoogleFonts.spaceGrotesk(fontSize: 11, color: _secondary)),
              if (widget.latest != null) ...[
                const SizedBox(height: 6),
                Text(
                  'Dernier point : temp. ${_thermal(widget.latest!)?.toStringAsFixed(1) ?? '—'} °C · press. ${_pressure(widget.latest!)?.toStringAsFixed(2) ?? '—'} bar',
                  style: GoogleFonts.inter(fontSize: 11, color: _onVariant.withValues(alpha: 0.9)),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          flex: 2,
          child: AnimatedBuilder(
            animation: _pulseCtrl,
            builder: (context, _) {
              return Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  color: _surfaceLowest,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: hints.hasStress
                        ? _danger.withValues(alpha: 0.5 + 0.45 * _pulseCtrl.value)
                        : _outlineVariant.withValues(alpha: 0.2),
                    width: hints.hasStress ? 2.5 : 1,
                  ),
                  boxShadow: hints.hasStress
                      ? [
                          BoxShadow(
                            color: _danger.withValues(alpha: 0.22 * _pulseCtrl.value),
                            blurRadius: 10,
                            spreadRadius: 0,
                          ),
                        ]
                      : null,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('RISQUE PANNE', style: GoogleFonts.spaceGrotesk(fontSize: 8, letterSpacing: 1.5, color: _onVariant)),
                    Text('${widget.probPanne}%', style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w900, color: riskColor)),
                    if (hints.typeLine.isNotEmpty)
                      Text(
                        hints.typeLine,
                        style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: _onSurface),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (hints.summaryLine.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        hints.summaryLine,
                        style: GoogleFonts.inter(fontSize: 9.5, height: 1.25, color: hints.hasStress ? _danger.withValues(alpha: 0.95) : _onVariant),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('Santé estimée', style: GoogleFonts.spaceGrotesk(fontSize: 8, color: _onVariant)),
            Text('${widget.healthPct}%', style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w900, color: _green)),
          ],
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          onPressed: widget.loading ? null : widget.onRefresh,
          icon: widget.loading
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: _primaryContainer))
              : const Icon(Icons.refresh),
          style: IconButton.styleFrom(backgroundColor: _surfaceLowest),
        ),
      ],
    );
  }

  Widget _kpiRow(List<double> thermal, List<double> pressure, List<double> vibration, PanneUiHints hints) {
    String fmt(List<double> xs, String u, [int d = 1]) {
      if (xs.isEmpty) return '—';
      final a = xs.reduce((x, y) => x + y) / xs.length;
      return '${a.toStringAsFixed(d)} $u';
    }

    String fmtMax(List<double> xs, String u, [int d = 2]) {
      if (xs.isEmpty) return '—';
      final m = xs.reduce((x, y) => x > y ? x : y);
      return '${m.toStringAsFixed(d)} $u';
    }

    return AnimatedBuilder(
      animation: _pulseCtrl,
      builder: (context, _) {
        return LayoutBuilder(
          builder: (context, c) {
            final narrow = c.maxWidth < 520;
            final children = [
              _kpiTile('Moy. temp.', fmt(thermal, '°C'), Icons.thermostat, hints.highlightMetrics.contains('thermal')),
              _kpiTile('Moy. press.', fmt(pressure, 'bar', 2), Icons.compress, hints.highlightMetrics.contains('pressure')),
              _kpiTile('Pic vibration', fmtMax(vibration, 'mm/s'), Icons.vibration, hints.highlightMetrics.contains('vibration')),
            ];
            if (narrow) {
              return Column(children: [for (final w in children) Padding(padding: const EdgeInsets.only(bottom: 8), child: w)]);
            }
            return Row(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) const SizedBox(width: 10),
                  Expanded(child: children[i]),
                ],
              ],
            );
          },
        );
      },
    );
  }

  Widget _kpiTile(String title, String value, IconData icon, bool stress) {
    final borderColor = stress ? _danger.withValues(alpha: 0.55 + 0.4 * _pulseCtrl.value) : _outlineVariant.withValues(alpha: 0.12);
    final bg = stress ? _danger.withValues(alpha: 0.08 + 0.1 * _pulseCtrl.value) : _surfaceLow;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor, width: stress ? 2 : 1),
        boxShadow: stress
            ? [
                BoxShadow(color: _danger.withValues(alpha: 0.18 * _pulseCtrl.value), blurRadius: 8),
              ]
            : null,
      ),
      child: Row(
        children: [
          Icon(icon, color: stress ? _danger : _primaryContainer.withValues(alpha: 0.9), size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title.toUpperCase(), style: GoogleFonts.spaceGrotesk(fontSize: 8, letterSpacing: 1, color: _onVariant)),
                Text(
                  value,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: stress ? _danger : _onSurface,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  ({String label, Color color, IconData icon}) _sensorState(String key, double? value) {
    if (value == null || !value.isFinite) {
      return (label: 'NO DATA', color: _onVariant, icon: Icons.help_outline);
    }
    switch (key) {
      case 'temperature':
        if (value >= _tempCrit) return (label: 'CRITIQUE', color: _danger, icon: Icons.local_fire_department);
        if (value >= _tempWarn) return (label: 'DÉGRADÉ', color: _warn, icon: Icons.warning_amber_rounded);
        return (label: 'NORMAL', color: _green, icon: Icons.check_circle_outline);
      case 'pressure':
        if (value >= _pressureCrit || value < 1.0) return (label: 'CRITIQUE', color: _danger, icon: Icons.error_outline);
        if (value >= _pressureWarn || value < 1.5) return (label: 'DÉGRADÉ', color: _warn, icon: Icons.warning_amber_rounded);
        return (label: 'NORMAL', color: _green, icon: Icons.check_circle_outline);
      case 'vibration':
        if (value >= _vibrationCrit) return (label: 'CRITIQUE', color: _danger, icon: Icons.error_outline);
        if (value >= _vibrationWarn) return (label: 'DÉGRADÉ', color: _warn, icon: Icons.warning_amber_rounded);
        return (label: 'NORMAL', color: _green, icon: Icons.check_circle_outline);
      case 'power':
        if (value >= _powerCrit) return (label: 'CRITIQUE', color: _danger, icon: Icons.bolt);
        if (value >= _powerWarn) return (label: 'DÉGRADÉ', color: _warn, icon: Icons.bolt);
        return (label: 'NORMAL', color: _green, icon: Icons.check_circle_outline);
      case 'current':
        if (value >= 28) return (label: 'CRITIQUE', color: _danger, icon: Icons.error_outline);
        if (value >= 20) return (label: 'DÉGRADÉ', color: _warn, icon: Icons.warning_amber_rounded);
        return (label: 'NORMAL', color: _green, icon: Icons.check_circle_outline);
      case 'ultrasonic':
        if (value <= 5) return (label: 'CRITIQUE', color: _danger, icon: Icons.error_outline);
        if (value <= 15) return (label: 'DÉGRADÉ', color: _warn, icon: Icons.warning_amber_rounded);
        return (label: 'NORMAL', color: _green, icon: Icons.check_circle_outline);
      case 'infrared':
        if (value >= 3500) return (label: 'CRITIQUE', color: _danger, icon: Icons.error_outline);
        if (value >= 2200) return (label: 'DÉGRADÉ', color: _warn, icon: Icons.warning_amber_rounded);
        return (label: 'NORMAL', color: _green, icon: Icons.check_circle_outline);
      default:
        return (label: 'INFO', color: _secondary, icon: Icons.tune);
    }
  }

  Widget _thresholdConfigCard() {
    Widget sliderRow({
      required String label,
      required String unit,
      required double warn,
      required double crit,
      required double min,
      required double max,
      required void Function(double warn, double crit) onChanged,
    }) {
      final safeWarn = warn.clamp(min, max);
      final safeCrit = crit.clamp(min, max);
      return Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        decoration: BoxDecoration(
          color: _surfaceLowest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _outlineVariant.withValues(alpha: 0.14)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$label  |  Warn: ${safeWarn.toStringAsFixed(1)} $unit · Crit: ${safeCrit.toStringAsFixed(1)} $unit',
              style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w600, color: _onSurface),
            ),
            const SizedBox(height: 6),
            Text('Seuil dégradé', style: GoogleFonts.inter(fontSize: 10, color: _onVariant)),
            Slider(
              value: safeWarn,
              min: min,
              max: max,
              divisions: 100,
              activeColor: _warn,
              label: safeWarn.toStringAsFixed(1),
              onChanged: (v) => onChanged(v, v >= safeCrit ? v + ((max - min) * 0.02) : safeCrit),
            ),
            Text('Seuil critique', style: GoogleFonts.inter(fontSize: 10, color: _onVariant)),
            Slider(
              value: safeCrit,
              min: min,
              max: max,
              divisions: 100,
              activeColor: _danger,
              label: safeCrit.toStringAsFixed(1),
              onChanged: (v) => onChanged(v <= safeWarn ? safeWarn + ((max - min) * 0.02) : safeWarn, v),
            ),
          ],
        ),
      );
    }

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: Container(
        decoration: BoxDecoration(
          color: _surfaceLow,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _outlineVariant.withValues(alpha: 0.18)),
        ),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          iconColor: _secondary,
          collapsedIconColor: _secondary,
          title: Text('SEUILS CONFIGURABLES CAPTEURS', style: GoogleFonts.spaceGrotesk(fontSize: 10, letterSpacing: 1.2, color: _secondary)),
          subtitle: Text('Ajustez les seuils d’alerte sans modifier le code.', style: GoogleFonts.inter(fontSize: 11, color: _onVariant)),
          children: [
            sliderRow(
              label: 'Température',
              unit: '°C',
              warn: _tempWarn,
              crit: _tempCrit,
              min: 30,
              max: 120,
              onChanged: (w, c) => setState(() {
                _tempWarn = w.clamp(30, 120);
                _tempCrit = c.clamp(_tempWarn + 0.5, 120);
              }),
            ),
            const SizedBox(height: 8),
            sliderRow(
              label: 'Pression',
              unit: 'bar',
              warn: _pressureWarn,
              crit: _pressureCrit,
              min: 1,
              max: 10,
              onChanged: (w, c) => setState(() {
                _pressureWarn = w.clamp(1, 10);
                _pressureCrit = c.clamp(_pressureWarn + 0.1, 10);
              }),
            ),
            const SizedBox(height: 8),
            sliderRow(
              label: 'Vibration',
              unit: 'mm/s',
              warn: _vibrationWarn,
              crit: _vibrationCrit,
              min: 0.5,
              max: 15,
              onChanged: (w, c) => setState(() {
                _vibrationWarn = w.clamp(0.5, 15);
                _vibrationCrit = c.clamp(_vibrationWarn + 0.1, 15);
              }),
            ),
            const SizedBox(height: 8),
            sliderRow(
              label: 'Power',
              unit: 'W',
              warn: _powerWarn,
              crit: _powerCrit,
              min: 500,
              max: 10000,
              onChanged: (w, c) => setState(() {
                _powerWarn = w.clamp(500, 10000);
                _powerCrit = c.clamp(_powerWarn + 50, 10000);
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _priorityBanner() {
    final temp = _num(_latestValue('thermal')) ?? _num(_latestValue('temperature'));
    final pressure = _num(_latestValue('pressure'));
    final vib = _num(_latestValue('vibration'));
    final power = _num(_latestValue('power'));

    final states = [
      _sensorState('temperature', temp),
      _sensorState('pressure', pressure),
      _sensorState('vibration', vib),
      _sensorState('power', power),
    ];
    var worst = states.first;
    for (final s in states.skip(1)) {
      final rank = s.label == 'CRITIQUE' ? 3 : s.label == 'DÉGRADÉ' ? 2 : 1;
      final current = worst.label == 'CRITIQUE' ? 3 : worst.label == 'DÉGRADÉ' ? 2 : 1;
      if (rank > current) worst = s;
    }

    final message = switch (worst.label) {
      'CRITIQUE' => 'Priorité haute: intervention immédiate recommandée.',
      'DÉGRADÉ' => 'Anomalie détectée: planifier une inspection rapide.',
      _ => 'Tous les capteurs critiques sont dans une plage normale.',
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _surfaceLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: worst.color.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Icon(worst.icon, size: 20, color: worst.color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.inter(fontSize: 12.5, color: _onSurface, fontWeight: FontWeight.w600),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: worst.color.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(99)),
            child: Text(worst.label, style: GoogleFonts.spaceGrotesk(fontSize: 9, letterSpacing: 1, color: worst.color, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _sensorAnalysisList(PanneUiHints hints) {
    Widget card({
      String metricId = '',
      required String name,
      required IconData icon,
      required String value,
      required String unit,
      required ({String label, Color color, IconData icon}) state,
      required String analysis,
    }) {
      final stress = metricId.isNotEmpty && hints.highlightMetrics.contains(metricId);
      return AnimatedBuilder(
        animation: _pulseCtrl,
        builder: (context, _) {
          return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: stress ? _danger.withValues(alpha: 0.06 + 0.08 * _pulseCtrl.value) : _surfaceLow,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: stress ? _danger.withValues(alpha: 0.55 + 0.4 * _pulseCtrl.value) : state.color.withValues(alpha: 0.32),
            width: stress ? 2.2 : 1,
          ),
          boxShadow: stress
              ? [BoxShadow(color: _danger.withValues(alpha: 0.2 * _pulseCtrl.value), blurRadius: 10)]
              : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: _onVariant, size: 18),
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
                          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: _onSurface),
                        ),
                      ),
                      Text(
                        '$value $unit'.trim(),
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: stress ? _danger : _onSurface,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(state.icon, size: 14, color: state.color),
                          const SizedBox(width: 4),
                          Text(
                            state.label,
                            style: GoogleFonts.spaceGrotesk(fontSize: 9, letterSpacing: 1, color: state.color, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                      Text(
                        analysis,
                        style: GoogleFonts.inter(fontSize: 11.5, color: _onVariant.withValues(alpha: 0.95)),
                      ),
                    ],
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

    final temp = _num(_latestValue('thermal')) ?? _num(_latestValue('temperature'));
    final pressure = _num(_latestValue('pressure'));
    final vibration = _num(_latestValue('vibration'));
    final power = _num(_latestValue('power'));
    final current = _num(_latestValue('current'));
    final ultra = _num(_latestValue('ultrasonic'));
    final infrared = _num(_latestValue('infrared'));
    final presence = _num(_latestValue('presence')) ?? 0;
    final magnetic = _num(_latestValue('magnetic')) ?? 0;

    String sensorAnalysis(String key, double? v, String status) {
      if (v == null || !v.isFinite) return 'Aucune donnée récente pour ce capteur.';
      if (status == 'CRITIQUE') return 'Seuil critique dépassé, intervention immédiate recommandée.';
      if (status == 'DÉGRADÉ') return 'Variation anormale détectée, planifier un contrôle rapide.';
      switch (key) {
        case 'temperature':
          return 'Thermique stable, fonctionnement nominal.';
        case 'pressure':
          return 'Pression dans la plage attendue.';
        case 'vibration':
          return 'Niveau vibratoire acceptable.';
        case 'power':
          return 'Consommation électrique cohérente.';
        case 'current':
          return 'Courant mesuré sans surcharge notable.';
        case 'ultrasonic':
          return 'Distance/écho cohérent avec l’environnement.';
        default:
          return 'Capteur en état normal.';
      }
    }

    final stTemp = _sensorState('temperature', temp);
    final stPressure = _sensorState('pressure', pressure);
    final stVibration = _sensorState('vibration', vibration);
    final stPower = _sensorState('power', power);
    final stCurrent = _sensorState('current', current);
    final stUltra = _sensorState('ultrasonic', ultra);
    final stInfra = _sensorState('infrared', infrared);
    final stPresence = presence >= 1 ? (label: 'ACTIF', color: _warn, icon: Icons.directions_run) : (label: 'CALME', color: _green, icon: Icons.check_circle_outline);
    final stMagnetic = magnetic >= 1 ? (label: 'DÉTECTÉ', color: _warn, icon: Icons.warning_amber_rounded) : (label: 'NORMAL', color: _green, icon: Icons.check_circle_outline);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _surfaceLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _outlineVariant.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ANALYSE UNIQUE PAR CAPTEUR', style: GoogleFonts.spaceGrotesk(fontSize: 9, letterSpacing: 1.3, color: _secondary)),
          const SizedBox(height: 10),
          card(metricId: 'thermal', name: 'Température', icon: Icons.thermostat, value: _fmtNum(temp, decimals: 1), unit: '°C', state: stTemp, analysis: sensorAnalysis('temperature', temp, stTemp.label)),
          card(metricId: 'pressure', name: 'Pression', icon: Icons.compress, value: _fmtNum(pressure, decimals: 2), unit: 'bar', state: stPressure, analysis: sensorAnalysis('pressure', pressure, stPressure.label)),
          card(metricId: 'vibration', name: 'Vibration', icon: Icons.vibration, value: _fmtNum(vibration, decimals: 2), unit: 'mm/s', state: stVibration, analysis: sensorAnalysis('vibration', vibration, stVibration.label)),
          card(metricId: 'power', name: 'Power', icon: Icons.bolt, value: _fmtNum(power, decimals: 1), unit: 'W', state: stPower, analysis: sensorAnalysis('power', power, stPower.label)),
          card(name: 'Current', icon: Icons.electric_meter, value: _fmtNum(current, decimals: 2), unit: 'A', state: stCurrent, analysis: sensorAnalysis('current', current, stCurrent.label)),
          card(metricId: 'ultrasonic', name: 'Ultrasonic', icon: Icons.waves, value: _fmtNum(ultra, decimals: 1), unit: 'cm', state: stUltra, analysis: sensorAnalysis('ultrasonic', ultra, stUltra.label)),
          card(name: 'Présence', icon: Icons.accessibility_new, value: presence.toStringAsFixed(0), unit: '', state: stPresence, analysis: presence >= 1 ? 'Présence détectée autour de la machine.' : 'Aucun mouvement détecté autour de la machine.'),
          card(metricId: 'magnetic', name: 'Magnétique', icon: Icons.sensors, value: magnetic.toStringAsFixed(0), unit: '', state: stMagnetic, analysis: magnetic >= 1 ? 'Variation magnétique détectée.' : 'Capteur magnétique stable.'),
          card(metricId: 'infrared', name: 'Infrarouge', icon: Icons.visibility, value: _fmtNum(infrared, decimals: 1), unit: '', state: stInfra, analysis: sensorAnalysis('infrared', infrared, stInfra.label)),
        ],
      ),
    );
  }

  Widget _latestPayloadCard() {
    Widget item(String label, String value) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: _surfaceLowest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _outlineVariant.withValues(alpha: 0.16)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label.toUpperCase(), style: GoogleFonts.spaceGrotesk(fontSize: 8, letterSpacing: 1, color: _onVariant)),
            const SizedBox(height: 2),
            Text(value, style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700, color: _onSurface)),
          ],
        ),
      );
    }

    final createdAt = (widget.latest?['createdAt'] ?? widget.latest?['updatedAt'] ?? '').toString();
    final temperature = _fmtNum(_latestValue('thermal'), decimals: 1) == '—'
        ? _fmtNum(_latestValue('temperature'), decimals: 1)
        : _fmtNum(_latestValue('thermal'), decimals: 1);
    final lat = _fmtNum(_latestValue('lat'), decimals: 6);
    final lng = _fmtNum(_latestValue('lng'), decimals: 6);
    final pressure = _fmtNum(_latestValue('pressure'));
    final power = _fmtNum(_latestValue('power'));
    final current = _fmtNum(_latestValue('current'));
    final ultrasonic = _fmtNum(_latestValue('ultrasonic'));
    final presence = (_latestValue('presence') ?? '—').toString();
    final magnetic = (_latestValue('magnetic') ?? '—').toString();
    final infrared = _fmtNum(_latestValue('infrared'));

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _surfaceLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _outlineVariant.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('DERNIÈRE TRAME MQTT REÇUE', style: GoogleFonts.spaceGrotesk(fontSize: 9, letterSpacing: 1.5, color: _secondary)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              item('Température', '$temperature °C'),
              item('Pression', '$pressure bar'),
              item('Power', '$power W'),
              item('Current', '$current A'),
              item('Ultrasonic', ultrasonic),
              item('Presence', presence),
              item('Magnetic', magnetic),
              item('Infrared', infrared),
              item('Latitude', lat),
              item('Longitude', lng),
            ],
          ),
          if (createdAt.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Horodatage: $createdAt',
              style: GoogleFonts.inter(fontSize: 11, color: _onVariant.withValues(alpha: 0.85)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _recentFramesCard() {
    final latestFirst = List<Map<String, dynamic>>.from(widget.history)
      ..sort((a, b) {
        final ta = DateTime.tryParse((a['createdAt'] ?? '').toString()) ?? DateTime.fromMillisecondsSinceEpoch(0);
        final tb = DateTime.tryParse((b['createdAt'] ?? '').toString()) ?? DateTime.fromMillisecondsSinceEpoch(0);
        return tb.compareTo(ta);
      });
    final rows = latestFirst.take(10).toList();

    String fmtField(Map<String, dynamic> p, String key, {int decimals = 2}) {
      final v = _num(_pointValue(p, key));
      if (v == null) return '—';
      return v.toStringAsFixed(decimals);
    }

    String when(Map<String, dynamic> p) {
      final raw = (p['createdAt'] ?? p['updatedAt'] ?? '').toString();
      final dt = DateTime.tryParse(raw);
      if (dt == null) return raw.isEmpty ? '—' : raw;
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _surfaceLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _outlineVariant.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('10 DERNIÈRES TRAMES MQTT', style: GoogleFonts.spaceGrotesk(fontSize: 9, letterSpacing: 1.5, color: _secondary)),
          const SizedBox(height: 10),
          if (rows.isEmpty)
            Text('Aucune trame dans l’historique.', style: GoogleFonts.inter(fontSize: 12, color: _onVariant))
          else
            Column(
              children: rows.map((p) {
                final temp = fmtField(p, 'thermal', decimals: 1) == '—' ? fmtField(p, 'temperature', decimals: 1) : fmtField(p, 'thermal', decimals: 1);
                final press = fmtField(p, 'pressure', decimals: 2);
                final power = fmtField(p, 'power', decimals: 1);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: _surfaceLowest,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _outlineVariant.withValues(alpha: 0.14)),
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 64,
                          child: Text(when(p), style: GoogleFonts.spaceGrotesk(fontSize: 10, color: _onVariant)),
                        ),
                        Expanded(
                          child: Text(
                            'T: $temp °C   P: $press bar   Pow: $power W',
                            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: _onSurface),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _lineChart(List<double> values, Color color, String unit) {
    if (values.isEmpty) {
      return Center(child: Text('Pas de données', style: GoogleFonts.inter(color: _onVariant)));
    }
    final spots = <FlSpot>[];
    for (var i = 0; i < values.length; i++) {
      spots.add(FlSpot(i.toDouble(), values[i]));
    }
    var minY = values.reduce((a, b) => a < b ? a : b);
    var maxY = values.reduce((a, b) => a > b ? a : b);
    if ((maxY - minY).abs() < 1e-6) {
      minY -= 1;
      maxY += 1;
    } else {
      final pad = (maxY - minY) * 0.08;
      minY -= pad;
      maxY += pad;
    }

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (values.length - 1).clamp(0, 9999).toDouble(),
        minY: minY,
        maxY: maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: (maxY - minY) > 0 ? (maxY - minY) / 4 : 1,
          getDrawingHorizontalLine: (v) => FlLine(color: _outlineVariant.withValues(alpha: 0.15), strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              getTitlesWidget: (v, m) => Text(
                v.toStringAsFixed(v.abs() >= 100 ? 0 : 1),
                style: GoogleFonts.inter(fontSize: 9, color: _onVariant.withValues(alpha: 0.75)),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: ((values.length > 12 ? (values.length / 6).ceilToDouble() : 1).clamp(1, 99)).toDouble(),
              getTitlesWidget: (v, m) => Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(v.toInt().toString(), style: GoogleFonts.inter(fontSize: 9, color: _onVariant.withValues(alpha: 0.6))),
              ),
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: color,
            barWidth: 2.4,
            isStrokeCapRound: true,
            dotData: FlDotData(show: values.length <= 24),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [color.withValues(alpha: 0.35), color.withValues(alpha: 0.02)],
              ),
            ),
          ),
        ],
        lineTouchData: LineTouchData(
          enabled: true,
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (touched) {
              return touched.map((t) {
                final y = t.y;
                return LineTooltipItem(
                  '${y.toStringAsFixed(2)} $unit',
                  GoogleFonts.inter(color: _onSurface, fontWeight: FontWeight.w600, fontSize: 12),
                );
              }).toList();
            },
          ),
        ),
      ),
    );
  }

  Widget _emptyCard({required IconData icon, required String title, required String subtitle, Widget? action}) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: _surfaceLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _outlineVariant.withValues(alpha: 0.14)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: _onVariant.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          Text(title, textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: _onSurface)),
          const SizedBox(height: 8),
          Text(subtitle, textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 13, color: _onVariant, height: 1.35)),
          if (action != null) ...[const SizedBox(height: 20), action],
        ],
      ),
    );
  }
}
