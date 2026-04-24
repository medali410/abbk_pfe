/// Références matérielles des capteurs prévus pour le déploiement (parc moteurs DALI).
///
/// Alignement avec les voies télémétriques : pression, puissance, vibration, présence,
/// température (thermique + IR selon refroidissement).
abstract final class DeployedSensors {
  static const String pressure = 'Capteur de pression piézorésistif';
  static const String powerElectrical = 'PZEM-004T v3';
  static const String vibration = 'ADXL345';
  static const String proximityInductive = 'Capteur de proximité inductif';

  /// Deux voies température côté moteur refroidi par air.
  static const String motorTempAirCooled = 'PT100 + infrarouge (IR)';

  /// Deux voies température côté moteur refroidi par eau.
  static const String motorTempWaterCooled = 'Sonde température du liquide + PT1000';

  /// Lignes courtes pour encarts UI (Observatoire, fiches).
  static const List<String> summaryLines = [
    'Pression — piézorésistif',
    'Puissance (réseau / charge) — PZEM-004T v3',
    'Vibration — ADXL345',
    'Présence / proximité — inductif',
    'Temp. moteur air — PT100 + IR',
    'Temp. moteur eau — liquide + PT1000',
  ];
}
