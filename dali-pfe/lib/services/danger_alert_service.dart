import 'dart:async';

// ──────────────────────────────────────────────────────────────────────────────
// DangerAlertEvent — payload broadcasted when the AI model detects a risk
// ──────────────────────────────────────────────────────────────────────────────

class DangerAlertEvent {
  final String machineId;
  final String machineName;
  final String mode; // 'danger' | 'risque'
  final double riskPercent;
  final String scenario;
  final double temperature;
  final double vibration;
  final double pressure;
  final double power;
  final double magnetic;
  final double infrared;
  final String dangerType;

  const DangerAlertEvent({
    required this.machineId,
    required this.machineName,
    required this.mode,
    required this.riskPercent,
    required this.scenario,
    required this.temperature,
    required this.vibration,
    required this.pressure,
    required this.power,
    required this.magnetic,
    required this.infrared,
    required this.dangerType,
  });
}

// ──────────────────────────────────────────────────────────────────────────────
// DangerAlertService — global singleton broadcaster
// ──────────────────────────────────────────────────────────────────────────────

class DangerAlertService {
  DangerAlertService._();
  static final DangerAlertService instance = DangerAlertService._();

  final _controller = StreamController<DangerAlertEvent>.broadcast();

  Stream<DangerAlertEvent> get stream => _controller.stream;

  void broadcast(DangerAlertEvent event) {
    if (!_controller.isClosed) {
      _controller.add(event);
    }
  }

  void dispose() {
    _controller.close();
  }
}
