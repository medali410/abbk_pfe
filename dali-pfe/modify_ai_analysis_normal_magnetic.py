import codecs

path = r'C:\Users\ASUS\Documents\abbk_pfe\dali-pfe\lib\ai_analysis_page.dart'

with codecs.open(path, 'r', encoding='utf-8') as f:
    content = f.read()

content = content.replace('\r\n', '\n')

# 1. Update magnetic sensor card thresholds to 999.0
target_card = '''          Expanded(child: _sensorCard(
            icon: '🧲', title: 'MAGNÉTIQUE',
            value: '${_magnetic.toStringAsFixed(2)} mT',
            raw: _magnetic, min: 0, max: 100,
            dangerThreshold: 80, warningThreshold: 50.0, unit: 'mT',
            isDisconnected: _magneticDisc,
          )),'''

replacement_card = '''          Expanded(child: _sensorCard(
            icon: '🧲', title: 'MAGNÉTIQUE',
            value: '${_magnetic.toStringAsFixed(2)} mT',
            raw: _magnetic, min: 0, max: 100,
            dangerThreshold: 999.0, warningThreshold: 999.0, unit: 'mT',
            isDisconnected: _magneticDisc,
          )),'''

# 2. Update risk calculations by finding the index of "// Chauffage risk:" up to "final Color chauffColor"
idx_start = content.find('// Chauffage risk:')
idx_end = content.find('final Color chauffColor =')

if idx_start != -1 and idx_end != -1:
    old_risk_pct = content[idx_start:idx_end]
    new_risk_pct = '''// Chauffage risk: based on tempVal (°C) (35→normal, 55→risque, 75→danger)
    final tempVal = _thermal > 0 ? _thermal : _tempContact;
    final double chauffageRiskPct = tempVal <= 0
        ? (_gaugePercent * 0.5).clamp(0, 100)
        : (tempVal <= 35.0
            ? 10.0
            : tempVal < 55.0
                ? 20.0 + ((tempVal - 35.0) / 20.0) * 19.0
                : tempVal <= 75.0
                    ? 40.0 + ((tempVal - 55.0) / 20.0) * 30.0
                    : 70.0 + ((tempVal - 75.0) / 25.0).clamp(0, 1) * 30.0);

    // Vibration risk: based on vibration mm/s (0→normal, 7→risque, 12→danger)
    final vibVal = _vibration;
    final double vibrationRiskPct = vibVal <= 0
        ? (_gaugePercent * 0.5).clamp(0, 100)
        : (vibVal <= 3.0
            ? 10.0
            : vibVal < 7.0
                ? 20.0 + ((vibVal - 3.0) / 4.0) * 19.0
                : vibVal <= 12.0
                    ? 40.0 + ((vibVal - 7.0) / 5.0) * 30.0
                    : 70.0 + ((vibVal - 12.0) / 8.0).clamp(0, 1) * 30.0);

    '''
    content = content[:idx_start] + new_risk_pct + content[idx_end:]
    has_risk_updated = True
else:
    has_risk_updated = False

target_compute_mode = '''  String _computeMode() {
    // Use _thermal (°C) from VUE D'ENSEMBLE, _vibration (mm/s)
    final temp = _thermal > 0 ? _thermal : (_tempContact + _tempInfra) / 2.0;
    final vib = _vibration > 0 ? _vibration : math.sqrt(_vibX * _vibX + _vibY * _vibY);
    final mag = _magnetic;
    // Vibration in mm/s: danger >= 12, risque >= 7
    // Temperature: danger >= 75, risque >= 55
    // Magnetic in mT: danger >= 80, risque >= 50
    if (temp >= 75.0 || vib >= 12.0 || mag >= 80.0) return 'danger';
    if (temp >= 55.0 || vib >= 7.0 || mag >= 50.0) return 'risque';
    return 'normal';
  }'''

replacement_compute_mode = '''  String _computeMode() {
    // Use _thermal (°C) from VUE D'ENSEMBLE, _vibration (mm/s)
    final temp = _thermal > 0 ? _thermal : (_tempContact + _tempInfra) / 2.0;
    final vib = _vibration > 0 ? _vibration : math.sqrt(_vibX * _vibX + _vibY * _vibY);
    // Vibration in mm/s: danger >= 12, risque >= 7
    // Temperature: danger >= 75, risque >= 55
    if (temp >= 75.0 || vib >= 12.0) return 'danger';
    if (temp >= 55.0 || vib >= 7.0) return 'risque';
    return 'normal';
  }'''

target_danger_type = '''  String _getDangerType() {
    List<String> risques = [];
    final temp = _thermal > 0 ? _thermal : (_tempContact + _tempInfra) / 2.0;
    final vib = _vibration > 0 ? _vibration : math.sqrt(_vibX * _vibX + _vibY * _vibY);
    final mag = _magnetic;
    if (temp >= 75.0) risques.add("Chauffage critique (>= 75°C)");
    else if (temp >= 55.0) risques.add("Surchauffe détectée (>= 55°C)");
    if (vib >= 12.0) risques.add("Vibration critique (>= 12 mm/s)");
    else if (vib >= 7.0) risques.add("Vibration anormale (>= 7 mm/s)");
    if (mag >= 80.0) risques.add("Magnétique critique (>= 80 mT)");
    else if (mag >= 50.0) risques.add("Magnétique anormal (>= 50 mT)");
    
    if (_gaugePercent >= 70) risques.add("IA: Probabilité de panne critique");
    else if (_gaugePercent >= 40) risques.add("IA: Anomalie détectée");
    
    if (risques.isEmpty) return "Risque indéterminé";
    return risques.join("\\n• ");
  }'''

replacement_danger_type = '''  String _getDangerType() {
    List<String> risques = [];
    final temp = _thermal > 0 ? _thermal : (_tempContact + _tempInfra) / 2.0;
    final vib = _vibration > 0 ? _vibration : math.sqrt(_vibX * _vibX + _vibY * _vibY);
    if (temp >= 75.0) risques.add("Chauffage critique (>= 75°C)");
    else if (temp >= 55.0) risques.add("Surchauffe détectée (>= 55°C)");
    if (vib >= 12.0) risques.add("Vibration critique (>= 12 mm/s)");
    else if (vib >= 7.0) risques.add("Vibration anormale (>= 7 mm/s)");
    
    if (_gaugePercent >= 70) risques.add("IA: Probabilité de panne critique");
    else if (_gaugePercent >= 40) risques.add("IA: Anomalie détectée");
    
    if (risques.isEmpty) return "Risque indéterminé";
    return risques.join("\\n• ");
  }'''

if target_card in content and has_risk_updated and target_compute_mode in content and target_danger_type in content:
    content = content.replace(target_card, replacement_card)
    content = content.replace(target_compute_mode, replacement_compute_mode)
    content = content.replace(target_danger_type, replacement_danger_type)
    content = content.replace('\n', '\r\n')
    with codecs.open(path, 'w', encoding='utf-8') as f:
        f.write(content)
    print('SUCCESS')
else:
    print('FAIL')
    if target_card not in content:
        print('target_card not found')
    if not has_risk_updated:
        print('risk update failed')
    if target_compute_mode not in content:
        print('target_compute_mode not found')
    if target_danger_type not in content:
        print('target_danger_type not found')
