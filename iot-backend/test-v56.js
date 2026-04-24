const mqtt = require('mqtt');
const brokerUrl = 'mqtt://broker.emqx.io';
const topic = 'abbk/asus01_9f3a/telemetry';

const client = mqtt.connect(brokerUrl);

// Format EXACT du code Arduino v5.6
const v56Data = {
    gateway: "ESP32-ABBKA",
    cycle: 42,
    machines: [
        {
            machineId: "MAC_A01",
            machineName: "Presse Hydraulique A01",
            metrics: {
                thermal: 38.5,
                humidity: 55.0,
                pressure: 7.2,
                power: 45.0,
                ultrasonic: 80.0,
                presence: 0,
                magnetic: 1
            },
            security: { state: "NORMAL", alarms: "AUCUNE" }
        },
        {
            machineId: "MAC_A02",
            machineName: "Tour CNC A02",
            metrics: {
                thermal: 42.1,
                humidity: 48.0,
                pressure: 8.5,
                power: 65.0,
                ultrasonic: 120.0,
                presence: 1,
                magnetic: 1
            },
            security: { state: "CRITIQUE", alarms: "TEMP_HAUTE" }
        }
    ]
};

client.on('connect', () => {
    console.log('🚀 [TEST v5.6] Envoi sur ' + topic);
    client.publish(topic, JSON.stringify(v56Data), () => {
        console.log('✅ Message injecté avec succès!');
        setTimeout(() => process.exit(0), 1000);
    });
});
