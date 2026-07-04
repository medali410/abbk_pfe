// src/controllers/maintenanceAgentController.js
const AgentModel = require('../models/maintenanceAgentModel');
const { serializeMaintenanceAgent, serializeMaintenanceAgentDashboard } = require('../views/maintenanceAgentView');
const { createUserWithProfile, hashPassword, getAuthUserId } = require('../lib/auth');
const { prisma } = require('../lib/prisma');
const { sendWelcomeEmail } = require('../services/emailService');

// ─── Helpers ─────────────────────────────────────────────────────────────────

async function loadMachineData(profile) {
    let machineIds = [];
    try { machineIds = JSON.parse(profile.machineIds || '[]'); } catch (_) {}

    const machines = machineIds.length
        ? await prisma.machine.findMany({
              where: { id: { in: machineIds } },
              select: { id: true, name: true, type: true, status: true, location: true, motorType: true },
          })
        : [];

    const telemetryMap = {};
    for (const m of machines) {
        const t = await prisma.telemetry.findFirst({
            where: { machineId: m.id },
            orderBy: { timestamp: 'desc' },
        });
        if (t) {
            telemetryMap[m.id] = {
                ...t,
                temperature: t.temp,
                pressure: t.voltage,
                voltage: t.voltage,
                magnetic: t.magnet
            };
        }
    }
    return { machines, telemetryMap };
}

// ─── Admin / Fleet Manager ────────────────────────────────────────────────────

/** GET /api/maintenance-agents */
async function listMaintenanceAgents(req, res) {
    try {
        const { clientId } = req.query;
        const rows = await AgentModel.listMaintenanceAgents({ clientId });
        res.set('Cache-Control', 'no-store');
        return res.json(rows.map(a => serializeMaintenanceAgent(a.user, a)));
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

/** GET /api/maintenance-agents/:id */
async function getMaintenanceAgent(req, res) {
    try {
        const row = await AgentModel.getAgentByIdOrCode(req.params.id);
        if (!row) return res.status(404).json({ error: 'Agent de maintenance introuvable' });
        return res.json(serializeMaintenanceAgent(row.user, row));
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

/** POST /api/maintenance-agents */
async function createMaintenanceAgent(req, res) {
    let createdUserId = null;
    try {
        const {
            email, password, name,
            firstName = '', lastName = '',
            address = '', clientId = '',
            machineIds = [],
        } = req.body;

        if (!email || !password)
            return res.status(400).json({ error: 'email et password sont obligatoires' });

        const { user, profile } = await createUserWithProfile(
            'maintenance',
            { email, nom: name || `${firstName} ${lastName}`.trim(), password, adresse: address },
            {
                firstName, lastName, clientId,
                machineIds: JSON.stringify(Array.isArray(machineIds) ? machineIds : []),
            },
        );
        createdUserId = user.id;

        // ✉️ Envoyer l'e-mail de bienvenue (non bloquant : si l'email échoue, le compte est quand même créé)
        try {
            await sendWelcomeEmail({
                to: email,
                name: user.nom || `${firstName} ${lastName}`.trim() || email,
                password, // mot de passe en clair (avant hachage)
                role: 'Agent de Maintenance',
            });
            console.log(`✉️  E-mail de bienvenue envoyé à ${email}`);
        } catch (mailErr) {
            console.warn(`⚠️  Impossible d'envoyer l'e-mail de bienvenue à ${email}:`, mailErr.message);
        }

        return res.status(201).json(serializeMaintenanceAgent(user, profile));

    } catch (err) {
        if (createdUserId) {
            try { await prisma.user.delete({ where: { id: createdUserId } }); } catch (_) {}
        }
        return res.status(err.status || 500).json({ error: err.message });
    }
}

/** PUT /api/maintenance-agents/:id */
async function updateMaintenanceAgent(req, res) {
    try {
        const existing = await AgentModel.getAgentByIdOrCode(req.params.id);
        if (!existing) return res.status(404).json({ error: 'Agent de maintenance introuvable' });

        const { email, password, name, firstName, lastName, address, clientId, machineIds } = req.body;

        const userData = {};
        if (email)    userData.email    = email;
        if (name)     userData.nom      = name;
        if (address)  userData.adresse  = address;
        if (password) userData.password = await hashPassword(password);

        const updatedUser = Object.keys(userData).length
            ? await prisma.user.update({ where: { id: existing.userId }, data: userData })
            : existing.user;

        const profileData = {};
        if (firstName  !== undefined) profileData.firstName  = firstName;
        if (lastName   !== undefined) profileData.lastName   = lastName;
        if (clientId   !== undefined) profileData.clientId   = clientId;
        if (machineIds !== undefined) profileData.machineIds = JSON.stringify(Array.isArray(machineIds) ? machineIds : []);

        const updatedProfile = Object.keys(profileData).length
            ? await AgentModel.updateAgentProfile(existing.id, profileData)
            : existing;

        return res.json(serializeMaintenanceAgent(updatedUser, updatedProfile));
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

/** DELETE /api/maintenance-agents/:id */
async function deleteMaintenanceAgent(req, res) {
    try {
        const existing = await AgentModel.getAgentByIdOrCode(req.params.id);
        if (!existing) return res.status(404).json({ error: 'Agent de maintenance introuvable' });
        await AgentModel.deleteAgent(existing.userId);
        return res.json({ success: true, deleted: existing.maintenanceAgentId });
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

/** PATCH /api/maintenance-agents/:id/machines */
async function assignMachines(req, res) {
    try {
        const existing = await AgentModel.getAgentByIdOrCode(req.params.id);
        if (!existing) return res.status(404).json({ error: 'Agent de maintenance introuvable' });

        const { machineIds = [] } = req.body;
        if (!Array.isArray(machineIds))
            return res.status(400).json({ error: 'machineIds doit être un tableau' });

        const updated = await AgentModel.setMachineIds(existing.id, machineIds);
        return res.json(serializeMaintenanceAgent(existing.user, updated));
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

// ─── Self (agent connecté) ────────────────────────────────────────────────────

/** GET /api/maintenance-agents/me */
async function getMyProfile(req, res) {
    try {
        const userId = getAuthUserId(req.auth);
        if (!userId) return res.status(401).json({ error: 'Non authentifié' });

        const profile = await AgentModel.getAgentByUserId(userId);
        if (!profile) return res.status(404).json({ error: 'Profil agent de maintenance introuvable' });

        const { machines, telemetryMap } = await loadMachineData(profile);

        const purchaseRequests = profile.clientId
            ? await prisma.purchaseRequest.findMany({
                  where: { linkedClientId: profile.clientId },
                  orderBy: { createdAt: 'desc' },
                  take: 10,
              })
            : [];

        res.set('Cache-Control', 'no-store');
        return res.json(
            serializeMaintenanceAgentDashboard(profile.user, profile, machines, telemetryMap, purchaseRequests),
        );
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

/** PATCH /api/maintenance-agents/me */
async function updateMyProfile(req, res) {
    try {
        const userId = getAuthUserId(req.auth);
        if (!userId) return res.status(401).json({ error: 'Non authentifié' });

        const profile = await AgentModel.getAgentByUserId(userId);
        if (!profile) return res.status(404).json({ error: 'Profil agent de maintenance introuvable' });

        const { nom, adresse, firstName, lastName, password } = req.body;

        const userData = {};
        if (nom)      userData.nom     = nom;
        if (adresse)  userData.adresse = adresse;
        if (password) userData.password = await hashPassword(password);

        const updatedUser = Object.keys(userData).length
            ? await prisma.user.update({ where: { id: userId }, data: userData })
            : profile.user;

        const profileData = {};
        if (firstName !== undefined) profileData.firstName = firstName;
        if (lastName  !== undefined) profileData.lastName  = lastName;

        const updatedProfile = Object.keys(profileData).length
            ? await AgentModel.updateAgentProfile(profile.id, profileData)
            : profile;

        return res.json(serializeMaintenanceAgent(updatedUser, updatedProfile));
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

/** GET /api/maintenance-agents/me/telemetry */
async function getMyMachinesTelemetry(req, res) {
    try {
        const userId = getAuthUserId(req.auth);
        if (!userId) return res.status(401).json({ error: 'Non authentifié' });

        const profile = await AgentModel.getAgentByUserId(userId);
        if (!profile) return res.status(404).json({ error: 'Profil agent de maintenance introuvable' });

        let machineIds = [];
        try { machineIds = JSON.parse(profile.machineIds || '[]'); } catch (_) {}

        const results = await Promise.all(
            machineIds.map(async (mid) => {
                const machine   = await prisma.machine.findUnique({ where: { id: mid }, select: { id: true, name: true, status: true, type: true } });
                const telemetry = await prisma.telemetry.findFirst({ where: { machineId: mid }, orderBy: { timestamp: 'desc' } });
                const mappedTelemetry = telemetry ? {
                    ...telemetry,
                    temperature: telemetry.temp,
                    pressure: telemetry.voltage,
                    voltage: telemetry.voltage,
                    magnetic: telemetry.magnet
                } : null;
                return { machine: machine || { id: mid, name: 'Inconnue' }, telemetry: mappedTelemetry };
            }),
        );
        return res.json(results);
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

/** POST /api/maintenance-agents/me/purchase-requests */
async function submitPurchaseRequest(req, res) {
    try {
        const userId = getAuthUserId(req.auth);
        if (!userId) return res.status(401).json({ error: 'Non authentifié' });

        const profile = await AgentModel.getAgentByUserId(userId);
        if (!profile) return res.status(404).json({ error: 'Profil agent de maintenance introuvable' });

        const { machineId, note = '', requesterName, requesterEmail = '', requesterPhone = '', location = '', googleMapsUrl = '' } = req.body;
        if (!machineId) return res.status(400).json({ error: 'machineId est obligatoire' });

        const machine = await prisma.machine.findUnique({ where: { id: machineId } });
        if (!machine) return res.status(404).json({ error: 'Machine introuvable' });

        const pr = await prisma.purchaseRequest.create({
            data: {
                machineId,
                machineName:    machine.name,
                linkedClientId: profile.clientId || '',
                requesterName:  requesterName || profile.user.nom,
                requesterEmail,
                requesterPhone,
                location,
                googleMapsUrl,
                note,
                status:         'PENDING',
                requestType:    'MAINTENANCE',
            },
        });
        return res.status(201).json(pr);
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

module.exports = {
    listMaintenanceAgents, getMaintenanceAgent, createMaintenanceAgent,
    updateMaintenanceAgent, deleteMaintenanceAgent, assignMachines,
    getMyProfile, updateMyProfile, getMyMachinesTelemetry, submitPurchaseRequest,
};
