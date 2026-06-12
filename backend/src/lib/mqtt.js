const mqtt = require('mqtt');
const telemetryController = require('../controllers/telemetryController');

let client = null;

function initMqtt(io) {
    const brokerUrl = process.env.MQTT_BROKER_URL || 'mqtt://192.168.1.150';
    console.log(`🔌 Connexion au broker MQTT : ${brokerUrl}`);

    client = mqtt.connect(brokerUrl);

    client.on('connect', () => {
        console.log('✅ Connecté au broker MQTT');
        // S'abonne aux télémétries de toutes les machines
        client.subscribe('machines/+/telemetry', (err) => {
            if (err) {
                console.error('❌ Erreur d\'abonnement au topic MQTT:', err);
            } else {
                console.log('📡 Abonné au topic : machines/+/telemetry');
            }
        });
    });

    client.on('message', async (topic, message) => {
        try {
            const payloadStr = message.toString();
            console.log(`✉️ Message MQTT reçu sur [${topic}]:`, payloadStr);

            const data = JSON.parse(payloadStr);

            // Extraire le machineId depuis le topic si absent du JSON
            // Le topic est "machines/{machineId}/telemetry"
            const topicParts = topic.split('/');
            if (topicParts.length >= 2 && !data.machineId) {
                data.machineId = topicParts[1];
            }

            // Sauvegarde en base de données
            await telemetryController.saveTelemetry(data);

            // Diffusion temps réel via Socket.io
            if (io) {
                if (data.power === undefined && data.torque !== undefined && data.rpm !== undefined) {
                    data.power = parseFloat(data.torque) * parseFloat(data.rpm);
                }
                io.emit('nouvelle_prediction', data);
                console.log(`⚡ Télémétrie de la machine ${data.machineId} diffusée via Socket.io`);
            }

        } catch (err) {
            console.error('❌ Erreur de traitement du message MQTT:', err.message);
        }
    });

    client.on('error', (err) => {
        console.error('❌ Erreur client MQTT:', err);
    });

    client.on('close', () => {
        console.log('⚠️ Connexion au broker MQTT fermée');
    });

    return client;
}

function publish(topic, payload) {
    if (!client) {
        console.error('❌ Impossible de publier : le client MQTT n\'est pas initialisé');
        return false;
    }
    const message = typeof payload === 'string' ? payload : JSON.stringify(payload);
    client.publish(topic, message, { qos: 1 }, (err) => {
        if (err) {
            console.error(`❌ Erreur de publication sur ${topic}:`, err);
        } else {
            console.log(`📡 Message MQTT publié sur ${topic}`);
        }
    });
    return true;
}

module.exports = { initMqtt, publish };

