// ============================================================
//  ABBKA - SYSTÈME COMPLET DE MAINTENANCE PRÉDICTIVE
//  Fichier : predictive-service.js
// ============================================================

const express = require('express');
const cors = require('cors');
const mqtt = require('mqtt');
const { GoogleGenerativeAI } = require('@google/generative-ai');
const mongoose = require('mongoose');
const path = require('path');
require('dotenv').config();

const app = express();
app.use(cors());
app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

// ==================== CONFIGURATION ====================
// Note: Utilisez un fichier .env pour GEMINI_API_KEY
const GEMINI_API_KEY = process.env.GEMINI_API_KEY || 'VOTRE_CLE_API_GEMINI_ICI';
const MQTT_BROKER = process.env.MQTT_BROKER || 'wss://broker.emqx.io:8084/mqtt';
const MQTT_TOPIC = 'abbk/asus01_9f3a/telemetry';
const MONGO_URI = process.env.MONGO_URI || 'mongodb://localhost:27017/abbka';
const PORT = process.env.PORT || 5000;

// ==================== INITIALISATION ====================
const genAI = new GoogleGenerativeAI(GEMINI_API_KEY);
const model = genAI.getGenerativeModel({ model: 'gemini-1.5-flash' });

mongoose.connect(MONGO_URI)
    .then(() => console.log('📦 MongoDB connecté'))
    .catch(err => console.error('MongoDB erreur:', err));

// ==================== SCHEMAS MONGODB ====================

// --- Utilisateurs ---
// --- Transformation globale pour renvoyer 'id' au lieu de '_id' ---
const toJSON = {
    virtuals: true,
    versionKey: false,
    transform: (doc, ret) => {
        ret.id = ret._id.toString();
        return ret;
    }
};

const userSchema = new mongoose.Schema({
    username: { type: String, unique: true, required: true },
    password: String,
    email: String,
    role: { type: String, enum: ['SUPER_ADMIN', 'COMPANY_ADMIN', 'TECHNICIAN'], default: 'TECHNICIAN' },
    phone: String,
    specialite: String, // Pour techniciens
    disponible: { type: Boolean, default: true }, // Pour techniciens
    createdAt: { type: Date, default: Date.now }
});

userSchema.set('toJSON', toJSON);
const User = mongoose.model('User', userSchema);

// --- Machines ---
const machineSchema = new mongoose.Schema({
    machineId: { type: String, unique: true, required: true },
    name: String,
    location: String,
    type: String,
    status: {
        type: String,
        enum: ['RUNNING', 'STOPPED', 'MAINTENANCE', 'ERROR'],
        default: 'STOPPED'
    },
    lastMaintenance: Date,
    createdAt: { type: Date, default: Date.now },
    updatedAt: { type: Date, default: Date.now }
});

machineSchema.set('toJSON', toJSON);
machineSchema.set('toJSON', toJSON);
const Machine = mongoose.model('Machine', machineSchema);

// --- Télémétrie ---
const telemetrySchema = new mongoose.Schema({
    machineId: String,
    metrics: Object,
    security: Object,
    prediction: Object,
    timestamp: { type: Date, default: Date.now },
    cycle: Number
});

telemetrySchema.set('toJSON', toJSON);
telemetrySchema.set('toJSON', toJSON);
const Telemetry = mongoose.model('Telemetry', telemetrySchema);

// --- Prédictions ---
const predictionSchema = new mongoose.Schema({
    machineId: String,
    failure_probability: Number,
    risk_level: String,
    recommended_action: String,
    metrics_snapshot: Object,
    analysis: String,
    timestamp: { type: Date, default: Date.now }
});

const Prediction = mongoose.model('Prediction', predictionSchema);

// --- Interventions (Workflow de maintenance) ---
const interventionSchema = new mongoose.Schema({
    machineId: String,
    machineName: String,
    titre: String,
    description: String,
    priorite: { type: String, enum: ['CRITIQUE', 'HAUTE', 'MOYENNE', 'BASSE'], default: 'MOYENNE' },
    statut: {
        type: String,
        enum: ['EN_ATTENTE', 'ACCEPTEE', 'EN_COURS', 'TERMINEE', 'REFUSEE'],
        default: 'EN_ATTENTE'
    },
    assigneA: { type: mongoose.Schema.Types.ObjectId, ref: 'User' }, // Technicien
    assignePar: { type: mongoose.Schema.Types.ObjectId, ref: 'User' }, // Admin
    dateCreation: { type: Date, default: Date.now },
    dateAcceptation: Date,
    dateTerminaison: Date,
    commentaireTechnicien: String,
    photoAvant: String,
    photoApres: String,
    pieceChangees: [String],
    tempsIntervention: Number, // en minutes
    prediction_id: { type: mongoose.Schema.Types.ObjectId, ref: 'Prediction' }
});

interventionSchema.set('toJSON', toJSON);
interventionSchema.set('toJSON', toJSON);
const Intervention = mongoose.model('Intervention', interventionSchema);

// --- Notifications ---
const notificationSchema = new mongoose.Schema({
    userId: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
    machineId: String,
    type: { type: String, enum: ['INFO', 'WARNING', 'CRITICAL', 'INTERVENTION'], default: 'INFO' },
    titre: String,
    message: String,
    lue: { type: Boolean, default: false },
    interventionId: { type: mongoose.Schema.Types.ObjectId, ref: 'Intervention' },
    createdAt: { type: Date, default: Date.now }
});

notificationSchema.set('toJSON', toJSON);
notificationSchema.set('toJSON', toJSON);
const Notification = mongoose.model('Notification', notificationSchema);

// ==================== VARIABLES GLOBALES ====================
let dataHistory = [];
const MAX_HISTORY = 50;
let liveDataClients = []; // Pour SSE (Server-Sent Events)

// ==================== FONCTION PRÉDICTION IA ====================

async function predictWithGemini(currentData, history) {
    if (!GEMINI_API_KEY || GEMINI_API_KEY === 'VOTRE_CLE_API_GEMINI_ICI') {
        return fallbackPrediction(currentData);
    }

    const prompt = `
Tu es un expert en maintenance prédictive industrielle pour le projet ABBKA.

MACHINE: ${currentData.machineId || 'MAC_A01'}

DONNÉES ACTUELLES DES CAPTEURS:
- Température (thermal): ${currentData.metrics?.thermal || 'N/A'} °C
- Humidité (humidity): ${currentData.metrics?.humidity || 'N/A'} %
- Pression (pressure): ${currentData.metrics?.pressure || 'N/A'} bar
- Puissance (power): ${currentData.metrics?.power || 'N/A'} kW
- Distance ultrasonique: ${currentData.metrics?.ultrasonic || 'N/A'} cm
- Présence (PIR): ${currentData.metrics?.presence || 0}
- Capteur magnétique (capot): ${currentData.metrics?.magnetic || 1}
- Infrarouge: ${currentData.metrics?.infrared || 'N/A'} °C

SEUILS NORMAUX:
- Température: 15-40°C (critique > 40°C)
- Pression: 0-8 bar (critique > 8 bar)
- Puissance: 0-80 kW (critique > 80 kW)
- Distance sécurité: > 30 cm

HISTORIQUE DES ${history.length} DERNIÈRES MESURES:
${JSON.stringify(history.slice(-10).map(h => ({
        thermal: h.metrics?.thermal,
        pressure: h.metrics?.pressure,
        power: h.metrics?.power,
        cycle: h.cycle
    })), null, 2)}

ANALYSE DEMANDÉE:
1. Évalue la probabilité de panne (0-100%)
2. Identifie les tendances dangereuses dans l'historique
3. Détermine le type de panne probable
4. Donne une recommandation de maintenance

RÉPONDS UNIQUEMENT EN JSON VALIDE avec cette structure exacte:
{
  "failure_probability": <nombre entre 0 et 100>,
  "risk_level": "<CRITIQUE|ELEVE|MOYEN|FAIBLE|MINIMAL>",
  "risk_color": "<red|orange|yellow|green>",
  "predicted_failure_type": "<type de panne probable>",
  "time_to_failure": "<estimation du temps avant panne>",
  "recommended_action": "<action recommandée>",
  "anomalies_detected": ["<liste des anomalies>"],
  "trends": {
    "temperature": "<STABLE|MONTANTE|DESCENDANTE|CRITIQUE>",
    "pressure": "<STABLE|MONTANTE|DESCENDANTE|CRITIQUE>",
    "power": "<STABLE|MONTANTE|DESCENDANTE|CRITIQUE>"
  },
  "confidence": <confiance du modèle 0-100>,
  "detailed_analysis": "<explication détaillée en français>"
}
`;

    try {
        const result = await model.generateContent(prompt);
        const response = result.response.text();
        const jsonMatch = response.match(/\{[\s\S]*\}/);
        if (jsonMatch) {
            return JSON.parse(jsonMatch[0]);
        }
        throw new Error('Pas de JSON dans la réponse');
    } catch (error) {
        console.error('❌ Erreur Gemini:', error.message);
        return fallbackPrediction(currentData);
    }
}

function fallbackPrediction(data) {
    const m = data.metrics || {};
    let probability = 0;
    let anomalies = [];

    if (m.thermal > 40) { probability += 30; anomalies.push('Température critique'); }
    if (m.thermal > 35) { probability += 10; anomalies.push('Température élevée'); }
    if (m.pressure > 8) { probability += 25; anomalies.push('Pression excessive'); }
    if (m.pressure > 6) { probability += 10; anomalies.push('Pression élevée'); }
    if (m.power > 80) { probability += 20; anomalies.push('Surcharge électrique'); }
    if (m.power > 60) { probability += 10; anomalies.push('Puissance élevée'); }
    if (m.magnetic === 0) { probability += 15; anomalies.push('Capot ouvert'); }

    probability = Math.min(probability, 100);

    let risk_level, risk_color;
    if (probability > 70) { risk_level = 'CRITIQUE'; risk_color = 'red'; }
    else if (probability > 50) { risk_level = 'ELEVE'; risk_color = 'orange'; }
    else if (probability > 30) { risk_level = 'MOYEN'; risk_color = 'yellow'; }
    else { risk_level = 'FAIBLE'; risk_color = 'green'; }

    return {
        failure_probability: probability,
        risk_level,
        risk_color,
        predicted_failure_type: anomalies[0] || 'Aucune',
        time_to_failure: probability > 50 ? 'Moins de 24h' : 'Plus de 7 jours',
        recommended_action: probability > 50 ? 'Maintenance urgente' : 'Surveillance normale',
        anomalies_detected: anomalies.length > 0 ? anomalies : ['Aucune anomalie'],
        trends: { temperature: 'STABLE', pressure: 'STABLE', power: 'STABLE' },
        confidence: 60,
        detailed_analysis: 'Analyse par règles (Gemini indisponible)',
        source: 'FALLBACK_RULES'
    };
}

// ==================== CONNEXION MQTT ====================

const mqttClient = mqtt.connect(MQTT_BROKER);

mqttClient.on('connect', () => {
    console.log('📡 MQTT connecté à', MQTT_BROKER);
    mqttClient.subscribe(MQTT_TOPIC, (err) => {
        if (!err) console.log('📡 Abonné à:', MQTT_TOPIC);
    });
});

mqttClient.on('message', async (topic, message) => {
    console.log(`📩 [DEBUG] Message MQTT reçu sur le topic: ${topic}`);
    try {
        const data = JSON.parse(message.toString());
        console.log(`\n══════ Données MQTT reçues (Cycle ${data.cycle || '?'}) ══════`);

        dataHistory.push(data);
        if (dataHistory.length > MAX_HISTORY) {
            dataHistory = dataHistory.slice(-MAX_HISTORY);
        }

        // Prédiction IA
        const prediction = await predictWithGemini(data, dataHistory);

        console.log(`  🔮 Probabilité panne: ${prediction.failure_probability}%`);
        console.log(`  ⚠️  Risque: ${prediction.risk_level}`);

        // Sauvegarder télémétrie
        const telemetry = new Telemetry({
            machineId: data.machineId,
            metrics: data.metrics,
            security: data.security,
            prediction: prediction,
            cycle: data.cycle
        });
        await telemetry.save();

        // Sauvegarder prédiction
        const pred = new Prediction({
            machineId: data.machineId,
            failure_probability: prediction.failure_probability,
            risk_level: prediction.risk_level,
            recommended_action: prediction.recommended_action,
            metrics_snapshot: data.metrics,
            analysis: prediction.detailed_analysis
        });
        const savedPrediction = await pred.save();

        // ⭐ CRÉER INTERVENTION AUTOMATIQUE SI RISQUE CRITIQUE
        if (prediction.failure_probability > 70 && prediction.risk_level === 'CRITIQUE') {
            // Vérifier si intervention n'existe pas déjà
            const existingIntervention = await Intervention.findOne({
                machineId: data.machineId,
                statut: { $in: ['EN_ATTENTE', 'ACCEPTEE', 'EN_COURS'] }
            });

            if (!existingIntervention) {
                const machine = await Machine.findOne({ machineId: data.machineId });

                const intervention = new Intervention({
                    machineId: data.machineId,
                    machineName: machine?.name || data.machineId,
                    titre: `Panne ${prediction.risk_level} - ${prediction.predicted_failure_type}`,
                    description: prediction.detailed_analysis,
                    priorite: 'CRITIQUE',
                    statut: 'EN_ATTENTE',
                    prediction_id: savedPrediction._id
                });
                const savedIntervention = await intervention.save();

                // Notifier tous les admins
                const admins = await User.find({ role: 'admin' });
                for (const admin of admins) {
                    await Notification.create({
                        userId: admin._id,
                        machineId: data.machineId,
                        type: 'CRITICAL',
                        titre: `🚨 Intervention Urgente - ${data.machineId}`,
                        message: `${prediction.predicted_failure_type}. Assignez un technicien.`,
                        interventionId: savedIntervention._id
                    });
                }

                console.log('  🔔 Intervention automatique créée');
            }
        }

        // Mettre à jour statut machine
        const newStatus = prediction.risk_level === 'CRITIQUE' ? 'ERROR' : 'RUNNING';
        await Machine.findOneAndUpdate(
            { machineId: data.machineId },
            {
                status: newStatus,
                updatedAt: new Date(),
                $setOnInsert: { machineId: data.machineId, name: data.machineId }
            },
            { upsert: true }
        );

        // Diffuser en temps réel (SSE)
        broadcastLiveData(data.machineId, {
            metrics: data.metrics,
            prediction: prediction,
            timestamp: new Date()
        });

    } catch (error) {
        console.error('❌ Erreur traitement MQTT:', error.message);
    }
});

// ==================== SERVER-SENT EVENTS (Temps Réel) ====================

function broadcastLiveData(machineId, data) {
    liveDataClients.forEach(client => {
        if (client.machineId === machineId) {
            client.res.write(`data: ${JSON.stringify(data)}\n\n`);
        }
    });
}

// ==================== ENDPOINTS API ====================

// ========== AUTHENTIFICATION ==========

app.post('/api/auth/login', async (req, res) => {
    try {
        const { username, password } = req.body;

        // Cherche soit par username, soit par email (car l'UI s'appelle "adresse email")
        let user = await User.findOne({ 
            $or: [
                { username: username },
                { email: username }
            ]
        });

        // Mise à jour forcée pour l'admin si nécessaire
        if (user && user.username === 'admin' && user.role !== 'SUPER_ADMIN') {
            user.role = 'SUPER_ADMIN';
            await user.save();
        }

        // Créer admin par défaut
        if (!user && username === 'admin') {
            user = await User.create({
                username: 'admin',
                password: 'admin',
                email: 'admin@abbka.com',
                role: 'SUPER_ADMIN'
            });
        }

        if (user && user.password === password) {
            res.json({
                success: true,
                user: {
                    id: user._id.toString(),
                    username: user.username,
                    email: user.email,
                    role: user.role,
                    phone: user.phone,
                    specialite: user.specialite
                },
                token: 'demo-token-' + user._id
            });
        } else {
            res.status(401).json({ success: false, message: 'Identifiants incorrects' });
        }
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// ========== GESTION MACHINES ==========

app.get('/api/machines', async (req, res) => {
    try {
        const machines = await Machine.find().sort({ createdAt: -1 });
        res.json(machines);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

app.post('/api/machines', async (req, res) => {
    try {
        const machine = await Machine.findOneAndUpdate(
            { machineId: req.body.machineId },
            { ...req.body, updatedAt: new Date() },
            { upsert: true, new: true }
        );
        res.json(machine);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

app.put('/api/machines/:machineId', async (req, res) => {
    try {
        const machine = await Machine.findOneAndUpdate(
            { machineId: req.params.machineId },
            { ...req.body, updatedAt: new Date() },
            { new: true }
        );
        res.json(machine);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

app.delete('/api/machines/:machineId', async (req, res) => {
    try {
        await Machine.deleteOne({ machineId: req.params.machineId });
        await Telemetry.deleteMany({ machineId: req.params.machineId });
        await Prediction.deleteMany({ machineId: req.params.machineId });
        res.json({ success: true, message: 'Machine supprimée' });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// ========== TELEMETRIE ==========

app.get('/api/telemetry/:machineId', async (req, res) => {
    try {
        const telemetry = await Telemetry.findOne({ machineId: req.params.machineId })
            .sort({ timestamp: -1 });
        if (!telemetry) return res.status(404).json({ error: 'Télémétrie non trouvée' });
        res.json(telemetry);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

app.get('/api/telemetry/:machineId/history', async (req, res) => {
    try {
        const history = await Telemetry.find({ machineId: req.params.machineId })
            .sort({ timestamp: -1 })
            .limit(50);
        res.json(history);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// ========== ALERTES ==========

app.get('/api/alerts', async (req, res) => {
    try {
        const { resolved, machineId } = req.query;
        let query = {};
        if (machineId) query.machineId = machineId;
        if (resolved !== undefined) query.lue = resolved === 'true';
        
        const alerts = await Notification.find(query).sort({ createdAt: -1 });
        res.json(alerts);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

app.post('/api/alerts', async (req, res) => {
    try {
        const alert = await Notification.create(req.body);
        res.json(alert);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

app.put('/api/alerts/:id/resolve', async (req, res) => {
    try {
        const alert = await Notification.findByIdAndUpdate(
            req.params.id,
            { lue: true },
            { new: true }
        );
        res.json(alert);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// ⭐ Démarrer/Arrêter machine (Admin uniquement)
app.post('/api/machines/:machineId/toggle', async (req, res) => {
    try {
        const machine = await Machine.findOne({ machineId: req.params.machineId });

        if (!machine) {
            return res.status(404).json({ error: 'Machine non trouvée' });
        }

        const newStatus = machine.status === 'RUNNING' ? 'STOPPED' : 'RUNNING';

        machine.status = newStatus;
        machine.updatedAt = new Date();
        await machine.save();

        res.json({ success: true, status: newStatus, machine });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// ========== GESTION TECHNICIENS ==========

app.get('/api/techniciens', async (req, res) => {
    try {
        const techniciens = await User.find({ role: 'technicien' })
            .select('-password')
            .sort({ createdAt: -1 });
        res.json(techniciens);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

app.post('/api/techniciens', async (req, res) => {
    try {
        const { username, password, email, phone, specialite } = req.body;

        const existingUser = await User.findOne({ username });
        if (existingUser) {
            return res.status(400).json({ error: 'Nom d\'utilisateur déjà utilisé' });
        }

        const technicien = await User.create({
            username,
            password,
            email,
            phone,
            specialite,
            role: 'technicien',
            disponible: true
        });

        const { password: _, ...technicienData } = technicien.toObject();
        res.json(technicienData);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

app.get('/api/users', async (req, res) => {
    try {
        const techniciens = await User.find({ role: 'technicien' })
            .select('-password')
            .sort({ createdAt: -1 });
        res.json(techniciens);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

app.get('/api/companies', async (req, res) => {
    try {
        res.json([{ id: 'c1', name: 'ABBKA Industries' }]);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

app.delete('/api/techniciens/:id', async (req, res) => {
    try {
        await User.deleteOne({ _id: req.params.id, role: 'technicien' });
        res.json({ success: true, message: 'Technicien supprimé' });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// ========== INTERVENTIONS ==========

app.get('/api/maintenance', async (req, res) => {
    try {
        const { userId, role, statut } = req.query;

        let query = {};

        if (role === 'technicien') {
            query.assigneA = userId;
        }

        if (statut) {
            query.statut = statut;
        }

        const interventions = await Intervention.find(query)
            .populate('assigneA', 'username email phone specialite')
            .populate('assignePar', 'username email')
            .sort({ dateCreation: -1 });

        res.json(interventions);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

app.post('/api/maintenance', async (req, res) => {
    try {
        const intervention = await Intervention.create(req.body);

        // Notifier le technicien assigné
        if (intervention.assigneA) {
            await Notification.create({
                userId: intervention.assigneA,
                machineId: intervention.machineId,
                type: 'INTERVENTION',
                titre: `📋 Nouvelle intervention - ${intervention.machineName}`,
                message: intervention.titre,
                interventionId: intervention._id
            });
        }

        res.json(intervention);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// ⭐ Assigner un technicien
app.post('/api/maintenance/:id/assign', async (req, res) => {
    try {
        const { technicienId, adminId } = req.body;

        const intervention = await Intervention.findByIdAndUpdate(
            req.params.id,
            {
                assigneA: technicienId,
                assignePar: adminId,
                statut: 'EN_ATTENTE'
            },
            { new: true }
        ).populate('assigneA', 'username email phone');

        // Notifier le technicien
        await Notification.create({
            userId: technicienId,
            machineId: intervention.machineId,
            type: 'INTERVENTION',
            titre: `📋 Intervention assignée - ${intervention.machineName}`,
            message: `Vous avez été assigné à: ${intervention.titre}`,
            interventionId: intervention._id
        });

        res.json(intervention);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// ⭐ Technicien accepte l'intervention
app.post('/api/interventions/:id/accept', async (req, res) => {
    try {
        const intervention = await Intervention.findByIdAndUpdate(
            req.params.id,
            {
                statut: 'ACCEPTEE',
                dateAcceptation: new Date()
            },
            { new: true }
        ).populate('assignePar', 'username');

        // Notifier l'admin
        if (intervention.assignePar) {
            await Notification.create({
                userId: intervention.assignePar._id,
                machineId: intervention.machineId,
                type: 'INFO',
                titre: `✅ Intervention acceptée - ${intervention.machineName}`,
                message: `L'intervention "${intervention.titre}" a été acceptée`,
                interventionId: intervention._id
            });
        }

        res.json(intervention);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// ⭐ Technicien refuse l'intervention
app.post('/api/interventions/:id/reject', async (req, res) => {
    try {
        const { raison } = req.body;

        const intervention = await Intervention.findByIdAndUpdate(
            req.params.id,
            {
                statut: 'REFUSEE',
                commentaireTechnicien: raison
            },
            { new: true }
        ).populate('assignePar', 'username');

        // Notifier l'admin
        if (intervention.assignePar) {
            await Notification.create({
                userId: intervention.assignePar._id,
                machineId: intervention.machineId,
                type: 'WARNING',
                titre: `❌ Intervention refusée - ${intervention.machineName}`,
                message: `Raison: ${raison}`,
                interventionId: intervention._id
            });
        }

        res.json(intervention);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// ⭐ Technicien commence l'intervention
app.post('/api/interventions/:id/start', async (req, res) => {
    try {
        const intervention = await Intervention.findByIdAndUpdate(
            req.params.id,
            { statut: 'EN_COURS' },
            { new: true }
        );

        // Mettre machine en maintenance
        await Machine.findOneAndUpdate(
            { machineId: intervention.machineId },
            { status: 'MAINTENANCE', updatedAt: new Date() }
        );

        res.json(intervention);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// ⭐ Technicien termine l'intervention
app.post('/api/interventions/:id/complete', async (req, res) => {
    try {
        const { commentaire, pieceChangees, tempsIntervention } = req.body;

        const intervention = await Intervention.findByIdAndUpdate(
            req.params.id,
            {
                statut: 'TERMINEE',
                dateTerminaison: new Date(),
                commentaireTechnicien: commentaire,
                pieceChangees: pieceChangees || [],
                tempsIntervention: tempsIntervention || 0
            },
            { new: true }
        ).populate('assignePar', 'username');

        // Notifier l'admin
        if (intervention.assignePar) {
            await Notification.create({
                userId: intervention.assignePar._id,
                machineId: intervention.machineId,
                type: 'INFO',
                titre: `✅ Intervention terminée - ${intervention.machineName}`,
                message: `La machine est prête à redémarrer. Commentaire: ${commentaire}`,
                interventionId: intervention._id
            });
        }

        res.json(intervention);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// ⭐ Admin redémarre la machine après réparation
app.post('/api/interventions/:id/restart-machine', async (req, res) => {
    try {
        const intervention = await Intervention.findById(req.params.id);

        if (intervention.statut !== 'TERMINEE') {
            return res.status(400).json({ error: 'Intervention non terminée' });
        }

        const machine = await Machine.findOneAndUpdate(
            { machineId: intervention.machineId },
            {
                status: 'RUNNING',
                lastMaintenance: new Date(),
                updatedAt: new Date()
            },
            { new: true }
        );

        res.json({ success: true, message: 'Machine redémarrée', machine });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// ========== NOTIFICATIONS ==========

app.get('/api/notifications', async (req, res) => {
    try {
        const { userId } = req.query;
        const limit = parseInt(req.query.limit) || 50;

        const query = userId ? { userId } : {};

        const notifications = await Notification.find(query)
            .sort({ createdAt: -1 })
            .limit(limit)
            .populate('interventionId', 'titre machineName statut');

        res.json(notifications);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

app.put('/api/notifications/:id/read', async (req, res) => {
    try {
        const notification = await Notification.findByIdAndUpdate(
            req.params.id,
            { lue: true },
            { new: true }
        );
        res.json(notification);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// ========== DASHBOARD ==========

app.get('/api/dashboard/:machineId', async (req, res) => {
    try {
        const machineId = req.params.machineId;

        const latestTelemetry = await Telemetry.findOne({ machineId })
            .sort({ timestamp: -1 });

        const latestPrediction = await Prediction.findOne({ machineId })
            .sort({ timestamp: -1 });

        const yesterday = new Date(Date.now() - 24 * 60 * 60 * 1000);
        const stats = await Prediction.aggregate([
            { $match: { machineId, timestamp: { $gte: yesterday } } },
            {
                $group: {
                    _id: null,
                    avg_probability: { $avg: '$failure_probability' },
                    max_probability: { $max: '$failure_probability' },
                    total_predictions: { $sum: 1 },
                    critical_count: {
                        $sum: { $cond: [{ $eq: ['$risk_level', 'CRITIQUE'] }, 1, 0] }
                    }
                }
            }
        ]);

        const history = await Prediction.find({ machineId })
            .sort({ timestamp: -1 })
            .limit(50)
            .select('failure_probability risk_level timestamp');

        res.json({
            machineId,
            current: {
                metrics: latestTelemetry?.metrics || {},
                prediction: latestPrediction || {}
            },
            stats_24h: stats[0] || {
                avg_probability: 0,
                max_probability: 0,
                total_predictions: 0,
                critical_count: 0
            },
            history: history.reverse(),
            last_update: latestTelemetry?.timestamp
        });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

app.get('/api/alerts/stats', async (req, res) => {
    try {
        const totalMachines = await Machine.countDocuments();
        const runningMachines = await Machine.countDocuments({ status: 'RUNNING' });
        const criticalAlerts = await Notification.countDocuments({ type: 'CRITICAL', lue: false });

        const recentPredictions = await Prediction.find()
            .sort({ timestamp: -1 })
            .limit(100);

        const avgRisk = recentPredictions.reduce((sum, p) => sum + p.failure_probability, 0) / recentPredictions.length || 0;

        const interventions = await Intervention.countDocuments({ statut: 'EN_ATTENTE' });

        res.json({
            total_machines: totalMachines,
            running_machines: runningMachines,
            stopped_machines: totalMachines - runningMachines,
            critical_alerts: criticalAlerts,
            average_risk: avgRisk.toFixed(1),
            total_predictions_today: recentPredictions.length,
            pending_interventions: interventions
        });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// ⭐ DONNÉES TEMPS RÉEL (Server-Sent Events)
app.get('/api/live/:machineId', (req, res) => {
    res.setHeader('Content-Type', 'text/event-stream');
    res.setHeader('Cache-Control', 'no-cache');
    res.setHeader('Connection', 'keep-alive');

    const clientId = Date.now();
    const client = {
        id: clientId,
        machineId: req.params.machineId,
        res
    };

    liveDataClients.push(client);

    req.on('close', () => {
        liveDataClients = liveDataClients.filter(c => c.id !== clientId);
    });
});

// ========== EXPORT ==========

app.get('/api/export/:machineId', async (req, res) => {
    try {
        const data = await Telemetry.find({ machineId: req.params.machineId })
            .sort({ timestamp: -1 })
            .limit(1000);

        let csv = 'Timestamp,Temperature,Humidity,Pressure,Power,Distance,Prediction,Risk\n';
        data.forEach(d => {
            csv += `${d.timestamp},${d.metrics?.thermal},${d.metrics?.humidity},${d.metrics?.pressure},${d.metrics?.power},${d.metrics?.ultrasonic},${d.prediction?.failure_probability},${d.prediction?.risk_level}\n`;
        });

        res.header('Content-Type', 'text/csv');
        res.attachment(`${req.params.machineId}_export.csv`);
        res.send(csv);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// --- Serve Frontend ---
app.get('/', (req, res) => {
    res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

// ========== HEALTH ==========

app.get('/api/health', (req, res) => {
    res.json({
        status: 'healthy',
        service: 'ABBKA Predictive Maintenance',
        ai_engine: 'Google Gemini 1.5 Flash',
        mqtt_connected: mqttClient.connected,
        data_points_in_memory: dataHistory.length,
        uptime: process.uptime()
    });
});

// ==================== DÉMARRAGE ====================

app.listen(PORT, () => {
    console.log(`
╔════════════════════════════════════════════════╗
║   🚀 ABBKA - SYSTÈME COMPLET                  ║
║                                                ║
║   🌐 API:  http://localhost:${PORT}              ║
║   🧠 IA:   Google Gemini 1.5 Flash            ║
║   📡 MQTT: ${MQTT_BROKER}       ║
║                                                ║
║   Fonctionnalités:                             ║
║   ✅ Gestion machines (CRUD)                  ║
║   ✅ Gestion techniciens                      ║
║   ✅ Workflow d'interventions complet         ║
║   ✅ Notifications temps réel                 ║
║   ✅ Données live (SSE)                       ║
╚════════════════════════════════════════════════╝
  `);
});
