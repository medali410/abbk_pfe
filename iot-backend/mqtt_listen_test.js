/**
 * Écoute MQTT (HiveMQ) pour vérifier que l'ESP32 / le simulateur envoie bien des trames.
 *
 *   node mqtt_listen_test.js
 *   node mqtt_listen_test.js MAC-1775750118162
 *
 * Souscrit à :
 *   machines/<ID>/telemetry
 *   machines/+/telemetry   (si ID = "all")
 *   test/machines
 */
const mqtt = require('mqtt');

const MACHINE_ID = process.argv[2] || 'MAC-1775750118162';
const BROKER = 'mqtt://broker.hivemq.com';
const DURATION_MS = Number(process.argv[3] || 45000);

const topics =
    MACHINE_ID === 'all'
        ? ['machines/+/telemetry', 'test/machines']
        : [`machines/${MACHINE_ID}/telemetry`, 'test/machines'];

console.log('Broker:', BROKER);
console.log('Topics:', topics.join(', '));
console.log('Durée:', DURATION_MS / 1000, 's (Ctrl+C pour arrêter avant)\n');

const client = mqtt.connect(BROKER);

let count = 0;
const t0 = Date.now();

client.on('connect', () => {
    topics.forEach((t) => client.subscribe(t, (err) => {
        if (err) console.error('Subscribe', t, err.message);
        else console.log('Abonné:', t);
    }));
});

client.on('message', (topic, buf) => {
    count += 1;
    const raw = buf.toString('utf8');
    let pretty = raw;
    try {
        pretty = JSON.stringify(JSON.parse(raw), null, 0);
    } catch (_) {}
    const elapsed = ((Date.now() - t0) / 1000).toFixed(1);
    console.log(`\n[#${count} +${elapsed}s] topic=${topic}`);
    console.log(pretty);
});

client.on('error', (e) => console.error('MQTT error:', e.message));

setTimeout(() => {
    console.log(`\n--- Fin (${count} message(s) reçu(s)) ---`);
    client.end();
    process.exit(0);
}, DURATION_MS);
