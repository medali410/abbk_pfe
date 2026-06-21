import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/api_service.dart';

class TelemetryHistoryWidget extends StatefulWidget {
  final String machineId;
  const TelemetryHistoryWidget({Key? key, required this.machineId}) : super(key: key);

  @override
  State<TelemetryHistoryWidget> createState() => _TelemetryHistoryWidgetState();
}

class _TelemetryHistoryWidgetState extends State<TelemetryHistoryWidget> {
  late Future<List<Map<String, dynamic>>> _historyFuture;

  @override
  void initState() {
    super.initState();
    _historyFuture = ApiService.getTelemetryHistory(widget.machineId, limit: 10);
  }

  Widget _buildMiniMetric(String label, String val, IconData icon, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(height: 2),
        Text(
          val,
          style: GoogleFonts.inter(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: const Color(0xFFE2E2E9),
          ),
        ),
        Text(
          label,
          style: GoogleFonts.spaceGrotesk(
            fontSize: 8,
            color: const Color(0xFFC4C4D4),
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _historyFuture,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Container(
            height: 200,
            decoration: BoxDecoration(
              color: const Color(0xFF13132B),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: const Center(
              child: CircularProgressIndicator(color: Color(0xFFE55A00)),
            ),
          );
        }
        if (snap.hasError) {
          return Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.red.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline_rounded, color: Colors.red),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Historique indisponible : \${snap.error}',
                    style: GoogleFonts.inter(color: Colors.red),
                  ),
                ),
              ],
            ),
          );
        }
        final rows = snap.data ?? [];
        if (rows.isEmpty) {
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
            decoration: BoxDecoration(
              color: const Color(0xFF13132B),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Column(
              children: [
                Icon(Icons.monitor_heart_outlined, size: 48, color: Colors.white.withOpacity(0.4)),
                const SizedBox(height: 16),
                Text(
                  'Aucune télémétrie enregistrée',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'En attente des premières données capteurs...',
                  style: GoogleFonts.inter(fontSize: 13, color: Colors.white54),
                ),
              ],
            ),
          );
        }
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF13132B),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.15)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: rows.length,
              separatorBuilder: (_, __) => Divider(height: 1, color: Colors.white.withOpacity(0.1)),
              itemBuilder: (context, i) {
                final r = rows[i];
                final tsRaw = (r['createdAt'] ?? r['updatedAt'] ?? r['timestamp'] ?? '').toString();
                
                String formattedTime = tsRaw;
                try {
                  if (tsRaw.isNotEmpty) {
                    final dt = DateTime.parse(tsRaw).toLocal();
                    final d = dt.day.toString().padLeft(2, '0');
                    final m = dt.month.toString().padLeft(2, '0');
                    final h = dt.hour.toString().padLeft(2, '0');
                    final min = dt.minute.toString().padLeft(2, '0');
                    formattedTime = '$d/$m/${dt.year} à $h:$min';
                  }
                } catch (_) {}

                final temp = (r['temperature'] ?? r['temp'] ?? '—').toString();
                final vib = (r['vibration'] ?? '—').toString();
                final pow = (r['power'] ?? r['powerConsumption'] ?? r['puissance'] ?? '—').toString();
                final press = (r['pressure'] ?? r['pression'] ?? '—').toString();
                final volt = (r['voltage'] ?? r['tension'] ?? '—').toString();
                
                return InkWell(
                  onTap: () {},
                  hoverColor: Colors.white.withOpacity(0.05),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: const BoxDecoration(
                            color: Color(0xFF1C1C3A),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.sensors_rounded, color: Color(0xFFE55A00), size: 14),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                formattedTime,
                                style: GoogleFonts.spaceGrotesk(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Relevé de capteurs',
                                style: GoogleFonts.inter(fontSize: 10, color: Colors.white70),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _buildMiniMetric('T°', '$temp°C', Icons.thermostat_rounded, const Color(0xFFFF5252)),
                              _buildMiniMetric('Vib', vib, Icons.vibration_rounded, const Color(0xFF448AFF)),
                              _buildMiniMetric('P', press, Icons.speed_rounded, const Color(0xFF69F0AE)),
                              _buildMiniMetric('W', pow, Icons.bolt_rounded, const Color(0xFFFFD740)),
                              _buildMiniMetric('Volt', '$volt V', Icons.electric_bolt_rounded, const Color(0xFFB388FF)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
