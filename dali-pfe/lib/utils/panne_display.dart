/// Aide à l’UI : quels capteurs mettre en avant et court texte explicatif (risque panne).
class PanneUiHints {
  const PanneUiHints({
    required this.highlightMetrics,
    required this.summaryLine,
    required this.typeLine,
  });

  /// Clés alignées sur les tuiles machine : thermal, pressure, power, ultrasonic, magnetic, infrared, vibration.
  final Set<String> highlightMetrics;
  final String summaryLine;
  final String typeLine;

  static const PanneUiHints empty = PanneUiHints(
    highlightMetrics: {},
    summaryLine: '',
    typeLine: '',
  );

  bool get hasStress => highlightMetrics.isNotEmpty;
}

/// Seuil minimal de risque (%) pour activer couleurs / pulsation « panne ».
const int kPanneUiProbMin = 32;

PanneUiHints computePanneUiHints({
  required int probPanne,
  String panneType = '',
  String scenarioLabel = '',
  String scenarioExplanation = '',
  double thermal = 0,
  double pressure = 0,
  double vibration = 0,
  double power = 0,
  double magnetic = 0,
  double infrared = 0,
  double ultrasonic = 0,
}) {
  if (probPanne < kPanneUiProbMin) {
    return PanneUiHints.empty;
  }

  final combined = '${panneType.toLowerCase()} ${scenarioLabel.toLowerCase()} ${scenarioExplanation.toLowerCase()}';
  final hints = <String>{};

  void matchThermal() {
    if (combined.contains('température') ||
        combined.contains('temperature') ||
        combined.contains('thermi') ||
        combined.contains('surchauff') ||
        combined.contains('thermique') ||
        combined.contains('dissipation')) {
      hints.add('thermal');
    }
  }

  void matchPressure() {
    if (combined.contains('pression') || combined.contains('pressure') || combined.contains('cycles de pression')) {
      hints.add('pressure');
    }
  }

  void matchVibration() {
    if (combined.contains('vibration') || combined.contains('roulement')) {
      hints.add('vibration');
    }
  }

  void matchPower() {
    if (combined.contains('puissance') ||
        combined.contains('power') ||
        combined.contains('électrique') ||
        combined.contains('electrique') ||
        combined.contains('surcharge')) {
      hints.add('power');
    }
  }

  void matchMagnetic() {
    if (combined.contains('magnétique') || combined.contains('magnetique') || combined.contains('magnetic')) {
      hints.add('magnetic');
    }
  }

  void matchInfrared() {
    if (combined.contains('infrarouge') || combined.contains('infrared')) {
      hints.add('infrared');
    }
  }

  void matchUltrasonic() {
    if (combined.contains('ultrason') || combined.contains('ultrasonic')) {
      hints.add('ultrasonic');
    }
  }

  matchThermal();
  matchPressure();
  matchVibration();
  matchPower();
  matchMagnetic();
  matchInfrared();
  matchUltrasonic();

  if (hints.isEmpty) {
    if (thermal >= 58) hints.add('thermal');
    if (vibration >= 3.2) hints.add('vibration');
    if (power >= 95000 || (power > 500 && power < 35000)) hints.add('power');
    if (pressure >= 0.055 || (pressure > 0 && pressure < 0.012)) hints.add('pressure');
    if (magnetic <= 18 || magnetic >= 82) hints.add('magnetic');
    if (ultrasonic <= 18 || ultrasonic >= 62) hints.add('ultrasonic');
  }

  final parts = <String>[];
  if (hints.contains('thermal')) {
    parts.add('Température ${thermal.toStringAsFixed(1)} °C');
  }
  if (hints.contains('pressure')) {
    parts.add('Pression ${pressure.toStringAsFixed(3)}');
  }
  if (hints.contains('vibration')) {
    parts.add('Vibration ${vibration.toStringAsFixed(2)}');
  }
  if (hints.contains('power')) {
    parts.add('Puissance ${power.toStringAsFixed(0)}');
  }
  if (hints.contains('magnetic')) {
    parts.add('Magnétique ${magnetic.toStringAsFixed(1)}');
  }
  if (hints.contains('infrared')) {
    parts.add('IR ${infrared.toStringAsFixed(1)}');
  }
  if (hints.contains('ultrasonic')) {
    parts.add('Ultrason ${ultrasonic.toStringAsFixed(1)}');
  }

  final type = [panneType, scenarioLabel].map((e) => e.trim()).where((e) => e.isNotEmpty).join(' · ');
  final typeLine = type.isEmpty ? 'Risque panne (détail capteurs)' : 'Type : $type';
  final summaryLine = parts.isEmpty ? 'Surveiller l’ensemble des capteurs.' : 'Valeurs concernées : ${parts.join(' · ')}';

  return PanneUiHints(
    highlightMetrics: hints,
    summaryLine: summaryLine,
    typeLine: typeLine,
  );
}

String? failureScenarioExplanation(Map<String, dynamic>? latest) {
  if (latest == null) return null;
  final fs = latest['failureScenario'];
  if (fs is Map) {
    final e = fs['scenarioExplanation'];
    if (e != null) return e.toString();
  }
  final direct = latest['scenarioExplanation'];
  if (direct != null) return direct.toString();
  return null;
}
