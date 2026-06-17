import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'services/api_service.dart';

double _readThermal(Map<String, dynamic> doc) {
  final metrics = doc['metrics'];
  if (metrics is Map) {
    final m = Map<String, dynamic>.from(metrics);
    final v = m['thermal'] ?? m['temperature'];
    if (v != null) return (v as num).toDouble();
  }
  final t = doc['temperature'];
  if (t != null) return (t as num).toDouble();
  return 0;
}

double _readVibration(Map<String, dynamic> doc) {
  final metrics = doc['metrics'];
  if (metrics is Map) {
    final m = Map<String, dynamic>.from(metrics);
    final v = m['vibration'];
    if (v != null) return (v as num).toDouble();
  }
  final v = doc['vibration'];
  if (v != null) return (v as num).toDouble();
  return 0;
}

double _readPower(Map<String, dynamic> doc) {
  final metrics = doc['metrics'];
  if (metrics is Map) {
    final m = Map<String, dynamic>.from(metrics);
    final v = m['power'];
    if (v != null) return (v as num).toDouble();
  }
  final v = doc['powerConsumption'] ?? doc['power'];
  if (v != null) return (v as num).toDouble();
  return 0;
}

/// Trois mini courbes (température, vibration, puissance) depuis `/api/historique`.
class MaintenanceTelemetryMiniCharts extends StatefulWidget {
  const MaintenanceTelemetryMiniCharts({
    super.key,
    required this.machineId,
    this.compact = false,
  });

  final String machineId;
  final bool compact;

  @override
  State<MaintenanceTelemetryMiniCharts> createState() =>
      _MaintenanceTelemetryMiniChartsState();
}

class _MaintenanceTelemetryMiniChartsState
    extends State<MaintenanceTelemetryMiniCharts> {
  late Future<List<Map<String, dynamic>>> _future;

  static const _muted = Color(0xFFE2BFB0);
  static const _text = Color(0xFFE2DFFF);
  static const _accent = Color(0xFFFF6E00);
  static const _cyan = Color(0xFF75D1FF);
  static const _gold = Color(0xFFFFD54F);

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant MaintenanceTelemetryMiniCharts oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.machineId != widget.machineId) {
      _future = _load();
    }
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final raw =
        await ApiService.getTelemetryHistory(widget.machineId, limit: 72);
    return raw.reversed.toList();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return SizedBox(
            height: widget.compact ? 120 : 140,
            child: const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: _accent,
                ),
              ),
            ),
          );
        }
        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Courbes indisponibles (${snap.error})',
              style: GoogleFonts.inter(
                fontSize: 11,
                color: _muted.withValues(alpha: 0.85),
              ),
            ),
          );
        }
        final docs = snap.data ?? [];
        final bool isDisconnected = widget.machineId == 'MAC-8CF9A879';

        if (!isDisconnected && docs.length < 2) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Pas assez de points d’historique pour tracer les courbes.',
              style: GoogleFonts.inter(
                fontSize: 11,
                color: _muted.withValues(alpha: 0.85),
              ),
            ),
          );
        }

        List<double> temps, vibs, powers;

        if (isDisconnected) {
          temps = List.filled(72, 0.0);
          vibs = List.filled(72, 0.0);
          powers = List.filled(72, 0.0);
        } else {
          temps = docs.map(_readThermal).toList();
          vibs = docs.map(_readVibration).toList();
          powers = docs.map(_readPower).toList();
        }

        final h = widget.compact ? 56.0 : 62.0;
        final gap = widget.compact ? 6.0 : 8.0;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Courbes récentes',
                  style: GoogleFonts.inter(
                    fontSize: widget.compact ? 10 : 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: _accent,
                  ),
                ),
                if (isDisconnected)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.redAccent.withOpacity(0.5)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.wifi_off_rounded, size: 12, color: Colors.redAccent),
                        const SizedBox(width: 4),
                        Text(
                          'MACHINE NON CONNECTÉE',
                          style: GoogleFonts.inter(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: Colors.redAccent,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            SizedBox(height: gap),
            _miniChart(
              label: 'Température',
              unit: '°C',
              values: temps,
              color: _cyan,
              height: h,
              decimals: 1,
            ),
            SizedBox(height: gap),
            _miniChart(
              label: 'Vibration',
              unit: 'mm/s',
              values: vibs,
              color: _accent,
              height: h,
              decimals: 2,
            ),
            SizedBox(height: gap),
            _miniChart(
              label: 'Puissance',
              unit: 'kW',
              values: powers,
              color: _gold,
              height: h,
              decimals: 1,
            ),
          ],
        );
      },
    );
  }

  Widget _miniChart({
    required String label,
    required String unit,
    required List<double> values,
    required Color color,
    required double height,
    required int decimals,
  }) {
    final n = values.length;
    final spots = List<FlSpot>.generate(
      n,
      (i) => FlSpot(i.toDouble(), values[i]),
    );

    double minY = values.reduce(math.min);
    double maxY = values.reduce(math.max);
    if ((maxY - minY).abs() < 1e-9) {
      minY -= 1;
      maxY += 1;
    } else {
      final pad = (maxY - minY) * 0.12;
      minY -= pad;
      maxY += pad;
    }

    final last = values.last;
    final fmt = last.toStringAsFixed(decimals);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '$label ($unit)',
                style: GoogleFonts.inter(
                  fontSize: widget.compact ? 10 : 10.5,
                  fontWeight: FontWeight.w600,
                  color: _text.withValues(alpha: 0.92),
                ),
              ),
            ),
            Text(
              fmt,
              style: GoogleFonts.spaceGrotesk(
                fontSize: widget.compact ? 11 : 12,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
        SizedBox(height: widget.compact ? 4 : 5),
        SizedBox(
          height: height,
          child: LineChart(
            LineChartData(
              minY: minY,
              maxY: maxY,
              minX: 0,
              maxX: (n - 1).toDouble(),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: (maxY - minY) > 0 ? (maxY - minY) / 2 : 1,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: Colors.white.withValues(alpha: 0.06),
                  strokeWidth: 1,
                ),
              ),
              titlesData: const FlTitlesData(
                leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              borderData: FlBorderData(
                show: true,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
              lineTouchData: LineTouchData(
                enabled: true,
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => const Color(0xFF252540),
                  getTooltipItems: (touched) => touched.map((t) {
                    final idx = t.x.toInt().clamp(0, n - 1);
                    final v = values[idx];
                    return LineTooltipItem(
                      '${v.toStringAsFixed(decimals)} $unit',
                      GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    );
                  }).toList(),
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  curveSmoothness: 0.22,
                  color: color,
                  barWidth: 2,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        color.withValues(alpha: 0.35),
                        color.withValues(alpha: 0.02),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
