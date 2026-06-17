import codecs

path = r'C:\Users\ASUS\Documents\abbk_pfe\dali-pfe\lib\ai_analysis_page.dart'

with codecs.open(path, 'r', encoding='utf-8') as f:
    content = f.read()

content = content.replace('\r\n', '\n')

target_1 = '''          Expanded(child: _sensorCard(
            icon: '🧲', title: 'MAGNÉTIQUE',
            value: '${_magnetic.toStringAsFixed(2)} mT',
            raw: _magnetic, min: 0, max: 100,
            dangerThreshold: 80, warningThreshold: 60, unit: 'mT',
            isDisconnected: _magneticDisc,
          )),'''

replacement_1 = '''          Expanded(child: _sensorCard(
            icon: '🧲', title: 'MAGNÉTIQUE',
            value: '${_magnetic.toStringAsFixed(2)} mT',
            raw: _magnetic, min: 0, max: 100,
            dangerThreshold: 80, warningThreshold: 50.0, unit: 'mT',
            isDisconnected: _magneticDisc,
          )),'''

target_2 = '''  String _computeMode() {
    // Use _thermal (°C) from VUE D'ENSEMBLE, _vibration (mm/s)
    final temp = _thermal > 0 ? _thermal : (_tempContact + _tempInfra) / 2.0;
    final vib = _vibration > 0 ? _vibration : math.sqrt(_vibX * _vibX + _vibY * _vibY);
    // Vibration in mm/s: danger >= 12, risque >= 7
    // Temperature: danger >= 75, risque >= 55
    if (temp >= 75.0 || vib >= 12.0) return 'danger';
    if (temp >= 55.0 || vib >= 7.0) return 'risque';
    return 'normal';
  }'''

replacement_2 = '''  String _computeMode() {
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

target_3 = '''  String _getDangerType() {
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

replacement_3 = '''  String _getDangerType() {
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

if target_1 in content and target_2 in content and target_3 in content:
    content = content.replace(target_1, replacement_1)
    content = content.replace(target_2, replacement_2)
    content = content.replace(target_3, replacement_3)
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
