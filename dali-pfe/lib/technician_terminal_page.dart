import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class TechnicianTerminalPage extends StatefulWidget {
  const TechnicianTerminalPage({super.key});

  @override
  State<TechnicianTerminalPage> createState() => _TechnicianTerminalPageState();
}

class _TechnicianTerminalPageState extends State<TechnicianTerminalPage> with TickerProviderStateMixin {
  String _techId = '8829-X';
  String _techName = 'Technicien';
  final List<String> _consoleLogs = [];
  final math.Random _random = math.Random();
  Timer? _logTimer;
  late AnimationController _waveController;

  @override
  void initState() {
    super.initState();
    _addInitialLogs();
    _startLogSimulation();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map<String, dynamic>) {
      setState(() {
        _techId = args['techId'] ?? '8829-X';
        _techName = args['name'] ?? 'Technicien';
      });
    }
  }

  @override
  void dispose() {
    _logTimer?.cancel();
    _waveController.dispose();
    super.dispose();
  }

  void _addInitialLogs() {
    _consoleLogs.addAll([
      '> INITIATING SECURE UPLINK...',
      '> AUTHENTICATING NODE_01 // SECURE_KEY_RECOGNIZED',
      '> ESTABLISHING BIOMETRIC HANDSHAKE...',
      '> ACCESS GRANTED. WELCOME OPERATOR.',
      '> MONITORING LIVE FEED FROM SECTOR G-7',
    ]);
  }

  void _startLogSimulation() {
    _logTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (!mounted) return;
      const msgs = [
        '> SCANNING GRID NODE 12... [OK]',
        '> PACKET RELAY OPTIMIZED',
        '> ENCRYPTION ROTATION COMPLETED',
        '> HEARTBEAT DETECTED ON SUB-SYSTEM B',
        '> IDLE_MODE: FALSE // ACTIVE_SENSORS: ALL',
      ];
      setState(() {
        if (_consoleLogs.length > 30) _consoleLogs.removeAt(0);
        _consoleLogs.add(msgs[_random.nextInt(msgs.length)]);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070B14),
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 3,
                  child: _buildMainTerminal(),
                ),
                _buildRightPanel(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: const Color(0xFF0A0E1A),
        border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.05))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Text(
            'CLIENT_ID // $_techId',
            style: GoogleFonts.orbitron(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
          const Spacer(),
          _buildHeaderInfo('LATENCY', '0.12ms'),
          _buildHeaderInfo('NODE', '01'),
          _buildHeaderInfo('STATUS', 'ACTIVE', color: Colors.greenAccent),
          const SizedBox(width: 20),
          const Icon(Icons.wifi, color: Colors.cyanAccent, size: 16),
          const SizedBox(width: 20),
          const Icon(Icons.settings_outlined, color: Colors.blueGrey, size: 20),
        ],
      ),
    );
  }

  Widget _buildHeaderInfo(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GoogleFonts.spaceGrotesk(color: Colors.blueGrey, fontSize: 8, fontWeight: FontWeight.bold)),
          Text(value, style: GoogleFonts.spaceGrotesk(color: color ?? Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildMainTerminal() {
    return Container(
      margin: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(20),
              itemCount: _consoleLogs.length,
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _consoleLogs[index],
                    style: GoogleFonts.spaceGrotesk(color: Colors.cyanAccent.withOpacity(0.7), fontSize: 12),
                  ),
                );
              },
            ),
          ),
          Container(
            height: 60,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05))),
            ),
            child: Row(
              children: [
                Text(
                  'TRANSMIT SECURE DATA...',
                  style: GoogleFonts.spaceGrotesk(color: Colors.blueGrey, fontSize: 12),
                ),
                const Spacer(),
                const Icon(Icons.keyboard_arrow_right, color: Colors.cyanAccent),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRightPanel() {
    return Container(
      width: 380,
      decoration: BoxDecoration(
        color: const Color(0xFF090D18),
        border: Border(left: BorderSide(color: Colors.white.withOpacity(0.05))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                const Icon(Icons.queue, color: Colors.orangeAccent, size: 18),
                const SizedBox(width: 10),
                Text(
                  'VALIDATION_QUEUE',
                  style: GoogleFonts.orbitron(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                _buildValidationCard('HARDWARE_OVERRIDE', 'REQUEST_BY: NODE_07', 'CRITICAL'),
                _buildValidationCard('LOG_AUTH_REQUEST', 'REQUEST_BY: EXT_USER_8', 'HIGH'),
                _buildValidationCard('ACCESS_GRANT', 'REQUEST_BY: SEC_NODE_2', 'MEDIUM'),
              ],
            ),
          ),
          _buildLiveTelemetry(),
        ],
      ),
    );
  }

  Widget _buildValidationCard(String title, String subtitle, String priority) {
    Color pColor = Colors.cyanAccent;
    if (priority == 'CRITICAL') pColor = Colors.redAccent;
    if (priority == 'HIGH') pColor = Colors.orangeAccent;

    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0C1322),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: GoogleFonts.orbitron(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: pColor.withOpacity(0.1), borderRadius: BorderRadius.circular(2)),
                child: Text(priority, style: GoogleFonts.spaceGrotesk(color: pColor, fontSize: 8, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(subtitle, style: GoogleFonts.spaceGrotesk(color: Colors.blueGrey, fontSize: 10)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () {},
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.greenAccent.withOpacity(0.1),
                    foregroundColor: Colors.greenAccent,
                    side: const BorderSide(color: Colors.greenAccent, width: 0.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  child: Text('VALIDATE', style: GoogleFonts.spaceGrotesk(fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {},
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent.withOpacity(0.1),
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(color: Colors.redAccent, width: 0.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  child: Text('DECLINE', style: GoogleFonts.spaceGrotesk(fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLiveTelemetry() {
    return Container(
      height: 180,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0E1A),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('LIVE_TELEMETRY', style: GoogleFonts.spaceGrotesk(color: Colors.blueGrey, fontSize: 10, fontWeight: FontWeight.bold)),
              Text('STREAMING...', style: GoogleFonts.spaceGrotesk(color: Colors.cyanAccent, fontSize: 8)),
            ],
          ),
          const Spacer(),
          SizedBox(
            height: 80,
            width: double.infinity,
            child: AnimatedBuilder(
              animation: _waveController,
              builder: (context, child) {
                return CustomPaint(
                  painter: WavePainter(color: Colors.cyanAccent, animationValue: _waveController.value),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class WavePainter extends CustomPainter {
  final Color color;
  final double animationValue;
  WavePainter({required this.color, required this.animationValue});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(0.5)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final path = Path();
    for (double i = 0; i <= size.width; i++) {
      double y = size.height / 2 + 
                 math.sin((i * 0.05) + (animationValue * 2 * math.pi)) * 20 + 
                 math.cos((i * 0.02) + (animationValue * math.pi)) * 10;
      if (i == 0) {
        path.moveTo(i, y);
      } else {
        path.lineTo(i, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
