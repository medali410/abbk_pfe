/**
 * Auto-test : souscrit puis publie une trame — vérifie la réception sur HiveMQ.
 *   node mqtt_self_test.js
 */
const mqtt = require('mqtt');

const MID = 'MAC-1775750118162';
const TOPIC = `machines/${MID}/telemetry`;
const BROKER = 'mqtt://broker.hivemq.com';

const payload = JSON.stringify({
    machineId: MID,
    name: 'dzli',
    temperature: 37.5,
    rpm: 1500,
    torque: 42,
    tool_wear: 22,
    temp_spread_k: 6,
    metrics: { thermal: 37.5, vibration: 7.0 },
});

const client = mqtt.connect(BROKER);
let received = 0;

client.on('connect', () => {
    console.log('Connecté. Abonnement + publication test...\n');
    client.subscribe(TOPIC, () => {
        setTimeout(() => {
            client.publish(TOPIC, payload);
            console.log('>> Publié sur', TOPIC);
        }, 400);
    });
});

client.on('message', (topic, buf) => {
    received += 1;
    console.log('<< Reçu sur', topic, ':', buf.toString());
    if (received >= 1) {
        console.log('\nOK — les messages MQTT passent bien sur ce topic.');
        client.end();
        process.exit(0);
    }
});

setTimeout(() => {
    console.error('\nÉCHEC — aucun message reçu en 8 s (réseau / broker ?)');
    client.end();
    process.exit(1);
}, 8000);
