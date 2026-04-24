const mqtt = require('mqtt');

// Configuration identique à l'ESP32
const brokerUrl = 'mqtt://broker.emqx.io:1883';
const topic = 'abbk/asus01_9f3a/telemetry';
const RELAY_URL = 'http://localhost:3001/api/sensor-data';

console.log('🚀 [MQTT-BRIDGE v5.6] Démarrage...');
console.log('📡 Broker: ' + brokerUrl);
console.log('📝 Topic: ' + topic);

const client = mqtt.connect(brokerUrl, {
    clientId: 'BRIDGE_NODE_SERVER_' + Math.random().toString(16).substring(2, 8),
    clean: true,
    connectTimeout: 4000,
    reconnectPeriod: 1000,
});

client.on('connect', () => {
    console.log('✅ Connecté au Broker EMQX (TCP 1883)');
    client.subscribe(topic, (err) => {
        if (!err) console.log('📥 Abonné au flux de telemetry');
        else console.error('❌ Erreur abonnement:', err);
    });
});

client.on('message', async (t, m) => {
    console.log(`\n📩 [MQTT] Message reçu sur ${t}`);
    try {
        const payload = JSON.parse(m.toString());

        if (payload.machines && Array.isArray(payload.machines)) {
            console.log(`📦 Paquet de ${payload.machines.length} machines`);

            for (const machine of payload.machines) {
                const mId = machine.machineId;
                const metrics = machine.metrics || {};

                // Mapping pour server.js / server.py
                const dataToRelay = {
                    machineId: mId,
                    temperature: metrics.thermal,
                    humidity: metrics.humidity,
                    pressure: metrics.pressure,
                    power: metrics.power,
                    torque: metrics.pressure,   // Valeur RÉELLE du capteur pression
                    rpm: metrics.thermal,        // Valeur RÉELLE du capteur température (utilisé comme indicateur)
                    tool_wear: metrics.ultrasonic,
                    machine_type: 'M'
                };

                // Envoi au Relais IA (Port 3001)
                try {
                    const response = await fetch(RELAY_URL, {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify(dataToRelay)
                    });
                    const result = await response.json();
                    console.log(`   🚀 [RELAIS ${mId}] IA: ${result.niveau} (${result.prob_panne}%)`);
                } catch (err) {
                    console.error(`   ❌ [RELAIS ${mId}] Échec serveur 3001:`, err.message);
                }
            }
        }
    } catch (e) {
        console.error('⚠️ Erreur de parsing JSON:', e.message);
        console.log('Contenu brut:', m.toString());
    }
});

client.on('error', (err) => {
    console.error('❌ Erreur MQTT:', err.message);
});

client.on('offline', () => console.log('⚠️ Bridge Offline'));
client.on('reconnect', () => console.log('🔄 Reconnexion au broker...'));
