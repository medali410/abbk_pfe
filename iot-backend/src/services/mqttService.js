const mqtt = require('mqtt');
const Telemetry = require('../models/Telemetry');
const Machine = require('../models/Machine');
const { checkThresholds } = require('./alertService');
const { analyzeWithAI } = require('./aiService');

const brokerUrl = 'mqtt://broker.emqx.io';
const topic = 'abbk/asus01_9f3a/telemetry';

// Contrôle de fréquence de l'analyse IA (toutes les N messages)
const AI_ANALYSIS_INTERVAL = 5; // Analyser 1 message sur 5 (éviter trop d'appels Groq)
let messageCounter = 0;

const connectMqtt = () => {
    console.log(`[MQTT] Connexion à ${brokerUrl}...`);
    const client = mqtt.connect(brokerUrl);

    client.on('connect', () => {
        console.log(`[MQTT] Connecté au broker avec succès !`);
        client.subscribe(topic, (err) => {
            if (!err) {
                console.log(`[MQTT] Abonné au topic: ${topic}`);
            } else {
                console.error(`[MQTT] Erreur d'abonnement:`, err);
            }
        });
    });

    client.on('message', async (topic, message) => {
        try {
            const data = JSON.parse(message.toString());

            if (!data || !data.machineId || !data.metrics) return;

            // 1. Sauvegarder la télémétrie en base
            const telemetryData = {
                machineId: data.machineId,
                temperature: data.metrics.thermal || 0,
                vibration: data.metrics.vibration || 0,
                powerConsumption: data.metrics.power || 0,
                proximity: data.metrics.ultrasonic || 0,
                metrics: data.metrics,
                createdAt: new Date()
            };
            await Telemetry.create(telemetryData);
            console.log(`[MQTT] Télémétrie sauvegardée pour machine: ${data.machineId} (Temp: ${data.metrics.thermal}°C)`);

            // 2. Récupérer la machine pour avoir ses seuils et paramètres
            const machine = await Machine.findById(data.machineId);
            if (!machine) {
                console.warn(`[MQTT] Machine non trouvée: ${data.machineId}`);
                return;
            }

            // 3. Vérification des seuils (alertes règles classiques) - TOUJOURS
            await checkThresholds(telemetryData, machine);

            // 4. Analyse IA prédictive - intervalles pour limiter les appels API Groq
            messageCounter++;
            if (messageCounter % AI_ANALYSIS_INTERVAL === 0) {
                console.log(`[AI] Déclenchement de l'analyse prédictive (message #${messageCounter})...`);
                // Non-bloquant : on ne attend pas le résultat pour continuer
                analyzeWithAI(data, machine).catch(err =>
                    console.error('[AI] Erreur analyse IA (non-critique):', err.message)
                );
            }

        } catch (error) {
            console.error(`[MQTT] Erreur traitement message:`, error.message);
        }
    });

    client.on('error', (err) => {
        console.error('[MQTT] Erreur de connexion:', err);
    });

    client.on('reconnect', () => {
        console.log('[MQTT] Reconnexion en cours...');
    });
};

module.exports = { connectMqtt };
