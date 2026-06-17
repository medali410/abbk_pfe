import codecs

path = r'C:\Users\ASUS\Documents\abbk_pfe\dali-pfe\lib\client_dashboard_page.dart'

with codecs.open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# Normalize newlines
content = content.replace('\r\n', '\n')

target_1 = '''  final Map<String, double> _realtimeTemps = {};
  final Map<String, double> _realtimeVibrations = {};
  final Map<String, double> _realtimeFrictions = {};
  final Map<String, double> _realtimePressures = {};
  final Map<String, double> _realtimeRisks = {};'''

replacement_1 = '''  final Map<String, double> _realtimeTemps = {};
  final Map<String, double> _realtimeVibrations = {};
  final Map<String, double> _realtimeFrictions = {};
  final Map<String, double> _realtimePressures = {};
  final Map<String, double> _realtimeMagnetics = {};
  final Map<String, double> _realtimeRisks = {};'''

target_2 = '''  Timer? _controlTicker;
  Timer? _machinesAutoRefreshTimer;

  // Public catalogue (same data as HomePage) shown inside the client dashboard (tab index=0).'''

replacement_2 = '''  Timer? _controlTicker;
  Timer? _machinesAutoRefreshTimer;

  final Map<String, String> _lastGlobalAlertMode = {};

  void _checkGlobalRisk(String mId, String mName, double temp, double vib, double mag, double iaRisk, Map<String, dynamic> machineData) {
    String newMode = 'normal';
    List<String> risques = [];
    if (temp >= 75.0) {
      newMode = 'danger';
      risques.add("Chauffage critique (>= 75°C)");
    } else if (temp >= 55.0) {
      if (newMode == 'normal') newMode = 'risque';
      risques.add("Surchauffe détectée (>= 55°C)");
    }

    if (vib >= 12.0) {
      newMode = 'danger';
      risques.add("Vibration critique (>= 12 mm/s)");
    } else if (vib >= 7.0) {
      if (newMode == 'normal') newMode = 'risque';
      risques.add("Vibration anormale (>= 7 mm/s)");
    }

    if (mag >= 80.0) {
      newMode = 'danger';
      risques.add("Magnétique critique (>= 80 mT)");
    } else if (mag >= 50.0) {
      if (newMode == 'normal') newMode = 'risque';
      risques.add("Magnétique anormal (>= 50 mT)");
    }

    if (iaRisk >= 70) {
      newMode = 'danger';
      risques.add("IA: Probabilité de panne critique");
    } else if (iaRisk >= 40) {
      if (newMode == 'normal') newMode = 'risque';
      risques.add("IA: Anomalie détectée");
    }

    final lastMode = _lastGlobalAlertMode[mId] ?? 'normal';
    if ((newMode == 'danger' || newMode == 'risque') && newMode != lastMode) {
      _lastGlobalAlertMode[mId] = newMode;
      _showGlobalDangerDialog(mId, mName, newMode, risques.join("\\n• "), machineData);
    } else if (newMode == 'normal') {
      _lastGlobalAlertMode[mId] = 'normal';
    }
  }

  void _showGlobalDangerDialog(String mId, String mName, String mode, String typeRisque, Map<String, dynamic> machineData) {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final color = mode == 'danger' ? const Color(0xFFFFB4AB) : const Color(0xFFFF6E00);
        final title = mode == 'danger' ? 'ALERTE DANGER' : 'ALERTE RISQUE';
        return AlertDialog(
          backgroundColor: const Color(0xFF272743),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: color, width: 2),
          ),
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: color, size: 32),
              const SizedBox(width: 10),
              Text(title, style: GoogleFonts.spaceGrotesk(color: color, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Machine: ' + mName.toUpperCase(), 
                style: GoogleFonts.inter(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Text('Le système a détecté une anomalie :', 
                style: GoogleFonts.inter(color: const Color(0xFFE2BFB0), fontSize: 13)),
              const SizedBox(height: 8),
              Text('• ' + typeRisque, 
                style: GoogleFonts.inter(color: color, fontSize: 14, fontWeight: FontWeight.w600)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('IGNORER', style: GoogleFonts.spaceGrotesk(color: const Color(0xFFE2BFB0))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: color),
              onPressed: () {
                Navigator.of(context).pop();
                setState(() {
                  _navIndex = 2; // AI Analysis page
                  _iaSelectedMachine = machineData;
                });
              },
              child: Text('AFFICHER', style: GoogleFonts.spaceGrotesk(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      }
    );
  }

  // Public catalogue (same data as HomePage) shown inside the client dashboard (tab index=0).'''

target_3 = '''          for (final m in list) {
            final mId = (m['machineId'] ?? m['id'] ?? m['_id'] ?? '').toString();
            if (mId.isNotEmpty) {
              _socket.on('ai:$mId', (data) {
                if (!mounted || data is! Map) return;
                setState(() {
                  _realtimeRisks[mId] = _toDouble(data['prob_panne'] ?? data['riskPercentage'], 0.0);
                });
              });
              
              ApiService.getLatestTelemetry(mId).then((tel) {
                if (tel != null && mounted) {
                  setState(() {
                    final rawMetrics = tel['metrics'];
                    final metrics = rawMetrics is Map ? Map<String, dynamic>.from(rawMetrics) : null;
                    _realtimeTemps[mId] = _toDouble(tel['temperature'] ?? tel['temp'] ?? metrics?['thermal'] ?? metrics?['temp'], 0.0);
                    _realtimeVibrations[mId] = _toDouble(tel['vibration'] ?? metrics?['vibration'], 0.0);
                    _realtimeFrictions[mId] = _toDouble(tel['friction'] ?? metrics?['friction'], 0.0);
                    _realtimePressures[mId] = _toDouble(tel['pressure'] ?? tel['pression'] ?? metrics?['pressure'] ?? metrics?['pression'], 0.0);
                    _lastTelemetryTime[mId] = DateTime.tryParse((tel['createdAt'] ?? tel['timestamp'] ?? '').toString()) ?? DateTime.now();
                  });
                }
              }).catchError((_) {});
            }
          }'''

replacement_3 = '''          for (final m in list) {
            final mId = (m['machineId'] ?? m['id'] ?? m['_id'] ?? '').toString();
            final mName = (m['name'] ?? m['nom'] ?? 'Machine').toString();
            if (mId.isNotEmpty) {
              _socket.on('ai:$mId', (data) {
                if (!mounted || data is! Map) return;
                setState(() {
                  _realtimeRisks[mId] = _toDouble(data['prob_panne'] ?? data['riskPercentage'], 0.0);
                });
                _checkGlobalRisk(mId, mName, _realtimeTemps[mId] ?? 0.0, _realtimeVibrations[mId] ?? 0.0, _realtimeMagnetics[mId] ?? 0.0, _realtimeRisks[mId] ?? 0.0, m);
              });
              
              ApiService.getLatestTelemetry(mId).then((tel) {
                if (tel != null && mounted) {
                  setState(() {
                    final rawMetrics = tel['metrics'];
                    final metrics = rawMetrics is Map ? Map<String, dynamic>.from(rawMetrics) : null;
                    _realtimeTemps[mId] = _toDouble(tel['temperature'] ?? tel['temp'] ?? metrics?['thermal'] ?? metrics?['temp'], 0.0);
                    _realtimeVibrations[mId] = _toDouble(tel['vibration'] ?? metrics?['vibration'], 0.0);
                    _realtimeFrictions[mId] = _toDouble(tel['friction'] ?? metrics?['friction'], 0.0);
                    _realtimePressures[mId] = _toDouble(tel['pressure'] ?? tel['pression'] ?? metrics?['pressure'] ?? metrics?['pression'], 0.0);
                    _realtimeMagnetics[mId] = _toDouble(tel['magnetic'] ?? tel['magnet'] ?? metrics?['magnetic'] ?? metrics?['magnet'], 0.0);
                    _lastTelemetryTime[mId] = DateTime.tryParse((tel['createdAt'] ?? tel['timestamp'] ?? '').toString()) ?? DateTime.now();
                  });
                  _checkGlobalRisk(mId, mName, _realtimeTemps[mId] ?? 0.0, _realtimeVibrations[mId] ?? 0.0, _realtimeMagnetics[mId] ?? 0.0, _realtimeRisks[mId] ?? 0.0, m);
                }
              }).catchError((_) {});
            }
          }'''

if target_1 in content and target_2 in content and target_3 in content:
    content = content.replace(target_1, replacement_1)
    content = content.replace(target_2, replacement_2)
    content = content.replace(target_3, replacement_3)
    
    # Save back with standard newlines or CRLF
    content = content.replace('\n', '\r\n')
    with codecs.open(path, 'w', encoding='utf-8') as f:
        f.write(content)
    print('SUCCESS')
else:
    print('FAIL')
    if target_1 not in content:
        print('target_1 not found')
    if target_2 not in content:
        print('target_2 not found')
    if target_3 not in content:
        print('target_3 not found')
