// ============================================================
// server.js - SERVEUR NODE.JS (Port 3001)
// Reçoit les données ESP32 et les RELAIE vers le ML Python
// ============================================================

const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const cors = require('cors');
const path = require('path');
const mqtt = require('mqtt');
const fs = require('fs');

const app = express();
const server = http.createServer(app);
const io = new Server(server, { cors: { origin: "*" } });

const mongoose = require('mongoose');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
require('dotenv').config();

const JWT_SECRET = process.env.JWT_SECRET || 'dali-pfe-dev-secret-change-me';
const JWT_EXPIRES = process.env.JWT_EXPIRES || '7d';

function signAuthToken(payload) {
    return jwt.sign(payload, JWT_SECRET, { expiresIn: JWT_EXPIRES });
}

function readBearerToken(req) {
    const h = req.headers.authorization || req.headers.Authorization || '';
    const m = String(h).match(/^Bearer\s+(.+)$/i);
    return m ? m[1].trim() : null;
}

function verifyAuthToken(req) {
    const t = readBearerToken(req);
    if (!t) return null;
    try {
        return jwt.verify(t, JWT_SECRET);
    } catch {
        return null;
    }
}

function normalizeAuthRole(role) {
    const r = String(role || '').toLowerCase();
    if (r === 'super_admin') return 'superadmin';
    if (r === 'company_admin') return 'admin';
    return r;
}

function requireAuth(req, res, next) {
    const decoded = verifyAuthToken(req);
    if (!decoded) {
        return res.status(401).json({ error: 'Authentification requise' });
    }
    req.auth = { ...decoded, role: normalizeAuthRole(decoded.role) };
    next();
}

function requireSuperAdmin(req, res, next) {
    if (req.auth?.role === 'superadmin') return next();
    return res.status(403).json({ error: 'Action réservée au super administrateur' });
}

function requireFleetManager(req, res, next) {
    const r = req.auth?.role;
    if (r === 'superadmin' || r === 'admin') return next();
    return res.status(403).json({ error: 'Accès refusé' });
}

/** Admin, technicien ou concepteur : actions terrain (arrêt moteur, ordres de maintenance ciblés). */
function requireFieldOperator(req, res, next) {
    const r = req.auth?.role;
    if (r === 'superadmin' || r === 'admin' || r === 'technician' || r === 'conception' || r === 'maintenance') {
        return next();
    }
    return res.status(403).json({ error: 'Accès réservé aux opérateurs terrain' });
}

function normalizeMachineIdsInput(raw) {
    if (raw == null) return undefined;
    if (Array.isArray(raw)) {
        return raw.map((x) => String(x).trim()).filter(Boolean);
    }
    if (typeof raw === 'string') {
        return raw.split(/[,;\s]+/).map((s) => s.trim()).filter(Boolean);
    }
    return undefined;
}

/**
 * Technicien / concepteur : même logique de périmètre (client + liste de machines optionnelle).
 * Liste vide = toutes les machines du client.
 */
async function assertMachineFieldAccess(req, res, machineDoc) {
    if (!machineDoc) {
        res.status(404).json({ error: 'Machine non trouvée' });
        return false;
    }
    const mid = String(machineDoc._id);
    const auth = req.auth;

    if (auth.role === 'superadmin') return true;

    if (auth.role === 'admin') {
        return assertFleetCompanyAccess(req, res, machineDoc.companyId);
    }

    if (auth.role === 'technician') {
        const tech = await Technician.findOne({ technicianId: String(auth.sub) });
        if (!tech) {
            res.status(403).json({ error: 'Technicien introuvable' });
            return false;
        }
        const aliases = await buildCompanyAliasSet(String(tech.companyId));
        if (!aliases.has(String(machineDoc.companyId))) {
            res.status(403).json({ error: 'Accès refusé pour cette machine' });
            return false;
        }
        const ids = (tech.machineIds || []).map(String);
        if (ids.length > 0 && !ids.includes(mid)) {
            res.status(403).json({ error: 'Machine non assignée à ce technicien' });
            return false;
        }
        return true;
    }

    if (auth.role === 'conception') {
        const c = await Concepteur.findById(auth.sub);
        if (!c) {
            res.status(403).json({ error: 'Compte conception invalide' });
            return false;
        }
        if (!c.companyId) {
            res.status(403).json({ error: 'Compte non rattaché à un client (companyId)' });
            return false;
        }
        const aliases = await buildCompanyAliasSet(String(c.companyId));
        if (!aliases.has(String(machineDoc.companyId))) {
            res.status(403).json({ error: 'Accès refusé pour cette machine' });
            return false;
        }
        const ids = (c.machineIds || []).map(String);
        if (ids.length > 0 && !ids.includes(mid)) {
            res.status(403).json({ error: 'Machine non assignée à ce concepteur' });
            return false;
        }
        return true;
    }

    res.status(403).json({ error: 'Accès refusé' });
    return false;
}

async function maintenanceOrdersFilterForAuth(auth) {
    if (auth.role === 'superadmin') return {};
    if (auth.role === 'admin') {
        if (!auth.companyId) return {};
        const aliases = await buildCompanyAliasSet(String(auth.companyId));
        return { companyId: { $in: Array.from(aliases) } };
    }
    if (auth.role === 'technician') {
        const tech = await Technician.findOne({ technicianId: String(auth.sub) });
        if (!tech?.companyId) return { _id: null };
        const aliases = await buildCompanyAliasSet(String(tech.companyId));
        return { companyId: { $in: Array.from(aliases) } };
    }
    if (auth.role === 'conception') {
        const c = await Concepteur.findById(auth.sub);
        if (!c?.companyId) return { _id: null };
        const aliases = await buildCompanyAliasSet(String(c.companyId));
        return { companyId: { $in: Array.from(aliases) } };
    }
    if (auth.role === 'maintenance') {
        const m =
            (await MaintenanceAgent.findById(String(auth.sub))) ||
            (await MaintenanceAgent.findOne({ maintenanceAgentId: String(auth.sub) }));
        if (!m?.clientId) return { _id: null };
        const aliases = await buildCompanyAliasSet(String(m.clientId));
        const machineIds = (m.machineIds || []).map(String);
        const base = { companyId: { $in: Array.from(aliases) } };
        if (machineIds.length === 0) return base;
        return { ...base, machineId: { $in: machineIds } };
    }
    return { _id: null };
}

async function assertMaintenanceOrderCompanyAccess(req, res, companyIdStr) {
    if (!companyIdStr) {
        res.status(400).json({ error: 'companyId requis' });
        return false;
    }
    const auth = req.auth;
    if (auth.role === 'superadmin') return true;
    if (auth.role === 'admin') {
        if (!auth.companyId) return true;
        if (!(await companyMatchesAuth(auth, companyIdStr))) {
            res.status(403).json({ error: 'Accès refusé pour ce client' });
            return false;
        }
        return true;
    }
    if (auth.role === 'technician') {
        const tech = await Technician.findOne({ technicianId: String(auth.sub) });
        if (!tech) {
            res.status(403).json({ error: 'Technicien introuvable' });
            return false;
        }
        const aliases = await buildCompanyAliasSet(String(tech.companyId));
        if (!aliases.has(String(companyIdStr))) {
            res.status(403).json({ error: 'Accès refusé pour ce client' });
            return false;
        }
        return true;
    }
    if (auth.role === 'conception') {
        const c = await Concepteur.findById(auth.sub);
        if (!c || !c.companyId) {
            res.status(403).json({ error: 'Compte conception invalide' });
            return false;
        }
        const aliases = await buildCompanyAliasSet(String(c.companyId));
        if (!aliases.has(String(companyIdStr))) {
            res.status(403).json({ error: 'Accès refusé pour ce client' });
            return false;
        }
        return true;
    }
    if (auth.role === 'maintenance') {
        const m =
            (await MaintenanceAgent.findById(String(auth.sub))) ||
            (await MaintenanceAgent.findOne({ maintenanceAgentId: String(auth.sub) }));
        if (!m || !m.clientId) {
            res.status(403).json({ error: 'Compte maintenance invalide' });
            return false;
        }
        const aliases = await buildCompanyAliasSet(String(m.clientId));
        if (!aliases.has(String(companyIdStr))) {
            res.status(403).json({ error: 'Accès refusé pour ce client' });
            return false;
        }
        return true;
    }
    res.status(403).json({ error: 'Accès refusé' });
    return false;
}

function escapeRegExp(s) {
    return String(s).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

async function verifyClientPassword(plain, stored) {
    if (!stored) return false;
    if (stored.startsWith('$2')) {
        return bcrypt.compare(plain, stored);
    }
    return plain === stored;
}

// Modèles Mongoose
const User = require('./src/models/User');
const Company = require('./src/models/Company');
const Machine = require('./src/models/Machine');
const Telemetry = require('./src/models/Telemetry');
const Alert = require('./src/models/Alert');
const Technician = require('./src/models/Technician');
const Client = require('./src/models/Client');
const ChatMessage = require('./src/models/ChatMessage');
const Conception = require('./src/models/Conception');
const Concepteur = require('./src/models/Concepteur');
const MaintenanceOrder = require('./src/models/MaintenanceOrder');
const MaintenanceAgent = require('./src/models/MaintenanceAgent');
const DiagnosticIntervention = require('./src/models/DiagnosticIntervention');
const scenarioService = require('./src/services/scenarioService');

async function applyTechDeltaToOwner(companyId, delta) {
    if (!companyId || !delta) return;
    const id = String(companyId);

    const query = [{ clientId: id }];
    if (mongoose.Types.ObjectId.isValid(id)) query.push({ _id: id });

    await Client.updateMany(
        { $or: query },
        { $inc: { techs: delta } }
    );

    if (mongoose.Types.ObjectId.isValid(id)) {
        await Company.findByIdAndUpdate(id, { $inc: { techs: delta } });
    }
}

async function buildCompanyAliasSet(clientIdParam) {
    const aliases = new Set([String(clientIdParam)]);
    const client = await Client.findOne({ clientId: clientIdParam }) ||
        (mongoose.Types.ObjectId.isValid(clientIdParam) ? await Client.findById(clientIdParam) : null);
    if (client) {
        aliases.add(String(client._id));
        if (client.clientId) aliases.add(String(client.clientId));
        if (client.name) aliases.add(String(client.name));
        return aliases;
    }
    if (mongoose.Types.ObjectId.isValid(clientIdParam)) {
        const company = await Company.findById(clientIdParam);
        if (company) {
            aliases.add(String(company._id));
            if (company.name) aliases.add(String(company.name));
        }
    }
    return aliases;
}

async function companyMatchesAuth(auth, companyKey) {
    if (!companyKey) return false;
    if (auth.role === 'superadmin') return true;
    if (auth.role !== 'admin') return false;
    if (!auth.companyId) return false;
    const aliases = await buildCompanyAliasSet(String(auth.companyId));
    return aliases.has(String(companyKey));
}

async function assertFleetCompanyAccess(req, res, companyKey) {
    if (req.auth.role === 'superadmin') return true;
    if (req.auth.role !== 'admin') {
        res.status(403).json({ error: 'Accès refusé' });
        return false;
    }
    if (!(await companyMatchesAuth(req.auth, companyKey))) {
        res.status(403).json({ error: 'Accès refusé pour cette ressource' });
        return false;
    }
    return true;
}

async function clientWritableByAuth(auth, clientDoc) {
    if (!clientDoc) return false;
    if (auth.role === 'superadmin') return true;
    if (auth.role !== 'admin') return false;
    if (!auth.companyId) return false;
    const aliases = await buildCompanyAliasSet(String(auth.companyId));
    if (clientDoc.clientId && aliases.has(String(clientDoc.clientId))) return true;
    if (clientDoc._id && aliases.has(String(clientDoc._id))) return true;
    return false;
}

/** Même fiche client (ObjectId ou clientId métier). */
function isSameClientDoc(a, b) {
    if (!a || !b) return false;
    if (String(a._id) === String(b._id)) return true;
    const aCid = a.clientId != null ? String(a.clientId) : '';
    const bCid = b.clientId != null ? String(b.clientId) : '';
    if (aCid && bCid && aCid === bCid) return true;
    return false;
}

async function machineCountForCompanyAliases(aliases) {
    return Machine.countDocuments({ companyId: { $in: Array.from(aliases) } });
}

async function validateTechnicianMachineIds(machineIds, companyId) {
    if (!machineIds || !Array.isArray(machineIds) || machineIds.length === 0) {
        return null;
    }
    const aliases = await buildCompanyAliasSet(companyId);
    const machines = await Machine.find({ _id: { $in: machineIds.map(String) } });
    if (machines.length !== machineIds.length) {
        return 'Une ou plusieurs machines sont introuvables';
    }
    for (const m of machines) {
        if (!aliases.has(String(m.companyId))) {
            return 'Chaque machine doit appartenir au client sélectionné';
        }
    }
    return null;
}

async function countOtherTechniciansOnMachine(machineId, excludeTechnicianId) {
    return Technician.countDocuments({
        machineIds: machineId,
        technicianId: { $ne: excludeTechnicianId }
    });
}

/** Réponse API machines = uniquement des documents Mongo valides (id + companyId). */
function serializeMachineDocs(docs) {
    return docs.map((doc) => {
        const o = { ...doc };
        if (o._id != null) o.id = String(o._id);
        delete o._id;
        if (o.__v !== undefined) delete o.__v;
        return o;
    });
}

const machineDbOnlyFilter = {
    _id: { $exists: true, $nin: [null, ''] },
    companyId: { $exists: true, $nin: [null, ''] },
};

function loadCommaList(envKey, defaultStr) {
    return String(process.env[envKey] || defaultStr)
        .split(',')
        .map((s) => s.trim())
        .filter(Boolean);
}

/**
 * Exclut machines de démo / tests (toujours en Mongo mais pas « vos » machines métier).
 * Désactiver : SHOW_DEMO_MACHINES=1
 * Personnaliser : DEMO_COMPANY_IDS=..., DEMO_MACHINE_PREFIXES=...
 */
function filterOutDemoMachinesIfNeeded(docs) {
    if (process.env.SHOW_DEMO_MACHINES === '1') return docs;
    const demoCompanyIds = new Set(loadCommaList('DEMO_COMPANY_IDS', 'CLI-DEMO-001,test_company'));
    const demoPrefixes = loadCommaList('DEMO_MACHINE_PREFIXES', 'MAC-DEMO-,MAC-TEST');
    return docs.filter((doc) => {
        const id = String(doc._id ?? '');
        const cid = String(doc.companyId ?? '');
        if (demoCompanyIds.has(cid)) return false;
        for (const p of demoPrefixes) {
            if (id.startsWith(p)) return false;
        }
        return true;
    });
}

function parseChatRoom(roomId = '') {
    const text = String(roomId);
    if (text.startsWith('chat_')) {
        const [, clientId = '', technicianId = ''] = text.split('_');
        return { type: 'client_technician', clientId, technicianId };
    }
    if (text.startsWith('team_machine_')) {
        return { type: 'machine_team', machineId: text.replace('team_machine_', '') };
    }
    return { type: 'other' };
}

// Connexion MongoDB avec repli local
async function connectToMongo() {
    const atlasUri = process.env.MONGO_URI;
    const localUri = 'mongodb://127.0.0.1:27017/dali_pfe';
    
    if (atlasUri) {
        console.log('⏳ Tentative de connexion à MongoDB Atlas...');
        try {
            await mongoose.connect(atlasUri, { serverSelectionTimeoutMS: 5000 });
            console.log('✅ MongoDB Atlas connecté');
            return true;
        } catch (err) {
            console.error('❌ Échec MongoDB Atlas:', err.message);
        }
    }

    console.log('⏳ Tentative de connexion à MongoDB Local...');
    try {
        await mongoose.connect(localUri, { serverSelectionTimeoutMS: 5000 });
        console.log('✅ MongoDB Local connecté (Repli)');
        return true;
    } catch (err) {
        console.error('❌ Échec MongoDB Local:', err.message);
        return false;
    }
}

connectToMongo().then(async (success) => {
    if (!success) return;
    try {
        await Conception.syncIndexes();
        const db = mongoose.connection.db;
        const names = (await db.listCollections().toArray()).map((c) => c.name);
        if (!names.includes('conceptions')) {
            await Conception.createCollection();
            console.log('[OK] Collection conceptions créée.');
        }
    } catch (e) {
        console.warn('[WARN] Init conceptions:', e.message);
    }
});

app.use(
    cors({
        origin: true,
        credentials: true,
        methods: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'OPTIONS'],
        allowedHeaders: ['Content-Type', 'Authorization', 'Accept'],
    }),
);
app.use(express.json());
// Les fichiers statiques sont enregistrés en fin de fichier pour que toutes les routes /api/* soient prioritaires.

const PORT = 3001;
const ML_SERVER = process.env.ML_SERVER || 'http://localhost:5000';  // Serveur Python ML
const MODEL_METRICS_FILE = process.env.MODEL_METRICS_FILE || '';
const STOP_THRESHOLD = Number(process.env.STOP_THRESHOLD || 75);
const TEMP_CRITICAL = Number(process.env.TEMP_CRITICAL || 85);

const IA_MOTOR_TYPES = new Set(['EL_S', 'EL_M', 'EL_L']);

function normalizeMotorType(raw) {
    const s = String(raw || 'EL_M').trim().toUpperCase();
    if (IA_MOTOR_TYPES.has(s)) return s;
    if (s === 'L' || s === 'LOW' || s === 'PETIT') return 'EL_S';
    if (s === 'M' || s === 'MEDIUM' || s === 'MOYEN') return 'EL_M';
    if (s === 'H' || s === 'HIGH' || s === 'LARGE') return 'EL_L';
    return 'EL_M';
}

async function getMachineMlProfile(machineId) {
    const fallback = { motorType: null, rulHoursPerModelUnit: null };
    if (!machineId) return fallback;
    try {
        const m = await Machine.findById(String(machineId)).select('motorType rulHoursPerModelUnit').lean();
        if (!m) return fallback;
        const scale = m.rulHoursPerModelUnit;
        const n = scale != null ? Number(scale) : null;
        const mt = m.motorType != null && String(m.motorType).trim() !== ''
            ? normalizeMotorType(m.motorType)
            : null;
        return {
            motorType: mt,
            rulHoursPerModelUnit: n != null && n > 0 && Number.isFinite(n) ? n : null,
        };
    } catch (_) {
        return fallback;
    }
}

/** Ajoute heures indicatives (calibration superadmin) + type moteur réellement envoyé au ML. */
function enrichMlResultWithRulHours(mlResult, profile, typeMoteurForMl) {
    if (!mlResult || typeof mlResult !== 'object') return mlResult;
    const raw = Number(mlResult.rul_estime);
    const out = { ...mlResult, type_moteur_ia: typeMoteurForMl || 'EL_M' };
    if (Number.isFinite(raw)) {
        out.rul_estime_modele = raw;
    }
    const scale = profile?.rulHoursPerModelUnit;
    if (Number.isFinite(raw) && scale != null && scale > 0) {
        out.rul_heures_indicatif = Math.round(raw * scale * 10) / 10;
    }
    return out;
}

/**
 * Capteurs affichés = exactement ce que l’ESP envoie (racine + metrics), aligné sur extractSeven pour fallback.
 * Évite les écarts Flutter/Mongo vs JSON MQTT (ex. vibration seulement dans metrics).
 */
function displaySensorsFromPayload(payload, seven) {
    const m = payload.metrics && typeof payload.metrics === 'object' ? payload.metrics : {};
    const pick = (a, b, c) => {
        for (const v of [a, b, c]) {
            if (v !== undefined && v !== null && v !== '') {
                const n = Number(v);
                if (Number.isFinite(n)) return n;
            }
        }
        return null;
    };
    const rpm = pick(payload.rpm, m.rpm, null) ?? 1450;
    const torque = pick(payload.torque, m.torque, null);
    let power = pick(payload.power, m.power, seven.power);
    if (power == null && torque != null && Number.isFinite(torque) && Number.isFinite(rpm)) {
        power = torque * rpm;
    }
    power = power ?? 0;
    return {
        temperature: pick(payload.temperature, m.thermal, seven.thermal) ?? 0,
        vibration: pick(payload.vibration, m.vibration, null) ?? 0,
        pressure: pick(payload.pressure, m.pressure, seven.pressure) ?? 0,
        power,
        friction: pick(payload.friction, m.friction, null) ?? 0,
        ultrasonic: pick(payload.ultrasonic, m.ultrasonic, seven.ultrasonic) ?? 0,
        presence: pick(payload.presence, m.presence, seven.presence) ?? 0,
        magnetic: pick(payload.magnetic, m.magnetic, seven.magnetic) ?? 0,
        infrared: pick(payload.infrared, m.infrared, seven.infrared) ?? 0,
        rpm,
        torque: torque != null && Number.isFinite(torque) ? torque : undefined,
        tool_wear: pick(payload.tool_wear, m.tool_wear, null) ?? undefined,
    };
}

// ============================================================
// STOCKER LES DONNÉES (Plus nécessaire avec MongoDB, mais gardé pour compatibilité immédiate si besoin)
// ============================================================

let machines = {}; 

// ============================================================
// CONFIGURATION MQTT (Broker Public)
// ============================================================

const MQTT_BROKER = "mqtt://broker.hivemq.com";
const MQTT_TOPIC = "test/machines";
// Machine IDs are now validated dynamically from MongoDB (no hardcoded list).
// Any machine created via dashboard, API, or Arduino auto-register is accepted.
const _knownMachineCache = new Set();

const mqttOptions = {
    keepalive: 60,
    reconnectPeriod: 1000,
    clientId: 'backend_server_' + Math.random().toString(16).substring(2, 8)
};

const mqttClient = mqtt.connect(MQTT_BROKER, mqttOptions);

mqttClient.on('connect', () => {
    console.log(`✅ Connecté au Broker MQTT: ${MQTT_BROKER}`);
    const topics = [
        MQTT_TOPIC,
        'machines/+/telemetry',
        'machines/+/status',
    ];
    mqttClient.subscribe(topics, (err) => {
        if (!err) {
            console.log(`📡 Abonné aux topics: ${topics.join(', ')}`);
        }
    });
});

mqttClient.on('reconnect', () => {
    console.log('🔄 Reconnexion au Broker MQTT...');
});

mqttClient.on('error', (err) => {
    console.error('❌ Erreur MQTT:', err.message);
});

mqttClient.on('offline', () => {
    console.log('⚠️ Backend MQTT Offline');
});

mqttClient.on('message', async (topic, message) => {
    // Handle machine status updates (from ESP32 after stop/start)
    const statusMatch = topic.match(/^machines\/(.+)\/status$/);
    if (statusMatch) {
        try {
            if (mongoose.connection.readyState !== 1) return;
            const statusData = JSON.parse(message.toString());
            const statusMachineId = statusMatch[1] || statusData.machineId;
            const newStatus = String(statusData.status || '').toUpperCase();
            if (statusMachineId && (newStatus === 'RUNNING' || newStatus === 'STOPPED')) {
                await Machine.findByIdAndUpdate(statusMachineId, { status: newStatus });
                io.emit('machine_status_update', { machineId: statusMachineId, status: newStatus });
                console.log(`📡 [${statusMachineId}] Statut mis à jour: ${newStatus}`);
            }
        } catch (e) {
            console.error('❌ Erreur parsing statut MQTT:', e.message);
        }
        return;
    }

    // Handle telemetry data (both legacy topic and per-machine topic)
    const telemetryMatch = topic.match(/^machines\/(.+)\/telemetry$/);
    const isTelemetryTopic = topic === MQTT_TOPIC || telemetryMatch;
    if (isTelemetryTopic) {
        let payload;
        try {
            payload = JSON.parse(message.toString());
        } catch (e) {
            payload = { temperature: parseFloat(message.toString()) };
        }

        const mId = telemetryMatch ? telemetryMatch[1] : (payload.machineId || payload.id || 'MAC_UNKNOWN');
        const machineId = String(mId);

        // Accept any machine that exists in MongoDB
        if (!_knownMachineCache.has(machineId)) {
            if (mongoose.connection.readyState === 1) {
                const existsInDb = await Machine.exists({ _id: machineId });
                if (!existsInDb) return;
                _knownMachineCache.add(machineId);
            } else {
                // If DB is down, we allow the machine for real-time relay anyway
                _knownMachineCache.add(machineId);
            }
        }
        
        // --- Layer 1: Rule-based scenario detection ---
        await scenarioService.ensureBootstrap(machineId);
        const seven = scenarioService.extractSevenFromPayload(payload);
        const mlProfile = await getMachineMlProfile(machineId);
        const motorType = normalizeMotorType(mlProfile.motorType || payload.type_moteur || payload.machine_type || 'EL_M');
        const scen = scenarioService.analyzeScenario(machineId, seven, motorType);

        // --- Layer 2: ML prediction (non-blocking) ---
        let mlResult = { prediction: undefined, prob_panne: 0, niveau: 'INCONNU', panne_type: 'Normale' };
        try {
            const mlData = buildMlPayload(payload, machineId, mlProfile);
            mlResult = await envoyerAuML(mlData);
            mlResult = enrichMlResultWithRulHours(mlResult, mlProfile, mlData.type_moteur);
        } catch (mlErr) {
            // ML unavailable — fusion will use rules-only mode
        }

        // --- Layer 3: Fusion ---
        const fused = fusionDecision(scen, mlResult);

        const disp = displaySensorsFromPayload(payload, seven);

        const prediction = {
            machineId: mId,
            zone: payload.zone || payload.locationZone || 'Zone inconnue',
            wifiRssi: payload.wifiRssi ?? null,
            lat: payload.lat ?? payload.latitude ?? null,
            lng: payload.lng ?? payload.longitude ?? null,
            temperature: disp.temperature,
            vibration: disp.vibration,
            friction: disp.friction,
            pressure: disp.pressure,
            power: disp.power,
            ultrasonic: disp.ultrasonic,
            presence: disp.presence,
            magnetic: disp.magnetic,
            infrared: disp.infrared,
            rpm: disp.rpm,
            torque: disp.torque,
            tool_wear: disp.tool_wear,
            timestamp: new Date().toLocaleTimeString(),
            prediction: fused.fusedProbPanne >= 50 ? 1 : 0,
            prob_panne: fused.fusedProbPanne,
            niveau: fused.fusedNiveau,
            panne_type: fused.fusedScenario,
            fusionSources: fused.fusionSources,
            ...scen,
            ml_scenario: mlResult.panne_type,
            ml_prob: mlResult.prob_panne,
            ae_anomaly: fused.aeAnomaly,
            rul_estime: mlResult.rul_estime,
            rul_estime_modele: mlResult.rul_estime_modele,
            rul_heures_indicatif: mlResult.rul_heures_indicatif,
            type_moteur_ia: mlResult.type_moteur_ia,
        };

        // Émettre via WebSockets pour le dashboard Flutter
        io.emit('nouvelle_prediction', prediction);
        console.log(`📡 [${mId}] Fusion: ${fused.fusedNiveau} (${fused.fusedProbPanne}%) [${fused.fusionSources}] | T=${prediction.temperature}°C P=${prediction.pressure}bar W=${prediction.power}kW`);

        // Sauvegarder en base
        try {
            if (mongoose.connection.readyState !== 1) {
                console.warn(`⚠️ [${mId}] DB déconnectée, skip sauvegarde télémétrie`);
                return;
            }
            const telemetry = new Telemetry({
                machineId: mId,
                temperature: prediction.temperature,
                vibration: prediction.vibration,
                metrics: {
                    thermal: prediction.temperature,
                    vibration: prediction.vibration,
                    friction: prediction.friction,
                    pressure: prediction.pressure,
                    power: prediction.power,
                    wifiRssi: prediction.wifiRssi,
                    ultrasonic: prediction.ultrasonic,
                    presence: prediction.presence,
                    magnetic: prediction.magnetic,
                    infrared: prediction.infrared,
                    rpm: prediction.rpm,
                    ...(prediction.torque != null ? { torque: prediction.torque } : {}),
                    ...(prediction.tool_wear != null ? { tool_wear: prediction.tool_wear } : {}),
                    lat: prediction.lat ?? payload.latitude ?? null,
                    lng: prediction.lng ?? payload.longitude ?? null,
                },
                failureScenario: {
                    scenarioCode: scen.scenarioCode,
                    scenarioLabel: scen.scenarioLabel,
                    scenarioProbPanne: fused.fusedProbPanne,
                    scenarioExplanation: scen.scenarioExplanation,
                    basedOnSamples: scen.basedOnSamples,
                    scenarioThermalSeries: scen.scenarioThermalSeries,
                    fusionSources: fused.fusionSources,
                    mlScenario: mlResult.panne_type,
                    aeAnomaly: fused.aeAnomaly,
                },
            });
            await telemetry.save();
            
            // Mise à jour optionnelle du statut (si l'ID existe en base)
            await Machine.findByIdAndUpdate(mId, { status: 'RUNNING' });
        } catch (err) {
            console.error('❌ Erreur sauvegarde MQTT DB:', err.message);
        }
    }
});

// ============================================================
// FONCTION: ENVOYER AU SERVEUR ML PYTHON
// ============================================================

async function envoyerAuML(donnees) {
    try {
        console.log(`[${donnees.machineId || 'ML'}] Relais vers Python...`);

        // Envoyer les données au serveur Python via HTTP POST
        const response = await fetch(ML_SERVER + '/api/predict', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(donnees)
        });
        if (!response.ok) {
            throw new Error(`ML HTTP ${response.status}`);
        }

        const raw = await response.json();
        const probPanne = Number.isFinite(raw.prob_panne)
            ? raw.prob_panne
            : Number.isFinite(raw.panne_probability)
                ? raw.panne_probability * 100
                : Number.isFinite(raw.failure_probability)
                    ? raw.failure_probability
                    : 0;

        return {
            ...raw,
            prediction: raw.prediction !== undefined ? raw.prediction : (probPanne >= 70 ? 1 : 0),
            prob_panne: Math.round(probPanne * 100) / 100,
            niveau: raw.niveau || (probPanne >= 80 ? 'CRITIQUE' : probPanne >= 60 ? 'ELEVE' : probPanne >= 40 ? 'SURVEILLANCE' : 'NORMAL'),
            panne_type: raw.panne_type || raw.scenario_label || raw.predicted_failure_type || 'NORMAL',
            rul_estime: raw.rul_estime ?? raw.rul ?? null,
            confiance: raw.scenario_confidence ?? raw.confidence ?? null,
        };

    } catch (error) {
        console.log('ERREUR connexion ML: ' + error.message);
        return {
            timestamp: new Date().toISOString(),
            prediction: undefined,
            prob_panne: 0,
            niveau: 'INCONNU',
            panne_type: 'Erreur Serveur ML',
            anomalies: ['Check server.py'],
            actions: ['Relancer Python'],
            tendance: 'INCONNU'
        };
    }
}

function buildSafetyDecision(prediction, telemetry = {}) {
    const prob = Number(prediction?.prob_panne || 0);
    const temp = Number(telemetry.temperature ?? telemetry.thermal ?? 0);
    const isCriticalProb = prob >= STOP_THRESHOLD;
    const isCriticalTemp = temp >= TEMP_CRITICAL;
    const shouldStop = isCriticalProb || (prob >= 70 && isCriticalTemp);

    let message = 'Machine stable, surveillance normale.';
    if (shouldStop) {
        message = `ARRET IMMEDIAT RECOMMANDE: risque panne ${prob.toFixed(1)}% (temp ${temp.toFixed(1)}°C).`;
    } else if (prob >= 60) {
        message = `Alerte forte: risque panne ${prob.toFixed(1)}%. Controle technique urgent.`;
    } else if (prob >= 40) {
        message = `Alerte preventive: risque panne ${prob.toFixed(1)}%.`;
    }

    return {
        requires_urgent_check: prob >= 60,
        requires_stop: shouldStop,
        stop_reason: shouldStop ? 'PROBABILITY_THRESHOLD' : null,
        notification_message: message,
        action_recommandee: shouldStop ? 'STOP_MOTEUR' : (prob >= 60 ? 'CONTROLE_URGENT' : 'SURVEILLANCE'),
    };
}

// ============================================================
// FUSION LAYER: Combine rules (Layer 1) + ML (Layer 2) scores
// ============================================================

function fusionDecision(rulesResult, mlResult) {
    const ruleScore  = Number(rulesResult?.scenarioProbPanne || 0);
    const mlProb     = Number(mlResult?.prob_panne || 0);
    const aeAnomaly  = mlResult?.ae_is_anomaly === true;
    const aeScore    = Number(mlResult?.ae_anomaly_score || 0);

    // Weighted fusion: ML model gets higher weight when available, rules as fallback
    const mlAvailable = mlProb > 0 || mlResult?.prediction !== undefined;
    let fusedProb;
    if (mlAvailable) {
        fusedProb = 0.55 * mlProb + 0.35 * ruleScore + (aeAnomaly ? 10 : 0);
    } else {
        fusedProb = ruleScore;
    }
    fusedProb = Math.min(100, Math.max(0, Math.round(fusedProb * 100) / 100));

    const fusedNiveau = fusedProb >= 80 ? 'CRITIQUE'
        : fusedProb >= 60 ? 'ELEVE'
        : fusedProb >= 40 ? 'SURVEILLANCE'
        : 'NORMAL';

    const scenarioLabel = mlResult?.panne_type && mlResult.panne_type !== 'NORMAL'
        ? mlResult.panne_type
        : rulesResult?.scenarioLabel || 'Normal';

    const sources = [];
    if (mlAvailable) sources.push(`ML:${mlProb.toFixed(1)}%`);
    sources.push(`Règles:${ruleScore}%`);
    if (aeAnomaly) sources.push(`Autoencoder:anomalie(${aeScore.toFixed(4)})`);

    return {
        fusedProbPanne: fusedProb,
        fusedNiveau,
        fusedScenario: scenarioLabel,
        fusionSources: sources.join(' + '),
        ruleScore,
        mlProb,
        aeAnomaly,
        aeScore,
    };
}

function buildMlPayload(data, machineId, profile) {
    const metrics = data.metrics || {};
    const rpm = Number(data.rpm ?? metrics.rpm ?? 1500);
    const torque = Number(data.torque ?? metrics.torque ?? 40);
    const hasExplicitAir = data.air_temperature != null || data.airTemperature != null;
    const hasExplicitProcess = data.process_temperature != null || data.processTemperature != null;

    const rawDisplayTemp = Number(
        data.temperature ?? metrics.thermal ?? NaN,
    );
    const looksLikeCelsius = Number.isFinite(rawDisplayTemp) && rawDisplayTemp > -55 && rawDisplayTemp < 145;

    let airTemperature;
    let processTemperature;
    let temperatureForMl;

    if (hasExplicitAir && hasExplicitProcess) {
        airTemperature = Number(data.air_temperature ?? data.airTemperature);
        processTemperature = Number(
            data.process_temperature ?? data.processTemperature ?? data.infrared ?? metrics.infrared ?? (airTemperature + 5),
        );
        temperatureForMl = (airTemperature + processTemperature) / 2;
    } else if (looksLikeCelsius) {
        const baseK = rawDisplayTemp + 273.15;
        const spreadK = Number(data.temp_spread_k ?? 8);
        const spread = Number.isFinite(spreadK) ? Math.min(25, Math.max(3, spreadK)) : 8;
        airTemperature = baseK - spread * 0.35;
        processTemperature = baseK + spread * 0.65;
        temperatureForMl = (airTemperature + processTemperature) / 2;
    } else {
        airTemperature = Number(
            data.air_temperature ?? data.airTemperature ?? data.temperature ?? metrics.thermal ?? 298,
        );
        processTemperature = Number(
            data.process_temperature ?? data.processTemperature ?? data.infrared ?? metrics.infrared ?? (airTemperature + 5),
        );
        temperatureForMl = (airTemperature + processTemperature) / 2;
    }

    const rawPress = Number(data.pressure ?? data.pression ?? metrics.pressure ?? NaN);
    const pressureLooksLikeBar = Number.isFinite(rawPress) && rawPress > 1.2;
    const pression = pressureLooksLikeBar
        ? (torque / Math.max(rpm, 1))
        : Number(data.pressure ?? data.pression ?? metrics.pressure ?? (torque / Math.max(rpm, 1)));

    const rawVib = Number(data.vibration ?? metrics.vibration ?? NaN);
    const vibFromRpm = rpm / 1000;
    let vibrationForMl = vibFromRpm;
    if (Number.isFinite(rawVib)) {
        if (rawVib <= 2.5) {
            vibrationForMl = rawVib;
        } else {
            vibrationForMl = Math.min(4.5, vibFromRpm + rawVib * 0.07);
        }
    }

    const motorFromPayload = data.type_moteur || data.machine_type || data.type;
    const typeMoteur = normalizeMotorType(profile?.motorType || motorFromPayload || 'EL_M');
    return {
        machineId,
        type_moteur: typeMoteur,
        temperature: temperatureForMl,
        pression,
        puissance: Number(data.power ?? data.puissance ?? metrics.power ?? (torque * rpm)),
        vibration: vibrationForMl,
        presence: Number(data.presence ?? metrics.presence ?? 1),
        magnetique: Number(data.magnetic ?? data.magnetique ?? metrics.magnetic ?? 0.6),
        infrarouge: Number(data.infrared ?? data.infrarouge ?? metrics.infrared ?? processTemperature),
        air_temperature: airTemperature,
        process_temperature: processTemperature,
        torque,
        rpm,
        tool_wear: Number(data.tool_wear ?? metrics.tool_wear ?? 50),
    };
}

function resolveModelMetricsPath() {
    const candidates = [
        MODEL_METRICS_FILE,
        path.join(__dirname, '..', 'modele_moteur_ia_inspect', 'models_v3_lstm', 'metrics.json'),
        path.join(__dirname, '..', 'modele_moteur_ia_inspect', 'models_v2_step4', 'metrics.json'),
        path.join(__dirname, '..', 'modele_moteur_ia_inspect', 'models_v2_over', 'metrics.json'),
        path.join(__dirname, '..', 'modele_moteur_ia_inspect', 'models_v2', 'metrics.json'),
    ].filter(Boolean);
    return candidates.find(p => fs.existsSync(p)) || null;
}

// ============================================================
// ROUTE: ESP32 ENVOIE LES DONNÉES (HTTP POST)
// ============================================================

app.post('/api/sensor-data', async function (req, res) {
    let data = req.body;
    let mId = data.machineId || data.id || 'MAC_A01';

    console.log(`>>> DONNEES ESP32 [${mId}] RECUES <<<`);

    // --- Layer 1: Rule-based scenario ---
    await scenarioService.ensureBootstrap(mId);
    const sensorSeven = scenarioService.extractSevenFromPayload(data);
    const httpProfile = await getMachineMlProfile(mId);
    const httpMotorType = normalizeMotorType(httpProfile.motorType || data.type_moteur || data.machine_type || data.type || 'EL_M');
    const httpScen = scenarioService.analyzeScenario(mId, sensorSeven, httpMotorType);

    // --- Layer 2: ML prediction ---
    let mlData = buildMlPayload(data, mId, httpProfile);
    let resultML = { prediction: 0, prob_panne: 0, niveau: 'INCONNU', panne_type: 'Normale' };
    try {
        resultML = await envoyerAuML(mlData);
        resultML = enrichMlResultWithRulHours(resultML, httpProfile, mlData.type_moteur);
    } catch (err) {
        console.error(`❌ [${mId}] Erreur ML:`, err.message);
    }

    // --- Layer 3: Fusion ---
    const httpFused = fusionDecision(httpScen, resultML);

    const httpDisp = displaySensorsFromPayload(data, sensorSeven);

    const prediction = {
        ...resultML,
        machineId: mId,
        machine_type: mlData.machine_type,
        rpm: httpDisp.rpm,
        torque: httpDisp.torque,
        tool_wear: httpDisp.tool_wear,
        power: httpDisp.power,
        temperature: httpDisp.temperature,
        vibration: httpDisp.vibration,
        friction: httpDisp.friction,
        pressure: httpDisp.pressure,
        ultrasonic: httpDisp.ultrasonic,
        presence: httpDisp.presence,
        magnetic: httpDisp.magnetic,
        infrared: httpDisp.infrared,
        humidity: data.humidity || data.metrics?.humidity || 50,
        timestamp: new Date().toLocaleTimeString(),
        prob_panne: httpFused.fusedProbPanne,
        niveau: httpFused.fusedNiveau,
        panne_type: httpFused.fusedScenario,
        prediction: httpFused.fusedProbPanne >= 50 ? 1 : 0,
        fusionSources: httpFused.fusionSources,
        scenarioCode: httpScen.scenarioCode,
        scenarioExplanation: httpScen.scenarioExplanation,
        ae_anomaly: httpFused.aeAnomaly,
    };
    const safetyDecision = buildSafetyDecision(prediction, {
        temperature: prediction.temperature,
        thermal: prediction.temperature,
    });
    Object.assign(prediction, safetyDecision);

    // --- SAUVEGARDE MONGODB ---
    try {
        // 1. Enregistrer la télémétrie
        const telemetry = new Telemetry({
            machineId: mId,
            temperature: prediction.temperature,
            vibration: prediction.vibration,
            powerConsumption: prediction.power,
            metrics: {
                thermal: prediction.temperature,
                vibration: prediction.vibration,
                friction: prediction.friction,
                power: prediction.power,
                pressure: prediction.pressure,
                ultrasonic: prediction.ultrasonic,
                presence: prediction.presence,
                magnetic: prediction.magnetic,
                infrared: prediction.infrared,
                rpm: prediction.rpm,
                ...(prediction.torque != null ? { torque: prediction.torque } : {}),
                ...(prediction.tool_wear != null ? { tool_wear: prediction.tool_wear } : {}),
            },
        });
        await telemetry.save();

        // 2. Créer une alerte si panne détectée
        if (prediction.prediction === 1) {
            const alert = new Alert({
                machineId: mId,
                severity: prediction.prob_panne > 80 ? 'HIGH' : 'MEDIUM',
                type: 'AI_PREDICTION',
                message: `Défaut prédit: ${prediction.panne_type} (${prediction.prob_panne}%)`,
                value: prediction.prob_panne
            });
            await alert.save();
            io.emit('alerte_panne', prediction);
        }

        if (prediction.requires_stop) {
            const cmdTopic = `machines/${mId}/cmd`;
            const cmdPayload = JSON.stringify({
                action: 'STOP_MOTOR',
                machineId: mId,
                reason: prediction.stop_reason,
                prob_panne: prediction.prob_panne,
                temperature: prediction.temperature,
                at: new Date().toISOString(),
            });
            mqttClient.publish(cmdTopic, cmdPayload);
            io.emit('machine_stop_command', {
                machineId: mId,
                ...safetyDecision,
                cmd_topic: cmdTopic,
            });
        }

        // 3. Mettre à jour le statut de la machine (si elle existe)
        await Machine.findByIdAndUpdate(mId, { status: 'RUNNING' });

    } catch (dbErr) {
        console.error('❌ Erreur Sauvegarde DB:', dbErr.message);
    }

    // Envoyer au dashboard via WebSocket
    io.emit('nouvelle_prediction', prediction);

    res.json({
        status: 'OK',
        machineId: mId,
        prob_panne: prediction.prob_panne,
        niveau: prediction.niveau
    });
});

// Alias for simulation scripts
app.post('/api/telemetry', async (req, res) => {
    // Redirect to sensor-data logic or just handle it here
    req.url = '/api/sensor-data';
    app.handle(req, res);
});

// ============================================================
// ROUTE: AUTO-ENREGISTREMENT MACHINE (depuis Arduino/ESP32)
// ============================================================

app.post('/api/machines/register', async (req, res) => {
    try {
        const { machineId, name, motorType, companyId, location, firmwareVersion, rulHoursPerModelUnit } = req.body;

        if (!machineId) {
            return res.status(400).json({ error: 'machineId est obligatoire' });
        }

        const existing = await Machine.findById(machineId);
        if (existing) {
            await Machine.findByIdAndUpdate(machineId, {
                status: 'RUNNING',
                ...(firmwareVersion && { firmwareVersion }),
            });
            _knownMachineCache.add(machineId);
            console.log(`📡 Machine ${machineId} reconnectée (${existing.name})`);
            return res.json({
                status: 'already_registered',
                machineId: existing._id,
                name: existing.name,
                motorType: existing.motorType,
            });
        }

        if (!companyId) {
            return res.status(400).json({
                error: 'companyId est obligatoire pour la première inscription'
            });
        }

        const rulScale = rulHoursPerModelUnit != null && rulHoursPerModelUnit !== ''
            ? Number(rulHoursPerModelUnit)
            : null;
        const machine = new Machine({
            _id: machineId,
            name: name || `Machine ${machineId}`,
            motorType: normalizeMotorType(motorType || 'EL_M'),
            rulHoursPerModelUnit: Number.isFinite(rulScale) && rulScale > 0 ? rulScale : null,
            companyId,
            location: location || '',
            registeredVia: 'arduino',
            firmwareVersion: firmwareVersion || '',
            status: 'RUNNING',
        });
        await machine.save();
        _knownMachineCache.add(machineId);

        try {
            await Client.findOneAndUpdate(
                { $or: [{ clientId: companyId }, { _id: companyId }] },
                { $inc: { machines: 1 } }
            );
        } catch (_) { /* client may not exist yet */ }

        console.log(`✅ Nouvelle machine enregistrée via Arduino: ${machineId} (${machine.name})`);
        io.emit('machine_registered', { machineId, name: machine.name, motorType: machine.motorType });

        res.status(201).json({
            status: 'registered',
            machineId: machine._id,
            name: machine.name,
            motorType: machine.motorType,
        });
    } catch (err) {
        console.error('Erreur enregistrement machine:', err.message);
        res.status(500).json({ error: err.message });
    }
});

app.get('/api/machines/:id/info', async (req, res) => {
    try {
        const machine = await Machine.findById(req.params.id);
        if (!machine) return res.status(404).json({ error: 'Machine non trouvée' });
        res.json({
            machineId: machine._id,
            name: machine.name,
            motorType: machine.motorType,
            rulHoursPerModelUnit: machine.rulHoursPerModelUnit ?? null,
            status: machine.status,
            companyId: machine.companyId,
            parameters: machine.parameters,
        });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.put('/api/machines/:id', requireAuth, requireFleetManager, async (req, res) => {
    try {
        const id = String(req.params.id);
        const machine = await Machine.findById(id);
        if (!machine) return res.status(404).json({ error: 'Machine non trouvée' });
        if (!(await assertFleetCompanyAccess(req, res, machine.companyId))) return;

        const patch = {};
        if (Object.prototype.hasOwnProperty.call(req.body, 'motorType')) {
            patch.motorType = normalizeMotorType(req.body.motorType);
        }
        if (Object.prototype.hasOwnProperty.call(req.body, 'rulHoursPerModelUnit')) {
            const v = req.body.rulHoursPerModelUnit;
            if (v === null || v === '' || v === undefined) {
                patch.rulHoursPerModelUnit = null;
            } else {
                const n = Number(v);
                patch.rulHoursPerModelUnit = Number.isFinite(n) && n > 0 ? n : null;
            }
        }

        if (Object.keys(patch).length === 0) {
            return res.status(400).json({ error: 'Aucun champ valide (motorType, rulHoursPerModelUnit)' });
        }

        Object.assign(machine, patch);
        await machine.save();

        res.json({
            machineId: machine._id,
            name: machine.name,
            motorType: machine.motorType,
            rulHoursPerModelUnit: machine.rulHoursPerModelUnit ?? null,
            status: machine.status,
        });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// ============================================================
// ROUTE: ARRÊT D'URGENCE MACHINE (depuis l'app Flutter)
// ============================================================

app.delete('/api/machines/:id', requireAuth, requireFleetManager, async (req, res) => {
    try {
        const id = String(req.params.id);
        const machine = await Machine.findById(id);
        if (!machine) {
            return res.status(404).json({ error: 'Machine non trouvée' });
        }
        if (!(await assertFleetCompanyAccess(req, res, machine.companyId))) return;

        const companyId = String(machine.companyId || '');

        await Telemetry.deleteMany({ machineId: id });
        await Alert.deleteMany({ machineId: id });
        await Technician.updateMany({}, { $pull: { machineIds: id } });

        await Machine.findByIdAndDelete(id);
        _knownMachineCache.delete(id);
        if (machines[id]) {
            delete machines[id];
        }

        let updatedClient = await Client.findOneAndUpdate(
            { clientId: companyId },
            { $inc: { machines: -1 } },
            { new: true }
        );
        if (!updatedClient && mongoose.Types.ObjectId.isValid(companyId)) {
            await Client.findByIdAndUpdate(companyId, { $inc: { machines: -1 } });
            await Company.findByIdAndUpdate(companyId, { $inc: { machines: -1 } });
        }
        await Client.updateMany({ machines: { $lt: 0 } }, { $set: { machines: 0 } });
        await Company.updateMany({ machines: { $lt: 0 } }, { $set: { machines: 0 } });

        io.emit('machine_deleted', { machineId: id });
        console.log('Machine supprimee: ' + id);
        res.json({ ok: true, machineId: id });
    } catch (err) {
        console.error('Erreur suppression machine:', err.message);
        res.status(500).json({ error: err.message });
    }
});

app.post('/api/machines/:id/stop', requireAuth, requireFieldOperator, async function (req, res) {
    const machineId = req.params.id;
    const { reason, stoppedBy } = req.body;

    console.log(`🛑 ARRÊT D'URGENCE demandé pour [${machineId}] par ${stoppedBy || 'inconnu'}`);

    try {
        const machinePre = await Machine.findById(machineId);
        if (!machinePre) {
            return res.status(404).json({ error: 'Machine non trouvée' });
        }
        if (!(await assertMachineFieldAccess(req, res, machinePre))) return;

        // 1. Envoyer la commande STOP via MQTT à l'ESP32
        const cmdTopic = `machines/${machineId}/control`;
        const cmdPayload = JSON.stringify({
            action: 'emergency_stop',
            machineId,
            reason: reason || 'Arrêt d\'urgence depuis l\'application',
            stoppedBy: stoppedBy || 'Système',
            at: new Date().toISOString(),
        });
        mqttClient.publish(cmdTopic, cmdPayload, { qos: 1 });

        // 2. Mettre à jour le statut en base de données
        await Machine.findByIdAndUpdate(machineId, { status: 'STOPPED' });

        // 3. Créer une alerte en base
        const alert = new Alert({
            machineId,
            severity: 'CRITICAL',
            type: 'EMERGENCY_STOP',
            message: `Arrêt d'urgence déclenché par ${stoppedBy || 'Système'}. ${reason || ''}`,
            value: 100,
        });
        await alert.save();

        // 4. Notifier tous les clients WebSocket
        io.emit('machine_stop_command', {
            machineId,
            status: 'STOPPED',
            stoppedBy: stoppedBy || 'Système',
            reason,
            at: new Date().toISOString(),
        });

        io.emit('machine_status_update', {
            machineId,
            status: 'STOPPED',
        });

        // 5. Notifier les techniciens assignés
        const machine = machinePre;
        if (machine) {
            const techs = await Technician.find({ machineIds: String(machine._id) });
            for (const t of techs) {
                const roomId = `chat_${machine.companyId}_${t.technicianId}`;
                const msg = {
                    roomId,
                    from: 'system',
                    senderName: 'Système',
                    text: `🛑 ARRÊT D'URGENCE — Machine ${machine.name || machineId} arrêtée par ${stoppedBy || 'Système'}. Raison: ${reason || 'Non spécifiée'}. Intervention sur site requise.`,
                    createdAt: new Date().toISOString(),
                };
                try {
                    await ChatMessage.create({ roomId, from: 'system', senderName: 'Système', text: msg.text });
                } catch (e) { /* ignore */ }
                io.to(roomId).emit('chat_message', msg);
            }
        }

        console.log(`✅ Machine [${machineId}] arrêtée avec succès`);
        res.json({
            status: 'STOPPED',
            machineId,
            stoppedBy,
            message: 'Machine arrêtée avec succès. Commande MQTT envoyée.',
        });
    } catch (err) {
        console.error('❌ Erreur arrêt machine:', err.message);
        res.status(500).json({ error: err.message });
    }
});

// ============================================================
// ROUTE: PREDICTION MANUELLE (depuis le dashboard)
// ============================================================

app.post('/api/predict', async function (req, res) {
    let data = req.body;
    let mId = data.machineId || 'MAC_A01';

    const predProfile = await getMachineMlProfile(mId);
    let mlData = buildMlPayload(data, mId, predProfile);

    let prediction = await envoyerAuML(mlData);
    prediction = enrichMlResultWithRulHours(prediction, predProfile, mlData.type_moteur);
    prediction.machineId = mId;
    Object.assign(prediction, buildSafetyDecision(prediction, {
        temperature: mlData.temperature,
    }));

    if (!machines[mId]) {
        machines[mId] = { historique: [], alertes: [], derniere: null, machineId: mId };
    }

    machines[mId].historique.push(prediction);
    if (machines[mId].historique.length > 100) machines[mId].historique.shift();
    machines[mId].derniere = prediction;

    if (prediction.prediction === 1) {
        machines[mId].alertes.push(prediction);
    }

    io.emit('nouvelle_prediction', prediction);
    res.json(prediction);
});

// ============================================================
// ROUTES: AUTH & CLIENTS (Transition MongoDB)
// ============================================================

function computeMaintenanceLevel(probPanne, machineStatus = '') {
    const status = String(machineStatus || '').toUpperCase();
    if (status === 'STOPPED') {
        return {
            level: 'DANGER',
            color: 'RED',
            recommendation: 'Machine arrêtée: intervention immédiate requise',
        };
    }
    if (status === 'RUNNING') {
        return {
            level: 'NORMAL',
            color: 'GREEN',
            recommendation: 'Machine en marche: surveillance continue',
        };
    }

    const p = Number(probPanne || 0);
    if (p >= 75) {
        return {
            level: 'DANGER',
            color: 'RED',
            recommendation: 'Intervention immédiate recommandée',
        };
    }
    if (p >= 40) {
        return {
            level: 'RISQUE',
            color: 'ORANGE',
            recommendation: 'Planifier une intervention préventive',
        };
    }
    return {
        level: 'NORMAL',
        color: 'GREEN',
        recommendation: 'Continuer la surveillance',
    };
}

app.post('/api/maintenance-login', async (req, res) => {
    try {
        const emailRaw = (req.body?.email || '').toString().trim().toLowerCase();
        const password = String(req.body?.password || '');
        if (!emailRaw || !password) {
            return res.status(400).json({ error: 'Email et mot de passe requis' });
        }

        const agent = await MaintenanceAgent.findOne({ email: emailRaw });
        if (!agent) {
            return res.status(401).json({ message: 'Identifiants invalides' });
        }
        const ok = await verifyClientPassword(password, agent.password);
        if (!ok) {
            return res.status(401).json({ message: 'Identifiants invalides' });
        }
        if (agent.password && !agent.password.startsWith('$2')) {
            bcrypt.hash(password, 10).then((hash) => {
                MaintenanceAgent.updateOne({ _id: agent._id }, { $set: { password: hash } }).catch(() => {});
            });
        }

        const out = agent.toObject({ virtuals: true });
        out.id = String(agent._id);
        delete out._id;
        delete out.__v;
        delete out.password;
        out.role = 'maintenance';
        out.token = signAuthToken({
            sub: String(agent._id),
            role: 'maintenance',
            companyId: String(agent.clientId || ''),
        });
        return res.json(out);
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
});

app.post('/api/login', async (req, res) => {
    const { email, password } = req.body;
    try {
        const emailRaw = (email || '').toString();
        const emailTrim = emailRaw.trim();
        const emailNorm = emailTrim.toLowerCase();

        // 1. Chercher dans la collection User — email (insensible à la casse) OU nom d’utilisateur (ex. admin / admin)
        let user = await User.findOne({ email: emailNorm })
            || await User.findOne({ email: emailTrim })
            || (emailTrim ? await User.findOne({ username: emailTrim }) : null)
            || (emailNorm ? await User.findOne({ username: emailNorm }) : null);

        if (user) {
            const ok = await verifyClientPassword(password, user.password);
            if (!ok) {
                return res.status(401).json({ message: 'Identifiants invalides' });
            }
            if (user.password && !user.password.startsWith('$2')) {
                bcrypt.hash(password, 10).then((hash) => {
                    User.updateOne({ _id: user._id }, { $set: { password: hash } }).catch(() => {});
                });
            }
            
            const responseData = user.toJSON();
            let role = responseData.role ? responseData.role.toLowerCase() : 'technician';
            if (role === 'super_admin') role = 'superadmin';
            if (role === 'company_admin') role = 'admin';
            responseData.role = role;
            responseData.id = user._id.toString();
            responseData.token = signAuthToken({
                sub: user._id.toString(),
                role,
                companyId: user.companyId ? String(user.companyId) : undefined,
            });
            return res.json(responseData);
        }

        // 1b. Concepteur (collection `concepteurs`) — distinct des documents [Conception] et des [Technician]
        let concepteur =
            (await Concepteur.findOne({ email: emailNorm })) ||
            (await Concepteur.findOne({ email: emailTrim })) ||
            (emailTrim ? await Concepteur.findOne({ username: emailTrim }) : null) ||
            (emailNorm ? await Concepteur.findOne({ username: emailNorm }) : null);
        if (concepteur) {
            const okC = await verifyClientPassword(password, concepteur.password);
            if (!okC) {
                return res.status(401).json({ message: 'Identifiants invalides' });
            }
            if (concepteur.password && !concepteur.password.startsWith('$2')) {
                bcrypt.hash(password, 10).then((hash) => {
                    Concepteur.updateOne({ _id: concepteur._id }, { $set: { password: hash } }).catch(() => {});
                });
            }
            const responseData = serializeConcepteurUser(concepteur);
            responseData.machineIds = concepteur.machineIds || [];
            const emailNormC = concepteur.email ? String(concepteur.email).toLowerCase().trim() : '';
            const userNormC = concepteur.username ? String(concepteur.username).trim() : '';
            responseData.token = signAuthToken({
                sub: concepteur._id.toString(),
                role: 'conception',
                companyId: concepteur.companyId ? String(concepteur.companyId) : undefined,
                /** Repli /api/conception/workspace si sub ne matche plus (token ancien, reset DB). */
                cMail: emailNormC || undefined,
                cUser: userNormC || undefined,
            });
            return res.json(responseData);
        }

        // 2. & 3. Client et/ou technicien (même email autorisé si le technicien est rattaché à ce client)
        let client = await Client.findOne({ email: emailNorm });
        if (!client && emailTrim) {
            client = await Client.findOne({
                email: new RegExp(`^${escapeRegExp(emailTrim)}$`, 'i')
            });
        }
        let technician = await Technician.findOne({ email: emailNorm });
        if (!technician && emailTrim) {
            technician = await Technician.findOne({
                email: new RegExp(`^${escapeRegExp(emailTrim)}$`, 'i')
            });
        }
        let maintenanceAgent = await MaintenanceAgent.findOne({ email: emailNorm });
        if (!maintenanceAgent && emailTrim) {
            maintenanceAgent = await MaintenanceAgent.findOne({
                email: new RegExp(`^${escapeRegExp(emailTrim)}$`, 'i')
            });
        }

        if (client) {
            const okC = await verifyClientPassword(password, client.password);
            if (okC) {
                if (client.password && !client.password.startsWith('$2')) {
                    bcrypt.hash(password, 10).then((hash) => {
                        Client.updateOne({ _id: client._id }, { $set: { password: hash } }).catch(() => {});
                    });
                }
                const responseData = client.toJSON();
                responseData.role = 'client';
                responseData.clientId = client.clientId;
                responseData.id = client._id.toString();
                responseData.name = client.name;
                responseData.token = signAuthToken({
                    sub: client._id.toString(),
                    role: 'client',
                    clientId: client.clientId ? String(client.clientId) : undefined,
                });
                return res.json(responseData);
            }
        }

        if (technician) {
            const okT = await verifyClientPassword(password, technician.password);
            if (okT) {
                if (technician.password && !technician.password.startsWith('$2')) {
                    bcrypt.hash(password, 10).then((hash) => {
                        Technician.updateOne({ _id: technician._id }, { $set: { password: hash } }).catch(() => {});
                    });
                }
                const responseData = technician.toJSON();
                responseData.role = 'technician';
                responseData.technicianId = technician.technicianId;
                responseData.id = technician.technicianId;
                responseData.name = technician.name;
                responseData.email = technician.email;
                responseData.companyId = technician.companyId;
                responseData.machineIds = technician.machineIds || [];
                responseData.token = signAuthToken({
                    sub: String(technician.technicianId || technician._id),
                    role: 'technician',
                    companyId: technician.companyId ? String(technician.companyId) : undefined,
                });
                return res.json(responseData);
            }
        }

        if (maintenanceAgent) {
            const okM = await verifyClientPassword(password, maintenanceAgent.password);
            if (okM) {
                if (maintenanceAgent.password && !maintenanceAgent.password.startsWith('$2')) {
                    bcrypt.hash(password, 10).then((hash) => {
                        MaintenanceAgent.updateOne({ _id: maintenanceAgent._id }, { $set: { password: hash } }).catch(() => {});
                    });
                }
                const responseData = maintenanceAgent.toJSON();
                responseData.role = 'maintenance';
                responseData.maintenanceAgentId = maintenanceAgent.maintenanceAgentId;
                responseData.id = maintenanceAgent.maintenanceAgentId || maintenanceAgent._id.toString();
                responseData.name = `${maintenanceAgent.firstName || ''} ${maintenanceAgent.lastName || ''}`.trim();
                responseData.email = maintenanceAgent.email;
                responseData.companyId = maintenanceAgent.clientId;
                responseData.machineIds = maintenanceAgent.machineIds || [];
                responseData.token = signAuthToken({
                    sub: String(maintenanceAgent._id),
                    role: 'maintenance',
                    companyId: maintenanceAgent.clientId ? String(maintenanceAgent.clientId) : undefined,
                });
                return res.json(responseData);
            }
        }

        if (client || technician || maintenanceAgent) {
            return res.status(401).json({ message: 'Identifiants invalides' });
        }

        return res.status(401).json({ message: 'Identifiants invalides' });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.get('/api/maintenance/workspace', requireAuth, async (req, res) => {
    try {
        if (req.auth.role !== 'maintenance') {
            return res.status(403).json({ error: 'Accès réservé au compte maintenance' });
        }
        const agent =
            (await MaintenanceAgent.findById(String(req.auth.sub)).lean()) ||
            (await MaintenanceAgent.findOne({ maintenanceAgentId: String(req.auth.sub) }).lean());
        if (!agent) {
            return res.status(404).json({ error: 'Compte maintenance introuvable' });
        }

        const machineIds = (agent.machineIds || []).map(String);
        let machineDocs = [];
        if (machineIds.length > 0) {
            machineDocs = await Machine.find({ _id: { $in: machineIds } })
                .select('_id name companyId status maintenanceControlActive maintenanceControlBy maintenanceControlStartedAt maintenanceControlEndsAt')
                .lean();
        } else if (agent.clientId) {
            machineDocs = await Machine.find({ companyId: String(agent.clientId) })
                .select('_id name companyId status maintenanceControlActive maintenanceControlBy maintenanceControlStartedAt maintenanceControlEndsAt')
                .lean();
        }

        const rows = [];
        for (const m of machineDocs) {
            const mid = String(m._id);
            const last = await Telemetry.findOne({ machineId: mid }).sort({ createdAt: -1 }).lean();
            const scenarioProb = Number(last?.failureScenario?.scenarioProbPanne || 0);
            const probPanne = Math.max(0, Math.min(100, scenarioProb));
            const lvl = computeMaintenanceLevel(probPanne, m.status);
            rows.push({
                machineId: mid,
                machineName: m.name || mid,
                companyId: String(m.companyId || ''),
                status: String(m.status || ''),
                probPanne,
                level: lvl.level,
                color: lvl.color,
                recommendation: lvl.recommendation,
                maintenanceControlActive: Boolean(m.maintenanceControlActive),
                maintenanceControlBy: String(m.maintenanceControlBy || ''),
                maintenanceControlStartedAt: m.maintenanceControlStartedAt || null,
                maintenanceControlEndsAt: m.maintenanceControlEndsAt || null,
                updatedAt: last?.createdAt || null,
                metrics: last?.metrics || {},
                failureScenario: last?.failureScenario || null,
            });
        }
        rows.sort((a, b) => Number(b.probPanne || 0) - Number(a.probPanne || 0));

        return res.json({
            agent: {
                id: String(agent._id),
                maintenanceAgentId: agent.maintenanceAgentId || '',
                firstName: agent.firstName || '',
                lastName: agent.lastName || '',
                fullName: `${agent.firstName || ''} ${agent.lastName || ''}`.trim(),
                email: agent.email || '',
                clientId: String(agent.clientId || ''),
            },
            machines: rows,
        });
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
});

app.post('/api/machines/:id/maintenance-control', requireAuth, async (req, res) => {
    try {
        if (req.auth?.role !== 'maintenance') {
            return res.status(403).json({ error: 'Action réservée au compte maintenance' });
        }

        const machineId = String(req.params.id || '').trim();
        if (!machineId) {
            return res.status(400).json({ error: 'machineId requis' });
        }

        const agent =
            (await MaintenanceAgent.findById(String(req.auth.sub)).lean()) ||
            (await MaintenanceAgent.findOne({ maintenanceAgentId: String(req.auth.sub) }).lean());
        if (!agent) {
            return res.status(404).json({ error: 'Compte maintenance introuvable' });
        }

        const machine = await Machine.findById(machineId);
        if (!machine) {
            return res.status(404).json({ error: 'Machine non trouvée' });
        }

        const aliases = await buildCompanyAliasSet(String(agent.clientId || ''));
        if (!aliases.has(String(machine.companyId || ''))) {
            return res.status(403).json({ error: 'Machine hors périmètre de ce compte maintenance' });
        }

        const assignedIds = (agent.machineIds || []).map(String);
        if (assignedIds.length > 0 && !assignedIds.includes(machineId)) {
            return res.status(403).json({ error: 'Machine non assignée à ce compte maintenance' });
        }

        const now = new Date();
        const fullName = `${agent.firstName || ''} ${agent.lastName || ''}`.trim() || 'Maintenance Agent';

        machine.maintenanceControlActive = true;
        machine.maintenanceControlBy = fullName;
        machine.maintenanceControlById = String(agent.maintenanceAgentId || agent._id || '');
        machine.maintenanceControlStartedAt = now;
        machine.maintenanceControlEndsAt = null;
        await machine.save();

        return res.json({
            machineId,
            maintenanceControlActive: true,
            maintenanceControlBy: machine.maintenanceControlBy,
            maintenanceControlStartedAt: machine.maintenanceControlStartedAt,
            maintenanceControlEndsAt: machine.maintenanceControlEndsAt,
            message: 'Prise en charge maintenance enregistrée',
        });
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
});

app.post('/api/machines/:id/maintenance-control/finish', requireAuth, async (req, res) => {
    try {
        if (req.auth?.role !== 'maintenance') {
            return res.status(403).json({ error: 'Action réservée au compte maintenance' });
        }

        const machineId = String(req.params.id || '').trim();
        if (!machineId) {
            return res.status(400).json({ error: 'machineId requis' });
        }

        const agent =
            (await MaintenanceAgent.findById(String(req.auth.sub)).lean()) ||
            (await MaintenanceAgent.findOne({ maintenanceAgentId: String(req.auth.sub) }).lean());
        if (!agent) {
            return res.status(404).json({ error: 'Compte maintenance introuvable' });
        }

        const machine = await Machine.findById(machineId);
        if (!machine) {
            return res.status(404).json({ error: 'Machine non trouvée' });
        }

        const aliases = await buildCompanyAliasSet(String(agent.clientId || ''));
        if (!aliases.has(String(machine.companyId || ''))) {
            return res.status(403).json({ error: 'Machine hors périmètre de ce compte maintenance' });
        }

        machine.maintenanceControlActive = false;
        machine.maintenanceControlBy = '';
        machine.maintenanceControlById = '';
        machine.maintenanceControlStartedAt = null;
        machine.maintenanceControlEndsAt = null;
        await machine.save();

        return res.json({
            machineId,
            maintenanceControlActive: false,
            message: 'Contrôle maintenance terminé',
        });
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
});

// ============================================================
// ROUTES: CONCEPTIONS (documents CAO / schémas)
// ============================================================

const CONCEPTION_DOC_TYPES = new Set(['Plan mécanique', 'Schéma électrique', 'Rapport technique', 'Manuel maintenance']);
const DIAGNOSTIC_SCENARIOS = {
    ELECTRICAL: {
        label: 'Panne électrique',
        steps: [
            'Contrôler capteurs puissance et température',
            'Vérifier courant et connexions armoire',
            'Confirmer défaut électrique réel ou capteur',
        ],
    },
    THERMAL: {
        label: 'Surchauffe thermique',
        steps: [
            'Contrôler capteurs température (principal + redondance)',
            'Vérifier ventilation / refroidissement',
            'Valider surcharge ou défaut capteur',
        ],
    },
    VIBRATION: {
        label: 'Anomalie vibratoire',
        steps: [
            'Contrôler capteur vibration et fixation',
            'Vérifier alignement / roulements',
            'Décider défaut mécanique réel ou capteur',
        ],
    },
    PRESSURE: {
        label: 'Anomalie pression/process',
        steps: [
            'Vérifier capteur pression et câblage',
            'Contrôler fuite/obstruction du circuit',
            'Valider origine process ou défaut capteur',
        ],
    },
    SENSOR_COMM: {
        label: 'Capteur / communication',
        steps: [
            'Contrôler alimentation et communication capteur',
            'Tester cohérence des valeurs remontées',
            'Recaler ou remplacer capteur si nécessaire',
        ],
    },
};

app.get('/api/conceptions', requireAuth, requireFleetManager, async (req, res) => {
    try {
        const docs = await Conception.find().sort({ updatedAt: -1 }).lean();
        for (const d of docs) {
            d.id = String(d._id);
            delete d._id;
            delete d.password;
            if (d.company) {
                const co = await Company.findById(d.company).select('name').lean();
                d.company = co ? { _id: d.company, name: co.name } : null;
            }
            if (d.clientId) {
                const cl = await Client.findOne({ clientId: d.clientId })
                    || (mongoose.Types.ObjectId.isValid(d.clientId) ? await Client.findById(d.clientId) : null);
                if (cl) d.clientName = cl.name;
            }
        }
        res.set('Cache-Control', 'no-store');
        res.json(docs);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.post('/api/conceptions', requireAuth, requireFleetManager, async (req, res) => {
    try {
        const name = String(req.body.name || '').trim();
        const version = String(req.body.version || 'v1.0').trim();
        const documentType = String(req.body.documentType || '').trim();
        const clientIdParam = req.body.clientId != null ? String(req.body.clientId).trim() : '';
        const securityEmail = req.body.securityEmail ? String(req.body.securityEmail).trim().toLowerCase() : '';
        const passwordPlain = req.body.password != null ? String(req.body.password) : '';
        const fileName = req.body.fileName ? String(req.body.fileName).trim() : '';
        const fileSize = req.body.fileSize ? String(req.body.fileSize).trim() : '';

        if (!name) {
            return res.status(400).json({ error: 'Nom du document obligatoire' });
        }
        if (!CONCEPTION_DOC_TYPES.has(documentType)) {
            return res.status(400).json({ error: 'Type de document invalide' });
        }
        if (!clientIdParam) {
            return res.status(400).json({ error: 'Vous devez sélectionner un client (pilote des machines)' });
        }

        const client = await Client.findOne({ clientId: clientIdParam })
            || (mongoose.Types.ObjectId.isValid(clientIdParam) ? await Client.findById(clientIdParam) : null);
        if (!client) {
            return res.status(400).json({ error: 'Client introuvable' });
        }

        let companyRef = null;
        if (mongoose.Types.ObjectId.isValid(String(client._id))) {
            const co = await Company.findById(client._id);
            if (co) companyRef = co._id;
        }

        const assignedClientId = client.clientId ? String(client.clientId) : String(client._id);

        let secPass;
        if (passwordPlain && passwordPlain.length > 0) {
            secPass = await bcrypt.hash(passwordPlain, 10);
        }

        const doc = new Conception({
            name,
            version: version || 'v1.0',
            documentType,
            company: companyRef || undefined,
            clientId: assignedClientId,
            securityEmail: securityEmail || undefined,
            password: secPass,
            status: 'BROUILLON',
            fileName: fileName || undefined,
            fileSize: fileSize || undefined,
        });
        await doc.save();

        const out = {
            id: String(doc._id),
            name: doc.name,
            version: doc.version,
            documentType: doc.documentType,
            clientId: doc.clientId,
            clientName: client.name,
            status: doc.status,
            securityEmail: doc.securityEmail || null,
            fileName: doc.fileName || null,
            fileSize: doc.fileSize || null,
        };
        res.status(201).json(out);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// ============================================================
// ROUTES: MAINTENANCE (ordres) & CONCEPTEURS (collection `concepteurs`)
// ============================================================

app.get('/api/maintenance-orders', requireAuth, requireFieldOperator, async (req, res) => {
    try {
        const filter = await maintenanceOrdersFilterForAuth(req.auth);
        const orders = await MaintenanceOrder.find(filter).sort({ createdAt: -1 }).lean();
        const out = orders.map((o) => {
            const x = { ...o };
            x.id = String(o._id);
            delete x._id;
            return x;
        });
        res.set('Cache-Control', 'no-store');
        res.json(out);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.post('/api/maintenance-orders', requireAuth, requireFieldOperator, async (req, res) => {
    try {
        const body = { ...req.body };
        if (!body.machineId || !body.companyId || !body.description) {
            return res.status(400).json({ error: 'machineId, companyId et description sont obligatoires' });
        }
        const typeNorm = String(body.type || 'CORRECTIVE').trim().toUpperCase();
        body.type = typeNorm || 'CORRECTIVE';
        if (!(await assertMaintenanceOrderCompanyAccess(req, res, String(body.companyId)))) return;
        const order = new MaintenanceOrder(body);
        await order.save();
        const o = order.toObject({ virtuals: true });
        o.id = String(order._id);
        delete o._id;
        delete o.__v;
        res.status(201).json(o);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.patch('/api/maintenance-orders/:id', requireAuth, requireFieldOperator, async (req, res) => {
    try {
        const id = String(req.params.id || '').trim();
        if (!id) return res.status(400).json({ error: 'id requis' });
        const doc = await MaintenanceOrder.findById(id);
        if (!doc) return res.status(404).json({ error: 'Ordre maintenance introuvable' });
        if (!(await assertMaintenanceOrderCompanyAccess(req, res, String(doc.companyId || '')))) return;

        const body = req.body || {};
        if (body.description != null) doc.description = String(body.description || '').trim();
        if (body.technicianId != null) doc.technicianId = String(body.technicianId || '').trim();
        if (body.priority != null) doc.priority = String(body.priority || 'MEDIUM').trim().toUpperCase();
        if (body.rootCause != null) doc.rootCause = String(body.rootCause || '').trim();
        if (body.actionTaken != null) doc.actionTaken = String(body.actionTaken || '').trim();
        if (body.closeNote != null) doc.closeNote = String(body.closeNote || '').trim();
        if (body.downtimeMinutes != null) {
            const n = Number(body.downtimeMinutes);
            doc.downtimeMinutes = Number.isFinite(n) && n >= 0 ? n : null;
        }
        await doc.save();

        const o = doc.toObject({ virtuals: true });
        o.id = String(doc._id);
        delete o._id;
        delete o.__v;
        return res.json(o);
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
});

app.patch('/api/maintenance-orders/:id/status', requireAuth, requireFieldOperator, async (req, res) => {
    try {
        const id = String(req.params.id || '').trim();
        const next = String(req.body?.status || '').trim().toUpperCase();
        if (!id || !next) return res.status(400).json({ error: 'id et status requis' });
        if (!['PENDING', 'IN_PROGRESS', 'COMPLETED'].includes(next)) {
            return res.status(400).json({ error: 'status invalide' });
        }

        const doc = await MaintenanceOrder.findById(id);
        if (!doc) return res.status(404).json({ error: 'Ordre maintenance introuvable' });
        if (!(await assertMaintenanceOrderCompanyAccess(req, res, String(doc.companyId || '')))) return;

        if (req.body?.rootCause != null) doc.rootCause = String(req.body.rootCause || '').trim();
        if (req.body?.actionTaken != null) doc.actionTaken = String(req.body.actionTaken || '').trim();
        if (req.body?.closeNote != null) doc.closeNote = String(req.body.closeNote || '').trim();
        if (req.body?.downtimeMinutes != null) {
            const n = Number(req.body.downtimeMinutes);
            doc.downtimeMinutes = Number.isFinite(n) && n >= 0 ? n : null;
        }

        if (next === 'IN_PROGRESS' && !doc.startedAt) {
            doc.startedAt = new Date();
        }
        if (next === 'COMPLETED') {
            if (!String(doc.rootCause || '').trim() || !String(doc.actionTaken || '').trim()) {
                return res.status(400).json({ error: 'rootCause et actionTaken requis pour clôturer' });
            }
            doc.closedAt = new Date();
        }
        if (next !== 'COMPLETED') {
            doc.closedAt = null;
        }
        doc.status = next;
        await doc.save();

        const o = doc.toObject({ virtuals: true });
        o.id = String(doc._id);
        delete o._id;
        delete o.__v;
        return res.json(o);
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
});

app.get('/api/diagnostic-interventions/scenarios', requireAuth, requireFieldOperator, async (req, res) => {
    const out = Object.entries(DIAGNOSTIC_SCENARIOS).map(([key, value]) => ({
        key,
        label: value.label,
        steps: value.steps,
    }));
    return res.json(out);
});

app.get('/api/diagnostic-interventions', requireAuth, requireFieldOperator, async (req, res) => {
    try {
        const filter = await maintenanceOrdersFilterForAuth(req.auth);
        if (req.query?.status) {
            filter.status = String(req.query.status).toUpperCase();
        }
        const docs = await DiagnosticIntervention.find(filter).sort({ updatedAt: -1 }).lean();
        const out = docs.map((d) => {
            const x = { ...d, id: String(d._id) };
            delete x._id;
            delete x.__v;
            return x;
        });
        res.set('Cache-Control', 'no-store');
        return res.json(out);
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
});

app.post('/api/diagnostic-interventions', requireAuth, requireFieldOperator, async (req, res) => {
    try {
        const machineId = String(req.body?.machineId || '').trim();
        const companyId = String(req.body?.companyId || '').trim();
        const scenarioType = String(req.body?.scenarioType || 'SENSOR_COMM').trim().toUpperCase();
        const summary = String(req.body?.summary || '').trim();
        const technicianId = String(req.body?.technicianId || '').trim();
        const technicianName = String(req.body?.technicianName || '').trim();
        if (!machineId || !companyId) {
            return res.status(400).json({ error: 'machineId et companyId requis' });
        }
        if (!(await assertMaintenanceOrderCompanyAccess(req, res, companyId))) return;
        const scenario = DIAGNOSTIC_SCENARIOS[scenarioType] || DIAGNOSTIC_SCENARIOS.SENSOR_COMM;
        const steps = scenario.steps.map((title, i) => ({
            order: i + 1,
            title,
            details: '',
            status: 'PENDING',
        }));
        const doc = new DiagnosticIntervention({
            machineId,
            companyId,
            scenarioType,
            scenarioLabel: scenario.label,
            summary,
            createdById: String(req.auth?.sub || ''),
            createdByRole: String(req.auth?.role || ''),
            createdByName: String(req.body?.createdByName || req.auth?.role || ''),
            technicianId,
            technicianName,
            status: 'OPEN',
            currentStepIndex: 0,
            steps,
            messages: [],
        });
        await doc.save();
        const out = doc.toObject({ virtuals: true });
        out.id = String(doc._id);
        delete out._id;
        delete out.__v;
        return res.status(201).json(out);
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
});

app.post('/api/diagnostic-interventions/:id/messages', requireAuth, requireFieldOperator, async (req, res) => {
    try {
        const id = String(req.params.id || '').trim();
        const content = String(req.body?.content || '').trim();
        if (!id || !content) return res.status(400).json({ error: 'id et content requis' });
        const doc = await DiagnosticIntervention.findById(id);
        if (!doc) return res.status(404).json({ error: 'Intervention introuvable' });
        if (!(await assertMaintenanceOrderCompanyAccess(req, res, String(doc.companyId || '')))) return;
        doc.messages.push({
            authorId: String(req.auth?.sub || ''),
            authorRole: String(req.auth?.role || ''),
            authorName: String(req.body?.authorName || req.auth?.role || ''),
            content,
            messageType: 'TEXT',
        });
        await doc.save();
        return res.json({ ok: true });
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
});

app.post('/api/diagnostic-interventions/:id/coordination', requireAuth, requireFieldOperator, async (req, res) => {
    try {
        const id = String(req.params.id || '').trim();
        const content = String(req.body?.content || '').trim();
        if (!id || !content) return res.status(400).json({ error: 'id et content requis' });
        const doc = await DiagnosticIntervention.findById(id);
        if (!doc) return res.status(404).json({ error: 'Intervention introuvable' });
        if (!(await assertMaintenanceOrderCompanyAccess(req, res, String(doc.companyId || '')))) return;
        
        const note = {
            authorId: String(req.auth?.sub || ''),
            authorRole: String(req.auth?.role || ''),
            authorName: String(req.body?.authorName || req.auth?.role || ''),
            content,
            messageType: 'TEXT',
            createdAt: new Date(),
        };
        doc.coordinationNotes.push(note);
        await doc.save();

        // Notify via socket
        io.emit('diagnostic_coordination', { interventionId: id, note });

        return res.json({ ok: true });
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
});

app.post('/api/diagnostic-interventions/:id/steps', requireAuth, requireFieldOperator, async (req, res) => {
    try {
        const id = String(req.params.id || '').trim();
        const title = String(req.body?.title || '').trim();
        const details = String(req.body?.details || '').trim();
        if (!id || !title) return res.status(400).json({ error: 'id et title requis' });
        const doc = await DiagnosticIntervention.findById(id);
        if (!doc) return res.status(404).json({ error: 'Intervention introuvable' });
        if (!(await assertMaintenanceOrderCompanyAccess(req, res, String(doc.companyId || '')))) return;
        doc.steps.push({
            order: doc.steps.length + 1,
            title,
            details,
            status: 'PENDING',
        });
        await doc.save();
        return res.json({ ok: true });
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
});

app.post('/api/diagnostic-interventions/:id/steps/:stepId/ok', requireAuth, requireFieldOperator, async (req, res) => {
    try {
        const id = String(req.params.id || '').trim();
        const stepId = String(req.params.stepId || '').trim();
        const note = String(req.body?.note || '').trim();
        const doc = await DiagnosticIntervention.findById(id);
        if (!doc) return res.status(404).json({ error: 'Intervention introuvable' });
        if (!(await assertMaintenanceOrderCompanyAccess(req, res, String(doc.companyId || '')))) return;
        const step = doc.steps.id(stepId);
        if (!step) return res.status(404).json({ error: 'Step introuvable' });
        step.status = 'DONE';
        step.doneById = String(req.auth?.sub || '');
        step.doneByRole = String(req.auth?.role || '');
        step.doneAt = new Date();
        step.note = note;
        doc.status = 'IN_PROGRESS';
        await doc.save();
        return res.json({ ok: true });
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
});

app.post('/api/diagnostic-interventions/:id/next', requireAuth, requireFieldOperator, async (req, res) => {
    try {
        const id = String(req.params.id || '').trim();
        const doc = await DiagnosticIntervention.findById(id);
        if (!doc) return res.status(404).json({ error: 'Intervention introuvable' });
        if (!(await assertMaintenanceOrderCompanyAccess(req, res, String(doc.companyId || '')))) return;
        const maxIndex = Math.max(0, doc.steps.length - 1);
        doc.currentStepIndex = Math.min(maxIndex, Number(doc.currentStepIndex || 0) + 1);
        await doc.save();
        return res.json({ ok: true, currentStepIndex: doc.currentStepIndex });
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
});

app.patch('/api/diagnostic-interventions/:id/decision', requireAuth, requireFieldOperator, async (req, res) => {
    try {
        const id = String(req.params.id || '').trim();
        const finalDecision = String(req.body?.finalDecision || '').trim().toUpperCase();
        const finalNote = String(req.body?.finalNote || '').trim();
        if (!['CAPTEUR_FAULT', 'REAL_MACHINE_FAULT'].includes(finalDecision)) {
            return res.status(400).json({ error: 'finalDecision invalide' });
        }
        const doc = await DiagnosticIntervention.findById(id);
        if (!doc) return res.status(404).json({ error: 'Intervention introuvable' });
        if (!(await assertMaintenanceOrderCompanyAccess(req, res, String(doc.companyId || '')))) return;
        doc.finalDecision = finalDecision;
        doc.finalNote = finalNote;
        await doc.save();
        return res.json({ ok: true });
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
});

app.patch('/api/diagnostic-interventions/:id/status', requireAuth, requireFieldOperator, async (req, res) => {
    try {
        const id = String(req.params.id || '').trim();
        const status = String(req.body?.status || '').trim().toUpperCase();
        if (!['OPEN', 'IN_PROGRESS', 'BLOCKED', 'DONE', 'CANCELLED'].includes(status)) {
            return res.status(400).json({ error: 'status invalide' });
        }
        const doc = await DiagnosticIntervention.findById(id);
        if (!doc) return res.status(404).json({ error: 'Intervention introuvable' });
        if (!(await assertMaintenanceOrderCompanyAccess(req, res, String(doc.companyId || '')))) return;
        doc.status = status;
        if (status === 'DONE' || status === 'CANCELLED') {
            doc.finishedAt = new Date();
        }
        await doc.save();
        return res.json({ ok: true });
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
});

async function generateMaintenanceAgentId() {
    for (let attempt = 0; attempt < 60; attempt++) {
        const id = `MAINT-${Date.now().toString(36).toUpperCase()}-${Math.random().toString(36).slice(2, 6).toUpperCase()}`;
        const exists = await MaintenanceAgent.exists({ maintenanceAgentId: id });
        if (!exists) return id;
    }
    return `MAINT-${new mongoose.Types.ObjectId().toString()}`;
}

function serializeMaintenanceAgentLean(doc) {
    const o = { ...doc };
    o.id = String(doc._id);
    delete o._id;
    delete o.password;
    delete o.__v;
    return o;
}

app.get('/api/maintenance-agents', async (req, res) => {
    try {
        const docs = await MaintenanceAgent.find().sort({ createdAt: -1 }).lean();
        const out = [];
        for (const d of docs) {
            const row = serializeMaintenanceAgentLean(d);
            const cid = row.clientId;
            if (cid) {
                const cl = await Client.findOne({ clientId: cid })
                    || (mongoose.Types.ObjectId.isValid(cid) ? await Client.findById(cid) : null);
                if (cl) row.clientName = cl.name;
            }
            if (Array.isArray(row.machineIds) && row.machineIds.length > 0) {
                const machines = await Machine.find({ _id: { $in: row.machineIds } }).select('name').lean();
                row.machineLabels = machines.map((m) => ({ id: String(m._id), name: m.name || String(m._id) }));
            } else {
                row.machineLabels = [];
            }
            out.push(row);
        }
        res.set('Cache-Control', 'no-store');
        res.json(out);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.post('/api/maintenance-agents', requireAuth, requireSuperAdmin, async (req, res) => {
    try {
        const firstName = String(req.body.firstName || '').trim();
        const lastName = String(req.body.lastName || '').trim();
        const emailNorm = String(req.body.email || '').trim().toLowerCase();
        const password = String(req.body.password || '');
        const address = String(req.body.address || '').trim();
        const location = String(req.body.location || '').trim();
        const clientIdRaw = req.body.clientId != null ? String(req.body.clientId).trim() : '';
        const machineIds = normalizeMachineIdsInput(req.body.machineIds) || [];

        if (!firstName || !lastName) {
            return res.status(400).json({ error: 'Prénom et nom obligatoires' });
        }
        if (!emailNorm.includes('@')) {
            return res.status(400).json({ error: 'Email invalide' });
        }
        if (password.length < 6) {
            return res.status(400).json({ error: 'Mot de passe minimum 6 caractères' });
        }
        if (!clientIdRaw) {
            return res.status(400).json({ error: 'Client obligatoire' });
        }
        if (machineIds.length === 0) {
            return res.status(400).json({ error: 'Sélectionnez au moins une machine' });
        }

        const client = await Client.findOne({ clientId: clientIdRaw })
            || (mongoose.Types.ObjectId.isValid(clientIdRaw) ? await Client.findById(clientIdRaw) : null);
        if (!client) {
            return res.status(400).json({ error: 'Client introuvable' });
        }

        const storedClientKey = client.clientId ? String(client.clientId) : String(client._id);
        const aliases = await buildCompanyAliasSet(storedClientKey);

        for (const mid of machineIds) {
            const m = await Machine.findById(mid);
            if (!m) {
                return res.status(400).json({ error: `Machine introuvable: ${mid}` });
            }
            if (!aliases.has(String(m.companyId))) {
                return res.status(400).json({ error: `La machine ${mid} n'appartient pas à ce client` });
            }
        }

        const dup = await MaintenanceAgent.findOne({ email: emailNorm });
        if (dup) {
            return res.status(409).json({ error: 'Cet email est déjà utilisé' });
        }

        const hash = await bcrypt.hash(password, 10);
        const maintenanceAgentId = await generateMaintenanceAgentId();
        const agent = await MaintenanceAgent.create({
            maintenanceAgentId,
            firstName,
            lastName,
            email: emailNorm,
            password: hash,
            address: address || undefined,
            location: location || undefined,
            clientId: storedClientKey,
            machineIds,
        });

        const row = serializeMaintenanceAgentLean(agent.toObject());
        row.clientName = client.name;
        const machines = await Machine.find({ _id: { $in: machineIds } }).select('name').lean();
        row.machineLabels = machines.map((m) => ({ id: String(m._id), name: m.name || String(m._id) }));
        res.status(201).json(row);
    } catch (err) {
        if (err.code === 11000) {
            return res.status(409).json({ error: 'Email ou identifiant déjà existant' });
        }
        res.status(500).json({ error: err.message });
    }
});

app.put('/api/maintenance-agents/:id', requireAuth, requireSuperAdmin, async (req, res) => {
    try {
        const param = String(req.params.id);
        let doc = await MaintenanceAgent.findOne({ maintenanceAgentId: param });
        if (!doc && mongoose.Types.ObjectId.isValid(param)) {
            doc = await MaintenanceAgent.findById(param);
        }
        if (!doc) {
            return res.status(404).json({ error: 'Agent introuvable' });
        }

        if (req.body.firstName !== undefined) {
            doc.firstName = String(req.body.firstName || '').trim();
        }
        if (req.body.lastName !== undefined) {
            doc.lastName = String(req.body.lastName || '').trim();
        }
        if (req.body.email !== undefined) {
            const emailNorm = String(req.body.email || '').trim().toLowerCase();
            if (!emailNorm.includes('@')) {
                return res.status(400).json({ error: 'Email invalide' });
            }
            const dup = await MaintenanceAgent.findOne({ email: emailNorm, _id: { $ne: doc._id } });
            if (dup) {
                return res.status(409).json({ error: 'Cet email est déjà utilisé' });
            }
            doc.email = emailNorm;
        }
        if (req.body.password != null && String(req.body.password).length > 0) {
            const password = String(req.body.password);
            if (password.length < 6) {
                return res.status(400).json({ error: 'Mot de passe minimum 6 caractères' });
            }
            doc.password = await bcrypt.hash(password, 10);
        }
        if (req.body.address !== undefined) {
            doc.address = String(req.body.address || '').trim();
        }
        if (req.body.location !== undefined) {
            doc.location = String(req.body.location || '').trim();
        }

        let clientKey = doc.clientId;
        if (req.body.clientId !== undefined) {
            clientKey = String(req.body.clientId || '').trim();
            if (!clientKey) {
                return res.status(400).json({ error: 'Client obligatoire' });
            }
            const client = await Client.findOne({ clientId: clientKey })
                || (mongoose.Types.ObjectId.isValid(clientKey) ? await Client.findById(clientKey) : null);
            if (!client) {
                return res.status(400).json({ error: 'Client introuvable' });
            }
            doc.clientId = client.clientId ? String(client.clientId) : String(client._id);
        }

        let machineIds = (doc.machineIds || []).map(String);
        if (req.body.machineIds !== undefined) {
            machineIds = normalizeMachineIdsInput(req.body.machineIds) || [];
            if (machineIds.length === 0) {
                return res.status(400).json({ error: 'Sélectionnez au moins une machine' });
            }
        }

        const storedClientKey = doc.clientId;
        const aliases = await buildCompanyAliasSet(storedClientKey);
        for (const mid of machineIds) {
            const m = await Machine.findById(mid);
            if (!m) {
                return res.status(400).json({ error: `Machine introuvable: ${mid}` });
            }
            if (!aliases.has(String(m.companyId))) {
                return res.status(400).json({ error: `La machine ${mid} n'appartient pas à ce client` });
            }
        }
        doc.machineIds = machineIds;

        if (!doc.firstName || !doc.lastName) {
            return res.status(400).json({ error: 'Prénom et nom obligatoires' });
        }

        await doc.save();
        const row = serializeMaintenanceAgentLean(doc.toObject());
        const cl = await Client.findOne({ clientId: doc.clientId })
            || (mongoose.Types.ObjectId.isValid(doc.clientId) ? await Client.findById(doc.clientId) : null);
        if (cl) row.clientName = cl.name;
        const machines = await Machine.find({ _id: { $in: doc.machineIds } }).select('name').lean();
        row.machineLabels = machines.map((m) => ({ id: String(m._id), name: m.name || String(m._id) }));
        res.json(row);
    } catch (err) {
        if (err.code === 11000) {
            return res.status(409).json({ error: 'Email ou identifiant déjà existant' });
        }
        res.status(500).json({ error: err.message });
    }
});

app.delete('/api/maintenance-agents/:id', requireAuth, requireSuperAdmin, async (req, res) => {
    try {
        const param = String(req.params.id);
        let doc = await MaintenanceAgent.findOne({ maintenanceAgentId: param });
        if (!doc && mongoose.Types.ObjectId.isValid(param)) {
            doc = await MaintenanceAgent.findById(param);
        }
        if (!doc) {
            return res.status(404).json({ error: 'Agent introuvable' });
        }
        await MaintenanceAgent.deleteOne({ _id: doc._id });
        res.json({ ok: true });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

function serializeConcepteurUser(doc) {
    const id = String(doc._id);
    const spec = (doc.specialite && String(doc.specialite).trim()) || 'Conception';
    return {
        id,
        email: doc.email,
        username: doc.username,
        role: 'conception',
        companyId: doc.companyId || null,
        machineIds: doc.machineIds || [],
        location: doc.location || null,
        specialite: doc.specialite || null,
        specialization: spec,
        createdAt: doc.createdAt || null,
        updatedAt: doc.updatedAt || null,
    };
}

app.get('/api/concepteurs', requireAuth, requireFieldOperator, async (req, res) => {
    try {
        const docs = await Concepteur.find({}).sort({ createdAt: -1 });
        res.set('Cache-Control', 'no-store');
        res.json(docs.map((d) => serializeConcepteurUser(d)));
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.get('/api/concepteurs/:id', requireAuth, requireFieldOperator, async (req, res) => {
    try {
        const param = String(req.params.id);
        let doc = mongoose.Types.ObjectId.isValid(param) ? await Concepteur.findById(param) : null;
        if (!doc) {
            doc = await Concepteur.findOne({ username: param });
        }
        if (!doc) {
            return res.status(404).json({ error: 'Concepteur introuvable' });
        }
        res.json(serializeConcepteurUser(doc));
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

/**
 * Espace conception (Observatory) : machines et client assignés au compte concepteur connecté.
 * Ne filtre pas les machines « démo » : le concepteur voit exactement son périmètre assigné.
 */
app.get('/api/conception/workspace', requireAuth, async (req, res) => {
    try {
        if (req.auth.role !== 'conception') {
            return res.status(403).json({ error: 'Accès réservé aux comptes conception' });
        }
        const subRaw = [req.auth.sub, req.auth.subject, req.auth.id]
            .map((x) => (x != null ? String(x).trim() : ''))
            .find((s) => s.length > 0) || '';
        let user = null;
        if (subRaw && mongoose.Types.ObjectId.isValid(subRaw)) {
            user = await Concepteur.findById(subRaw).lean();
        }
        const cMail = req.auth.cMail != null ? String(req.auth.cMail).toLowerCase().trim() : '';
        const cUser = req.auth.cUser != null ? String(req.auth.cUser).trim() : '';
        if (!user && cMail) {
            user = await Concepteur.findOne({ email: cMail }).lean();
        }
        if (!user && cUser) {
            user = await Concepteur.findOne({ username: cUser }).lean();
        }
        const coId = req.auth.companyId != null ? String(req.auth.companyId).trim() : '';
        if (!user && coId) {
            const list = await Concepteur.find({ companyId: coId }).lean();
            if (list.length === 1) {
                user = list[0];
            } else if (list.length > 1 && cMail) {
                user = list.find((x) => String(x.email || '').toLowerCase() === cMail) || null;
            } else if (list.length > 1 && cUser) {
                user = list.find((x) => String(x.username || '').trim() === cUser) || null;
            }
        }
        if (!user) {
            return res.status(404).json({
                error: 'Utilisateur introuvable',
                hint: 'Déconnectez-vous puis reconnectez-vous, ou exécutez: npm run seed:demo && npm run seed:dev-concepteur',
            });
        }
        const machineIds = (user.machineIds || []).map((x) => String(x).trim()).filter(Boolean);
        const companyId = user.companyId != null ? String(user.companyId).trim() : '';
        let docs = [];
        if (machineIds.length > 0) {
            docs = await Machine.find({ _id: { $in: machineIds } }).lean();
        } else if (companyId) {
            docs = await Machine.find({ companyId }).lean();
        }
        let client = null;
        if (companyId) {
            client =
                (await Client.findOne({ clientId: companyId }).lean()) ||
                (mongoose.Types.ObjectId.isValid(companyId) ? await Client.findById(companyId).lean() : null);
        }
        res.set('Cache-Control', 'no-store');
        res.json({
            user: {
                id: String(user._id),
                username: user.username || '',
                email: user.email || '',
                companyId,
                machineIds,
            },
            client: client
                ? {
                      name: client.name || '',
                      clientId: client.clientId != null ? String(client.clientId) : String(client._id),
                  }
                : null,
            machines: serializeMachineDocs(docs),
        });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.post('/api/concepteurs', requireAuth, requireFleetManager, async (req, res) => {
    try {
        const emailNorm = String(req.body.email || '').trim().toLowerCase();
        const username = String(req.body.username || '').trim();
        const password = String(req.body.password || '');
        const location = String(req.body.location || '').trim();
        const companyId = req.body.companyId != null ? String(req.body.companyId).trim() : '';
        const specialite = String(req.body.specialite || '').trim();
        const machineIdsNorm = normalizeMachineIdsInput(req.body.machineIds);

        if (!emailNorm.includes('@')) {
            return res.status(400).json({ error: 'Email invalide' });
        }
        if (!username) {
            return res.status(400).json({ error: 'Nom d\'utilisateur obligatoire' });
        }
        if (password.length < 6) {
            return res.status(400).json({ error: 'Mot de passe minimum 6 caractères' });
        }
        if (req.auth.role === 'admin') {
            if (!companyId) {
                return res.status(400).json({
                    error: 'Client / entreprise obligatoire pour créer un concepteur avec ce compte administrateur.',
                });
            }
            if (!(await assertFleetCompanyAccess(req, res, companyId))) return;
        }
        if (machineIdsNorm && machineIdsNorm.length > 0) {
            if (!companyId) {
                return res.status(400).json({ error: 'Sélectionnez un client avant d\'assigner des machines.' });
            }
            const vErr = await validateTechnicianMachineIds(machineIdsNorm, companyId);
            if (vErr) return res.status(400).json({ error: vErr });
        }

        const [dupUserEmail, dupTechEmail, dupClientEmail, dupConcEmail, dupUserName, dupConcName] = await Promise.all([
            User.findOne({ email: emailNorm }),
            Technician.findOne({ email: emailNorm }),
            Client.findOne({ email: emailNorm }),
            Concepteur.findOne({ email: emailNorm }),
            User.findOne({ username }),
            Concepteur.findOne({ username }),
        ]);
        if (dupUserEmail || dupTechEmail || dupClientEmail || dupConcEmail) {
            return res.status(409).json({ error: 'Cet email est déjà utilisé' });
        }
        if (dupUserName || dupConcName) {
            return res.status(409).json({ error: 'Ce nom d\'utilisateur est déjà pris' });
        }

        const hash = await bcrypt.hash(password, 10);
        const user = await Concepteur.create({
            email: emailNorm,
            username,
            password: hash,
            location: location || undefined,
            companyId: companyId || undefined,
            machineIds: machineIdsNorm && machineIdsNorm.length > 0 ? machineIdsNorm : undefined,
            specialite: specialite || undefined,
        });
        res.status(201).json(serializeConcepteurUser(user));
    } catch (err) {
        if (err.code === 11000) {
            return res.status(409).json({ error: 'Email ou identifiant déjà existant' });
        }
        res.status(500).json({ error: err.message });
    }
});

app.put('/api/concepteurs/:id', requireAuth, requireFleetManager, async (req, res) => {
    try {
        const param = String(req.params.id);
        let user = mongoose.Types.ObjectId.isValid(param) ? await Concepteur.findById(param) : null;
        if (!user) {
            user = await Concepteur.findOne({ username: param });
        }
        if (!user) {
            return res.status(404).json({ error: 'Concepteur introuvable' });
        }
        if (!(await assertFleetCompanyAccess(req, res, user.companyId))) return;

        const emailRaw = req.body.email;
        const usernameRaw = req.body.username;
        const password = req.body.password != null ? String(req.body.password) : '';
        const location = req.body.location;
        const companyId = req.body.companyId;
        const specialite = req.body.specialite;
        const machineIdsRaw = req.body.machineIds;

        if (emailRaw !== undefined) {
            const emailNorm = String(emailRaw).trim().toLowerCase();
            if (!emailNorm.includes('@')) {
                return res.status(400).json({ error: 'Email invalide' });
            }
            const dup =
                (await User.findOne({ email: emailNorm })) ||
                (await Technician.findOne({ email: emailNorm })) ||
                (await Client.findOne({ email: emailNorm })) ||
                (await Concepteur.findOne({ email: emailNorm, _id: { $ne: user._id } }));
            if (dup) {
                return res.status(409).json({ error: 'Cet email est déjà utilisé' });
            }
            user.email = emailNorm;
        }
        if (usernameRaw !== undefined) {
            const un = String(usernameRaw).trim();
            if (!un) {
                return res.status(400).json({ error: 'Nom d\'utilisateur obligatoire' });
            }
            const dup =
                (await User.findOne({ username: un })) ||
                (await Concepteur.findOne({ username: un, _id: { $ne: user._id } }));
            if (dup) {
                return res.status(409).json({ error: 'Ce nom d\'utilisateur est déjà pris' });
            }
            user.username = un;
        }
        if (password.length > 0) {
            if (password.length < 6) {
                return res.status(400).json({ error: 'Mot de passe minimum 6 caractères' });
            }
            user.password = await bcrypt.hash(password, 10);
        }
        if (location !== undefined) {
            user.location = String(location || '').trim() || undefined;
        }
        if (companyId !== undefined) {
            const nextCid = companyId != null && String(companyId).trim() !== ''
                ? String(companyId).trim()
                : undefined;
            if (String(nextCid || '') !== String(user.companyId || '')) {
                if (req.auth.role === 'admin' && !nextCid) {
                    return res.status(400).json({ error: 'Le client ne peut pas être retiré pour ce compte.' });
                }
                if (nextCid && !(await assertFleetCompanyAccess(req, res, nextCid))) return;
            }
            user.companyId = nextCid;
        }
        if (specialite !== undefined) {
            user.specialite = String(specialite || '').trim() || undefined;
        }
        if (machineIdsRaw !== undefined) {
            const mid = normalizeMachineIdsInput(machineIdsRaw);
            const effectiveCompany = String(user.companyId || '').trim();
            if (mid && mid.length > 0) {
                if (!effectiveCompany) {
                    return res.status(400).json({ error: 'Associez un client avant d\'assigner des machines.' });
                }
                const vErr = await validateTechnicianMachineIds(mid, effectiveCompany);
                if (vErr) return res.status(400).json({ error: vErr });
            }
            user.machineIds = mid && mid.length > 0 ? mid : [];
        }

        await user.save();
        res.json(serializeConcepteurUser(user));
    } catch (err) {
        if (err.code === 11000) {
            return res.status(409).json({ error: 'Email ou identifiant déjà existant' });
        }
        res.status(500).json({ error: err.message });
    }
});

app.delete('/api/concepteurs/:id', requireAuth, requireFleetManager, async (req, res) => {
    try {
        const param = String(req.params.id);
        let user = mongoose.Types.ObjectId.isValid(param) ? await Concepteur.findById(param) : null;
        if (!user) {
            user = await Concepteur.findOne({ username: param });
        }
        if (!user) {
            return res.status(404).json({ error: 'Concepteur introuvable' });
        }
        if (!(await assertFleetCompanyAccess(req, res, user.companyId))) return;
        await Concepteur.deleteOne({ _id: user._id });
        res.json({ ok: true });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// ============================================================
// ROUTES: TECHNICIANS
// ============================================================

/**
 * Répertoire unifié : techniciens ([Technician]) + concepteurs ([Concepteur]) + agents maintenance (super-admin).
 */
app.get('/api/team-directory', requireAuth, requireFieldOperator, async (req, res) => {
    try {
        const auth = req.auth;
        const out = [];

        let techFilter = {};
        let concFilter = {};
        if (auth.role === 'admin' && auth.companyId) {
            const aliases = await buildCompanyAliasSet(String(auth.companyId));
            const arr = Array.from(aliases);
            techFilter = { companyId: { $in: arr } };
            concFilter = { companyId: { $in: arr } };
        } else if (auth.role === 'technician') {
            const tech = await Technician.findOne({ technicianId: String(auth.sub) });
            if (tech && tech.companyId) {
                const aliases = await buildCompanyAliasSet(String(tech.companyId));
                const arr = Array.from(aliases);
                techFilter = { companyId: { $in: arr } };
                concFilter = { companyId: { $in: arr } };
            }
        } else if (auth.role === 'maintenance') {
            const agent = await MaintenanceAgent.findOne({ $or: [{ _id: auth.sub }, { maintenanceAgentId: auth.sub }] });
            if (agent && agent.clientId) {
                const aliases = await buildCompanyAliasSet(String(agent.clientId));
                const arr = Array.from(aliases);
                techFilter = { companyId: { $in: arr } };
                concFilter = { companyId: { $in: arr } };
            }
        }

        const technicians = await Technician.find(techFilter).sort({ createdAt: -1 }).lean();
        for (const t of technicians) {
            const tid = t.technicianId ? String(t.technicianId) : String(t._id);
            const rawT = { ...t, technicianId: tid };
            delete rawT.password;
            const cid = t.companyId != null ? String(t.companyId) : '—';
            out.push({
                directoryKind: 'technician',
                id: tid,
                displayId: t.technicianId ? String(t.technicianId) : String(t._id),
                roleLabel: 'TECHNICIEN',
                name: t.name || '—',
                specialization: t.specialization || 'Général',
                phone: t.phone || '—',
                companyId: cid,
                companyLine: cid,
                status: t.status || 'Disponible',
                imageUrl: t.imageUrl || null,
                email: t.email || null,
                raw: rawT,
            });
        }

        const concepteurs = await Concepteur.find(concFilter).sort({ createdAt: -1 }).lean();
        for (const u of concepteurs) {
            const uid = String(u._id);
            const display = (u.username && String(u.username).trim()) || u.email || uid;
            const cidc = u.companyId != null ? String(u.companyId) : '—';
            out.push({
                directoryKind: 'concepteur',
                id: uid,
                displayId: display,
                roleLabel: 'CONCEPTEUR',
                name: display,
                specialization: (u.specialite && String(u.specialite).trim()) || 'Conception',
                phone: (u.location && String(u.location).trim()) || (u.email ? String(u.email) : '—'),
                companyId: cidc,
                companyLine: cidc,
                status: 'Actif',
                imageUrl: null,
                email: u.email || null,
                raw: {
                    id: uid,
                    email: u.email,
                    username: u.username,
                    companyId: u.companyId,
                    machineIds: u.machineIds || [],
                    location: u.location,
                    specialite: u.specialite,
                },
            });
        }

        if (auth.role === 'superadmin') {
            const agents = await MaintenanceAgent.find().sort({ createdAt: -1 }).lean();
            for (const a of agents) {
                const aid = String(a.maintenanceAgentId || a._id);
                let clientLabel = a.clientId ? String(a.clientId) : '—';
                const cl = a.clientId
                    ? ((await Client.findOne({ clientId: a.clientId }))
                        || (mongoose.Types.ObjectId.isValid(a.clientId) ? await Client.findById(a.clientId) : null))
                    : null;
                if (cl && cl.name) clientLabel = `${cl.name} (${clientLabel})`;
                const rawA = { ...a, id: String(a._id), clientDisplay: clientLabel };
                delete rawA.password;
                const cida = a.clientId != null ? String(a.clientId) : '—';
                out.push({
                    directoryKind: 'maintenance',
                    id: aid,
                    displayId: aid,
                    roleLabel: 'MAINTENANCE',
                    name: `${a.firstName || ''} ${a.lastName || ''}`.trim() || '—',
                    specialization: 'Personnel maintenance',
                    phone: (a.location && String(a.location).trim()) || (a.email ? String(a.email) : '—'),
                    companyId: cida,
                    companyLine: clientLabel,
                    status: 'Actif',
                    imageUrl: null,
                    email: a.email || null,
                    raw: rawA,
                });
            }
        }

        out.sort((a, b) => String(a.name || '').localeCompare(String(b.name || ''), 'fr', { sensitivity: 'base' }));
        res.set('Cache-Control', 'no-store');
        res.json(out);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.get('/api/technicians', async (req, res) => {
    try {
        const technicians = await Technician.find();
        res.json(technicians);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.post('/api/technicians', requireAuth, requireFleetManager, async (req, res) => {
    try {
        const techData = { ...req.body };
        delete techData.technicianId;
        delete techData.id;
        const emailNorm = (techData.email || '').toString().trim().toLowerCase();
        const password = (techData.password || '').toString();
        const fullName = (techData.name || '').toString().trim();
        const companyId = techData.companyId;
        const machineIds = Array.isArray(techData.machineIds)
            ? techData.machineIds.map((x) => String(x)).filter(Boolean)
            : [];

        if (!fullName || !fullName.includes(' ')) {
            return res.status(400).json({ error: 'Nom et prénom obligatoires (ex: Jean Dupont)' });
        }
        if (!emailNorm || !emailNorm.includes('@')) {
            return res.status(400).json({ error: 'Email invalide: le symbole @ est obligatoire' });
        }
        if (!password || password.length < 6) {
            return res.status(400).json({ error: 'Mot de passe de connexion obligatoire (minimum 6 caractères)' });
        }
        if (!companyId) {
            return res.status(400).json({ error: 'Le client est obligatoire pour assigner un technicien' });
        }

        let assignedClient = await Client.findOne({ clientId: companyId });
        if (!assignedClient && mongoose.Types.ObjectId.isValid(companyId)) {
            assignedClient = await Client.findById(companyId) || await Company.findById(companyId);
        }
        if (!assignedClient) {
            return res.status(400).json({ error: 'Client invalide: impossible de lier ce technicien' });
        }
        if (!(await assertFleetCompanyAccess(req, res, companyId))) return;

        const [dupUser, dupClient, dupTech, dupConcepteur] = await Promise.all([
            User.findOne({ email: emailNorm }),
            Client.findOne({ email: emailNorm }),
            Technician.findOne({ email: emailNorm }),
            Concepteur.findOne({ email: emailNorm }),
        ]);
        if (dupUser) {
            return res.status(409).json({ error: 'Cet email est déjà utilisé (compte administrateur)' });
        }
        if (dupConcepteur) {
            return res.status(409).json({ error: 'Cet email est déjà utilisé (compte concepteur)' });
        }
        if (dupClient && !isSameClientDoc(dupClient, assignedClient)) {
            return res.status(409).json({ error: 'Cet email est déjà utilisé par un autre client' });
        }
        if (dupTech) {
            return res.status(409).json({ error: 'Un technicien existe déjà avec cet email' });
        }

        const aliases = await buildCompanyAliasSet(companyId);
        const mCount = await machineCountForCompanyAliases(aliases);
        if (mCount < 1) {
            return res.status(400).json({
                error: 'Ce client n\'a aucune machine : créez d\'abord au moins une machine, puis ajoutez le technicien en choisissant les équipements qu\'il contrôle.'
            });
        }
        if (machineIds.length < 1) {
            return res.status(400).json({
                error: 'Choisissez au moins une machine que ce technicien contrôlera (obligatoire).'
            });
        }
        const vErr = await validateTechnicianMachineIds(machineIds, companyId);
        if (vErr) return res.status(400).json({ error: vErr });

        const year = new Date().getFullYear();
        let generated;
        let exists = true;
        while (exists) {
            generated = 'TECH-' + year + '-' + Math.floor(Math.random() * 1000000).toString().padStart(6, '0');
            exists = await Technician.exists({ technicianId: generated });
        }
        techData.technicianId = generated;

        techData.email = emailNorm;
        techData.password = await bcrypt.hash(password, 10);
        techData.machineIds = machineIds;
        delete techData._id;

        const technician = new Technician(techData);
        await technician.save();

        await applyTechDeltaToOwner(technician.companyId, 1);

        console.log(`✅ Technicien ajouté : ${technician.name} (${machineIds.length} machine(s))`);
        res.status(201).json(technician.toJSON());
    } catch (err) {
        console.error('❌ Erreur Ajout Technicien:', err.message);
        if (err.code === 11000) {
            const key = err.keyPattern ? Object.keys(err.keyPattern).join(',') : '';
            if (key.includes('email')) {
                return res.status(409).json({ error: 'Un technicien existe déjà avec cet email' });
            }
            if (key.includes('technicianId')) {
                return res.status(409).json({ error: 'Identifiant technicien en conflit — réessayez' });
            }
            return res.status(409).json({ error: 'Donnée en conflit (doublon en base)' });
        }
        res.status(500).json({ error: err.message });
    }
});

app.put('/api/technicians/:id', requireAuth, requireFleetManager, async (req, res) => {
    try {
        const existingTechnician = await Technician.findOne({ technicianId: req.params.id });
        if (!existingTechnician) return res.status(404).json({ error: 'Technicien non trouvé' });
        if (!(await assertFleetCompanyAccess(req, res, existingTechnician.companyId))) return;

        const raw = { ...req.body };
        if (raw.password === '' || raw.password === undefined) {
            delete raw.password;
        } else if (raw.password) {
            if (String(raw.password).length < 6) {
                return res.status(400).json({ error: 'Mot de passe minimum 6 caractères' });
            }
            raw.password = await bcrypt.hash(String(raw.password), 10);
        }

        if (raw.email) {
            raw.email = String(raw.email).trim().toLowerCase();
            if (!raw.email.includes('@')) {
                return res.status(400).json({ error: 'Email invalide' });
            }
            const dupUser = await User.findOne({ email: raw.email });
            const dupClient = await Client.findOne({ email: raw.email });
            const dupConcepteur = await Concepteur.findOne({ email: raw.email });
            if (dupUser || dupClient || dupConcepteur) {
                return res.status(409).json({ error: 'Cet email est déjà utilisé (admin, client ou concepteur)' });
            }
            const dupTech = await Technician.findOne({
                email: raw.email,
                technicianId: { $ne: existingTechnician.technicianId }
            });
            if (dupTech) {
                return res.status(409).json({ error: 'Un autre technicien utilise déjà cet email' });
            }
        }

        const companyId = raw.companyId !== undefined ? raw.companyId : existingTechnician.companyId;
        if (raw.companyId !== undefined && String(raw.companyId) !== String(existingTechnician.companyId)) {
            if (!(await assertFleetCompanyAccess(req, res, raw.companyId))) return;
        }
        if (raw.machineIds !== undefined) {
            const mids = Array.isArray(raw.machineIds)
                ? raw.machineIds.map((x) => String(x)).filter(Boolean)
                : [];
            const aliases = await buildCompanyAliasSet(companyId);
            const mCount = await machineCountForCompanyAliases(aliases);
            if (mCount > 0 && mids.length < 1) {
                return res.status(400).json({ error: 'Au moins une machine doit rester assignée à ce technicien' });
            }
            if (mids.length > 0) {
                const vErr = await validateTechnicianMachineIds(mids, companyId);
                if (vErr) return res.status(400).json({ error: vErr });
            }
            const oldSet = new Set((existingTechnician.machineIds || []).map(String));
            const newSet = new Set(mids);
            for (const mid of oldSet) {
                if (!newSet.has(mid)) {
                    const n = await countOtherTechniciansOnMachine(mid, existingTechnician.technicianId);
                    if (n < 1) {
                        return res.status(400).json({
                            error: `La machine ${mid} doit garder au moins un technicien : réassignez avant de retirer ce profil`
                        });
                    }
                }
            }
            raw.machineIds = mids;
        }

        const oldCompanyId = String(existingTechnician.companyId || '');
        const technician = await Technician.findOneAndUpdate(
            { technicianId: req.params.id },
            raw,
            { new: true }
        );
        if (!technician) return res.status(404).json({ error: 'Technicien non trouvé' });

        const newCompanyId = String(technician.companyId || '');
        if (oldCompanyId && newCompanyId && oldCompanyId !== newCompanyId) {
            await applyTechDeltaToOwner(oldCompanyId, -1);
            await applyTechDeltaToOwner(newCompanyId, 1);
        }

        console.log(`✅ Technicien modifié : ${technician.name}`);
        res.json(technician.toJSON());
    } catch (err) {
        console.error('❌ Erreur Modification Technicien:', err.message);
        res.status(500).json({ error: err.message });
    }
});

app.delete('/api/technicians/:id', requireAuth, requireFleetManager, async (req, res) => {
    try {
        const paramId = String(req.params.id);
        let technician = await Technician.findOne({ technicianId: paramId });
        if (!technician && mongoose.Types.ObjectId.isValid(paramId)) {
            technician = await Technician.findById(paramId);
        }
        if (!technician) {
            return res.status(404).json({ error: 'Technicien non trouvé' });
        }
        if (!(await assertFleetCompanyAccess(req, res, technician.companyId))) return;

        const tid = String(technician.technicianId || paramId);
        await Technician.deleteOne({ _id: technician._id });
        await applyTechDeltaToOwner(technician.companyId, -1);

        console.log('Technicien supprime : ' + technician.name + ' (' + tid + ')');
        res.json({ message: 'Technicien supprimé avec succès', technicianId: tid });
    } catch (err) {
        console.error('Erreur Suppression Technicien:', err.message);
        res.status(500).json({ error: err.message });
    }
});

// ============================================================
// ROUTES: CLIENTS
// ============================================================

app.get('/api/clients', async (req, res) => {
    try {
        const clients = await Client.find();
        if (clients.length === 0) {
            // Fallback pour la compatibilité avec Company si la collection Client est vide
            const companies = await Company.find();
            return res.json(companies.map(c => ({ ...c.toJSON(), id: c._id, clientId: c._id })));
        }
        res.json(clients);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.post('/api/clients', requireAuth, requireSuperAdmin, async (req, res) => {
    console.log('📝 Tentative d\'ajout de client:', { ...req.body, password: req.body.password ? '[mask]' : '' });
    try {
        const data = { ...req.body };
        const name = (data.name || '').toString().trim();
        const emailNorm = (data.email || '').toString().trim().toLowerCase();
        const plainPassword = (data.password || '').toString();

        if (!name) {
            return res.status(400).json({ error: 'Le nom de l\'entreprise est obligatoire' });
        }
        if (!emailNorm || !emailNorm.includes('@')) {
            return res.status(400).json({ error: 'Email de connexion client invalide (obligatoire)' });
        }
        if (!plainPassword || plainPassword.length < 6) {
            return res.status(400).json({ error: 'Mot de passe client obligatoire (minimum 6 caractères)' });
        }

        const [dupUser, dupClient, dupTech, dupConcepteur] = await Promise.all([
            User.findOne({ email: emailNorm }),
            Client.findOne({ email: emailNorm }),
            Technician.findOne({ email: emailNorm }),
            Concepteur.findOne({ email: emailNorm }),
        ]);
        if (dupUser || dupClient || dupTech || dupConcepteur) {
            return res.status(409).json({ error: 'Cet email est déjà utilisé (admin, client, technicien ou concepteur)' });
        }

        if (!data.clientId) {
            data.clientId = 'CLI-' + new Date().getFullYear() + '-' + Math.floor(Math.random() * 1000).toString().padStart(3, '0');
        }

        data.name = name;
        data.email = emailNorm;
        data.password = await bcrypt.hash(plainPassword, 10);

        data.machines = 0;
        data.techs = 0;
        data.alerts = 0;
        if (data.health === undefined) data.health = 1.0;

        const client = new Client(data);
        await client.save();
        console.log(`✅ Client ajouté : ${client.name} (login: ${emailNorm})`);
        res.status(201).json(client.toJSON());
    } catch (err) {
        console.error('❌ Erreur Ajout Client:', err.message);
        if (err.code === 11000) {
            return res.status(409).json({ error: 'Email ou identifiant client déjà existant' });
        }
        res.status(500).json({ error: err.message });
    }
});

app.put('/api/clients/:id', requireAuth, requireFleetManager, async (req, res) => {
    try {
        const paramId = req.params.id;
        const raw = { ...req.body };

        if (raw.password === '' || raw.password === undefined) {
            delete raw.password;
        } else if (raw.password) {
            if (String(raw.password).length < 6) {
                return res.status(400).json({ error: 'Mot de passe minimum 6 caractères' });
            }
            raw.password = await bcrypt.hash(String(raw.password), 10);
        }

        let targetClient = await Client.findOne({ clientId: paramId });
        if (!targetClient && mongoose.Types.ObjectId.isValid(paramId)) {
            targetClient = await Client.findById(paramId);
        }

        if (targetClient) {
            if (!(await clientWritableByAuth(req.auth, targetClient))) {
                return res.status(403).json({ error: 'Accès refusé' });
            }
        } else if (req.auth.role !== 'superadmin') {
            return res.status(403).json({ error: 'Accès refusé' });
        }

        if (raw.email) {
            raw.email = String(raw.email).trim().toLowerCase();
            if (!raw.email.includes('@')) {
                return res.status(400).json({ error: 'Email invalide' });
            }
            const dupUser = await User.findOne({ email: raw.email });
            const dupTech = await Technician.findOne({ email: raw.email });
            const dupConcepteur = await Concepteur.findOne({ email: raw.email });
            if (dupUser || dupTech || dupConcepteur) {
                return res.status(409).json({ error: 'Cet email est déjà utilisé (admin, technicien ou concepteur)' });
            }
            if (targetClient) {
                const dupClient = await Client.findOne({
                    email: raw.email,
                    _id: { $ne: targetClient._id }
                });
                if (dupClient) {
                    return res.status(409).json({ error: 'Cet email est déjà attribué à un autre client' });
                }
            }
        }

        let client = await Client.findOneAndUpdate({ clientId: paramId }, raw, { new: true });

        if (!client && mongoose.Types.ObjectId.isValid(paramId)) {
            client = await Client.findByIdAndUpdate(paramId, raw, { new: true });
        }

        if (!client) {
            const { password: _pw, ...companyBody } = req.body;
            client = await Company.findByIdAndUpdate(paramId, companyBody, { new: true });
        }

        if (!client) return res.status(404).json({ error: 'Client non trouvé' });
        console.log(`✅ Client modifié : ${client.name}`);
        res.json(client.toJSON ? client.toJSON() : client);
    } catch (err) {
        console.error('❌ Erreur Modification Client:', err.message);
        if (err.code === 11000) {
            return res.status(409).json({ error: 'Email déjà utilisé' });
        }
        res.status(500).json({ error: err.message });
    }
});

app.delete('/api/clients/:id', requireAuth, requireSuperAdmin, async (req, res) => {
    try {
        let client = await Client.findOneAndDelete({ clientId: req.params.id });
        
        if (!client) {
            // Fallback pour Company
            client = await Company.findByIdAndDelete(req.params.id);
        }
        
        if (!client) return res.status(404).json({ error: 'Client non trouvé' });
        console.log(`🗑️ Client supprimé : ${client.name}`);
        res.json({ message: 'Client supprimé avec succès' });
    } catch (err) {
        console.error('❌ Erreur Suppression Client:', err.message);
        res.status(500).json({ error: err.message });
    }
});

// ============================================================
// ROUTES: CONSULTER LES DONNÉES
// ============================================================

app.get('/api/historique', async function (req, res) {
    let mId = req.query.machineId;
    try {
        if (mId) {
            const docs = await Telemetry.find({ machineId: mId }).sort({ createdAt: -1 }).limit(100);
            return res.json(docs);
        }
        const allTelemetry = await Telemetry.find().sort({ createdAt: -1 }).limit(200);
        res.json(allTelemetry);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.get('/api/alertes', async function (req, res) {
    try {
        const alerts = await Alert.find({ resolved: false }).sort({ createdAt: -1 });
        res.json(alerts);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.get('/api/status', async function (req, res) {
    try {
        const machineCount = await Machine.countDocuments();
        const alertCount = await Alert.countDocuments({ resolved: false });
        res.json({
            serveur: 'Node.js + MongoDB',
            port: PORT,
            database: 'Connectée',
            stats: {
                machines: machineCount,
                alertes_actives: alertCount
            }
        });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.get('/api/chat/messages', async (req, res) => {
    try {
        const roomId = String(req.query.roomId || '');
        if (!roomId) return res.status(400).json({ error: 'roomId requis' });
        const limit = Math.max(1, Math.min(Number(req.query.limit || 100), 500));
        const docs = await ChatMessage.find({ roomId }).sort({ createdAt: 1 }).limit(limit);
        res.json(docs);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.get('/api/chat/technician-conversations', async (req, res) => {
    try {
        const technicianId = String(req.query.technicianId || '');
        if (!technicianId) return res.status(400).json({ error: 'technicianId requis' });
        const tech = await Technician.findOne({ technicianId });
        if (!tech) return res.json([]);
        const roomId = `chat_${tech.companyId}_${technicianId}`;
        const last = await ChatMessage.findOne({ roomId }).sort({ createdAt: -1 });
        const client = await Client.findOne({
            $or: [{ clientId: tech.companyId }, { _id: tech.companyId }]
        });
        res.json([{
            roomId,
            clientId: String(tech.companyId || ''),
            clientName: client?.name || String(tech.companyId || 'Client'),
            technicianId,
            technicianName: tech.name || 'Technicien',
            lastText: last?.text || '',
            lastAt: last?.createdAt || null,
        }]);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.get('/api/chat/client-conversations', async (req, res) => {
    try {
        const clientId = String(req.query.clientId || '');
        if (!clientId) return res.status(400).json({ error: 'clientId requis' });
        const techs = await Technician.find({ companyId: clientId });
        const rows = [];
        for (const t of techs) {
            const roomId = `chat_${clientId}_${t.technicianId}`;
            const last = await ChatMessage.findOne({ roomId }).sort({ createdAt: -1 });
            rows.push({
                roomId,
                clientId,
                clientName: clientId,
                technicianId: t.technicianId,
                technicianName: t.name || 'Technicien',
                lastText: last?.text || '',
                lastAt: last?.createdAt || null,
            });
        }
        rows.sort((a, b) => new Date(b.lastAt || 0) - new Date(a.lastAt || 0));
        res.json(rows);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.get('/api/chat/conception-conversations', async (req, res) => {
    try {
        const techs = await Technician.find({});
        const rows = [];
        for (const t of techs) {
            const roomId = `chat_conception_${t.technicianId}`;
            const last = await ChatMessage.findOne({ roomId }).sort({ createdAt: -1 });
            rows.push({
                roomId,
                clientId: 'conception',
                clientName: t.name || 'Technicien',
                technicianId: t.technicianId,
                technicianName: t.name || 'Technicien',
                specialization: t.specialization || '',
                lastText: last?.text || '',
                lastAt: last?.createdAt || null,
            });
        }
        rows.sort((a, b) => new Date(b.lastAt || 0) - new Date(a.lastAt || 0));
        res.json(rows);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.post('/api/clients/:id/machines', requireAuth, requireFleetManager, async (req, res) => {
    try {
        const clientId = req.params.id;
        if (!(await assertFleetCompanyAccess(req, res, clientId))) return;
        const { assignedTechnicianIds, ...restBody } = req.body;
        const techIds = Array.isArray(assignedTechnicianIds)
            ? assignedTechnicianIds.map((x) => String(x)).filter(Boolean)
            : [];

        const aliases = await buildCompanyAliasSet(clientId);
        const techCount = await Technician.countDocuments({ companyId: { $in: Array.from(aliases) } });

        if (techIds.length < 1) {
            if (techCount > 0) {
                return res.status(400).json({
                    error: 'Au moins un technicien doit être assigné à cette machine (obligatoire lorsqu\'il existe déjà des techniciens pour ce client).'
                });
            }
        } else {
            for (const tid of techIds) {
                const t = await Technician.findOne({ technicianId: tid });
                if (!t || !aliases.has(String(t.companyId))) {
                    return res.status(400).json({
                        error: `Technicien invalide ou non rattaché à ce client : ${tid}`
                    });
                }
            }
        }

        const machine = new Machine({
            ...restBody,
            companyId: clientId,
            status: 'STOPPED'
        });

        if (!machine._id) machine._id = 'MAC-' + Date.now();

        machine.motorType = normalizeMotorType(machine.motorType || 'EL_M');
        const rsNew = Number(restBody.rulHoursPerModelUnit);
        machine.rulHoursPerModelUnit = Number.isFinite(rsNew) && rsNew > 0 ? rsNew : null;

        await machine.save();

        const mid = String(machine._id);
        for (const tid of techIds) {
            await Technician.updateOne(
                { technicianId: tid },
                { $addToSet: { machineIds: mid } }
            );
        }

        let updatedClient = await Client.findOneAndUpdate(
            { clientId: clientId },
            { $inc: { machines: 1 } },
            { new: true }
        );

        if (!updatedClient && mongoose.Types.ObjectId.isValid(clientId)) {
            updatedClient = await Client.findByIdAndUpdate(clientId, { $inc: { machines: 1 } }) ||
                await Company.findByIdAndUpdate(clientId, { $inc: { machines: 1 } });
        }

        const assignMsg = techIds.length > 0 ? `${techIds.length} technicien(s)` : 'sans technicien (première machine — créez ensuite un technicien lié à cette machine)';
        console.log(`✅ Machine "${machine.name}" ajoutée au client ${clientId} (${assignMsg})`);
        res.status(201).json(machine);
    } catch (err) {
        console.error('❌ Erreur Ajout Machine:', err.message);
        res.status(500).json({ error: err.message });
    }
});

app.get('/api/clients/:id/machines', async (req, res) => {
    try {
        const aliases = await buildCompanyAliasSet(req.params.id);
        let docs = await Machine.find({
            ...machineDbOnlyFilter,
            companyId: { $in: Array.from(aliases) },
        })
            .sort({ updatedAt: -1, createdAt: -1 })
            .lean();
        docs = filterOutDemoMachinesIfNeeded(docs);
        res.set('Cache-Control', 'no-store, must-revalidate');
        res.json(serializeMachineDocs(docs));
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.get('/api/clients/:id/technicians', async (req, res) => {
    try {
        const id = req.params.id;
        const client = await Client.findOne({ clientId: id }) || (mongoose.Types.ObjectId.isValid(id) ? await Client.findById(id) : null);
        const aliases = new Set([id]);
        if (client) {
            aliases.add(String(client._id));
            if (client.clientId) aliases.add(String(client.clientId));
            if (client.name) aliases.add(String(client.name));
        }

        const technicians = await Technician.find({ companyId: { $in: Array.from(aliases) } });
        res.json(technicians);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.get('/api/machines', async (req, res) => {
    try {
        let docs = await Machine.find(machineDbOnlyFilter)
            .sort({ updatedAt: -1, createdAt: -1 })
            .lean();
        docs = filterOutDemoMachinesIfNeeded(docs);
        res.set('Cache-Control', 'no-store, must-revalidate');
        res.json(serializeMachineDocs(docs));
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.get('/api/health', function (req, res) {
    res.json({
        ok: true,
        service: 'iot-backend/server.js',
        port: PORT,
        ml_server: ML_SERVER,
        mongo: mongoose.connection.readyState === 1 ? 'connected' : 'disconnected',
        api: {
            teamDirectory: 'GET /api/team-directory',
            concepteurs: 'GET /api/concepteurs',
            conceptions: 'GET /api/conceptions',
            maintenanceAgents: 'GET /api/maintenance-agents',
        },
    });
});

app.get('/api/model-metrics', function (req, res) {
    try {
        const metricsPath = resolveModelMetricsPath();
        if (!metricsPath) {
            return res.json({
                panne_accuracy: null,
                source: 'metrics.json introuvable',
            });
        }
        const content = fs.readFileSync(metricsPath, 'utf-8');
        const data = JSON.parse(content);
        return res.json(data);
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
});

// ============================================================
// WEBSOCKET: CONNEXION TEMPS REEL
// ============================================================

io.on('connection', function (socket) {
    console.log('Client dashboard connecte: ' + socket.id);

    Object.values(machines).forEach(m => {
        if (m.derniere) {
            socket.emit('nouvelle_prediction', m.derniere);
        }
    });

    socket.on('test_prediction', async function (data) {
        const raw = data && typeof data === 'object' ? data : {};
        let mId = raw.machineId || 'MAC_A01';
        const tp = await getMachineMlProfile(mId);
        const mlData = buildMlPayload(raw, mId, tp);
        let prediction = await envoyerAuML(mlData);
        prediction = enrichMlResultWithRulHours(prediction, tp, mlData.type_moteur);
        prediction.machineId = mId;

        if (!machines[mId]) machines[mId] = { historique: [], alertes: [], derniere: null, machineId: mId };

        machines[mId].historique.push(prediction);
        machines[mId].derniere = prediction;

        io.emit('nouvelle_prediction', prediction);

        if (prediction.prediction === 1) {
            machines[mId].alertes.push(prediction);
            io.emit('alerte_panne', prediction);
        }
    });

    socket.on('simuler_degradation', async function (data) {
        let mId = (data && data.machineId) || 'MAC_A01';
        console.log(`Simulation degradation [${mId}] lancee...`);

        let etapes = [
            { rpm: 1500, torque: 42, tool_wear: 50, pressure: 120, ultrasonic: 40, presence: 1, magnetic: 45, infrared: 30, machine_type: 'M' },
            { rpm: 1600, torque: 45, tool_wear: 80, pressure: 130, ultrasonic: 42, presence: 1, magnetic: 48, infrared: 35, machine_type: 'M' },
            { rpm: 1800, torque: 50, tool_wear: 120, pressure: 145, ultrasonic: 45, presence: 1, magnetic: 52, infrared: 42, machine_type: 'M' },
            { rpm: 2000, torque: 53, tool_wear: 160, pressure: 160, ultrasonic: 38, presence: 1, magnetic: 58, infrared: 50, machine_type: 'M' },
            { rpm: 2200, torque: 56, tool_wear: 185, pressure: 175, ultrasonic: 35, presence: 1, magnetic: 65, infrared: 60, machine_type: 'M' },
            { rpm: 2400, torque: 58, tool_wear: 195, pressure: 185, ultrasonic: 30, presence: 1, magnetic: 72, infrared: 70, machine_type: 'M' },
            { rpm: 2600, torque: 62, tool_wear: 205, pressure: 195, ultrasonic: 25, presence: 0, magnetic: 80, infrared: 82, machine_type: 'M' },
            { rpm: 2700, torque: 65, tool_wear: 215, pressure: 205, ultrasonic: 20, presence: 0, magnetic: 85, infrared: 88, machine_type: 'M' },
            { rpm: 2800, torque: 68, tool_wear: 220, pressure: 215, ultrasonic: 15, presence: 0, magnetic: 92, infrared: 92, machine_type: 'M' },
            { rpm: 2900, torque: 72, tool_wear: 230, pressure: 230, ultrasonic: 10, presence: 0, magnetic: 98, infrared: 98, machine_type: 'M' },
        ];

        for (let i = 0; i < etapes.length; i++) {
            await new Promise(function (resolve) {
                setTimeout(async function () {
                    let stepData = { ...etapes[i], machineId: mId };
                    const sp = await getMachineMlProfile(mId);
                    const mlStep = buildMlPayload(stepData, mId, sp);
                    let prediction = await envoyerAuML(mlStep);
                    prediction = enrichMlResultWithRulHours(prediction, sp, mlStep.type_moteur);
                    prediction.machineId = mId;

                    if (!machines[mId]) machines[mId] = { historique: [], alertes: [], derniere: null, machineId: mId };
                    machines[mId].historique.push(prediction);
                    machines[mId].derniere = prediction;

                    io.emit('nouvelle_prediction', prediction);
                    if (prediction.prediction === 1) {
                        machines[mId].alertes.push(prediction);
                        io.emit('alerte_panne', prediction);
                    }
                    resolve();
                }, 1000);
            });
        }
    });

    socket.on('join_chat_room', function (payload) {
        const roomId = payload && payload.roomId;
        if (!roomId) return;
        socket.join(roomId);
        socket.emit('chat_system', { roomId, message: 'Connecté au salon de discussion' });
    });

    socket.on('chat_message', async function (payload) {
        const roomId = payload && payload.roomId;
        if (!roomId) return;
        const msg = {
            roomId,
            from: payload.from || 'client',
            senderName: payload.senderName || 'Utilisateur',
            text: payload.text || '',
            createdAt: new Date().toISOString(),
        };
        try {
            if (String(msg.text).trim().length > 0) {
                const parsed = parseChatRoom(roomId);
                await ChatMessage.create({
                    roomId,
                    from: msg.from,
                    senderName: msg.senderName,
                    text: msg.text,
                    meta: parsed,
                });
            }
        } catch (e) {
            console.error('❌ chat save error:', e.message);
        }
        io.to(roomId).emit('chat_message', msg);
    });

    socket.on('machine_stop', async function (payload) {
        const machineId = payload && payload.machineId;
        if (!machineId) return;

        console.log(`🛑 [Socket] Arrêt machine ${machineId} par ${payload.stoppedBy || 'inconnu'}`);

        // Envoyer la commande STOP via MQTT
        const cmdTopic = `machines/${machineId}/control`;
        const cmdPayload = JSON.stringify({
            action: 'emergency_stop',
            machineId,
            reason: payload.reason || 'Arrêt d\'urgence',
            stoppedBy: payload.stoppedBy || 'Système',
            at: new Date().toISOString(),
        });
        mqttClient.publish(cmdTopic, cmdPayload, { qos: 1 });

        // Mettre à jour en base
        try {
            await Machine.findByIdAndUpdate(machineId, { status: 'STOPPED' });
        } catch (e) { /* ignore */ }

        io.emit('machine_status_update', {
            machineId,
            status: 'STOPPED',
            stoppedBy: payload.stoppedBy,
        });
    });

    socket.on('panne_alert', async function (payload) {
        const machineId = payload && payload.machineId;
        if (!machineId) return;
        const alertText = payload.alertText || `[ALERTE] Machine ${machineId} : risque ${payload.riskPercent || '?'}%`;
        try {
            const machine = await Machine.findOne({
                $or: [{ _id: machineId }, { machineId }]
            });
            if (machine) {
                const companyId = String(machine.companyId || '');
                const techs = await Technician.find({ machineIds: String(machine._id) });
                for (const t of techs) {
                    const roomId = `chat_${companyId}_${t.technicianId}`;
                    const msg = {
                        roomId,
                        from: 'system',
                        senderName: 'Système IA',
                        text: alertText,
                        createdAt: new Date().toISOString(),
                    };
                    try {
                        await ChatMessage.create({ roomId, from: 'system', senderName: 'Système IA', text: alertText });
                    } catch (e) { console.error('panne_alert save err:', e.message); }
                    io.to(roomId).emit('chat_message', msg);
                }
            }
        } catch (e) {
            console.error('panne_alert handler error:', e.message);
        }
        io.emit('panne_notification', {
            machineId,
            riskPercent: payload.riskPercent || 0,
            alertText,
            at: new Date().toISOString(),
        });
    });

    socket.on('call_request', function (payload) {
        const roomId = payload && payload.roomId;
        if (!roomId) return;
        io.to(roomId).emit('call_request', {
            roomId,
            from: payload.from || 'client',
            callerName: payload.callerName || 'Utilisateur',
            at: new Date().toISOString(),
        });
    });

    socket.on('call_response', function (payload) {
        const roomId = payload && payload.roomId;
        if (!roomId) return;
        io.to(roomId).emit('call_response', {
            roomId,
            accepted: !!payload.accepted,
            responderName: payload.responderName || 'Technicien',
            at: new Date().toISOString(),
        });
    });

    socket.on('webrtc_offer', function (payload) {
        const roomId = payload && payload.roomId;
        if (!roomId || !payload.offer) return;
        socket.to(roomId).emit('webrtc_offer', {
            roomId,
            offer: payload.offer,
            from: payload.from || 'client',
            senderName: payload.senderName || 'Utilisateur',
        });
    });

    socket.on('webrtc_answer', function (payload) {
        const roomId = payload && payload.roomId;
        if (!roomId || !payload.answer) return;
        socket.to(roomId).emit('webrtc_answer', {
            roomId,
            answer: payload.answer,
            from: payload.from || 'client',
            senderName: payload.senderName || 'Utilisateur',
        });
    });

    socket.on('webrtc_ice_candidate', function (payload) {
        const roomId = payload && payload.roomId;
        if (!roomId || !payload.candidate) return;
        socket.to(roomId).emit('webrtc_ice_candidate', {
            roomId,
            candidate: payload.candidate,
        });
    });

    socket.on('call_end', function (payload) {
        const roomId = payload && payload.roomId;
        if (!roomId) return;
        io.to(roomId).emit('call_end', { roomId });
    });

    socket.on('disconnect', function () {
        console.log('Client deconnecte');
    });
});

// Routes /api non définies → JSON explicite (évite un 404 HTML confus depuis un autre service)
app.use((req, res, next) => {
    if (req.path.startsWith('/api')) {
        console.warn('[404 API]', req.method, req.originalUrl);
        return res.status(404).json({
            error: 'Route API inconnue sur ce serveur',
            path: req.originalUrl,
            hint: 'Lancez iot-backend avec: npm start (server.js, port 3001). Test: GET /api/health',
        });
    }
    next();
});

// Dashboard statique (après toutes les routes API — évite des 404 fantômes sur /api/*)
app.use(express.static(path.join(__dirname, 'dashboard')));

// ============================================================
// DEMARRER LE SERVEUR
// ============================================================

server.listen(PORT, function () {
    console.log('');
    console.log('==================================================');
    console.log('  SERVEUR NODE.JS - RELAIS IA');
    console.log('==================================================');
    console.log('  Dashboard: http://localhost:' + PORT);
    console.log('  API ESP32:  http://localhost:' + PORT + '/api/sensor-data');
    console.log('  API Predict: http://localhost:' + PORT + '/api/predict');
    console.log('  ML Server:  ' + ML_SERVER);
    console.log('==================================================');
    console.log('');
    console.log('  En attente des donnees ESP32...');
});
