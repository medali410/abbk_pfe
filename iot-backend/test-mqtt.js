const mqtt = require('mqtt');

const brokerUrl = 'wss://broker.emqx.io:8084/mqtt';
const topic = 'abbk/asus01_9f3a/telemetry';

const payload = {
    machineId: "MAC_A01",
    metrics: {
        thermal: 105.5,
        pressure: 12.2,
        power: 95.0,
        ultrasonic: 2.3,
        presence: 1,
        magnetic: 1,
        infrared: 110.0
    },
    timestamp: new Date().toISOString()
};

console.log('[MQTT TEST] Connexion à', brokerUrl, '...');
const client = mqtt.connect(brokerUrl);

client.on('connect', () => {
    client.subscribe(topic);
    console.log('[MQTT TEST] Subscribed to own topic.');

    client.publish(topic, JSON.stringify(payload), {}, (err) => {
        if (err) {
            console.error('[MQTT TEST] Erreur envoi:', err);
        } else {
            console.log('\n✅ Message MQTT envoyé avec succès !');
        }
    });
});

client.on('message', (t, m) => {
    console.log('\n📩 SOURCE: Broker | Topic:', t);
    console.log('📦 Content:', m.toString());
    console.log('✅ Confirmation: Le message a fait l\'aller-retour au broker!');
    client.end();
    process.exit(0);
});

client.on('error', (err) => {
    console.error('[MQTT TEST] Erreur:', err.message);
    process.exit(1);
});
