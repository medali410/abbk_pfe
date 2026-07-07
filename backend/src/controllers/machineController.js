const MachineModel = require('../models/machineModel');
const { serializeMachine } = require('../views/machineView');
const { validateCreateMachine, validateUpdateMachine } = require('../lib/validators');
const mqtt = require('../lib/mqtt');

async function getUserConcepteurId(req) {
    if (req.auth?.concepteurId) return String(req.auth.concepteurId);
    if (!req.auth?.userId) return null;
    const { PrismaClient } = require('@prisma/client');
    const prisma = new PrismaClient();
    const c = await prisma.concepteur.findUnique({ where: { userId: Number(req.auth.userId) } });
    return c ? String(c.id) : String(req.auth.userId);
}

async function list(req, res) {
    try {
        const catalog = String(req.query.catalog || '') === '1';
        const includeAll = String(req.query.includeAllMongo || '') === '1';
        const unassigned = String(req.query.unassigned || '') === '1';
        const maintenanceAgentId = req.query.maintenanceAgentId || null;
        let concepterId = req.query.concepterId || null;
        let concepteurMachineIds = [];
        if (req.auth?.role === 'conception' || req.auth?.role === 'concepteur') {
            const userConcepteurId = await getUserConcepteurId(req);
            concepterId = userConcepteurId;
            const { prisma } = require('../lib/prisma');
            const concepteurObj = await prisma.concepteur.findUnique({ where: { id: parseInt(userConcepteurId) } });
            if (concepteurObj) {
                try { concepteurMachineIds = JSON.parse(concepteurObj.machineIds || '[]'); } catch (e) { }
            }
        }

        let rows = await MachineModel.findMany({ catalog, includeAll, unassigned, concepterId });
        if (req.auth?.role === 'conception' || req.auth?.role === 'concepteur') {
            rows = rows.filter(m => String(m.concepteurId) === String(concepterId) || concepteurMachineIds.includes(String(m.id)) || concepteurMachineIds.includes(String(m._id)));
        }

        if (maintenanceAgentId) {
            const { prisma } = require('../lib/prisma');
            const agent = await prisma.maintenanceAgent.findFirst({
                where: { OR: [{ maintenanceAgentId }, { userId: parseInt(maintenanceAgentId) || 0 }] }
            });
            if (agent) {
                let mIds = [];
                try { mIds = JSON.parse(agent.machineIds || '[]'); } catch (e) { }
                rows = rows.filter(m => mIds.includes(String(m.id)) || mIds.includes(String(m._id)));
            } else {
                rows = [];
            }
        }

        if (req.auth?.role === 'technician') {
            const { prisma } = require('../lib/prisma');
            const tech = await prisma.technician.findUnique({ where: { userId: Number(req.auth.userId) } });
            if (tech) {
                let mIds = [];
                try { mIds = JSON.parse(tech.machineIds || '[]'); } catch (e) { }
                // BYPASS FILTER FOR DEMO DEMO DEMO
                // rows = rows.filter(m => mIds.includes(String(m.id)) || String(m.technicianId) === tech.technicianId);
            } else {
                // rows = [];
            }
        }

        const { PrismaClient } = require('@prisma/client');
        const prisma = new PrismaClient();
        const concepteurs = await prisma.concepteur.findMany({ include: { user: true } });
        const concepteurMap = {};
        concepteurs.forEach(c => {
            concepteurMap[String(c.id)] = c.user?.nom || 'Inconnu';
        });

        const serializedRows = rows.map(m => {
            const sm = serializeMachine(m);
            sm.concepteurName = concepteurMap[sm.concepteurId] || 'Inconnu';
            return sm;
        });

        res.set('Cache-Control', 'no-store');
        return res.json(serializedRows);
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

async function create(req, res) {
    try {
        const createErrors = validateCreateMachine(req.body);
        if (createErrors.length > 0) {
            return res.status(400).json({ error: createErrors.join(' | '), errors: createErrors });
        }
        const row = await MachineModel.create(req.body);
        return res.status(201).json(serializeMachine(row));
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

async function getById(req, res) {
    try {
        const row = await MachineModel.findById(req.params.machineId);
        if (!row) return res.status(404).json({ error: 'Machine introuvable' });

        if (req.auth?.role === 'conception' || req.auth?.role === 'concepteur') {
            const userConcepteurId = await getUserConcepteurId(req);
            const { prisma } = require('../lib/prisma');
            const concepteurObj = await prisma.concepteur.findUnique({ where: { id: parseInt(userConcepteurId) } });
            let allowedIds = [];
            if (concepteurObj) {
                try { allowedIds = JSON.parse(concepteurObj.machineIds || '[]'); } catch (e) { }
            }
            if (String(row.concepteurId) !== userConcepteurId && !allowedIds.includes(String(row.id))) {
                return res.status(403).json({ error: 'Accès interdit. Cette machine ne fait pas partie de votre parc.' });
            }
        }
        return res.json(serializeMachine(row));
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

async function stop(req, res) {
    try {
        const { machineId } = req.params;
        const { reason, stoppedBy } = req.body;
        const existing = await MachineModel.findById(machineId);
        if (!existing) return res.status(404).json({ error: 'Machine introuvable' });

        if (req.auth?.role === 'conception' || req.auth?.role === 'concepteur') {
            const userConcepteurId = await getUserConcepteurId(req);
            if (existing.concepteurId && String(existing.concepteurId) !== userConcepteurId) {
                return res.status(403).json({ error: 'Accès en lecture seule. Vous ne pouvez arrêter que vos propres machines.' });
            }
        }

        console.log(`🛑 ARRÊT D'URGENCE machine ${machineId} par ${stoppedBy || 'inconnu'}. Raison: ${reason || 'non spécifiée'}`);

        mqtt.publish(`machines/${machineId}/control`, JSON.stringify({ command: 'OFF' }));

        const row = await MachineModel.updateStatus(machineId, 'STOPPED');
        return res.json({
            success: true,
            message: 'Machine arrêtée avec succès',
            machine: serializeMachine(row)
        });
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

async function remove(req, res) {
    try {
        const { machineId } = req.params;
        const row = await MachineModel.findById(machineId);
        if (!row) return res.status(404).json({ error: 'Machine introuvable' });

        if (req.auth?.role === 'conception' || req.auth?.role === 'concepteur') {
            const userConcepteurId = await getUserConcepteurId(req);
            if (row.concepteurId && String(row.concepteurId) !== userConcepteurId) {
                return res.status(403).json({ error: 'Accès en lecture seule. Vous ne pouvez supprimer que vos propres machines.' });
            }
        }

        await MachineModel.remove(machineId);
        return res.json({
            success: true,
            message: 'Machine supprimée avec succès'
        });
    } catch (err) {
        console.error('Erreur lors de la suppression de la machine:', err);
        return res.status(500).json({ error: err.message });
    }
}

async function update(req, res) {
    try {
        const { machineId } = req.params;
        const existing = await MachineModel.findById(machineId);
        if (!existing) return res.status(404).json({ error: 'Machine introuvable' });

        if (req.auth?.role === 'conception' || req.auth?.role === 'concepteur') {
            const userConcepteurId = await getUserConcepteurId(req);
            if (existing.concepteurId && String(existing.concepteurId) !== userConcepteurId) {
                return res.status(403).json({ error: 'Accès en lecture seule. Vous ne pouvez modifier que vos propres machines.' });
            }
        }

        const updateErrors = validateUpdateMachine(req.body);
        if (updateErrors.length > 0) {
            return res.status(400).json({ error: updateErrors.join(' | '), errors: updateErrors });
        }
        const row = await MachineModel.update(machineId, req.body);
        return res.json(serializeMachine(row));
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

async function start(req, res) {
    try {
        const { machineId } = req.params;
        const existing = await MachineModel.findById(machineId);
        if (!existing) return res.status(404).json({ error: 'Machine introuvable' });

        if (req.auth?.role === 'conception' || req.auth?.role === 'concepteur') {
            const userConcepteurId = await getUserConcepteurId(req);
            if (existing.concepteurId && String(existing.concepteurId) !== userConcepteurId) {
                return res.status(403).json({ error: 'Accès en lecture seule. Vous ne pouvez démarrer que vos propres machines.' });
            }
        }

        if (existing.status === 'STOPPED_DANGER') {
            return res.status(403).json({ error: 'Démarrage bloqué : La machine est en ARRÊT DANGER. Veuillez réinitialiser la sécurité d\'abord.' });
        }

        console.log(`🚀 DÉMARRAGE machine ${machineId}`);

        mqtt.publish(`machines/${machineId}/control`, JSON.stringify({ command: 'ON' }));

        const row = await MachineModel.updateStatus(machineId, 'RUNNING');
        return res.json({
            success: true,
            message: 'Machine démarrée avec succès',
            machine: serializeMachine(row)
        });
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
}

const { prisma } = require('../lib/prisma');

async function saveConfigAndPublish(req, res) {
    try {
        const { machineId } = req.params;
        const { ssid, password, newMachineId } = req.body;

        if (!ssid || !password) {
            return res.status(400).json({ error: 'SSID et mot de passe WiFi obligatoires' });
        }

        // 1. Publication MQTT (sur l'ancien topic pour que l'ESP32 reçoive la config)
        const topic = `machines/${machineId}/config`;
        const payload = {
            ssid,
            password,
            machineId: newMachineId || machineId
        };
        mqtt.publish(topic, payload);

        // 2. Sauvegarde en DB
        let row;
        if (newMachineId && newMachineId !== machineId) {
            // Mettre à jour l'ID (clé primaire) et les infos WiFi dans la DB
            row = await prisma.machine.update({
                where: { id: String(machineId) },
                data: {
                    id: String(newMachineId),
                    wifiSsid: ssid,
                    wifiPassword: password
                }
            });
            console.log(`🆔 ID de la machine mis à jour en DB de ${machineId} à ${newMachineId}`);
        } else {
            row = await MachineModel.update(machineId, {
                wifiSsid: ssid,
                wifiPassword: password
            });
        }

        return res.json({
            success: true,
            message: 'WiFi et ID configurés et publiés sur MQTT avec succès',
            machine: serializeMachine(row)
        });
    } catch (err) {
        console.error('Erreur saveConfigAndPublish:', err);
        return res.status(500).json({ error: err.message });
    }
}

async function resetDanger(req, res) {
    try {
        const { machineId } = req.params;
        const existing = await MachineModel.findById(machineId);
        if (!existing) return res.status(404).json({ error: 'Machine introuvable' });

        if (req.auth?.role === 'conception' || req.auth?.role === 'concepteur') {
            const userConcepteurId = await getUserConcepteurId(req);
            if (existing.concepteurId && String(existing.concepteurId) !== userConcepteurId) {
                return res.status(403).json({ error: 'Accès en lecture seule. Vous ne pouvez réinitialiser que vos propres machines.' });
            }
        }

        if (existing.status !== 'STOPPED_DANGER') {
            return res.status(400).json({ error: 'La machine n\'est pas en état d\'arrêt d\'urgence automatique.' });
        }

        // Marquer les incidents comme résolus
        await prisma.securityIncident.updateMany({
            where: { machineId: machineId, resolved: false },
            data: { resolved: true, resolvedBy: req.auth?.email || 'System' }
        });

        console.log(`🔓 RÉINITIALISATION DANGER machine ${machineId}`);

        const row = await MachineModel.updateStatus(machineId, 'STOPPED');
        return res.json({
            success: true,
            message: 'Sécurité réinitialisée. Vous pouvez redémarrer la machine.',
            machine: serializeMachine(row)
        });
    } catch (err) {
        console.error('Erreur resetDanger:', err);
        return res.status(500).json({ error: err.message });
    }
}

module.exports = { list, create, getById, update, stop, start, remove, saveConfigAndPublish, resetDanger };
