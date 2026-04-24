const axios = require('axios');
const Alert = require('../models/Alert');

// URL du webhook n8n (AI Analysis)
// En test: utiliser /webhook-test/  |  En production: utiliser /webhook/
const N8N_AI_WEBHOOK = process.env.N8N_AI_WEBHOOK_URL || 'http://127.0.0.1:5678/webhook/ai-motor-analysis';

/**
 * Envoie les données télémétriques au workflow n8n (AI Agent)
 * et traite la réponse de prédiction de panne.
 *
 * @param {Object} data - Données MQTT brutes { machineId, metrics, timestamp }
 * @param {Object} machine - Document Mongoose Machine
 */
async function analyzeWithAI(data, machine) {
    try {
        const payload = {
            machineId: data.machineId,
            machineName: machine.name || data.machineId,
            metrics: data.metrics,
            timestamp: data.timestamp || new Date().toISOString(),
            // Contexte des seuils de la machine pour que l'IA soit plus précise
            thresholds: buildThresholds(machine)
        };

        console.log(`[AI] Envoi des données télémétriques à n8n pour analyse... (Machine: ${data.machineId})`);

        const response = await axios.post(N8N_AI_WEBHOOK, payload, {
            headers: { 'Content-Type': 'application/json' },
            timeout: 15000 // 15 secondes max
        });

        const aiResult = response.data;
        console.log(`[AI] Réponse reçue:`, JSON.stringify(aiResult));

        // Traiter la réponse de l'IA
        await processAIResponse(aiResult, machine);

        return aiResult;

    } catch (error) {
        if (error.code === 'ECONNREFUSED') {
            console.warn('[AI] n8n non joignable (ECONNREFUSED) - analyse IA ignorée');
        } else if (error.response) {
            console.error('[AI] Erreur réponse n8n:', error.response.status, error.response.data);
        } else {
            console.error('[AI] Erreur lors de l\'analyse IA:', error.message);
        }
        return null;
    }
}

/**
 * Traite la réponse JSON de l'AI Agent n8n
 * et crée/met à jour les alertes en base de données.
 */
async function processAIResponse(aiResult, machine) {
    // L'AI Agent n8n retourne généralement un objet texte ou JSON
    // On essaie de parser si c'est une chaîne
    let parsed = aiResult;
    if (typeof aiResult === 'string') {
        try {
            // Chercher un bloc JSON dans le texte
            const jsonMatch = aiResult.match(/\{[\s\S]*\}/);
            if (jsonMatch) parsed = JSON.parse(jsonMatch[0]);
        } catch (e) {
            console.warn('[AI] Impossible de parser la réponse JSON de l\'IA:', aiResult);
            return;
        }
    }

    // Gérer le nouveau format du workflow (où le webhook renvoie directement l'output)
    if (parsed && typeof parsed === 'object') {
        // L'Agent renvoie parfois la réponse dans "output"
        if (parsed.output && typeof parsed.output === 'string') {
            try {
                const jsonMatch = parsed.output.match(/\{[\s\S]*\}/);
                if (jsonMatch) parsed = JSON.parse(jsonMatch[0]);
            } catch (e) {
                console.warn('[AI] Impossible de parser output:', parsed.output);
            }
        } else if (parsed.text && typeof parsed.text === 'string') {
            try {
                const jsonMatch = parsed.text.match(/\{[\s\S]*\}/);
                if (jsonMatch) parsed = JSON.parse(jsonMatch[0]);
            } catch (e) {
                console.warn('[AI] Impossible de parser text:', parsed.text);
            }
        }
    }

    if (!parsed || !parsed.status) {
        console.warn('[AI] Format de réponse IA inattendu, attendu {status:...}. Reçu:', parsed);
        return;
    }

    const { status, predicted_failure, failure_type, time_to_failure, recommendation, confidence } = parsed;

    console.log(`[AI] Analyse complète → Statut: ${status} | Panne prédite: ${predicted_failure} | Confiance: ${confidence}%`);

    // Créer une alerte IA si statut WARNING ou CRITICAL
    if (status === 'WARNING' || status === 'CRITICAL') {
        const severity = status === 'CRITICAL' ? 'HIGH' : 'MEDIUM';
        const message = buildAlertMessage(status, failure_type, time_to_failure, recommendation, confidence);

        // Vérifier s'il y a déjà une alerte IA active
        const existingAIAlert = await Alert.findOne({
            machineId: machine._id,
            type: 'AI_PREDICTION',
            resolved: false
        });

        if (existingAIAlert) {
            // Mettre à jour si sévérité plus élevée ou confiance différente
            if (existingAIAlert.severity !== severity || Math.abs((existingAIAlert.value || 0) - confidence) > 10) {
                existingAIAlert.severity = severity;
                existingAIAlert.message = message;
                existingAIAlert.value = confidence;
                await existingAIAlert.save();
                console.log(`[AI] Alerte IA mise à jour pour machine: ${machine.name}`);
            }
        } else {
            // Créer nouvelle alerte IA
            await Alert.create({
                machineId: machine._id,
                machineName: machine.name,
                severity: severity,
                type: 'AI_PREDICTION',
                message: message,
                value: confidence,
                threshold: 70 // Seuil de confiance minimum
            });
            console.log(`[AI] 🚨 Nouvelle alerte IA créée pour machine: ${machine.name} → ${failure_type}`);
        }
    } else if (status === 'NORMAL') {
        // Résoudre les alertes IA existantes si tout est normal
        await Alert.updateMany(
            { machineId: machine._id, type: 'AI_PREDICTION', resolved: false },
            { resolved: true, resolvedAt: new Date() }
        );
    }
}

/**
 * Construit un message d'alerte lisible depuis les données IA
 */
function buildAlertMessage(status, failure_type, time_to_failure, recommendation, confidence) {
    const prefix = status === 'CRITICAL' ? '🔴 CRITIQUE' : '🟡 AVERTISSEMENT';
    let msg = `${prefix} [IA - ${confidence}% confiance]`;

    if (failure_type) msg += ` - Panne prédite: ${failure_type}`;
    if (time_to_failure) msg += ` dans ${time_to_failure}`;
    if (recommendation) msg += `. Action: ${recommendation}`;

    return msg;
}

/**
 * Construit l'objet de seuils depuis les paramètres machine
 * pour donner du contexte à l'IA
 */
function buildThresholds(machine) {
    if (!machine.parameters || machine.parameters.length === 0) return {};
    const thresholds = {};
    for (const param of machine.parameters) {
        if (param.enabled) {
            thresholds[param.key] = {
                label: param.label,
                unit: param.unit,
                warn: param.warnThreshold,
                critical: param.criticalThreshold
            };
        }
    }
    return thresholds;
}

/**
 * Envoie une question utilisateur à l'agent IA n8n (mode Chat).
 *
 * @param {String} machineId - ID de la machine
 * @param {String} message - Question de l'utilisateur
 * @param {Object} machine - Document Machine pour le contexte
 */
async function chatWithAI(machineId, message, machine) {
    try {
        const payload = {
            type: 'chat', // Distinguer du mode 'analysis' automatique
            machineId: machineId,
            machineName: machine.name || machineId,
            message: message,
            metrics: machine.telemetry?.metrics || {},
            thresholds: buildThresholds(machine)
        };

        console.log(`[AI Chat] Envoi question pour machine: ${machineId}`);

        const response = await axios.post(N8N_AI_WEBHOOK, payload, {
            headers: { 'Content-Type': 'application/json' },
            timeout: 20000 // 20 secondes car l'IA peut être lente à répondre
        });

        // La réponse de l'agent peut être dans .output ou directement l'objet
        const aiResponse = response.data;
        let textResponse = '';

        if (typeof aiResponse === 'string') {
            textResponse = aiResponse;
        } else if (aiResponse.output) {
            textResponse = aiResponse.output;
        } else if (aiResponse.text) {
            textResponse = aiResponse.text;
        } else {
            textResponse = JSON.stringify(aiResponse);
        }

        return {
            text: textResponse,
            timestamp: new Date().toISOString()
        };

    } catch (error) {
        console.error('[AI Chat] Erreur:', error.message);
        throw new Error('L\'IA est indisponible pour le moment.');
    }
}

module.exports = { analyzeWithAI, chatWithAI };
