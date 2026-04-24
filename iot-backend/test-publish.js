const mqtt = require('mqtt');
const brokerUrl = 'mqtt://broker.emqx.io';
const topic = 'abbk/asus01_9f3a/telemetry';

const client = mqtt.connect(brokerUrl);

const testData = {
    machines: [
        {
            machineId: "MAC_A01",
            metrics: {
                thermal: 35.5,
                humidity: 50,
                pressure: 6.2,
                power: 45,
                ultrasonic: 80
            }
        }
    ]
};

client.on('connect', () => {
    console.log('🚀 Envoi message TEST sur ' + topic);
    client.publish(topic, JSON.stringify(testData), () => {
        console.log('✅ Envoyé!');
        process.exit(0);
    });
});
