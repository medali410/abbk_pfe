const mqtt = require('mqtt');
const brokerUrl = 'mqtt://broker.emqx.io';
const topic = 'abbk/test/loopback';

console.log('🔄 [LOOPBACK] Connexion à ' + brokerUrl);
const client = mqtt.connect(brokerUrl);

client.on('connect', () => {
    console.log('✅ Connecté! Abonnement à ' + topic);
    client.subscribe(topic, () => {
        console.log('🚀 Envoi message de test...');
        client.publish(topic, JSON.stringify({ hello: "world", time: Date.now() }));
    });
});

client.on('message', (t, m) => {
    console.log(`\n🎉 SUCCÈS! Message reçu sur ${t}`);
    console.log(`📄 Contenu: ${m.toString()}`);
    process.exit(0);
});

client.on('error', (err) => {
    console.error('❌ Erreur:', err);
    process.exit(1);
});

setTimeout(() => {
    console.log('⏳ Timeout: Aucun message reçu en 10s. Le broker ou le réseau bloque peut-être.');
    process.exit(1);
}, 10000);
