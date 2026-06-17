// ================================================================
// ABBK Backend — src/lib/mqtt.js
// ================================================================

const mqtt = require('mqtt');
const telemetryController = require('../controllers/telemetryController');
const { predictMachineRisk, handleAIPrediction } = require('./aiPredictionService');

let client = null;

function initMqtt(io) {
    const brokerUrl = process.env.MQTT_BROKER_URL || 'mqtt://192.168.1.150';
    console.log(`🔌 Connexion au broker MQTT : ${brokerUrl}`);

    client = mqtt.connect(brokerUrl);

    client.on('connect', () => {
        console.log('✅ Connecté au broker MQTT');
        client.subscribe('machines/+/telemetry', (err) => {
            if (err) {
                console.error('❌ Erreur abonnement MQTT:', err);
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

            const topicParts = topic.split('/');
            if (topicParts.length >= 2 && !data.machineId) {
                data.machineId = topicParts[1];
            }

            // 1. Sauvegarder télémétrie
            await telemetryController.saveTelemetry(data);

            // 2. Calcul puissance si absent
            if (data.power === undefined && data.torque !== undefined && data.rpm !== undefined) {
                data.power = parseFloat(data.torque) * parseFloat(data.rpm);
            }

            // 3. Diffusion télémétrie brute Socket.IO
            if (io) {
                io.emit('nouvelle_prediction', data);
                console.log(`⚡ Télémétrie machine ${data.machineId} diffusée`);
            }

            // 4. Appel service IA
            const aiResult = await predictMachineRisk(data.machineId, data);
            console.log(
                `🤖 IA [${data.machineId}] → ` +
                `${aiResult.type_panne} | ` +
                `Risque: ${aiResult.risk_percentage}% | ` +
                `Status: ${aiResult.status}`
            );

            // 5. Sauvegarde + alertes + Socket.IO
            await handleAIPrediction(data.machineId, aiResult, io);

        } catch (err) {
            console.error('❌ Erreur traitement message MQTT:', err.message);
        }
    });

    client.on('error', (err) => {
        console.error('❌ Erreur client MQTT:', err);
    });

    client.on('close', () => {
        console.log('⚠️ Connexion MQTT fermée');
    });

    return client;
}

function publish(topic, payload) {
    if (!client) {
        console.error('❌ Client MQTT non initialisé');
        return false;
    }
    const message = typeof payload === 'string' ? payload : JSON.stringify(payload);
    client.publish(topic, message, { qos: 1 }, (err) => {
        if (err) {
            console.error(`❌ Erreur publication ${topic}:`, err);
        } else {
            console.log(`📡 MQTT publié sur ${topic}`);
        }
    });
    return true;
}

module.exports = { initMqtt, publish };
