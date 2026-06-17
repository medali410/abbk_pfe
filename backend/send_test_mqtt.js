const mqtt = require('mqtt');
const client = mqtt.connect('mqtt://broker.hivemq.com');

client.on('connect', () => {
  console.log('Connecté à HiveMQ. Envoi d\'un message de télémétrie de test pour MAC-8CF9A879...');
  
  const payload = {
    machineId: "MAC-8CF9A879",
    type_moteur: "air_cooled",
    air_temperature: 300.5,
    process_temperature: 301.2,
    rpm: 1480,
    torque: 42,
    tool_wear: 18,
    temperature: 28.5,
    vibration: 1.2,
    vibration_mm_s: 1.2,
    presence: 1,
    magnetic: 50.0,
    infrared: 28.5,
    ultrasonic: 0.0,
    pressure: 0.028,
    power: 62.2,
    voltage: 230.0,
    current: 0.27,
    energy_kwh: 1.5,
    frequency: 50.0,
    power_factor: 0.95,
    metrics: {
      thermal: 28.5,
      vibration: 1.2,
      vibration_mm_s: 1.2,
      pressure: 0.028,
      power: 62.2,
      ultrasonic: 0.0,
      presence: 1,
      magnetic: 50.0,
      infrared: 28.5,
      rpm: 1480,
      torque: 42,
      tool_wear: 18
    },
    sensors: {
      mlx_ambient_c: 27.35,
      mlx_object_c: 28.5,
      accel_x_ms2: 0.1,
      accel_y_ms2: 0.2,
      accel_z_ms2: 9.8,
      vibration_intensity_ms2: 1.2,
      vibration_g: 0.12
    }
  };

  client.publish('machines/MAC-8CF9A879/telemetry', JSON.stringify(payload), { qos: 0 }, (err) => {
    if (err) {
      console.error('Erreur d\'envoi:', err);
    } else {
      console.log('Message de test envoyé avec succès !');
    }
    client.end();
  });
});
