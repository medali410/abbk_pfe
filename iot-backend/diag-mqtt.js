const mqtt = require('mqtt');
const brokerUrl = 'mqtt://broker.emqx.io';
const topic = '#'; // TOUT

console.log('🔍 [GLOBAL SNIFFER] Écoute de TOUS les messages sur le broker...');
const client = mqtt.connect(brokerUrl);

client.on('connect', () => {
    console.log('✅ Connecté! Observation du trafic...');
    client.subscribe(topic);
});

client.on('message', (t, m) => {
    const msg = m.toString();
    if (msg.includes('machineId') || msg.includes('MAC_') || msg.includes('abbk')) {
        console.log(`\n🎯 TROUVÉ! Topic: ${t}`);
        console.log(`📄 Contenu: ${msg}`);
    }
});

client.on('error', (err) => console.error('❌ Erreur:', err));

setTimeout(() => {
    console.log('\nSTOP Diagnostic après 20s');
    process.exit(0);
}, 20000);
